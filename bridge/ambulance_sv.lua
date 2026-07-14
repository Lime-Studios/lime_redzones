-- Tries each supported ambulance job's server-side revive export.
-- Only genuine export calls are trusted as "success" (a missing/broken export
-- throws and pcall catches it) — TriggerEvent/TriggerClientEvent never throw
-- even when nothing is listening, so they can't be used to detect success.
-- If nothing verifiably worked, hand off to the client for its own attempt
-- plus a guaranteed native-resurrect fallback.
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

    -- No verified server-side export worked — let the client try its own
    -- event-based integrations, with a guaranteed native fallback if those
    -- don't actually bring the player back up either.
    TriggerClientEvent('lime_redzones:client:doRevive', src, coords, heading)
end
