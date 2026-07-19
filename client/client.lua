local Zones, zoneBlips = {}, {}
local currentZoneId    = nil
local currentSafeId    = nil
-- Pending respawn request. Retried until the player is actually alive, because
-- a single fire-and-forget attempt could be lost to a dropped event, the
-- server's rate limit, or a revive that silently failed.
local reviveRequest    = nil
local RZ_DEBUG         = false  -- toggle with /rz_debug
local kills, deaths, killStreak = 0, 0, 0
local recentKills = {}  -- victim ped -> last kill time (dedup repeated damage events)
local wasDead          = false
local tabletOpen, tabletMode, hudMoveMode = false, nil, false
local personalColor    = nil
local hudPos           = nil

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
local function DrawPolyWalls(z)
    local n = #z.poly
    local baseZ = z.polyMinZ or (z.vec.z - 2.0)
    local topZ  = z.polyMaxZ or (baseZ + 6.0)
    local r, g, b = z._r, z._g, z._b
    -- colorA drives the dome's translucency; reuse it here, clamped so the
    -- walls never turn into an opaque box or vanish entirely.
    local a = math.max(20, math.min(160, z._a or 80))
    local edgeA = math.min(110, a + 30)
    for i = 1, n do
        local p1 = z.poly[i]
        local p2 = z.poly[i % n + 1]
        -- Each wall = a quad = two triangles. DrawPoly is SINGLE-SIDED (only
        -- the side whose vertices wind counter-clockwise toward the camera is
        -- drawn), so every triangle is drawn in BOTH windings. Without the
        -- reversed copies, walls facing away from the camera vanish — which is
        -- why part of the box wasn't showing.
        -- Triangle 1: bottom-left, bottom-right, top-right
        DrawPoly(p1.x, p1.y, baseZ, p2.x, p2.y, baseZ, p2.x, p2.y, topZ, r, g, b, a)
        DrawPoly(p2.x, p2.y, topZ,  p2.x, p2.y, baseZ, p1.x, p1.y, baseZ, r, g, b, a) -- reverse
        -- Triangle 2: bottom-left, top-right, top-left
        DrawPoly(p1.x, p1.y, baseZ, p2.x, p2.y, topZ, p1.x, p1.y, topZ, r, g, b, a)
        DrawPoly(p1.x, p1.y, topZ,  p2.x, p2.y, topZ, p1.x, p1.y, baseZ, r, g, b, a) -- reverse
        -- Soft base + top edge so the boundary reads without a bright wireframe.
        DrawLine(p1.x, p1.y, baseZ, p2.x, p2.y, baseZ, r, g, b, edgeA)
        DrawLine(p1.x, p1.y, topZ,  p2.x, p2.y, topZ,  r, g, b, math.floor(edgeA * 0.6))
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
    placing = nil
    if tabletProp and DoesEntityExist(tabletProp) then DeleteEntity(tabletProp) end
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
local Opts = {}

RegisterNetEvent('lime_redzones:client:syncOptions', function(o) Opts = o or {} end)

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
    local nr = NextStreakReward(z, killStreak)
    SendNUIMessage({
        type = 'updateRedzoneUI', display = true,
        zoneName = z.name, kills = kills, deaths = deaths, streak = killStreak,
        nextReward = nr and { streak = tonumber(nr.streak), name = nr.name, amount = tonumber(nr.amount) or 1 } or nil,
    })
end

local TABLET_DICT = 'amb@code_human_in_bus_passenger_idles@female@tablet@base'

local function clearTabletProp()
    if tabletProp and DoesEntityExist(tabletProp) then
        DetachEntity(tabletProp, true, true)
        DeleteEntity(tabletProp)
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
            RequestAnimDict(TABLET_DICT)
            
            local wantName = 'limeredzones_prop'
            local model = GetHashKey(wantName)
            local isFallback = false

            RequestModel(model)
            
            local tries = 0
            while not HasModelLoaded(model) and tries < 300 do
                Wait(10)
                tries = tries + 1
                if myGen ~= tabletAnimGen then
                    SetModelAsNoLongerNeeded(model)
                    return
                end
            end

            if not HasModelLoaded(model) then
                model = GetHashKey('prop_cs_tablet')
                isFallback = true
                RequestModel(model)
                while not HasModelLoaded(model) do Wait(0) end
            end

            if myGen ~= tabletAnimGen or not tabletOpen then
                SetModelAsNoLongerNeeded(model)
                return
            end

            ped = PlayerPedId()
            RequestAnimDict(TABLET_DICT)
            while not HasAnimDictLoaded(TABLET_DICT) do Wait(0) end
            
            TaskPlayAnim(ped, TABLET_DICT, 'base', 3.0, 3.0, -1, 50, 0, false, false, false)

            clearTabletProp()
            
            local boneCoords = GetPedBoneCoords(ped, 28422, 0.0, 0.0, 0.0)
            tabletProp = CreateObject(model, boneCoords.x, boneCoords.y, boneCoords.z, true, true, false)
            
            while not DoesEntityExist(tabletProp) do Wait(0) end
            
            SetEntityCollision(tabletProp, false, false)
            SetEntityVisible(tabletProp, true, false)
            SetEntityAlpha(tabletProp, 255, false)
            ResetEntityAlpha(tabletProp)
            
            local bone = GetPedBoneIndex(ped, 28422) -- SKEL_R_Hand
            
            local offX, offY, offZ, rotX, rotY, rotZ
            if isFallback then
                offX, offY, offZ = 0.0, -0.03, 0.0
                rotX, rotY, rotZ = 20.0, -90.0, 0.0
            else
                -- INTEGRATED YOUR PROVIDED CONFIGURATION SETTINGS
                offX, offY, offZ = 0.05, -0.005, -0.04
                rotX, rotY, rotZ = 0.0, 180.0, 0.0
            end
            
            AttachEntityToEntity(tabletProp, ped, bone,
                offX, offY, offZ, rotX, rotY, rotZ, 
                true, false, false, false, 2, true)

            SetModelAsNoLongerNeeded(model)
        end)
    else
        StopAnimTask(ped, TABLET_DICT, 'base', 2.0)
        ClearPedSecondaryTask(ped)
        clearTabletProp()
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

-- Drives pending respawn requests. Cheap: sleeps 500ms and does nothing at all
-- unless a request is actually outstanding.
CreateThread(function()
    while true do
        Wait(500)
        local r = reviveRequest
        if r then
            local ped = PlayerPedId()
            -- Alive again (by our hand or an admin/medic) — nothing left to do.
            if not IsEntityDead(ped) and not IsPedDeadOrDying(ped, true) then
                reviveRequest = nil
            elseif GetGameTimer() >= r.at then
                -- Server rate-limits revives at 8s; space retries wider than
                -- that so a retry can't be swallowed by the limiter.
                r.at = GetGameTimer() + 9000
                r.tries = (r.tries or 0) + 1
                if r.tries > 6 then
                    reviveRequest = nil
                    Notify(_U('revive_failed'), 'error')
                else
                    TriggerServerEvent('lime_redzones:server:attemptRevive', r.zone, r.exit, 0.0)
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
    local ped = PlayerPedId()
    SetTablet(false)

    CreateThread(function()
        DoScreenFadeOut(400)
        while not IsScreenFadedOut() do Wait(10) end

        local veh = GetVehiclePedIsIn(ped, false)
        local ent = (veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped) and veh or ped

        -- Request the collision volume first, otherwise the player can land
        -- under the map before the ground streams in.
        SetEntityCoordsNoOffset(ent, coords.x, coords.y, coords.z, false, false, false)
        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        local tries = 0
        while not HasCollisionLoadedAroundEntity(ent) and tries < 100 do
            RequestCollisionAtCoord(coords.x, coords.y, coords.z)
            Wait(10)
            tries = tries + 1
        end

        -- Only snap to ground when using the zone centre as a fallback. A
        -- configured spawn point was placed deliberately (rooftop, interior,
        -- balcony), so snapping it down would move it off the intended spot.
        if not exact then
            local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 10.0, false)
            if found then SetEntityCoordsNoOffset(ent, coords.x, coords.y, groundZ, false, false, false) end
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
if Config.LeaderboardKeybindEnabled ~= false then
    RegisterKeyMapping('leaderboard', 'Toggle Redzone Leaderboard', 'keyboard', Config.LeaderboardKey or 'F1')
end

RegisterCommand('rz_admin', function()
    if tabletOpen and tabletMode == 'admin' then SetTablet(false)
    else TriggerServerEvent('lime_redzones:server:adminOpen') end
end, false)

RegisterCommand('rz_color', function() OpenPlayerTablet('color') end, false)
RegisterCommand('rz_hud', function() SetHudMove(not hudMoveMode) end, false)

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
    local camPos = vector3(start.x, start.y, start.z + 18.0)
    local rotX, rotZ = -35.0, GetEntityHeading(ped)
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
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
        local target = camPos + fwd * 2000.0
        local ray = StartShapeTestRay(camPos.x, camPos.y, camPos.z, target.x, target.y, target.z, 1 + 16, 0, 7)
        local _, hit, hitPos = GetShapeTestResult(ray)
        if hit and hit ~= 0 and hitPos then
            lastHit = vector3(hitPos.x, hitPos.y, hitPos.z)
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
    DestroyCam(cam, false)
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
        if DoesEntityExist(ped) then
            if npcTargetLib == 'ox' then pcall(function() exports.ox_target:removeLocalEntity(ped) end) end
            SetEntityAsMissionEntity(ped, true, true)
            DeleteEntity(ped)
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
                local within = d <= ((z.radius or 60.0) + 100.0)
                if within and not spawnedNpcs[zoneId] then
                    SpawnZoneNpcs(zoneId, z)
                elseif not within and spawnedNpcs[zoneId] then
                    DespawnZoneNpcs(zoneId)
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
    while true do
        local renderDist = DynRenderDist or 120.0
        if not next(Zones) then Wait(2500) goto continue end

        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)

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
            SendNUIMessage({ type = 'safezone', display = true, name = safeZone.name, speedLimit = tonumber(safeZone.speedLimit) or 0 })
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
            if currentZoneId then
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
                Wait(nDist > (nearest and nearest.radius or 0) + renderDist + 200.0 and 2000 or 1000)
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
            frame = frame + (showVisual and 1 or 30)
            if frame >= 30 then
                frame = 0
                local inside = InsideZone(nearest, pos)
                local dead   = IsEntityDead(ped)

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


                if currentZoneId and dead and not wasDead then
                    wasDead = true
                    deaths = deaths + 1
                    killStreak = 0
                    UpdateHUD()
                    TriggerServerEvent('lime_redzones:server:reportDeath', currentZoneId)

                    if Opts.killCamEnabled ~= false then
                        local killer = GetPedSourceOfDeath(ped)
                        if killer and killer ~= 0 and killer ~= ped and DoesEntityExist(killer) then
                            CreateThread(function()
                                killCamActive = true
                                local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

                                local kPlayer = NetworkGetPlayerIndexFromPed(killer)
                                if kPlayer == -1 then
                                    for _, pid in ipairs(GetActivePlayers()) do
                                        if GetPlayerPed(pid) == killer then kPlayer = pid break end
                                    end
                                end
                                local killerName = (kPlayer and kPlayer ~= -1) and GetPlayerName(kPlayer) or 'Unknown'
                                local killerId = kPlayer ~= -1 and GetPlayerServerId(kPlayer) or 0
                                local camDur = math.max(1000, tonumber(Opts.killCamDuration) or 5000)

                                SendNUIMessage({ type = 'killCam', display = true, killer = killerName, id = killerId, duration = camDur })

                                local function frameKiller()
                                    if not DoesEntityExist(killer) then return end
                                    -- Third-person: sit behind and above the killer, framing their whole body.
                                    local kc = GetEntityCoords(killer)
                                    local heading = GetEntityHeading(killer)
                                    local rad = math.rad(heading)
                                    local camPos = vector3(
                                        kc.x + math.sin(rad) * 2.6,
                                        kc.y - math.cos(rad) * 2.6,
                                        kc.z + 1.2
                                    )
                                    SetCamCoord(cam, camPos.x, camPos.y, camPos.z)
                                    PointCamAtEntity(cam, killer, 0.0, 0.0, 0.0, true)
                                end

                                frameKiller()
                                SetCamActive(cam, true)
                                RenderScriptCams(true, false, 0, true, true)

                                local t = GetGameTimer()
                                while killCamActive and (GetGameTimer() - t) < camDur and DoesEntityExist(killer) do
                                    Wait(0)
                                    frameKiller()
                                end

                                RenderScriptCams(false, false, 0, true, true)
                                DestroyCam(cam, false)
                                killCamActive = false
                                SendNUIMessage({ type = 'killCam', display = false })
                            end)
                        end
                    end

                    local z = Zones[currentZoneId]
                    local exits = z.exits or {}
                    local exit
                    if #exits > 0 then
                        local e = exits[math.random(#exits)]
                        exit = { x = e.x, y = e.y, z = e.z }
                    else

                        local away = (z.teleportAway or 30.0) + z.radius
                        local ang = math.random() * 6.28318
                        exit = { x = z.coords.x + math.cos(ang) * away, y = z.coords.y + math.sin(ang) * away, z = z.coords.z }
                    end
                    local zid = currentZoneId
                    -- Fire-and-forget was unreliable: if the request was lost,
                    -- rate-limited, or the revive silently failed, the player
                    -- stayed dead with no second attempt. Retry until we're
                    -- actually alive, then stop.
                    reviveRequest = { zone = zid, exit = exit, at = GetGameTimer() + (z.reviveDelay or 8000) }
                elseif not dead and wasDead then
                    wasDead = false
                    killCamActive = false
                    reviveRequest = nil
                end
            end

            -- Per-zone rule: no shooting from outside the zone, so players
            -- can't camp the perimeter and pick off people inside. Gate it on
            -- ACTUAL containment (position), not the 30-frame-stale currentZoneId
            -- — that lag left firing disabled for a moment after leaving, and if
            -- the loop kept ticking near the edge it never re-enabled. Only
            -- blocks while genuinely near-but-outside this specific zone.
            local shootBlocked = false
            if nearest.blockOutsideShooting == true and not InsideZone(nearest, pos) then
                shootBlocked = true
                DisablePlayerFiring(PlayerId(), true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 140, true)
                DisableControlAction(0, 141, true)
                DisableControlAction(0, 142, true)
                DisableControlAction(0, 257, true)
            end

            -- A safe zone may sit inside/near this redzone — keep it drawn and
            -- its rules enforced while we're handling the redzone.
            local safeVisible2 = safeZone and safeDist <= (safeZone.radius + renderDist) and safeZone.showMarker ~= false
            if safeVisible2 then DrawSafeMarker(safeZone) end
            if currentSafeId then ApplySafeTick(Zones[currentSafeId]) end

            -- Only stay per-frame while something needs it: a visible visual,
            -- an active shooting block, or safe-zone rules. Otherwise ~300ms.
            if showVisual or shootBlocked or safeVisible2 or currentSafeId then
                Wait(0)
            else
                Wait(300)
            end
        end
        ::continue::
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

RegisterCommand('rz_debug', function()
    RZ_DEBUG = not RZ_DEBUG
    Notify('Redzone debug ' .. (RZ_DEBUG and 'ON' or 'OFF') .. '. Check F8 console.', 'info')
    print('[lime_redzones] debug = ' .. tostring(RZ_DEBUG) .. ' | currentZoneId = ' .. tostring(currentZoneId))
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
    else
        local v = victim
        CreateThread(function()
            local tries = 0
            while tries < 15 do
                Wait(80)
                tries = tries + 1
                if not DoesEntityExist(v) then return end
                if IsEntityDead(v) then
                    registerKill('health-poll')
                    return
                end
            end
        end)
    end
end)
