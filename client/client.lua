local Zones, zoneBlips = {}, {}
local currentZoneId    = nil
local kills, deaths, killStreak = 0, 0, 0
local wasDead          = false
local tabletOpen, tabletMode, hudMoveMode = false, nil, false
local personalColor    = nil
local hudPos           = nil

local function HexToRGB(hex)
    hex = hex:gsub('#', '')
    return tonumber('0x' .. hex:sub(1,2)) or 255, tonumber('0x' .. hex:sub(3,4)) or 0, tonumber('0x' .. hex:sub(5,6)) or 0
end

-- Compute which enabled zone the player is physically inside RIGHT NOW.
-- Used at kill time so we never miss a kill due to the throttled state loop.
local function ZoneAtPlayer()
    local pos = GetEntityCoords(PlayerPedId())
    for id, z in pairs(Zones) do
        if z.enabled and z.vec then
            if #(pos - z.vec) <= z.radius then return id end
        end
    end
    return nil
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
end)

CreateThread(function()
    local rawC = GetResourceKvpString('rz_personal_color')
    if rawC then
        local ok, p = pcall(json.decode, rawC)
        if ok and p and p.hex then personalColor = p end
    end
    local rawP = GetResourceKvpString('rz_hud_pos')
    if rawP then
        local ok, p = pcall(json.decode, rawP)
        if ok and p then hudPos = p end
    end
    Wait(2000)
    TriggerServerEvent('lime_redzones:server:requestZones')
    if hudPos then SendNUIMessage({ type = 'hudPos', pos = hudPos }) end
end)

local function ClearBlips()
    for _, b in pairs(zoneBlips) do
        if DoesBlipExist(b.blip) then RemoveBlip(b.blip) end
        if DoesBlipExist(b.ring) then RemoveBlip(b.ring) end
    end
    zoneBlips = {}
end

local function BuildBlips()
    ClearBlips()
    for id, z in pairs(Zones) do
        if z.enabled then
            local c = z.coords
            local blip = AddBlipForCoord(c.x, c.y, c.z)
            SetBlipSprite(blip, z.blipSprite or 310)
            SetBlipColour(blip, z.blipColor or 1)
            SetBlipScale(blip, 0.9)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(z.name)
            EndTextCommandSetBlipName(blip)
            local ring = AddBlipForRadius(c.x, c.y, c.z, z.radius + 0.0)
            SetBlipAlpha(ring, 80)
            SetBlipColour(ring, z.blipColor or 1)
            SetBlipAsShortRange(ring, true)
            zoneBlips[id] = { blip = blip, ring = ring }
        end
    end
end

local DynRenderDist = nil
local Opts = {}

RegisterNetEvent('lime_redzones:client:syncOptions', function(o) Opts = o or {} end)

RegisterNetEvent('lime_redzones:client:syncZones', function(zones, renderDist)
    DynRenderDist = tonumber(renderDist)
    Zones = zones or {}
    for _, z in pairs(Zones) do
        z.vec = vector3(z.coords.x, z.coords.y, z.coords.z)
        z._r, z._g, z._b = HexToRGB(z.colorHex or '#FF0000')
        z._a = z.colorA or 80
    end
    BuildBlips()
end)

local function NextStreakReward(zone, streak)
    local best
    for _, sr in ipairs(zone.streakRewards or {}) do
        local th = tonumber(sr.streak) or 0
        if th > streak and (not best or th < tonumber(best.streak)) then best = sr end
    end
    return best
end

local function UpdateHUD()
    if not currentZoneId then
        SendNUIMessage({ type = 'updateRedzoneUI', display = false })
        return
    end
    local z = Zones[currentZoneId]
    local nr = NextStreakReward(z, killStreak)
    SendNUIMessage({
        type = 'updateRedzoneUI', display = true,
        zoneName = z.name, kills = kills, deaths = deaths, streak = killStreak,
        nextReward = nr and { streak = tonumber(nr.streak), name = nr.name, amount = tonumber(nr.amount) or 1 } or nil,
    })
end

local function SetTablet(open, mode, tab, payload)
    tabletOpen, tabletMode = open, open and mode or nil
    local function kvpJson(key)
        local r = GetResourceKvpString(key)
        if r then local ok, v = pcall(json.decode, r) if ok then return v end end
        return nil
    end
    SendNUIMessage({
        type = 'tablet', display = open, mode = mode, tab = tab,
        zones = payload and payload.zones, gangs = payload and payload.gangs,
        settings = payload and payload.settings,
        perms = payload and payload.perms,
        personalColor = personalColor,
        options = Opts,
        hudTheme = GetResourceKvpString('rz_hud_theme') or (Opts.hudDefaultTheme or 'lime'),
        hudPreset = GetResourceKvpString('rz_hud_preset') or (Opts.hudDefaultPreset or 'top'),
        hudScale = tonumber(GetResourceKvpFloat('rz_hud_scale')) or 1.0,
        killfeedPos = kvpJson('rz_kf_pos'),
        killfeedScale = tonumber(GetResourceKvpFloat('rz_kf_scale')) or 1.0,
        killfeedTheme = GetResourceKvpString('rz_kf_theme') or 'inherit',
        killmsgPos = kvpJson('rz_km_pos'),
        killmsgScale = tonumber(GetResourceKvpFloat('rz_km_scale')) or 1.0,
        killmsgTheme = GetResourceKvpString('rz_km_theme') or 'inherit',
    })
    if not hudMoveMode then
        if open then
            CreateThread(function()
                Wait(0)
                SetNuiFocus(true, true)
            end)
        else
            SetNuiFocus(false, false)
        end
    end
end

local function SetHudMove(on)
    hudMoveMode = on
    SendNUIMessage({ type = 'hudMove', enabled = on })
    SetNuiFocus(on, on)
    if on then Notify('Drag the HUD, then click Done.', 'info') end
end

RegisterNetEvent('lime_redzones:client:notify', function(m, t, d) Notify(m, t, d) end)

RegisterNetEvent('lime_redzones:client:logs', function(category, entries)
    SendNUIMessage({ type = 'logs', category = category, entries = entries })
end)
RegisterNetEvent('lime_redzones:client:logConfig', function(cfg)
    SendNUIMessage({ type = 'logConfig', config = cfg })
end)

RegisterNetEvent('lime_redzones:client:killFeed', function(entry)
    if type(entry) ~= 'table' then return end
    SendNUIMessage({ type = 'killFeed', entry = entry })

    -- Big on-screen kill message only for the player who got the kill.
    if Opts.killMessageEnabled ~= false and entry.killerId and entry.killerId == GetPlayerServerId(PlayerId()) then
        SendNUIMessage({
            type = 'killMessage',
            victim = entry.victim or 'Enemy',
            weapon = entry.weapon or 'Weapon',
            streak = entry.streak or 0,
        })
    end
end)

RegisterNetEvent('lime_redzones:client:updateLeaderboard', function(players, gangs, globalP, totals)
    SendNUIMessage({ type = 'lbData', players = players, gangs = gangs, globalPlayers = globalP, totals = totals })
end)

RegisterNetEvent('lime_redzones:client:syncStreak', function(s)
    killStreak = s or 0
    UpdateHUD()
end)

RegisterNetEvent('lime_redzones:client:openAdmin', function(z, g, st)
    SetTablet(true, 'admin', 'zones', { zones = z, gangs = g, settings = st })
end)
RegisterNetEvent('lime_redzones:client:myIdentifier', function(lic, id)
    SendNUIMessage({ type = 'myIdentifier', license = lic, identifier = id })
end)

RegisterNetEvent('lime_redzones:client:adminData', function(z, g, st)
    if tabletOpen and tabletMode == 'admin' then
        SendNUIMessage({ type = 'adminData', zones = z, gangs = g, settings = st })
    end
end)

local function OpenPlayerTablet(tab)
    if tabletOpen then SetTablet(false)
    else
        TriggerServerEvent('lime_redzones:server:requestLeaderboard')
        SetTablet(true, 'player', tab or 'leaderboard')
    end
end

RegisterCommand('leaderboard', function() OpenPlayerTablet('leaderboard') end, false)
RegisterCommand('rz', function() OpenPlayerTablet('leaderboard') end, false)
if Config.LeaderboardKeybindEnabled ~= false then
    RegisterKeyMapping('leaderboard', 'Toggle Redzone Leaderboard', 'keyboard', Config.LeaderboardKey or 'F1')
end

RegisterCommand('rz_admin', function()
    if tabletOpen and tabletMode == 'admin' then SetTablet(false)
    else TriggerServerEvent('lime_redzones:server:adminOpen') end
end, false)

RegisterCommand('rz_color', function() OpenPlayerTablet('color') end, false)
RegisterCommand('rz_hud', function() SetHudMove(not hudMoveMode) end, false)

RegisterNUICallback('closeTablet', function(_, cb) SetTablet(false) cb({}) end)
RegisterNUICallback('forceClose', function(_, cb)
    tabletOpen, hudMoveMode = false, false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'tablet', display = false })
    cb({})
end)
RegisterNUICallback('openAdminPanel', function(_, cb)
    TriggerServerEvent('lime_redzones:server:adminOpen')
    cb({})
end)
RegisterNUICallback('openPlayerTablet', function(_, cb)
    TriggerServerEvent('lime_redzones:server:requestLeaderboard')
    SetTablet(true, 'player', 'rzleaderboard')
    cb({})
end)

RegisterNUICallback('addAdminId', function(d, cb)
    TriggerServerEvent('lime_redzones:server:addAdmin', tostring(d.identifier or ''))
    cb({})
end)
RegisterNUICallback('removeAdminId', function(d, cb)
    TriggerServerEvent('lime_redzones:server:removeAdmin', tostring(d.identifier or ''))
    cb({})
end)
RegisterNUICallback('getMyIdentifier', function(_, cb)
    TriggerServerEvent('lime_redzones:server:myIdentifier')
    cb({})
end)

RegisterNUICallback('toggleZone', function(d, cb)
    TriggerServerEvent('lime_redzones:server:toggleZone', d.id, d.enabled)
    cb({})
end)
RegisterNUICallback('saveRanks', function(d, cb)
    TriggerServerEvent('lime_redzones:server:saveRanks', d.ranks) cb({})
end)
RegisterNUICallback('saveHudTheme', function(d, cb)
    if d.theme then SetResourceKvp('rz_hud_theme', tostring(d.theme)) end
    if d.preset then SetResourceKvp('rz_hud_preset', tostring(d.preset)) end
    if d.scale then SetResourceKvpFloat('rz_hud_scale', tonumber(d.scale) or 1.0) end
    SendNUIMessage({ type = 'hudStyle', theme = d.theme, preset = d.preset, scale = d.scale })
    Notify('HUD style saved.', 'success')
    cb({})
end)

RegisterNUICallback('saveKillfeedStyle', function(d, cb)
    if d.scale then SetResourceKvpFloat('rz_kf_scale', tonumber(d.scale) or 1.0) end
    if d.theme then SetResourceKvp('rz_kf_theme', tostring(d.theme)) end
    SendNUIMessage({ type = 'kfStyle', scale = d.scale, theme = d.theme })
    Notify('Kill feed style saved.', 'success')
    cb({})
end)

RegisterNUICallback('requestLogs', function(d, cb)
    TriggerServerEvent('lime_redzones:server:requestLogs', d.category or 'admin')
    cb({})
end)
RegisterNUICallback('requestLogConfig', function(_, cb)
    TriggerServerEvent('lime_redzones:server:requestLogConfig')
    cb({})
end)
RegisterNUICallback('saveLogConfig', function(d, cb)
    TriggerServerEvent('lime_redzones:server:saveLogConfig', d)
    cb({})
end)
RegisterNUICallback('saveKillMsgStyle', function(d, cb)
    if d.scale then SetResourceKvpFloat('rz_km_scale', tonumber(d.scale) or 1.0) end
    if d.theme then SetResourceKvp('rz_km_theme', tostring(d.theme)) end
    SendNUIMessage({ type = 'kmStyle', scale = d.scale, theme = d.theme })
    Notify('Kill message style saved.', 'success')
    cb({})
end)

RegisterNUICallback('startKmMove', function(_, cb)
    SetTablet(false)
    SendNUIMessage({ type = 'kmMove', enabled = true })
    SetNuiFocus(true, true)
    Notify('Drag the kill message, then click Done.', 'info')
    cb({})
end)

RegisterNUICallback('saveKillMsgPos', function(d, cb)
    if d.x and d.y then SetResourceKvp('rz_km_pos', json.encode({ x = d.x, y = d.y })) end
    SendNUIMessage({ type = 'kmMove', enabled = false })
    SetNuiFocus(false, false)
    Notify('Kill message position saved.', 'success')
    cb({})
end)

RegisterNUICallback('resetKmPos', function(_, cb)
    DeleteResourceKvp('rz_km_pos')
    SendNUIMessage({ type = 'kmReset' })
    Notify('Kill message position reset.', 'success')
    cb({})
end)
RegisterNUICallback('saveKillfeedPos', function(d, cb)
    if d.x and d.y then SetResourceKvp('rz_kf_pos', json.encode({ x = d.x, y = d.y })) end
    SendNUIMessage({ type = 'kfMove', enabled = false })
    SetNuiFocus(false, false)
    Notify('Kill feed position saved.', 'success')
    cb({})
end)
RegisterNUICallback('startKfMove', function(_, cb)
    SetTablet(false)
    SendNUIMessage({ type = 'kfMove', enabled = true })
    SetNuiFocus(true, true)
    Notify('Drag the kill feed, then release.', 'info')
    cb({})
end)
RegisterNUICallback('resetKfPos', function(_, cb)
    DeleteResourceKvp('rz_kf_pos')
    SendNUIMessage({ type = 'kfReset' })
    Notify('Kill feed position reset.', 'success')
    cb({})
end)

RegisterNUICallback('startHudMove', function(_, cb)
    SetTablet(false)
    SetHudMove(true)
    cb({})
end)
RegisterNUICallback('resetHudPos', function(_, cb)
    hudPos = nil
    DeleteResourceKvp('rz_hud_pos')
    SendNUIMessage({ type = 'hudPos', pos = nil })
    Notify('HUD position reset.', 'success')
    cb({})
end)
RegisterNUICallback('saveOptions', function(d, cb)
    TriggerServerEvent('lime_redzones:server:saveOptions', d) cb({})
end)

RegisterNUICallback('saveHudPos', function(d, cb)
    if type(d.x) == 'number' and type(d.y) == 'number' then
        hudPos = { x = d.x, y = d.y }
        SetResourceKvp('rz_hud_pos', json.encode(hudPos))
        SendNUIMessage({ type = 'hudPos', pos = hudPos })
        Notify('HUD position saved. Use /rz_hud_reset to restore default.', 'success')
    end
    SetHudMove(false)
    cb({})
end)

RegisterCommand('rz_hud_reset', function()
    hudPos = nil
    DeleteResourceKvp('rz_hud_pos')
    SendNUIMessage({ type = 'hudPos', pos = nil })
    Notify('HUD position reset to default.', 'success')
end, false)

RegisterNUICallback('savePersonalColor', function(d, cb)
    if d.reset then
        personalColor = nil
        DeleteResourceKvp('rz_personal_color')
        Notify('Personal zone colour reset.', 'success')
    elseif type(d.hex) == 'string' and d.hex:match('^#%x%x%x%x%x%x$') then
        personalColor = { hex = d.hex, a = math.max(0, math.min(255, math.floor(tonumber(d.a) or 80))) }
        SetResourceKvp('rz_personal_color', json.encode(personalColor))
        Notify('Personal zone colour saved.', 'success')
    end
    SendNUIMessage({ type = 'tablet', personalColor = personalColor })
    cb({})
end)

RegisterNUICallback('saveZone', function(d, cb) TriggerServerEvent('lime_redzones:server:saveZone', d) cb({}) end)
RegisterNUICallback('deleteZone', function(d, cb) TriggerServerEvent('lime_redzones:server:deleteZone', d.id) cb({}) end)
RegisterNUICallback('saveGang', function(d, cb) TriggerServerEvent('lime_redzones:server:saveGang', d) cb({}) end)
RegisterNUICallback('deleteGang', function(d, cb) TriggerServerEvent('lime_redzones:server:deleteGang', d.name) cb({}) end)
RegisterNUICallback('saveResetSettings', function(d, cb)
    TriggerServerEvent('lime_redzones:server:saveResetSettings', d.which, d.cfg) cb({})
end)
RegisterNUICallback('resetLeaderboard', function(d, cb)
    TriggerServerEvent('lime_redzones:server:resetLeaderboard', d.which) cb({})
end)
RegisterNUICallback('getMyPosition', function(_, cb)
    local p = GetEntityCoords(PlayerPedId())
    cb({ x = math.floor(p.x * 100) / 100, y = math.floor(p.y * 100) / 100, z = math.floor(p.z * 100) / 100 })
end)
RegisterNUICallback('teleportToZone', function(d, cb)
    local z = Zones[tostring(d.id)]
    if z then SetEntityCoords(PlayerPedId(), z.coords.x, z.coords.y, z.coords.z + 1.0) end
    cb({})
end)

local placing = nil

RegisterNUICallback('startPlacement', function(d, cb)
    placing = { draft = d.draft, points = d.draft and d.draft.exits or {} }
    SetTablet(false)
    cb({})

    CreateThread(function()
        Notify('Placement mode: ~g~E~s~ place point · ~g~G~s~ finish', 'info', 6000)
        while placing do
            Wait(0)
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)

            for _, p in ipairs(placing.points) do
                DrawMarker(1, p.x, p.y, p.z - 0.95, 0.0,0.0,0.0, 0.0,0.0,0.0,
                    1.2, 1.2, 0.6, 163, 230, 53, 160, false, false, 2, false, nil, nil, false)
            end

            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(
                ('Respawn points: %d/5~n~~INPUT_PICKUP~ Place  ·  ~INPUT_DETONATE~ Finish'):format(#placing.points))
            EndTextCommandDisplayHelp(0, false, false, -1)

            if IsControlJustReleased(0, 38) and #placing.points < 5 then
                placing.points[#placing.points+1] = {
                    x = math.floor(pos.x * 100) / 100,
                    y = math.floor(pos.y * 100) / 100,
                    z = math.floor(pos.z * 100) / 100,
                }
                PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
            end
            if IsControlJustReleased(0, 47) then
                local draft = placing.draft
                draft.exits = placing.points
                placing = nil
                SetTablet(true, 'admin', 'zones')
                SendNUIMessage({ type = 'placementDone', draft = draft })
            end
        end
    end)
end)

CreateThread(function()
    local frame = 0
    while true do
        local renderDist = DynRenderDist or Config.RenderDistance or 120.0
        if not next(Zones) then Wait(2500) goto continue end

        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)

        local nearest, nearestId, nDist = nil, nil, math.huge
        for id, z in pairs(Zones) do
            if z.enabled then
                local d = #(pos - z.vec)
                if d < nDist then nearest, nearestId, nDist = z, id, d end
            end
        end

        if not nearest or nDist > (nearest.radius + renderDist) then
            if currentZoneId then
                currentZoneId = nil
                kills, deaths, killStreak = 0, 0, 0
                UpdateHUD()
            end
            Wait(nDist > (nearest and nearest.radius or 0) + renderDist + 200.0 and 2000 or 1000)
        else
            local mr, mg, mb, ma = nearest._r, nearest._g, nearest._b, nearest._a
            if personalColor then
                mr, mg, mb = HexToRGB(personalColor.hex)
                ma = personalColor.a
            end
            DrawMarker(28, nearest.vec.x, nearest.vec.y, nearest.vec.z,
                0.0,0.0,0.0, 0.0,0.0,0.0,
                nearest.radius + 0.0, nearest.radius + 0.0, nearest.radius + 0.0,
                mr, mg, mb, ma, false, false, 2, false, nil, nil, false)

            frame = frame + 1
            if frame >= 30 then
                frame = 0
                local inside = nDist <= nearest.radius
                local dead   = IsEntityDead(ped)

                if inside and currentZoneId ~= nearestId then
                    currentZoneId = nearestId
                    kills, deaths, killStreak = 0, 0, 0
                    UpdateHUD()
                elseif not inside and currentZoneId then
                    currentZoneId = nil
                    kills, deaths, killStreak = 0, 0, 0
                    UpdateHUD()
                end

                if currentZoneId and dead and not wasDead then
                    wasDead = true
                    deaths = deaths + 1
                    UpdateHUD()
                    TriggerServerEvent('lime_redzones:server:reportDeath', currentZoneId)

                    if Opts.killCamEnabled ~= false then
                        local killer = GetPedSourceOfDeath(ped)
                        if killer and killer ~= 0 and killer ~= ped and DoesEntityExist(killer) then
                            CreateThread(function()
                                killCamActive = true
                                local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

                                local kPlayer = NetworkGetPlayerIndexFromPed(killer)
                                local killerName = kPlayer ~= -1 and GetPlayerName(kPlayer) or 'Enemy'
                                local killerId = kPlayer ~= -1 and GetPlayerServerId(kPlayer) or 0

                                SendNUIMessage({ type = 'killCam', display = true, killer = killerName, id = killerId })

                                local function positionPOV()
                                    if not DoesEntityExist(killer) then return end
                                    -- Killer's eye-line POV: just behind and slightly above the head,
                                    -- aimed where the killer is facing (their point of view).
                                    local headBone = GetPedBoneCoords(killer, 0x796E, 0.0, 0.0, 0.0) -- SKEL_Head
                                    local fwd = GetEntityForwardVector(killer)
                                    local camPos = vector3(
                                        headBone.x - fwd.x * 0.55,
                                        headBone.y - fwd.y * 0.55,
                                        headBone.z + 0.22
                                    )
                                    SetCamCoord(cam, camPos.x, camPos.y, camPos.z)
                                    local look = vector3(headBone.x + fwd.x * 8.0, headBone.y + fwd.y * 8.0, headBone.z + 0.05)
                                    PointCamAtCoord(cam, look.x, look.y, look.z)
                                end

                                positionPOV()
                                SetCamActive(cam, true)
                                RenderScriptCams(true, false, 0, true, true)

                                local t = GetGameTimer()
                                local camDur = tonumber(Opts.killCamDuration) or 5000
                                while killCamActive and (GetGameTimer() - t) < camDur and DoesEntityExist(killer) do
                                    Wait(0)
                                    positionPOV()
                                end

                                RenderScriptCams(false, false, 0, true, true)
                                DestroyCam(cam, false)
                                killCamActive = false
                                SendNUIMessage({ type = 'killCam', display = false })
                            end)
                        end
                    end

                    local z = Zones[currentZoneId]
                    local exits = z.exits or {}
                    local exit
                    if #exits > 0 then
                        local e = exits[math.random(#exits)]
                        exit = { x = e.x, y = e.y, z = e.z }
                    else

                        local away = (z.teleportAway or 30.0) + z.radius
                        local ang = math.random() * 6.28318
                        exit = { x = z.coords.x + math.cos(ang) * away, y = z.coords.y + math.sin(ang) * away, z = z.coords.z }
                    end
                    local zid = currentZoneId
                    SetTimeout(z.reviveDelay or 8000, function()
                        TriggerServerEvent('lime_redzones:server:attemptRevive', zid, exit, 0.0)
                    end)
                elseif not dead and wasDead then
                    wasDead = false
                    killCamActive = false
                end
            end
            Wait(0)
        end
        ::continue::
    end
end)

CreateThread(function()
    local wasDeadGlobal = false
    while true do
        Wait(1500)
        local dead = IsEntityDead(PlayerPedId())
        if dead and not wasDeadGlobal then
            wasDeadGlobal = true
            if not currentZoneId then
                TriggerServerEvent('lime_redzones:server:globalDeath')
            end
        elseif not dead and wasDeadGlobal then
            wasDeadGlobal = false
        end
    end
end)

local RZ_DEBUG = false  -- toggle with /rz_debug

local function dbg(...)
    if RZ_DEBUG then print('[lime_redzones]', ...) end
end

RegisterCommand('rz_debug', function()
    RZ_DEBUG = not RZ_DEBUG
    Notify('Redzone debug ' .. (RZ_DEBUG and 'ON' or 'OFF') .. '. Check F8 console.', 'info')
    print('[lime_redzones] debug = ' .. tostring(RZ_DEBUG) .. ' | currentZoneId = ' .. tostring(currentZoneId))
end, false)

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end

    local victim   = args[1]
    local attacker = args[2]
    local weapon   = args[5]
    local isFatal  = args[6]

    if not victim or not attacker then return end
    if attacker ~= PlayerPedId() then return end
    if not IsEntityAPed(victim) then return end
    if victim == attacker then return end

    dbg(('damage event: victim=%s isPlayer=%s fatal=%s zone=%s'):format(
        victim, tostring(IsPedAPlayer(victim)), tostring(isFatal), tostring(currentZoneId)))

    local function registerKill(reason)
        local zoneNow = ZoneAtPlayer() or currentZoneId
        dbg('registerKill via ' .. reason .. ' | zoneNow=' .. tostring(zoneNow))
        if zoneNow then
            currentZoneId = zoneNow
            kills = kills + 1
            killStreak = killStreak + 1
            UpdateHUD()
            local victimPlayer = NetworkGetPlayerIndexFromPed(victim)
            local victimId = victimPlayer ~= -1 and GetPlayerServerId(victimPlayer) or 0
            TriggerServerEvent('lime_redzones:server:giveKillReward', zoneNow, victimId, weapon)
        else
            TriggerServerEvent('lime_redzones:server:globalKill')
        end
    end

    -- Accept NPC or player kills inside a zone (some servers use AI). Players only outside.
    local victimIsPlayer = IsPedAPlayer(victim)

    if isFatal == 1 or isFatal == true then
        registerKill('isFatal')
    else
        local v = victim
        CreateThread(function()
            local tries = 0
            while tries < 15 do
                Wait(80)
                tries = tries + 1
                if not DoesEntityExist(v) then return end
                if IsEntityDead(v) then
                    registerKill('health-poll')
                    return
                end
            end
        end)
    end
end)
