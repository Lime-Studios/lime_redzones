CB = { active = false }

CreateThread(function()
    for _ = 1, 40 do
        if GetResourceState('community_bridge') == 'started' then break end
        Wait(250)
    end
    CB.active = GetResourceState('community_bridge') == 'started'
    if CB.active then
        print('^2[lime_redzones] Community Bridge detected — using it for framework, inventory, banking and notifications.^0')
    else
        print('^3[lime_redzones] Community Bridge not found — using built-in bridges.^0')
    end
end)

local function try(fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok then return nil end
    return res == nil and true or res
end

function CB.AddCash(src, amount)
    if not CB.active then return nil end
    return try(function() return exports.community_bridge:AddAccountBalance(src, 'cash', amount) end)
end

function CB.RemoveCash(src, amount)
    if not CB.active then return nil end
    return try(function() return exports.community_bridge:RemoveAccountBalance(src, 'cash', amount) end)
end

function CB.AddBank(src, amount, reason)
    if not CB.active then return nil end
    return try(function() return exports.community_bridge:AddAccountBalance(src, 'bank', amount, reason) end)
end

function CB.RemoveBank(src, amount, reason)
    if not CB.active then return nil end
    return try(function() return exports.community_bridge:RemoveAccountBalance(src, 'bank', amount, reason) end)
end

function CB.AddItem(src, item, amount)
    if not CB.active then return nil end
    return try(function() return exports.community_bridge:AddItem(src, item, amount) end)
end

function CB.GetPlayerName(src)
    if not CB.active then return nil end
    return try(function() return exports.community_bridge:GetPlayerName(src) end)
end

function CB.GetIdentifier(src)
    if not CB.active then return nil end
    return try(function() return exports.community_bridge:GetPlayerIdentifier(src) end)
end

function CB.Notify(src, message, ntype)
    if not CB.active then return nil end
    return try(function() return exports.community_bridge:SendNotify(src, message, ntype) end)
end
