-- lime_redzones logging bridge
-- Config is stored in Data.settings.logs (persisted to SQL by server.lua).
-- This file exposes Log() and GetLogs(); it reads config via GetLogSettings() from server.lua.

local LogStore = {}   -- category -> { entries... } newest first

local function cfg()
    if GetLogSettings then return GetLogSettings() end
    return { enabled = true, categories = {}, webhooks = {}, leaderboardPost = {} }
end

local function memCap()
    return (Config and Config.LogKeepInMemory) or 200
end

local function pushMemory(category, entry)
    LogStore[category] = LogStore[category] or {}
    table.insert(LogStore[category], 1, entry)
    local cap = memCap()
    while #LogStore[category] > cap do table.remove(LogStore[category]) end
end

local function sendWebhook(url, title, description, fields)
    if not url or url == '' then return end
    local embed = { {
        title = title,
        description = description,
        color = (Config and Config.LogColor) or 10672181,
        fields = fields,
        footer = { text = 'lime_redzones' },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    } }
    PerformHttpRequest(url, function() end, 'POST',
        json.encode({ username = 'Redzone Logs', embeds = embed }),
        { ['Content-Type'] = 'application/json' })
end

-- category: 'admin' | 'kills' | 'revives' | 'leaderboardRz' | 'leaderboardGlobal'
local function webhookFor(category)
    return (cfg().webhooks or {})[category]
end

function Log(category, title, description, fields)
    local c = cfg()
    if c.enabled == false then return end

    local isLeaderboard = (category == 'leaderboardRz' or category == 'leaderboardGlobal')
    if not isLeaderboard and (c.categories or {})[category] == false then return end

    if not isLeaderboard then
        pushMemory(category, {
            category = category, title = title,
            description = description or '', fields = fields, time = os.time(),
        })
    end

    sendWebhook(webhookFor(category), title, description, fields)
end

function GetLogs(category, limit)
    limit = limit or 50
    local out, src = {}, LogStore[category] or {}
    for i = 1, math.min(limit, #src) do out[i] = src[i] end
    return out
end

-- Public leaderboard auto-post timer.
CreateThread(function()
    local lastPost = 0
    while true do
        Wait(30000)
        local c = cfg()
        local lp = c.leaderboardPost
        if c.enabled ~= false and lp and lp.enabled and lp.interval and lp.interval > 0 then
            local now = os.time()
            if now - lastPost >= (lp.interval * 60) then
                lastPost = now
                if _G.PostLeaderboardLog then _G.PostLeaderboardLog(lp.board or 'redzone', lp.top or 10) end
            end
        end
    end
end)
