-- Client-side ambulance integration + guaranteed revive.
--
-- TriggerEvent never errors just because nothing is listening, so it can't
-- tell us whether a framework's revive actually happened — a wrong event
-- name for someone's installed version used to fail completely silently.
-- Every path below now finishes with a health check: if the player is
-- still dead after giving the framework a moment to act, we force a native
-- resurrect so revive always works regardless of which job is installed.

-- All ambulance resources this script knows how to hand a revive to.
local AMBULANCE_RESOURCES = {
    'wasabi_ambulance', 'osp_ambulance', 'esx-ambulancejob', 'esx_ambulancejob',
    'qb-ambulancejob', 'qbx_medical', 'qs-ambulancejob', 'ars_ambulancejob',
    'ps-medic', 'fd_ambulance', 'codem-ambulance', 'lc_doj_ambulance', 't-ems',
    'core_ambulance',
}

local function AmbulanceJobRunning()
    for _, res in ipairs(AMBULANCE_RESOURCES) do
        if GetResourceState(res) == 'started' then return true end
    end
    return false
end

local function teleportTo(coords, heading)
    if not coords then return end
    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    if heading then SetEntityHeading(ped, heading) end
end

local function nativeResurrect(coords, heading)
    local ped = PlayerPedId()
    local pos = coords or GetEntityCoords(ped)
    NetworkResurrectLocalPlayer(pos.x, pos.y, pos.z, heading or GetEntityHeading(ped), true, false)
    ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    ClearPedTasksImmediately(ped)
end

-- Give whichever framework revive we triggered a moment to take effect,
-- then force a native resurrect if the player is still dead. This is what
-- actually guarantees revives work — not the (unreliable) event trigger.
local function ensureAlive(coords, heading, delay)
    SetTimeout(delay or 900, function()
        if IsEntityDead(PlayerPedId()) then
            nativeResurrect(coords, heading)
        end
    end)
end

RegisterNetEvent('lime_redzones:client:postReviveTeleport', function(coords, heading)
    SetTimeout(500, function() teleportTo(coords, heading) end)
end)

-- Sent after a server-side export revive reports success — still verifies,
-- since a successful export call doesn't guarantee the framework actually
-- cleared the player's dead state (version mismatches, custom death systems).
RegisterNetEvent('lime_redzones:client:verifyRevive', function(coords, heading)
    ensureAlive(coords, heading, 900)
end)

RegisterNetEvent('lime_redzones:client:doRevive', function(coords, heading)
    if GetResourceState('wasabi_ambulance') == 'started' then
        TriggerEvent('wasabi_ambulance:revivePlayer')
    elseif GetResourceState('osp_ambulance') == 'started' then
        TriggerEvent('osp_ambulance:client:revive')
        TriggerEvent('osp-ambulance:revive')
    elseif GetResourceState('esx-ambulancejob') == 'started' then
        TriggerEvent('esx-ambulancejob:revive')
    elseif GetResourceState('esx_ambulancejob') == 'started' then
        TriggerEvent('esx_ambulancejob:revive')
    elseif GetResourceState('qb-ambulancejob') == 'started' then
        TriggerEvent('hospital:client:Revive')
    elseif GetResourceState('qbx_medical') == 'started' then
        pcall(function() exports.qbx_medical:Revive() end)
    elseif GetResourceState('qs-ambulancejob') == 'started' then
        TriggerEvent('qs-ambulancejob:revivePlayer')
    elseif GetResourceState('ars_ambulancejob') == 'started' then
        TriggerEvent('ars_ambulancejob:client:revivePlayer')
    elseif GetResourceState('ps-medic') == 'started' then
        TriggerEvent('ps-medic:client:RevivePlayer')
    elseif GetResourceState('fd_ambulance') == 'started' then
        TriggerEvent('fd_ambulance:client:revive')
    elseif GetResourceState('codem-ambulance') == 'started' then
        TriggerEvent('codem-ambulance:client:revivePlayer')
    elseif GetResourceState('lc_doj_ambulance') == 'started' then
        TriggerEvent('lc_doj:ambulance:revivePlayer')
    elseif GetResourceState('t-ems') == 'started' then
        TriggerEvent('t-ems:client:revive')
    end

    SetTimeout(500, function() teleportTo(coords, heading) end)
    -- Regardless of which branch ran (or none did), confirm it worked.
    ensureAlive(coords, heading, 1200)
end)

RegisterNetEvent('lime_redzones:client:reviveDenied', function()
    SetTimeout(5000, function()
        -- Only force a fallback resurrect if no supported ambulance job is
        -- running at all — if one is, let it own the death/revive flow.
        if IsEntityDead(PlayerPedId()) and not AmbulanceJobRunning() then
            nativeResurrect(nil, GetEntityHeading(PlayerPedId()))
        end
    end)
end)
