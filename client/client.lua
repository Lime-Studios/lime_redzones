local Zones, zoneBlips = {}, {}
local currentZoneId    = nil
local currentSafeId    = nil
-- Pending respawn request. Retried until the player is actually alive, because
-- a single fire-and-forget attempt could be lost to a dropped event, the
-- server's rate limit, or a revive that silently failed.
local reviveRequest    = nil
-- Debug output. Driven by the admin "Debug mode" option (server-synced), with
-- an optional per-client override via /rz_debug. RZ_DEBUG_LOCAL: nil = follow
-- the server option, true/false = a manual override for this client only.
local RZ_DEBUG         = false
local RZ_DEBUG_LOCAL   = nil
local RZ_DEBUG_SERVER  = false
local function resolveDebug()
    if RZ_DEBUG_LOCAL ~= nil then RZ_DEBUG = RZ_DEBUG_LOCAL else RZ_DEBUG = RZ_DEBUG_SERVER end
end
-- Debug print that ALSO mirrors to the server console (rate-limited). F8 is
-- lost when the client crashes; the server console keeps the breadcrumb trail
-- leading up to it. Global so the bridge files can use it too.
local _sdbgLast, _sdbgN = 0, 0
function RZDbg(msg)
    if not RZ_DEBUG then return end
    msg = tostring(msg)
    print('[lime_redzones] ' .. msg)
    local now = GetGameTimer()
    if now - _sdbgLast > 1000 then _sdbgLast, _sdbgN = now, 0 end
    _sdbgN = _sdbgN + 1
    if _sdbgN <= 8 then
        TriggerServerEvent('lime_redzones:server:clientDebug', msg)
    end
end
local kills, deaths, killStreak = 0, 0, 0
local recentKills = {}  -- victim ped -> last kill time (dedup repeated damage events)
local pendingPoll = {}  -- victim ped -> true while a death poll thread is live
local wasDead          = false
local downedSince      = nil
local reviveDispatchedAt = nil
local tabletOpen, tabletMode, hudMoveMode = false, nil, false
local personalColor    = nil
local hudPos           = nil
-- Options sync arrives after these are declared, but RunKillCam / SetTabletAnim
-- reference Opts before line 400 — a local declared lower reads as nil (global)
-- above its declaration, which crashed the render thread pre-sync. Hoisted.
local Opts             = {}

local function HexToRGB(hex)
    hex = hex:gsub('#', '')
    return tonumber('0x' .. hex:sub(1,2)) or 255, tonumber('0x' .. hex:sub(3,4)) or 0, tonumber('0x' .. hex:sub(5,6)) or 0
end

-- Ray-casting point-in-polygon (2D). Mirrors the server's check so the client
-- and server agree on who's inside a custom-shaped zone.
local function PointInPoly(x, y, poly)
    local inside, n = false, #poly
    local j = n
    for i = 1, n do
        local xi, yi = poly[i].x, poly[i].y
        local xj, yj = poly[j].x, poly[j].y
        if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / ((yj - yi) ~= 0 and (yj - yi) or 1e-9) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

-- True when the player is dead OR in a framework "downed/laststand" state.
-- Many ambulance jobs leave you downed at nonzero health with IsEntityDead
-- FALSE — which is why a revive sometimes never fired despite being "killed".
--
-- The real check lives in bridge/ambulance.lua (LimeIsDowned) because it needs
-- to ask the detected ambulance job directly: wasabi neither leaves the ped
-- natively dead nor sets a downed statebag, so a generic check reads a downed
-- wasabi player as alive and the death was cleared before the revive fired.
-- Keeping one implementation means the zone loop and the revive chain can't
-- disagree about whether a death happened. The fallback below only runs if the
-- bridge file failed to load.
local function isDownedOrDead(ped)
    if type(LimeIsDowned) == 'function' then return LimeIsDowned(ped) end
    if IsEntityDead(ped) then return true end
    if IsPedDeadOrDying(ped, true) then return true end
    local ok, v = pcall(function() return LocalPlayer.state.isDead end)
    if ok and v == true then return true end
    return GetEntityHealth(ped) <= 5 and IsPedRagdoll(ped)
end

-- Debounced "genuinely back up, and staying up".
--
-- A death system does not go from alive to downed in one clean step. wasabi
-- kills the ped, then resurrects it into a downed animation — so for a short
-- window mid-death the ped is natively alive AND wasabi's own isPlayerDead()
-- has not flipped true yet. Every downed signal reads false at once.
--
-- Treating that flicker as "the player got up" cancelled the queued revive
-- before its delay elapsed, which is the "revives the first time but not the
-- second" bug: it is a race, so it lands differently on each death (the kill
-- cam starting on one death and not another is enough to shift the timing).
--
-- Requiring the not-downed reading to HOLD makes the check immune to that
-- window regardless of which death system is installed, while still cancelling
-- promptly when a medic genuinely revives someone before our delay is up.
local UP_GRACE_MS = 2000
local upSince = nil
local function confirmedUp(ped)
    if isDownedOrDead(ped) then upSince = nil return false end
    upSince = upSince or GetGameTimer()
    return (GetGameTimer() - upSince) >= UP_GRACE_MS
end

-- Kill cam: spectate the killer's POV briefly after dying in a zone.
local killCamHandle = nil
local killCamActive = false
-- Bumped on every teardown so a kill-cam thread that is still winding down can
-- tell its run is over. Without it, a thread from the PREVIOUS death would run
-- its teardown against whatever handle was current — destroying the camera the
-- NEXT death had just created, and leaving that death's camera half-alive.
local killCamGen = 0

-- Every camera this resource creates, until it is destroyed. A camera is a
-- pooled game object: leaking one per death fills the pool within a handful of
-- deaths and the game hard-crashes with "Pool Full". Ownership tracking is
-- deliberately independent of killCamHandle/killCamGen — those describe which
-- camera is CURRENT, which is a different question from which ones still EXIST,
-- and conflating the two is what allowed the leak below.
-- Tagged by owner ('kill' | 'editor'). The two have completely separate
-- lifecycles — the shape editor's camera lives as long as an admin is editing
-- — so a sweep must never reach across. An untagged sweep would destroy the
-- editor camera out from under an admin who happened to die while editing.
local liveCams = {}

local function makeCam(kind)
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    if not (cam and cam ~= 0 and DoesCamExist(cam)) then return nil end
    liveCams[cam] = kind
    return cam
end

local function dropCam(cam)
    if cam == nil then return end
    if DoesCamExist(cam) then
        SetCamActive(cam, false)
        DestroyCam(cam, false)
    end
    liveCams[cam] = nil
    if killCamHandle == cam then killCamHandle = nil end
end

-- Safety net: destroy anything of `kind` we created that is somehow still
-- alive (nil = every kind, for resource stop). Cheap — the table is empty in
-- the normal case — and it makes a leak self-healing rather than terminal.
local function reapCams(kind)
    for cam, k in pairs(liveCams) do
        if kind == nil or k == kind then dropCam(cam) end
    end
end

-- Pool census, logged on every death. A "Pool Full" crash names the pool only
-- sometimes ("<<unknown pool>>" when the hash isn't in the client's table), so
-- watching the counts climb across deaths identifies the leak directly instead
-- of it having to be inferred from which death crashes.
-- ⚠ NEVER call this automatically. GetGamePool allocates a script GUID for
-- EVERY entity it returns, so one call enumerating peds + objects + vehicles +
-- pickups churns through thousands of handles on a busy map. Wiring it into
-- the death path (behind the debug flag) meant that anyone running with debug
-- ON — i.e. anyone collecting logs to diagnose a pool crash — was allocating
-- thousands of handles per death, making the very crash they were chasing
-- arrive sooner. It is manual-only, via /rz_pools.
local POOL_NAMES = { 'CPed', 'CObject', 'CVehicle', 'CPickup' }
local poolBase = nil   -- counts at the first sample, for the delta below

local function poolCounts()
    local out = {}
    for _, name in ipairs(POOL_NAMES) do
        local ok, t = pcall(GetGamePool, name)
        out[name] = (ok and type(t) == 'table') and #t or -1
    end
    local cams = 0
    for _ in pairs(liveCams) do cams = cams + 1 end
    out.ourCams = cams
    return out
end

-- Absolute counts don't reveal much on their own — GTA's own pools rise and
-- fall constantly. The DELTA since the first death is what matters: a number
-- that only ever climbs across deaths is the leak, and it names itself.
local function poolCensus()
    local now = poolCounts()
    poolBase = poolBase or now
    local parts = {}
    for _, name in ipairs(POOL_NAMES) do
        parts[#parts + 1] = ('%s=%d(%+d)'):format(name:sub(2):lower(), now[name], now[name] - poolBase[name])
    end
    parts[#parts + 1] = ('ourCams=%d'):format(now.ourCams)
    return 'pools: ' .. table.concat(parts, ' ')
end

local function destroyKillCam()
    killCamGen = killCamGen + 1
    if killCamHandle ~= nil then
        -- Drop the render override ONLY when the camera being torn down is
        -- ours. This used to run unconditionally on every teardown — including
        -- from the post-revive teleport — which also cancelled whatever camera
        -- another resource had active, an ambulance job's death cam included.
        RenderScriptCams(false, false, 0, true, true)
        dropCam(killCamHandle)
    end
    reapCams('kill')
    if killCamActive then
        killCamActive = false
        SendNUIMessage({ type = 'killCam', display = false })
    end
end

local function RunKillCam(ped)
    if type(Opts) ~= 'table' or Opts.killCamEnabled == false then return end
    if killCamActive then return end
    local killer = GetPedSourceOfDeath(ped)
    if not (killer and killer ~= 0 and killer ~= ped and DoesEntityExist(killer)) then return end
    -- Must be another PLAYER's ped. Ambulance jobs that down you without
    -- killing the ped (wasabi) leave GetPedSourceOfDeath returning a stale
    -- handle from an earlier death, so an unverified handle here would open a
    -- scripted camera — and take over RenderScriptCams — during someone else's
    -- death sequence.
    if not IsPedAPlayer(killer) then return end
    killCamActive = true
    -- Sweep anything left over from a previous run before adding another. This
    -- used to DestroyCam the old handle directly, which left it registered as
    -- live; dropCam/reapCams keep the registry honest.
    dropCam(killCamHandle)
    reapCams('kill')

    -- Resolve the killer's identity up front from the ped handle.
    local kPlayer = NetworkGetPlayerIndexFromPed(killer)
    if kPlayer == -1 then
        for _, pid in ipairs(GetActivePlayers()) do
            if GetPlayerPed(pid) == killer then kPlayer = pid break end
        end
    end
    local killerName = (kPlayer and kPlayer ~= -1) and GetPlayerName(kPlayer) or 'Unknown'
    local killerId = (kPlayer and kPlayer ~= -1) and GetPlayerServerId(kPlayer) or 0
    local camDur = math.max(1000, tonumber(Opts.killCamDuration) or 5000)
    SendNUIMessage({ type = 'killCam', display = true, killer = killerName, id = killerId, duration = camDur })
    RZDbg('killcam start (killer '..tostring(killerId)..')')

    local myGen = killCamGen
    CreateThread(function()
        -- Finite-guard: a NaN/inf coordinate fed to a camera native is an
        -- instant hard crash (not a catchable Lua error). If the killer's
        -- position can't be read cleanly we skip the camera entirely and just
        -- show the NUI banner.
        local function finite(n) return n == n and n ~= math.huge and n ~= -math.huge end
        -- This run's own camera, so finish() can always reclaim it.
        local cam = nil
        -- Teardown has two independent halves, and merging them was the leak:
        --
        --   our camera  — ALWAYS destroyed, no matter what else has happened.
        --                 Previously this was gated behind the generation
        --                 check, so if destroyKillCam() ran in the window
        --                 between capturing myGen and CreateCam below, this
        --                 thread created a camera and then refused to destroy
        --                 it. killCamHandle was overwritten by the next death,
        --                 so nothing could ever reclaim it: one camera leaked
        --                 per death until the pool was full.
        --
        --   shared state — only touched while this run is still current, so a
        --                 thread winding down can't clobber a newer kill cam.
        local function finish()
            if cam ~= nil then
                if killCamHandle == cam then RenderScriptCams(false, false, 0, true, true) end
                dropCam(cam)
                cam = nil
            end
            if myGen == killCamGen then destroyKillCam() end
        end
        local function killerCoords()
            if not DoesEntityExist(killer) then return nil end
            local c = GetEntityCoords(killer)
            if not (finite(c.x) and finite(c.y) and finite(c.z)) then return nil end
            return c
        end

        local start = killerCoords()
        if not start then
            -- No safe position — banner only, no scripted camera.
            local t0 = GetGameTimer()
            while killCamActive and myGen == killCamGen and (GetGameTimer() - t0) < camDur do Wait(100) end
            finish()
            return
        end

        -- Point the camera AT A COORDINATE, never at a raw entity handle:
        -- PointCamAtEntity on another player's ped that isn't fully networked
        -- locally can crash. PointCamAtCoord is safe with validated numbers.
        cam = makeCam('kill')
        if cam == nil then
            -- Camera pool exhausted (another resource leaking cams, or a very
            -- busy scene). Fall back to the banner instead of driving natives
            -- against an invalid handle, which is a hard crash.
            RZDbg('killcam: CreateCam failed — banner only')
            local t0 = GetGameTimer()
            while killCamActive and myGen == killCamGen and (GetGameTimer() - t0) < camDur do Wait(100) end
            finish()
            return
        end
        killCamHandle = cam
        local function place()
            -- Re-validated every frame: destroyKillCam can run from another
            -- thread (revive, respawn, resource stop) between our Wait(0) and
            -- this call, and driving a destroyed cam handle crashes the game.
            if not (killCamActive and killCamHandle == cam and DoesCamExist(cam)) then return false end
            local c = killerCoords() or start
            local rad = math.rad(GetEntityHeading(killer))
            local camX = c.x + math.sin(rad) * 2.6
            local camY = c.y - math.cos(rad) * 2.6
            local camZ = c.z + 1.2
            if finite(camX) and finite(camY) and finite(camZ) then
                SetCamCoord(cam, camX, camY, camZ)
                PointCamAtCoord(cam, c.x, c.y, c.z + 0.2)
            end
            return true
        end
        place()
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, true)
        local t = GetGameTimer()
        while killCamActive and myGen == killCamGen
              and (GetGameTimer() - t) < camDur and DoesEntityExist(killer) do
            Wait(0)
            if not place() then break end
        end
        finish()
    end)
end

local function ZoneHasPoly(z)
    return type(z.poly) == 'table' and #z.poly >= 3
end

-- True containment test for either zone shape.
local function InsideZone(z, pos)
    if ZoneHasPoly(z) then
        if z.polyMinZ and pos.z < z.polyMinZ then return false end
        if z.polyMaxZ and pos.z > z.polyMaxZ then return false end
        return PointInPoly(pos.x, pos.y, z.poly)
    end
    return #(pos - z.vec) <= z.radius
end

-- Draws the outline as vertical wall segments between consecutive points.
-- Saved shapes render as translucent walls in the zone's own colour and
-- transparency — the same look as the circular dome, not a debug outline.
-- Each wall is two triangles drawn in both winding orders so it's visible
-- from either side.
-- Wall geometry is FIXED per zone, so all vertex math is done ONCE at sync
-- (BuildZoneTris) into a flat number array; the per-frame path below just
-- feeds cached numbers to DrawPoly/DrawLine. This was a large slice of the
-- old resmon cost: per-frame table indexing + math for every wall.
function BuildZoneTris(z)
    if not (type(z.poly) == 'table' and #z.poly >= 3) then z._tris, z._lines = nil, nil return end
    local n = #z.poly
    local baseZ = z.polyMinZ or (z.vec.z - 2.0)
    local topZ  = z.polyMaxZ or (baseZ + 6.0)
    local tris, lines = {}, {}
    local ti, li = 0, 0
    for i = 1, n do
        local p1 = z.poly[i]
        local p2 = z.poly[i % n + 1]
        -- Quad = 2 triangles, each in BOTH windings (DrawPoly is single-sided).
        local quads = {
            p1.x,p1.y,baseZ, p2.x,p2.y,baseZ, p2.x,p2.y,topZ,
            p2.x,p2.y,topZ,  p2.x,p2.y,baseZ, p1.x,p1.y,baseZ,
            p1.x,p1.y,baseZ, p2.x,p2.y,topZ,  p1.x,p1.y,topZ,
            p1.x,p1.y,topZ,  p2.x,p2.y,topZ,  p1.x,p1.y,baseZ,
        }
        for k = 1, #quads do ti = ti + 1 tris[ti] = quads[k] end
        local seg = { p1.x,p1.y,baseZ, p2.x,p2.y,baseZ, p1.x,p1.y,topZ, p2.x,p2.y,topZ }
        for k = 1, #seg do li = li + 1 lines[li] = seg[k] end
    end
    z._tris, z._lines = tris, lines
end

local function DrawPolyWalls(z)
    local t = z._tris
    if not t then BuildZoneTris(z) t = z._tris if not t then return end end
    local r, g, b = z._r, z._g, z._b
    local a = math.max(20, math.min(160, z._a or 80))
    local edgeA = math.min(110, a + 30)
    local edgeA2 = math.floor(edgeA * 0.6)
    for i = 1, #t, 9 do
        DrawPoly(t[i],t[i+1],t[i+2], t[i+3],t[i+4],t[i+5], t[i+6],t[i+7],t[i+8], r, g, b, a)
    end
    local L = z._lines
    for i = 1, #L, 12 do
        DrawLine(L[i],L[i+1],L[i+2], L[i+3],L[i+4],L[i+5], r, g, b, edgeA)
        DrawLine(L[i+6],L[i+7],L[i+8], L[i+9],L[i+10],L[i+11], r, g, b, edgeA2)
    end
end

local function DrawSafeMarker(z)
    if not z then return end
    if ZoneHasPoly(z) then DrawPolyWalls(z) return end
    DrawMarker(28, z.vec.x, z.vec.y, z.vec.z, 0.0,0.0,0.0, 0.0,0.0,0.0,
        z.radius + 0.0, z.radius + 0.0, z.radius + 0.0,
        z._r, z._g, z._b, z._a, false, false, 2, false, nil, nil, false)
end

local limitedVeh = nil

-- Cheap, must run every frame while inside a safe zone.
local function ApplySafeTick(z)
    if not z then return end
    local ped = PlayerPedId()

    -- Speed limit (mph). SetVehicleMaxSpeed wants m/s; 0 restores default.
    local limit = tonumber(z.speedLimit) or 0
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and limit > 0 then
        if limitedVeh ~= veh then limitedVeh = veh end
        SetVehicleMaxSpeed(veh, limit / 2.236936)
    elseif limitedVeh and (veh == 0 or limit <= 0) then
        if DoesEntityExist(limitedVeh) then SetVehicleMaxSpeed(limitedVeh, 0.0) end
        limitedVeh = nil
    end

    -- Belt and braces on the ram: clear any damage the engine recorded this
    -- frame and keep the ped from being knocked down by a car. The victim's
    -- own client is authoritative for their health, so doing this here is what
    -- actually stops the kill.
    if z.invincible ~= false then
        ClearPedLastDamageBone(ped)
        SetEntityCanBeDamaged(ped, false)
        if veh ~= 0 then SetEntityCanBeDamaged(veh, false) end
    end

    -- Weapon handling. Three modes (weaponMode), with disableWeapons kept for
    -- backwards compatibility:
    --   'holster'  — force unarmed, block firing (the strict default)
    --   'blockfire'— let players draw/aim, but firing does nothing
    --   'off'      — no weapon restriction
    local mode = z.weaponMode
    if not mode then
        -- Legacy zones only had the on/off flag.
        mode = (z.disableWeapons == false) and 'off' or 'holster'
    end
    if mode == 'off' then return end

    -- 'blockfire' keeps the weapon out; 'holster' forces it away.
    if mode == 'holster' and GetSelectedPedWeapon(ped) ~= `WEAPON_UNARMED` then
        SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
    end

    -- Firing is blocked in BOTH holster and blockfire modes. The third arg
    -- TRUE means "disable this control".
    DisablePlayerFiring(PlayerId(), true)
    DisableControlAction(0, 24, true)  -- attack
    DisableControlAction(0, 257, true) -- attack 2
    DisableControlAction(0, 263, true) -- melee 2
    DisableControlAction(0, 264, true) -- melee 3
    DisableControlAction(0, 140, true) -- melee light
    DisableControlAction(0, 141, true) -- melee heavy
    DisableControlAction(0, 142, true) -- melee alt

    -- Holster mode additionally blocks aiming and drawing a weapon at all.
    if mode == 'holster' then
        DisableControlAction(0, 25, true)  -- aim
        DisableControlAction(0, 37, true)  -- weapon wheel
        DisableControlAction(0, 47, true)  -- G (equip)
        DisableControlAction(0, 58, true)  -- G (equip, alt)
    end
end

-- Runs on safe zone enter/exit only.
local function ApplySafeState(z)
    local ped = PlayerPedId()

    if not z then
        SetEntityInvincible(ped, false)
        SetEntityProofs(ped, false, false, false, false, false, false, false, false)
        SetEntityCanBeDamaged(ped, true)
        SetPedCanRagdollFromPlayerImpact(ped, true)
        SetPedCanBeKnockedOffVehicle(ped, 1)
        SetPlayerCanDoDriveBy(PlayerId(), true)
        local exitVeh = GetVehiclePedIsIn(ped, false)
        if exitVeh ~= 0 then SetEntityCanBeDamaged(exitVeh, true) end
        if limitedVeh and DoesEntityExist(limitedVeh) then
            SetVehicleMaxSpeed(limitedVeh, 0.0)
            SetEntityCanBeDamaged(limitedVeh, true)
        end
        limitedVeh = nil
        return
    end

    if z.invincible ~= false then
        SetEntityInvincible(ped, true)
        -- SetEntityInvincible alone does NOT stop vehicle impact damage — GTA
        -- handles that separately, which is why players could still be rammed
        -- to death. Proofs cover it: bullet, fire, explosion, collision, melee.
        SetEntityProofs(ped, true, true, true, true, true, true, true, true)
        SetPedCanBeKnockedOffVehicle(ped, 1)
    else
        SetEntityInvincible(ped, false)
        SetEntityProofs(ped, false, false, false, false, false, false, false, false)
    end

    local wmode = z.weaponMode or ((z.disableWeapons == false) and 'off' or 'holster')
    if wmode ~= 'off' then
        -- Drivebys mean firing from a vehicle — disabled in both restricted
        -- modes. Only holster mode forces the weapon away on entry.
        SetPlayerCanDoDriveBy(PlayerId(), false)
        if wmode == 'holster' then
            SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
        end
    end
    if z.phaseThrough ~= false then
        SetPedCanRagdollFromPlayerImpact(ped, false)
    end
end

-- Phasing needs re-applying as players stream in and out, but nowhere near
-- every frame — a slow tick keeps the hot loop cheap.
CreateThread(function()
    while true do
        -- Fast enough to catch a car entering at speed; near-free when idle.
        Wait(currentSafeId and 250 or 1000)
        local z = currentSafeId and Zones[currentSafeId]
        if z and z.phaseThrough ~= false then
            local ped = PlayerPedId()
            local myVeh = GetVehiclePedIsIn(ped, false)
            for _, pid in ipairs(GetActivePlayers()) do
                if pid ~= PlayerId() then
                    local other = GetPlayerPed(pid)
                    if other ~= 0 and other ~= ped and DoesEntityExist(other) then
                        -- Peds and vehicles both: a car ramming someone in the
                        -- zone must pass through, not kill them.
                        SetEntityNoCollisionEntity(ped, other, true)
                        local oVeh = GetVehiclePedIsIn(other, false)
                        if oVeh ~= 0 then
                            SetEntityNoCollisionEntity(ped, oVeh, true)
                            if myVeh ~= 0 then SetEntityNoCollisionEntity(myVeh, oVeh, true) end
                        end
                        if myVeh ~= 0 then SetEntityNoCollisionEntity(myVeh, other, true) end
                    end
                end
            end
        end
    end
end)

-- Resolves the zone at kill time, independent of the throttled state loop.
-- Redzones only: this backs kill attribution, so a safe zone must never
-- resolve here.
local function ZoneAtPlayer()
    local pos = GetEntityCoords(PlayerPedId())
    for id, z in pairs(Zones) do
        if z.enabled and z.vec and z.type ~= 'safezone' then
            if InsideZone(z, pos) then return id end
        end
    end
    return nil
end

-- Active respawn/tp/npc point placement. Declared here — above onResourceStop
-- and SetTablet — because both clear it; declared later they'd hit a global
-- while the loop reads this local, and the "stuck disabled controls" bug
-- would quietly return.
local placing = nil
local tabletProp = nil  -- attached tablet prop while the panel is open
local lastWeapNotify = 0  -- throttles the weapon-lock notification
local tabletAnimGen = 0 -- bumps on every open/close so a slow loader can tell
                        -- its request was superseded and must not spawn a prop

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    -- Cameras survive a resource restart, so anything still live here would be
    -- leaked permanently — a restart-to-fix loop is how these accumulate.
    RenderScriptCams(false, false, 0, true, true)
    reapCams()
    placing = nil
    if tabletProp and DoesEntityExist(tabletProp) then
        DetachEntity(tabletProp, true, true)
        if not NetworkHasControlOfEntity(tabletProp) then NetworkRequestControlOfEntity(tabletProp) end
        SetEntityAsMissionEntity(tabletProp, true, true)
        DeleteEntity(tabletProp)
        if DoesEntityExist(tabletProp) then DeleteObject(tabletProp) end
    end
    tabletProp = nil
    EnableAllControlActions(0)
    EnableAllControlActions(1)
    EnableAllControlActions(2)
    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
        SetEntityCanBeDamaged(ped, true)
        SetEntityInvincible(ped, false)
    end
end)

CreateThread(function()
    local rawC = GetResourceKvpString('rz_personal_color')
    if rawC then
        local ok, p = pcall(json.decode, rawC)
        if ok and p and p.hex then
            personalColor = p
            -- Old saves may lack .a — a nil alpha into DrawMarker is a hard
            -- error that kills the render thread (zone visuals vanish).
            personalColor.a = math.max(0, math.min(255, math.floor(tonumber(p.a) or 80)))
            personalColor._r, personalColor._g, personalColor._b = HexToRGB(p.hex)
        end
    end
    local rawP = GetResourceKvpString('rz_hud_pos')
    if rawP then
        local ok, p = pcall(json.decode, rawP)
        if ok and p then hudPos = p end
    end
    Wait(2000)
    TriggerServerEvent('lime_redzones:server:requestZones')
    if hudPos then SendNUIMessage({ type = 'hudPos', pos = hudPos }) end
end)

local function ClearBlips()
    for _, b in pairs(zoneBlips) do
        if DoesBlipExist(b.blip) then RemoveBlip(b.blip) end
        if b.ring and DoesBlipExist(b.ring) then RemoveBlip(b.ring) end
    end
    zoneBlips = {}
end

local function BuildBlips()
    ClearBlips()
    for id, z in pairs(Zones) do
        if z.enabled and z.showBlip ~= false then
            local c = z.coords
            local isSafe = z.type == 'safezone'
            local blip = AddBlipForCoord(c.x, c.y, c.z)
            SetBlipSprite(blip, z.blipSprite or (isSafe and 60 or 310))
            SetBlipColour(blip, z.blipColor or (isSafe and 2 or 1))
            SetBlipScale(blip, 0.9)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(z.name)
            EndTextCommandSetBlipName(blip)
            local ring = nil
            if z.showRadiusBlip ~= false then
                ring = AddBlipForRadius(c.x, c.y, c.z, z.radius + 0.0)
                SetBlipAlpha(ring, isSafe and 70 or 80)
                SetBlipColour(ring, z.blipColor or (isSafe and 2 or 1))
                SetBlipAsShortRange(ring, true)
            end
            zoneBlips[id] = { blip = blip, ring = ring }
        end
    end
end

local DynRenderDist = nil
RegisterNetEvent('lime_redzones:client:syncOptions', function(o)
    Opts = o or {}
    RZ_DEBUG_SERVER = Opts.debugMode == true
    resolveDebug()
    -- Push the admin's global theme to the UI on every options sync (incl. the
    -- initial one on join) so the HUD and tablet carry the custom accent
    -- immediately, without waiting for the tablet to be opened.
    if type(Opts.customTheme) == 'table' then
        SendNUIMessage({ type = 'tablet', customTheme = Opts.customTheme })
    end
end)

-- Global theme builder push. Update the cached option and tell the UI to
-- recolour immediately — the HUD/kill feed are always mounted, so this
-- repaints them live without needing the tablet open.
RegisterNetEvent('lime_redzones:client:syncCustomTheme', function(theme)
    if type(theme) == 'table' then
        Opts.customTheme = theme
        SendNUIMessage({ type = 'tablet', customTheme = theme, hudTheme = Opts.hudDefaultTheme or 'lime' })
    end
end)

RegisterNetEvent('lime_redzones:client:syncZones', function(zones, renderDist)
    DynRenderDist = tonumber(renderDist)
    Zones = zones or {}
    for _, z in pairs(Zones) do
        z.vec = vector3(z.coords.x, z.coords.y, z.coords.z)
        z._r, z._g, z._b = HexToRGB(z.colorHex or '#FF0000')
        z._a = z.colorA or 80
        -- Weapon lock: pre-hash the allowed names once. Unarmed is always
        -- permitted so the enforcement itself can't fight the player.
        if type(z.allowedWeapons) == 'table' and #z.allowedWeapons > 0 then
            local set = { [`WEAPON_UNARMED`] = true }
            for _, w in ipairs(z.allowedWeapons) do
                set[GetHashKey(w)] = true
            end
            z._weapSet = set
        else
            z._weapSet = nil
        end
        BuildZoneTris(z)
    end
    BuildBlips()
end)

local function NextStreakReward(zone, streak)
    local best
    for _, sr in ipairs(zone.streakRewards or {}) do
        local th = tonumber(sr.streak) or 0
        if th > streak and (not best or th < tonumber(best.streak)) then best = sr end
    end
    return best
end

local function UpdateHUD()
    if not currentZoneId then
        SendNUIMessage({ type = 'updateRedzoneUI', display = false })
        return
    end
    local z = Zones[currentZoneId]
    if not z then
        SendNUIMessage({ type = 'updateRedzoneUI', display = false })
        return
    end
    -- Per-zone: hide the on-screen kills/deaths blade while the zone still
    -- works normally (kills, rewards, revives all unaffected).
    if z.hideHud == true then
        SendNUIMessage({ type = 'updateRedzoneUI', display = false })
        return
    end
    local nr = NextStreakReward(z, killStreak)
    SendNUIMessage({
        type = 'updateRedzoneUI', display = true,
        zoneName = z.name, kills = kills, deaths = deaths, streak = killStreak,
        nextReward = nr and { streak = tonumber(nr.streak), name = nr.name, amount = tonumber(nr.amount) or 1 } or nil,
    })
end

-- Death → revive detection. Runs EVERY loop pass, independent of the render
-- branch: previously this lived inside the "near a zone / drawing" branch, so
-- if death nudged the cached distance past render range (ragdoll, death-cam,
-- a framework yank) the loop fell into the "far" branch, currentZoneId was
-- cleared, and the death — and its revive — were never registered. That was
-- the intermittent "revive doesn't work" bug.
local function CheckDeath(ped)
    local dead = isDownedOrDead(ped)
    if currentZoneId and dead and not wasDead then
        wasDead = true
        -- Arm the debounce fresh for this death. Without this it still holds a
        -- timestamp from however long the player was alive before dying, so the
        -- very first not-downed flicker would already satisfy the grace period
        -- and cancel the revive instantly.
        upSince = nil
        downedSince = GetGameTimer()
        deaths = deaths + 1
        killStreak = 0
        UpdateHUD()
        TriggerServerEvent('lime_redzones:server:reportDeath', currentZoneId)
        local z = Zones[currentZoneId]
        if z then
            local exit
            local exits = z.exits
            if type(exits) == 'table' and #exits > 0 then
                -- Placed deliberately by an admin (rooftop, interior, balcony),
                -- so the height is meant literally: exact = do not ground-snap.
                local e = exits[math.random(#exits)]
                exit = { x = e.x, y = e.y, z = e.z, exact = true }
            else
                -- Fallback ring around the zone. The Z here is the ZONE CENTRE's
                -- height applied to a point 30m+ outside it, which is simply the
                -- wrong height on any terrain that isn't flat — it can be metres
                -- underground or in mid-air. Flagged inexact so the teleport
                -- snaps it to the real ground once the map has streamed in.
                local away = (z.teleportAway or 30.0) + z.radius
                local ang = math.random() * 6.28318
                exit = { x = z.coords.x + math.cos(ang) * away, y = z.coords.y + math.sin(ang) * away,
                         z = z.coords.z, exact = false }
            end
            reviveRequest = { zone = currentZoneId, exit = exit, at = GetGameTimer() + (z.reviveDelay or 8000) }
            if type(LimeReviveLockedOut) == 'function' and LimeReviveLockedOut() then
                reviveRequest = nil
                RZDbg('death registered but revive suppressed (loop lockout)')
            else
                RZDbg('death detected in zone '..tostring(currentZoneId)..' — revive queued (delay '..tostring(z.reviveDelay or 8000)..'ms) | '
                    .. (type(LimeDownedWhy) == 'function' and LimeDownedWhy() or ''))
            end
        end
        RunKillCam(ped)
    elseif wasDead then
        -- Reset ONLY once the player is CONFIRMED up — see confirmedUp(). A
        -- single not-downed frame is not enough: it cancelled the queued revive
        -- mid-death, which is exactly the "revives the first time, not the
        -- second" bug. Resetting too eagerly is also what used to re-arm this
        -- check every pass, firing a fresh kill cam + reportDeath each time and
        -- flooding the camera pool.
        if confirmedUp(ped) then
            wasDead = false
            -- Full teardown, not just the flag. Clearing the flag alone left
            -- our scripted camera rendering for up to a frame while the
            -- ambulance job was restoring its own camera on revive — two
            -- resources driving RenderScriptCams against each other.
            destroyKillCam()
            reviveRequest = nil
            reviveDispatchedAt = nil
            downedSince = nil
            RZDbg('death state cleared — ready for next death | '
                .. (type(LimeDownedWhy) == 'function' and LimeDownedWhy() or ''))
        end
    end
end

-- Tablet-in-hand animation while the panel is open. Optional (Options tab),
-- skipped when dead or in a vehicle where the pose looks broken.
--
-- All stock GTA dictionaries — nothing custom is streamed. Tried in order, so
-- if the first fails to stream (busy scene, slow disk) the pose still plays
-- instead of the player standing empty-handed holding a floating tablet.
-- These are all upper-body idles, so they read correctly on any ped and the
-- player can still walk around.
local TABLET_ANIMS = {
    { dict = Config.TabletAnimDict or 'amb@code_human_in_bus_passenger_idles@female@tablet@base',
      name = Config.TabletAnimName or 'base' },
    { dict = 'amb@world_human_tourist_map@male@base',      name = 'base' },
    { dict = 'amb@world_human_seat_wall_tablet@female@base', name = 'base' },
}
-- AF_LOOPING(1) + AF_UPPERBODY(16) + AF_SECONDARY(32).
-- The old value was 50 = AF_HOLD_LAST_FRAME(2) + 16 + 32, with no LOOPING bit.
-- A -1 duration with no loop flag plays the idle ONCE and freezes on its last
-- frame, which is why the pose looked dead the moment it settled.
local TABLET_ANIM_FLAGS = 49

local tabletAnim = nil   -- the entry from TABLET_ANIMS that actually loaded

local function loadAnimDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    -- BOUNDED. This was `while not HasAnimDictLoaded(d) do Wait(0) end` — an
    -- unbounded spin, so a dictionary that never streamed hung the thread at
    -- Wait(0) forever and the prop was never attached.
    local tries = 0
    while not HasAnimDictLoaded(dict) and tries < 100 do
        Wait(10)
        tries = tries + 1
    end
    return HasAnimDictLoaded(dict)
end

local function resolveTabletAnim()
    if tabletAnim and HasAnimDictLoaded(tabletAnim.dict) then return tabletAnim end
    for _, a in ipairs(TABLET_ANIMS) do
        if loadAnimDict(a.dict) then tabletAnim = a return a end
    end
    return nil
end

local function playTabletAnim(ped)
    local a = tabletAnim
    if not a then return end
    if not IsEntityPlayingAnim(ped, a.dict, a.name, 3) then
        TaskPlayAnim(ped, a.dict, a.name, 3.0, 3.0, -1, TABLET_ANIM_FLAGS, 0, false, false, false)
    end
end

local function stopTabletAnim(ped)
    local a = tabletAnim
    if a then StopAnimTask(ped, a.dict, a.name, 2.0) end
    ClearPedSecondaryTask(ped)
end

local function clearTabletProp()
    if tabletProp and DoesEntityExist(tabletProp) then
        DetachEntity(tabletProp, true, true)
        -- Networked objects won't delete unless we own them and they're flagged
        -- as a mission entity — otherwise the handle lingers and the object pool
        -- fills up over repeated opens ("Pool Full, Size == 256").
        if not NetworkHasControlOfEntity(tabletProp) then
            NetworkRequestControlOfEntity(tabletProp)
        end
        SetEntityAsMissionEntity(tabletProp, true, true)
        DeleteEntity(tabletProp)
        if DoesEntityExist(tabletProp) then DeleteObject(tabletProp) end
    end
    tabletProp = nil
end

local function SetTabletAnim(on)
    local ped = PlayerPedId()
    tabletAnimGen = tabletAnimGen + 1
    local myGen = tabletAnimGen
    if on then
        if Opts.tabletAnim == false then return end
        if IsEntityDead(ped) or IsPedInAnyVehicle(ped, true) then return end
        CreateThread(function()
            resolveTabletAnim()

            -- Default GTA tablet (prop_cs_tablet). Stock model, always available
            -- on every client, so nothing custom is streamed and there's no ytd/
            -- ytyp to load or leak.
            local wantName = Config.TabletProp or 'prop_cs_tablet'
            local model = GetHashKey(wantName)
            RequestModel(model)

            local tries = 0
            while not HasModelLoaded(model) and tries < 100 do
                Wait(10)
                tries = tries + 1
                if myGen ~= tabletAnimGen then
                    SetModelAsNoLongerNeeded(model)
                    return
                end
            end
            if myGen ~= tabletAnimGen or not tabletOpen or not HasModelLoaded(model) then
                SetModelAsNoLongerNeeded(model)
                return
            end

            ped = PlayerPedId()
            playTabletAnim(ped)

            -- Ensure no orphan prop survives before making a new one, and the
            -- generation guard below means at most one exists per client.
            clearTabletProp()
            local boneCoords = GetPedBoneCoords(ped, 28422, 0.0, 0.0, 0.0)
            -- Local object (not networked): it's a cosmetic stock prop only you
            -- need to see, so it never touches the networked entity pool. Stock
            -- GTA props don't suffer the OneSync culling that made the custom
            -- streamed model vanish, so local is both safe and pool-free here.
            tabletProp = CreateObject(model, boneCoords.x, boneCoords.y, boneCoords.z, false, false, false)

            local waitExist = 0
            while not DoesEntityExist(tabletProp) and waitExist < 50 do Wait(0); waitExist = waitExist + 1 end
            if not DoesEntityExist(tabletProp) then tabletProp = nil; SetModelAsNoLongerNeeded(model); return end

            SetEntityCollision(tabletProp, false, false)
            SetEntityVisible(tabletProp, true, false)
            SetEntityAlpha(tabletProp, 255, false)
            ResetEntityAlpha(tabletProp)

            local bone = GetPedBoneIndex(ped, 28422) -- SKEL_R_Hand
            -- Stock GTA tablet offsets (the default prop_cs_tablet).
            local offX, offY, offZ = 0.0, -0.03, 0.0
            local rotX, rotY, rotZ = 20.0, -90.0, 0.0
            AttachEntityToEntity(tabletProp, ped, bone,
                offX, offY, offZ, rotX, rotY, rotZ,
                true, false, false, false, 2, true)
            SetModelAsNoLongerNeeded(model)

            -- Closed during the load/attach window: tear back down.
            if myGen ~= tabletAnimGen or not tabletOpen then
                stopTabletAnim(ped)
                clearTabletProp()
                return
            end

            -- Keep-alive. The animation was played once and never checked
            -- again, so anything that cleared the ped's tasks — walking,
            -- sprinting, taking a hit, another resource calling
            -- ClearPedTasks — ended the pose for good while the tablet stayed
            -- glued to a limp hand for the rest of the session. Re-applies the
            -- pose and re-attaches the prop whenever either has dropped, and
            -- exits the moment this open is superseded.
            while tabletOpen and myGen == tabletAnimGen do
                Wait(500)
                if not (tabletOpen and myGen == tabletAnimGen) then break end
                local p = PlayerPedId()
                if IsEntityDead(p) or IsPedInAnyVehicle(p, true) then
                    -- Pose looks broken here; drop it and pick back up on exit.
                    stopTabletAnim(p)
                else
                    playTabletAnim(p)
                    -- A respawn swaps the ped, which silently detaches the prop.
                    if tabletProp and DoesEntityExist(tabletProp)
                       and not IsEntityAttachedToEntity(tabletProp, p) then
                        AttachEntityToEntity(tabletProp, p, GetPedBoneIndex(p, 28422),
                            offX, offY, offZ, rotX, rotY, rotZ,
                            true, false, false, false, 2, true)
                    end
                end
            end
        end)
    else
        stopTabletAnim(ped)
        clearTabletProp()
        -- Release the streaming request. RequestAnimDict was called on every
        -- open with no matching release, so the dict stayed pinned in memory
        -- for the whole session.
        if tabletAnim then RemoveAnimDict(tabletAnim.dict) end
    end
end

local function SetTablet(open, mode, tab, payload)
    tabletOpen, tabletMode = open, open and mode or nil
    SetTabletAnim(open)
    if open and placing then
        placing = nil
        SendNUIMessage({ type = 'placementBar', display = false })
    end
    local function kvpJson(key)
        local r = GetResourceKvpString(key)
        if r then local ok, v = pcall(json.decode, r) if ok then return v end end
        return nil
    end
    SendNUIMessage({
        type = 'tablet', display = open, mode = mode, tab = tab,
        -- Players need zones too (Teleport tab). Admin payloads carry the full
        -- server-side records; everyone else gets the already-synced client copy.
        zones = (payload and payload.zones) or Zones,
        gangs = payload and payload.gangs,
        settings = payload and payload.settings,
        perms = payload and payload.perms,
        personalColor = personalColor,
        options = Opts,
        hudTheme = GetResourceKvpString('rz_hud_theme') or (Opts.hudDefaultTheme or 'lime'),
        customTheme = Opts.customTheme,
        hudPreset = GetResourceKvpString('rz_hud_preset') or (Opts.hudDefaultPreset or 'top'),
        hudScale = tonumber(GetResourceKvpFloat('rz_hud_scale')) or 1.0,
        tabletScale = tonumber(GetResourceKvpFloat('rz_tablet_scale')) or 1.0,
        killfeedPos = kvpJson('rz_kf_pos'),
        killfeedScale = tonumber(GetResourceKvpFloat('rz_kf_scale')) or 1.0,
        killfeedTheme = GetResourceKvpString('rz_kf_theme') or 'inherit',
        killmsgPos = kvpJson('rz_km_pos'),
        killmsgScale = tonumber(GetResourceKvpFloat('rz_km_scale')) or 1.0,
        killmsgTheme = GetResourceKvpString('rz_km_theme') or 'inherit',
        firstTime = GetResourceKvpString('rz_seen_tutorial') ~= 'v3',
    })
    if not hudMoveMode then
        if open then
            CreateThread(function()
                Wait(0)
                SetNuiFocus(true, true)
            end)
        else
            SetNuiFocus(false, false)
        end
    end
end

local function SetHudMove(on)
    hudMoveMode = on
    SendNUIMessage({ type = 'hudMove', enabled = on })
    SetNuiFocus(on, on)
    if on then Notify('Drag the HUD, then click Done.', 'info') end
end

RegisterNetEvent('lime_redzones:client:notify', function(m, t, d) Notify(m, t, d) end)

RegisterNetEvent('lime_redzones:client:logs', function(category, entries, total, page)
    SendNUIMessage({ type = 'logs', category = category, entries = entries, total = total, page = page })
end)
RegisterNetEvent('lime_redzones:client:logConfig', function(cfg)
    SendNUIMessage({ type = 'logConfig', config = cfg })
end)
RegisterNetEvent('lime_redzones:client:prizeHistory', function(history)
    SendNUIMessage({ type = 'prizeHistory', history = history })
end)
RegisterNetEvent('lime_redzones:client:stats', function(stats)
    SendNUIMessage({ type = 'stats', stats = stats })
end)

RegisterNetEvent('lime_redzones:client:myStats', function(k, d)
    kills, deaths = tonumber(k) or 0, tonumber(d) or 0
    UpdateHUD()
end)

RegisterNetEvent('lime_redzones:client:killFeed', function(entry)
    -- Highlight your own kills in the feed.
    entry.mine = tonumber(entry.killerId) == GetPlayerServerId(PlayerId())
    if type(entry) ~= 'table' then return end
    SendNUIMessage({ type = 'killFeed', entry = entry })

    -- Big on-screen kill message only for the player who got the kill.
    if Opts.killMessageEnabled ~= false and entry.killerId and entry.killerId == GetPlayerServerId(PlayerId()) then
        SendNUIMessage({
            type = 'killMessage',
            victim = entry.victim or 'Enemy',
            weapon = entry.weapon or 'Weapon',
            streak = entry.streak or 0,
        })
    end
end)

RegisterNetEvent('lime_redzones:client:updateLeaderboard', function(players, gangs, globalP, totals)
    SendNUIMessage({ type = 'lbData', players = players, gangs = gangs, globalPlayers = globalP, totals = totals })
end)

RegisterNetEvent('lime_redzones:client:syncStreak', function(s)
    killStreak = s or 0
    UpdateHUD()
end)

RegisterNetEvent('lime_redzones:client:openAdmin', function(z, g, st)
    SetTablet(true, 'admin', 'zones', { zones = z, gangs = g, settings = st })
end)
RegisterNetEvent('lime_redzones:client:myIdentifier', function(lic, id)
    SendNUIMessage({ type = 'myIdentifier', license = lic, identifier = id })
end)

-- Drives pending respawn requests. Cheap: does nothing at all unless a request
-- is actually outstanding. Polled at 200ms so a zone's configured revive delay
-- is honoured closely — at 500ms a 3s delay could land at 3.5s, which reads as
-- the revive being slow when it was just the poll interval.
CreateThread(function()
    while true do
        Wait(200)
        local r = reviveRequest
        if r then
            local ped = PlayerPedId()
            -- Confirmed up (see confirmedUp) — clear all death state. This has
            -- to be the debounced check, not a raw one: the not-downed flicker
            -- during a death system's own sequence would otherwise delete the
            -- pending request here too, before it ever got a chance to fire.
            -- It must also never be a bare native-alive check — laststand
            -- leaves the ped natively alive while still down, and resetting on
            -- that re-armed CheckDeath every pass, firing a fresh kill cam each
            -- time until the camera pool overflowed ("Pool Full, Size == 256").
            if confirmedUp(ped) then
                reviveRequest = nil
                wasDead = false
                destroyKillCam()
            -- Retry only while actually down. During the grace window the
            -- player reads as up but isn't confirmed yet — retrying there would
            -- fire a second revive at someone who has just been revived.
            elseif isDownedOrDead(ped) and GetGameTimer() >= r.at then
                -- Lockout: the bridge detected our revive fighting an unknown
                -- death system (revive → re-down loop). Stop requesting — the
                -- player uses the server's own respawn flow until it clears.
                if type(LimeReviveLockedOut) == 'function' and LimeReviveLockedOut() then
                    reviveRequest = nil
                    RZDbg('revive request dropped (loop lockout active)')
                -- Don't restart the revive chain if one is already running from
                -- a previous attempt — re-firing attemptRevive re-triggers the
                -- whole server→client revive path (extra threads + resurrects),
                -- which is what accumulated across a slow revive and crashed the
                -- game on the third death. Push the next check out and wait.
                elseif type(LimeReviveInProgress) == 'function' and LimeReviveInProgress() then
                    r.at = GetGameTimer() + 2000
                else
                    -- Retry cadence: wider than the server's 3s limiter so a
                    -- retry can't be swallowed, but not so wide the player waits
                    -- ages between attempts.
                    r.at = GetGameTimer() + 4000
                    r.tries = (r.tries or 0) + 1
                    if r.tries > 6 then
                        reviveRequest = nil
                        reviveDispatchedAt = reviveDispatchedAt or GetGameTimer()
                        Notify(_U('revive_failed'), 'error')
                    else
                        reviveDispatchedAt = reviveDispatchedAt or GetGameTimer()
                        RZDbg('attemptRevive sent (try '..tostring(r.tries)..') zone '..tostring(r.zone))
                        TriggerServerEvent('lime_redzones:server:attemptRevive', r.zone, r.exit, 0.0)
                    end
                end
            end
        end
    end
end)

-- Server refused (zone disabled, no funds, revive-inside off). Stop retrying;
-- the player will use the normal respawn flow instead.
RegisterNetEvent('lime_redzones:client:reviveDenied', function()
    reviveRequest = nil
end)

RegisterNetEvent('lime_redzones:client:teleportTo', function(coords, name, exact)
    if not coords then return end
    RZDbg('teleportTo received')
    local ped = PlayerPedId()
    SetTablet(false)
    -- End any active kill cam before we fade + teleport, so its render thread
    -- can't keep a scripted camera alive across the revive.
    destroyKillCam()

    CreateThread(function()
        DoScreenFadeOut(400)
        -- Bounded: if another resource cancels the fade (a death screen doing
        -- its own transition is the usual culprit) this waited forever and the
        -- player was left frozen mid-teleport with no way out.
        local fadeWait = 0
        while not IsScreenFadedOut() and fadeWait < 2000 do Wait(10) fadeWait = fadeWait + 10 end

        local veh = GetVehiclePedIsIn(ped, false)
        local ent = (veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped) and veh or ped

        -- SetEntityCoords rather than the NoOffset variant: the engine applies
        -- its own placement correction instead of forcing the ped to a literal
        -- coordinate that may be inside geometry.
        SetEntityCoords(ent, coords.x, coords.y, coords.z, false, false, false, false)

        -- Collision requested ONCE, then polled. Re-issuing the request on
        -- every 10ms iteration queued up to 100 streaming requests per
        -- teleport; in an MLO-dense area that queue cannot drain, and a few
        -- teleports exhausted the streamer and hard-crashed the client.
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        local waited = 0
        while not HasCollisionLoadedAroundEntity(ent) and waited < 3000 do
            Wait(50)
            waited = waited + 50
        end

        -- Only snap to ground when using the zone centre as a fallback. A
        -- configured spawn point was placed deliberately (rooftop, interior,
        -- balcony), so snapping it down would move it off the intended spot.
        if not exact then
            local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 10.0, false)
            if found then SetEntityCoords(ent, coords.x, coords.y, groundZ, false, false, false, false) end
        end

        if coords.h then SetEntityHeading(ent, coords.h + 0.0) end
        FreezeEntityPosition(ent, false)

        DoScreenFadeIn(600)
        Notify(_U('teleport_arrived', name or 'the redzone'), 'success')
    end)
end)

RegisterNetEvent('lime_redzones:client:adminData', function(z, g, st, perms)
    if tabletOpen and tabletMode == 'admin' then
        SendNUIMessage({ type = 'adminData', zones = z, gangs = g, settings = st, perms = perms })
    end
end)

local function OpenPlayerTablet(tab)
    if tabletOpen then SetTablet(false)
    else
        TriggerServerEvent('lime_redzones:server:requestLeaderboard')
        SetTablet(true, 'player', tab or 'leaderboard')
    end
end

RegisterCommand('leaderboard', function() OpenPlayerTablet('leaderboard') end, false)
RegisterCommand('rz', function() OpenPlayerTablet('leaderboard') end, false)

RegisterCommand('rz_admin', function()
    if tabletOpen and tabletMode == 'admin' then SetTablet(false)
    else TriggerServerEvent('lime_redzones:server:adminOpen') end
end, false)

RegisterCommand('rz_color', function() OpenPlayerTablet('color') end, false)
RegisterCommand('rz_hud', function() SetHudMove(not hudMoveMode) end, false)

-- Keybinds. RegisterKeyMapping must run at startup and can't be changed live,
-- so we read the admin-configured defaults (server option) with a short wait
-- for the first sync, then fall back to Config. Which key a player actually
-- uses is theirs to rebind in GTA Settings once registered; these only set the
-- default and whether the bind exists at all. Changes apply next restart.
CreateThread(function()
    -- Give syncOptions a moment to land so panel-set keys win over Config.
    local waited = 0
    while (type(Opts) ~= 'table' or Opts.keybinds == nil) and waited < 3000 do
        Wait(100); waited = waited + 100
    end
    local kb = (type(Opts) == 'table' and Opts.keybinds) or {}
    local function bind(cmd, label, cfgEnabled, cfgKey, optName)
        local o = kb[optName]
        local enabled = (o ~= nil) and (o.enabled == true) or (o == nil and cfgEnabled ~= false)
        local key = (o and o.key) or cfgKey or 'F1'
        if enabled then
            RegisterKeyMapping(cmd, label, 'keyboard', key)
        end
    end
    bind('leaderboard', 'Toggle Redzone Leaderboard', Config.LeaderboardKeybindEnabled, Config.LeaderboardKey, 'leaderboard')
    bind('rz_admin',    'Open Redzone Admin Panel',    Config.AdminKeybindEnabled,       Config.AdminKey,       'admin')
    bind('rz_hud',      'Move Redzone HUD',            Config.HudMoveKeybindEnabled,     Config.HudMoveKey,     'hudMove')
end)

-- Forward NUI data straight to a server event.
local function forward(name, event, arg)
    RegisterNUICallback(name, function(d, cb)
        TriggerServerEvent(event, arg and arg(d) or nil)
        cb({})
    end)
end

RegisterNUICallback('closeTablet', function(_, cb)
    SetTablet(false)
    TriggerServerEvent('lime_redzones:server:adminClosed')
    cb({})
end)
RegisterNUICallback('tutorialSeen', function(_, cb)
    SetResourceKvp('rz_seen_tutorial', 'v3')
    cb({})
end)
RegisterNUICallback('forceClose', function(_, cb)
    -- ESC safety-net close. This bypassed SetTablet, so the tablet animation
    -- and prop were left running — only the UI's X (which routes through
    -- SetTablet) cleaned them up. Do the same teardown here.
    tabletOpen, hudMoveMode = false, false
    SetTabletAnim(false)
    if placing then placing = nil; SendNUIMessage({ type = 'placementBar', display = false }) end
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'tablet', display = false })
    TriggerServerEvent('lime_redzones:server:adminClosed')
    cb({})
end)
RegisterNUICallback('openAdminPanel', function(_, cb)
    TriggerServerEvent('lime_redzones:server:adminOpen')
    cb({})
end)
RegisterNUICallback('openPlayerTablet', function(_, cb)
    TriggerServerEvent('lime_redzones:server:requestLeaderboard')
    SetTablet(true, 'player', 'rzleaderboard')
    cb({})
end)

forward('addAdminId', 'lime_redzones:server:addAdmin', function(d) return tostring(d.identifier or '') end)
forward('removeAdminId', 'lime_redzones:server:removeAdmin', function(d) return tostring(d.identifier or '') end)
forward('getMyIdentifier', 'lime_redzones:server:myIdentifier')

RegisterNUICallback('toggleZone', function(d, cb) TriggerServerEvent('lime_redzones:server:toggleZone', d.id, d.enabled) cb({}) end)
forward('saveRanks', 'lime_redzones:server:saveRanks', function(d) return d.ranks end)
RegisterNUICallback('saveTabletScale', function(d, cb)
    local sc = tonumber(d.scale) or 1.0
    if sc < 0.7 then sc = 0.7 elseif sc > 1.5 then sc = 1.5 end
    SetResourceKvpFloat('rz_tablet_scale', sc)
    cb({})
end)

RegisterNUICallback('saveHudTheme', function(d, cb)
    if d.theme then SetResourceKvp('rz_hud_theme', tostring(d.theme)) end
    if d.preset then SetResourceKvp('rz_hud_preset', tostring(d.preset)) end
    if d.scale then SetResourceKvpFloat('rz_hud_scale', tonumber(d.scale) or 1.0) end
    SendNUIMessage({ type = 'hudStyle', theme = d.theme, preset = d.preset, scale = d.scale })
    Notify('HUD style saved.', 'success')
    cb({})
end)

RegisterNUICallback('saveKillfeedStyle', function(d, cb)
    if d.scale then SetResourceKvpFloat('rz_kf_scale', tonumber(d.scale) or 1.0) end
    if d.theme then SetResourceKvp('rz_kf_theme', tostring(d.theme)) end
    SendNUIMessage({ type = 'kfStyle', scale = d.scale, theme = d.theme })
    Notify('Kill feed style saved.', 'success')
    cb({})
end)

forward('requestLogs', 'lime_redzones:server:requestLogs', function(d) return d end)
forward('wipeLogs', 'lime_redzones:server:wipeLogs', function(d) return d end)
forward('requestLogConfig', 'lime_redzones:server:requestLogConfig')
forward('postLeaderboardNow', 'lime_redzones:server:postLeaderboardNow', function(d) return d.board or 'redzone' end)
forward('requestPrizeHistory', 'lime_redzones:server:requestPrizeHistory')
forward('requestStats', 'lime_redzones:server:requestStats')
forward('wipePrizeHistory', 'lime_redzones:server:wipePrizeHistory')
forward('deletePrizeEntry', 'lime_redzones:server:deletePrizeEntry', function(d) return d end)
forward('saveLogConfig', 'lime_redzones:server:saveLogConfig', function(d) return d end)
RegisterNUICallback('saveKillMsgStyle', function(d, cb)
    if d.scale then SetResourceKvpFloat('rz_km_scale', tonumber(d.scale) or 1.0) end
    if d.theme then SetResourceKvp('rz_km_theme', tostring(d.theme)) end
    SendNUIMessage({ type = 'kmStyle', scale = d.scale, theme = d.theme })
    Notify('Kill message style saved.', 'success')
    cb({})
end)

RegisterNUICallback('startKmMove', function(_, cb)
    SetTablet(false)
    SendNUIMessage({ type = 'kmMove', enabled = true })
    SetNuiFocus(true, true)
    Notify('Drag the kill message, then click Done.', 'info')
    cb({})
end)

RegisterNUICallback('saveKillMsgPos', function(d, cb)
    if d.x and d.y then SetResourceKvp('rz_km_pos', json.encode({ x = d.x, y = d.y })) end
    SendNUIMessage({ type = 'kmMove', enabled = false })
    SetNuiFocus(false, false)
    Notify('Kill message position saved.', 'success')
    cb({})
end)

RegisterNUICallback('resetKmPos', function(_, cb)
    DeleteResourceKvp('rz_km_pos')
    SendNUIMessage({ type = 'kmReset' })
    Notify('Kill message position reset.', 'success')
    cb({})
end)
RegisterNUICallback('saveKillfeedPos', function(d, cb)
    if d.x and d.y then SetResourceKvp('rz_kf_pos', json.encode({ x = d.x, y = d.y })) end
    SendNUIMessage({ type = 'kfMove', enabled = false })
    SetNuiFocus(false, false)
    Notify('Kill feed position saved.', 'success')
    cb({})
end)
RegisterNUICallback('startKfMove', function(_, cb)
    SetTablet(false)
    SendNUIMessage({ type = 'kfMove', enabled = true })
    SetNuiFocus(true, true)
    Notify('Drag the kill feed, then release.', 'info')
    cb({})
end)
RegisterNUICallback('resetKfPos', function(_, cb)
    DeleteResourceKvp('rz_kf_pos')
    SendNUIMessage({ type = 'kfReset' })
    Notify('Kill feed position reset.', 'success')
    cb({})
end)

RegisterNUICallback('startHudMove', function(_, cb)
    SetTablet(false)
    SetHudMove(true)
    cb({})
end)
RegisterNUICallback('resetHudPos', function(_, cb)
    hudPos = nil
    DeleteResourceKvp('rz_hud_pos')
    SendNUIMessage({ type = 'hudPos', pos = nil })
    Notify('HUD position reset.', 'success')
    cb({})
end)
RegisterNUICallback('saveOptions', function(d, cb)
    TriggerServerEvent('lime_redzones:server:saveOptions', d) cb({})
end)
RegisterNUICallback('saveCustomTheme', function(d, cb)
    TriggerServerEvent('lime_redzones:server:saveCustomTheme', d) cb({})
end)

RegisterNUICallback('saveHudPos', function(d, cb)
    if type(d.x) == 'number' and type(d.y) == 'number' then
        hudPos = { x = d.x, y = d.y }
        SetResourceKvp('rz_hud_pos', json.encode(hudPos))
        SendNUIMessage({ type = 'hudPos', pos = hudPos })
        Notify('HUD position saved. Use /rz_hud_reset to restore default.', 'success')
    end
    SetHudMove(false)
    cb({})
end)

RegisterCommand('rz_hud_reset', function()
    hudPos = nil
    DeleteResourceKvp('rz_hud_pos')
    SendNUIMessage({ type = 'hudPos', pos = nil })
    Notify('HUD position reset to default.', 'success')
end, false)

RegisterNUICallback('savePersonalColor', function(d, cb)
    if d.reset then
        personalColor = nil
        DeleteResourceKvp('rz_personal_color')
        Notify('Personal zone colour reset.', 'success')
    elseif type(d.hex) == 'string' and d.hex:match('^#%x%x%x%x%x%x$') then
        personalColor = { hex = d.hex, a = math.max(0, math.min(255, math.floor(tonumber(d.a) or 80))) }
        personalColor._r, personalColor._g, personalColor._b = HexToRGB(d.hex)
        SetResourceKvp('rz_personal_color', json.encode(personalColor))
        Notify('Personal zone colour saved.', 'success')
    end
    SendNUIMessage({ type = 'tablet', personalColor = personalColor })
    cb({})
end)

RegisterNUICallback('saveZone', function(d, cb) TriggerServerEvent('lime_redzones:server:saveZone', d) cb({}) end)
RegisterNUICallback('deleteZone', function(d, cb) TriggerServerEvent('lime_redzones:server:deleteZone', d.id) cb({}) end)
RegisterNUICallback('saveGang', function(d, cb) TriggerServerEvent('lime_redzones:server:saveGang', d) cb({}) end)
RegisterNUICallback('deleteGang', function(d, cb) TriggerServerEvent('lime_redzones:server:deleteGang', d.name) cb({}) end)
RegisterNUICallback('saveResetSettings', function(d, cb)
    TriggerServerEvent('lime_redzones:server:saveResetSettings', d.which, d.cfg) cb({})
end)
RegisterNUICallback('resetLeaderboard', function(d, cb)
    TriggerServerEvent('lime_redzones:server:resetLeaderboard', d.which) cb({})
end)
RegisterNUICallback('getMyPosition', function(_, cb)
    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    cb({
        x = math.floor(p.x * 100) / 100,
        y = math.floor(p.y * 100) / 100,
        z = math.floor(p.z * 100) / 100,
        h = math.floor(GetEntityHeading(ped) * 10) / 10,
    })
end)
RegisterNUICallback('adminTeleportToZone', function(d, cb)
    TriggerServerEvent('lime_redzones:server:adminTeleportToZone', d.id)
    cb({})
end)

RegisterNUICallback('requestAdminData', function(_, cb)
    TriggerServerEvent('lime_redzones:server:requestAdminData')
    cb({})
end)

RegisterNUICallback('bulkUpdateZones', function(d, cb)
    TriggerServerEvent('lime_redzones:server:bulkUpdateZones', d.ids, d.patch)
    cb({})
end)

RegisterNUICallback('teleportToZone', function(d, cb)
    -- This used to teleport the player directly on the client — free, instant,
    -- and with no permission or cost check at all. The paid/validated flow
    -- already existed server-side (cost, allowTeleport, position handling)
    -- but nothing ever called it. Route through it properly now.
    TriggerServerEvent('lime_redzones:server:teleportToZone', d.id)
    cb({})
end)


-- ── Zone shape creator (freecam) ────────────────────────────────
-- Quasar-style: fly a free camera, place corners at the crosshair, adjust the
-- top/bottom height live, with a filled wall preview and an NUI control bar.

local function updatePlacementBar(mode, count, max, minZ, maxZ, speed)
    SendNUIMessage({ type = 'placementBar', display = true, mode = mode,
        count = count, max = max, minZ = minZ or 0, maxZ = maxZ or 0, speed = speed or 1 })
end

local function hidePlacementBar()
    SendNUIMessage({ type = 'placementBar', display = false })
end

-- Filled translucent wall between two corners, visible from both sides.
local function DrawWallQuad(a, b, zLo, zHi, r, g, bl, al)
    -- Both triangles, both windings — see DrawPolyWalls. Matches the saved-zone
    -- render so the editor preview looks like the final zone.
    DrawPoly(a.x, a.y, zLo, b.x, b.y, zLo, b.x, b.y, zHi, r, g, bl, al)
    DrawPoly(b.x, b.y, zHi, b.x, b.y, zLo, a.x, a.y, zLo, r, g, bl, al)
    DrawPoly(a.x, a.y, zLo, b.x, b.y, zHi, a.x, a.y, zHi, r, g, bl, al)
    DrawPoly(a.x, a.y, zHi, b.x, b.y, zHi, a.x, a.y, zLo, r, g, bl, al)
end

local function RunPolyFreecam(draft)
    local ped = PlayerPedId()
    local start = GetEntityCoords(ped)
    local points = draft.poly or {}
    local minZ = tonumber(draft.polyMinZ) or (start.z - 2.0)
    local maxZ = tonumber(draft.polyMaxZ) or (start.z + 8.0)
    if maxZ <= minZ then maxZ = minZ + 4.0 end
    local speed = 1.0

    local lastHit = nil
    local rayHandle = nil   -- one async shape test in flight at a time
    -- Editing an existing shape: start the camera above its centroid, not at
    -- the player — otherwise editing a zone drawn across the map opens the
    -- freecam staring at nothing.
    local camPos
    if #points >= 1 then
        local cx, cy = 0.0, 0.0
        for i = 1, #points do cx = cx + points[i].x; cy = cy + points[i].y end
        cx, cy = cx / #points, cy / #points
        camPos = vector3(cx, cy, maxZ + 22.0)
    else
        camPos = vector3(start.x, start.y, start.z + 18.0)
    end
    local rotX, rotZ = -35.0, GetEntityHeading(ped)
    -- Registered as live so it is reclaimable from outside this function. The
    -- editor runs under pcall, and on error the handler at the call site could
    -- only reset RenderScriptCams — `cam` is a local, so the camera itself was
    -- unreachable and leaked on every shape-editor error.
    local cam = makeCam('editor')
    if cam == nil then
        -- Camera pool is full. Bail with a clear message instead of driving
        -- natives against a nil handle for the whole editing session.
        Notify('Cannot open the shape editor — the game camera pool is full. Rejoin and try again.', 'error')
        hidePlacementBar()
        return
    end
    SetCamCoord(cam, camPos.x, camPos.y, camPos.z)
    SetCamRot(cam, rotX, 0.0, rotZ, 2)
    RenderScriptCams(true, true, 400, true, true)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)

    local barTick = 0
    updatePlacementBar('poly', #points, 24, minZ, maxZ, speed)

    while true do
        Wait(0)
        -- Group 0 alone leaves the frontend (group 2) live, which let
        -- ESC/Backspace close the menu mid-placement. Disabling a control
        -- still lets IsDisabledControl* read it, so our own binds keep working.
        --
        -- SetPlayerControl(false) must NOT be used here: it halts input
        -- processing entirely, so the freecam couldn't fly or place points.
        DisableAllControlActions(0)
        DisableAllControlActions(1)
        DisableAllControlActions(2)
        -- Optional niceties. Guarded because a missing/renamed native throws,
        -- which would kill this thread and abandon the camera mid-edit.
        if SetPauseMenuActive then pcall(SetPauseMenuActive, false) end
        if HudWeaponWheelIgnoreSelection then pcall(HudWeaponWheelIgnoreSelection) end
        HideHudAndRadarThisFrame()

        -- Mouse look
        rotZ = rotZ - GetDisabledControlNormal(0, 1) * 6.0
        rotX = math.max(-89.0, math.min(89.0, rotX - GetDisabledControlNormal(0, 2) * 5.0))
        local radZ, radX = math.rad(rotZ), math.rad(rotX)
        local fwd = vector3(-math.sin(radZ) * math.cos(radX), math.cos(radZ) * math.cos(radX), math.sin(radX))
        local right = vector3(math.cos(radZ), math.sin(radZ), 0.0)

        -- Fly: WASD, Q down, E up; scroll adjusts speed
        local mv = speed * (IsDisabledControlPressed(0, 21) and 2.5 or 1.0) -- shift boost
        if IsDisabledControlPressed(0, 32) then camPos = camPos + fwd * mv end        -- W
        if IsDisabledControlPressed(0, 33) then camPos = camPos - fwd * mv end        -- S
        if IsDisabledControlPressed(0, 34) then camPos = camPos - right * mv end      -- A
        if IsDisabledControlPressed(0, 35) then camPos = camPos + right * mv end      -- D
        if IsDisabledControlPressed(0, 44) then camPos = camPos - vector3(0,0,mv) end   -- Q down
        if IsDisabledControlPressed(0, 38) then camPos = camPos + vector3(0,0,mv) end   -- E up
        if IsDisabledControlPressed(0, 22) then camPos = camPos + vector3(0,0,mv) end   -- Space up (alt)
        if IsDisabledControlJustPressed(0, 241) then speed = math.min(6.0, speed + 0.3) end
        if IsDisabledControlJustPressed(0, 242) then speed = math.max(0.2, speed - 0.3) end

        SetCamCoord(cam, camPos.x, camPos.y, camPos.z)
        SetCamRot(cam, rotX, 0.0, rotZ, 2)

        -- Height bounds: X/Z move the top; Shift+X / Shift+Z move the bottom.
        local shift = IsDisabledControlPressed(0, 21)
        -- Height bounds: X or ↑ raises, Z or ↓ lowers (Shift = bottom edge).
        -- The control bar advertised the arrow keys but only X/Z were wired —
        -- both pairs work now.
        if IsDisabledControlJustPressed(0, 73) or IsDisabledControlJustPressed(0, 172) then      -- X / Up
            if shift then minZ = math.min(maxZ - 1.0, minZ + 1.0) else maxZ = maxZ + 1.0 end
        end
        if IsDisabledControlJustPressed(0, 20) or IsDisabledControlJustPressed(0, 173) then      -- Z / Down
            if shift then minZ = minZ - 1.0 else maxZ = math.max(minZ + 1.0, maxZ - 1.0) end
        end

        -- Crosshair raycast to world. Flag 1 = world geometry, 16 = water.
        -- GetShapeTestResult returns a BOOLEAN for `hit` in CFX Lua (not 1/0),
        -- and the result often isn't ready on the frame the ray is started —
        -- both of which meant `cursor` was always nil and no point could be
        -- placed. Keep the previous frame's hit so the cursor stays steady.
        --
        -- LEAK: this used to start a brand new ray EVERY frame and read it
        -- once. An async shape test only releases its slot once its result is
        -- actually collected (status 2 = ready, 0 = invalid); status 1 means
        -- still pending, and a pending test that is never read again holds its
        -- slot forever. At 60fps that abandoned one slot per frame, so a few
        -- seconds in the shape editor exhausted the shape-test pool and the
        -- game hard-crashed with a pool-full error. Now: one test in flight,
        -- and a new one only starts after the previous has resolved.
        if rayHandle == nil then
            local target = camPos + fwd * 2000.0
            rayHandle = StartShapeTestRay(camPos.x, camPos.y, camPos.z,
                target.x, target.y, target.z, 1 + 16, 0, 7)
        else
            local status, hit, hitPos = GetShapeTestResult(rayHandle)
            if status ~= 1 then          -- 1 = still pending, keep waiting
                rayHandle = nil
                if hit and hit ~= 0 and hitPos then
                    lastHit = vector3(hitPos.x, hitPos.y, hitPos.z)
                end
            end
        end
        local cursor = lastHit

        -- Fallback: if the ray never resolves (some map/streaming setups don't
        -- return a hit against distant geometry), project onto the zone's
        -- ground plane so a point can always be placed rather than the tool
        -- appearing dead.
        if not cursor then
            local denom = fwd.z
            if denom < -0.05 then
                local t = (camPos.z - minZ) / -denom
                if t > 0 and t < 3000.0 then
                    cursor = vector3(camPos.x + fwd.x * t, camPos.y + fwd.y * t, minZ)
                end
            end
        end

        -- Preview: walls, corner posts, edge lines, cursor marker
        local n = #points
        for i = 1, n do
            local a = points[i]
            local b = points[i % n + 1]
            if n > 1 then
                DrawWallQuad(a, b, minZ, maxZ, 163, 230, 53, 55)
                DrawLine(a.x, a.y, minZ, b.x, b.y, minZ, 163, 230, 53, 220)
                DrawLine(a.x, a.y, maxZ, b.x, b.y, maxZ, 163, 230, 53, 160)
            end
            DrawLine(a.x, a.y, minZ, a.x, a.y, maxZ, 163, 230, 53, 130)
            DrawMarker(28, a.x, a.y, minZ + 0.4, 0.0,0.0,0.0, 0.0,0.0,0.0,
                0.5, 0.5, 0.5, 163, 230, 53, 200, false, false, 2, false, nil, nil, false)
        end
        if cursor then
            DrawMarker(28, cursor.x, cursor.y, cursor.z + 0.25, 0.0,0.0,0.0, 0.0,0.0,0.0,
                0.4, 0.4, 0.4, 255, 255, 255, 180, false, false, 2, false, nil, nil, false)
            -- Preview edge from the last placed corner to the cursor
            if n > 0 then
                local last = points[n]
                DrawLine(last.x, last.y, minZ, cursor.x, cursor.y, cursor.z, 255, 255, 255, 120)
            end
        end

        -- Add / undo / done / cancel.
        -- 237/238 are the raw mouse buttons (INPUT_CURSOR_ACCEPT/CANCEL) rather
        -- than 24/25 (attack/aim) — those are hooked by other scripts and were
        -- firing their actions through even while disabled.
        if IsDisabledControlJustPressed(0, 237) and cursor and n < 24 then
            points[n + 1] = { x = math.floor(cursor.x * 100) / 100, y = math.floor(cursor.y * 100) / 100, z = math.floor(cursor.z * 100) / 100 }
            PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
        end
        if IsDisabledControlJustPressed(0, 238) and n > 0 then
            table.remove(points)
            PlaySoundFrontend(-1, 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
        end
        -- Enter only (191). 18 is INPUT_FRONTEND_ACCEPT and doubles as the
        -- menu-accept, which closed the tablet the moment a point was placed.
        if IsDisabledControlJustPressed(0, 191) then
            draft.poly = #points >= 3 and points or {}
            draft.polyMinZ = #points >= 3 and minZ or nil
            draft.polyMaxZ = #points >= 3 and maxZ or nil
            break
        end
        -- Backspace only (177 is FRONTEND_CANCEL / ESC — same problem as above).
        if IsDisabledControlJustPressed(0, 194) then
            break -- draft untouched: cancel keeps whatever shape it had before
        end

        barTick = barTick + 1
        if barTick >= 15 then
            barTick = 0
            updatePlacementBar('poly', #points, 24, minZ, maxZ, speed)
            if RZ_DEBUG then
                print(('[lime_redzones] freecam pts=%d cursor=%s cam=%.1f,%.1f,%.1f')
                    :format(#points, cursor and 'yes' or 'NO', camPos.x, camPos.y, camPos.z))
            end
        end
    end

    RenderScriptCams(false, true, 400, true, true)
    dropCam(cam)
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    EnableAllControlActions(0)
    EnableAllControlActions(1)
    EnableAllControlActions(2)
    hidePlacementBar()
end

local function BeginPointPlacement(mode, draft, maxPoints, onFinish, onError)
    maxPoints = maxPoints or 5
    local existing
    if mode == 'tp' then existing = draft.tpPoints
    elseif mode == 'npc' then existing = draft.teleportNpcs
    else existing = draft.exits end
    existing = existing or {}
    placing = { draft = draft, points = existing, mode = mode, max = maxPoints }

    CreateThread(function()
        local ok, err = pcall(function()
            updatePlacementBar(mode, #placing.points, maxPoints)
            local barTick = 0
            while placing do
                Wait(0)
                local ped = PlayerPedId()
                local pos = GetEntityCoords(ped)

                -- Movement stays free (you walk to each point), but the keys we've
                -- bound must not also fire their game action: E enters vehicles,
                -- G is a weapon control, X is duck.
                DisableControlAction(0, 38, true)   -- E
                DisableControlAction(0, 47, true)   -- G
                DisableControlAction(0, 73, true)   -- X
                DisableControlAction(0, 23, true)   -- F (enter vehicle alt)
                DisableControlAction(0, 75, true)   -- exit vehicle
                DisableControlAction(0, 24, true)   -- attack
                DisableControlAction(0, 25, true)   -- aim
                DisableControlAction(0, 37, true)   -- weapon wheel
                DisableControlAction(0, 194, true)  -- backspace (our cancel)

                for _, p in ipairs(placing.points) do
                    DrawMarker(1, p.x, p.y, (p.z or pos.z) - 0.95, 0.0,0.0,0.0, 0.0,0.0,0.0,
                        1.2, 1.2, 0.6, 163, 230, 53, 160, false, false, 2, false, nil, nil, false)
                end

                if IsDisabledControlJustReleased(0, 73) and #placing.points > 0 then -- X undo
                    table.remove(placing.points)
                    PlaySoundFrontend(-1, 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                end

                if IsDisabledControlJustReleased(0, 38) and #placing.points < placing.max then -- E place
                    placing.points[#placing.points+1] = {
                        x = math.floor(pos.x * 100) / 100,
                        y = math.floor(pos.y * 100) / 100,
                        z = math.floor(pos.z * 100) / 100,
                        h = math.floor(GetEntityHeading(ped) * 10) / 10,
                        model = (placing.mode == 'npc')
                                and (Config.TeleportNpcModels and Config.TeleportNpcModels[#placing.points+1])
                                or nil,
                    }
                    PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                end

                if IsDisabledControlJustPressed(0, 194) then -- Backspace: cancel
                    placing = nil
                    hidePlacementBar()
                    -- Draft untouched. Each caller decides where cancel lands:
                    -- the tablet flow reopens the editor, the /rz_addteleportnpc
                    -- flow just exits placement.
                    if onError then onError() end
                end

                if placing and IsDisabledControlJustReleased(0, 47) then -- G finish
                    local finalDraft = placing.draft
                    if placing.mode == 'tp' then finalDraft.tpPoints = placing.points
                    elseif placing.mode == 'npc' then finalDraft.teleportNpcs = placing.points
                    else finalDraft.exits = placing.points end
                    placing = nil
                    hidePlacementBar()
                    if onFinish then onFinish(finalDraft) end
                end

                barTick = barTick + 1
                if barTick >= 20 and placing then
                    barTick = 0
                    updatePlacementBar(placing.mode, #placing.points, maxPoints)
                end
            end
        end)

        if not ok then
            -- Same failure mode as the shape editor: without this, an error mid-loop
            -- killed the thread with `placing` still set, silently leaving attack/aim
            -- disabled for this admin with no UI and no way out except relogging.
            print('[lime_redzones] ^1point placement ERROR:^0 ' .. tostring(err))
            placing = nil
            hidePlacementBar()
            Notify('Placement editor error — check server console (F8).', 'error')
            if onError then onError() end
        end
    end)
end

RegisterNUICallback('startPlacement', function(d, cb)
    local mode = (d.mode == 'tp' and 'tp') or (d.mode == 'poly' and 'poly') or (d.mode == 'npc' and 'npc') or 'exit'
    print(('[lime_redzones] startPlacement received: mode=%s draft=%s')
        :format(tostring(d.mode), d.draft and 'yes' or 'NIL'))
    SetTablet(false)
    cb({})

    -- Zone shape: full freecam experience in its own flow.
    if mode == 'poly' then
        CreateThread(function()
            local draft = d.draft or {}
            print(('[lime_redzones] shape editor: opening (existing corners=%d)')
                :format(type(draft.poly) == 'table' and #draft.poly or 0))

            local ok, err = pcall(RunPolyFreecam, draft)
            if not ok then
                -- Without this, any native error killed the thread silently and
                -- the camera/draft were simply abandoned — looking exactly like
                -- "nothing happened".
                print('[lime_redzones] ^1shape editor ERROR:^0 ' .. tostring(err))
                RenderScriptCams(false, false, 0, true, true)
                reapCams('editor')   -- unreachable from here otherwise
                local ped = PlayerPedId()
                FreezeEntityPosition(ped, false)
                SetEntityVisible(ped, true, false)
                EnableAllControlActions(0)
                EnableAllControlActions(1)
                EnableAllControlActions(2)
                hidePlacementBar()
                Notify('Shape editor error — check server console (F8).', 'error')
            end

            print(('[lime_redzones] shape editor: closed with %d corner(s)')
                :format(type(draft.poly) == 'table' and #draft.poly or 0))
            SetTablet(true, 'admin', 'zones')
            SendNUIMessage({ type = 'placementDone', draft = draft })
        end)
        return
    end

    -- Respawn / teleport points / teleport-NPC points: on-foot with the NUI
    -- control bar (the GTA help-text UI is gone).
    local maxPoints = (mode == 'npc') and 4 or 5
    local draft = d.draft or {}
    BeginPointPlacement(mode, draft, maxPoints, function(finalDraft)
        SetTablet(true, 'admin', 'zones')
        SendNUIMessage({ type = 'placementDone', draft = finalDraft })
    end, function()
        SetTablet(true, 'admin', 'zones')
        -- Cancelled: restore the untouched draft so edits aren't lost.
        SendNUIMessage({ type = 'placementDone', draft = draft })
    end)
end)

-- The tablet UI doesn't have a button for teleport-NPC placement yet, so
-- /rz_addteleportnpc drives the same placement flow directly from a command.
RegisterNetEvent('lime_redzones:client:beginNpcPlacement', function(zone)
    Notify(('Placing teleport NPCs for "%s" — E to place (max 4), X to undo, G to finish.')
        :format(zone.name or tostring(zone.id)), 'info')
    BeginPointPlacement('npc', zone, 4, function(finalDraft)
        TriggerServerEvent('lime_redzones:server:saveZone', finalDraft)
        Notify('Teleport NPC positions saved.', 'success')
    end)
end)

RegisterCommand('rz_addteleportnpc', function(_, args)
    local zoneId = args[1]
    if not zoneId then
        Notify('Usage: /rz_addteleportnpc <zoneId> — zone IDs are shown in the admin tablet\'s Zones tab.', 'error')
        return
    end
    TriggerServerEvent('lime_redzones:server:beginNpcPlacement', zoneId)
end, false)

-- ── Teleport NPCs ────────────────────────────────────────────────
-- Physical peds placed per-zone (via /rz_addteleportnpc, up to 4) that offer
-- a "Teleport to Redzone" interaction instead of requiring the tablet.
-- Interacting fires the exact same paid/validated server event the tablet
-- button uses, so cost and allowTeleport are enforced identically here.

local spawnedNpcs = {}  -- zoneId -> array of ped handles
local npcGen       = {} -- zoneId -> generation counter, guards against a
                         -- despawn racing an in-flight model load respawning
                         -- a ped into a generation that's already gone.
local npcTargetLib = nil

CreateThread(function()
    if GetResourceState('ox_target') == 'started' then npcTargetLib = 'ox'
    elseif GetResourceState('qb-target') == 'started' then npcTargetLib = 'qb'
    elseif GetResourceState('qtarget') == 'started' then npcTargetLib = 'qtarget'
    end
end)

local function AddNpcTarget(ped, zoneId, zoneName)
    local label = ('Teleport to %s'):format(zoneName or 'Redzone')
    if npcTargetLib == 'ox' then
        pcall(function()
            exports.ox_target:addLocalEntity(ped, {
                { name = 'rz_tp_' .. tostring(zoneId) .. '_' .. tostring(ped),
                  icon = 'fas fa-street-view', label = label,
                  onSelect = function() TriggerServerEvent('lime_redzones:server:teleportToZone', zoneId) end },
            })
        end)
    elseif npcTargetLib then
        local res = npcTargetLib == 'qb' and 'qb-target' or 'qtarget'
        pcall(function()
            exports[res]:AddTargetEntity(ped, {
                options = { { type = 'client', icon = 'fas fa-street-view', label = label,
                    action = function() TriggerServerEvent('lime_redzones:server:teleportToZone', zoneId) end } },
                distance = 2.5,
            })
        end)
    end
    -- No target resource installed: the native E-key prompt thread below handles it.
end

local function SpawnZoneNpcs(zoneId, zone)
    if spawnedNpcs[zoneId] then return end
    local gen = (npcGen[zoneId] or 0) + 1
    npcGen[zoneId] = gen
    local handles = {}
    spawnedNpcs[zoneId] = handles

    for i, npc in ipairs(zone.teleportNpcs) do
        if i <= 4 then
            CreateThread(function()
                local model = (type(npc.model) == 'string' and npc.model ~= '') and npc.model
                              or (Config.TeleportNpcModels and Config.TeleportNpcModels[i]) or 'a_m_y_business_01'
                local hash = GetHashKey(model)
                RequestModel(hash)
                local tries = 0
                while not HasModelLoaded(hash) and tries < 100 do Wait(10) tries = tries + 1 end

                -- Bail if this zone's NPCs were despawned (or respawned into a
                -- new generation) while the model was still loading.
                if spawnedNpcs[zoneId] ~= handles or npcGen[zoneId] ~= gen or not HasModelLoaded(hash) then
                    SetModelAsNoLongerNeeded(hash)
                    return
                end

                local ped = CreatePed(4, hash, npc.x, npc.y, (npc.z or 0.0) - 1.0, npc.h or 0.0, false, true)
                SetEntityAsMissionEntity(ped, true, true)
                FreezeEntityPosition(ped, true)
                SetEntityInvincible(ped, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedCanRagdoll(ped, false)
                SetPedDiesWhenInjured(ped, false)
                SetPedCanBeTargetted(ped, false)
                SetPedCanPlayAmbientAnims(ped, true)
                TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
                SetModelAsNoLongerNeeded(hash)

                if spawnedNpcs[zoneId] == handles and npcGen[zoneId] == gen then
                    handles[#handles+1] = ped
                    AddNpcTarget(ped, zoneId, zone.name)
                else
                    DeleteEntity(ped)
                end
            end)
        end
    end
end

local function DespawnZoneNpcs(zoneId)
    local handles = spawnedNpcs[zoneId]
    if not handles then return end
    spawnedNpcs[zoneId] = nil
    npcGen[zoneId] = (npcGen[zoneId] or 0) + 1
    for _, ped in ipairs(handles) do
        -- Target entries are removed unconditionally, before the existence
        -- check: only ox was being cleaned up, so qb-target/qtarget kept an
        -- entry per ped for every spawn/despawn cycle as players moved in and
        -- out of range — an unbounded table plus stale entries on recycled
        -- ped handles.
        if npcTargetLib == 'ox' then
            pcall(function() exports.ox_target:removeLocalEntity(ped) end)
        elseif npcTargetLib == 'qb' then
            pcall(function() exports['qb-target']:RemoveTargetEntity(ped) end)
        elseif npcTargetLib == 'qtarget' then
            pcall(function() exports.qtarget:RemoveTargetEntity(ped) end)
        end
        if DoesEntityExist(ped) then
            SetEntityAsMissionEntity(ped, true, true)
            DeleteEntity(ped)
            if DoesEntityExist(ped) then DeletePed(ped) end
        end
    end
end

CreateThread(function()
    while true do
        Wait(1000)
        local pos = GetEntityCoords(PlayerPedId())
        for zoneId, z in pairs(Zones) do
            local hasNpcs = z.type ~= 'safezone' and z.enabled ~= false and z.allowTeleport == true
                            and type(z.teleportNpcs) == 'table' and #z.teleportNpcs > 0
            if hasNpcs then
                local d = #(pos - vector3(z.coords.x, z.coords.y, z.coords.z))
                -- Hysteresis: spawn at the inner edge, despawn 40m beyond it.
                -- With a single threshold, standing near the boundary spawned
                -- and despawned four peds every second — and a revive drops you
                -- exactly there, since exit points sit just outside the zone.
                -- Each cycle is 4x RequestModel + CreatePed + mission-entity
                -- registration, which is how the entity pools filled up.
                local base = (z.radius or 60.0) + 100.0
                if spawnedNpcs[zoneId] then
                    if d > base + 40.0 then DespawnZoneNpcs(zoneId) end
                elseif d <= base then
                    SpawnZoneNpcs(zoneId, z)
                end
            elseif spawnedNpcs[zoneId] then
                DespawnZoneNpcs(zoneId) -- zone deleted, disabled, or teleport/NPCs turned off
            end
        end
    end
end)

-- Native fallback when no target resource is installed: closest NPC within
-- 2m gets a help-text prompt, E teleports.
CreateThread(function()
    while true do
        if npcTargetLib then
            Wait(2500) -- target resource owns the interaction; just idle-poll for it going away
            goto continue
        end

        local pos = GetEntityCoords(PlayerPedId())
        local closestPed, closestZone, closestD = nil, nil, 2.0
        for zoneId, handles in pairs(spawnedNpcs) do
            for _, npcPed in ipairs(handles) do
                if DoesEntityExist(npcPed) then
                    local dd = #(pos - GetEntityCoords(npcPed))
                    if dd < closestD then closestD = dd closestPed = npcPed closestZone = zoneId end
                end
            end
        end

        if closestPed then
            local z = Zones[closestZone]
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(('Press ~INPUT_CONTEXT~ to teleport to %s'):format(z and z.name or 'Redzone'))
            EndTextCommandDisplayHelp(0, false, false, -1)
            if IsControlJustReleased(0, 38) then -- E
                TriggerServerEvent('lime_redzones:server:teleportToZone', closestZone)
            end
            Wait(0)
        else
            Wait(500)
        end
        ::continue::
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for zoneId in pairs(spawnedNpcs) do DespawnZoneNpcs(zoneId) end
end)

CreateThread(function()
    local frame = 0
    -- Nearest-zone selection is cached: zones don't move, so re-ranking every
    -- one of them per frame was pure waste (the bulk of the old 0.04-0.06ms).
    -- The full scan runs at most every 250ms; between scans only the two
    -- cached distances are refreshed.
    local nearest, nearestId, nDist = nil, nil, math.huge
    local safeZone, safeZoneId, safeDist = nil, nil, math.huge
    local nextScan = 0
    -- One pass of the zone loop. Runs under pcall: an error in here used to
    -- kill the whole thread silently — zone bubbles and detection just
    -- disappeared until a resource restart (typically right after a death,
    -- since the death path is the least-travelled code).
    local function ZonePass()
        local renderDist = DynRenderDist or 120.0
        if not next(Zones) then Wait(2500) return end

        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)

        -- Death/revive is checked here, every pass, before any branch decides
        -- how much to draw or how long to sleep — so it can never be skipped by
        -- falling into the far-away branch after a death displaces the player.
        CheckDeath(ped)

        local now = GetGameTimer()
        if now >= nextScan then
            nextScan = now + 250
            nearest, nearestId, nDist = nil, nil, math.huge
            safeZone, safeZoneId, safeDist = nil, nil, math.huge
            -- Track the nearest of each type separately: a safe zone can sit
            -- inside a redzone, and both need to apply independently.
            for id, z in pairs(Zones) do
                if z.enabled then
                    local d = #(pos - z.vec)
                    if z.type == 'safezone' then
                        if d < safeDist then safeZone, safeZoneId, safeDist = z, id, d end
                    else
                        if d < nDist then nearest, nearestId, nDist = z, id, d end
                    end
                end
            end
        else
            if nearest then nDist = #(pos - nearest.vec) end
            if safeZone then safeDist = #(pos - safeZone.vec) end
        end

        -- Safe zone state (independent of redzone proximity).
        local inSafe = safeZone and InsideZone(safeZone, pos)
        if inSafe and currentSafeId ~= safeZoneId then
            currentSafeId = safeZoneId
            TriggerServerEvent('lime_redzones:server:syncSafePresence', currentSafeId)
            ApplySafeState(safeZone)
            if safeZone.hideHud ~= true then
                SendNUIMessage({ type = 'safezone', display = true, name = safeZone.name, speedLimit = tonumber(safeZone.speedLimit) or 0 })
            end
            Notify(_U('entered_safezone', safeZone.name), 'success')

            -- Optional: remove the car on entry (default off — greenzones are
            -- usually where players park). Same eject-then-delete as redzones.
            if safeZone.deleteVehicleOnEntry == true then
                local ped2 = PlayerPedId()
                local veh = GetVehiclePedIsIn(ped2, false)
                if veh ~= 0 and DoesEntityExist(veh) then
                    TaskLeaveVehicle(ped2, veh, 16)
                    SetTimeout(700, function()
                        if DoesEntityExist(veh) then
                            SetEntityAsMissionEntity(veh, true, true)
                            DeleteEntity(veh)
                        end
                    end)
                    Notify(_U('no_vehicles'), 'info')
                end
            end
        elseif not inSafe and currentSafeId then
            local leftName = Zones[currentSafeId] and Zones[currentSafeId].name or 'safe zone'
            currentSafeId = nil
            TriggerServerEvent('lime_redzones:server:syncSafePresence', nil)
            ApplySafeState(nil)
            SendNUIMessage({ type = 'safezone', display = false })
            Notify(_U('left_safezone', leftName), 'info')
        end

        if not nearest or nDist > (nearest.radius + renderDist) then
            -- Keep the zone association while dead with a pending revive — the
            -- death displaced us out of range, but we're still "in" the zone
            -- until the revive resolves. Dropping it here blanks the HUD and
            -- can race the revive.
            if currentZoneId and not (wasDead and reviveRequest) then
                currentZoneId = nil
                UpdateHUD()
            end
            -- Per-frame work is only needed while actually drawing the safe
            -- zone visual or enforcing its rules from inside. A hidden visual
            -- (showMarker off) costs a slow tick, not a render loop.
            local safeVisible = safeZone and safeDist <= (safeZone.radius + renderDist) and safeZone.showMarker ~= false
            if safeVisible then
                DrawSafeMarker(safeZone)
                if currentSafeId then ApplySafeTick(Zones[currentSafeId]) end
                Wait(0)
            elseif currentSafeId then
                -- Inside a safe zone with the visual hidden: rules still apply
                -- every frame (weapon block is a per-frame disable).
                ApplySafeTick(Zones[currentSafeId])
                Wait(0)
            else
                -- Never sleep long while the player is still flagged inside a
                -- zone — a death needs to be caught within a frame or two.
                Wait(currentZoneId and 0 or (nDist > (nearest and nearest.radius or 0) + renderDist + 200.0 and 2000 or 1000))
            end
        else
            -- "Show zone visual" off = skip all drawing; the zone still works
            -- (entry, kills, revives) on a slow tick instead of a render loop.
            local showVisual = nearest.showMarker ~= false
            if showVisual then
                local mr, mg, mb, ma = nearest._r, nearest._g, nearest._b, nearest._a
                if personalColor then
                    mr, mg, mb = personalColor._r or mr, personalColor._g or mg, personalColor._b or mb
                    ma = personalColor.a
                end
                if ZoneHasPoly(nearest) then
                    -- Personal colour still applies; walls read the cached values.
                    local pr, pg, pb = nearest._r, nearest._g, nearest._b
                    nearest._r, nearest._g, nearest._b = mr, mg, mb
                    DrawPolyWalls(nearest)
                    nearest._r, nearest._g, nearest._b = pr, pg, pb
                else
                    DrawMarker(28, nearest.vec.x, nearest.vec.y, nearest.vec.z,
                        0.0,0.0,0.0, 0.0,0.0,0.0,
                        nearest.radius + 0.0, nearest.radius + 0.0, nearest.radius + 0.0,
                        mr, mg, mb, ma, false, false, 2, false, nil, nil, false)
                end
            end

            -- With the visual hidden the loop sleeps ~300ms per pass, so the
            -- 30-frame cadence would take 9s to fire; run the checks every
            -- pass instead.
            -- Death/downed is checked EVERY pass (cheap), independent of the
            -- 30-frame cadence used for the heavier inside/entry logic — a
            -- delayed death check meant the revive could be skipped entirely.
            frame = frame + (showVisual and 1 or 30)
            if frame >= 30 then
                frame = 0
                local inside = InsideZone(nearest, pos)

                if inside and currentZoneId ~= nearestId then
                    currentZoneId = nearestId
                    TriggerServerEvent('lime_redzones:server:requestMyStats')
                    UpdateHUD()

                    if nearest.deleteVehicleOnEntry ~= false then
                        local veh = GetVehiclePedIsIn(ped, false)
                        if veh ~= 0 and DoesEntityExist(veh) then
                            TaskLeaveVehicle(ped, veh, 16)
                            SetTimeout(700, function()
                                if DoesEntityExist(veh) then
                                    SetEntityAsMissionEntity(veh, true, true)
                                    DeleteEntity(veh)
                                end
                            end)
                            Notify(_U('no_vehicles'), 'info')
                        end
                    end
                elseif not inside and currentZoneId then
                    currentZoneId = nil
                    UpdateHUD()
                end

                if inside and nearest.infiniteStamina then
                    RestorePlayerStamina(PlayerId(), 1.0)
                end

                -- Weapon lock: only whitelisted weapons usable inside. Checked
                -- on the same cadence as the other inside logic — swapping to a
                -- banned gun gets holstered within half a second.
                if inside and nearest._weapSet then
                    local cur = GetSelectedPedWeapon(PlayerPedId())
                    if not nearest._weapSet[cur] then
                        SetCurrentPedWeapon(PlayerPedId(), `WEAPON_UNARMED`, true)
                        if (GetGameTimer() - (lastWeapNotify or 0)) > 8000 then
                            lastWeapNotify = GetGameTimer()
                            Notify(_U('weapon_locked'), 'error')
                        end
                    end
                end
            end

            -- Per-zone rule: no shooting from outside the zone, so players
            -- A safe zone may sit inside/near this redzone — keep it drawn and
            -- its rules enforced while we're handling the redzone.
            local safeVisible2 = safeZone and safeDist <= (safeZone.radius + renderDist) and safeZone.showMarker ~= false
            if safeVisible2 then DrawSafeMarker(safeZone) end
            if currentSafeId then ApplySafeTick(Zones[currentSafeId]) end

            -- Only stay per-frame while something needs it: a visible visual,
            -- an active shooting block, or safe-zone rules. Otherwise ~300ms.
            if showVisual or safeVisible2 or currentSafeId then
                Wait(0)
            else
                Wait(300)
            end
        end
    end

    while true do
        local ok, err = pcall(ZonePass)
        if not ok then
            print('[lime_redzones] ERROR in zone loop (recovered): ' .. tostring(err))
            pcall(TriggerServerEvent, 'lime_redzones:server:clientDebug', 'ZONE LOOP ERROR: ' .. tostring(err))
            Wait(1000)
        end
    end
end)

CreateThread(function()
    local wasDeadGlobal = false
    while true do
        Wait(1500)
        local _t = GetGameTimer()
        for ped, ts in pairs(recentKills) do
            if _t - ts > 5000 then recentKills[ped] = nil end
        end
        -- Skip entirely if global leaderboard is disabled.
        if Opts.globalLbEnabled == false then
            wasDeadGlobal = false
        else
            local dead = IsEntityDead(PlayerPedId())
            if dead and not wasDeadGlobal then
                wasDeadGlobal = true
                if not currentZoneId then
                    TriggerServerEvent('lime_redzones:server:globalDeath')
                end
            elseif not dead and wasDeadGlobal then
                wasDeadGlobal = false
            end
        end
    end
end)


local function dbg(...)
    if RZ_DEBUG then print('[lime_redzones]', ...) end
end

-- Pool readout on demand. Run it before your first death and after each one:
-- whichever number climbs and never comes back down is the leak. "ours" counts
-- only entities THIS resource created and still owns, so it separates a leak
-- here from one in another resource.
RegisterCommand('rz_pools', function()
    local mine = 0
    for _, handles in pairs(spawnedNpcs) do
        for _, p in ipairs(handles) do
            if DoesEntityExist(p) then mine = mine + 1 end
        end
    end
    local cams = 0
    for _ in pairs(liveCams) do cams = cams + 1 end
    local line = ('%s | ourNpcs=%d ourCams=%d tabletProp=%s')
        :format(poolCensus(), mine, cams, tostring(tabletProp ~= nil))
    print('[lime_redzones] ' .. line)
    Notify(line, 'info', 12000)
end, false)

RegisterCommand('rz_debug', function()
    -- Per-client override toggle. Flips relative to whatever's currently
    -- effective (server option or a prior override).
    RZ_DEBUG_LOCAL = not RZ_DEBUG
    resolveDebug()
    Notify('Redzone debug ' .. (RZ_DEBUG and 'ON' or 'OFF') .. ' (local override). Check F8 console.', 'info')
    print('[lime_redzones] debug = ' .. tostring(RZ_DEBUG) .. ' (override) | server option = ' .. tostring(RZ_DEBUG_SERVER) .. ' | currentZoneId = ' .. tostring(currentZoneId))
end, false)

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end

    local victim   = args[1]
    local attacker = args[2]
    local weapon   = args[5]
    local isFatal  = args[6]

    if not victim or not attacker then return end
    if attacker ~= PlayerPedId() then return end
    if not IsEntityAPed(victim) then return end
    if victim == attacker then return end

    dbg(('damage event: victim=%s isPlayer=%s fatal=%s zone=%s'):format(
        victim, tostring(IsPedAPlayer(victim)), tostring(isFatal), tostring(currentZoneId)))

    -- Resolve the victim's server id now, while the ped handle is fresh — by the
    -- time a delayed (health-poll) kill confirms, some ambulance jobs have already
    -- swapped/reset the ped, which would make this resolve to nothing.
    --
    -- NetworkGetPlayerIndexFromPed returns -1 for peds that aren't fully
    -- networked to us yet, which is the usual reason the feed said "Enemy".
    -- Fall back to matching the ped against the active player list, then to
    -- nearest-player-by-position.
    local function resolveVictimId(vped)
        local idx = NetworkGetPlayerIndexFromPed(vped)
        if idx and idx ~= -1 then return GetPlayerServerId(idx) end

        for _, pid in ipairs(GetActivePlayers()) do
            if GetPlayerPed(pid) == vped then return GetPlayerServerId(pid) end
        end

        if DoesEntityExist(vped) then
            local vpos, best, bestD = GetEntityCoords(vped), nil, 2.0
            for _, pid in ipairs(GetActivePlayers()) do
                local p = GetPlayerPed(pid)
                if p ~= 0 and p ~= PlayerPedId() and DoesEntityExist(p) then
                    local d = #(GetEntityCoords(p) - vpos)
                    if d < bestD then bestD = d; best = pid end
                end
            end
            if best then return GetPlayerServerId(best) end
        end
        return 0
    end

    local victimServerId = resolveVictimId(victim)
    dbg('victim resolved to server id: ' .. tostring(victimServerId))

    local function registerKill(reason)
        -- Guard against the same death firing multiple damage events.
        if recentKills[victim] and (GetGameTimer() - recentKills[victim]) < 3000 then return end
        recentKills[victim] = GetGameTimer()

        local zoneNow = ZoneAtPlayer() or currentZoneId
        dbg('registerKill via ' .. reason .. ' | zoneNow=' .. tostring(zoneNow))
        if zoneNow then
            currentZoneId = zoneNow
            kills = kills + 1
            killStreak = killStreak + 1
            UpdateHUD()
            TriggerServerEvent('lime_redzones:server:giveKillReward', zoneNow, victimServerId, weapon)
        else
            TriggerServerEvent('lime_redzones:server:globalKill')
        end
    end

    -- Only real players count as kills, in a zone or globally. NPC/ped kills
    -- are ignored entirely — `victimIsPlayer` used to be computed here and
    -- never actually checked, which is why NPC/AI kills were counting.
    local victimIsPlayer = IsPedAPlayer(victim)
    if not victimIsPlayer then return end

    if isFatal == 1 or isFatal == true then
        registerKill('isFatal')
    elseif not pendingPoll[victim] and not recentKills[victim] then
        -- ONE poll per victim, not one per bullet. This used to spawn a 1.2s
        -- polling thread for every non-fatal damage event, so a single burst
        -- of automatic fire created dozens of concurrent threads and a busy
        -- zone kept hundreds alive at once — the dedup inside registerKill ran
        -- far too late to prevent any of it.
        pendingPoll[victim] = true
        local v = victim
        CreateThread(function()
            for _ = 1, 15 do
                Wait(80)
                if not DoesEntityExist(v) then break end
                if IsEntityDead(v) then
                    registerKill('health-poll')
                    break
                end
            end
            pendingPoll[v] = nil
        end)
    end
end)
