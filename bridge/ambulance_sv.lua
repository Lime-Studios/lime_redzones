-- Self-contained ambulance bridge (server). Auto-detects the running medical
-- script and revives through its own export/event — no external bridge or
-- Community Bridge needed (Community Bridge has no medical module, so revives
-- can never route through it).
--
-- Two separate questions are answered here, and conflating them was the bug
-- behind "Zone revive conflicts with the death system":
--
--   1. Is a death/downed system running?  -> Config.MedicalResources
--      Answers "may I force a native resurrect?". Any listed resource means
--      no, stay hands-off. Wide list, needs no adapter.
--
--   2. How do I revive through it?        -> ADAPTERS below
--      Narrow, verified list. A resource can answer yes to (1) and have no
--      entry here; that's fine and is what the config hooks are for.

-- ── Adapters ────────────────────────────────────────────────────────────
-- revive(src): dispatch the revive. Return false to say "not applicable".
-- Every adapter is called inside pcall by the caller.
--
-- Verified against each script's own docs:
--   wasabi v1 + v2  server export  RevivePlayer(serverId)   (identical in both)
--   qbx_medical     server export  Revive(playerId)
--   qb-ambulancejob client event   hospital:client:Revive
--   esx_ambulancejob client event  esx_ambulancejob:revive
--   ars_ambulancejob client event  ars_ambulancejob:healPlayer, { revive = true }
--   p_ambulancejob  client event   p_ambulancejob/client/death/revive
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
        -- brutal_ambulancejob publishes a client `IsDead` export but documents
        -- no revive entry point — 'brutal_ambulancejob:revive' is a broadcast
        -- it fires AFTER a revive, not a command. Best effort only; if it
        -- doesn't land the verify step below falls through cleanly, and the
        -- startup report tells the owner to set Config.ReviveExport.
        key = 'brutal', label = 'brutal_ambulancejob (best effort)',
        resources = { 'brutal_ambulancejob' },
        bestEffort = true,
        revive = function(src) TriggerClientEvent('brutal_ambulancejob:revive', src) end,
    },
}

-- ── Detection ───────────────────────────────────────────────────────────
local detected      = nil   -- adapter table, or false when none applies
local detectedRes   = nil   -- the actual running resource name
local medicalRes    = nil   -- first running Config.MedicalResources entry, or false

local function started(res)
    return type(res) == 'string' and res ~= '' and GetResourceState(res) == 'started'
end

-- Which config hook (if any) is taking over. Checked first everywhere so a
-- server owner's explicit setting always beats auto-detection.
local function configHook()
    local re = Config.ReviveExport
    if type(re) == 'table' and started(re.resource) then
        return 'export', ('%s:%s()'):format(re.resource, re.export or 'Revive')
    end
    if type(re) == 'table' and type(re.resource) == 'string' and re.resource ~= '' then
        -- Configured but not running — worth surfacing rather than silently ignoring.
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

-- Any death system at all — the "may I force a native resurrect?" question.
local function detectMedical()
    if medicalRes ~= nil then return medicalRes end
    for _, res in ipairs(Config.MedicalResources or {}) do
        if started(res) then medicalRes = res return medicalRes end
    end
    -- An adapter match counts even if the name isn't in the wide list.
    if detectAdapter() then medicalRes = detectedRes return medicalRes end
    medicalRes = false
    return false
end

function MedicalPresentSv() return detectMedical() ~= false end

-- ── Server-side death check ─────────────────────────────────────────────
-- The old code called IsPedDeadOrDying() here. That is a CLIENT-only native —
-- on the server it is nil, so the call raised "attempt to call a nil value",
-- killed the verification thread, and the player was never sent either the
-- teleport or the fallback. They just stayed dead while the client retried.
--
-- Statebags are the portable answer: qbx, wasabi, ars, pScripts and the QB/ESX
-- ambulance jobs all publish one of these on the player. GetEntityHealth is
-- the backstop and IS available server-side.
local DOWN_KEYS = { 'isDead', 'dead', 'inLaststand', 'laststand', 'isDowned', 'downed' }

-- Returns true (down), false (up), or nil (no reliable signal on this side).
-- nil matters: health is NOT a usable liveness test when an ambulance job is
-- installed, because the ones that down you rather than kill you leave the ped
-- at nonzero health the whole time. Treating that as "alive" made the server
-- declare every wasabi revive successful ~250ms after dispatching it, long
-- before it had actually happened.
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

    if detectMedical() then return nil end   -- ped health proves nothing here

    local ped = GetPlayerPed(src)
    if ped and ped ~= 0 then
        local hp = GetEntityHealth(ped)
        if type(hp) == 'number' then return hp <= 0 end
    end
    return nil
end

-- ── Startup report ──────────────────────────────────────────────────────
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
    -- Late-started medical resources are common; give them a moment before we
    -- cache a detection result.
    Wait(4000)
    report()
end)

RegisterCommand('rz_medical', function(src)
    if src ~= 0 then return end   -- console only
    -- Re-detect on demand so this reflects live resource state, not the cache.
    detected, detectedRes, medicalRes = nil, nil, nil
    report()
end, true)

-- ── Revive dispatch ─────────────────────────────────────────────────────
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

    -- The remaining hooks are fire-and-forget; several can be set at once.
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
            -- A death system owns this player and we have no way to drive it.
            -- Forcing a native resurrect here is exactly what started the
            -- revive → re-down fight, so we don't. Tell the owner once.
            if not warnedNoPath then
                warnedNoPath = true
                print('^1[lime_redzones] No revive path for the detected death system — zone revives are disabled.^0')
                print('^1[lime_redzones] Run "rz_medical" in the console for what to set in config.lua.^0')
            end
            TriggerClientEvent('lime_redzones:client:reviveDenied', src, 'noPath')
            return
        end
        -- No death system at all: the client's native resurrect is safe and is
        -- the only thing that will get this player up.
        TriggerClientEvent('lime_redzones:client:doRevive', src, coords, heading)
        return
    end

    -- The revive is away. Who confirms it landed depends on what we can see
    -- from here:
    --
    --   nil  -> no reliable server-side signal (an ambulance job is installed
    --           and publishes no statebag). Hand straight to the client, which
    --           asks that job's own death check and is authoritative. It waits
    --           and only teleports + confirms the charge once genuinely up.
    --   true -> still down; poll until it clears or we run out of budget.
    --
    -- The client never charges for a revive it didn't see land, so handing over
    -- early is safe — and it is what makes the revive feel immediate rather
    -- than waiting out a server-side timer that can't observe anything.
    if IsDownedSv(src) == nil then
        TriggerClientEvent('lime_redzones:client:postReviveTeleport', src, coords, heading)
        return
    end

    CreateThread(function()
        local deadline = GetGameTimer() + (tonumber(Config.ReviveWaitMedical) or 12000)
        while GetGameTimer() < deadline do
            Wait(250)
            if GetPlayerName(src) == nil then return end   -- dropped mid-revive
            if IsDownedSv(src) ~= true then
                TriggerClientEvent('lime_redzones:client:postReviveTeleport', src, coords, heading)
                return
            end
        end
        if type(RZDbgSv) == 'function' then RZDbgSv(('revive(%s) dispatched but never landed'):format(src)) end
        -- Let the client decide: it will wait it out if a death system is
        -- present, or native-resurrect if there genuinely isn't one.
        TriggerClientEvent('lime_redzones:client:doRevive', src, coords, heading)
    end)
end
