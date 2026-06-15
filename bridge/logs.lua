-- lime_redzones logging bridge
-- Provides: Log(category, title, description, fields), GetLogs(category), SetLogConfig(...)
-- Logs go to: (1) an in-memory ring buffer for the admin panel, (2) optional Discord webhooks.

local LogStore = {}          -- category -> { entries... } (newest first)
local LogCfg                 -- live copy of Config.Logs, overridable from the admin panel

local function ensureCfg()
    if not LogCfg then
        LogCfg = Config.Logs or {}
        LogCfg.webhooks   = LogCfg.webhooks   or {}
        LogCfg.categories = LogCfg.categories or {}
        LogCfg.keepInMemory = LogCfg.keepInMemory or 200
    end
    return LogCfg
end

-- Allow the admin panel to toggle categories / set webhooks at runtime.
function SetLogConfig(patch)
    local cfg = ensureCfg()
    if type(patch) ~= 'table' then return end
    if patch.enabled ~= nil then cfg.enabled = patch.enabled == true end
    if type(patch.categories) == 'table' then
        for k, v in pairs(patch.categories) do cfg.categories[k] = v == true end
    end
    if type(patch.webhooks) == 'table' then
        for k, v in pairs(patch.webhooks) do
            if type(v) == 'string' then cfg.webhooks[k] = v end
        end
    end
    if type(patch.leaderboardPost) == 'table' then
        cfg.leaderboardPost = cfg.leaderboardPost or {}
        for k, v in pairs(patch.leaderboardPost) do cfg.leaderboardPost[k] = v end
    end
end

function GetLogConfig()
    local cfg = ensureCfg()
    return {
        enabled = cfg.enabled ~= false,
        categories = cfg.categories,
        webhooks = cfg.webhooks,
        leaderboardPost = cfg.leaderboardPost,
    }
end

local function pushMemory(category, entry)
    local cfg = ensureCfg()
    LogStore[category] = LogStore[category] or {}
    table.insert(LogStore[category], 1, entry)
    local cap = cfg.keepInMemory or 200
    while #LogStore[category] > cap do table.remove(LogStore[category]) end
end

local function sendWebhook(url, title, description, fields, color)
    if not url or url == '' then return end
    local embed = {
        {
            title = title,
            description = description,
            color = color or (ensureCfg().color or 10672181),
            fields = fields,
            footer = { text = 'lime_redzones' },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        }
    }
    PerformHttpRequest(url, function() end, 'POST',
        json.encode({ username = 'Redzone Logs', embeds = embed }),
        { ['Content-Type'] = 'application/json' })
end

-- Main entry point. category: 'admin' | 'kills' | 'revives' | 'leaderboard'
function Log(category, title, description, fields)
    local cfg = ensureCfg()
    if cfg.enabled == false then return end

    -- 'leaderboard' is a system post, always allowed; others respect category toggles.
    if category ~= 'leaderboard' and cfg.categories[category] == false then return end

    local entry = {
        category = category,
        title = title,
        description = description or '',
        fields = fields,
        time = os.time(),
    }
    if category ~= 'leaderboard' then pushMemory(category, entry) end

    sendWebhook(cfg.webhooks[category], title, description, fields)
end

-- Serve recent logs to the admin panel (capped slice).
function GetLogs(category, limit)
    limit = limit or 50
    local out = {}
    local src = LogStore[category] or {}
    for i = 1, math.min(limit, #src) do out[i] = src[i] end
    return out
end

-- ── Public leaderboard auto-post ───────────────────────────────
-- BuildLeaderboardEmbed is provided by server.lua (it owns the data).
CreateThread(function()
    while true do
        local cfg = ensureCfg()
        local lp = cfg.leaderboardPost
        if cfg.enabled ~= false and lp and lp.enabled and lp.interval and lp.interval > 0 then
            Wait(lp.interval * 60000)
            if _G.PostLeaderboardLog then _G.PostLeaderboardLog(lp.board or 'redzone', lp.top or 10) end
        else
            Wait(60000) -- re-check config every minute when disabled
        end
    end
end)
