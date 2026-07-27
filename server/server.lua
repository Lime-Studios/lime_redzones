local FW, FWName = nil, 'none'
if GetResourceState('qbx_core') == 'started' then FWName = 'qbx'
elseif GetResourceState('qb-core') == 'started' then FW, FWName = exports['qb-core']:GetCoreObject(), 'qb'
elseif GetResourceState('es_extended') == 'started' then FW, FWName = exports['es_extended']:getSharedObject(), 'esx' end

local HasSQL = GetResourceState('oxmysql') == 'started'

local function RefreshSQL()
    HasSQL = GetResourceState('oxmysql') == 'started'
    return HasSQL
end

local Data = {
    zones = {}, customGangs = {}, nextZoneId = 1,
    gangs = {}, gangOf = {}, nextGangId = 1,
    lb       = { players = {}, gangs = {} },
    globalLb = { players = {} },
    podiums  = {},
    nextPodiumId = 1,
    pendingPrizes = {},
    prizeHistory = {},
    settings = {
        reset       = { enabled = false, day = 0, hour = 18, prizeName = 'money', prizeAmount = 50000, lastReset = 0, resetElo = false },
        globalReset = { enabled = false, day = 0, hour = 18, prizeName = 'money', prizeAmount = 25000, lastReset = 0, resetElo = false },
        elo = {
            enabled = true, start = 1000, floor = 0,
            kNew = 48, kMid = 32, kHigh = 20,
            provisional = 30, highAt = 5000,
            streakFrom = 3, streakStep = 3, streakCap = 30,
            kdBoostMax = 0.25,
        },
        eloRanks = {
            { min = 0,    name = 'Unranked',    color = '#6B7280' },
            { min = 1000, name = 'Bronze I',    color = '#B07A4A' },
            { min = 1500, name = 'Bronze II',   color = '#B07A4A' },
            { min = 2000, name = 'Silver I',    color = '#C2C8D2' },
            { min = 2500, name = 'Silver II',   color = '#C2C8D2' },
            { min = 3000, name = 'Gold I',      color = '#E8B341' },
            { min = 3500, name = 'Gold II',     color = '#E8B341' },
            { min = 4000, name = 'Platinum I',  color = '#5FD3C4' },
            { min = 4500, name = 'Platinum II', color = '#5FD3C4' },
            { min = 5000, name = 'Diamond I',   color = '#6AA9FF' },
            { min = 5500, name = 'Diamond II',  color = '#6AA9FF' },
            { min = 6000, name = 'Elite I',     color = '#B98CFF' },
            { min = 6500, name = 'Elite II',    color = '#B98CFF' },
            { min = 7000, name = 'Legend',      color = '#FF6B6B' },
        },
        options     = {
            rewardNotify = true, streakAnnounce = true, renderDistance = 120,
            leaderboardEnabled = true, globalLbEnabled = true,
            streaksEnabled = true, personalColorEnabled = true,
            personalColorOpacity = true, personalColorHue = true,
            gangLbEnabled = true, killFeedEnabled = true, killCamEnabled = true, killMessageEnabled = true,
            gangMode = 'framework',
            gangMaxMembers = 10, gangCreateCost = 0, gangCreateCostSource = 'cash',
            gangInviteExpiry = 120,
            hudDefaultPreset = 'top', hudDefaultTheme = 'lime',
            hudDefaults = {
                theme = 'lime', preset = 'top', scale = 1.0, pos = false,
                szPos = false,
                kfTheme = 'inherit', kfScale = 1.0, kfPos = false,
                kmTheme = 'inherit', kmScale = 1.0, kmPos = false,
                lock = false,
            },
            reviveWaitMedical = 12000, reviveWaitNative = 4000,
            nativeReviveFallback = true,
            tabletProp = 'prop_cs_tablet',
            tabletAnimDict = 'amb@code_human_in_bus_passenger_idles@female@tablet@base',
            tabletAnimName = 'base',
            logColor = 10672181,
            debugMode = false,
            keybinds = {
                leaderboard = { enabled = true,  key = 'F1' },
                admin       = { enabled = false, key = 'F6' },
                hudMove     = { enabled = false, key = 'F7' },
            },
            customTheme = { accent = '#A3E635', text = nil },
            killFeedDuration = 6000, killCamDuration = 5000,
            lbCols = { kills = true, deaths = true, kd = true, streak = false },
        },
        logs = {
            enabled = true,
            categories = { admin = true, kills = false, revives = true },
            retentionDays = 14,
            webhooks = { admin = '', kills = '', revives = '', leaderboardRz = '', leaderboardGlobal = '' },
            leaderboardPost = { enabled = false, board = 'redzone', interval = 30, top = 10 },
        },
        admins      = {},
        ranks       = {
            { name = 'Moderator', perms = { zones = false, gangs = false, leaderboards = true, options = false, killfeed = false, logs = false } },
            { name = 'Admin',     perms = { zones = true,  gangs = true,  leaderboards = true, options = true,  killfeed = true,  logs = true } },
        },
    },
}

local saveQueued = false
local function WriteNow()
    if not HasSQL then
        print('^3[lime_redzones] WriteNow skipped — no SQL. Data is NOT persisting.^0')
        return
    end
    exports.oxmysql:update('UPDATE lime_redzones SET data = ? WHERE id = 1', { json.encode(Data) }, function(affected)
        if affected == 0 then
            exports.oxmysql:insert('INSERT INTO lime_redzones (id, data) VALUES (1, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)', { json.encode(Data) })
        end
    end)
end

function SaveData()
    if saveQueued then return end
    saveQueued = true
    SetTimeout(2000, function()
        saveQueued = false
        WriteNow()
    end)
end

function SaveDataNow()
    saveQueued = false
    WriteNow()
end

local ATOMIC_SETTINGS = { eloRanks = true, ranks = true, admins = true }

local function deepMerge(target, src)
    for k, v in pairs(src) do
        if ATOMIC_SETTINGS[k] then
            target[k] = v
        elseif type(v) == 'table' and type(target[k]) == 'table' then
            deepMerge(target[k], v)
        else
            target[k] = v
        end
    end
end

local function ApplyLoaded(parsed)
    if type(parsed) ~= 'table' then return end
    for k, v in pairs(parsed) do
        if k == 'settings' and type(v) == 'table' then
            deepMerge(Data.settings, v)
        else
            Data[k] = v
        end
    end
    local saved = parsed.settings and parsed.settings.options
    if type(saved) == 'table' and type(saved.hudDefaults) ~= 'table' then
        local d = Data.settings.options.hudDefaults
        if type(saved.hudDefaultTheme) == 'string' then d.theme = saved.hudDefaultTheme end
        if type(saved.hudDefaultPreset) == 'string' then d.preset = saved.hudDefaultPreset end
    end
end

local function MergeConfigAdmins()
    if type(Config.Admins) ~= 'table' then return end
    Data.settings.admins = Data.settings.admins or {}
    for _, a in ipairs(Config.Admins) do
        local found = false
        for _, e in ipairs(Data.settings.admins) do
            if (type(e) == 'table' and e.id or e) == (type(a) == 'table' and a.id or a) then found = true break end
        end
        if not found then Data.settings.admins[#Data.settings.admins+1] = a end
    end
end

local function SeedIfEmpty() end

local function LoadData(done)
    RefreshSQL()
    if not HasSQL then
        print('^1[lime_redzones] oxmysql not started — running in-memory (data will NOT persist). Add oxmysql as a dependency.^0')
        SeedIfEmpty()
        MergeConfigAdmins()
        done()
        return
    end
    if HasSQL then

        exports.oxmysql:query([[
            CREATE TABLE IF NOT EXISTS lime_redzones (
                id INT PRIMARY KEY,
                data LONGTEXT
            )
        ]], {}, function()
            exports.oxmysql:scalar('SELECT data FROM lime_redzones WHERE id = 1', {}, function(raw)
                if raw then
                    local ok, parsed = pcall(json.decode, raw)
                    if ok then ApplyLoaded(parsed) end
                    SeedIfEmpty()
                    MergeConfigAdmins()
                    done()
                else
                    exports.oxmysql:scalar([[
                        SELECT COUNT(*) FROM information_schema.tables
                        WHERE table_schema = DATABASE() AND table_name = 'lime_zones'
                    ]], {}, function(exists)
                        local function finishFresh()
                            local fileRaw = LoadResourceFile(GetCurrentResourceName(), 'data.json')
                            if fileRaw and fileRaw ~= '' and fileRaw ~= '{}' then
                                local ok, parsed = pcall(json.decode, fileRaw)
                                if ok then ApplyLoaded(parsed) end
                            end
                            SeedIfEmpty()
                            MergeConfigAdmins()
                            exports.oxmysql:insert('INSERT INTO lime_redzones (id, data) VALUES (1, ?)', { json.encode(Data) }, function()
                                done()
                            end)
                        end

                        if (tonumber(exists) or 0) > 0 then
                            exports.oxmysql:scalar('SELECT data FROM lime_zones WHERE id = 1', {}, function(legacy)
                                if legacy then
                                    local ok, parsed = pcall(json.decode, legacy)
                                    if ok then
                                        ApplyLoaded(parsed)
                                        print('^2[lime_redzones] Migrated data from interim lime_zones table.^0')
                                    end
                                end
                                finishFresh()
                            end)
                        else
                            finishFresh()
                        end
                    end)
                end
            end)
        end)
    end
end

local function GetPlayer(src)
    if FWName == 'qbx' then return exports.qbx_core:GetPlayer(src)
    elseif FWName == 'qb' then return FW.Functions.GetPlayer(src)
    elseif FWName == 'esx' then return FW.GetPlayerFromId(src) end
end

local function FmtPrize(name, amount)
    if name == 'money' then return '$' .. amount end
    if name == 'bank' or name == 'bankmoney' then return '$' .. amount .. ' (bank)' end
    return amount .. 'x ' .. tostring(name)
end

local function GetPName(src)
    if CB and CB.active then
        local n = CB.GetPlayerName(src)
        if type(n) == 'string' and n ~= '' then return n end
    end
    local p = GetPlayer(src)
    if p then
        if FWName == 'qbx' or FWName == 'qb' then
            local ci = p.PlayerData.charinfo
            local n = (('%s %s'):format(ci.firstname or '', ci.lastname or '')):match('^%s*(.-)%s*$')
            if n ~= '' then return n end
        elseif FWName == 'esx' then return p.getName() end
    end
    return GetPlayerName(src) or ('Player ' .. src)
end

local function RemoveCash(src, amount)
    if amount <= 0 then return true end
    if CB and CB.active then
        local r = CB.RemoveCash(src, amount)
        if r ~= nil then return r ~= false end
    end
    local p = GetPlayer(src)
    if not p then return FWName == 'none' end
    if FWName == 'qbx' or FWName == 'qb' then
        local cash = p.Functions.GetMoney and p.Functions.GetMoney('cash') or 0
        if cash >= amount then
            return p.Functions.RemoveMoney('cash', amount, 'redzone') ~= false
        end
        local ok, removed = pcall(function() return p.Functions.RemoveItem('money', amount) end)
        return ok and removed == true
    elseif FWName == 'esx' then
        if p.getMoney() >= amount then p.removeMoney(amount) return true end
        return false
    end
    return false
end

local function AddCash(src, amount)
    if amount <= 0 then return end
    if CB and CB.active and CB.AddCash(src, amount) then return end
    local p = GetPlayer(src)
    if not p then return end
    if FWName == 'qbx' or FWName == 'qb' then p.Functions.AddMoney('cash', amount, 'redzone')
    elseif FWName == 'esx' then p.addMoney(amount) end
end

local function GiveItem(src, item, amount)
    if item == 'money' or item == 'cash' then AddCash(src, amount) return true end
    if item == 'bank' or item == 'bankmoney' then return AddBank and AddBank(src, amount, 'Redzone Reward') or false end
    if CB and CB.active then
        local r = CB.AddItem(src, item, amount)
        if r ~= nil and r ~= false then return true end
    end
    if not InvIsFramework() and InvAddItem(src, item, amount) then return true end
    local p = GetPlayer(src)
    if not p then return false end
    if FWName == 'qbx' or FWName == 'qb' then
        return pcall(function() p.Functions.AddItem(item, amount) end)
    elseif FWName == 'esx' then
        return pcall(function() p.addInventoryItem(item, amount) end)
    end
    return false
end

local function GangMode()
    local m = Data.settings.options.gangMode
    if m == 'player' or m == 'off' then return m end
    return 'framework'
end

local function FrameworkGang(src)
    local p = GetPlayer(src)
    if p then
        if FWName == 'qbx' or FWName == 'qb' then
            local pd = p.PlayerData
            if pd.gang and pd.gang.name and pd.gang.name ~= 'none' then
                return { name = pd.gang.name, label = pd.gang.label or pd.gang.name }
            end
            if pd.job and pd.job.type == 'gang' then
                return { name = pd.job.name, label = pd.job.label or pd.job.name }
            end
        elseif FWName == 'esx' then
            local job = p.job
            if job and job.type == 'gang' then return { name = job.name, label = job.label or job.name } end
        end
    end
    return nil
end

function PlayerGangOf(identifier)
    if not identifier then return nil end
    local gid = Data.gangOf[identifier]
    if not gid then return nil end
    local g = Data.gangs[gid]
    if not g then Data.gangOf[identifier] = nil return nil end
    return g
end

local function GetIdentifier(src)
    local p = GetPlayer(src)
    if p and (FWName == 'qbx' or FWName == 'qb') then
        local cid = p.PlayerData and p.PlayerData.citizenid
        if cid then return cid end
    end
    return GetPlayerIdentifierByType(src, 'license') or ('src:' .. tostring(src))
end

local function GetGang(src)
    local mode = GangMode()
    if mode == 'off' then return nil end
    if mode == 'player' then
        local g = PlayerGangOf(GetIdentifier(src))
        if g then return { name = g.id, label = g.label } end
        return nil
    end
    return FrameworkGang(src)
end

local function FrameworkIsAdmin(src)
    if FWName == 'qbx' then
        local ok, isGod = pcall(function() return exports.qbx_core:HasPermission(src, 'god') end)
        if ok and isGod then return true end
        local ok2, isAdmin = pcall(function() return exports.qbx_core:HasPermission(src, 'admin') end)
        if ok2 and isAdmin then return true end
        local ok3, grp = pcall(function()
            local p = exports.qbx_core:GetPlayer(src)
            return p and p.PlayerData and p.PlayerData.group
        end)
        if ok3 and (grp == 'god' or grp == 'admin') then return true end
        return false
    elseif FWName == 'qb' then
        if not FW then return false end
        local ok, res = pcall(function()
            return FW.Functions.HasPermission(src, 'god') or FW.Functions.HasPermission(src, 'admin')
        end)
        if ok and res then return true end
        local ok2, res2 = pcall(function() return FW.Functions.HasPermission(src, { 'god', 'admin' }) end)
        if ok2 and res2 then return true end
        local ok3, perm = pcall(function() return FW.Functions.GetPermission(src) end)
        if ok3 and (perm == 'god' or perm == 'admin') then return true end
        return false
    elseif FWName == 'esx' then
        local ok, grp = pcall(function()
            local p = GetPlayer(src)
            return p and p.getGroup and p.getGroup()
        end)
        if ok and (grp == 'god' or grp == 'admin' or grp == 'superadmin') then return true end
        return false
    end
    return false
end

local function IsAdmin(src)
    if src == 0 then return true end

    if IsPlayerAceAllowed(src, 'lime_redzones.admin')
        or IsPlayerAceAllowed(src, 'lime_redzones.god')
        or IsPlayerAceAllowed(src, 'god')
        or IsPlayerAceAllowed(src, 'command') then return true end

    local lic = GetPlayerIdentifierByType(src, 'license')
    local id  = GetIdentifier(src)
    for _, a in ipairs(Data.settings.admins or {}) do
        local aid = type(a) == 'table' and a.id or a
        if aid == lic or aid == id then return true end
    end

    return FrameworkIsAdmin(src)
end

local function PlayerDistFromZone(src, zone)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    local pos = GetEntityCoords(ped)
    if not pos or (pos.x == 0.0 and pos.y == 0.0 and pos.z == 0.0) then return nil end
    return #(pos - vector3(zone.coords.x, zone.coords.y, zone.coords.z))
end

local function PointInPoly(x, y, poly)
    local inside, n = false, #poly
    local j = n
    for i = 1, n do
        local xi, yi = poly[i].x, poly[i].y
        local xj, yj = poly[j].x, poly[j].y
        if ((yi > y) ~= (yj > y)) and (x < (xj - xi) * (y - yi) / ((yj - yi) ~= 0 and (yj - yi) or 1e-9) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

local function PlayerInZone(src, zone, slack)
    local dist = PlayerDistFromZone(src, zone)
    if dist == nil then return true end

    if type(zone.poly) == 'table' and #zone.poly >= 3 then
        local ped = GetPlayerPed(src)
        if ped == 0 then return true end
        local p = GetEntityCoords(ped)
        if zone.polyMinZ and p.z < (zone.polyMinZ - (slack or 30.0)) then return false end
        if zone.polyMaxZ and p.z > (zone.polyMaxZ + (slack or 30.0)) then return false end
        if PointInPoly(p.x, p.y, zone.poly) then return true end
        return dist <= (slack or 30.0)
    end

    return dist <= (zone.radius + (slack or 30.0))
end

local function PlayerInAnyZone(src, slack)
    for _, z in pairs(Data.zones) do
        if z.enabled and PlayerInZone(src, z, slack) then return true end
    end
    return false
end

ADMIN_SECTIONS = { 'zones', 'gangs', 'leaderboards', 'options', 'killfeed', 'logs' }

local function AllSections(full)
    local t = {}
    for _, k in ipairs(ADMIN_SECTIONS) do t[k] = true end
    if full then t._full = true end
    return t
end

local function GetAdminPerms(src)
    if src == 0
        or IsPlayerAceAllowed(src, 'lime_redzones.god')
        or IsPlayerAceAllowed(src, 'god')
        or FrameworkIsAdmin(src) then
        return AllSections(true)
    end

    local lic = GetPlayerIdentifierByType(src, 'license')
    local id  = GetIdentifier(src)
    for _, a in ipairs(Data.settings.admins or {}) do
        if type(a) == 'table' and (a.id == lic or a.id == id) and a.rank then
            for _, r in ipairs(Data.settings.ranks or {}) do
                if r.name == a.rank then return r.perms end
            end
        end
    end

    return AllSections(false)
end

local function HasPerm(src, section)
    if not IsAdmin(src) then return false end
    local perms = GetAdminPerms(src)
    if perms._full then return true end
    return perms[section] == true
end

local function BroadcastZones(target)
    TriggerClientEvent('lime_redzones:client:syncZones', target or -1, Data.zones,
        tonumber(Data.settings.options.renderDistance) or 120)
end

local streaks, lastKill, lastDeath, lastGlobal, lastRevive = {}, {}, {}, {}, {}
local reviveInFlight = {}
local reviveTpAck = {}
local playerInSafeZone = {}
local panelOpen = {}
local pendingReviveCharge = {}
local lastRequest = {}

local function reqOk(src, gap, key)
    key = key or 'default'
    lastRequest[src] = lastRequest[src] or {}
    local now = GetGameTimer() / 1000.0
    if lastRequest[src][key] and (now - lastRequest[src][key]) < (gap or 0.5) then return false end
    lastRequest[src][key] = now
    return true
end

local function cap(t, n) local r = {} for i = 1, math.min(n, #t) do r[i] = t[i] end return r end

local DAY_NAMES = { [0]='Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday' }

local function ResetInfo(cfg)
    if not cfg or not cfg.enabled then return nil end
    return {
        enabled = true,
        label   = ('%s %02d:00'):format(DAY_NAMES[cfg.day] or 'Sunday', cfg.hour or 18),
        prize   = cfg.prizeAmount > 0 and {
            name = cfg.prizeName, amount = cfg.prizeAmount
        } or nil,
    }
end

local function WeaponLabel(w)
    w = tonumber(w)
    if not w then return 'Weapon' end
    return (Config.WeaponNames and Config.WeaponNames[w]) or 'Weapon'
end

local lbDirty = false
PodiumsDirty = false
local function PushLeaderboard(target)
    if target == nil or target == -1 then
        lbDirty = true
        PodiumsDirty = true
        return
    end
    PushLeaderboardNow(target)
end

function PushLeaderboardNow(target)
    local pList, gList, glList = {}, {}, {}
    local rzKills, rzDeaths = 0, 0
    local glKills, glDeaths = 0, 0

    for id, d in pairs(Data.lb.players) do
        pList[#pList+1] = { id = id, name = d.name, kills = d.kills, deaths = d.deaths, elo = d.elo }
        rzKills, rzDeaths = rzKills + d.kills, rzDeaths + d.deaths
    end
    table.sort(pList, function(a, b) return a.kills > b.kills end)

    for _, d in pairs(Data.lb.gangs) do
        gList[#gList+1] = { label = d.label, kills = d.kills, deaths = d.deaths }
    end
    table.sort(gList, function(a, b) return a.kills > b.kills end)

    for id, d in pairs(Data.globalLb.players) do
        glList[#glList+1] = { id = id, name = d.name, kills = d.kills, deaths = d.deaths, elo = d.elo }
        glKills, glDeaths = glKills + d.kills, glDeaths + d.deaths
    end
    table.sort(glList, function(a, b) return a.kills > b.kills end)

    TriggerClientEvent('lime_redzones:client:updateLeaderboard', target or -1,
        cap(pList, 30), cap(gList, 30), cap(glList, 30),
        {
            kills = rzKills, deaths = rzDeaths, players = #pList,
            globalKills = glKills, globalDeaths = glDeaths, globalPlayersCount = #glList,
            reset = ResetInfo(Data.settings.reset),
            globalReset = ResetInfo(Data.settings.globalReset),
            cols = Data.settings.options.lbCols,
            gangLb = Data.settings.options.gangLbEnabled ~= false,
            options = Data.settings.options,
        })
end

CreateThread(function()
    while true do
        Wait(2000)
        if lbDirty then
            lbDirty = false
            PushLeaderboardNow(-1)
        end
    end
end)

local function EnsureP(store, src)
    local id = GetIdentifier(src)
    if not id then return { name = GetPName(src), kills = 0, deaths = 0 } end
    store[id] = store[id] or { name = GetPName(src), kills = 0, deaths = 0 }
    store[id].name = GetPName(src)
    return store[id]
end

local function GrantPrizeOrQueue(identifier, name, amount)

    for _, sid in ipairs(GetPlayers()) do
        local src = tonumber(sid)
        if GetIdentifier(src) == identifier then
            GiveItem(src, name, amount)
            NotifySv(src, ('🏆 Leaderboard winner! Prize: %s'):format(
                FmtPrize(name, amount)), 'success')
            return
        end
    end
    Data.pendingPrizes[identifier] = { name = name, amount = amount }
end

local function DoReset(which)
    local cfg = Data.settings[which]
    local store = which == 'reset' and Data.lb.players or Data.globalLb.players
    local boardName = which == 'reset' and 'Redzone' or 'Global'
    local logCat = which == 'reset' and 'leaderboardRz' or 'leaderboardGlobal'

    local top, topKills = nil, -1
    for id, d in pairs(store) do
        if d.kills > topKills then top, topKills = id, d.kills end
    end
    local winnerName = (top and store[top] and store[top].name) or nil
    local hasWinner = top and topKills > 0

    if hasWinner and cfg.prizeAmount and cfg.prizeAmount > 0 then
        GrantPrizeOrQueue(top, cfg.prizeName or 'money', cfg.prizeAmount)
        Data.prizeHistory = Data.prizeHistory or {}
        table.insert(Data.prizeHistory, 1, {
            board = which == 'reset' and 'redzone' or 'global',
            name = winnerName or 'Unknown',
            identifier = top,
            prize = { name = cfg.prizeName or 'money', amount = cfg.prizeAmount },
            kills = topKills,
            time = os.time(),
        })
        while #Data.prizeHistory > 50 do table.remove(Data.prizeHistory) end
    end

    if Log then
        local desc, fields
        if hasWinner then
            desc = ('🏆 **%s** won the weekly %s leaderboard with **%d kills**!'):format(winnerName or 'Unknown', boardName, topKills)
            fields = {}
            if cfg.prizeAmount and cfg.prizeAmount > 0 then
                fields[#fields+1] = { name = 'Prize', value = FmtPrize(cfg.prizeName, cfg.prizeAmount), inline = true }
            end
            fields[#fields+1] = { name = 'Kills', value = tostring(topKills), inline = true }
        else
            desc = ('The weekly %s leaderboard reset — no kills were recorded this week.'):format(boardName)
        end
        Log(logCat, ('🔄 %s Leaderboard Reset'):format(boardName), desc, fields)
    end

    local resetElo = cfg.resetElo == true
    local kept = {}
    for id, d in pairs(store) do
        if resetElo then d.elo = nil end
        if d.elo ~= nil or d.appearance ~= nil then
            d.kills, d.deaths = 0, 0
            kept[id] = d
        end
    end
    if which == 'reset' then Data.lb = { players = kept, gangs = {} }
    else Data.globalLb = { players = kept } end

    cfg.lastReset = os.time()
    SaveData()
    PushLeaderboard(-1)
    if resetElo and PushEloAll then PushEloAll() end
    print(('[lime_redzones] %s leaderboard reset complete (Elo %s).')
        :format(boardName, resetElo and 'cleared' or 'kept'))
end

CreateThread(function()
    while true do
        Wait(60000)
        local now = os.date('*t')
        for _, which in ipairs({ 'reset', 'globalReset' }) do
            local cfg = Data.settings[which]
            if cfg and cfg.enabled
                and now.wday - 1 == (cfg.day or 0)
                and now.hour == (cfg.hour or 18)
                and (os.time() - (cfg.lastReset or 0)) > 3700 then
                DoReset(which)
            end
        end
    end
end)

AddEventHandler('playerJoining', function()
    local src = source
    SetTimeout(15000, function()
        local id = GetIdentifier(src)
        local prize = Data.pendingPrizes[id]
        if prize then
            Data.pendingPrizes[id] = nil
            GiveItem(src, prize.name, prize.amount)
            NotifySv(src, ('🏆 Leaderboard winner! Prize: %s'):format(
                FmtPrize(prize.name, prize.amount)), 'success')
            SaveData()
        end
    end)
end)

local RZ_DEBUG_SV = GetConvar('lime_redzones_debug', 'false') == 'true'
local function dbgsv(...) if RZ_DEBUG_SV then print('[lime_redzones:sv]', ...) end end
function RZDbgSv(msg)
    if RZ_DEBUG_SV or (Data and Data.settings and Data.settings.options and Data.settings.options.debugMode == true) then
        print('[lime_redzones:sv] ' .. tostring(msg))
    end
end

local clientDbgLast = {}
RegisterNetEvent('lime_redzones:server:clientDebug', function(msg)
    local src = source
    if not (RZ_DEBUG_SV or Data.settings.options.debugMode == true) then return end
    if type(msg) ~= 'string' then return end
    local now = GetGameTimer()
    local b = clientDbgLast[src]
    if b and (now - b.at) < 1000 then
        b.n = b.n + 1
        if b.n > 10 then return end
    else
        clientDbgLast[src] = { at = now, n = 1 }
    end
    print(('[lime_redzones:client %s|%s] %s'):format(src, GetPName(src), msg:sub(1, 256)))
end)

local function RewardAmount(it)
    if it.rand and it.min and it.max then return math.random(it.min, it.max) end
    return tonumber(it.amount) or 1
end

RegisterNetEvent('lime_redzones:server:giveKillReward', function(zoneId, victimId, weapon)
    local src  = source
    if zoneId == nil then return end
    zoneId = tostring(zoneId)
    victimId = tonumber(victimId) or 0
    weapon = tonumber(weapon) or 0
    local zone = Data.zones[zoneId]
    dbgsv(('giveKillReward from %s zone=%s exists=%s'):format(src, zoneId, tostring(zone ~= nil)))
    if not zone or not zone.enabled then dbgsv('rejected: no/disabled zone') return end
    if zone.type == 'safezone' then dbgsv('rejected: safe zone') return end

    if victimId <= 0 then dbgsv('rejected: victim not a resolved player (NPC)') return end
    if GetPlayerName(victimId) == nil then dbgsv('rejected: victim not a connected player') return end
    local vidForElo = victimId

    if victimId > 0 and playerInSafeZone[victimId] then
        dbgsv('rejected: victim in safe zone')
        return
    end

    local now = GetGameTimer() / 1000.0
    if lastKill[src] and (now - lastKill[src]) < 1.5 then dbgsv('rejected: rate limit') return end

    if not PlayerInZone(src, zone, 60.0) then dbgsv('rejected: not in zone') return end
    lastKill[src] = now
    dbgsv('kill accepted, granting rewards')

    streaks[src] = (streaks[src] or 0) + 1
    local streak = streaks[src]

    local parts = {}
    for _, item in ipairs(zone.rewardItems or {}) do
        local amt = RewardAmount(item)
        local granted = GiveItem(src, item.name, amt)
        dbgsv(('reward %s x%s -> %s'):format(item.name, amt, tostring(granted)))
        if granted then
            parts[#parts+1] = FmtPrize(item.name, amt)
        end
    end
    for _, sr in ipairs(zone.streakRewards or {}) do
        if Data.settings.options.streaksEnabled ~= false and tonumber(sr.streak) == streak then
            local amt = RewardAmount(sr)
            if GiveItem(src, sr.name, amt) then
                parts[#parts+1] = ('STREAK %d: %s'):format(streak,
                    FmtPrize(sr.name, amt))
            end
        end
    end
    if #parts > 0 and Data.settings.options.rewardNotify ~= false then
        NotifySv(src, 'Reward: ' .. table.concat(parts, ' · '), 'success')
    end

    local heal = math.max(0, math.min(200, math.floor(tonumber(zone.killHeal) or 0)))
    if heal > 0 or zone.killHealFull == true then
        TriggerClientEvent('lime_redzones:client:killHeal', src, heal, zone.killHealFull == true)
    end

    local lb = EnsureP(Data.lb.players, src)
    lb.kills = lb.kills + 1
    zone.kills = (zone.kills or 0) + 1

    if EloEnabled and EloEnabled() and vidForElo > 0 then
        local victimRec = EnsureP(Data.lb.players, vidForElo)
        local newR, delta, vNew, vDelta, bonus = EloExchange(lb, victimRec, streak)
        if newR then
            local rName, rColor = EloRankOf(newR)
            TriggerClientEvent('lime_redzones:client:elo', src, newR, rName, rColor, delta, bonus)
            local vName, vColor = EloRankOf(vNew)
            TriggerClientEvent('lime_redzones:client:elo', vidForElo, vNew, vName, vColor, vDelta, 0)
        end
    end
    if Data.settings.options.globalLbEnabled ~= false then
        local glb = EnsureP(Data.globalLb.players, src)
        glb.kills = glb.kills + 1
    end
    if Data.settings.options.gangLbEnabled ~= false then
        local gang = GetGang(src)
        if gang then
            Data.lb.gangs[gang.name] = Data.lb.gangs[gang.name] or { label = gang.label, kills = 0, deaths = 0 }
            Data.lb.gangs[gang.name].kills = Data.lb.gangs[gang.name].kills + 1
        end
    end

    TriggerClientEvent('lime_redzones:client:syncStreak', src, streak)
    local vId = tonumber(victimId) or 0
    local victimName = (vId > 0 and GetPlayerName(vId)) and GetPName(vId) or 'Unknown'
    if Data.settings.options.killFeedEnabled ~= false then
        TriggerClientEvent('lime_redzones:client:killFeed', -1, {
            killer = GetPName(src), killerId = src,
            victim = victimName, victimId = vId,
            weapon = WeaponLabel(weapon), streak = streak,
            duration = Data.settings.options.killFeedDuration or 6000,
        })
    end

    if Log then
        Log('kills', 'Redzone Kill',
            ('**%s** killed **%s**'):format(GetPName(src), victimName),
            {
                { name = 'Zone',   value = zone.name or zoneId, inline = true },
                { name = 'Weapon', value = WeaponLabel(weapon), inline = true },
                { name = 'Streak', value = tostring(streak),    inline = true },
            })
    end
    SaveData()
    PushLeaderboard(-1)
    if MaybeSnapshotPublic then MaybeSnapshotPublic(src) end
end)

RegisterNetEvent('lime_redzones:server:reportDeath', function(zoneId)
    local src = source
    if zoneId == nil then return end
    zoneId = tostring(zoneId)
    local zone = Data.zones[zoneId]
    if not zone then return end

    local now = GetGameTimer() / 1000.0
    if lastDeath[src] and (now - lastDeath[src]) < 5.0 then return end
    if not PlayerInZone(src, zone, 50.0) then return end
    lastDeath[src] = now

    reviveInFlight[src] = nil

    streaks[src] = 0
    TriggerClientEvent('lime_redzones:client:syncStreak', src, 0)

    local lb = EnsureP(Data.lb.players, src)
    lb.deaths = lb.deaths + 1
    if Data.settings.options.globalLbEnabled ~= false then
        local glb = EnsureP(Data.globalLb.players, src)
        glb.deaths = glb.deaths + 1
    end
    local gang = GetGang(src)
    if gang then
        Data.lb.gangs[gang.name] = Data.lb.gangs[gang.name] or { label = gang.label, kills = 0, deaths = 0 }
        Data.lb.gangs[gang.name].deaths = Data.lb.gangs[gang.name].deaths + 1
    end
    SaveData()
    PushLeaderboard(-1)
end)

RegisterNetEvent('lime_redzones:server:globalKill', function()
    if Data.settings.options.globalLbEnabled == false then return end
    local src = source
    local now = GetGameTimer() / 1000.0
    if lastGlobal[src] and (now - lastGlobal[src]) < 1.5 then return end
    lastGlobal[src] = now

    local lb = EnsureP(Data.globalLb.players, src)
    lb.kills = lb.kills + 1
    SaveData()
    PushLeaderboard(-1)
    if MaybeSnapshotPublic then MaybeSnapshotPublic(src) end
end)

RegisterNetEvent('lime_redzones:server:globalDeath', function()
    if Data.settings.options.globalLbEnabled == false then return end
    local src = source
    local now = GetGameTimer() / 1000.0
    if lastDeath[src] and (now - lastDeath[src]) < 3.0 then return end
    lastDeath[src] = now
    local lb = EnsureP(Data.globalLb.players, src)
    lb.deaths = lb.deaths + 1
    SaveData()
    PushLeaderboard(-1)
end)

RegisterNetEvent('lime_redzones:server:attemptRevive', function(zoneId, coords, heading)
    local src  = source
    local zone = Data.zones[tostring(zoneId)]
    if not zone then return end

    local now = GetGameTimer() / 1000.0
    if lastRevive[src] and (now - lastRevive[src]) < 3.0 then return end
    lastRevive[src] = now

    if zone.reviveInside == false then
        TriggerClientEvent('lime_redzones:client:reviveDenied', src)
        return
    end

    local maxAway = zone.radius + (tonumber(zone.teleportAway) or 30.0) + 60.0
    local zx, zy, zz = zone.coords.x, zone.coords.y, zone.coords.z
    local cx = coords and tonumber(coords.x)
    local cy = coords and tonumber(coords.y)
    local cz = coords and tonumber(coords.z)
    local valid = cx and cy and cz
        and math.abs(cz - zz) < 80.0
        and (((cx - zx)^2 + (cy - zy)^2) ^ 0.5) <= maxAway
    local exact = (coords and coords.exact == true) or false
    if not valid then
        local away = zone.radius + (tonumber(zone.teleportAway) or 30.0)
        coords = { x = zx + away, y = zy, z = zz, exact = false }
    else
        coords = { x = cx, y = cy, z = cz, exact = exact }
    end
    heading = tonumber(heading) or 0.0

    local cost = tonumber(zone.reviveCost) or 0
    local fromBank = zone.reviveCostSource == 'bank'

    pendingReviveCharge[src] = { cost = cost, fromBank = fromBank, zone = zone.name or tostring(zoneId) }

    if reviveInFlight[src] and (GetGameTimer() - reviveInFlight[src]) < 20000 then
        return
    end
    reviveInFlight[src] = GetGameTimer()

    reviveTpAck[src] = false
    TriggerClientEvent('lime_redzones:client:preReviveTeleport', src, coords, heading)
    CreateThread(function()
        local deadline = GetGameTimer() + 3000
        while GetGameTimer() < deadline and reviveTpAck[src] == false do Wait(100) end
        reviveTpAck[src] = nil
        if GetPlayerName(src) == nil then return end
        DoRevive(src, coords, heading)
    end)
end)

RegisterNetEvent('lime_redzones:server:reviveTeleported', function()
    local src = source
    if reviveTpAck[src] == false then reviveTpAck[src] = true end
end)

RegisterNetEvent('lime_redzones:server:confirmRevive', function()
    local src = source
    reviveInFlight[src] = nil
    local pend = pendingReviveCharge[src]
    if not pend then return end
    pendingReviveCharge[src] = nil
    local cost, fromBank = pend.cost, pend.fromBank
    if cost <= 0 then return end

    local paid
    if fromBank then
        paid = RemoveBank ~= nil and RemoveBank(src, cost, 'Redzone Revive') == true
    else
        paid = RemoveCash(src, cost) == true
    end
    if paid then
        NotifySv(src, ('Revived — $%s deducted%s.'):format(cost, fromBank and ' from bank' or ''), 'success')
        if Log then
            Log('revives', 'Paid Revive', ('**%s** revived'):format(GetPName(src)),
                { { name = 'Zone', value = pend.zone, inline = true },
                  { name = 'Cost', value = '$' .. tostring(cost) .. (fromBank and ' (bank)' or ' (cash)'), inline = true } })
        end
    end
end)

RegisterNetEvent('lime_redzones:server:requestLeaderboard', function()
    local src = source
    if not reqOk(src, 1.0, 'leaderboard') then return end
    if Data.settings.options.leaderboardEnabled == false and not IsAdmin(src) then
        NotifySv(src, 'The leaderboard is currently disabled.', 'error')
        return
    end
    PushLeaderboard(src)
end)
RegisterNetEvent('lime_redzones:server:teleportToZone', function(zoneId)
    local src = source
    if zoneId == nil then return end
    if not reqOk(src, 3.0, 'teleport') then
        NotifySv(src, _U('teleport_cooldown'), 'error')
        return
    end

    local zone = Data.zones[tostring(zoneId)]
    if not zone or not zone.enabled then return end
    if zone.allowTeleport ~= true then
        NotifySv(src, _U('teleport_disabled'), 'error')
        return
    end

    local ped = GetPlayerPed(src)
    if ped == 0 or GetEntityHealth(ped) <= 0 then
        NotifySv(src, _U('teleport_dead'), 'error')
        return
    end

    local cost = tonumber(zone.teleportCost) or 0
    dbgsv(('teleport zone=%s rawCost=%s cost=%d source=%s RemoveBank=%s')
        :format(tostring(zoneId), tostring(zone.teleportCost), cost,
                tostring(zone.teleportCostSource), tostring(RemoveBank ~= nil)))
    if cost > 0 then
        local fromBank = zone.teleportCostSource == 'bank'
        local paid
        if fromBank then
            paid = RemoveBank ~= nil and RemoveBank(src, cost, 'Redzone Teleport') == true
        else
            paid = RemoveCash(src, cost) == true
        end
        dbgsv(('teleport charge fromBank=%s paid=%s'):format(tostring(fromBank), tostring(paid)))
        if not paid then
            NotifySv(src, ('You need $%s %s to teleport here.'):format(cost, fromBank and 'in your bank' or 'in cash'), 'error')
            return
        end
    end

    local dest, exact = zone.coords, false
    local pts = zone.tpPoints
    if type(pts) == 'table' and #pts > 0 then
        dest, exact = pts[math.random(1, #pts)], true
    end

    TriggerClientEvent('lime_redzones:client:teleportTo', src, dest, zone.name, exact)
    NotifySv(src, ('Teleporting to %s%s.'):format(zone.name, cost > 0 and (' — $' .. cost .. ' deducted') or ''), 'success')
    Log('admin', 'Redzone Teleport', ('**%s** teleported to **%s**%s')
        :format(GetPName(src), zone.name, cost > 0 and (' ($' .. cost .. ')') or ''), nil, GetPName(src))
end)

RegisterNetEvent('lime_redzones:server:requestZones', function()
    if not reqOk(source, 1.0, 'zones') then return end
    BroadcastZones(source)
    TriggerClientEvent('lime_redzones:client:syncOptions', source, Data.settings.options)
    if PushPodiums then PushPodiums(source) end
end)

RegisterNetEvent('lime_redzones:server:myIdentifier', function()
    local src = source
    if not IsAdmin(src) then return end
    if not reqOk(src, 1.0, 'myid') then return end
    TriggerClientEvent('lime_redzones:client:myIdentifier', src,
        GetPlayerIdentifierByType(src, 'license') or '', GetIdentifier(src))
end)

RegisterNetEvent('lime_redzones:server:syncSafePresence', function(zoneId)
    local src = source
    if not reqOk(src, 0.4, 'safepresence') then return end

    if zoneId == nil then playerInSafeZone[src] = nil return end

    local z = Data.zones[tostring(zoneId)]
    if not z or z.type ~= 'safezone' or not z.enabled then playerInSafeZone[src] = nil return end

    local ped = GetPlayerPed(src)
    if ped == 0 then playerInSafeZone[src] = nil return end

    local pos = GetEntityCoords(ped)
    local d = #(pos - vector3(z.coords.x, z.coords.y, z.coords.z))
    playerInSafeZone[src] = (d <= (z.radius + 15.0)) and tostring(zoneId) or nil
end)

exports('IsInSafeZone', function(src) return playerInSafeZone[src] ~= nil end)

AddEventHandler('playerDropped', function()
    local src = source
    streaks[src], lastKill[src], lastDeath[src], lastGlobal[src], lastRevive[src], lastRequest[src] = nil, nil, nil, nil, nil, nil
    playerInSafeZone[src] = nil
    panelOpen[src] = nil
    clientDbgLast[src] = nil
    pendingReviveCharge[src] = nil
    reviveInFlight[src] = nil
    reviveTpAck[src] = nil
    if PodiumWatchDropped then PodiumWatchDropped(src) end
end)

RegisterNetEvent('lime_redzones:server:adminTeleportToZone', function(zoneId)
    local src = source
    if not HasPerm(src, 'zones') then NotifySv(src, _U('no_permission'), 'error') return end
    if zoneId == nil then return end
    local zone = Data.zones[tostring(zoneId)]
    if not zone then return end
    Log('admin', 'Admin Teleport', ('**%s** teleported to zone **%s**'):format(GetPName(src), zone.name or '?'), nil, GetPName(src))
    TriggerClientEvent('lime_redzones:client:teleportTo', src, zone.coords, zone.name, false)
end)

RegisterNetEvent('lime_redzones:server:requestAdminData', function()
    local src = source
    if not reqOk(src, 1.0, 'admindata') then return end
    if not IsAdmin(src) then return end
    panelOpen[src] = true
    TriggerClientEvent('lime_redzones:client:adminData', src, Data.zones, Data.customGangs, Data.settings, GetAdminPerms(src),
        PlayerGangList and PlayerGangList() or nil)
end)

local function BroadcastAdminData()
    local gl = PlayerGangList and PlayerGangList() or nil
    for src in pairs(panelOpen) do
        if GetPlayerName(src) and IsAdmin(src) then
            TriggerClientEvent('lime_redzones:client:adminData', src, Data.zones, Data.customGangs, Data.settings, GetAdminPerms(src), gl)
        else
            panelOpen[src] = nil
        end
    end
end

RegisterNetEvent('lime_redzones:server:adminOpen', function()
    local src = source
    if not IsAdmin(src) then NotifySv(src, 'No permission.', 'error') return end
    if not reqOk(src, 1.0, 'adminopen') then return end
    panelOpen[src] = true
    TriggerClientEvent('lime_redzones:client:openAdmin', src, Data.zones, Data.customGangs, Data.settings, GetAdminPerms(src),
        PlayerGangList and PlayerGangList() or nil)
end)

RegisterNetEvent('lime_redzones:server:adminClosed', function()
    panelOpen[source] = nil
end)

local function sanitizeRewards(t, withStreak)
    local out = {}
    if type(t) ~= 'table' then return out end
    for i = 1, math.min(20, #t) do
        local it = t[i]
        if type(it) == 'table' and type(it.name) == 'string' and it.name ~= '' then
            local row = {
                name   = it.name:sub(1, 50),
                amount = math.max(1, math.floor(tonumber(it.amount) or 1)),
            }

            if it.rand and tonumber(it.min) and tonumber(it.max) then
                row.rand = true
                row.min  = math.max(1, math.floor(tonumber(it.min)))
                row.max  = math.max(row.min, math.floor(tonumber(it.max)))
            end
            if withStreak then row.streak = math.max(1, math.floor(tonumber(it.streak) or 1)) end
            out[#out+1] = row
        end
    end
    return out
end

RegisterNetEvent('lime_redzones:server:beginNpcPlacement', function(zoneId)
    local src = source
    if not HasPerm(src, 'zones') then NotifySv(src, _U('no_permission'), 'error') return end
    if zoneId == nil then return end
    local zone = Data.zones[tostring(zoneId)]
    if not zone then NotifySv(src, 'Zone not found.', 'error') return end
    if zone.type == 'safezone' then NotifySv(src, 'Safe zones cannot have teleport NPCs.', 'error') return end
    local ok, copy = pcall(json.decode, json.encode(zone))
    if not ok then return end
    TriggerClientEvent('lime_redzones:client:beginNpcPlacement', src, copy)
end)

RegisterNetEvent('lime_redzones:server:saveZone', function(zone)
    local src = source
    if not HasPerm(src, 'zones') then return end
    if type(zone) ~= 'table' or type(zone.name) ~= 'string' then return end
    if type(zone.coords) ~= 'table' then return end

    local id = zone.id and tostring(zone.id) or tostring(Data.nextZoneId)
    if not zone.id then Data.nextZoneId = Data.nextZoneId + 1 end

    local exits = {}
    if type(zone.exits) == 'table' then
        for i = 1, math.min(5, #zone.exits) do
            local e = zone.exits[i]
            if type(e) == 'table' then
                exits[#exits+1] = { x = tonumber(e.x) or 0, y = tonumber(e.y) or 0, z = tonumber(e.z) or 0 }
            end
        end
    end

    local poly = {}
    if type(zone.poly) == 'table' then
        for i = 1, math.min(24, #zone.poly) do
            local p = zone.poly[i]
            if type(p) == 'table' and tonumber(p.x) and tonumber(p.y) then
                poly[#poly+1] = { x = tonumber(p.x), y = tonumber(p.y) }
            end
        end
    end
    if #poly < 3 then poly = {} end

    if #poly >= 3 then
        local cx, cy, cz, n = 0.0, 0.0, 0.0, #poly
        for _, p in ipairs(poly) do cx, cy = cx + p.x, cy + p.y end
        cx, cy = cx / n, cy / n
        cz = tonumber(zone.polyMinZ) or (type(zone.coords) == 'table' and tonumber(zone.coords.z)) or 30.0
        local maxR = 0.0
        for _, p in ipairs(poly) do
            local d = ((p.x - cx)^2 + (p.y - cy)^2) ^ 0.5
            if d > maxR then maxR = d end
        end
        zone.coords = { x = cx, y = cy, z = cz }
        zone.radius = math.max(10.0, math.ceil(maxR + 5.0))
    end

    local tpPoints = {}
    if type(zone.tpPoints) == 'table' then
        for i = 1, math.min(5, #zone.tpPoints) do
            local p = zone.tpPoints[i]
            if type(p) == 'table' then
                tpPoints[#tpPoints+1] = {
                    x = tonumber(p.x) or 0, y = tonumber(p.y) or 0, z = tonumber(p.z) or 0,
                    h = tonumber(p.h) or 0.0,
                }
            end
        end
    end

    local teleportNpcs = {}
    if type(zone.teleportNpcs) == 'table' then
        for i = 1, math.min(4, #zone.teleportNpcs) do
            local p = zone.teleportNpcs[i]
            if type(p) == 'table' then
                teleportNpcs[#teleportNpcs+1] = {
                    x = tonumber(p.x) or 0, y = tonumber(p.y) or 0, z = tonumber(p.z) or 0,
                    h = tonumber(p.h) or 0.0,
                    model = (type(p.model) == 'string' and p.model ~= '' and p.model:sub(1, 60))
                            or (Config.TeleportNpcModels and Config.TeleportNpcModels[i])
                            or 'a_m_y_business_01',
                }
            end
        end
    end

    local ztype = zone.type == 'safezone' and 'safezone' or 'redzone'
    local isSafe = ztype == 'safezone'

    local base = {
        id = id,
        type = ztype,
        name = zone.name:sub(1, 40),
        coords = { x = tonumber(zone.coords.x) or 0, y = tonumber(zone.coords.y) or 0, z = tonumber(zone.coords.z) or 0 },
        radius = math.max(10.0, math.min(500.0, tonumber(zone.radius) or 60.0)),
        colorHex = (type(zone.colorHex) == 'string' and zone.colorHex:match('^#%x%x%x%x%x%x$')) and zone.colorHex
                   or (isSafe and '#57F187' or '#FF0000'),
        colorA = math.max(0, math.min(255, math.floor(tonumber(zone.colorA) or (isSafe and 60 or 80)))),
        blipSprite = tonumber(zone.blipSprite) or (isSafe and 60 or 310),
        blipColor = tonumber(zone.blipColor) or (isSafe and 2 or 1),
        poly = poly,
        showMarker = zone.showMarker ~= false,
        polyMinZ = tonumber(zone.polyMinZ) or nil,
        polyMaxZ = tonumber(zone.polyMaxZ) or nil,
        showBlip = zone.showBlip ~= false,
        showRadiusBlip = zone.showRadiusBlip ~= false,
        hideHud = zone.hideHud == true,
        enabled = zone.enabled ~= false,
    }

    if isSafe then
        base.deleteVehicleOnEntry = zone.deleteVehicleOnEntry == true
        base.tpPoints             = tpPoints
        base.allowTeleport        = zone.allowTeleport == true
        base.teleportCost         = math.max(0, math.floor(tonumber(zone.teleportCost) or 0))
        base.teleportCostSource   = zone.teleportCostSource == 'bank' and 'bank' or 'cash'
        local wm = zone.weaponMode
        if wm ~= 'holster' and wm ~= 'blockfire' and wm ~= 'off' then
            wm = (zone.disableWeapons == false) and 'off' or 'holster'
        end
        base.weaponMode = wm
        base.disableWeapons = wm ~= 'off'
        base.invincible     = zone.invincible ~= false
        base.phaseThrough   = zone.phaseThrough ~= false
        base.speedLimit     = math.max(0, math.min(200, math.floor(tonumber(zone.speedLimit) or 0)))
    else
        base.rewardItems          = sanitizeRewards(zone.rewardItems, false)
        base.streakRewards        = sanitizeRewards(zone.streakRewards, true)
        base.killHeal             = math.max(0, math.min(200, math.floor(tonumber(zone.killHeal) or 0)))
        base.killHealFull         = zone.killHealFull == true
        base.reviveCost           = math.max(0, tonumber(zone.reviveCost) or 0)
        base.reviveInside         = zone.reviveInside ~= false
        base.reviveCostSource     = zone.reviveCostSource == 'bank' and 'bank' or 'cash'
        base.reviveDelay          = math.max(1000, tonumber(zone.reviveDelay) or 8000)
        base.teleportAway         = math.max(5.0, math.min(200.0, tonumber(zone.teleportAway) or 30.0))
        base.exits                = exits
        base.tpPoints             = tpPoints
        base.teleportNpcs         = teleportNpcs
        base.deleteVehicleOnEntry = zone.deleteVehicleOnEntry ~= false
        base.infiniteStamina      = zone.infiniteStamina == true
        base.allowTeleport        = zone.allowTeleport == true
        base.teleportCost         = math.max(0, math.floor(tonumber(zone.teleportCost) or 0))
        base.teleportCostSource   = zone.teleportCostSource == 'bank' and 'bank' or 'cash'
    end

    Data.zones[id] = base
    SaveData()
    BroadcastZones(-1)
    BroadcastAdminData()
    NotifySv(src, _U('zone_saved', Data.zones[id].name), 'success')
    if Log then Log('admin', 'Zone Saved', ('**%s** saved zone **%s**'):format(GetPName(src), Data.zones[id].name)) end
end)

RegisterNetEvent('lime_redzones:server:bulkUpdateZones', function(ids, patch)
    local src = source
    if not HasPerm(src, 'zones') then NotifySv(src, _U('no_permission'), 'error') return end
    if type(ids) ~= 'table' or type(patch) ~= 'table' then return end

    local RZ_FIELDS = {
        enabled = 'bool', showBlip = 'bool', showRadiusBlip = 'bool', showMarker = 'bool',
        hideHud = 'bool',
        deleteVehicleOnEntry = 'bool', infiniteStamina = 'bool',
        allowTeleport = 'bool', teleportCost = 'int', teleportCostSource = 'source',
        reviveCost = 'int', reviveCostSource = 'source', reviveInside = 'bool',
        killHeal = 'int', killHealFull = 'bool',
    }
    local SAFE_FIELDS = {
        enabled = 'bool', showBlip = 'bool', showRadiusBlip = 'bool', showMarker = 'bool',
        hideHud = 'bool',
        deleteVehicleOnEntry = 'bool', invincible = 'bool', phaseThrough = 'bool',
        speedLimit = 'int', weaponMode = 'wmode',
    }

    local function coerce(kind, v)
        if kind == 'bool'   then return v == true end
        if kind == 'int'    then return math.max(0, math.floor(tonumber(v) or 0)) end
        if kind == 'source' then return (v == 'bank') and 'bank' or 'cash' end
        if kind == 'wmode'  then
            return (v == 'blockfire' or v == 'off') and v or 'holster'
        end
        return nil
    end

    local wantType = nil
    local applied, changedFields = 0, {}
    for _, id in ipairs(ids) do
        local z = Data.zones[tostring(id)]
        if z then
            local ztype = (z.type == 'safezone') and 'safezone' or 'redzone'
            if not wantType then wantType = ztype end
            if ztype == wantType then
                local fields = (ztype == 'safezone') and SAFE_FIELDS or RZ_FIELDS
                for k, v in pairs(patch) do
                    local kind = fields[k]
                    if kind then
                        local cv = coerce(kind, v)
                        if cv ~= nil then z[k] = cv; changedFields[k] = true end
                    end
                end
                if fields.weaponMode and patch.weaponMode ~= nil then
                    z.disableWeapons = z.weaponMode ~= 'off'
                end
                applied = applied + 1
            end
        end
    end

    if applied == 0 then NotifySv(src, 'No matching zones updated.', 'error') return end
    SaveData()
    BroadcastZones(-1)
    BroadcastAdminData()

    local fieldList = {}
    for k in pairs(changedFields) do fieldList[#fieldList+1] = k end
    NotifySv(src, ('Updated %d zone%s.'):format(applied, applied == 1 and '' or 's'), 'success')
    if Log then
        Log('admin', 'Bulk Zone Update',
            ('**%s** updated **%d** zones (%s)'):format(GetPName(src), applied,
                #fieldList > 0 and table.concat(fieldList, ', ') or 'no fields'),
            nil, GetPName(src))
    end
end)

RegisterNetEvent('lime_redzones:server:toggleZone', function(zoneId, enabled)
    local src = source
    if not HasPerm(src, 'zones') then return end
    local z = Data.zones[tostring(zoneId)]
    if not z then return end
    z.enabled = enabled == true
    SaveData()
    BroadcastZones(-1)
    BroadcastAdminData()
    NotifySv(src, ('Zone "%s" %s.'):format(z.name, z.enabled and 'enabled' or 'disabled'), 'success')
    if Log then Log('admin', 'Zone Toggled', ('**%s** %s zone **%s**'):format(GetPName(src), z.enabled and 'enabled' or 'disabled', z.name)) end
end)

RegisterNetEvent('lime_redzones:server:deleteZone', function(zoneId)
    local src = source
    if not HasPerm(src, 'zones') then return end
    local z = Data.zones[tostring(zoneId)]
    if not z then return end
    local name = z.name
    Data.zones[tostring(zoneId)] = nil
    SaveData()
    BroadcastZones(-1)
    BroadcastAdminData()
    NotifySv(src, ('Zone "%s" deleted.'):format(name), 'success')
    if Log then Log('admin', 'Zone Deleted', ('**%s** deleted zone **%s**'):format(GetPName(src), name)) end
end)

RegisterNetEvent('lime_redzones:server:saveGang', function(gang)
    local src = source
    if not HasPerm(src, 'gangs') then return end
    if type(gang) ~= 'table' or type(gang.name) ~= 'string' or gang.name == '' then return end
    Data.customGangs[gang.name:sub(1, 30)] = { label = (gang.label or gang.name):sub(1, 40) }
    SaveData()
    BroadcastAdminData()
    NotifySv(src, ('Gang "%s" registered.'):format(gang.label or gang.name), 'success')
    if Log then Log('admin', 'Gang Added', ('**%s** added gang **%s**'):format(GetPName(src), gang.label or gang.name)) end
end)

RegisterNetEvent('lime_redzones:server:deleteGang', function(name)
    local src = source
    if not HasPerm(src, 'gangs') then return end
    Data.customGangs[tostring(name)] = nil
    SaveData()
    BroadcastAdminData()
    NotifySv(src, _U('gang_removed', tostring(name)), 'success')
    if Log then Log('admin', 'Gang Deleted', ('**%s** deleted gang **%s**'):format(GetPName(src), tostring(name))) end
end)

local GANG_RANKS = { owner = 3, officer = 2, member = 1 }

local function GangOpt(key, default, lo, hi)
    local v = tonumber(Data.settings.options[key])
    if not v then return default end
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return math.floor(v)
end

local function GangMemberCount(g)
    local n = 0
    for _ in pairs(g.members or {}) do n = n + 1 end
    return n
end

local function CleanGangText(s, max)
    s = tostring(s or ''):gsub('%s+', ' '):gsub('^%s*(.-)%s*$', '%1')
    return s:sub(1, max)
end

local function MemberKey(identifier)
    local h = 5381
    for i = 1, #identifier do h = (h * 33 + identifier:byte(i)) % 4294967296 end
    return 'm' .. tostring(h)
end

local function MemberByKey(g, key)
    for id in pairs(g.members or {}) do
        if MemberKey(id) == key then return id end
    end
    return nil
end

local function GangRankOf(g, identifier)
    local m = g and g.members and g.members[identifier]
    return m and m.rank or nil
end

local function GangCan(g, identifier, minRank)
    local r = GangRankOf(g, identifier)
    return r ~= nil and (GANG_RANKS[r] or 0) >= (GANG_RANKS[minRank] or 99)
end

local function PruneGangInvites(g)
    local ttl = GangOpt('gangInviteExpiry', 120, 15, 3600)
    local now = os.time()
    local changed = false
    for id, inv in pairs(g.invites or {}) do
        if (now - (inv.at or 0)) > ttl then g.invites[id] = nil changed = true end
    end
    return changed
end

local function GangStats(gangId)
    local rec = Data.lb.gangs[gangId]
    return { kills = rec and rec.kills or 0, deaths = rec and rec.deaths or 0 }
end

local function OnlineByIdentifier()
    local map = {}
    for _, sid in ipairs(GetPlayers()) do
        local s = tonumber(sid)
        local id = GetIdentifier(s)
        if id then map[id] = s end
    end
    return map
end

local function GangPublic(g, online)
    local members = {}
    for id, m in pairs(g.members or {}) do
        members[#members+1] = {
            id = MemberKey(id), name = m.name or 'Unknown', rank = m.rank or 'member',
            online = online[id] ~= nil, joined = m.joined,
        }
    end
    table.sort(members, function(a, b)
        local ra, rb = GANG_RANKS[a.rank] or 0, GANG_RANKS[b.rank] or 0
        if ra ~= rb then return ra > rb end
        return (a.name or '') < (b.name or '')
    end)
    local st = GangStats(g.id)
    return {
        id = g.id, label = g.label, tag = g.tag, color = g.color,
        created = g.created, members = members,
        kills = st.kills, deaths = st.deaths,
        max = GangOpt('gangMaxMembers', 10, 2, 60),
    }
end

local function PushGangState(src)
    local id = GetIdentifier(src)
    if not id then return end
    local mode = GangMode()
    local online = OnlineByIdentifier()
    local g = PlayerGangOf(id)

    local invites = {}
    if mode == 'player' and not g then
        for _, gang in pairs(Data.gangs) do
            PruneGangInvites(gang)
            local inv = gang.invites and gang.invites[id]
            if inv then
                invites[#invites+1] = {
                    id = gang.id, label = gang.label, tag = gang.tag, color = gang.color,
                    by = inv.by, members = GangMemberCount(gang),
                }
            end
        end
    end

    local roster = {}
    if mode == 'player' and g and GangCan(g, id, 'officer') then
        for _, sid in ipairs(GetPlayers()) do
            local s = tonumber(sid)
            local pid = GetIdentifier(s)
            if pid and not PlayerGangOf(pid) then
                roster[#roster+1] = { id = s, name = GetPName(s) }
            end
        end
        table.sort(roster, function(a, b) return (a.name or '') < (b.name or '') end)
    end

    TriggerClientEvent('lime_redzones:client:gangState', src, {
        mode = mode,
        enabled = Data.settings.options.gangLbEnabled ~= false,
        me = MemberKey(id),
        rank = g and GangRankOf(g, id) or nil,
        gang = g and GangPublic(g, online) or nil,
        invites = invites,
        roster = roster,
        maxMembers = GangOpt('gangMaxMembers', 10, 2, 60),
        createCost = GangOpt('gangCreateCost', 0, 0, 100000000),
        createCostSource = Data.settings.options.gangCreateCostSource == 'bank' and 'bank' or 'cash',
    })
end

local function PushGangStateToMembers(g)
    local online = OnlineByIdentifier()
    for id in pairs(g.members or {}) do
        local s = online[id]
        if s then PushGangState(s) end
    end
end

local function GangLog(title, desc, fields)
    if Log then Log('admin', title, desc, fields) end
end

local function GangGate(src)
    if GangMode() ~= 'player' then
        NotifySv(src, 'Player gangs are disabled on this server.', 'error')
        return nil
    end
    local id = GetIdentifier(src)
    if not id then return nil end
    return id
end

RegisterNetEvent('lime_redzones:server:gangState', function()
    local src = source
    if not reqOk(src, 0.5, 'gangstate') then return end
    PushGangState(src)
end)

RegisterNetEvent('lime_redzones:server:gangCreate', function(d)
    local src = source
    local id = GangGate(src)
    if not id or type(d) ~= 'table' then return end
    if not reqOk(src, 2.0, 'gangcreate') then return end
    if PlayerGangOf(id) then NotifySv(src, 'You are already in a gang.', 'error') return end

    local label = CleanGangText(d.label, 24)
    local tag   = CleanGangText(d.tag, 4):upper():gsub('[^A-Z0-9]', '')
    if #label < 3 then NotifySv(src, 'Gang name needs at least 3 characters.', 'error') return end
    if #tag < 2 then NotifySv(src, 'Gang tag needs 2-4 letters or numbers.', 'error') return end
    for _, g in pairs(Data.gangs) do
        if g.label:lower() == label:lower() then NotifySv(src, 'That gang name is taken.', 'error') return end
        if g.tag:upper() == tag then NotifySv(src, 'That gang tag is taken.', 'error') return end
    end

    local cost = GangOpt('gangCreateCost', 0, 0, 100000000)
    if cost > 0 then
        local fromBank = Data.settings.options.gangCreateCostSource == 'bank'
        local paid
        if fromBank then paid = RemoveBank ~= nil and RemoveBank(src, cost, 'Gang Creation') == true
        else paid = RemoveCash(src, cost) == true end
        if not paid then
            NotifySv(src, ('You need $%s%s to start a gang.'):format(cost, fromBank and ' in the bank' or ''), 'error')
            return
        end
    end

    local gid = 'g' .. tostring(Data.nextGangId or 1)
    Data.nextGangId = (Data.nextGangId or 1) + 1
    local color = type(d.color) == 'string' and d.color:match('^#%x%x%x%x%x%x$') and d.color or '#A3E635'
    Data.gangs[gid] = {
        id = gid, label = label, tag = tag, color = color,
        owner = id, created = os.time(),
        members = { [id] = { name = GetPName(src), rank = 'owner', joined = os.time() } },
        invites = {},
    }
    Data.gangOf[id] = gid
    SaveData()
    PushGangState(src)
    PushLeaderboard(-1)
    NotifySv(src, ('Gang "%s" created.'):format(label), 'success')
    GangLog('Gang Created', ('**%s** created the gang **%s** [%s]'):format(GetPName(src), label, tag))
end)

RegisterNetEvent('lime_redzones:server:gangInvite', function(d)
    local src = source
    local id = GangGate(src)
    if not id or type(d) ~= 'table' then return end
    if not reqOk(src, 1.0, 'ganginvite') then return end
    local g = PlayerGangOf(id)
    if not g or not GangCan(g, id, 'officer') then
        NotifySv(src, 'Only the owner or an officer can invite.', 'error')
        return
    end
    local target = tonumber(d.target)
    if not target or GetPlayerName(target) == nil then NotifySv(src, 'That player is not online.', 'error') return end
    local tid = GetIdentifier(target)
    if not tid or tid == id then return end
    if PlayerGangOf(tid) then NotifySv(src, 'They are already in a gang.', 'error') return end

    local maxM = GangOpt('gangMaxMembers', 10, 2, 60)
    if GangMemberCount(g) >= maxM then
        NotifySv(src, ('Your gang is full (%d members).'):format(maxM), 'error')
        return
    end

    g.invites = g.invites or {}
    PruneGangInvites(g)
    g.invites[tid] = { by = GetPName(src), at = os.time(), name = GetPName(target) }
    SaveData()
    NotifySv(src, ('Invited %s to %s.'):format(GetPName(target), g.label), 'success')
    NotifySv(target, ('%s invited you to join %s.'):format(GetPName(src), g.label), 'info')
    PushGangState(target)
    PushGangState(src)
end)

RegisterNetEvent('lime_redzones:server:gangInviteAnswer', function(d)
    local src = source
    local id = GangGate(src)
    if not id or type(d) ~= 'table' then return end
    if not reqOk(src, 0.5, 'ganginvans') then return end
    local g = Data.gangs[tostring(d.id or '')]
    if not g or not g.invites or not g.invites[id] then return end
    g.invites[id] = nil

    if d.accept ~= true then
        SaveData()
        PushGangState(src)
        return
    end
    if PlayerGangOf(id) then NotifySv(src, 'You are already in a gang.', 'error') return end
    local maxM = GangOpt('gangMaxMembers', 10, 2, 60)
    if GangMemberCount(g) >= maxM then
        NotifySv(src, 'That gang is full.', 'error')
        SaveData()
        PushGangState(src)
        return
    end

    g.members[id] = { name = GetPName(src), rank = 'member', joined = os.time() }
    Data.gangOf[id] = g.id
    SaveData()
    NotifySv(src, ('You joined %s.'):format(g.label), 'success')
    PushGangStateToMembers(g)
    PushLeaderboard(-1)
    GangLog('Gang Joined', ('**%s** joined the gang **%s**'):format(GetPName(src), g.label))
end)

local function RemoveFromGang(g, identifier)
    if not g.members or not g.members[identifier] then return false end
    g.members[identifier] = nil
    if Data.gangOf[identifier] == g.id then Data.gangOf[identifier] = nil end
    return true
end

local function DisbandGang(g, reason, actorName)
    for id in pairs(g.members or {}) do
        if Data.gangOf[id] == g.id then Data.gangOf[id] = nil end
    end
    Data.gangs[g.id] = nil
    Data.lb.gangs[g.id] = nil
    GangLog('Gang Disbanded', ('**%s** — %s'):format(g.label, reason), actorName and
        { { name = 'By', value = actorName, inline = true } } or nil)
end

RegisterNetEvent('lime_redzones:server:gangLeave', function()
    local src = source
    local id = GangGate(src)
    if not id then return end
    if not reqOk(src, 1.0, 'gangleave') then return end
    local g = PlayerGangOf(id)
    if not g then return end

    if g.owner == id then
        NotifySv(src, 'Hand the gang over or disband it before leaving.', 'error')
        return
    end
    local label = g.label
    RemoveFromGang(g, id)
    SaveData()
    NotifySv(src, ('You left %s.'):format(label), 'info')
    PushGangState(src)
    PushGangStateToMembers(g)
    PushLeaderboard(-1)
end)

RegisterNetEvent('lime_redzones:server:gangKick', function(d)
    local src = source
    local id = GangGate(src)
    if not id or type(d) ~= 'table' then return end
    if not reqOk(src, 0.5, 'gangkick') then return end
    local g = PlayerGangOf(id)
    if not g or not GangCan(g, id, 'officer') then return end
    local tid = MemberByKey(g, tostring(d.id or ''))
    if not tid or tid == id then return end
    local target = g.members[tid]
    if not target then return end
    if (GANG_RANKS[target.rank] or 0) >= (GANG_RANKS[GangRankOf(g, id)] or 0) then
        NotifySv(src, 'You cannot remove someone at or above your rank.', 'error')
        return
    end

    local name = target.name or 'Member'
    RemoveFromGang(g, tid)
    SaveData()
    NotifySv(src, ('Removed %s from %s.'):format(name, g.label), 'success')
    local online = OnlineByIdentifier()
    if online[tid] then
        NotifySv(online[tid], ('You were removed from %s.'):format(g.label), 'error')
        PushGangState(online[tid])
    end
    PushGangStateToMembers(g)
    PushLeaderboard(-1)
end)

RegisterNetEvent('lime_redzones:server:gangSetRank', function(d)
    local src = source
    local id = GangGate(src)
    if not id or type(d) ~= 'table' then return end
    if not reqOk(src, 0.5, 'gangrank') then return end
    local g = PlayerGangOf(id)
    if not g or g.owner ~= id then
        NotifySv(src, 'Only the gang owner can change ranks.', 'error')
        return
    end
    local tid = MemberByKey(g, tostring(d.id or ''))
    local rank = tostring(d.rank or '')
    local target = tid and g.members[tid]
    if not target or tid == id then return end

    if rank == 'owner' then
        target.rank = 'owner'
        g.members[id].rank = 'officer'
        g.owner = tid
        SaveData()
        NotifySv(src, ('%s now owns %s.'):format(target.name or 'They', g.label), 'success')
        GangLog('Gang Ownership Transferred', ('**%s** handed **%s** to **%s**'):format(GetPName(src), g.label, target.name or tid))
    elseif rank == 'officer' or rank == 'member' then
        target.rank = rank
        SaveData()
        NotifySv(src, ('%s is now a%s %s.'):format(target.name or 'Member', rank == 'officer' and 'n' or '', rank), 'success')
    else
        return
    end
    PushGangStateToMembers(g)
end)

RegisterNetEvent('lime_redzones:server:gangEdit', function(d)
    local src = source
    local id = GangGate(src)
    if not id or type(d) ~= 'table' then return end
    if not reqOk(src, 1.0, 'gangedit') then return end
    local g = PlayerGangOf(id)
    if not g or g.owner ~= id then return end

    local label = CleanGangText(d.label, 24)
    local tag   = CleanGangText(d.tag, 4):upper():gsub('[^A-Z0-9]', '')
    if #label < 3 or #tag < 2 then NotifySv(src, 'Name needs 3+ characters and a 2-4 character tag.', 'error') return end
    for _, other in pairs(Data.gangs) do
        if other.id ~= g.id then
            if other.label:lower() == label:lower() then NotifySv(src, 'That gang name is taken.', 'error') return end
            if other.tag:upper() == tag then NotifySv(src, 'That gang tag is taken.', 'error') return end
        end
    end

    g.label = label
    g.tag = tag
    if type(d.color) == 'string' and d.color:match('^#%x%x%x%x%x%x$') then g.color = d.color end
    if Data.lb.gangs[g.id] then Data.lb.gangs[g.id].label = label end
    SaveData()
    NotifySv(src, 'Gang updated.', 'success')
    PushGangStateToMembers(g)
    PushLeaderboard(-1)
end)

RegisterNetEvent('lime_redzones:server:gangDisband', function()
    local src = source
    local id = GangGate(src)
    if not id then return end
    if not reqOk(src, 2.0, 'gangdisband') then return end
    local g = PlayerGangOf(id)
    if not g or g.owner ~= id then return end

    local label = g.label
    local online = OnlineByIdentifier()
    local members = {}
    for mid in pairs(g.members or {}) do members[#members+1] = mid end
    DisbandGang(g, 'disbanded by the owner', GetPName(src))
    SaveData()
    for _, mid in ipairs(members) do
        local s = online[mid]
        if s then
            if s ~= src then NotifySv(s, ('%s was disbanded.'):format(label), 'error') end
            PushGangState(s)
        end
    end
    NotifySv(src, ('%s disbanded.'):format(label), 'success')
    PushLeaderboard(-1)
end)

RegisterNetEvent('lime_redzones:server:adminDeleteGang', function(d)
    local src = source
    if not HasPerm(src, 'gangs') then return end
    if type(d) ~= 'table' then return end
    local g = Data.gangs[tostring(d.id or '')]
    if not g then return end
    local label = g.label
    local online = OnlineByIdentifier()
    local members = {}
    for mid in pairs(g.members or {}) do members[#members+1] = mid end
    DisbandGang(g, 'removed by an admin', GetPName(src))
    SaveData()
    for _, mid in ipairs(members) do
        local s = online[mid]
        if s then
            NotifySv(s, ('%s was removed by an admin.'):format(label), 'error')
            PushGangState(s)
        end
    end
    BroadcastAdminData()
    PushLeaderboard(-1)
    NotifySv(src, ('Gang "%s" removed.'):format(label), 'success')
end)

function PlayerGangList()
    local out = {}
    local online = OnlineByIdentifier()
    for _, g in pairs(Data.gangs) do
        local st = GangStats(g.id)
        local on = 0
        local ownerName = 'Unknown'
        for mid, m in pairs(g.members or {}) do
            if online[mid] then on = on + 1 end
            if mid == g.owner then ownerName = m.name or 'Unknown' end
        end
        out[#out+1] = {
            id = g.id, label = g.label, tag = g.tag, color = g.color,
            owner = ownerName, created = g.created,
            members = GangMemberCount(g), online = on,
            kills = st.kills, deaths = st.deaths,
        }
    end
    table.sort(out, function(a, b)
        if a.kills == b.kills then return (a.label or '') < (b.label or '') end
        return a.kills > b.kills
    end)
    return out
end

RegisterNetEvent('lime_redzones:server:saveResetSettings', function(which, cfg)
    local src = source
    if not HasPerm(src, 'leaderboards') then return end
    if which ~= 'reset' and which ~= 'globalReset' then return end
    if type(cfg) ~= 'table' then return end
    local cur = Data.settings[which]
    cur.enabled     = cfg.enabled == true
    cur.day         = math.max(0, math.min(6, math.floor(tonumber(cfg.day) or 0)))
    cur.hour        = math.max(0, math.min(23, math.floor(tonumber(cfg.hour) or 18)))
    cur.prizeName   = type(cfg.prizeName) == 'string' and cfg.prizeName:sub(1, 50) or 'money'
    cur.prizeAmount = math.max(0, math.floor(tonumber(cfg.prizeAmount) or 0))
    cur.resetElo    = cfg.resetElo == true
    SaveData()
    BroadcastAdminData()
    PushLeaderboard(-1)
    NotifySv(src, _U('reset_saved'), 'success')
    if Log then Log('admin', 'Reset Schedule Updated', ('**%s** updated the %s reset schedule'):format(GetPName(src), which == 'globalReset' and 'Global' or 'Redzone')) end
end)

RegisterNetEvent('lime_redzones:server:saveOptions', function(opts)
    local src = source
    if type(opts) ~= 'table' then return end
    local fullOpts = HasPerm(src, 'options')
    if not fullOpts then
        if not HasPerm(src, 'killfeed') then return end
        local o = Data.settings.options
        o.killFeedEnabled    = opts.killFeedEnabled ~= false
        o.killCamEnabled     = opts.killCamEnabled ~= false
        o.killMessageEnabled = opts.killMessageEnabled ~= false
        o.killFeedDuration   = math.max(2000, math.min(20000, math.floor(tonumber(opts.killFeedDuration) or 6000)))
        o.killCamDuration    = math.max(2000, math.min(15000, math.floor(tonumber(opts.killCamDuration) or 5000)))
        SaveData()
        TriggerClientEvent('lime_redzones:client:syncOptions', -1, o)
        NotifySv(src, _U('settings_saved'), 'success')
        return
    end
    Data.settings.options.rewardNotify   = opts.rewardNotify ~= false
    Data.settings.options.streakAnnounce = opts.streakAnnounce ~= false
    local o = Data.settings.options
    o.renderDistance = math.max(50, math.min(500, math.floor(tonumber(opts.renderDistance) or 120)))
    o.rewardNotify         = opts.rewardNotify ~= false
    o.streakAnnounce       = opts.streakAnnounce ~= false
    o.leaderboardEnabled   = opts.leaderboardEnabled ~= false
    o.globalLbEnabled      = opts.globalLbEnabled ~= false
    o.gangLbEnabled        = opts.gangLbEnabled ~= false
    if opts.gangMode == 'player' or opts.gangMode == 'off' or opts.gangMode == 'framework' then
        o.gangMode = opts.gangMode
    end
    o.gangMaxMembers       = math.max(2, math.min(60, math.floor(tonumber(opts.gangMaxMembers) or 10)))
    o.gangCreateCost       = math.max(0, math.min(100000000, math.floor(tonumber(opts.gangCreateCost) or 0)))
    o.gangCreateCostSource = opts.gangCreateCostSource == 'bank' and 'bank' or 'cash'
    o.gangInviteExpiry     = math.max(15, math.min(3600, math.floor(tonumber(opts.gangInviteExpiry) or 120)))
    o.streaksEnabled       = opts.streaksEnabled ~= false
    o.personalColorEnabled = opts.personalColorEnabled ~= false
    o.personalColorOpacity = opts.personalColorOpacity ~= false
    o.personalColorHue     = opts.personalColorHue ~= false
    o.killFeedEnabled      = opts.killFeedEnabled ~= false
    o.killMessageEnabled   = opts.killMessageEnabled ~= false
    o.killFeedDuration     = math.max(2000, math.min(20000, math.floor(tonumber(opts.killFeedDuration) or 6000)))
    o.killCamDuration      = math.max(2000, math.min(15000, math.floor(tonumber(opts.killCamDuration) or 5000)))
    o.killCamEnabled       = opts.killCamEnabled ~= false
    o.tabletAnim           = opts.tabletAnim ~= false
    o.reviveWaitMedical    = math.max(2000, math.min(60000, math.floor(tonumber(opts.reviveWaitMedical) or 12000)))
    o.reviveWaitNative     = math.max(1000, math.min(30000, math.floor(tonumber(opts.reviveWaitNative) or 4000)))
    o.nativeReviveFallback = opts.nativeReviveFallback ~= false
    if type(opts.tabletProp) == 'string' and opts.tabletProp ~= '' then
        o.tabletProp = opts.tabletProp:sub(1, 60)
    end
    if type(opts.tabletAnimDict) == 'string' and opts.tabletAnimDict ~= '' then
        o.tabletAnimDict = opts.tabletAnimDict:sub(1, 120)
    end
    if type(opts.tabletAnimName) == 'string' and opts.tabletAnimName ~= '' then
        o.tabletAnimName = opts.tabletAnimName:sub(1, 60)
    end
    o.logColor             = math.max(0, math.min(16777215, math.floor(tonumber(opts.logColor) or 10672181)))
    o.debugMode            = opts.debugMode == true
    if type(opts.keybinds) == 'table' then
        local function cleanKey(v, fallback)
            v = tostring(v or ''):upper():gsub('[^A-Z0-9]', '')
            if v == '' or #v > 12 then return fallback end
            return v
        end
        o.keybinds = o.keybinds or {}
        for _, name in ipairs({ 'leaderboard', 'admin', 'hudMove' }) do
            local inb = opts.keybinds[name]
            if type(inb) == 'table' then
                local prev = o.keybinds[name] or {}
                o.keybinds[name] = {
                    enabled = inb.enabled == true,
                    key = cleanKey(inb.key, prev.key or 'F1'),
                }
            end
        end
    end
    if type(opts.lbCols) == 'table' then
        o.lbCols = {
            kills  = opts.lbCols.kills ~= false,
            deaths = opts.lbCols.deaths ~= false,
            kd     = opts.lbCols.kd ~= false,
            streak = opts.lbCols.streak == true,
        }
    end
    SaveData()
    BroadcastZones(-1)
    TriggerClientEvent('lime_redzones:client:syncOptions', -1, o)
    BroadcastAdminData()
    NotifySv(src, 'Options saved.', 'success')
    if Log then Log('admin', 'Options Updated', ('**%s** updated server options'):format(GetPName(src))) end
end)

local function isHex6(s)
    return type(s) == 'string' and s:match('^#%x%x%x%x%x%x$') ~= nil
end

RegisterNetEvent('lime_redzones:server:saveCustomTheme', function(theme)
    local src = source
    if not HasPerm(src, 'options') then return end
    if type(theme) ~= 'table' then return end
    local accent = isHex6(theme.accent) and theme.accent or '#A3E635'
    local text   = isHex6(theme.text) and theme.text or nil
    Data.settings.options.customTheme = { accent = accent, text = text }
    SaveData()
    TriggerClientEvent('lime_redzones:client:syncOptions', -1, Data.settings.options)
    TriggerClientEvent('lime_redzones:client:syncCustomTheme', -1, Data.settings.options.customTheme)
    BroadcastAdminData()
    NotifySv(src, 'Theme applied to all players.', 'success')
    if Log then Log('admin', 'Theme Updated', ('**%s** set the global theme accent to %s'):format(GetPName(src), accent)) end
end)

local HUD_PRESETS = { top = true, ['top-left'] = true, ['top-right'] = true, bottom = true, left = true, right = true }
local HUD_THEMES  = { lime = true, crimson = true, cyan = true, amber = true, violet = true, mono = true, custom = true }

local function cleanHudTheme(v, fallback, allowInherit)
    if type(v) ~= 'string' then return fallback end
    if allowInherit and v == 'inherit' then return 'inherit' end
    if isHex6(v) then return v end
    if HUD_THEMES[v] then return v end
    return fallback
end

local function cleanHudPos(v, fallback)
    if v == false or v == nil then return false end
    if type(v) ~= 'table' then return fallback end
    local x, y = tonumber(v.x), tonumber(v.y)
    if not x or not y then return fallback end
    return { x = math.max(0, math.min(100, x)), y = math.max(0, math.min(100, y)) }
end

local function cleanHudScale(v, fallback)
    local n = tonumber(v)
    if not n then return fallback end
    return math.max(0.6, math.min(1.6, n))
end

local function HudDefaults()
    local o = Data.settings.options
    o.hudDefaults = o.hudDefaults or {}
    return o.hudDefaults
end

RegisterNetEvent('lime_redzones:server:saveHudDefaults', function(patch)
    local src = source
    if not HasPerm(src, 'options') then NotifySv(src, _U('no_permission'), 'error') return end
    if type(patch) ~= 'table' then return end
    local d = HudDefaults()

    if patch.reset == true then
        Data.settings.options.hudDefaults = {
            theme = 'lime', preset = 'top', scale = 1.0, pos = false,
            szPos = false,
            kfTheme = 'inherit', kfScale = 1.0, kfPos = false,
            kmTheme = 'inherit', kmScale = 1.0, kmPos = false,
            lock = false,
        }
        d = Data.settings.options.hudDefaults
    else
        if patch.theme   ~= nil then d.theme   = cleanHudTheme(patch.theme, d.theme or 'lime') end
        if patch.preset  ~= nil then d.preset  = HUD_PRESETS[patch.preset] and patch.preset or (d.preset or 'top') end
        if patch.scale   ~= nil then d.scale   = cleanHudScale(patch.scale, d.scale or 1.0) end
        if patch.pos     ~= nil then d.pos     = cleanHudPos(patch.pos, d.pos or false) end
        if patch.szPos   ~= nil then d.szPos   = cleanHudPos(patch.szPos, d.szPos or false) end
        if patch.kfTheme ~= nil then d.kfTheme = cleanHudTheme(patch.kfTheme, d.kfTheme or 'inherit', true) end
        if patch.kfScale ~= nil then d.kfScale = cleanHudScale(patch.kfScale, d.kfScale or 1.0) end
        if patch.kfPos   ~= nil then d.kfPos   = cleanHudPos(patch.kfPos, d.kfPos or false) end
        if patch.kmTheme ~= nil then d.kmTheme = cleanHudTheme(patch.kmTheme, d.kmTheme or 'inherit', true) end
        if patch.kmScale ~= nil then d.kmScale = cleanHudScale(patch.kmScale, d.kmScale or 1.0) end
        if patch.kmPos   ~= nil then d.kmPos   = cleanHudPos(patch.kmPos, d.kmPos or false) end
        if patch.lock    ~= nil then d.lock    = patch.lock == true end
    end

    Data.settings.options.hudDefaultTheme  = d.theme or 'lime'
    Data.settings.options.hudDefaultPreset = d.preset or 'top'

    SaveData()
    TriggerClientEvent('lime_redzones:client:syncOptions', -1, Data.settings.options)
    if not patch.silent then
        NotifySv(src, 'HUD defaults saved.', 'success')
        if Log then Log('admin', 'HUD Defaults Updated', ('**%s** updated the server-wide HUD defaults'):format(GetPName(src))) end
    end
end)

local LB_STORES = {
    redzone = function() return Data.lb.players end,
    global  = function() return Data.globalLb.players end,
}

local function LbEditorList(store)
    local out = {}
    for id, d in pairs(store) do
        out[#out+1] = {
            id = id, name = d.name or 'Unknown',
            kills = math.floor(tonumber(d.kills) or 0),
            deaths = math.floor(tonumber(d.deaths) or 0),
            elo = d.elo and math.floor(tonumber(d.elo)) or nil,
        }
    end
    table.sort(out, function(a, b)
        if a.kills == b.kills then return (a.name or '') < (b.name or '') end
        return a.kills > b.kills
    end)
    return out
end

local function PushLbEditor(src)
    TriggerClientEvent('lime_redzones:client:lbEditor', src,
        LbEditorList(Data.lb.players), LbEditorList(Data.globalLb.players))
end

RegisterNetEvent('lime_redzones:server:requestLbEditor', function()
    local src = source
    if not HasPerm(src, 'leaderboards') then return end
    if not reqOk(src, 0.5, 'lbEditor') then return end
    PushLbEditor(src)
end)

RegisterNetEvent('lime_redzones:server:saveLbEntry', function(payload)
    local src = source
    if not HasPerm(src, 'leaderboards') then NotifySv(src, _U('no_permission'), 'error') return end
    if type(payload) ~= 'table' then return end
    local getStore = LB_STORES[payload.board]
    if not getStore then return end
    local store = getStore()
    local id = type(payload.id) == 'string' and payload.id or nil
    if not id or not store[id] then return end

    local rec = store[id]
    local before = ('%d/%d'):format(rec.kills or 0, rec.deaths or 0)
    rec.kills  = math.max(0, math.min(1000000, math.floor(tonumber(payload.kills) or rec.kills or 0)))
    rec.deaths = math.max(0, math.min(1000000, math.floor(tonumber(payload.deaths) or rec.deaths or 0)))
    if type(payload.name) == 'string' and payload.name ~= '' then rec.name = payload.name:sub(1, 60) end
    if payload.elo ~= nil then
        if payload.elo == false or payload.elo == '' then
            rec.elo = nil
        else
            rec.elo = math.max(0, math.min(100000, math.floor(tonumber(payload.elo) or 0)))
        end
    end

    SaveData()
    PushLeaderboard(-1)
    PushLbEditor(src)
    PushEloAll()
    NotifySv(src, ('Updated %s.'):format(rec.name or id), 'success')
    if Log then
        Log('admin', 'Leaderboard Entry Edited', ('**%s** edited **%s** on the %s board'):format(
            GetPName(src), rec.name or id, payload.board == 'global' and 'Global' or 'Redzone'),
            { { name = 'Before (K/D)', value = before, inline = true },
              { name = 'After (K/D)', value = ('%d/%d'):format(rec.kills, rec.deaths), inline = true },
              { name = 'Identifier', value = id, inline = false } })
    end
end)

RegisterNetEvent('lime_redzones:server:deleteLbEntry', function(payload)
    local src = source
    if not HasPerm(src, 'leaderboards') then NotifySv(src, _U('no_permission'), 'error') return end
    if type(payload) ~= 'table' then return end
    local getStore = LB_STORES[payload.board]
    if not getStore then return end
    local store = getStore()
    local id = type(payload.id) == 'string' and payload.id or nil
    if not id or not store[id] then return end

    local name = store[id].name or id
    store[id] = nil
    SaveData()
    PushLeaderboard(-1)
    PushLbEditor(src)
    NotifySv(src, ('Removed %s from the board.'):format(name), 'success')
    if Log then
        Log('admin', 'Leaderboard Entry Removed', ('**%s** removed **%s** from the %s board'):format(
            GetPName(src), name, payload.board == 'global' and 'Global' or 'Redzone'),
            { { name = 'Identifier', value = id, inline = false } })
    end
end)

RegisterNetEvent('lime_redzones:server:saveRanks', function(ranks)
    local src = source
    if not GetAdminPerms(src)._full then NotifySv(src, 'Only full admins can edit ranks.', 'error') return end
    if type(ranks) ~= 'table' then return end
    local out = {}
    for i = 1, math.min(10, #ranks) do
        local r = ranks[i]
        if type(r) == 'table' and type(r.name) == 'string' and r.name ~= '' then
            out[#out+1] = {
                name = r.name:sub(1,30),
                perms = {
                    zones = r.perms and r.perms.zones == true,
                    gangs = r.perms and r.perms.gangs == true,
                    leaderboards = r.perms and r.perms.leaderboards == true,
                    options = r.perms and r.perms.options == true,
                    killfeed = r.perms and r.perms.killfeed == true,
                },
            }
        end
    end
    Data.settings.ranks = out
    SaveData()
    BroadcastAdminData()
    NotifySv(src, 'Ranks saved.', 'success')
    if Log then Log('admin', 'Ranks Updated', ('**%s** updated admin ranks'):format(GetPName(src))) end
end)

RegisterNetEvent('lime_redzones:server:addAdmin', function(payload)
    local src = source
    if not GetAdminPerms(src)._full then NotifySv(src, 'Only full admins can manage admins.', 'error') return end
    local idStr = type(payload) == 'table' and payload.id or payload
    local rank  = type(payload) == 'table' and payload.rank or nil
    if type(idStr) ~= 'string' or idStr == '' or #idStr > 80 then return end
    for _, a in ipairs(Data.settings.admins) do
        if (type(a) == 'table' and a.id or a) == idStr then return end
    end
    Data.settings.admins[#Data.settings.admins+1] = { id = idStr, rank = rank }
    SaveData()
    BroadcastAdminData()
    NotifySv(src, ('Admin added: %s'):format(idStr), 'success')
    if Log then Log('admin', 'Admin Added', ('**%s** added admin `%s`'):format(GetPName(src), idStr)) end
end)

RegisterNetEvent('lime_redzones:server:removeAdmin', function(identifier)
    local src = source
    if not GetAdminPerms(src)._full then return end
    for i, a in ipairs(Data.settings.admins) do
        if (type(a) == 'table' and a.id or a) == identifier then
            table.remove(Data.settings.admins, i)
            SaveData()
            BroadcastAdminData()
            NotifySv(src, _U('admin_removed', identifier), 'success')
            if Log then Log('admin', 'Admin Removed', ('**%s** removed admin `%s`'):format(GetPName(src), identifier)) end
            return
        end
    end
end)

RegisterNetEvent('lime_redzones:server:resetLeaderboard', function(which)
    local src = source
    if not HasPerm(src, 'leaderboards') then return end
    if which == 'global' then DoReset('globalReset') else DoReset('reset') end
    BroadcastAdminData()
    NotifySv(src, ('%s leaderboard reset.'):format(which == 'global' and 'Global' or 'Redzone'), 'success')
    if Log then Log('admin', 'Leaderboard Reset', ('**%s** reset the %s leaderboard'):format(GetPName(src), which == 'global' and 'Global' or 'Redzone')) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    SaveDataNow()
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    LoadData(function()
        Data.gangs = Data.gangs or {}
        Data.gangOf = {}
        Data.nextGangId = tonumber(Data.nextGangId) or 1
        for gid, g in pairs(Data.gangs) do
            g.id = gid
            g.members = g.members or {}
            g.invites = g.invites or {}
            local hasOwner = false
            for mid, m in pairs(g.members) do
                m.rank = m.rank or 'member'
                if mid == g.owner then hasOwner = true end
                Data.gangOf[mid] = gid
            end
            if not hasOwner then
                local first = next(g.members)
                if first then g.owner = first g.members[first].rank = 'owner' end
            end
            if not next(g.members) then
                Data.gangs[gid] = nil
                Data.lb.gangs[gid] = nil
            end
        end

        local migrated = 0
        for _, z in pairs(Data.zones) do
            local before = migrated
            if not z.type then z.type = 'redzone'; migrated = migrated + 1 end
            if z.type ~= 'safezone' then
                if z.allowTeleport      == nil then z.allowTeleport = false;      migrated = migrated + 1 end
                if z.teleportCost       == nil then z.teleportCost = 0;           migrated = migrated + 1 end
                if z.teleportCostSource == nil then z.teleportCostSource = 'cash'; migrated = migrated + 1 end
                if z.tpPoints           == nil then z.tpPoints = {};              migrated = migrated + 1 end
                if z.reviveCostSource   == nil then z.reviveCostSource = 'cash';  migrated = migrated + 1 end
                if z.killHeal           == nil then z.killHeal = 0;               migrated = migrated + 1 end
                if z.killHealFull       == nil then z.killHealFull = false;       migrated = migrated + 1 end
            end
            if z.showBlip == nil then z.showBlip = true; migrated = migrated + 1 end
            if z.showMarker == nil then z.showMarker = true; migrated = migrated + 1 end
            if z.type == 'safezone' and z.weaponMode == nil then
                z.weaponMode = (z.disableWeapons == false) and 'off' or 'holster'
                migrated = migrated + 1
            end
            if before ~= migrated then z._migrated = nil end
        end
        if migrated > 0 then
            print(('[lime_redzones] ^3Backfilled %d missing field(s) on existing zones.^0'):format(migrated))
            SaveData()
        end

        local rz, sz = 0, 0
        for _, z in pairs(Data.zones) do
            if z.type == 'safezone' then sz = sz + 1 else rz = rz + 1 end
        end
        print(('[lime_redzones] ^2Started^0 · FW: ^3%s^0 · Inv: ^3%s^0 · Storage: ^3%s^0 · Redzones: ^3%d^0 · Safe zones: ^3%d^0')
            :format(FWName, GetInventoryName(), HasSQL and 'MySQL' or 'JSON', rz, sz))
        Wait(500)
        BroadcastZones(-1)
    end)
end)

function PostLeaderboardLog(board, top)
    top = top or 10
    local store = (board == 'global') and Data.globalLb.players or Data.lb.players
    local list = {}
    for id, d in pairs(store) do list[#list+1] = { name = d.name, kills = d.kills or 0, deaths = d.deaths or 0 } end
    table.sort(list, function(a, b) return a.kills > b.kills end)

    local lines = {}
    for i = 1, math.min(top, #list) do
        local p = list[i]
        local medal = i == 1 and '🥇' or i == 2 and '🥈' or i == 3 and '🥉' or ('**' .. i .. '.**')
        lines[#lines+1] = ('%s %s — %d kills / %d deaths'):format(medal, p.name or 'Unknown', p.kills, p.deaths)
    end
    if #lines == 0 then lines[1] = '_No data yet._' end

    if Log then
        Log('leaderboard',
            ('🏆 %s Leaderboard — Top %d'):format(board == 'global' and 'Global' or 'Redzone', math.min(top, #list > 0 and #list or top)),
            table.concat(lines, '\n'))
    end
end
_G.PostLeaderboardLog = PostLeaderboardLog

function GetLogSettings()
    return Data.settings.logs or { enabled = true, categories = {}, webhooks = {}, leaderboardPost = {} }
end

function PostLeaderboardLog(board, top)
    top = top or 10
    local isGlobal = (board == 'global')
    local store = isGlobal and Data.globalLb.players or Data.lb.players
    local list = {}
    for _, d in pairs(store) do list[#list+1] = { name = d.name, kills = d.kills or 0, deaths = d.deaths or 0 } end
    table.sort(list, function(a, b) return a.kills > b.kills end)

    local lines = {}
    for i = 1, math.min(top, #list) do
        local p = list[i]
        local medal = i == 1 and '🥇' or i == 2 and '🥈' or i == 3 and '🥉' or ('**' .. i .. '.**')
        lines[#lines+1] = ('%s %s — %d kills / %d deaths'):format(medal, p.name or 'Unknown', p.kills, p.deaths)
    end
    if #lines == 0 then lines[1] = '_No data yet._' end

    if Log then
        Log(isGlobal and 'leaderboardGlobal' or 'leaderboardRz',
            ('🏆 %s Leaderboard — Top %d'):format(isGlobal and 'Global' or 'Redzone', math.min(top, math.max(#list, 1))),
            table.concat(lines, '\n'))
    end
end
_G.PostLeaderboardLog = PostLeaderboardLog

RegisterNetEvent('lime_redzones:server:wipeLogs', function(payload)
    local src = source
    if not HasPerm(src, 'logs') then return end
    local category = tostring(type(payload) == 'table' and payload.category or payload or 'all')
    if category ~= 'all' and category ~= 'admin' and category ~= 'kills' and category ~= 'revives' then return end

    WipeLogs(category, function(affected)
        NotifySv(src, ('Wiped %d log entr%s.'):format(affected, affected == 1 and 'y' or 'ies'), 'success')
        Log('admin', 'Logs Wiped', ('**%s** wiped %s logs (%d entries)'):format(GetPName(src), category, affected), nil, GetPName(src))
        GetLogsPaged(category == 'all' and 'admin' or category, 1, 10, nil, function(res)
            TriggerClientEvent('lime_redzones:client:logs', src, category == 'all' and 'admin' or category, res.entries, res.total, 1)
        end)
    end)
end)

RegisterNetEvent('lime_redzones:server:requestLogs', function(payload)
    local src = source
    if not HasPerm(src, 'logs') then return end
    if not reqOk(src, 0.3, 'logs') then return end

    payload = type(payload) == 'table' and payload or {}
    local category = tostring(payload.category or 'admin')
    if category ~= 'admin' and category ~= 'kills' and category ~= 'revives' then category = 'admin' end
    local page = math.max(1, math.floor(tonumber(payload.page) or 1))
    local perPage = math.max(5, math.min(50, math.floor(tonumber(payload.perPage) or 10)))
    local search = type(payload.search) == 'string' and payload.search:sub(1, 60) or nil

    GetLogsPaged(category, page, perPage, search, function(res)
        TriggerClientEvent('lime_redzones:client:logs', src, category, res.entries, res.total, page)
    end)
end)

RegisterNetEvent('lime_redzones:server:saveLogConfig', function(patch)
    local src = source
    if not GetAdminPerms(src)._full then NotifySv(src, 'Only full admins can change logging.', 'error') return end
    if type(patch) ~= 'table' then return end

    local L = Data.settings.logs
    if patch.enabled ~= nil then L.enabled = patch.enabled == true end
    if type(patch.categories) == 'table' then
        L.categories = L.categories or {}
        for k, v in pairs(patch.categories) do L.categories[k] = v == true end
    end
    if type(patch.webhooks) == 'table' then
        L.webhooks = L.webhooks or {}
        for k, v in pairs(patch.webhooks) do if type(v) == 'string' then L.webhooks[k] = v end end
    end
    if type(patch.leaderboardPost) == 'table' then
        L.leaderboardPost = L.leaderboardPost or {}
        for k, v in pairs(patch.leaderboardPost) do L.leaderboardPost[k] = v end
        L.leaderboardPost.interval = math.max(1, math.floor(tonumber(L.leaderboardPost.interval) or 30))
        L.leaderboardPost.top = math.max(3, math.min(25, math.floor(tonumber(L.leaderboardPost.top) or 10)))
    end

    if patch.retentionDays ~= nil then L.retentionDays = math.max(0, math.min(365, math.floor(tonumber(patch.retentionDays) or 14))) end
    SaveData()
    NotifySv(src, 'Logging settings saved.', 'success')
    if Log then Log('admin', 'Logging Updated', ('**%s** changed logging settings'):format(GetPName(src))) end
end)

RegisterNetEvent('lime_redzones:server:requestLogConfig', function()
    local src = source
    if not HasPerm(src, 'options') then return end
    TriggerClientEvent('lime_redzones:client:logConfig', src, GetLogSettings())
end)

RegisterNetEvent('lime_redzones:server:postLeaderboardNow', function(board)
    local src = source
    if not HasPerm(src, 'options') then return end
    board = (board == 'global') and 'global' or 'redzone'
    local top = (Data.settings.logs.leaderboardPost and Data.settings.logs.leaderboardPost.top) or 10
    PostLeaderboardLog(board, top)
    NotifySv(src, ('Posted %s leaderboard to Discord.'):format(board == 'global' and 'Global' or 'Redzone'), 'success')
    if Log then Log('admin', 'Leaderboard Posted', ('**%s** manually posted the %s leaderboard'):format(GetPName(src), board == 'global' and 'Global' or 'Redzone')) end
end)

RegisterNetEvent('lime_redzones:server:requestMyStats', function()
    local src = source
    if not reqOk(src, 0.5, 'mystats') then return end
    local id = GetIdentifier(src)
    local p = Data.lb.players[id]
    TriggerClientEvent('lime_redzones:client:myStats', src, p and p.kills or 0, p and p.deaths or 0)
end)

RegisterNetEvent('lime_redzones:server:requestStats', function()
    local src = source
    if not IsAdmin(src) then return end
    if not reqOk(src, 1.0, 'stats') then return end

    local totalZones, activeZones = 0, 0
    local zoneList = {}
    for id, z in pairs(Data.zones) do
        totalZones = totalZones + 1
        if z.enabled then activeZones = activeZones + 1 end
        zoneList[#zoneList+1] = { id = id, name = z.name or id, enabled = z.enabled and true or false, kills = z.kills or 0 }
    end
    table.sort(zoneList, function(a, b) return (a.kills or 0) > (b.kills or 0) end)

    local playersTracked, totalKills, totalDeaths = 0, 0, 0
    local top = {}
    for _, p in pairs(Data.lb.players) do
        playersTracked = playersTracked + 1
        totalKills = totalKills + (p.kills or 0)
        totalDeaths = totalDeaths + (p.deaths or 0)
        top[#top+1] = { name = p.name, kills = p.kills or 0, deaths = p.deaths or 0 }
    end
    table.sort(top, function(a, b) return a.kills > b.kills end)
    local topPlayers = {}
    for i = 1, math.min(5, #top) do topPlayers[i] = top[i] end

    local gangs = 0
    for _ in pairs(Data.lb.gangs or {}) do gangs = gangs + 1 end

    TriggerClientEvent('lime_redzones:client:stats', src, {
        totalZones = totalZones, activeZones = activeZones, zoneList = zoneList,
        playersTracked = playersTracked, totalKills = totalKills, totalDeaths = totalDeaths,
        topPlayers = topPlayers, gangs = gangs, admins = #(Data.settings.admins or {}),
    })
end)

RegisterNetEvent('lime_redzones:server:wipePrizeHistory', function()
    local src = source
    if not HasPerm(src, 'leaderboards') then return end
    Data.prizeHistory = {}
    SaveData()
    TriggerClientEvent('lime_redzones:client:prizeHistory', src, {})
    NotifySv(src, 'Past winners wiped.', 'success')
    if Log then Log('admin', 'Past Winners Wiped', ('**%s** wiped the past winners list'):format(GetPName(src))) end
end)

RegisterNetEvent('lime_redzones:server:deletePrizeEntry', function(payload)
    local src = source
    if not HasPerm(src, 'leaderboards') then return end
    local idx = tonumber(type(payload) == 'table' and payload.index or payload)
    if not idx or not Data.prizeHistory or not Data.prizeHistory[idx + 1] then return end
    local entry = table.remove(Data.prizeHistory, idx + 1)
    SaveData()
    TriggerClientEvent('lime_redzones:client:prizeHistory', src, Data.prizeHistory)
    NotifySv(src, 'Winner entry removed.', 'success')
    if Log then Log('admin', 'Past Winner Removed', ('**%s** removed a past-winner entry (**%s**)'):format(GetPName(src), entry and entry.name or 'unknown')) end
end)

RegisterNetEvent('lime_redzones:server:requestPrizeHistory', function()
    local src = source
    if not reqOk(src, 1.0, 'prizehistory') then return end
    TriggerClientEvent('lime_redzones:client:prizeHistory', src, Data.prizeHistory or {})
end)

local lastSnapshot = {}
local podiumWatch = {}

CreateThread(function()
    while true do
        Wait(600000)
        local cutoff = os.time() - 300
        for id, t in pairs(lastSnapshot) do
            if t < cutoff then lastSnapshot[id] = nil end
        end
    end
end)

local function BoardStore(board)
    return board == 'global' and Data.globalLb.players or Data.lb.players
end

local function TopThree(board)
    local ranked = board == 'ranked'
    local list = {}
    for id, d in pairs(BoardStore(ranked and 'redzone' or board)) do
        local keep = ranked and d.elo ~= nil or (d.kills or 0) > 0
        if keep then
            local rating = EloOf(d)
            local tier, colour = EloRankOf(rating)
            list[#list+1] = {
                identifier = id, name = d.name,
                kills = d.kills or 0, deaths = d.deaths or 0,
                elo = rating, rank = tier, color = colour,
                appearance = d.appearance,
            }
        end
    end
    if ranked then
        table.sort(list, function(a, b) return a.elo > b.elo end)
    else
        table.sort(list, function(a, b)
            if a.kills == b.kills then return (a.deaths or 0) < (b.deaths or 0) end
            return a.kills > b.kills
        end)
    end
    local out = {}
    for i = 1, math.min(3, #list) do out[i] = list[i] end
    return out
end

local function TopThreeCached(cache, board)
    board = board or 'redzone'
    local hit = cache[board]
    if hit == nil then
        hit = TopThree(board)
        cache[board] = hit
    end
    return hit
end

function PushPodiums(target)
    local payload, cache = {}, {}
    for id, p in pairs(Data.podiums) do
        if type(p.points) == 'table' and #p.points > 0 then
            local winners = {}
            for i, w in ipairs(TopThreeCached(cache, p.board)) do
                winners[i] = {
                    name = w.name, kills = w.kills, deaths = w.deaths,
                    elo = w.elo, rank = w.rank, color = w.color,
                    appearance = w.appearance,
                }
            end
            payload[#payload+1] = {
                id = id, label = p.label, board = p.board,
                points = p.points, winners = winners,
            }
        end
    end
    TriggerClientEvent('lime_redzones:client:syncPodiums', target or -1, payload)
end

local SNAPSHOT_REFRESH = 300
local SNAPSHOT_RETRY   = 20

local function PodiumBoards()
    local boards = {}
    for _, p in pairs(Data.podiums) do boards[p.board or 'redzone'] = true end
    return boards
end

local function StoredAppearance(id)
    local rec = Data.lb.players[id] or Data.globalLb.players[id]
    return rec and rec.appearance or nil
end

local function AskForSnapshot(src, id, gap)
    local now = os.time()
    if lastSnapshot[id] and (now - lastSnapshot[id]) < gap then return end
    lastSnapshot[id] = now
    TriggerClientEvent('lime_redzones:client:captureAppearance', src)
end

function MaybeSnapshotPublic(src)
    if not next(Data.podiums) then return end
    local id = GetIdentifier(src)
    if not id then return end

    local cache = {}
    local wanted = false
    for board in pairs(PodiumBoards()) do
        for _, w in ipairs(TopThreeCached(cache, board)) do
            if w.identifier == id then wanted = true break end
        end
        if wanted then break end
    end
    if not wanted then return end

    AskForSnapshot(src, id, StoredAppearance(id) and SNAPSHOT_REFRESH or SNAPSHOT_RETRY)
end

local function PodiumIdentifiers()
    local cache, want = {}, {}
    if not next(Data.podiums) then return want end
    for board in pairs(PodiumBoards()) do
        for _, w in ipairs(TopThreeCached(cache, board)) do
            want[w.identifier] = w
        end
    end
    return want
end

local function SetPodiumWatch(src, on)
    if podiumWatch[src] == on then return end
    podiumWatch[src] = on
    TriggerClientEvent('lime_redzones:client:podiumWatch', src, on)
end

function PodiumWatchDropped(src) podiumWatch[src] = nil end

local function SyncPodiumWatchFor(src, want)
    local id = GetIdentifier(src)
    local w = id and (want or PodiumIdentifiers())[id]
    SetPodiumWatch(src, w ~= nil)
    if w and not w.appearance then AskForSnapshot(src, id, SNAPSHOT_RETRY) end
end

local function SyncPodiumWatch()
    local want = PodiumIdentifiers()
    for _, sid in ipairs(GetPlayers()) do
        SyncPodiumWatchFor(tonumber(sid), want)
    end
end

local function PodiumSignature()
    local cache, parts = {}, {}
    for id, p in pairs(Data.podiums) do
        local row = { id }
        for i = 1, 3 do
            local w = TopThreeCached(cache, p.board)[i]
            row[#row+1] = w and ('%s/%s/%s/%s'):format(
                tostring(w.identifier), tostring(w.kills), tostring(w.elo),
                w.appearance and tostring(w.appearance.sig or w.appearance.model) or '-') or '-'
        end
        parts[#parts+1] = table.concat(row, '|')
    end
    table.sort(parts)
    return table.concat(parts, ';')
end

local lastPodiumSig = nil

CreateThread(function()
    while true do
        Wait(2500)
        if PodiumsDirty then
            PodiumsDirty = false
            local sig = next(Data.podiums) and PodiumSignature() or ''
            if sig ~= lastPodiumSig then
                lastPodiumSig = sig
                PushPodiums(-1)
            end
            SyncPodiumWatch()
        end
    end
end)

local function AppearanceSig(a)
    local parts = { tostring(a.model), tostring(a.hair), tostring(a.hairHl), tostring(a.eyes) }
    for _, c in ipairs(a.comps or {}) do parts[#parts+1] = 'c' .. table.concat(c, ',') end
    for _, p in ipairs(a.props or {}) do parts[#parts+1] = 'p' .. table.concat(p, ',') end
    if a.blend then parts[#parts+1] = 'b' .. table.concat(a.blend, ',') end
    for _, o in ipairs(a.overlays or {}) do parts[#parts+1] = 'o' .. table.concat(o, ',') end
    for _, f in ipairs(a.features or {}) do parts[#parts+1] = 'f' .. table.concat(f, ',') end
    local s = table.concat(parts, '|')
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return h
end

RegisterNetEvent('lime_redzones:server:appearanceSnapshot', function(appearance)
    local src = source
    if not reqOk(src, 3.0, 'appearance') then return end
    if type(appearance) ~= 'table' or type(appearance.model) ~= 'number' then return end
    local comps, props = {}, {}
    if type(appearance.comps) == 'table' then
        for i = 1, math.min(12, #appearance.comps) do
            local c = appearance.comps[i]
            if type(c) == 'table' then
                comps[#comps+1] = { tonumber(c[1]) or 0, tonumber(c[2]) or 0, tonumber(c[3]) or 0, tonumber(c[4]) or 0 }
            end
        end
    end
    if type(appearance.props) == 'table' then
        for i = 1, math.min(8, #appearance.props) do
            local pr = appearance.props[i]
            if type(pr) == 'table' then
                props[#props+1] = { tonumber(pr[1]) or 0, tonumber(pr[2]) or 0, tonumber(pr[3]) or 0 }
            end
        end
    end

    local blend
    if type(appearance.blend) == 'table' and #appearance.blend >= 9 then
        blend = {}
        for i = 1, 9 do blend[i] = tonumber(appearance.blend[i]) or 0 end
    end
    local overlays = {}
    if type(appearance.overlays) == 'table' then
        for i = 1, math.min(13, #appearance.overlays) do
            local o = appearance.overlays[i]
            if type(o) == 'table' then
                overlays[#overlays + 1] = {
                    tonumber(o[1]) or 0, tonumber(o[2]) or 255, tonumber(o[3]) or 0,
                    tonumber(o[4]) or 0, tonumber(o[5]) or 0, tonumber(o[6]) or 1.0,
                }
            end
        end
    end
    local features = {}
    if type(appearance.features) == 'table' then
        for i = 1, math.min(20, #appearance.features) do
            local f = appearance.features[i]
            if type(f) == 'table' then
                features[#features + 1] = { tonumber(f[1]) or 0, tonumber(f[2]) or 0.0 }
            end
        end
    end

    local clean = {
        model = appearance.model, comps = comps, props = props,
        blend = blend, overlays = overlays, features = features,
        hair = tonumber(appearance.hair) or 0,
        hairHl = tonumber(appearance.hairHl) or 0,
        eyes = tonumber(appearance.eyes) or 0,
    }
    clean.sig = AppearanceSig(clean)
    local id = GetIdentifier(src)
    if not id then return end

    local prev = StoredAppearance(id)
    if prev and prev.sig == clean.sig then return end

    if Data.lb.players[id]       then Data.lb.players[id].appearance = clean end
    if Data.globalLb.players[id] then Data.globalLb.players[id].appearance = clean end
    SaveData()
    PodiumsDirty = true
end)

RegisterNetEvent('lime_redzones:server:requestPodiums', function()
    local src = source
    PushPodiums(src)
    SyncPodiumWatchFor(src)
end)

RegisterNetEvent('lime_redzones:server:savePodium', function(d)
    local src = source
    if not HasPerm(src, 'zones') then NotifySv(src, _U('no_permission'), 'error') return end
    if type(d) ~= 'table' then return end

    local id = tostring(d.id or '')
    if id == '' or Data.podiums[id] == nil then
        id = tostring(Data.nextPodiumId or 1)
        Data.nextPodiumId = (Data.nextPodiumId or 1) + 1
    end

    local points = {}
    if type(d.points) == 'table' then
        for i = 1, math.min(3, #d.points) do
            local p = d.points[i]
            if type(p) == 'table' and tonumber(p.x) and tonumber(p.y) and tonumber(p.z) then
                points[#points+1] = { x = tonumber(p.x), y = tonumber(p.y), z = tonumber(p.z), h = tonumber(p.h) or 0.0 }
            end
        end
    end

    Data.podiums[id] = {
        id = id,
        label = tostring(d.label or ('Podium ' .. id)):sub(1, 40),
        board = (d.board == 'global' and 'global') or (d.board == 'ranked' and 'ranked') or 'redzone',
        points = points,
    }
    SaveData()
    PodiumsDirty = true
    NotifySv(src, ('Podium "%s" saved (%d position%s).'):format(Data.podiums[id].label, #points, #points == 1 and '' or 's'), 'success')
    if Log then
        Log('admin', 'Podium Saved', ('**%s** saved podium **%s**'):format(GetPName(src), Data.podiums[id].label),
            { { name = 'Board', value = Data.podiums[id].board, inline = true },
              { name = 'Spots', value = tostring(#points), inline = true } })
    end
end)

RegisterNetEvent('lime_redzones:server:deletePodium', function(id)
    local src = source
    if not HasPerm(src, 'zones') then NotifySv(src, _U('no_permission'), 'error') return end
    id = tostring(id or '')
    local p = Data.podiums[id]
    if not p then return end
    Data.podiums[id] = nil
    SaveData()
    PodiumsDirty = true
    NotifySv(src, ('Podium "%s" deleted.'):format(p.label or id), 'success')
end)

RegisterNetEvent('lime_redzones:server:beginPodiumPlacement', function(id, label, board)
    local src = source
    if not HasPerm(src, 'zones') then NotifySv(src, _U('no_permission'), 'error') return end
    id = tostring(id or '')
    local existing = Data.podiums[id]
    TriggerClientEvent('lime_redzones:client:beginPodiumPlacement', src, {
        id = existing and existing.id or '',
        label = existing and existing.label or (label ~= nil and tostring(label) or 'Podium'),
        board = existing and existing.board or ((board == 'global' and 'global') or (board == 'ranked' and 'ranked') or 'redzone'),
        points = existing and existing.points or {},
    })
end)

local function EloCfg() return Data.settings.elo or {} end
function EloEnabled() return EloCfg().enabled ~= false end

function EloOf(rec)
    if type(rec) ~= 'table' then return EloCfg().start or 1000 end
    return tonumber(rec.elo) or (EloCfg().start or 1000)
end

function EloRankOf(rating)
    local ranks = Data.settings.eloRanks or {}
    local best = ranks[1]
    for i = 1, #ranks do
        if rating >= (ranks[i].min or 0) then best = ranks[i] end
    end
    return best and best.name or 'Unranked', best and best.color or '#ffffff'
end

local function kFactor(rec)
    local c = EloCfg()
    local rating = EloOf(rec)
    local fights = (rec.kills or 0) + (rec.deaths or 0)
    local k
    if fights < (c.provisional or 30) then k = c.kNew or 48
    elseif rating >= (c.highAt or 2000) then k = c.kHigh or 20
    else k = c.kMid or 32 end

    local kd = (rec.deaths or 0) > 0 and (rec.kills or 0) / rec.deaths or (rec.kills or 0)
    if kd > 1 then
        local boost = math.min((kd - 1) * 0.15, c.kdBoostMax or 0.25)
        k = k * (1 + boost)
    end
    return k
end

local function expected(ra, rb)
    return 1.0 / (1.0 + 10.0 ^ ((rb - ra) / 400.0))
end

local function applyElo(rec, delta)
    local c = EloCfg()
    local newRating = EloOf(rec) + delta
    local floor = c.floor or 0
    if newRating < floor then newRating = floor end
    rec.elo = math.floor(newRating + 0.5)
    return rec.elo
end

function EloExchange(killerRec, victimRec, streak)
    if not EloEnabled() then return end
    local c = EloCfg()
    local ra, rb = EloOf(killerRec), EloOf(victimRec)
    local ea = expected(ra, rb)

    local gain = kFactor(killerRec) * (1.0 - ea)
    local loss = kFactor(victimRec) * (1.0 - expected(rb, ra))

    local bonus = 0
    streak = tonumber(streak) or 0
    if streak >= (c.streakFrom or 3) then
        bonus = math.min((streak - (c.streakFrom or 3) + 1) * (c.streakStep or 3), c.streakCap or 30)
    end

    local after  = applyElo(killerRec, gain + bonus)
    local vAfter = applyElo(victimRec, -loss)
    return after, after - ra, vAfter, vAfter - rb, bonus
end

function EloForSrc(src)
    local id = GetIdentifier(src)
    if not id then return EloCfg().start or 1000 end
    return EloOf(Data.lb.players[id])
end

RegisterNetEvent('lime_redzones:server:requestElo', function()
    local src = source
    if not EloEnabled() then
        TriggerClientEvent('lime_redzones:client:eloRanks', src, {}, false)
        return
    end
    local rating = EloForSrc(src)
    local name, color = EloRankOf(rating)
    TriggerClientEvent('lime_redzones:client:elo', src, rating, name, color)
    TriggerClientEvent('lime_redzones:client:eloRanks', src, Data.settings.eloRanks or {}, true)
end)

local function num(v, default, lo, hi)
    local n = tonumber(v)
    if not n then return default end
    if lo and n < lo then n = lo end
    if hi and n > hi then n = hi end
    return n
end

RegisterNetEvent('lime_redzones:server:saveEloSettings', function(d)
    local src = source
    if not HasPerm(src, 'leaderboards') then NotifySv(src, _U('no_permission'), 'error') return end
    if type(d) ~= 'table' then return end
    local e = Data.settings.elo

    e.enabled     = d.enabled ~= false
    e.start       = num(d.start,       e.start,       0,    5000)
    e.floor       = num(d.floor,       e.floor,       0,    5000)
    e.kNew        = num(d.kNew,        e.kNew,        1,    200)
    e.kMid        = num(d.kMid,        e.kMid,        1,    200)
    e.kHigh       = num(d.kHigh,       e.kHigh,       1,    200)
    e.provisional = num(d.provisional, e.provisional, 0,    1000)
    e.highAt      = num(d.highAt,      e.highAt,      0,    10000)
    e.streakFrom  = num(d.streakFrom,  e.streakFrom,  1,    100)
    e.streakStep  = num(d.streakStep,  e.streakStep,  0,    100)
    e.streakCap   = num(d.streakCap,   e.streakCap,   0,    500)
    e.kdBoostMax  = num(d.kdBoostMax,  e.kdBoostMax,  0,    2)

    SaveData()
    NotifySv(src, 'Elo settings saved.', 'success')
    TriggerClientEvent('lime_redzones:client:adminData', src, nil, nil, Data.settings, GetAdminPerms(src))
    PushEloAll()
end)

RegisterNetEvent('lime_redzones:server:saveEloRanks', function(list)
    local src = source
    if not HasPerm(src, 'leaderboards') then NotifySv(src, _U('no_permission'), 'error') return end
    if type(list) ~= 'table' then return end

    local out = {}
    for i = 1, math.min(30, #list) do
        local r = list[i]
        if type(r) == 'table' then
            local name = tostring(r.name or ''):sub(1, 20)
            local color = tostring(r.color or '')
            if name ~= '' then
                out[#out+1] = {
                    min   = num(r.min, 0, 0, 100000),
                    name  = name,
                    color = color:match('^#%x%x%x%x%x%x$') and color or '#ffffff',
                }
            end
        end
    end
    if #out == 0 then NotifySv(src, 'Keep at least one rank tier.', 'error') return end
    table.sort(out, function(a, b) return a.min < b.min end)

    Data.settings.eloRanks = out
    SaveData()
    NotifySv(src, ('Saved %d rank tier%s.'):format(#out, #out == 1 and '' or 's'), 'success')
    TriggerClientEvent('lime_redzones:client:adminData', src, nil, nil, Data.settings, GetAdminPerms(src))
    PushEloAll()
end)

RegisterNetEvent('lime_redzones:server:requestPodiumAdmin', function()
    local src = source
    if not HasPerm(src, 'zones') then return end
    local list = {}
    for id, p in pairs(Data.podiums) do
        list[#list+1] = { id = id, label = p.label, board = p.board, count = #(p.points or {}) }
    end
    table.sort(list, function(a, b) return (a.label or '') < (b.label or '') end)
    TriggerClientEvent('lime_redzones:client:podiumAdmin', src, list)
end)

function RZOption(key, default)
    local v = Data.settings and Data.settings.options and Data.settings.options[key]
    if v == nil then return default end
    return v
end

function PushEloAll()
    local ranks = Data.settings.eloRanks or {}
    local on = EloEnabled()
    TriggerClientEvent('lime_redzones:client:eloRanks', -1, ranks, on)
    if not on then return end
    for _, src in ipairs(GetPlayers()) do
        src = tonumber(src)
        local rating = EloForSrc(src)
        local name, color = EloRankOf(rating)
        TriggerClientEvent('lime_redzones:client:elo', src, rating, name, color)
    end
end

RegisterNetEvent('lime_redzones:server:wipeElo', function()
    local src = source
    if not HasPerm(src, 'leaderboards') then NotifySv(src, _U('no_permission'), 'error') return end
    local n = 0
    for _, store in ipairs({ Data.lb.players, Data.globalLb.players }) do
        for _, rec in pairs(store) do
            if rec.elo ~= nil then rec.elo = nil n = n + 1 end
        end
    end
    SaveData()
    PushEloAll()
    PushLeaderboard(-1)
    NotifySv(src, ('Reset %d rating%s — everyone starts fresh.'):format(n, n == 1 and '' or 's'), 'success')
    if Log then
        Log('admin', 'Elo Reset', ('**%s** reset all Redzone Elo ratings'):format(GetPName(src)),
            { { name = 'Records cleared', value = tostring(n), inline = true } })
    end
end)
