function DoRevive(src, coords, heading)

    if GetResourceState('wasabi_ambulance') == 'started' then
        -- Wasabi V2 export, then V1 export, then V1/V2 server event
        local ok = pcall(function() exports.wasabi_ambulance:revivePlayer(src) end)
        if not ok then ok = pcall(function() exports.wasabi_ambulance:RevivePlayer(src) end) end
        if not ok then ok = pcall(function() TriggerClientEvent('wasabi_ambulance:revivePlayer', src) end) end
        if ok then
            TriggerClientEvent('lime_redzones:client:postReviveTeleport', src, coords, heading)
            return
        end
    end

    if GetResourceState('osp_ambulance') == 'started' then
        local ok = pcall(function() exports.osp_ambulance:revivePlayer(src) end)
        if not ok then ok = pcall(function() exports.osp_ambulance:RevivePlayer(src) end) end
        if ok then
            TriggerClientEvent('lime_redzones:client:postReviveTeleport', src, coords, heading)
            return
        end
    end

    if GetResourceState('core_ambulance') == 'started' then
        local ok = pcall(function() exports.core_ambulance:revivePlayer(src) end)
        if not ok then
            ok = pcall(function() exports.core_ambulance:RevivePlayer(src) end)
        end
        if ok then
            TriggerClientEvent('lime_redzones:client:postReviveTeleport', src, coords, heading)
            return
        end
    end

    TriggerClientEvent('lime_redzones:client:doRevive', src, coords, heading)
end
