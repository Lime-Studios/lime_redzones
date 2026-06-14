local FW, FWName = nil, 'none'
if GetResourceState('qbx_core') == 'started' then FWName = 'qbx'
elseif GetResourceState('qb-core') == 'started' then FW, FWName = exports['qb-core']:GetCoreObject(), 'qb'
elseif GetResourceState('es_extended') == 'started' then FW, FWName = exports['es_extended']:getSharedObject(), 'esx' end

local HasSQL = GetResourceState('oxmysql') == 'started'

local Data = {
    zones = {}, customGangs = {}, nextZoneId = 1,
    lb       = { players = {}, gangs = {} },
    globalLb = { players = {} },
    pendingPrizes = {},
    settings = {
        reset       = { enabled = false, day = 0, hour = 18, prizeName = 'money', prizeAmount = 50000, lastReset = 0 },
        globalReset = { enabled = false, day = 0, hour = 18, prizeName = 'money', prizeAmount = 25000, lastReset = 0 },
        options     = {
            rewardNotify = true, streakAnnounce = true, renderDistance = 120,
            leaderboardEnabled = true, globalLbEnabled = true,
            streaksEnabled = true, personalColorEnabled = true,
            personalColorOpacity = true, personalColorHue = true,
            gangLbEnabled = true, killFeedEnabled = true, killCamEnabled = true, killMessageEnabled = true,
            hudDefaultPreset = 'top', hudDefaultTheme = 'lime',
            killFeedDuration = 6000, killCamDuration = 5000,
            lbCols = { kills = true, deaths = true, kd = true, streak = false },
        },
        admins      = {},
        ranks       = {
            { name = 'Moderator', perms = { zones = false, gangs = false, leaderboards = true, options = false, killfeed = false } },
            { name = 'Admin',     perms = { zones = true,  gangs = true,  leaderboards = true, options = true,  killfeed = true } },
        },
    },
}

local saveQueued = false
local function WriteNow()
    if not HasSQL then return end
    exports.oxmysql:update('UPDATE lime_redzones SET data = ? WHERE id = 1', { json.encode(Data) })
end

function SaveData()
    if saveQueued then return end
    saveQueued = true
    SetTimeout(2000, function()
        saveQueued = false
        WriteNow()
    end)
end

-- Flush immediately (used on shutdown so nothing is lost to the debounce).
function SaveDataNow()
    saveQueued = false
    WriteNow()
end

local function deepMerge(target, src)
    for k, v in pairs(src) do
        if type(v) == 'table' and type(target[k]) == 'table' then
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
            -- Deep-merge so saved values win but any newly-added default keys survive.
            deepMerge(Data.settings, v)
        else
            Data[k] = v
        end
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

local DEFAULT_ZONE = {
    id = '1', name = 'Ambush Zone',
    coords = { x = 1204.55, y = -1288.42, z = 35.23 },
    radius = 60.0, colorHex = '#FF0000', colorA = 80,
    blipSprite = 310, blipColor = 1,
    rewardItems   = { { name = 'money', amount = 5000 } },
    streakRewards = { { streak = 3, name = 'armor', amount = 1 }, { streak = 5, name = 'money', amount = 2500 } },
    reviveCost = 10000, reviveInside = true, reviveDelay = 8000,
    teleportAway = 30.0, exits = {}, enabled = true,
}

local function SeedIfEmpty()
    if not next(Data.zones) and Config.SeedDefaultZone ~= false then
        Data.zones['1'] = DEFAULT_ZONE
        Data.nextZoneId = 2
        SaveData()
    end
end

local function LoadData(done)
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
            end)
        end)
    end
end

local function GetPlayer(src)
    if FWName == 'qbx' then return exports.qbx_core:GetPlayer(src)
    elseif FWName == 'qb' then return FW.Functions.GetPlayer(src)
    elseif FWName == 'esx' then return FW.GetPlayerFromId(src) end
end

local function GetPName(src)
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
    local p = GetPlayer(src)
    if not p then return end
    if FWName == 'qbx' or FWName == 'qb' then p.Functions.AddMoney('cash', amount, 'redzone')
    elseif FWName == 'esx' then p.addMoney(amount) end
end

local function GiveItem(src, item, amount)
    if item == 'money' or item == 'cash' then AddCash(src, amount) return true end
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

local function GetGang(src)
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

local function GetIdentifier(src)
    local p = GetPlayer(src)
    if p and (FWName == 'qbx' or FWName == 'qb') then return p.PlayerData.citizenid end
    return GetPlayerIdentifierByType(src, 'license') or tostring(src)
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
    if FWName == 'qbx' then
        local ok, r = pcall(function() return exports.qbx_core:HasPermission(src, 'admin') end)
        return ok and r
    elseif FWName == 'qb' then return FW.Functions.HasPermission(src, 'admin')
    elseif FWName == 'esx' then
        local p = GetPlayer(src)
        return p and (p.getGroup() == 'admin' or p.getGroup() == 'superadmin')
    end
    return false
end

local function PlayerDistFromZone(src, zone)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    local pos = GetEntityCoords(ped)
    if not pos or (pos.x == 0.0 and pos.y == 0.0 and pos.z == 0.0) then return nil end
    return #(pos - vector3(zone.coords.x, zone.coords.y, zone.coords.z))
end

local function PlayerInZone(src, zone, slack)
    local dist = PlayerDistFromZone(src, zone)
    -- Fail-open: if position is unreadable (OneSync off / sync gap), trust the
    -- client's own in-zone check rather than silently dropping a real kill.
    if dist == nil then return true end
    return dist <= (zone.radius + (slack or 30.0))
end

local function PlayerInAnyZone(src, slack)
    for _, z in pairs(Data.zones) do
        if z.enabled and PlayerInZone(src, z, slack) then return true end
    end
    return false
end

local function GetAdminPerms(src)
    if src == 0 or IsPlayerAceAllowed(src, 'lime_redzones.god') or IsPlayerAceAllowed(src, 'god') then
        return { zones = true, gangs = true, leaderboards = true, options = true, killfeed = true, _full = true }
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
    return { zones = true, gangs = true, leaderboards = true, options = true, killfeed = true }
end

-- Section-level permission gate for admin events.
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

local WEAPON_NAMES = {
    [453432689] = 'Pistol', [1593441988] = 'Combat Pistol', [-1716589765] = 'Pistol .50',
    [-1076751822] = 'SNS Pistol', [-771403250] = 'Heavy Pistol', [137902532] = 'Vintage Pistol',
    [-1063057011] = 'AP Pistol', [-1045183535] = 'Assault Rifle', [-2084633992] = 'Carbine Rifle',
    [-1357824103] = 'Advanced Rifle', [-1063057001] = 'Special Carbine', [2132975508] = 'Bullpup Rifle',
    [-494615257] = 'Micro SMG', [324215364] = 'SMG', [736523883] = 'Assault SMG', [-619010992] = 'Combat PDW',
    [487013001] = 'Pump Shotgun', [2017895192] = 'Sawed-Off', [-1654528753] = 'Bullpup Shotgun',
    [100416529] = 'Sniper Rifle', [205991906] = 'Heavy Sniper', [-1357824103] = 'Rifle',
    [-1466123335] = 'Knife', [-122831616] = 'Pistol Mk2', [-1075685676] = 'Pistol Mk2',
    [3220176749] = 'Heavy Revolver', [-879347409] = 'Revolver', [-853065399] = 'Combat MG',
    [-1660422300] = 'MG', [911657153] = 'Stun Gun', [615608432] = 'Melee', [-1786099057] = 'Nightstick',
    [1737195953] = 'Unarmed', [-1569615261] = 'Unarmed',
}

local function WeaponLabel(w)
    w = tonumber(w)
    if not w then return 'Weapon' end
    return WEAPON_NAMES[w] or 'Weapon'
end

local function PushLeaderboard(target)
    local pList, gList, glList = {}, {}, {}
    local rzKills, rzDeaths = 0, 0
    local glKills, glDeaths = 0, 0

    for id, d in pairs(Data.lb.players) do
        pList[#pList+1] = { id = id, name = d.name, kills = d.kills, deaths = d.deaths }
        rzKills, rzDeaths = rzKills + d.kills, rzDeaths + d.deaths
    end
    table.sort(pList, function(a, b) return a.kills > b.kills end)

    for _, d in pairs(Data.lb.gangs) do
        gList[#gList+1] = { label = d.label, kills = d.kills, deaths = d.deaths }
    end
    table.sort(gList, function(a, b) return a.kills > b.kills end)

    for id, d in pairs(Data.globalLb.players) do
        glList[#glList+1] = { id = id, name = d.name, kills = d.kills, deaths = d.deaths }
        glKills, glDeaths = glKills + d.kills, glDeaths + d.deaths
    end
    table.sort(glList, function(a, b) return a.kills > b.kills end)

    TriggerClientEvent('lime_redzones:client:updateLeaderboard', target or -1,
        cap(pList, 30), cap(gList, 30), cap(glList, 30),
        {
            -- RZ board totals
            kills = rzKills, deaths = rzDeaths, players = #pList,
            -- Global board totals (separate)
            globalKills = glKills, globalDeaths = glDeaths, globalPlayersCount = #glList,
            reset = ResetInfo(Data.settings.reset),
            globalReset = ResetInfo(Data.settings.globalReset),
            cols = Data.settings.options.lbCols,
            gangLb = Data.settings.options.gangLbEnabled ~= false,
            options = Data.settings.options,
        })
end

local function EnsureP(store, src)
    local id = GetIdentifier(src)
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
                name == 'money' and ('$' .. amount) or (amount .. 'x ' .. name)), 'success')
            return
        end
    end
    Data.pendingPrizes[identifier] = { name = name, amount = amount }
end

local function DoReset(which)
    local cfg = Data.settings[which]
    local store = which == 'reset' and Data.lb.players or Data.globalLb.players

    if cfg.prizeAmount and cfg.prizeAmount > 0 then
        local top, topKills = nil, -1
        for id, d in pairs(store) do
            if d.kills > topKills then top, topKills = id, d.kills end
        end
        if top and topKills > 0 then
            GrantPrizeOrQueue(top, cfg.prizeName or 'money', cfg.prizeAmount)
        end
    end

    if which == 'reset' then Data.lb = { players = {}, gangs = {} }
    else Data.globalLb = { players = {} } end
    cfg.lastReset = os.time()
    SaveData()
    PushLeaderboard(-1)
    print(('[lime_redzones] %s leaderboard reset complete.'):format(which == 'reset' and 'Zone' or 'Global'))
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
                prize.name == 'money' and ('$' .. prize.amount) or (prize.amount .. 'x ' .. prize.name)), 'success')
            SaveData()
        end
    end)
end)

local RZ_DEBUG_SV = GetConvar('lime_redzones_debug', 'false') == 'true'
local function dbgsv(...) if RZ_DEBUG_SV then print('[lime_redzones:sv]', ...) end end

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

    local now = os.clock()
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
            parts[#parts+1] = item.name == 'money' and ('$' .. amt) or (amt .. 'x ' .. item.name)
        end
    end
    for _, sr in ipairs(zone.streakRewards or {}) do
        if Data.settings.options.streaksEnabled ~= false and tonumber(sr.streak) == streak then
            local amt = RewardAmount(sr)
            if GiveItem(src, sr.name, amt) then
                parts[#parts+1] = ('STREAK %d: %s'):format(streak,
                    sr.name == 'money' and ('$' .. amt) or (amt .. 'x ' .. sr.name))
            end
        end
    end
    if #parts > 0 and Data.settings.options.rewardNotify ~= false then
        NotifySv(src, 'Reward: ' .. table.concat(parts, ' · '), 'success')
    end

    local lb = EnsureP(Data.lb.players, src)
    lb.kills = lb.kills + 1
    -- Redzone kills also count toward the server-wide Global leaderboard.
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
    if Data.settings.options.killFeedEnabled ~= false then
        local victimName = 'Enemy'
        local vId = tonumber(victimId) or 0
        if vId > 0 then victimName = GetPName(vId) end
        TriggerClientEvent('lime_redzones:client:killFeed', -1, {
            killer = GetPName(src), killerId = src,
            victim = victimName, victimId = vId,
            weapon = WeaponLabel(weapon), streak = streak,
            duration = Data.settings.options.killFeedDuration or 6000,
        })
    end
    SaveData()
    PushLeaderboard(-1)
end)

RegisterNetEvent('lime_redzones:server:reportDeath', function(zoneId)
    local src = source
    if zoneId == nil then return end
    zoneId = tostring(zoneId)
    local zone = Data.zones[tostring(zoneId)]
    if not zone then return end

    local now = os.clock()
    if lastDeath[src] and (now - lastDeath[src]) < 5.0 then return end
    if not PlayerInZone(src, zone, 50.0) then return end
    lastDeath[src] = now

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
    local now = os.clock()
    if lastGlobal[src] and (now - lastGlobal[src]) < 1.5 then return end
    lastGlobal[src] = now

    local lb = EnsureP(Data.globalLb.players, src)
    lb.kills = lb.kills + 1
    SaveData()
    PushLeaderboard(-1)
end)

RegisterNetEvent('lime_redzones:server:globalDeath', function()
    if Data.settings.options.globalLbEnabled == false then return end
    local src = source
    local lb = EnsureP(Data.globalLb.players, src)
    lb.deaths = lb.deaths + 1
    SaveData()
    PushLeaderboard(-1)
end)

RegisterNetEvent('lime_redzones:server:attemptRevive', function(zoneId, coords, heading)
    local src  = source
    local zone = Data.zones[tostring(zoneId)]
    if not zone then return end

    local now = os.clock()
    if lastRevive[src] and (now - lastRevive[src]) < 8.0 then return end
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
    if not valid then
        local away = zone.radius + (tonumber(zone.teleportAway) or 30.0)
        coords = { x = zx + away, y = zy, z = zz }
    else
        coords = { x = cx, y = cy, z = cz }
    end
    heading = tonumber(heading) or 0.0

    local cost = tonumber(zone.reviveCost) or 0
    if RemoveCash(src, cost) then
        DoRevive(src, coords, heading)
        if cost > 0 then NotifySv(src, ('Revived — $%s deducted.'):format(cost), 'success') end
    else
        NotifySv(src, ('You need $%s cash to be revived here.'):format(cost), 'error')
        TriggerClientEvent('lime_redzones:client:reviveDenied', src)
    end
end)

RegisterNetEvent('lime_redzones:server:requestLeaderboard', function()
    if Data.settings.options.leaderboardEnabled == false and not IsAdmin(source) then
        NotifySv(source, 'The leaderboard is currently disabled.', 'error')
        return
    end
    PushLeaderboard(source)
end)
RegisterNetEvent('lime_redzones:server:requestZones', function()
    BroadcastZones(source)
    TriggerClientEvent('lime_redzones:client:syncOptions', source, Data.settings.options)
end)

RegisterNetEvent('lime_redzones:server:myIdentifier', function()
    local src = source
    if not IsAdmin(src) then return end
    TriggerClientEvent('lime_redzones:client:myIdentifier', src,
        GetPlayerIdentifierByType(src, 'license') or '', GetIdentifier(src))
end)

AddEventHandler('playerDropped', function()
    local src = source
    streaks[src], lastKill[src], lastDeath[src], lastGlobal[src], lastRevive[src] = nil, nil, nil, nil, nil
end)

local function SendAdminData(src)
    TriggerClientEvent('lime_redzones:client:adminData', src, Data.zones, Data.customGangs, Data.settings, GetAdminPerms(src))
end

RegisterNetEvent('lime_redzones:server:adminOpen', function()
    local src = source
    if not IsAdmin(src) then NotifySv(src, 'No permission.', 'error') return end
    TriggerClientEvent('lime_redzones:client:openAdmin', src, Data.zones, Data.customGangs, Data.settings, GetAdminPerms(src))
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

    Data.zones[id] = {
        id = id,
        name = zone.name:sub(1, 40),
        coords = { x = tonumber(zone.coords.x) or 0, y = tonumber(zone.coords.y) or 0, z = tonumber(zone.coords.z) or 0 },
        radius = math.max(10.0, math.min(500.0, tonumber(zone.radius) or 60.0)),
        colorHex = (type(zone.colorHex) == 'string' and zone.colorHex:match('^#%x%x%x%x%x%x$')) and zone.colorHex or '#FF0000',
        colorA = math.max(0, math.min(255, math.floor(tonumber(zone.colorA) or 80))),
        blipSprite = tonumber(zone.blipSprite) or 310,
        blipColor = tonumber(zone.blipColor) or 1,
        rewardItems = sanitizeRewards(zone.rewardItems, false),
        streakRewards = sanitizeRewards(zone.streakRewards, true),
        reviveCost = math.max(0, tonumber(zone.reviveCost) or 0),
        reviveInside = zone.reviveInside ~= false,
        reviveDelay = math.max(1000, tonumber(zone.reviveDelay) or 8000),
        teleportAway = math.max(5.0, math.min(200.0, tonumber(zone.teleportAway) or 30.0)),
        exits = exits,
        enabled = zone.enabled ~= false,
    }
    SaveData()
    BroadcastZones(-1)
    SendAdminData(src)
    NotifySv(src, ('Zone "%s" saved.'):format(Data.zones[id].name), 'success')
end)

RegisterNetEvent('lime_redzones:server:toggleZone', function(zoneId, enabled)
    local src = source
    if not HasPerm(src, 'zones') then return end
    local z = Data.zones[tostring(zoneId)]
    if not z then return end
    z.enabled = enabled == true
    SaveData()
    BroadcastZones(-1)
    SendAdminData(src)
    NotifySv(src, ('Zone "%s" %s.'):format(z.name, z.enabled and 'enabled' or 'disabled'), 'success')
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
    SendAdminData(src)
    NotifySv(src, ('Zone "%s" deleted.'):format(name), 'success')
end)

RegisterNetEvent('lime_redzones:server:saveGang', function(gang)
    local src = source
    if not HasPerm(src, 'gangs') then return end
    if type(gang) ~= 'table' or type(gang.name) ~= 'string' or gang.name == '' then return end
    Data.customGangs[gang.name:sub(1, 30)] = { label = (gang.label or gang.name):sub(1, 40) }
    SaveData()
    SendAdminData(src)
    NotifySv(src, ('Gang "%s" registered.'):format(gang.label or gang.name), 'success')
end)

RegisterNetEvent('lime_redzones:server:deleteGang', function(name)
    local src = source
    if not HasPerm(src, 'gangs') then return end
    Data.customGangs[tostring(name)] = nil
    SaveData()
    SendAdminData(src)
    NotifySv(src, ('Gang "%s" removed.'):format(tostring(name)), 'success')
end)

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
    SaveData()
    SendAdminData(src)
    PushLeaderboard(-1)
    NotifySv(src, 'Reset schedule saved.', 'success')
end)

RegisterNetEvent('lime_redzones:server:saveOptions', function(opts)
    local src = source
    if not HasPerm(src, 'options') then return end
    if type(opts) ~= 'table' then return end
    Data.settings.options.rewardNotify   = opts.rewardNotify ~= false
    Data.settings.options.streakAnnounce = opts.streakAnnounce ~= false
    local o = Data.settings.options
    o.renderDistance = math.max(50, math.min(500, math.floor(tonumber(opts.renderDistance) or 120)))
    o.rewardNotify         = opts.rewardNotify ~= false
    o.streakAnnounce       = opts.streakAnnounce ~= false
    o.leaderboardEnabled   = opts.leaderboardEnabled ~= false
    o.globalLbEnabled      = opts.globalLbEnabled ~= false
    o.gangLbEnabled        = opts.gangLbEnabled ~= false
    o.streaksEnabled       = opts.streaksEnabled ~= false
    o.personalColorEnabled = opts.personalColorEnabled ~= false
    o.personalColorOpacity = opts.personalColorOpacity ~= false
    o.personalColorHue     = opts.personalColorHue ~= false
    o.killFeedEnabled      = opts.killFeedEnabled ~= false
    o.killMessageEnabled   = opts.killMessageEnabled ~= false
    o.killFeedDuration     = math.max(2000, math.min(20000, math.floor(tonumber(opts.killFeedDuration) or 6000)))
    o.killCamDuration      = math.max(2000, math.min(15000, math.floor(tonumber(opts.killCamDuration) or 5000)))
    o.killCamEnabled       = opts.killCamEnabled ~= false
    if opts.hudDefaultPreset then o.hudDefaultPreset = tostring(opts.hudDefaultPreset):sub(1,12) end
    if opts.hudDefaultTheme then o.hudDefaultTheme = tostring(opts.hudDefaultTheme):sub(1,12) end
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
    SendAdminData(src)
    NotifySv(src, 'Options saved.', 'success')
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
    SendAdminData(src)
    NotifySv(src, 'Ranks saved.', 'success')
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
    SendAdminData(src)
    NotifySv(src, ('Admin added: %s'):format(idStr), 'success')
end)

RegisterNetEvent('lime_redzones:server:removeAdmin', function(identifier)
    local src = source
    if not GetAdminPerms(src)._full then return end
    for i, a in ipairs(Data.settings.admins) do
        if (type(a) == 'table' and a.id or a) == identifier then
            table.remove(Data.settings.admins, i)
            SaveData()
            SendAdminData(src)
            NotifySv(src, ('Admin removed: %s'):format(identifier), 'success')
            return
        end
    end
end)

RegisterNetEvent('lime_redzones:server:resetLeaderboard', function(which)
    local src = source
    if not HasPerm(src, 'leaderboards') then return end
    if which == 'global' then DoReset('globalReset') else DoReset('reset') end
    SendAdminData(src)
    NotifySv(src, ('%s leaderboard reset.'):format(which == 'global' and 'Global' or 'Redzone'), 'success')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    SaveDataNow()
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    LoadData(function()
        local c = 0 for _ in pairs(Data.zones) do c = c + 1 end
        print(('[lime_redzones] ^2Started^0 · FW: ^3%s^0 · Inv: ^3%s^0 · Storage: ^3%s^0 · Zones: ^3%d^0')
            :format(FWName, GetInventoryName(), HasSQL and 'MySQL' or 'JSON', c))
        Wait(500)
        BroadcastZones(-1)
    end)
end)
