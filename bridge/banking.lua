-- Bank money bridge. Tries popular standalone banking resources first (so the
-- reason shows up in that resource's own transaction history), then falls
-- back to the framework's built-in bank account. Every call is pcall-guarded
-- since export names/signatures vary by resource version.
--
-- Self-contained framework access: server.lua's GetPlayer/FWName are locals
-- there, invisible to this file — reaching for them resolved to nil and
-- crashed the whole charge path (the "bank cost doesn't work" bug).

local BFW, BFWName = nil, 'none'
if GetResourceState('qbx_core') == 'started' then BFWName = 'qbx'
elseif GetResourceState('qb-core') == 'started' then BFWName = 'qb'; BFW = exports['qb-core']:GetCoreObject()
elseif GetResourceState('es_extended') == 'started' then BFWName = 'esx'; BFW = exports['es_extended']:getSharedObject()
end

local function BGetPlayer(src)
    if BFWName == 'qbx' then
        local ok, p = pcall(function() return exports.qbx_core:GetPlayer(src) end)
        return ok and p or nil
    elseif BFWName == 'qb' and BFW then return BFW.Functions.GetPlayer(src)
    elseif BFWName == 'esx' and BFW then return BFW.GetPlayerFromId(src) end
    return nil
end

local function tryExport(fn)
    local ok, result = pcall(fn)
    if not ok then return nil end
    return result ~= false
end

function AddBank(src, amount, reason)
    if amount <= 0 then return true end
    reason = reason or 'Redzone'

    if CB and CB.active then
        local r = CB.AddBank(src, amount, reason)
        if r ~= nil then return r ~= false end
    end

    if GetResourceState('Renewed-Banking') == 'started' then
        local r = tryExport(function() return exports['Renewed-Banking']:addAccountMoney(src, amount, reason) end)
        if r ~= nil then return r ~= false end
    end
    if GetResourceState('okokBanking') == 'started' then
        local r = tryExport(function() return exports.okokBanking:AddMoney(src, amount, reason) end)
        if r ~= nil then return r ~= false end
    end
    if GetResourceState('fd_banking') == 'started' then
        local r = tryExport(function() return exports.fd_banking:AddMoney(src, amount, reason) end)
        if r ~= nil then return r ~= false end
    end
    if GetResourceState('qb-banking') == 'started' then
        local r = tryExport(function() return exports['qb-banking']:AddMoney(src, amount, reason) end)
        if r ~= nil then return r ~= false end
    end

    -- Fallback: framework's own bank account.
    local p = BGetPlayer(src)
    if not p then return false end
    if BFWName == 'qbx' or BFWName == 'qb' then
        return tryExport(function() return p.Functions.AddMoney('bank', amount, reason) end) == true
    elseif BFWName == 'esx' then
        return tryExport(function() p.addAccountMoney('bank', amount) return true end) == true
    end
    return false
end

function RemoveBank(src, amount, reason)
    if amount <= 0 then return true end
    reason = reason or 'Redzone'

    if CB and CB.active then
        local r = CB.RemoveBank(src, amount, reason)
        if r ~= nil then return r ~= false end
    end

    if GetResourceState('Renewed-Banking') == 'started' then
        local r = tryExport(function() return exports['Renewed-Banking']:removeAccountMoney(src, amount, reason) end)
        if r ~= nil then return r ~= false end
    end
    if GetResourceState('okokBanking') == 'started' then
        local r = tryExport(function() return exports.okokBanking:RemoveMoney(src, amount, reason) end)
        if r ~= nil then return r ~= false end
    end
    if GetResourceState('fd_banking') == 'started' then
        local r = tryExport(function() return exports.fd_banking:RemoveMoney(src, amount, reason) end)
        if r ~= nil then return r ~= false end
    end
    if GetResourceState('qb-banking') == 'started' then
        local r = tryExport(function() return exports['qb-banking']:RemoveMoney(src, amount, reason) end)
        if r ~= nil then return r ~= false end
    end

    local p = BGetPlayer(src)
    if not p then return false end
    if BFWName == 'qbx' or BFWName == 'qb' then
        local bal = p.Functions.GetMoney and p.Functions.GetMoney('bank') or 0
        if bal < amount then return false end
        return tryExport(function() return p.Functions.RemoveMoney('bank', amount, reason) end) == true
    elseif BFWName == 'esx' then
        local acc = p.getAccount and p.getAccount('bank')
        if acc and acc.money < amount then return false end
        return tryExport(function() p.removeAccountMoney('bank', amount) return true end) == true
    end
    return false
end
