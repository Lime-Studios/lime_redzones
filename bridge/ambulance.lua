-- Every path here ends with a health check + native resurrect fallback,
-- since TriggerEvent doesn't error when nothing's listening for it.

-- Ambulance resources this script knows how to hand a revive to.
local AMBULANCE_RESOURCES = {
    'wasabi_ambulance', 'osp_ambulance', 'esx-ambulancejob', 'esx_ambulancejob',
    'qb-ambulancejob', 'qbx_ambulancejob', 'qbx_medical', 'qs-ambulancejob', 'ars_ambulancejob',
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

-- Decide whether the player is genuinely stuck post-revive. Never touch a
-- player who is already alive and in control — clearing tasks or rewriting
-- statebags on someone who's up and running interrupts them and can fight
-- the framework's own post-revive flow.
local function stillStuck(ped)
    if IsEntityDead(ped) then return true end
    if IsPedDeadOrDying(ped, true) then return true end
    if IsEntityPositionFrozen and IsEntityPositionFrozen(ped) then return true end
    -- Downed statebag without native death (QB/QBX laststand style).
    local ok, dead = pcall(function() return LocalPlayer.state.isDead end)
    if ok and dead == true then return true end
    local ok2, ls = pcall(function() return LocalPlayer.state.inLaststand end)
    if ok2 and ls == true then return true end
    return false
end

local function forceAliveState(coords, heading)
    local ped = PlayerPedId()
    if not stillStuck(ped) then return end

    if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) then
        nativeResurrect(coords, heading)
        ped = PlayerPedId()
    end

    pcall(function()
        if LocalPlayer.state.isDead then LocalPlayer.state:set('isDead', false, true) end
        if LocalPlayer.state.inLaststand then LocalPlayer.state:set('inLaststand', false, true) end
    end)

    FreezeEntityPosition(ped, false)
    SetPedCanRagdoll(ped, true)
    ClearPedTasksImmediately(ped)
end

-- Re-check a few times: frameworks finish their revive at different speeds,
-- so a single fixed-delay check either fires too early (interrupting a revive
-- in progress) or too late (long stuck time). Each pass only acts if stuck.
-- Wait for the framework's revive to actually land, then teleport. Polls
-- instead of using one fixed delay, because ambulance jobs finish at very
-- different speeds — and teleporting mid-revive is what caused players to be
-- charged, moved, then left dead or yanked to a hospital.
local function reviveThenTeleport(coords, heading)
    CreateThread(function()
        local waited = 0
        while waited < 4000 do
            Wait(100)
            waited = waited + 100
            if not stillStuck(PlayerPedId()) then
                -- Revive landed. Let it finish its own teleport first, then move.
                Wait(300)
                teleportTo(coords, heading)
                return
            end
        end

        -- Framework never revived us — force it, then move.
        forceAliveState(coords, heading)
        Wait(200)
        teleportTo(coords, heading)
    end)
end

RegisterNetEvent('lime_redzones:client:postReviveTeleport', function(coords, heading)
    reviveThenTeleport(coords, heading)
end)

RegisterNetEvent('lime_redzones:client:doRevive', function(coords, heading)
    local handled = false

    -- Community Bridge knows the installed ambulance job; try it before our
    -- own per-resource guesses.
    if CB and CB.active and CB.Revive() then
        handled = true
    elseif GetResourceState('wasabi_ambulance') == 'started' then
        TriggerEvent('wasabi_ambulance:revivePlayer'); handled = true
    elseif GetResourceState('osp_ambulance') == 'started' then
        TriggerEvent('osp_ambulance:client:revive')
        TriggerEvent('osp-ambulance:revive'); handled = true
    elseif GetResourceState('esx-ambulancejob') == 'started' then
        TriggerEvent('esx-ambulancejob:revive'); handled = true
    elseif GetResourceState('esx_ambulancejob') == 'started' then
        TriggerEvent('esx_ambulancejob:revive'); handled = true
    elseif GetResourceState('qb-ambulancejob') == 'started' then
        TriggerEvent('hospital:client:Revive'); handled = true
    elseif GetResourceState('qbx_medical') == 'started' or GetResourceState('qbx_ambulancejob') == 'started' then
        -- qbx_medical owns its death state; this event clears it as well as
        -- resurrecting, which a native-only revive would not do.
        TriggerEvent('qbx_medical:client:playerRevived'); handled = true
    elseif GetResourceState('qs-ambulancejob') == 'started' then
        TriggerEvent('qs-ambulancejob:revivePlayer'); handled = true
    elseif GetResourceState('ars_ambulancejob') == 'started' then
        TriggerEvent('ars_ambulancejob:client:revivePlayer'); handled = true
    elseif GetResourceState('ps-medic') == 'started' then
        TriggerEvent('ps-medic:client:RevivePlayer'); handled = true
    elseif GetResourceState('fd_ambulance') == 'started' then
        TriggerEvent('fd_ambulance:client:revive'); handled = true
    elseif GetResourceState('codem-ambulance') == 'started' then
        TriggerEvent('codem-ambulance:client:revivePlayer'); handled = true
    elseif GetResourceState('lc_doj_ambulance') == 'started' then
        TriggerEvent('lc_doj:ambulance:revivePlayer'); handled = true
    elseif GetResourceState('t-ems') == 'started' then
        TriggerEvent('t-ems:client:revive'); handled = true
    end

    -- No ambulance job at all: resurrect immediately rather than leaving the
    -- player dead for a second waiting on a framework that will never answer.
    if not handled then
        nativeResurrect(coords, heading)
        teleportTo(coords, heading)
        return
    end

    -- Teleport only once the framework's revive has settled. Moving the ped
    -- while a revive/respawn is still running lets the framework snap the
    -- player back to its own hospital spawn instead of the zone exit.
    reviveThenTeleport(coords, heading)
end)

RegisterNetEvent('lime_redzones:client:reviveDenied', function()
    SetTimeout(5000, function()
        -- Only force it if no ambulance job owns the revive flow.
        if IsEntityDead(PlayerPedId()) and not AmbulanceJobRunning() then
            nativeResurrect(nil, GetEntityHeading(PlayerPedId()))
        end
    end)
end)
