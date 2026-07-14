local notifyWarned = false
local limeFn = nil

local function s(v)
    if type(v) == 'string' then return v end
    if type(v) == 'number' then return tostring(v) end
    if v == nil then return '' end
    return tostring(v)
end

local function tryLime(message, ntype, duration)
    message, ntype, duration = s(message), s(ntype), tonumber(duration) or 4000

    local candidates = {
        function() exports.lime_notify:Notify(message, ntype, duration) end,
        function() exports.lime_notify:SendNotify(message, ntype, duration) end,
        function() exports.lime_notify:notify({ title = 'Redzone', description = message, message = message, type = ntype, duration = duration }) end,
        function() exports.lime_notify:Notify({ title = 'Redzone', description = message, message = message, type = ntype, duration = duration }) end,
        function() exports.lime_notify:SendNotify({ title = 'Redzone', description = message, message = message, type = ntype, duration = duration }) end,
        function() exports.lime_notify:ShowNotification(message, ntype, duration) end,
        function() TriggerEvent('lime_notify:notify', { message = message, description = message, type = ntype, duration = duration }) end,
    }

    if limeFn then
        if pcall(candidates[limeFn]) then return true end
        limeFn = nil
    end
    for i, fn in ipairs(candidates) do
        if pcall(fn) then limeFn = i return true end
    end
    return false
end

function Notify(message, ntype, duration)
    message  = s(message)
    if message == '' then return end
    ntype    = (ntype ~= nil and ntype ~= '') and s(ntype) or 'info'
    duration = tonumber(duration) or 4000

    if GetResourceState('ox_lib') == 'started' then
        local t = ntype == 'info' and 'inform' or ntype
        if pcall(function() lib.notify({ title = 'Redzone', description = message, type = t, duration = duration }) end) then return end
    end
    if GetResourceState('lime_notify') == 'started' and tryLime(message, ntype, duration) then return end
    if GetResourceState('okokNotify') == 'started' then
        if pcall(function() exports['okokNotify']:Alert('Redzone', message, duration, ntype) end) then return end
    end
    if GetResourceState('mythic_notify') == 'started' then
        local t = ntype == 'info' and 'inform' or ntype
        if pcall(function() exports['mythic_notify']:DoHudText(t, message) end) then return end
    end
    if GetResourceState('qbx_core') == 'started' then
        if pcall(function() exports.qbx_core:Notify(message, ntype == 'info' and 'primary' or ntype, duration) end) then return end
    end
    if GetResourceState('qb-core') == 'started' then
        if pcall(function() exports['qb-core']:GetCoreObject().Functions.Notify(message, ntype == 'info' and 'primary' or ntype, duration) end) then return end
    end
    if GetResourceState('es_extended') == 'started' then
        TriggerEvent('esx:showNotification', message)
        return
    end

    -- No external notification resource found. This script uses external
    -- notifications only (no built-in/native notify). Warn once so the
    -- server owner knows to install/start a supported notify resource.
    if not notifyWarned then
        notifyWarned = true
        print('^3[lime_redzones] No supported notification resource detected (ox_lib, lime_notify, okokNotify, mythic_notify, qbx_core, qb-core, es_extended). Notifications will not be shown.^0')
    end
end
