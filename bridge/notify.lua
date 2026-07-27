local notifyWarned = false

local function sanitize(message)
    message = tostring(message or '')
    message = message:gsub('~[%a]~', ''):gsub('~n~', ' ')
    message = message:gsub('%s+', ' '):match('^%s*(.-)%s*$') or ''
    if #message > 200 then message = message:sub(1, 197) .. '…' end
    return message
end

local TYPE_MAP = {
    ox      = { info = 'inform',  success = 'success', error = 'error', warning = 'warning' },
    okok    = { info = 'info',    success = 'success', error = 'error', warning = 'warning' },
    mythic  = { info = 'inform',  success = 'success', error = 'error', warning = 'alert'   },
    qb      = { info = 'primary', success = 'success', error = 'error', warning = 'warning' },
}

local function norm(ntype)
    ntype = tostring(ntype or 'info'):lower()
    if ntype ~= 'success' and ntype ~= 'error' and ntype ~= 'warning' then ntype = 'info' end
    return ntype
end

function Notify(message, ntype, duration)
    message = sanitize(message)
    if message == '' then return end
    ntype = norm(ntype)
    duration = math.max(1500, math.min(15000, tonumber(duration) or 5000))

    if GetResourceState('ox_lib') == 'started' then
        local ok = pcall(function()
            exports.ox_lib:notify({ title = 'Lime Zones', description = message, type = TYPE_MAP.ox[ntype], duration = duration })
        end)
        if ok then return end
    end

    if GetResourceState('lime_notify') == 'started' then
        local ok = pcall(function() exports.lime_notify:Notify(message, ntype, duration) end)
        if ok then return end
    end

    if CB and CB.active then
        local ok = pcall(function() exports.community_bridge:SendNotify(message, ntype, duration) end)
        if ok then return end
    end

    if GetResourceState('okokNotify') == 'started' then
        TriggerEvent('okokNotify:Alert', 'Lime Zones', message, duration, TYPE_MAP.okok[ntype])
        return
    end

    if GetResourceState('mythic_notify') == 'started' then
        exports.mythic_notify:SendAlert(TYPE_MAP.mythic[ntype], message, duration)
        return
    end

    if GetResourceState('qbx_core') == 'started' then
        exports.qbx_core:Notify(message, TYPE_MAP.qb[ntype], duration)
        return
    end

    if GetResourceState('qb-core') == 'started' then
        TriggerEvent('QBCore:Notify', message, TYPE_MAP.qb[ntype], duration)
        return
    end

    if GetResourceState('es_extended') == 'started' then
        TriggerEvent('esx:showNotification', message)
        return
    end

    if not notifyWarned then
        notifyWarned = true
        print('^3[lime_redzones] No supported notification resource detected (ox_lib, lime_notify, okokNotify, mythic_notify, qbx_core, qb-core, es_extended). Notifications will not be shown.^0')
    end
end
