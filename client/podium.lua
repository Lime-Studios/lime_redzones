local podiums = {}
local spawned = {}
local podiumGen = {}

local COMPONENTS = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }
local PROPS      = { 0, 1, 2, 6, 7 }
local OVERLAYS   = 12
local FEATURES   = 19
local SPAWN_DIST = 60.0
local LABEL_DIST = 12.0
local PLACE_LABEL = { 'FIRST place', 'SECOND place', 'THIRD place' }

local function captureAppearance()
    local ped = PlayerPedId()
    local comps, props = {}, {}
    for i = 1, #COMPONENTS do
        local c = COMPONENTS[i]
        comps[#comps + 1] = {
            c, GetPedDrawableVariation(ped, c), GetPedTextureVariation(ped, c), GetPedPaletteVariation(ped, c),
        }
    end
    for i = 1, #PROPS do
        local p = PROPS[i]
        local drawable = GetPedPropIndex(ped, p)
        if drawable ~= -1 then
            props[#props + 1] = { p, drawable, GetPedPropTextureIndex(ped, p) }
        end
    end

    local blend
    local okB, b = pcall(GetPedHeadBlendData, ped)
    if okB and type(b) == 'table' then
        blend = {
            b.shapeFirst or 0, b.shapeSecond or 0, b.shapeThird or 0,
            b.skinFirst or 0,  b.skinSecond or 0,  b.skinThird or 0,
            b.shapeMix or 0.0, b.skinMix or 0.0,   b.thirdMix or 0.0,
        }
    end

    local overlays = {}
    for i = 0, OVERLAYS do
        local ok, r1, r2, r3, r4, r5, r6 = pcall(GetPedHeadOverlayData, ped, i)
        if ok then
            local value, colType, col1, col2, opacity
            if type(r1) == 'boolean' then
                value, colType, col1, col2, opacity = r2, r3, r4, r5, r6
            else
                value, colType, col1, col2, opacity = r1, r2, r3, r4, r5
            end
            value = tonumber(value) or 255
            if value ~= 255 then
                opacity = tonumber(opacity)
                if not opacity or opacity < 0.0 or opacity > 1.0 then opacity = 1.0 end
                overlays[#overlays + 1] = {
                    i, value, tonumber(colType) or 0,
                    tonumber(col1) or 0, tonumber(col2) or 0, opacity,
                }
            end
        end
    end

    local features = {}
    if GetPedFaceFeature then
        for i = 0, FEATURES do
            local ok, v = pcall(GetPedFaceFeature, ped, i)
            v = ok and tonumber(v) or nil
            if v and v ~= 0.0 then
                features[#features + 1] = { i, math.max(-1.0, math.min(1.0, v)) }
            end
        end
    end

    local hair, hairHl, eyes = 0, 0, 0
    pcall(function() hair = GetPedHairColor(ped) or 0 end)
    pcall(function() hairHl = GetPedHairHighlightColor(ped) or 0 end)
    pcall(function() eyes = GetPedEyeColor(ped) or 0 end)

    return {
        model = GetEntityModel(ped),
        comps = comps, props = props,
        blend = blend, overlays = overlays, features = features,
        hair = hair, hairHl = hairHl, eyes = eyes,
    }
end

local watching = false
local lastFingerprint = nil

local function fingerprint()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then return nil end
    local parts = { tostring(GetEntityModel(ped)) }
    for i = 1, #COMPONENTS do
        local c = COMPONENTS[i]
        parts[#parts + 1] = ('%d.%d.%d'):format(c, GetPedDrawableVariation(ped, c), GetPedTextureVariation(ped, c))
    end
    for i = 1, #PROPS do
        local p = PROPS[i]
        parts[#parts + 1] = ('p%d.%d.%d'):format(p, GetPedPropIndex(ped, p), GetPedPropTextureIndex(ped, p))
    end
    return table.concat(parts, '|')
end

local function pushSnapshot()
    lastFingerprint = fingerprint()
    TriggerServerEvent('lime_redzones:server:appearanceSnapshot', captureAppearance())
end

RegisterNetEvent('lime_redzones:client:captureAppearance', function()
    pushSnapshot()
end)

RegisterNetEvent('lime_redzones:client:podiumWatch', function(on)
    on = on == true
    if on == watching then return end
    watching = on
    if watching then lastFingerprint = nil end
end)

CreateThread(function()
    local ticks = 0
    while true do
        Wait(watching and 5000 or 15000)
        if watching then
            ticks = ticks + 1
            if ticks >= 12 then ticks = 0 lastFingerprint = nil end
            local fp = fingerprint()
            if fp and fp ~= lastFingerprint then pushSnapshot() end
        else
            ticks = 0
            lastFingerprint = nil
        end
    end
end)

local function applyAppearance(ped, a)
    if type(a) ~= 'table' then return end

    pcall(SetPedDefaultComponentVariation, ped)
    for i = 0, OVERLAYS do
        pcall(SetPedHeadOverlay, ped, i, 255, 0.0)
    end

    local b = a.blend
    if type(b) == 'table' and #b >= 9 then
        pcall(SetPedHeadBlendData, ped,
            b[1], b[2], b[3], b[4], b[5], b[6],
            b[7] + 0.0, b[8] + 0.0, b[9] + 0.0, false)
    end

    for _, o in ipairs(a.overlays or {}) do
        pcall(SetPedHeadOverlay, ped, o[1], o[2], (o[6] or 1.0) + 0.0)
        pcall(SetPedHeadOverlayColor, ped, o[1], o[3] or 0, o[4] or 0, o[5] or 0)
    end

    if SetPedFaceFeature then
        for _, f in ipairs(a.features or {}) do
            pcall(SetPedFaceFeature, ped, f[1], (f[2] or 0.0) + 0.0)
        end
    end

    for _, c in ipairs(a.comps or {}) do
        SetPedComponentVariation(ped, c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 0)
    end
    for _, p in ipairs(a.props or {}) do
        SetPedPropIndex(ped, p[1] or 0, p[2] or 0, p[3] or 0, true)
    end

    pcall(SetPedHairColor, ped, a.hair or 0, a.hairHl or 0)
    pcall(SetPedEyeColor, ped, a.eyes or 0)
end

local FALLBACK_MODEL = `mp_m_freemode_01`

local function spawnPodium(id, p)
    if spawned[id] then return end
    local gen = (podiumGen[id] or 0) + 1
    podiumGen[id] = gen
    local rec = { peds = {} }
    spawned[id] = rec

    for i = 1, math.min(3, #p.points) do
        local pt = p.points[i]
        local win = p.winners and p.winners[i]
        CreateThread(function()
            local model = (win and win.appearance and win.appearance.model) or FALLBACK_MODEL
            if not IsModelInCdimage(model) or not IsModelAPed(model) then model = FALLBACK_MODEL end
            RequestModel(model)
            local tries = 0
            while not HasModelLoaded(model) and tries < 100 do Wait(10) tries = tries + 1 end
            if spawned[id] ~= rec or podiumGen[id] ~= gen or not HasModelLoaded(model) then
                SetModelAsNoLongerNeeded(model)
                return
            end

            local ped = CreatePed(4, model, pt.x, pt.y, pt.z - 1.0, pt.h or 0.0, false, false)
            SetModelAsNoLongerNeeded(model)
            if not DoesEntityExist(ped) then return end

            if win and win.appearance then applyAppearance(ped, win.appearance) end
            SetEntityAsMissionEntity(ped, true, true)
            FreezeEntityPosition(ped, true)
            SetEntityInvincible(ped, true)
            SetBlockingOfNonTemporaryEvents(ped, true)
            SetPedCanRagdoll(ped, false)
            SetPedDiesWhenInjured(ped, false)
            SetPedCanBeTargetted(ped, false)
            TaskStartScenarioInPlace(ped, i == 1 and 'WORLD_HUMAN_CHEERING' or 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)

            if spawned[id] == rec and podiumGen[id] == gen then
                rec.peds[#rec.peds + 1] = ped
            else
                DeleteEntity(ped)
            end
        end)
    end
end

local function despawnPodium(id)
    local rec = spawned[id]
    if not rec then return end
    spawned[id] = nil
    podiumGen[id] = (podiumGen[id] or 0) + 1
    for _, ped in ipairs(rec.peds) do
        if DoesEntityExist(ped) then
            SetEntityAsMissionEntity(ped, true, true)
            DeleteEntity(ped)
            if DoesEntityExist(ped) then DeletePed(ped) end
        end
    end
end

local function despawnAll()
    for id in pairs(spawned) do despawnPodium(id) end
end

local podiumSig = {}

local function winnerSig(p)
    local rows = {}
    for i = 1, 3 do
        local w = p.winners and p.winners[i]
        rows[i] = w and ('%s/%s/%s/%s'):format(
            tostring(w.name), tostring(w.kills), tostring(w.elo),
            w.appearance and tostring(w.appearance.model) or '-') or '-'
    end
    for _, pt in ipairs(p.points or {}) do
        rows[#rows + 1] = ('%.2f,%.2f,%.2f,%.2f'):format(pt.x or 0.0, pt.y or 0.0, pt.z or 0.0, pt.h or 0.0)
    end
    return table.concat(rows, ';')
end

local function scanPodiums()
    local near = false
    if #podiums > 0 then
        local pos = GetEntityCoords(PlayerPedId())
        for _, p in ipairs(podiums) do
            local pt = p.points and p.points[1]
            if pt then
                local dx, dy, dz = pos.x - pt.x, pos.y - pt.y, pos.z - pt.z
                local d = (dx * dx + dy * dy + dz * dz) ^ 0.5
                if spawned[p.id] then
                    if d > SPAWN_DIST + 20.0 then despawnPodium(p.id) else near = true end
                elseif d <= SPAWN_DIST then
                    spawnPodium(p.id, p)
                    near = true
                end
            end
        end
    end
    return near
end

RegisterNetEvent('lime_redzones:client:syncPodiums', function(list)
    local incoming = type(list) == 'table' and list or {}
    local seen, sigs = {}, {}
    for _, p in ipairs(incoming) do
        seen[p.id] = true
        sigs[p.id] = winnerSig(p)
    end
    for id in pairs(spawned) do
        if not seen[id] or sigs[id] ~= podiumSig[id] then despawnPodium(id) end
    end
    podiumSig = sigs
    podiums = incoming
    scanPodiums()
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then despawnAll() end
end)

CreateThread(function()
    Wait(3000)
    TriggerServerEvent('lime_redzones:server:requestPodiums')
end)

CreateThread(function()
    while true do
        Wait(scanPodiums() and 1000 or 2000)
    end
end)

local function hexToRgb(hex)
    if type(hex) ~= 'string' then return 255, 255, 255 end
    hex = hex:gsub('#', '')
    if #hex < 6 then return 255, 255, 255 end
    return tonumber(hex:sub(1, 2), 16) or 255,
           tonumber(hex:sub(3, 4), 16) or 255,
           tonumber(hex:sub(5, 6), 16) or 255
end

local function drawText3D(x, y, z, text, r, g, b)
    SetTextScale(0.32, 0.32)
    SetTextFont(4)
    SetTextColour(r, g, b, 215)
    SetTextCentre(true)
    SetTextOutline()
    SetDrawOrigin(x, y, z, 0)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

local PLACE_RGB = { { 255, 214, 84 }, { 206, 212, 222 }, { 214, 148, 90 } }

local function commas(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local sign = ''
    if s:sub(1, 1) == '-' then sign, s = '-', s:sub(2) end
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    return sign .. out
end

CreateThread(function()
    while true do
        local drew = false
        if next(spawned) then
            local pos = GetEntityCoords(PlayerPedId())
            for _, p in ipairs(podiums) do
                local rec = spawned[p.id]
                if rec then
                    for i, ped in ipairs(rec.peds) do
                        if DoesEntityExist(ped) then
                            local pc = GetEntityCoords(ped)
                            local dx, dy, dz = pos.x - pc.x, pos.y - pc.y, pos.z - pc.z
                            if (dx * dx + dy * dy + dz * dz) <= (LABEL_DIST * LABEL_DIST) then
                                local w = p.winners and p.winners[i]
                                local c = PLACE_RGB[i] or PLACE_RGB[3]
                                drawText3D(pc.x, pc.y, pc.z + 1.14,
                                    ('#%d  %s'):format(i, w and w.name or 'Unclaimed'), c[1], c[2], c[3])
                                if w then
                                    local tr, tg, tb = hexToRgb(w.color)
                                    drawText3D(pc.x, pc.y, pc.z + 1.00,
                                        tostring(w.rank or 'Unranked'), tr, tg, tb)
                                    drawText3D(pc.x, pc.y, pc.z + 0.87,
                                        commas(w.elo or 0) .. ' Elo', 225, 228, 232)
                                end
                                drew = true
                            end
                        end
                    end
                end
            end
        end
        Wait(drew and 0 or 500)
    end
end)

RegisterNetEvent('lime_redzones:client:beginPodiumPlacement', function(draft)
    if type(RZBeginPointPlacement) ~= 'function' then return end
    Notify(('Placing "%s" — walk to each spot and press E for 1st, 2nd then 3rd. X undoes, G saves.')
        :format(draft.label or 'Podium'), 'info')
    RZBeginPointPlacement('podium', draft, 3, function(final)
        TriggerServerEvent('lime_redzones:server:savePodium', {
            id = final.id, label = final.label, board = final.board, points = final.podiumPoints or final.points,
        })
    end)
end)

RegisterCommand('rz_addpodium', function(_, args)
    local board = (args[1] == 'global') and 'global' or 'redzone'
    local label = table.concat(args, ' ', 2)
    if label == '' then label = (board == 'global' and 'Global Podium' or 'Redzone Podium') end
    TriggerServerEvent('lime_redzones:server:beginPodiumPlacement', '', label, board)
end, false)
