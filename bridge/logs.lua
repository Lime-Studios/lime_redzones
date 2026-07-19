-- Logging bridge. Entries are written to their own `lime_redzones_logs` table
-- so they survive restarts and can be paged/searched from the tablet.
-- Retention (auto-wipe) and manual wipes are configured in Data.settings.logs.

local ready = false

local function cfg()
    if GetLogSettings then return GetLogSettings() end
    return { enabled = true, categories = {}, webhooks = {}, leaderboardPost = {}, retentionDays = 14 }
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(250) end
    exports.oxmysql:query([[
        CREATE TABLE IF NOT EXISTS lime_redzones_logs (
            id INT AUTO_INCREMENT PRIMARY KEY,
            category VARCHAR(32) NOT NULL,
            title VARCHAR(120) NOT NULL,
            description TEXT,
            actor VARCHAR(120),
            fields TEXT,
            created_at INT NOT NULL,
            INDEX idx_cat_time (category, created_at)
        )
    ]], {}, function() ready = true end)
end)

local function sendWebhook(url, title, description, fields)
    if not url or url == '' then return end
    local embed = { {
        title = title,
        description = description,
        color = (Config and Config.LogColor) or 10930928,
        fields = fields,
        footer = { text = 'lime_redzones' },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    } }
    PerformHttpRequest(url, function() end, 'POST',
        json.encode({ username = 'Redzone Logs', embeds = embed }),
        { ['Content-Type'] = 'application/json' })
end

-- actor is optional; it's shown as its own column in the tablet.
function Log(category, title, description, fields, actor)
    local c = cfg()
    if c.enabled == false then return end
    if (c.categories or {})[category] == false then return end

    if ready then
        exports.oxmysql:insert(
            'INSERT INTO lime_redzones_logs (category, title, description, actor, fields, created_at) VALUES (?, ?, ?, ?, ?, ?)',
            { category, tostring(title):sub(1, 120), tostring(description or ''), actor and tostring(actor):sub(1, 120) or nil,
              fields and json.encode(fields) or nil, os.time() }
        )
    end

    sendWebhook((c.webhooks or {})[category], title, description, fields)
end

-- Paged fetch. Returns newest first plus a total so the UI can page.
function GetLogsPaged(category, page, perPage, search, done)
    if not ready then done({ entries = {}, total = 0 }) return end
    page = math.max(1, tonumber(page) or 1)
    perPage = math.max(5, math.min(50, tonumber(perPage) or 10))
    local offset = (page - 1) * perPage

    local where, args = 'category = ?', { category }
    if search and search ~= '' then
        where = where .. ' AND (title LIKE ? OR description LIKE ? OR actor LIKE ?)'
        local like = '%' .. search .. '%'
        args[#args+1] = like; args[#args+1] = like; args[#args+1] = like
    end

    exports.oxmysql:scalar('SELECT COUNT(*) FROM lime_redzones_logs WHERE ' .. where, args, function(total)
        local qArgs = {}
        for i, v in ipairs(args) do qArgs[i] = v end
        qArgs[#qArgs+1] = perPage
        qArgs[#qArgs+1] = offset
        exports.oxmysql:query(
            'SELECT id, category, title, description, actor, fields, created_at FROM lime_redzones_logs WHERE ' .. where ..
            ' ORDER BY id DESC LIMIT ? OFFSET ?', qArgs,
            function(rows)
                local out = {}
                for i, r in ipairs(rows or {}) do
                    local f = nil
                    if r.fields then local ok, parsed = pcall(json.decode, r.fields) if ok then f = parsed end end
                    out[i] = { id = r.id, category = r.category, title = r.title,
                               description = r.description, actor = r.actor, fields = f, time = r.created_at }
                end
                done({ entries = out, total = tonumber(total) or 0 })
            end)
    end)
end

function WipeLogs(category, done)
    if not ready then if done then done(0) end return end
    if category and category ~= 'all' then
        exports.oxmysql:update('DELETE FROM lime_redzones_logs WHERE category = ?', { category },
            function(affected) if done then done(affected or 0) end end)
    else
        exports.oxmysql:update('DELETE FROM lime_redzones_logs', {},
            function(affected) if done then done(affected or 0) end end)
    end
end

-- Retention sweep: drop anything older than retentionDays. 0 = keep forever.
CreateThread(function()
    while true do
        Wait(3600000)
        local days = tonumber(cfg().retentionDays) or 0
        if ready and days > 0 then
            exports.oxmysql:update('DELETE FROM lime_redzones_logs WHERE created_at < ?',
                { os.time() - (days * 86400) })
        end
    end
end)
