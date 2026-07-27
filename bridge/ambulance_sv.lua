local ADAPTERS = {
    {
        key = 'wasabi', label = 'wasabi_ambulance (v1/v2)',
        resources = { 'wasabi_ambulance', 'wasabi_ambulance_v2', 'wasabi_medical' },
        revive = function(src, res) exports[res]:RevivePlayer(src) end,
    },
    {
        key = 'qbx', label = 'qbx_medical',
        resources = { 'qbx_medical', 'qbx_ambulancejob' },
        revive = function(src) exports.qbx_medical:Revive(src) end,
    },
    {
        key = 'qb', label = 'qb-ambulancejob',
        resources = { 'qb-ambulancejob', 'ps-medic', 'tgiann-hospital' },
        revive = function(src) TriggerClientEvent('hospital:client:Revive', src) end,
    },
    {
        key = 'esx', label = 'esx_ambulancejob',
        resources = { 'esx_ambulancejob', 'esx-ambulancejob' },
        revive = function(src) TriggerClientEvent('esx_ambulancejob:revive', src) end,
    },
    {
        key = 'ars', label = 'ars_ambulancejob',
        resources = { 'ars_ambulancejob' },
        revive = function(src) TriggerClientEvent('ars_ambulancejob:healPlayer', src, { revive = true }) end,
    },
    {
        key = 'pScripts', label = 'p_ambulancejob',
        resources = { 'p_ambulancejob' },
        revive = function(src) TriggerClientEvent('p_ambulancejob/client/death/revive', src) end,
    },
    {
        key = 'brutal', label = 'brutal_ambulancejob (best effort)',
        resources = { 'brutal_ambulancejob' },
        bestEffort = true,
        revive = function(src) TriggerClientEvent('brutal_ambulancejob:revive', src) end,
    },
}

local detected      = nil
local detectedRes   = nil
local medicalRes    = nil

local function started(res)
    return type(res) == 'string' and res ~= '' and GetResourceState(res) == 'started'
end

local function configHook()
    local re = Config.ReviveExport
    if type(re) == 'table' and started(re.resource) then
        return 'export', ('%s:%s()'):format(re.resource, re.export or 'Revive')
    end
    if type(re) == 'table' and type(re.resource) == 'string' and re.resource ~= '' then
        return 'export-missing', re.resource
    end
    if type(Config.ReviveCommand) == 'string' and Config.ReviveCommand ~= '' then
        return 'command', Config.ReviveCommand
    end
    if type(Config.ReviveServerEvent) == 'string' and Config.ReviveServerEvent ~= '' then
        return 'serverEvent', Config.ReviveServerEvent
    end
    if type(Config.ReviveClientEvent) == 'string' and Config.ReviveClientEvent ~= '' then
        return 'clientEvent', Config.ReviveClientEvent
    end
    return nil
end

local function detectAdapter()
    if detected ~= nil then return detected end
    local pin = Config.Ambulance
    if pin == 'none' then detected = false return false end
    for _, a in ipairs(ADAPTERS) do
        if pin == 'auto' or pin == nil or pin == a.key then
            for _, res in ipairs(a.resources) do
                if started(res) then
                    detected, detectedRes = a, res
                    return detected
                end
            end
        end
    end
    detected = false
    return false
end

local function detectMedical()
    if medicalRes ~= nil then return medicalRes end
    for _, res in ipairs(Config.MedicalResources or {}) do
        if started(res) then medicalRes = res return medicalRes end
    end
    if detectAdapter() then medicalRes = detectedRes return medicalRes end
    medicalRes = false
    return false
end

function MedicalPresentSv() return detectMedical() ~= false end

local DOWN_KEYS = { 'isDead', 'dead', 'inLaststand', 'laststand', 'isDowned', 'downed' }

function IsDownedSv(src)
    local ok, down = pcall(function()
        local p = Player(src)
        local st = p and p.state
        if not st then return nil end
        for i = 1, #DOWN_KEYS do
            if st[DOWN_KEYS[i]] == true then return true end
        end
        return nil
    end)
    if ok and down == true then return true end

    if detectMedical() then return nil end

    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
        local hp = GetEntityHealth(ped)
        if type(hp) == 'number' then return hp <= 0 end
    end
    return nil
end

local function report(printer)
    printer = printer or print
    local hookKind, hookWhat = configHook()
    local adapter = detectAdapter()
    local med = detectMedical()

    printer('^5[lime_redzones] ── medical / revive setup ───────────────────^0')
    if med then
        printer(('  death system detected : ^2%s^0'):format(med))
    else
        printer('  death system detected : ^3none^0')
    end

    if hookKind == 'export' then
        printer(('  revive path           : ^2Config.ReviveExport -> %s^0'):format(hookWhat))
    elseif hookKind == 'export-missing' then
        printer(('  revive path           : ^1Config.ReviveExport points at "%s" which is NOT started^0'):format(hookWhat))
    elseif hookKind == 'command' then
        printer(('  revive path           : ^2Config.ReviveCommand -> "%s <id>"^0'):format(hookWhat))
    elseif hookKind == 'serverEvent' then
        printer(('  revive path           : ^2Config.ReviveServerEvent -> %s^0'):format(hookWhat))
    elseif hookKind == 'clientEvent' then
        printer(('  revive path           : ^2Config.ReviveClientEvent -> %s^0'):format(hookWhat))
    elseif adapter then
        printer(('  revive path           : ^2built-in adapter "%s" via %s^0'):format(adapter.label, detectedRes))
        if adapter.bestEffort then
            printer('                          ^3(best effort — this script publishes no documented revive API)^0')
        end
    elseif med then
        printer('  revive path           : ^1NONE^0')
        printer(('  ^1"%s" is running but this script has no adapter for it.^0'):format(med))
        printer('  ^1Zone revives will not fire. Set Config.ReviveExport (or one of the^0')
        printer('  ^1other Revive* hooks) in config.lua to point at your revive function.^0')
    else
        printer('  revive path           : ^2native resurrect (no death system installed)^0')
    end

    if Config.Ambulance ~= 'auto' and Config.Ambulance ~= nil then
        printer(('  Config.Ambulance      : pinned to "%s"'):format(tostring(Config.Ambulance)))
    end
    printer('^5[lime_redzones] ─────────────────────────────────────────────^0')
end

CreateThread(function()
    Wait(4000)
    report()
end)

RegisterCommand('rz_medical', function(src)
    if src ~= 0 then return end
    detected, detectedRes, medicalRes = nil, nil, nil
    report()
end, true)

local warnedNoPath = false

local function dispatchRevive(src)
    local hookKind = configHook()

    if hookKind == 'export' then
        local re = Config.ReviveExport
        local ok = pcall(function() exports[re.resource][re.export or 'Revive'](src) end)
        if type(RZDbgSv) == 'function' then
            RZDbgSv(('ReviveExport %s:%s(%s) ok=%s'):format(re.resource, re.export or 'Revive', src, tostring(ok)))
        end
        return ok
    end

    local used = false
    if type(Config.ReviveCommand) == 'string' and Config.ReviveCommand ~= '' then
        pcall(ExecuteCommand, ('%s %s'):format(Config.ReviveCommand, src))
        used = true
    end
    if type(Config.ReviveServerEvent) == 'string' and Config.ReviveServerEvent ~= '' then
        pcall(TriggerEvent, Config.ReviveServerEvent, src)
        used = true
    end
    if type(Config.ReviveClientEvent) == 'string' and Config.ReviveClientEvent ~= '' then
        TriggerClientEvent(Config.ReviveClientEvent, src)
        used = true
    end
    if used then return true end

    local a = detectAdapter()
    if a then
        local ok, err = pcall(a.revive, src, detectedRes)
        if type(RZDbgSv) == 'function' then
            RZDbgSv(('adapter %s revive(%s) ok=%s%s'):format(a.key, src, tostring(ok), ok and '' or (' err=' .. tostring(err))))
        end
        return ok
    end

    return false
end

function DoRevive(src, coords, heading)
    local dispatched = dispatchRevive(src)

    if not dispatched then
        if detectMedical() then
            if not warnedNoPath then
                warnedNoPath = true
                print('^1[lime_redzones] No revive path for the detected death system — zone revives are disabled.^0')
                print('^1[lime_redzones] Run "rz_medical" in the console for what to set in config.lua.^0')
            end
            TriggerClientEvent('lime_redzones:client:reviveDenied', src, 'noPath')
            return
        end
        TriggerClientEvent('lime_redzones:client:doRevive', src, coords, heading)
        return
    end

    if IsDownedSv(src) == nil then
        TriggerClientEvent('lime_redzones:client:postReviveTeleport', src, coords, heading)
        return
    end

    CreateThread(function()
        local deadline = GetGameTimer() + (tonumber(RZOption and RZOption('reviveWaitMedical', 12000)) or 12000)
        while GetGameTimer() < deadline do
            Wait(250)
            if GetPlayerName(src) == nil then return end
            if IsDownedSv(src) ~= true then
                TriggerClientEvent('lime_redzones:client:postReviveTeleport', src, coords, heading)
                return
            end
        end
        if type(RZDbgSv) == 'function' then RZDbgSv(('revive(%s) dispatched but never landed'):format(src)) end
        TriggerClientEvent('lime_redzones:client:doRevive', src, coords, heading)
    end)
end
