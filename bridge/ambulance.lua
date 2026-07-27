local function bdbg(msg)
    if type(RZDbg) == 'function' then RZDbg('[revive] ' .. msg) end
end

local function finite(n)
    return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

local function teleportTo(coords, heading)
    if not coords then return end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not (finite(x) and finite(y) and finite(z)) then
        bdbg('teleport skipped — non-finite coords')
        return
    end
    local h = tonumber(heading)

    local ped = PlayerPedId()
    SetEntityCoords(ped, x, y, z, false, false, false, false)
    if finite(h) then SetEntityHeading(ped, h) end

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

local medicalRes   = nil
local deathCheck   = nil

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
    Wait(5000)
    resolveMedical()
    if medicalRes then bdbg('death system present: ' .. medicalRes) end
end)

local DOWN_KEYS = { 'isDead', 'dead', 'inLaststand', 'laststand', 'isDowned', 'downed' }

local function readDownState()
    local st = LocalPlayer.state
    for i = 1, #DOWN_KEYS do
        if st[DOWN_KEYS[i]] == true then return true end
    end
    return false
end

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
                down, decided = _downVal, true
            end
        end
        if not decided or not down then
            local ok2, r2 = pcall(readDownState)
            if ok2 and r2 == true then down = true end
        end
        if not down and GetEntityHealth(ped) <= 5 and IsPedRagdoll(ped) then
            down = true
        end
        _downVal = down
    end
    return _downVal
end

local function stillStuck(ped) return LimeIsDowned(ped) end

function LimeDownedWhy()
    local ped = PlayerPedId()
    local job = 'n/a'
    if deathCheck then
        local ok, r = pcall(deathCheck)
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

local RESURRECT_MIN_GAP = 2500
local UP_CONFIRM_MS     = 4000
local REDOWN_WINDOW     = 6000
local FIGHT_LIMIT       = 3
local LOCKOUT_MS        = 45000

local lastResurrect     = 0
local fightCount        = 0
local reviveLockoutUntil = 0
local warnedConflict    = false

function LimeReviveLockedOut() return GetGameTimer() < reviveLockoutUntil end

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
        fightCount = 0
    end)
end

local function nativeResurrect(coords, heading)
    if LimeReviveLockedOut() then bdbg('nativeResurrect skipped (locked out)') return false end

    if medicalPresent() then
        bdbg('nativeResurrect skipped (death system present)')
        return false
    end
    if RZOption('nativeReviveFallback', true) == false then
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

local reviveChainActive = false
function LimeReviveInProgress() return reviveChainActive end

local lastFailNotify = 0
local function notifyFailed()
    local now = GetGameTimer()
    if now - lastFailNotify < 20000 then return end
    lastFailNotify = now
    if type(Notify) == 'function' then Notify(_U('revive_failed'), 'error') end
end

local DRIFT_LIMIT = 15.0

local function driftedFrom(coords)
    if not coords then return false end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not (finite(x) and finite(y) and finite(z)) then return false end
    return #(GetEntityCoords(PlayerPedId()) - vector3(x, y, z)) > DRIFT_LIMIT
end

local lastPreTeleport = 0
local function preReviveTeleport(coords, heading)
    local now = GetGameTimer()
    if now - lastPreTeleport < 1500 then return end
    lastPreTeleport = now
    bdbg('pre-revive teleport to exit')
    teleportTo(coords, heading)
end

local function awaitReviveAtExit(coords, heading)
    if reviveChainActive then bdbg('chain already active — skip') return end
    reviveChainActive = true
    bdbg('revive chain start')
    preReviveTeleport(coords, heading)
    CreateThread(function()
        local hasMedical = medicalPresent()
        local budget = hasMedical
            and (tonumber(RZOption('reviveWaitMedical', 12000)) or 12000)
            or  (tonumber(RZOption('reviveWaitNative', 4000)) or 4000)

        local function landed()
            Wait(300)
            bdbg('revive landed at exit')
            TriggerServerEvent('lime_redzones:server:confirmRevive')
            if driftedFrom(coords) then
                bdbg('revive relocated the ped — returning to the exit')
                teleportTo(coords, heading)
            end
        end

        local waited = 0
        while waited < budget do
            Wait(150)
            waited = waited + 150
            if not stillStuck(PlayerPedId()) then
                landed()
                reviveChainActive = false
                return
            end
        end

        if hasMedical then
            bdbg('death system present but revive did not land — leaving it alone')
            notifyFailed()
        elseif nativeResurrect(coords, heading) then
            Wait(300)
            if not stillStuck(PlayerPedId()) then
                landed()
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

RegisterNetEvent('lime_redzones:client:preReviveTeleport', function(coords, heading)
    preReviveTeleport(coords, heading)
    TriggerServerEvent('lime_redzones:server:reviveTeleported')
end)

RegisterNetEvent('lime_redzones:client:postReviveTeleport', function(coords, heading)
    awaitReviveAtExit(coords, heading)
end)

RegisterNetEvent('lime_redzones:client:doRevive', function(coords, heading)
    if reviveChainActive then bdbg('doRevive ignored (chain active)') return end
    bdbg('doRevive received')
    if not medicalPresent() then
        preReviveTeleport(coords, heading)
        if nativeResurrect(coords, heading) then
            Wait(300)
            if not stillStuck(PlayerPedId()) then
                TriggerServerEvent('lime_redzones:server:confirmRevive')
                if driftedFrom(coords) then teleportTo(coords, heading) end
                return
            end
        end
    end
    awaitReviveAtExit(coords, heading)
end)

RegisterNetEvent('lime_redzones:client:reviveDenied', function(reason)
    bdbg('revive denied by server' .. (reason and (' (' .. tostring(reason) .. ')') or ''))
    if reason == 'noPath' then
        print('^3[lime_redzones] Zone revive has no configured path — see "rz_medical" on the server console.^0')
    end
end)
