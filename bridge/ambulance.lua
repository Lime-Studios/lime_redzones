local function teleportTo(coords, heading)
    if not coords then return end
    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    if heading then SetEntityHeading(ped, heading) end
end

RegisterNetEvent('lime_redzones:client:postReviveTeleport', function(coords, heading)

    SetTimeout(500, function()
        teleportTo(coords, heading)
    end)
end)

RegisterNetEvent('lime_redzones:client:doRevive', function(coords, heading)
    local handled = false

    if GetResourceState('wasabi_ambulance') == 'started' then
        -- Wasabi V2 (event) then V1 (export) fallbacks
        local ok = pcall(function() TriggerEvent('wasabi_ambulance:revivePlayer') end)
        if not ok then ok = pcall(function() exports.wasabi_ambulance:revivePlayer() end) end
        if not ok then ok = pcall(function() exports.wasabi_ambulance:RevivePlayer() end) end
        handled = ok
    elseif GetResourceState('osp_ambulance') == 'started' then
        local ok = pcall(function() TriggerEvent('osp_ambulance:client:revive') end)
        if not ok then ok = pcall(function() exports.osp_ambulance:revivePlayer() end) end
        if not ok then ok = pcall(function() TriggerEvent('osp-ambulance:revive') end) end
        handled = ok
    elseif GetResourceState('esx-ambulancejob') == 'started' then
        TriggerEvent('esx-ambulancejob:revive'); handled = true
    elseif GetResourceState('esx_ambulancejob') == 'started' then
        TriggerEvent('esx_ambulancejob:revive'); handled = true
    elseif GetResourceState('qb-ambulancejob') == 'started' then
        TriggerEvent('hospital:client:Revive'); handled = true
    elseif GetResourceState('qbx_medical') == 'started' then
        exports.qbx_medical:Revive(); handled = true
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

    if handled then
        SetTimeout(500, function() teleportTo(coords, heading) end)
        return
    end

    local ped = PlayerPedId()
    local pos = coords or GetEntityCoords(ped)
    NetworkResurrectLocalPlayer(pos.x, pos.y, pos.z, heading or 0.0, true, false)
    ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    ClearPedTasksImmediately(ped)
end)

RegisterNetEvent('lime_redzones:client:reviveDenied', function()

    SetTimeout(5000, function()
        local ped = PlayerPedId()
        if IsEntityDead(ped) and GetResourceState('wasabi_ambulance') ~= 'started'
            and GetResourceState('qb-ambulancejob') ~= 'started'
            and GetResourceState('qbx_medical') ~= 'started'
            and GetResourceState('esx_ambulancejob') ~= 'started'
            and GetResourceState('esx-ambulancejob') ~= 'started' then
            local pos = GetEntityCoords(ped)
            NetworkResurrectLocalPlayer(pos.x, pos.y, pos.z, GetEntityHeading(ped), true, false)
            ped = PlayerPedId()
            SetEntityHealth(ped, 110)
            ClearPedBloodDamage(ped)
        end
    end)
end)
