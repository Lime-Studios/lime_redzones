-- Server-side revive. Only a real export call proves success (a missing or
-- broken export throws and pcall catches it) — TriggerClientEvent never throws,
-- so it can never be used to detect whether a revive worked.
--
-- Each entry: resource name -> list of exports to try, in order.
local SERVER_REVIVES = {
    { res = 'qbx_medical',      fns = { 'Revive' } },
    { res = 'wasabi_ambulance', fns = { 'revivePlayer', 'RevivePlayer' } },
    { res = 'osp_ambulance',    fns = { 'revivePlayer', 'RevivePlayer' } },
    { res = 'core_ambulance',   fns = { 'revivePlayer', 'RevivePlayer' } },
    { res = 'ars_ambulancejob', fns = { 'revivePlayer', 'RevivePlayer' } },
}

local function tryServerRevive(src)
    for _, entry in ipairs(SERVER_REVIVES) do
        if GetResourceState(entry.res) == 'started' then
            for _, fn in ipairs(entry.fns) do
                local ok = pcall(function() return exports[entry.res][fn](nil, src) end)
                if ok then return true end
            end
        end
    end
    return false
end

function DoRevive(src, coords, heading)
    -- Community Bridge first: it already knows which ambulance job is running
    -- and how to revive through it. Its result is trusted only if the export
    -- genuinely succeeded — the client still verifies before teleporting.
    if CB and CB.active and CB.Revive(src) then
        TriggerClientEvent('lime_redzones:client:postReviveTeleport', src, coords, heading)
        return
    end

    if tryServerRevive(src) then
        -- Export reported success, but a successful call doesn't guarantee the
        -- framework actually cleared the player's death state. The client
        -- verifies and handles the teleport once the revive has landed.
        TriggerClientEvent('lime_redzones:client:postReviveTeleport', src, coords, heading)
        return
    end

    -- No verified server export — let the client try its own integrations,
    -- with its own guaranteed fallback.
    TriggerClientEvent('lime_redzones:client:doRevive', src, coords, heading)
end
