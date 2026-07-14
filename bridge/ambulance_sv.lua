-- Only trusts genuine export calls as success (pcall catches a broken export) —
-- TriggerClientEvent never throws, so it can't be used to detect success.
function DoRevive(src, coords, heading)

    if GetResourceState('wasabi_ambulance') == 'started' then
        local ok = pcall(function() exports.wasabi_ambulance:revivePlayer(src) end)
        if not ok then ok = pcall(function() exports.wasabi_ambulance:RevivePlayer(src) end) end
        if ok then
            TriggerClientEvent('lime_redzones:client:postReviveTeleport', src, coords, heading)
            TriggerClientEvent('lime_redzones:client:verifyRevive', src, coords, heading)
            return
        end
    end

    if GetResourceState('osp_ambulance') == 'started' then
        local ok = pcall(function() exports.osp_ambulance:revivePlayer(src) end)
        if not ok then ok = pcall(function() exports.osp_ambulance:RevivePlayer(src) end) end
        if ok then
            TriggerClientEvent('lime_redzones:client:postReviveTeleport', src, coords, heading)
            TriggerClientEvent('lime_redzones:client:verifyRevive', src, coords, heading)
            return
        end
    end

    if GetResourceState('core_ambulance') == 'started' then
        local ok = pcall(function() exports.core_ambulance:revivePlayer(src) end)
        if not ok then ok = pcall(function() exports.core_ambulance:RevivePlayer(src) end) end
        if ok then
            TriggerClientEvent('lime_redzones:client:postReviveTeleport', src, coords, heading)
            TriggerClientEvent('lime_redzones:client:verifyRevive', src, coords, heading)
            return
        end
    end

    -- No verified export worked — let the client try its own integrations.
    TriggerClientEvent('lime_redzones:client:doRevive', src, coords, heading)
end
