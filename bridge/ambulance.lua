-- Client-side revive glue. The server drives the real revive through the
-- detected ambulance job; this file only handles the two things that must
-- happen on the dying player's own machine:
--
--   1. waiting for the revive to actually land, then teleporting to the exit
--   2. a native resurrect, but ONLY when no death system exists to fight
--
-- The old loop-breaker in here is what produced the "Zone revive conflicts
-- with the death system" warning. It flagged a conflict whenever two native
-- resurrects landed 3-8s apart — but the client's own retry loop re-sends a
-- revive request every 4s, so one slow revive was enough to trip it. It fired
-- on a revive that was merely late, never on an actual conflict.
--
-- A real conflict has a shape: we get the player UP, and something puts them
-- straight back DOWN. That is what is detected now, and it takes three of
-- those in a row before we back off.

local function bdbg(msg)
    if type(RZDbg) == 'function' then RZDbg('[revive] ' .. msg) end
end

local function finite(n)
    return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end


local function teleportTo(coords, heading)
    if not coords then return end
    -- Reject anything non-finite before it reaches a native. A NaN coordinate
    -- fed to SetEntityCoords is an instant hard crash, not a Lua error, and
    -- these coordinates have been through a JSON round trip.
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not (finite(x) and finite(y) and finite(z)) then
        bdbg('teleport skipped — non-finite coords')
        return
    end
    local h = tonumber(heading)

    -- SetEntityCoords, NOT SetEntityCoordsNoOffset. The "NoOffset" variant
    -- places the ped at the literal coordinate with no ground correction, so
    -- any exit whose Z is even slightly off plants the player inside geometry.
    -- SetEntityCoords applies the engine's own placement correction, which is
    -- what every teleport that works reliably uses.
    local ped = PlayerPedId()
    SetEntityCoords(ped, x, y, z, false, false, false, false)
    if finite(h) then SetEntityHeading(ped, h) end

    -- Collision is requested ONCE, then polled.
    --
    -- This previously re-issued RequestCollisionAtCoord on every 10ms iteration
    -- — up to 100 fresh streaming requests per teleport. Each call queues work
    -- in the streamer; spamming the same coordinate a hundred times floods that
    -- queue, and in an area dense with MLOs it cannot drain between deaths.
    -- A few revives was enough to exhaust the pool and hard-crash the client,
    -- which is why the crash tracked map density rather than anything in the
    -- revive logic itself. One request is all the streamer ever needed.
    CreateThread(function()
        RequestCollisionAtCoord(x, y, z)
        local waited = 0
        while not HasCollisionLoadedAroundEntity(ped) and waited < 3000 do
            Wait(50)
            waited = waited + 50
        end
        bdbg(('teleport settled after %dms'):format(waited))
    end)
end

-- ── Is a death system installed? ────────────────────────────────────────
-- Same list the server uses (config.lua is a shared_script), so the two sides
-- can never disagree about whether it's safe to force a resurrect.
local medicalRes   = nil    -- running resource name, or false
local deathCheck   = nil    -- that script's own "am I dead?" call, if it has one

-- Scripts whose downed state is NOT visible through natives or a statebag.
-- wasabi is the important one: it does not leave the ped natively dead and
-- publishes no downed statebag, so every generic check reads a downed player
-- as alive. That is why a death was registered and then immediately cleared
-- ("death state cleared — ready for next death") before the revive dispatched.
-- Both wasabi v1 and v2 expose the same client export.
local DEATH_CHECKS = {
    { resources = { 'wasabi_ambulance', 'wasabi_ambulance_v2', 'wasabi_medical' },
      check = function(res) return exports[res]:isPlayerDead() end },
    { resources = { 'ars_ambulancejob' },
      check = function() return exports.ars_ambulancejob:isDead() end },
    { resources = { 'brutal_ambulancejob' },
      check = function() return exports.brutal_ambulancejob:IsDead() end },
}

local function resolveMedical()
    medicalRes, deathCheck = false, nil
    for _, res in ipairs(Config.MedicalResources or {}) do
        if GetResourceState(res) == 'started' then medicalRes = res break end
    end
    for _, d in ipairs(DEATH_CHECKS) do
        for _, res in ipairs(d.resources) do
            if GetResourceState(res) == 'started' then
                deathCheck = function() return d.check(res) end
                medicalRes = medicalRes or res
                bdbg('using ' .. res .. "'s own death check")
                return
            end
        end
    end
end

local function medicalPresent()
    if medicalRes == nil then resolveMedical() end
    return medicalRes ~= false
end

CreateThread(function()
    -- Resources can start after us; settle, then take the real reading.
    Wait(5000)
    resolveMedical()
    if medicalRes then bdbg('death system present: ' .. medicalRes) end
end)

-- ── Downed detection ────────────────────────────────────────────────────
-- Single source of truth for "is this player down?", used by the revive chain
-- here and by the zone loop in client.lua. Having two separate versions of
-- this check is what let the two disagree about whether a death had happened.
--
-- Order matters: the ambulance job's own answer wins, because it is the thing
-- that decides when you're up. Statebags cover the jobs that publish one, and
-- the natives catch a plain death with no ambulance job at all.
local DOWN_KEYS = { 'isDead', 'dead', 'inLaststand', 'laststand', 'isDowned', 'downed' }

local function readDownState()
    local st = LocalPlayer.state
    for i = 1, #DOWN_KEYS do
        if st[DOWN_KEYS[i]] == true then return true end
    end
    return false
end

-- Ambulance jobs are NOT consistent about what their death check returns.
-- wasabi answers with a status STRING ('dead', 'laststand') on some paths and
-- a plain boolean on others. The old test was `r == true`, so 'dead' was
-- silently classified as alive — the death was cleared, no revive fired, and
-- because it depends which path wasabi took it worked sometimes and not
-- others. That is the "sometimes revives, sometimes doesn't" bug.
--
-- Normalise every shape these APIs actually return instead of assuming one.
local ALIVE_WORDS = {
    ['alive'] = true, ['none'] = true, ['ok'] = true, ['healthy'] = true,
    ['up'] = true, ['false'] = true, ['nil'] = true, ['0'] = true, [''] = true,
}

local function asDowned(v)
    if v == nil or v == false then return false end
    if v == true then return true end
    local t = type(v)
    if t == 'number' then return v ~= 0 end
    if t == 'string' then return not ALIVE_WORDS[v:lower()] end
    if t == 'table' then
        for i = 1, #DOWN_KEYS do
            if v[DOWN_KEYS[i]] == true then return true end
        end
        return false
    end
    return false
end

-- The export/statebag half is sampled at ~10Hz: a cross-resource export call
-- every frame from the render loop is far too expensive, and neither answer
-- changes between frames. The natives stay per-frame so a plain death is still
-- caught immediately.
local _downAt, _downVal = 0, false

function LimeIsDowned(ped)
    ped = ped or PlayerPedId()
    if IsEntityDead(ped) then return true end
    if IsPedDeadOrDying(ped, true) then return true end

    local now = GetGameTimer()
    if now - _downAt >= 100 then
        _downAt = now
        local down, decided = false, false
        if medicalPresent() and deathCheck then
            local ok, r = pcall(deathCheck)
            if ok then
                if r ~= nil then down, decided = asDowned(r), true end
            else
                -- The export threw (resource restarting, or not ready yet).
                -- Hold the previous reading rather than assuming the player is
                -- up: guessing "alive" here cancels a queued revive, and a
                -- single transient failure would do it.
                down, decided = _downVal, true
            end
        end
        if not decided or not down then
            local ok2, r2 = pcall(readDownState)
            if ok2 and r2 == true then down = true end
        end
        _downVal = down
    end
    if _downVal then return true end

    -- Near-zero health while ragdolled is a strong downed signal too.
    if GetEntityHealth(ped) <= 5 and IsPedRagdoll(ped) then return true end
    return false
end

local function stillStuck(ped) return LimeIsDowned(ped) end

-- Every downed signal, individually, as one line. When a revive misfires the
-- question is always "which source said the player was up?" — this answers it
-- directly instead of leaving it to be inferred from timing.
function LimeDownedWhy()
    local ped = PlayerPedId()
    local job = 'n/a'
    if deathCheck then
        local ok, r = pcall(deathCheck)
        -- Type and normalised verdict included: the raw value alone read as
        -- "dead" while the code treated it as alive, and nothing in the log
        -- showed that gap. These ambulance-job APIs are not boolean-typed.
        job = ok and ('%s<%s>->%s'):format(tostring(r), type(r), tostring(asDowned(r))) or 'ERR'
    end
    local bags = {}
    for i = 1, #DOWN_KEYS do
        local ok, v = pcall(function() return LocalPlayer.state[DOWN_KEYS[i]] end)
        if ok and v == true then bags[#bags + 1] = DOWN_KEYS[i] end
    end
    return ('native=%s dying=%s %s=%s bags=%s hp=%s'):format(
        tostring(IsEntityDead(ped)),
        tostring(IsPedDeadOrDying(ped, true)),
        tostring(medicalRes or 'job'),
        job,
        #bags > 0 and table.concat(bags, ',') or '-',
        tostring(GetEntityHealth(ped)))
end

-- ── Native resurrect, with a real conflict detector ─────────────────────
local RESURRECT_MIN_GAP = 2500    -- ignore duplicate calls inside this window
local UP_CONFIRM_MS     = 4000    -- how long we'll wait to confirm we got up
local REDOWN_WINDOW     = 6000    -- up, then down again this fast = a fight
local FIGHT_LIMIT       = 3       -- consecutive fights before backing off
local LOCKOUT_MS        = 45000

local lastResurrect     = 0
local fightCount        = 0
local reviveLockoutUntil = 0
local warnedConflict    = false

function LimeReviveLockedOut() return GetGameTimer() < reviveLockoutUntil end

-- Watches one resurrect through to a verdict. Only a confirmed up → down
-- transition counts as a conflict; a resurrect that simply never took is a
-- failure, not a fight, and must not trip the lockout.
local function watchForFight()
    CreateThread(function()
        local t0 = GetGameTimer()
        while stillStuck(PlayerPedId()) do
            if GetGameTimer() - t0 > UP_CONFIRM_MS then
                bdbg('resurrect never took — not counted as a conflict')
                return
            end
            Wait(150)
        end

        local upAt = GetGameTimer()
        while GetGameTimer() - upAt < REDOWN_WINDOW do
            Wait(200)
            if stillStuck(PlayerPedId()) then
                fightCount = fightCount + 1
                bdbg(('re-downed %dms after resurrect (fight %d/%d)')
                    :format(GetGameTimer() - upAt, fightCount, FIGHT_LIMIT))
                if fightCount >= FIGHT_LIMIT then
                    fightCount = 0
                    reviveLockoutUntil = GetGameTimer() + LOCKOUT_MS
                    bdbg('conflict confirmed — pausing auto-revive for 45s')
                    -- Told once per session, not once per death. This is an
                    -- install problem, not something the player can act on
                    -- repeatedly, and repeating it just spams them.
                    if not warnedConflict then
                        warnedConflict = true
                        if type(Notify) == 'function' then
                            Notify(_U('revive_conflict'), 'error')
                        end
                        print('^1[lime_redzones] Auto-revive is being undone by another death system.^0')
                        print('^1[lime_redzones] Add its resource name to Config.MedicalResources in config.lua.^0')
                    end
                end
                return
            end
        end
        -- Stayed up through the window: healthy revive, forget prior strikes.
        fightCount = 0
    end)
end

local function nativeResurrect(coords, heading)
    if LimeReviveLockedOut() then bdbg('nativeResurrect skipped (locked out)') return false end

    -- Never fight an installed death system. This one rule prevents the
    -- conflict outright; the detector below is only a safety net for a death
    -- system whose resource name isn't in Config.MedicalResources.
    if medicalPresent() then
        bdbg('nativeResurrect skipped (death system present)')
        return false
    end
    if Config.NativeReviveFallback == false then
        bdbg('nativeResurrect skipped (disabled in config)')
        return false
    end

    local now = GetGameTimer()
    if now - lastResurrect < RESURRECT_MIN_GAP then
        bdbg('nativeResurrect skipped (duplicate call)')
        return false
    end
    lastResurrect = now

    bdbg('nativeResurrect')
    local ped = PlayerPedId()
    local pos = coords or GetEntityCoords(ped)
    NetworkResurrectLocalPlayer(pos.x, pos.y, pos.z, heading or GetEntityHeading(ped), true, false)
    ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    ClearPedTasksImmediately(ped)
    -- Clear every downed statebag we know about so a framework doesn't
    -- immediately re-down us off a stale flag.
    pcall(function()
        for i = 1, #DOWN_KEYS do
            if LocalPlayer.state[DOWN_KEYS[i]] then
                LocalPlayer.state:set(DOWN_KEYS[i], false, true)
            end
        end
    end)
    FreezeEntityPosition(ped, false)
    watchForFight()
    return true
end

-- ── Revive chain ────────────────────────────────────────────────────────
local reviveChainActive = false
function LimeReviveInProgress() return reviveChainActive end

local lastFailNotify = 0
local function notifyFailed()
    -- Throttled: the retry loop can reach this several times per death and
    -- three identical error toasts in a row reads as the script being broken.
    local now = GetGameTimer()
    if now - lastFailNotify < 20000 then return end
    lastFailNotify = now
    if type(Notify) == 'function' then Notify(_U('revive_failed'), 'error') end
end

-- Wait for the revive to land (the ambulance job's own, or ours), then
-- teleport to the zone exit. One chain at a time.
local function reviveThenTeleport(coords, heading)
    if reviveChainActive then bdbg('chain already active — skip') return end
    reviveChainActive = true
    bdbg('revive chain start')
    CreateThread(function()
        local hasMedical = medicalPresent()
        local budget = hasMedical
            and (tonumber(Config.ReviveWaitMedical) or 12000)
            or  (tonumber(Config.ReviveWaitNative) or 4000)

        local waited = 0
        while waited < budget do
            Wait(150)
            waited = waited + 150
            if not stillStuck(PlayerPedId()) then
                Wait(300)
                bdbg('revive landed — teleporting')
                TriggerServerEvent('lime_redzones:server:confirmRevive')
                teleportTo(coords, heading)
                reviveChainActive = false
                return
            end
        end

        if hasMedical then
            -- A death system is installed but didn't get us up in time. Forcing
            -- a native resurrect here is what created the fight, so we don't —
            -- the player uses that system's own respawn.
            bdbg('death system present but revive did not land — leaving it alone')
            notifyFailed()
        elseif nativeResurrect(coords, heading) then
            Wait(300)
            if not stillStuck(PlayerPedId()) then
                TriggerServerEvent('lime_redzones:server:confirmRevive')
                teleportTo(coords, heading)
            else
                notifyFailed()
            end
        else
            bdbg('revive timed out and native resurrect unavailable')
            notifyFailed()
        end
        reviveChainActive = false
    end)
end

RegisterNetEvent('lime_redzones:client:postReviveTeleport', function(coords, heading)
    reviveThenTeleport(coords, heading)
end)

RegisterNetEvent('lime_redzones:client:doRevive', function(coords, heading)
    if reviveChainActive then bdbg('doRevive ignored (chain active)') return end
    bdbg('doRevive received')
    -- Reached when the server's revive didn't land, or there was no path at
    -- all. With no death system installed the native resurrect is safe and
    -- immediate; otherwise fall into the wait-it-out chain.
    if not medicalPresent() then
        if nativeResurrect(coords, heading) then
            Wait(300)
            if not stillStuck(PlayerPedId()) then
                TriggerServerEvent('lime_redzones:server:confirmRevive')
                teleportTo(coords, heading)
                return
            end
        end
    end
    reviveThenTeleport(coords, heading)
end)

RegisterNetEvent('lime_redzones:client:reviveDenied', function(reason)
    bdbg('revive denied by server' .. (reason and (' (' .. tostring(reason) .. ')') or ''))
    if reason == 'noPath' then
        -- Config problem, not a player problem. Console only.
        print('^3[lime_redzones] Zone revive has no configured path — see "rz_medical" on the server console.^0')
    end
end)
