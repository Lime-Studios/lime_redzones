local Zones, zoneBlips = {}, {}
local currentZoneId    = nil
local currentSafeId    = nil
local reviveRequest    = nil
local RZ_DEBUG         = false
local RZ_DEBUG_LOCAL   = nil
local RZ_DEBUG_SERVER  = false
local function resolveDebug()
    if RZ_DEBUG_LOCAL ~= nil then RZ_DEBUG = RZ_DEBUG_LOCAL else RZ_DEBUG = RZ_DEBUG_SERVER end
end
local _sdbgLast, _sdbgN = 0, 0
function RZDbg(msg)
    if not RZ_DEBUG then return end
    msg = tostring(msg)
    print('[lime_redzones] ' .. msg)
    local now = GetGameTimer()
    if now - _sdbgLast > 1000 then _sdbgLast, _sdbgN = now, 0 end
    _sdbgN = _sdbgN + 1
    if _sdbgN <= 8 then
        TriggerServerEvent('lime_redzones:server:clientDebug', msg)
    end
end
local kills, deaths, killStreak = 0, 0, 0
local recentKills = {}
local pendingPoll = {}
local wasDead          = false
local downedSince      = nil
local reviveDispatchedAt = nil
local tabletOpen, tabletMode, hudMoveMode = false, nil, false
local hudDefaultTarget = nil
local personalColor    = nil
local hudPos           = nil
local szPos            = nil
local szMoveMode       = false
local Opts             = {}

local function HexToRGB(hex)
    hex = hex:gsub('#', '')
    return tonumber('0x' .. hex:sub(1,2)) or 255, tonumber('0x' .. hex:sub(3,4)) or 0, tonumber('0x' .. hex:sub(5,6)) or 0
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

local _limeIsDowned = nil
CreateThread(function()
    Wait(0)
    if type(LimeIsDowned) == 'function' then _limeIsDowned = LimeIsDowned end
end)

local function isDownedOrDead(ped)
    local f = _limeIsDowned
    if f then return f(ped) end
    if IsEntityDead(ped) then return true end
    if IsPedDeadOrDying(ped, true) then return true end
    local ok, v = pcall(function() return LocalPlayer.state.isDead end)
    if ok and v == true then return true end
    return GetEntityHealth(ped) <= 5 and IsPedRagdoll(ped)
end

local UP_GRACE_MS = 2000
local upSince = nil
local function confirmedUp(ped)
    if isDownedOrDead(ped) then upSince = nil return false end
    upSince = upSince or GetGameTimer()
    return (GetGameTimer() - upSince) >= UP_GRACE_MS
end

local killCamHandle = nil
local killCamActive = false
local killCamGen = 0

local liveCams = {}

local function makeCam(kind)
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    if not (cam and cam ~= 0 and DoesCamExist(cam)) then return nil end
    liveCams[cam] = kind
    return cam
end

local function dropCam(cam)
    if cam == nil then return end
    if DoesCamExist(cam) then
        SetCamActive(cam, false)
        DestroyCam(cam, false)
    end
    liveCams[cam] = nil
    if killCamHandle == cam then killCamHandle = nil end
end

local function reapCams(kind)
    for cam, k in pairs(liveCams) do
        if kind == nil or k == kind then dropCam(cam) end
    end
end

local POOL_NAMES = { 'CPed', 'CObject', 'CVehicle', 'CPickup' }
local poolBase = nil

local function poolCounts()
    local out = {}
    for _, name in ipairs(POOL_NAMES) do
        local ok, t = pcall(GetGamePool, name)
        out[name] = (ok and type(t) == 'table') and #t or -1
    end
    local cams = 0
    for _ in pairs(liveCams) do cams = cams + 1 end
    out.ourCams = cams
    return out
end

local function poolCensus()
    local now = poolCounts()
    poolBase = poolBase or now
    local parts = {}
    for _, name in ipairs(POOL_NAMES) do
        parts[#parts + 1] = ('%s=%d(%+d)'):format(name:sub(2):lower(), now[name], now[name] - poolBase[name])
    end
    parts[#parts + 1] = ('ourCams=%d'):format(now.ourCams)
    return 'pools: ' .. table.concat(parts, ' ')
end

local function destroyKillCam()
    killCamGen = killCamGen + 1
    if killCamHandle ~= nil then
        RenderScriptCams(false, false, 0, true, true)
        dropCam(killCamHandle)
    end
    reapCams('kill')
    if killCamActive then
        killCamActive = false
        SendNUIMessage({ type = 'killCam', display = false })
    end
end

local function RunKillCam(ped)
    if type(Opts) ~= 'table' or Opts.killCamEnabled == false then return end
    if killCamActive then return end
    local killer = GetPedSourceOfDeath(ped)
    if not (killer and killer ~= 0 and killer ~= ped and DoesEntityExist(killer)) then return end
    if not IsPedAPlayer(killer) then return end
    killCamActive = true
    dropCam(killCamHandle)
    reapCams('kill')

    local kPlayer = NetworkGetPlayerIndexFromPed(killer)
    if kPlayer == -1 then
        for _, pid in ipairs(GetActivePlayers()) do
            if GetPlayerPed(pid) == killer then kPlayer = pid break end
        end
    end
    local killerName = (kPlayer and kPlayer ~= -1) and GetPlayerName(kPlayer) or 'Unknown'
    local killerId = (kPlayer and kPlayer ~= -1) and GetPlayerServerId(kPlayer) or 0
    local camDur = math.max(1000, tonumber(Opts.killCamDuration) or 5000)
    SendNUIMessage({ type = 'killCam', display = true, killer = killerName, id = killerId, duration = camDur })
    RZDbg('killcam start (killer '..tostring(killerId)..')')

    local myGen = killCamGen
    CreateThread(function()
        local function finite(n) return n == n and n ~= math.huge and n ~= -math.huge end
        local cam = nil
        local function finish()
            if cam ~= nil then
                if killCamHandle == cam then RenderScriptCams(false, false, 0, true, true) end
                dropCam(cam)
                cam = nil
            end
            if myGen == killCamGen then destroyKillCam() end
        end
        local function killerCoords()
            if not DoesEntityExist(killer) then return nil end
            local c = GetEntityCoords(killer)
            if not (finite(c.x) and finite(c.y) and finite(c.z)) then return nil end
            return c
        end

        local start = killerCoords()
        if not start then
            local t0 = GetGameTimer()
            while killCamActive and myGen == killCamGen and (GetGameTimer() - t0) < camDur do Wait(100) end
            finish()
            return
        end

        cam = makeCam('kill')
        if cam == nil then
            RZDbg('killcam: CreateCam failed — banner only')
            local t0 = GetGameTimer()
            while killCamActive and myGen == killCamGen and (GetGameTimer() - t0) < camDur do Wait(100) end
            finish()
            return
        end
        killCamHandle = cam
        local function place()
            if not (killCamActive and killCamHandle == cam and DoesCamExist(cam)) then return false end
            local c = killerCoords() or start
            local rad = math.rad(GetEntityHeading(killer))
            local camX = c.x + math.sin(rad) * 2.6
            local camY = c.y - math.cos(rad) * 2.6
            local camZ = c.z + 1.2
            if finite(camX) and finite(camY) and finite(camZ) then
                SetCamCoord(cam, camX, camY, camZ)
                PointCamAtCoord(cam, c.x, c.y, c.z + 0.2)
            end
            return true
        end
        place()
        SetCamActive(cam, true)
        RenderScriptCams(true, false, 0, true, true)
        local t = GetGameTimer()
        while killCamActive and myGen == killCamGen
              and (GetGameTimer() - t) < camDur and DoesEntityExist(killer) do
            Wait(0)
            if not place() then break end
        end
        finish()
    end)
end

local function ZoneHasPoly(z)
    return type(z.poly) == 'table' and #z.poly >= 3
end

local function InsideZone(z, pos)
    local isPoly = z._isPoly
    if isPoly == nil then isPoly = ZoneHasPoly(z) end
    if isPoly then
        if z.polyMinZ and pos.z < z.polyMinZ then return false end
        if z.polyMaxZ and pos.z > z.polyMaxZ then return false end
        return PointInPoly(pos.x, pos.y, z.poly)
    end
    return #(pos - z.vec) <= z.radius
end

function BuildZoneTris(z)
    if not (type(z.poly) == 'table' and #z.poly >= 3) then
        z._tris, z._lines, z._mid, z._walls = nil, nil, nil, 0
        return
    end
    local n = #z.poly
    local baseZ = z.polyMinZ or (z.vec.z - 2.0)
    local topZ  = z.polyMaxZ or (baseZ + 6.0)
    local tris, lines, mid = {}, {}, {}
    local ti, li, mi = 0, 0, 0
    for i = 1, n do
        local p1 = z.poly[i]
        local p2 = z.poly[i % n + 1]
        local quads = {
            p1.x,p1.y,baseZ, p2.x,p2.y,baseZ, p2.x,p2.y,topZ,
            p2.x,p2.y,topZ,  p2.x,p2.y,baseZ, p1.x,p1.y,baseZ,
            p1.x,p1.y,baseZ, p2.x,p2.y,topZ,  p1.x,p1.y,topZ,
            p1.x,p1.y,topZ,  p2.x,p2.y,topZ,  p1.x,p1.y,baseZ,
        }
        for k = 1, #quads do ti = ti + 1 tris[ti] = quads[k] end
        local seg = { p1.x,p1.y,baseZ, p2.x,p2.y,baseZ, p1.x,p1.y,topZ, p2.x,p2.y,topZ }
        for k = 1, #seg do li = li + 1 lines[li] = seg[k] end
        mi = mi + 1 mid[mi] = (p1.x + p2.x) * 0.5
        mi = mi + 1 mid[mi] = (p1.y + p2.y) * 0.5
    end
    z._tris, z._lines, z._mid, z._walls = tris, lines, mid, n

    local a = math.max(20, math.min(160, z._a or 80))
    local edgeA = math.min(110, a + 30)
    z._fillA, z._edgeA, z._edgeA2 = a, edgeA, math.floor(edgeA * 0.6)
end

local function DrawPolyWalls(z, px, py, cullDist)
    local t = z._tris
    if not t then BuildZoneTris(z) t = z._tris if not t then return end end
    local L, mid, walls = z._lines, z._mid, z._walls
    local r, g, b = z._dr or z._r, z._dg or z._g, z._db or z._b
    local a, edgeA, edgeA2 = z._fillA or 80, z._edgeA or 110, z._edgeA2 or 66
    local cull2 = cullDist and (cullDist * cullDist) or nil

    for w = 0, walls - 1 do
        local skip = false
        if cull2 then
            local dx = mid[w * 2 + 1] - px
            local dy = mid[w * 2 + 2] - py
            skip = (dx * dx + dy * dy) > cull2
        end
        if not skip then
            local i = w * 36
            DrawPoly(t[i+1],t[i+2],t[i+3],    t[i+4],t[i+5],t[i+6],    t[i+7],t[i+8],t[i+9],    r,g,b,a)
            DrawPoly(t[i+10],t[i+11],t[i+12], t[i+13],t[i+14],t[i+15], t[i+16],t[i+17],t[i+18], r,g,b,a)
            DrawPoly(t[i+19],t[i+20],t[i+21], t[i+22],t[i+23],t[i+24], t[i+25],t[i+26],t[i+27], r,g,b,a)
            DrawPoly(t[i+28],t[i+29],t[i+30], t[i+31],t[i+32],t[i+33], t[i+34],t[i+35],t[i+36], r,g,b,a)
            local j = w * 12
            DrawLine(L[j+1],L[j+2],L[j+3], L[j+4],L[j+5],L[j+6],  r,g,b,edgeA)
            DrawLine(L[j+7],L[j+8],L[j+9], L[j+10],L[j+11],L[j+12], r,g,b,edgeA2)
        end
    end
end

local function DrawSafeMarker(z, px, py, cullDist)
    if not z then return end
    if z._isPoly then DrawPolyWalls(z, px, py, cullDist) return end
    DrawMarker(28, z.vec.x, z.vec.y, z.vec.z, 0.0,0.0,0.0, 0.0,0.0,0.0,
        z.radius + 0.0, z.radius + 0.0, z.radius + 0.0,
        z._r, z._g, z._b, z._a, false, false, 2, false, nil, nil, false)
end

local limitedVeh = nil

local myPlayerId = PlayerId()
local function ApplySafeControls(holster)
    DisablePlayerFiring(myPlayerId, true)
    DisableControlAction(0, 24, true)
    DisableControlAction(0, 257, true)
    DisableControlAction(0, 263, true)
    DisableControlAction(0, 264, true)
    DisableControlAction(0, 140, true)
    DisableControlAction(0, 141, true)
    DisableControlAction(0, 142, true)

    if holster then
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 37, true)
        DisableControlAction(0, 47, true)
        DisableControlAction(0, 58, true)
    end
end

local function ApplySafeSlow(z)
    if not z then return end
    local ped = PlayerPedId()

    local limit = tonumber(z.speedLimit) or 0
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 and limit > 0 then
        if limitedVeh ~= veh then limitedVeh = veh end
        SetVehicleMaxSpeed(veh, limit / 2.236936)
    elseif limitedVeh and (veh == 0 or limit <= 0) then
        if DoesEntityExist(limitedVeh) then SetVehicleMaxSpeed(limitedVeh, 0.0) end
        limitedVeh = nil
    end

    if z.invincible ~= false then
        ClearPedLastDamageBone(ped)
        SetEntityCanBeDamaged(ped, false)
        if veh ~= 0 then SetEntityCanBeDamaged(veh, false) end
    end

    if z._wmode == 'holster' and GetSelectedPedWeapon(ped) ~= `WEAPON_UNARMED` then
        SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
    end
end

CreateThread(function()
    while true do
        local z = currentSafeId and Zones[currentSafeId] or nil
        if z then
            ApplySafeSlow(z)
            Wait(200)
        else
            Wait(500)
        end
    end
end)

local function ApplySafeState(z)
    local ped = PlayerPedId()

    if not z then
        SetEntityInvincible(ped, false)
        SetEntityProofs(ped, false, false, false, false, false, false, false, false)
        SetEntityCanBeDamaged(ped, true)
        SetPedCanRagdollFromPlayerImpact(ped, true)
        SetPedCanRagdoll(ped, true)
        SetPedCanBeKnockedOffVehicle(ped, 1)
        SetPlayerCanDoDriveBy(PlayerId(), true)
        local exitVeh = GetVehiclePedIsIn(ped, false)
        if exitVeh ~= 0 then SetEntityCanBeDamaged(exitVeh, true) end
        if limitedVeh and DoesEntityExist(limitedVeh) then
            SetVehicleMaxSpeed(limitedVeh, 0.0)
            SetEntityCanBeDamaged(limitedVeh, true)
        end
        limitedVeh = nil
        return
    end

    if z.invincible ~= false then
        SetEntityInvincible(ped, true)
        SetEntityProofs(ped, true, true, true, true, true, true, true, true)
        SetPedCanBeKnockedOffVehicle(ped, 1)
    else
        SetEntityInvincible(ped, false)
        SetEntityProofs(ped, false, false, false, false, false, false, false, false)
    end

    local wmode = z.weaponMode or ((z.disableWeapons == false) and 'off' or 'holster')
    if wmode ~= 'off' then
        SetPlayerCanDoDriveBy(PlayerId(), false)
        if wmode == 'holster' then
            SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
        end
    end
    if z.phaseThrough ~= false then
        SetPedCanRagdollFromPlayerImpact(ped, false)
        SetPedCanRagdoll(ped, false)
        SetPedCanBeKnockedOffVehicle(ped, 1)
    end
end

local phaseTargets = {}
local phaseMyVeh   = 0
local nextPhaseScan = 0
local PHASE_RANGE = 40.0

local function refreshPhaseTargets(ped)
    local t, n = {}, 0
    local myId = PlayerId()
    local mine = GetEntityCoords(ped)
    phaseMyVeh = GetVehiclePedIsIn(ped, false)
    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= myId then
            local other = GetPlayerPed(pid)
            if other ~= 0 and other ~= ped and DoesEntityExist(other) then
                if #(GetEntityCoords(other) - mine) <= PHASE_RANGE then
                    n = n + 1 t[n] = other
                    local oVeh = GetVehiclePedIsIn(other, false)
                    if oVeh ~= 0 then n = n + 1 t[n] = oVeh end
                end
            end
        end
    end
    phaseTargets = t
end

local function applyPhase(ped)
    local t = phaseTargets
    local myVeh = phaseMyVeh
    for i = 1, #t do
        local e = t[i]
        SetEntityNoCollisionEntity(ped, e, true)
        if myVeh ~= 0 then SetEntityNoCollisionEntity(myVeh, e, true) end
    end
end

CreateThread(function()
    while true do
        local z = currentSafeId and Zones[currentSafeId] or nil
        if z and z.phaseThrough ~= false then
            local ped = PlayerPedId()
            local now = GetGameTimer()
            if now >= nextPhaseScan then
                nextPhaseScan = now + 250
                refreshPhaseTargets(ped)
            end
            if #phaseTargets > 0 then
                applyPhase(ped)
                Wait(0)
            else
                phaseMyVeh = 0
                Wait(150)
            end
        else
            if #phaseTargets > 0 then phaseTargets = {} end
            Wait(500)
        end
    end
end)

local function ZoneAtPlayer()
    local pos = GetEntityCoords(PlayerPedId())
    for id, z in pairs(Zones) do
        if z.enabled and z.vec and z.type ~= 'safezone' then
            if InsideZone(z, pos) then return id end
        end
    end
    return nil
end

local placing = nil
local tabletProp = nil
local lastWeapNotify = 0
local tabletAnimGen = 0

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    RenderScriptCams(false, false, 0, true, true)
    reapCams()
    placing = nil
    if tabletProp and DoesEntityExist(tabletProp) then
        DetachEntity(tabletProp, true, true)
        if not NetworkHasControlOfEntity(tabletProp) then NetworkRequestControlOfEntity(tabletProp) end
        SetEntityAsMissionEntity(tabletProp, true, true)
        DeleteEntity(tabletProp)
        if DoesEntityExist(tabletProp) then DeleteObject(tabletProp) end
    end
    tabletProp = nil
    EnableAllControlActions(0)
    EnableAllControlActions(1)
    EnableAllControlActions(2)
    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
        SetEntityCanBeDamaged(ped, true)
        SetEntityInvincible(ped, false)
        SetEntityProofs(ped, false, false, false, false, false, false, false, false)
        SetPedCanRagdoll(ped, true)
        SetPedCanRagdollFromPlayerImpact(ped, true)
        SetPedCanBeKnockedOffVehicle(ped, 1)
        SetPlayerCanDoDriveBy(PlayerId(), true)
    end
end)

CreateThread(function()
    local rawC = GetResourceKvpString('rz_personal_color')
    if rawC then
        local ok, p = pcall(json.decode, rawC)
        if ok and p and p.hex then
            personalColor = p
            personalColor.a = math.max(0, math.min(255, math.floor(tonumber(p.a) or 80)))
            personalColor._r, personalColor._g, personalColor._b = HexToRGB(p.hex)
        end
    end
    local rawSz = GetResourceKvpString('rz_sz_pos')
    if rawSz then
        local ok, p = pcall(json.decode, rawSz)
        if ok and p then szPos = p end
    end
    local rawP = GetResourceKvpString('rz_hud_pos')
    if rawP then
        local ok, p = pcall(json.decode, rawP)
        if ok and p then hudPos = p end
    end
    Wait(2000)
    TriggerServerEvent('lime_redzones:server:requestZones')
    if hudPos then SendNUIMessage({ type = 'hudPos', pos = hudPos }) end
    if szPos then SendNUIMessage({ type = 'szPos', pos = szPos }) end
    ApplyHudStyle()
end)

local function ClearBlips()
    for _, b in pairs(zoneBlips) do
        if DoesBlipExist(b.blip) then RemoveBlip(b.blip) end
        if b.ring and DoesBlipExist(b.ring) then RemoveBlip(b.ring) end
    end
    zoneBlips = {}
end

local function BuildBlips()
    ClearBlips()
    for id, z in pairs(Zones) do
        if z.enabled and z.showBlip ~= false then
            local c = z.coords
            local isSafe = z.type == 'safezone'
            local blip = AddBlipForCoord(c.x, c.y, c.z)
            SetBlipSprite(blip, z.blipSprite or (isSafe and 60 or 310))
            SetBlipColour(blip, z.blipColor or (isSafe and 2 or 1))
            SetBlipScale(blip, 0.9)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(z.name)
            EndTextCommandSetBlipName(blip)
            local ring = nil
            if z.showRadiusBlip ~= false then
                ring = AddBlipForRadius(c.x, c.y, c.z, z.radius + 0.0)
                SetBlipAlpha(ring, isSafe and 70 or 80)
                SetBlipColour(ring, z.blipColor or (isSafe and 2 or 1))
                SetBlipAsShortRange(ring, true)
            end
            zoneBlips[id] = { blip = blip, ring = ring }
        end
    end
end

local DynRenderDist = nil
function RZOption(key, default)
    local v = Opts and Opts[key]
    if v == nil then return default end
    return v
end
local function KvpJson(key)
    local raw = GetResourceKvpString(key)
    if not raw then return nil end
    local ok, v = pcall(json.decode, raw)
    if ok and type(v) == 'table' then return v end
    return nil
end

local function HudDef()
    local d = Opts and Opts.hudDefaults
    return type(d) == 'table' and d or {}
end

function HudLocked() return HudDef().lock == true end

local function defPos(defKey)
    local v = HudDef()[defKey]
    if type(v) == 'table' and tonumber(v.x) and tonumber(v.y) then return v end
    return nil
end

local function resolvedPos(kvpKey, defKey)
    if HudLocked() then return defPos(defKey) end
    return KvpJson(kvpKey) or defPos(defKey)
end

local function resolvedStr(kvpKey, defKey, fallback)
    local def = HudDef()[defKey]
    if type(def) ~= 'string' or def == '' then def = fallback end
    if HudLocked() then return def end
    return GetResourceKvpString(kvpKey) or def
end

local function resolvedNum(kvpKey, defKey, fallback)
    local def = tonumber(HudDef()[defKey]) or fallback
    if HudLocked() then return def end
    local v = tonumber(GetResourceKvpFloat(kvpKey))
    if v and v > 0 then return v end
    return def
end

function HudStyleState()
    return {
        hudTheme      = resolvedStr('rz_hud_theme', 'theme', 'lime'),
        hudPreset     = resolvedStr('rz_hud_preset', 'preset', 'top'),
        hudScale      = resolvedNum('rz_hud_scale', 'scale', 1.0),
        hudPos        = resolvedPos('rz_hud_pos', 'pos'),
        szPos         = resolvedPos('rz_sz_pos', 'szPos'),
        killfeedTheme = resolvedStr('rz_kf_theme', 'kfTheme', 'inherit'),
        killfeedScale = resolvedNum('rz_kf_scale', 'kfScale', 1.0),
        killfeedPos   = resolvedPos('rz_kf_pos', 'kfPos'),
        killmsgTheme  = resolvedStr('rz_km_theme', 'kmTheme', 'inherit'),
        killmsgScale  = resolvedNum('rz_km_scale', 'kmScale', 1.0),
        killmsgPos    = resolvedPos('rz_km_pos', 'kmPos'),
    }
end

function ApplyHudStyle()
    local s = HudStyleState()
    hudPos, szPos = s.hudPos, s.szPos
    SendNUIMessage({ type = 'hudStyle', theme = s.hudTheme, preset = s.hudPreset, scale = s.hudScale })
    SendNUIMessage({ type = 'hudPos', pos = s.hudPos })
    SendNUIMessage({ type = 'szPos', pos = s.szPos })
    SendNUIMessage({ type = 'kfStyle', theme = s.killfeedTheme, scale = s.killfeedScale })
    SendNUIMessage({ type = 'kfPos', pos = s.killfeedPos })
    SendNUIMessage({ type = 'kmStyle', theme = s.killmsgTheme, scale = s.killmsgScale })
    SendNUIMessage({ type = 'kmPos', pos = s.killmsgPos })
end

RegisterNetEvent('lime_redzones:client:syncOptions', function(o)
    Opts = o or {}
    RZ_DEBUG_SERVER = Opts.debugMode == true
    resolveDebug()
    ApplyHudStyle()
    if type(Opts.customTheme) == 'table' then
        SendNUIMessage({ type = 'tablet', customTheme = Opts.customTheme })
    end
end)

RegisterNetEvent('lime_redzones:client:syncCustomTheme', function(theme)
    if type(theme) == 'table' then
        Opts.customTheme = theme
        SendNUIMessage({ type = 'tablet', customTheme = theme })
        ApplyHudStyle()
    end
end)

RegisterNetEvent('lime_redzones:client:syncZones', function(zones, renderDist)
    DynRenderDist = tonumber(renderDist)
    Zones = zones or {}
    for _, z in pairs(Zones) do
        z.vec = vector3(z.coords.x, z.coords.y, z.coords.z)
        z._r, z._g, z._b = HexToRGB(z.colorHex or '#FF0000')
        z._a = z.colorA or 80
        z._isPoly = type(z.poly) == 'table' and #z.poly >= 3
        z._safe = z.type == 'safezone'
        z._wmode = z.weaponMode or ((z.disableWeapons == false) and 'off' or 'holster')
        z._holster = z._wmode == 'holster'
        if type(z.allowedWeapons) == 'table' and #z.allowedWeapons > 0 then
            local set = { [`WEAPON_UNARMED`] = true }
            for _, w in ipairs(z.allowedWeapons) do
                set[GetHashKey(w)] = true
            end
            z._weapSet = set
        else
            z._weapSet = nil
        end
        BuildZoneTris(z)
    end
    ApplyDrawColors()
    BuildBlips()
end)

function ApplyDrawColors()
    for _, z in pairs(Zones) do
        if personalColor then
            z._dr = personalColor._r or z._r
            z._dg = personalColor._g or z._g
            z._db = personalColor._b or z._b
            z._da = personalColor.a
        else
            z._dr, z._dg, z._db, z._da = z._r, z._g, z._b, z._a
        end
    end
end

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
    if not z then
        SendNUIMessage({ type = 'updateRedzoneUI', display = false })
        return
    end
    if z.hideHud == true then
        SendNUIMessage({ type = 'updateRedzoneUI', display = false })
        return
    end
    local nr = NextStreakReward(z, killStreak)
    SendNUIMessage({
        type = 'updateRedzoneUI', display = true,
        zoneName = z.name, kills = kills, deaths = deaths, streak = killStreak,
        nextReward = nr and { streak = tonumber(nr.streak), name = nr.name, amount = tonumber(nr.amount) or 1 } or nil,
    })
end

local function CheckDeath(ped)
    local dead = isDownedOrDead(ped)
    if currentZoneId and dead and not wasDead then
        wasDead = true
        upSince = nil
        downedSince = GetGameTimer()
        deaths = deaths + 1
        killStreak = 0
        UpdateHUD()
        TriggerServerEvent('lime_redzones:server:reportDeath', currentZoneId)
        local z = Zones[currentZoneId]
        if z then
            local exit
            local exits = z.exits
            if type(exits) == 'table' and #exits > 0 then
                local e = exits[math.random(#exits)]
                exit = { x = e.x, y = e.y, z = e.z, exact = true }
            else
                local away = (z.teleportAway or 30.0) + z.radius
                local ang = math.random() * 6.28318
                exit = { x = z.coords.x + math.cos(ang) * away, y = z.coords.y + math.sin(ang) * away,
                         z = z.coords.z, exact = false }
            end
            reviveRequest = { zone = currentZoneId, exit = exit, at = GetGameTimer() + (z.reviveDelay or 8000) }
            if type(LimeReviveLockedOut) == 'function' and LimeReviveLockedOut() then
                reviveRequest = nil
                RZDbg('death registered but revive suppressed (loop lockout)')
            else
                RZDbg('death detected in zone '..tostring(currentZoneId)..' — revive queued (delay '..tostring(z.reviveDelay or 8000)..'ms) | '
                    .. (type(LimeDownedWhy) == 'function' and LimeDownedWhy() or ''))
            end
        end
        RunKillCam(ped)
    elseif wasDead then
        if confirmedUp(ped) then
            wasDead = false
            destroyKillCam()
            reviveRequest = nil
            reviveDispatchedAt = nil
            downedSince = nil
            RZDbg('death state cleared — ready for next death | '
                .. (type(LimeDownedWhy) == 'function' and LimeDownedWhy() or ''))
        end
    end
end

local function tabletAnimPrimary()
    return {
        dict = RZOption('tabletAnimDict', 'amb@code_human_in_bus_passenger_idles@female@tablet@base'),
        name = RZOption('tabletAnimName', 'base'),
    }
end
local TABLET_ANIMS = {
    nil,
    { dict = 'amb@world_human_tourist_map@male@base',      name = 'base' },
    { dict = 'amb@world_human_seat_wall_tablet@female@base', name = 'base' },
}
local TABLET_ANIM_FLAGS = 49

local tabletAnim = nil

local function loadAnimDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local tries = 0
    while not HasAnimDictLoaded(dict) and tries < 100 do
        Wait(10)
        tries = tries + 1
    end
    return HasAnimDictLoaded(dict)
end

local function resolveTabletAnim()
    if tabletAnim and HasAnimDictLoaded(tabletAnim.dict) then return tabletAnim end
    TABLET_ANIMS[1] = tabletAnimPrimary()
    for _, a in ipairs(TABLET_ANIMS) do
        if loadAnimDict(a.dict) then tabletAnim = a return a end
    end
    return nil
end

local function playTabletAnim(ped)
    local a = tabletAnim
    if not a then return end
    if IsEntityPlayingAnim(ped, a.dict, a.name, 3) then return end
    if not HasAnimDictLoaded(a.dict) then
        RequestAnimDict(a.dict)
        if not HasAnimDictLoaded(a.dict) then return end
    end
    TaskPlayAnim(ped, a.dict, a.name, 3.0, -8.0, -1, TABLET_ANIM_FLAGS, 0, false, false, false)
end

local function stopTabletAnim(ped)
    local a = tabletAnim
    if a then StopAnimTask(ped, a.dict, a.name, 2.0) end
    ClearPedSecondaryTask(ped)
end

local function clearTabletProp()
    if tabletProp and DoesEntityExist(tabletProp) then
        DetachEntity(tabletProp, true, true)
        if not NetworkHasControlOfEntity(tabletProp) then
            NetworkRequestControlOfEntity(tabletProp)
        end
        SetEntityAsMissionEntity(tabletProp, true, true)
        DeleteEntity(tabletProp)
        if DoesEntityExist(tabletProp) then DeleteObject(tabletProp) end
    end
    tabletProp = nil
end

local function SetTabletAnim(on)
    local ped = PlayerPedId()
    tabletAnimGen = tabletAnimGen + 1
    local myGen = tabletAnimGen
    if on then
        if Opts.tabletAnim == false then return end
        if IsEntityDead(ped) or IsPedInAnyVehicle(ped, true) then return end
        CreateThread(function()
            resolveTabletAnim()

            local wantName = RZOption('tabletProp', 'prop_cs_tablet')
            local model = GetHashKey(wantName)
            RequestModel(model)

            local tries = 0
            while not HasModelLoaded(model) and tries < 100 do
                Wait(10)
                tries = tries + 1
                if myGen ~= tabletAnimGen then
                    SetModelAsNoLongerNeeded(model)
                    return
                end
            end
            if myGen ~= tabletAnimGen or not tabletOpen or not HasModelLoaded(model) then
                SetModelAsNoLongerNeeded(model)
                return
            end

            ped = PlayerPedId()
            playTabletAnim(ped)

            clearTabletProp()
            local boneCoords = GetPedBoneCoords(ped, 28422, 0.0, 0.0, 0.0)
            tabletProp = CreateObject(model, boneCoords.x, boneCoords.y, boneCoords.z, false, false, false)

            local waitExist = 0
            while not DoesEntityExist(tabletProp) and waitExist < 50 do Wait(0); waitExist = waitExist + 1 end
            if not DoesEntityExist(tabletProp) then tabletProp = nil; SetModelAsNoLongerNeeded(model); return end

            SetEntityCollision(tabletProp, false, false)
            SetEntityVisible(tabletProp, true, false)
            SetEntityAlpha(tabletProp, 255, false)
            ResetEntityAlpha(tabletProp)

            local bone = GetPedBoneIndex(ped, 28422)
            local offX, offY, offZ = 0.0, -0.03, 0.0
            local rotX, rotY, rotZ = 20.0, -90.0, 0.0
            AttachEntityToEntity(tabletProp, ped, bone,
                offX, offY, offZ, rotX, rotY, rotZ,
                true, false, false, false, 2, true)
            SetModelAsNoLongerNeeded(model)

            if myGen ~= tabletAnimGen or not tabletOpen then
                stopTabletAnim(ped)
                clearTabletProp()
                return
            end

            while tabletOpen and myGen == tabletAnimGen do
                Wait(500)
                if not (tabletOpen and myGen == tabletAnimGen) then break end
                local p = PlayerPedId()
                if IsEntityDead(p) or IsPedInAnyVehicle(p, true) then
                    stopTabletAnim(p)
                else
                    playTabletAnim(p)
                    if tabletProp and DoesEntityExist(tabletProp)
                       and not IsEntityAttachedToEntity(tabletProp, p) then
                        AttachEntityToEntity(tabletProp, p, GetPedBoneIndex(p, 28422),
                            offX, offY, offZ, rotX, rotY, rotZ,
                            true, false, false, false, 2, true)
                    end
                end
            end
        end)
    else
        stopTabletAnim(ped)
        clearTabletProp()
    end
end

local function SetTablet(open, mode, tab, payload)
    tabletOpen, tabletMode = open, open and mode or nil
    SetTabletAnim(open)
    if open then hudDefaultTarget = nil end
    if open and placing then
        placing = nil
        SendNUIMessage({ type = 'placementBar', display = false })
    end
    local s = HudStyleState()
    SendNUIMessage({
        type = 'tablet', display = open, mode = mode, tab = tab,
        zones = (payload and payload.zones) or Zones,
        gangs = payload and payload.gangs,
        settings = payload and payload.settings,
        perms = payload and payload.perms,
        playerGangs = payload and payload.playerGangs,
        personalColor = personalColor,
        options = Opts,
        customTheme = Opts.customTheme,
        hudLocked = HudLocked(),
        hudTheme = s.hudTheme,
        hudPreset = s.hudPreset,
        hudScale = s.hudScale,
        hudPos = s.hudPos,
        szPos = s.szPos,
        tabletScale = tonumber(GetResourceKvpFloat('rz_tablet_scale')) or 1.0,
        killfeedPos = s.killfeedPos,
        killfeedScale = s.killfeedScale,
        killfeedTheme = s.killfeedTheme,
        killmsgPos = s.killmsgPos,
        killmsgScale = s.killmsgScale,
        killmsgTheme = s.killmsgTheme,
        firstTime = GetResourceKvpString('rz_seen_tutorial') ~= 'v3',
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

RegisterNetEvent('lime_redzones:client:logs', function(category, entries, total, page)
    SendNUIMessage({ type = 'logs', category = category, entries = entries, total = total, page = page })
end)
RegisterNetEvent('lime_redzones:client:logConfig', function(cfg)
    SendNUIMessage({ type = 'logConfig', config = cfg })
end)
RegisterNetEvent('lime_redzones:client:prizeHistory', function(history)
    SendNUIMessage({ type = 'prizeHistory', history = history })
end)
RegisterNetEvent('lime_redzones:client:stats', function(stats)
    SendNUIMessage({ type = 'stats', stats = stats })
end)

RegisterNetEvent('lime_redzones:client:myStats', function(k, d)
    kills, deaths = tonumber(k) or 0, tonumber(d) or 0
    UpdateHUD()
end)

RegisterNetEvent('lime_redzones:client:killFeed', function(entry)
    entry.mine = tonumber(entry.killerId) == GetPlayerServerId(PlayerId())
    if type(entry) ~= 'table' then return end
    SendNUIMessage({ type = 'killFeed', entry = entry })

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

local myElo = { rating = nil, rank = nil, color = nil }
RegisterNetEvent('lime_redzones:client:elo', function(rating, rank, color, delta, bonus)
    myElo.rating, myElo.rank, myElo.color = tonumber(rating), rank, color
    SendNUIMessage({
        type = 'elo', rating = myElo.rating, rank = rank, color = color,
        delta = tonumber(delta) or 0, bonus = tonumber(bonus) or 0,
    })
end)

CreateThread(function()
    Wait(4000)
    TriggerServerEvent('lime_redzones:server:requestElo')
end)

RegisterNetEvent('lime_redzones:client:eloRanks', function(ranks, enabled)
    SendNUIMessage({ type = 'eloRanks', ranks = ranks, enabled = enabled })
end)

RegisterNetEvent('lime_redzones:client:syncStreak', function(s)
    killStreak = s or 0
    UpdateHUD()
end)

RegisterNetEvent('lime_redzones:client:killHeal', function(amount, full)
    local ped = PlayerPedId()
    if isDownedOrDead(ped) then return end
    local maxHp = GetEntityMaxHealth(ped)
    local hp = GetEntityHealth(ped)
    local target
    if full == true then
        target = maxHp
    else
        amount = math.floor(tonumber(amount) or 0)
        if amount <= 0 then return end
        target = math.min(maxHp, hp + amount)
    end
    if target <= hp then return end
    SetEntityHealth(ped, target)
    if Opts.rewardNotify ~= false then
        Notify(_U('kill_heal', target - hp), 'success')
    end
end)

local PLAYER_TABS = {
    hub = true, rzleaderboard = true, leaderboard = true,
    teleport = true, color = true, hud = true, rank = true, gang = true,
}
local ADMIN_TABS = {
    dash = true, zones = true, gangs = true, resets = true,
    logs = true, killfeed = true, options = true, prizes = true,
    perms = true, stats = true, ranked = true,
}

local function lastTab(mode)
    local key = mode == 'admin' and 'rz_last_admin_tab' or 'rz_last_tab'
    local set = mode == 'admin' and ADMIN_TABS or PLAYER_TABS
    local t = GetResourceKvpString(key)
    return (t and set[t]) and t or nil
end

RegisterNetEvent('lime_redzones:client:openAdmin', function(z, g, st, perms, playerGangs)
    SetTablet(true, 'admin', lastTab('admin') or 'dash',
        { zones = z, gangs = g, settings = st, perms = perms, playerGangs = playerGangs })
end)

RegisterNetEvent('lime_redzones:client:gangState', function(state)
    SendNUIMessage({ type = 'gangState', state = state })
end)
RegisterNetEvent('lime_redzones:client:myIdentifier', function(lic, id)
    SendNUIMessage({ type = 'myIdentifier', license = lic, identifier = id })
end)

CreateThread(function()
    while true do
        Wait(200)
        local r = reviveRequest
        if r then
            local ped = PlayerPedId()
            if confirmedUp(ped) then
                reviveRequest = nil
                wasDead = false
                destroyKillCam()
            elseif isDownedOrDead(ped) and GetGameTimer() >= r.at then
                if type(LimeReviveLockedOut) == 'function' and LimeReviveLockedOut() then
                    reviveRequest = nil
                    RZDbg('revive request dropped (loop lockout active)')
                elseif type(LimeReviveInProgress) == 'function' and LimeReviveInProgress() then
                    r.at = GetGameTimer() + 2000
                else
                    r.at = GetGameTimer() + 4000
                    r.tries = (r.tries or 0) + 1
                    if r.tries > 6 then
                        reviveRequest = nil
                        reviveDispatchedAt = reviveDispatchedAt or GetGameTimer()
                        Notify(_U('revive_failed'), 'error')
                    else
                        reviveDispatchedAt = reviveDispatchedAt or GetGameTimer()
                        RZDbg('attemptRevive sent (try '..tostring(r.tries)..') zone '..tostring(r.zone))
                        TriggerServerEvent('lime_redzones:server:attemptRevive', r.zone, r.exit, 0.0)
                    end
                end
            end
        end
    end
end)

RegisterNetEvent('lime_redzones:client:reviveDenied', function()
    reviveRequest = nil
end)

RegisterNetEvent('lime_redzones:client:teleportTo', function(coords, name, exact)
    if not coords then return end
    RZDbg('teleportTo received')
    local ped = PlayerPedId()
    SetTablet(false)
    destroyKillCam()

    CreateThread(function()
        DoScreenFadeOut(400)
        local fadeWait = 0
        while not IsScreenFadedOut() and fadeWait < 2000 do Wait(10) fadeWait = fadeWait + 10 end

        local veh = GetVehiclePedIsIn(ped, false)
        local ent = (veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped) and veh or ped

        SetEntityCoords(ent, coords.x, coords.y, coords.z, false, false, false, false)

        RequestCollisionAtCoord(coords.x, coords.y, coords.z)
        local waited = 0
        while not HasCollisionLoadedAroundEntity(ent) and waited < 3000 do
            Wait(50)
            waited = waited + 50
        end

        if not exact then
            local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 10.0, false)
            if found then SetEntityCoords(ent, coords.x, coords.y, groundZ, false, false, false, false) end
        end

        if coords.h then SetEntityHeading(ent, coords.h + 0.0) end
        FreezeEntityPosition(ent, false)

        DoScreenFadeIn(600)
        Notify(_U('teleport_arrived', name or 'the redzone'), 'success')
    end)
end)

RegisterNetEvent('lime_redzones:client:adminData', function(z, g, st, perms, playerGangs)
    if tabletOpen and tabletMode == 'admin' then
        SendNUIMessage({ type = 'adminData', zones = z, gangs = g, settings = st, perms = perms, playerGangs = playerGangs })
    end
end)

local function OpenPlayerTablet(tab)
    if tabletOpen then SetTablet(false)
    else
        TriggerServerEvent('lime_redzones:server:requestLeaderboard')
        TriggerServerEvent('lime_redzones:server:requestElo')
        SetTablet(true, 'player', tab or lastTab('player') or 'leaderboard')
    end
end

RegisterNUICallback('saveLastTab', function(d, cb)
    if type(d) == 'table' then
        local t = tostring(d.tab or '')
        if d.mode == 'admin' then
            if ADMIN_TABS[t] then SetResourceKvp('rz_last_admin_tab', t) end
        elseif PLAYER_TABS[t] then
            SetResourceKvp('rz_last_tab', t)
        end
    end
    cb({})
end)

RegisterCommand('leaderboard', function() OpenPlayerTablet() end, false)
RegisterCommand('rz', function() OpenPlayerTablet() end, false)

RegisterCommand('rz_admin', function()
    if tabletOpen and tabletMode == 'admin' then SetTablet(false)
    else TriggerServerEvent('lime_redzones:server:adminOpen') end
end, false)

RegisterCommand('rz_color', function() OpenPlayerTablet('color') end, false)
RegisterCommand('rz_hud', function() hudDefaultTarget = nil SetHudMove(not hudMoveMode) end, false)

CreateThread(function()
    local waited = 0
    while (type(Opts) ~= 'table' or Opts.keybinds == nil) and waited < 3000 do
        Wait(100); waited = waited + 100
    end
    local kb = (type(Opts) == 'table' and Opts.keybinds) or {}
    local function bind(cmd, label, cfgEnabled, cfgKey, optName)
        local o = kb[optName]
        local enabled = (o ~= nil) and (o.enabled == true) or (o == nil and cfgEnabled ~= false)
        local key = (o and o.key) or cfgKey or 'F1'
        if enabled then
            RegisterKeyMapping(cmd, label, 'keyboard', key)
        end
    end
    bind('leaderboard', 'Toggle Redzone Leaderboard', Config.LeaderboardKeybindEnabled, Config.LeaderboardKey, 'leaderboard')
    bind('rz_admin',    'Open Redzone Admin Panel',    Config.AdminKeybindEnabled,       Config.AdminKey,       'admin')
    bind('rz_hud',      'Move Redzone HUD',            Config.HudMoveKeybindEnabled,     Config.HudMoveKey,     'hudMove')
end)

local function forward(name, event, arg)
    RegisterNUICallback(name, function(d, cb)
        TriggerServerEvent(event, arg and arg(d) or nil)
        cb({})
    end)
end

RegisterNUICallback('closeTablet', function(_, cb)
    SetTablet(false)
    TriggerServerEvent('lime_redzones:server:adminClosed')
    cb({})
end)
RegisterNUICallback('tutorialSeen', function(_, cb)
    SetResourceKvp('rz_seen_tutorial', 'v3')
    cb({})
end)
RegisterNUICallback('forceClose', function(_, cb)
    tabletOpen, hudMoveMode = false, false
    SetTabletAnim(false)
    if placing then placing = nil; SendNUIMessage({ type = 'placementBar', display = false }) end
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'tablet', display = false })
    TriggerServerEvent('lime_redzones:server:adminClosed')
    cb({})
end)
RegisterNUICallback('openAdminPanel', function(_, cb)
    TriggerServerEvent('lime_redzones:server:adminOpen')
    cb({})
end)
RegisterNUICallback('openPlayerTablet', function(_, cb)
    TriggerServerEvent('lime_redzones:server:requestLeaderboard')
    SetTablet(true, 'player', lastTab('player') or 'rzleaderboard')
    cb({})
end)

forward('addAdminId', 'lime_redzones:server:addAdmin', function(d) return tostring(d.identifier or '') end)
forward('removeAdminId', 'lime_redzones:server:removeAdmin', function(d) return tostring(d.identifier or '') end)
forward('getMyIdentifier', 'lime_redzones:server:myIdentifier')

RegisterNUICallback('toggleZone', function(d, cb) TriggerServerEvent('lime_redzones:server:toggleZone', d.id, d.enabled) cb({}) end)
forward('saveRanks', 'lime_redzones:server:saveRanks', function(d) return d.ranks end)
RegisterNUICallback('saveTabletScale', function(d, cb)
    local sc = tonumber(d.scale) or 1.0
    if sc < 0.7 then sc = 0.7 elseif sc > 1.5 then sc = 1.5 end
    SetResourceKvpFloat('rz_tablet_scale', sc)
    cb({})
end)

local function saveDefaultPos(key, p)
    TriggerServerEvent('lime_redzones:server:saveHudDefaults', { [key] = p })
end

RegisterNUICallback('saveHudTheme', function(d, cb)
    if HudLocked() then
        Notify('HUD styling is locked by an admin.', 'error')
        ApplyHudStyle()
        cb({})
        return
    end
    if d.theme then SetResourceKvp('rz_hud_theme', tostring(d.theme)) end
    if d.preset then SetResourceKvp('rz_hud_preset', tostring(d.preset)) end
    if d.scale then SetResourceKvpFloat('rz_hud_scale', tonumber(d.scale) or 1.0) end
    SendNUIMessage({ type = 'hudStyle', theme = d.theme, preset = d.preset, scale = d.scale })
    if not d.silent then Notify('HUD style saved.', 'success') end
    cb({})
end)

RegisterNUICallback('saveKillfeedStyle', function(d, cb)
    if HudLocked() then
        Notify('HUD styling is locked by an admin.', 'error')
        ApplyHudStyle()
        cb({})
        return
    end
    if d.scale then SetResourceKvpFloat('rz_kf_scale', tonumber(d.scale) or 1.0) end
    if d.theme then SetResourceKvp('rz_kf_theme', tostring(d.theme)) end
    SendNUIMessage({ type = 'kfStyle', scale = d.scale, theme = d.theme })
    Notify('Kill feed style saved.', 'success')
    cb({})
end)

forward('requestLogs', 'lime_redzones:server:requestLogs', function(d) return d end)
forward('wipeLogs', 'lime_redzones:server:wipeLogs', function(d) return d end)
forward('requestLogConfig', 'lime_redzones:server:requestLogConfig')
forward('postLeaderboardNow', 'lime_redzones:server:postLeaderboardNow', function(d) return d.board or 'redzone' end)
forward('requestPrizeHistory', 'lime_redzones:server:requestPrizeHistory')
forward('requestStats', 'lime_redzones:server:requestStats')
forward('wipePrizeHistory', 'lime_redzones:server:wipePrizeHistory')
forward('deletePrizeEntry', 'lime_redzones:server:deletePrizeEntry', function(d) return d end)
forward('saveLogConfig', 'lime_redzones:server:saveLogConfig', function(d) return d end)
forward('saveHudDefaults', 'lime_redzones:server:saveHudDefaults', function(d) return d end)
forward('gangState', 'lime_redzones:server:gangState')
forward('gangCreate', 'lime_redzones:server:gangCreate', function(d) return d end)
forward('gangInvite', 'lime_redzones:server:gangInvite', function(d) return d end)
forward('gangInviteAnswer', 'lime_redzones:server:gangInviteAnswer', function(d) return d end)
forward('gangLeave', 'lime_redzones:server:gangLeave')
forward('gangKick', 'lime_redzones:server:gangKick', function(d) return d end)
forward('gangSetRank', 'lime_redzones:server:gangSetRank', function(d) return d end)
forward('gangEdit', 'lime_redzones:server:gangEdit', function(d) return d end)
forward('gangDisband', 'lime_redzones:server:gangDisband')
forward('adminDeleteGang', 'lime_redzones:server:adminDeleteGang', function(d) return d end)
forward('requestLbEditor', 'lime_redzones:server:requestLbEditor')
forward('saveLbEntry', 'lime_redzones:server:saveLbEntry', function(d) return d end)
forward('deleteLbEntry', 'lime_redzones:server:deleteLbEntry', function(d) return d end)

RegisterNetEvent('lime_redzones:client:lbEditor', function(redzone, global)
    SendNUIMessage({ type = 'lbEditor', redzone = redzone, global = global })
end)
RegisterNUICallback('saveKillMsgStyle', function(d, cb)
    if HudLocked() then
        Notify('HUD styling is locked by an admin.', 'error')
        ApplyHudStyle()
        cb({})
        return
    end
    if d.scale then SetResourceKvpFloat('rz_km_scale', tonumber(d.scale) or 1.0) end
    if d.theme then SetResourceKvp('rz_km_theme', tostring(d.theme)) end
    SendNUIMessage({ type = 'kmStyle', scale = d.scale, theme = d.theme })
    Notify('Kill message style saved.', 'success')
    cb({})
end)

RegisterNUICallback('startKmMove', function(d, cb)
    hudDefaultTarget = d.asDefault and 'kmPos' or nil
    SetTablet(false)
    SendNUIMessage({ type = 'kmMove', enabled = true })
    SetNuiFocus(true, true)
    Notify(hudDefaultTarget and 'Drag the kill message to its default spot, then click Done.'
        or 'Drag the kill message, then click Done.', 'info')
    cb({})
end)

RegisterNUICallback('saveKillMsgPos', function(d, cb)
    if d.x and d.y then
        if hudDefaultTarget == 'kmPos' then
            saveDefaultPos('kmPos', { x = d.x, y = d.y })
        else
            SetResourceKvp('rz_km_pos', json.encode({ x = d.x, y = d.y }))
            Notify('Kill message position saved.', 'success')
        end
    end
    hudDefaultTarget = nil
    SendNUIMessage({ type = 'kmMove', enabled = false })
    SetNuiFocus(false, false)
    cb({})
end)

RegisterNUICallback('resetKmPos', function(_, cb)
    DeleteResourceKvp('rz_km_pos')
    SendNUIMessage({ type = 'kmReset' })
    ApplyHudStyle()
    Notify('Kill message position reset.', 'success')
    cb({})
end)
RegisterNUICallback('saveKillfeedPos', function(d, cb)
    if d.x and d.y then
        if hudDefaultTarget == 'kfPos' then
            saveDefaultPos('kfPos', { x = d.x, y = d.y })
        else
            SetResourceKvp('rz_kf_pos', json.encode({ x = d.x, y = d.y }))
            Notify('Kill feed position saved.', 'success')
        end
    end
    hudDefaultTarget = nil
    SendNUIMessage({ type = 'kfMove', enabled = false })
    SetNuiFocus(false, false)
    cb({})
end)
RegisterNUICallback('startKfMove', function(d, cb)
    hudDefaultTarget = d.asDefault and 'kfPos' or nil
    SetTablet(false)
    SendNUIMessage({ type = 'kfMove', enabled = true })
    SetNuiFocus(true, true)
    Notify(hudDefaultTarget and 'Drag the kill feed to its default spot, then click Done.'
        or 'Drag the kill feed, then release.', 'info')
    cb({})
end)
RegisterNUICallback('resetKfPos', function(_, cb)
    DeleteResourceKvp('rz_kf_pos')
    SendNUIMessage({ type = 'kfReset' })
    ApplyHudStyle()
    Notify('Kill feed position reset.', 'success')
    cb({})
end)

RegisterNUICallback('startHudMove', function(d, cb)
    hudDefaultTarget = d.asDefault and 'pos' or nil
    SetTablet(false)
    SetHudMove(true)
    cb({})
end)

local function SetSzMove(on)
    szMoveMode = on
    SendNUIMessage({ type = 'szMove', enabled = on })
    SetNuiFocus(on, on)
    if on then Notify('Drag the safe zone badge, then click Done.', 'info') end
end

RegisterNUICallback('startSzMove', function(d, cb)
    hudDefaultTarget = d.asDefault and 'szPos' or nil
    SetTablet(false)
    SetSzMove(true)
    cb({})
end)

RegisterNUICallback('saveSzPos', function(d, cb)
    if type(d.x) == 'number' and type(d.y) == 'number' then
        if hudDefaultTarget == 'szPos' then
            saveDefaultPos('szPos', { x = d.x, y = d.y })
        else
            szPos = { x = d.x, y = d.y }
            SetResourceKvp('rz_sz_pos', json.encode(szPos))
            SendNUIMessage({ type = 'szPos', pos = szPos })
            Notify('Safe zone HUD position saved.', 'success')
        end
    end
    hudDefaultTarget = nil
    SetSzMove(false)
    cb({})
end)

RegisterNUICallback('resetSzPos', function(_, cb)
    DeleteResourceKvp('rz_sz_pos')
    ApplyHudStyle()
    Notify('Safe zone HUD position reset.', 'success')
    cb({})
end)
RegisterNUICallback('resetHudPos', function(_, cb)
    DeleteResourceKvp('rz_hud_pos')
    ApplyHudStyle()
    Notify('HUD position reset.', 'success')
    cb({})
end)
RegisterNetEvent('lime_redzones:client:podiumAdmin', function(list)
    SendNUIMessage({ type = 'podiumAdmin', podiums = list })
end)

forward('requestPodiumAdmin', 'lime_redzones:server:requestPodiumAdmin')
forward('wipeElo', 'lime_redzones:server:wipeElo')
forward('saveEloSettings', 'lime_redzones:server:saveEloSettings', function(d) return d end)
forward('saveEloRanks', 'lime_redzones:server:saveEloRanks', function(d) return d.ranks end)
forward('deletePodium', 'lime_redzones:server:deletePodium', function(d) return d.id end)

RegisterNUICallback('startPodiumPlacement', function(d, cb)
    SetTablet(false)
    TriggerServerEvent('lime_redzones:server:beginPodiumPlacement',
        tostring(d.id or ''), tostring(d.label or 'Podium'), tostring(d.board or 'redzone'))
    cb({})
end)

RegisterNUICallback('saveOptions', function(d, cb)
    TriggerServerEvent('lime_redzones:server:saveOptions', d) cb({})
end)
RegisterNUICallback('saveCustomTheme', function(d, cb)
    TriggerServerEvent('lime_redzones:server:saveCustomTheme', d) cb({})
end)

RegisterNUICallback('saveHudPos', function(d, cb)
    if type(d.x) == 'number' and type(d.y) == 'number' then
        if hudDefaultTarget == 'pos' then
            saveDefaultPos('pos', { x = d.x, y = d.y })
        else
            hudPos = { x = d.x, y = d.y }
            SetResourceKvp('rz_hud_pos', json.encode(hudPos))
            SendNUIMessage({ type = 'hudPos', pos = hudPos })
            Notify('HUD position saved. Use /rz_hud_reset to restore default.', 'success')
        end
    end
    hudDefaultTarget = nil
    SetHudMove(false)
    cb({})
end)

RegisterCommand('rz_hud_reset', function()
    DeleteResourceKvp('rz_hud_pos')
    ApplyHudStyle()
    Notify('HUD position reset to default.', 'success')
end, false)

RegisterNUICallback('savePersonalColor', function(d, cb)
    if d.reset then
        personalColor = nil
        ApplyDrawColors()
        DeleteResourceKvp('rz_personal_color')
        Notify('Personal zone colour reset.', 'success')
    elseif type(d.hex) == 'string' and d.hex:match('^#%x%x%x%x%x%x$') then
        personalColor = { hex = d.hex, a = math.max(0, math.min(255, math.floor(tonumber(d.a) or 80))) }
        personalColor._r, personalColor._g, personalColor._b = HexToRGB(d.hex)
        ApplyDrawColors()
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
    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)
    cb({
        x = math.floor(p.x * 100) / 100,
        y = math.floor(p.y * 100) / 100,
        z = math.floor(p.z * 100) / 100,
        h = math.floor(GetEntityHeading(ped) * 10) / 10,
    })
end)
RegisterNUICallback('adminTeleportToZone', function(d, cb)
    TriggerServerEvent('lime_redzones:server:adminTeleportToZone', d.id)
    cb({})
end)

RegisterNUICallback('requestAdminData', function(_, cb)
    TriggerServerEvent('lime_redzones:server:requestAdminData')
    cb({})
end)

RegisterNUICallback('bulkUpdateZones', function(d, cb)
    TriggerServerEvent('lime_redzones:server:bulkUpdateZones', d.ids, d.patch)
    cb({})
end)

RegisterNUICallback('teleportToZone', function(d, cb)
    TriggerServerEvent('lime_redzones:server:teleportToZone', d.id)
    cb({})
end)

local function updatePlacementBar(mode, count, max, minZ, maxZ, speed)
    SendNUIMessage({ type = 'placementBar', display = true, mode = mode,
        count = count, max = max, minZ = minZ or 0, maxZ = maxZ or 0, speed = speed or 1 })
end

local function hidePlacementBar()
    SendNUIMessage({ type = 'placementBar', display = false })
end

local function DrawWallQuad(a, b, zLo, zHi, r, g, bl, al)
    DrawPoly(a.x, a.y, zLo, b.x, b.y, zLo, b.x, b.y, zHi, r, g, bl, al)
    DrawPoly(b.x, b.y, zHi, b.x, b.y, zLo, a.x, a.y, zLo, r, g, bl, al)
    DrawPoly(a.x, a.y, zLo, b.x, b.y, zHi, a.x, a.y, zHi, r, g, bl, al)
    DrawPoly(a.x, a.y, zHi, b.x, b.y, zHi, a.x, a.y, zLo, r, g, bl, al)
end

local function RunPolyFreecam(draft)
    local ped = PlayerPedId()
    local start = GetEntityCoords(ped)
    local points = draft.poly or {}
    local minZ = tonumber(draft.polyMinZ) or (start.z - 2.0)
    local maxZ = tonumber(draft.polyMaxZ) or (start.z + 8.0)
    if maxZ <= minZ then maxZ = minZ + 4.0 end
    local speed = 1.0

    local lastHit = nil
    local rayHandle = nil
    local camPos
    if #points >= 1 then
        local cx, cy = 0.0, 0.0
        for i = 1, #points do cx = cx + points[i].x; cy = cy + points[i].y end
        cx, cy = cx / #points, cy / #points
        camPos = vector3(cx, cy, maxZ + 22.0)
    else
        camPos = vector3(start.x, start.y, start.z + 18.0)
    end
    local rotX, rotZ = -35.0, GetEntityHeading(ped)
    local cam = makeCam('editor')
    if cam == nil then
        Notify('Cannot open the shape editor — the game camera pool is full. Rejoin and try again.', 'error')
        hidePlacementBar()
        return
    end
    SetCamCoord(cam, camPos.x, camPos.y, camPos.z)
    SetCamRot(cam, rotX, 0.0, rotZ, 2)
    RenderScriptCams(true, true, 400, true, true)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)

    local barTick = 0
    updatePlacementBar('poly', #points, 24, minZ, maxZ, speed)

    while true do
        Wait(0)
        DisableAllControlActions(0)
        DisableAllControlActions(1)
        DisableAllControlActions(2)
        if SetPauseMenuActive then pcall(SetPauseMenuActive, false) end
        if HudWeaponWheelIgnoreSelection then pcall(HudWeaponWheelIgnoreSelection) end
        HideHudAndRadarThisFrame()

        rotZ = rotZ - GetDisabledControlNormal(0, 1) * 6.0
        rotX = math.max(-89.0, math.min(89.0, rotX - GetDisabledControlNormal(0, 2) * 5.0))
        local radZ, radX = math.rad(rotZ), math.rad(rotX)
        local fwd = vector3(-math.sin(radZ) * math.cos(radX), math.cos(radZ) * math.cos(radX), math.sin(radX))
        local right = vector3(math.cos(radZ), math.sin(radZ), 0.0)

        local mv = speed * (IsDisabledControlPressed(0, 21) and 2.5 or 1.0)
        if IsDisabledControlPressed(0, 32) then camPos = camPos + fwd * mv end
        if IsDisabledControlPressed(0, 33) then camPos = camPos - fwd * mv end
        if IsDisabledControlPressed(0, 34) then camPos = camPos - right * mv end
        if IsDisabledControlPressed(0, 35) then camPos = camPos + right * mv end
        if IsDisabledControlPressed(0, 44) then camPos = camPos - vector3(0,0,mv) end
        if IsDisabledControlPressed(0, 38) then camPos = camPos + vector3(0,0,mv) end
        if IsDisabledControlPressed(0, 22) then camPos = camPos + vector3(0,0,mv) end
        if IsDisabledControlJustPressed(0, 241) then speed = math.min(6.0, speed + 0.3) end
        if IsDisabledControlJustPressed(0, 242) then speed = math.max(0.2, speed - 0.3) end

        SetCamCoord(cam, camPos.x, camPos.y, camPos.z)
        SetCamRot(cam, rotX, 0.0, rotZ, 2)

        local shift = IsDisabledControlPressed(0, 21)
        if IsDisabledControlJustPressed(0, 73) or IsDisabledControlJustPressed(0, 172) then
            if shift then minZ = math.min(maxZ - 1.0, minZ + 1.0) else maxZ = maxZ + 1.0 end
        end
        if IsDisabledControlJustPressed(0, 20) or IsDisabledControlJustPressed(0, 173) then
            if shift then minZ = minZ - 1.0 else maxZ = math.max(minZ + 1.0, maxZ - 1.0) end
        end

        if rayHandle == nil then
            local target = camPos + fwd * 2000.0
            rayHandle = StartShapeTestRay(camPos.x, camPos.y, camPos.z,
                target.x, target.y, target.z, 1 + 16, 0, 7)
        else
            local status, hit, hitPos = GetShapeTestResult(rayHandle)
            if status ~= 1 then
                rayHandle = nil
                if hit and hit ~= 0 and hitPos then
                    lastHit = vector3(hitPos.x, hitPos.y, hitPos.z)
                end
            end
        end
        local cursor = lastHit

        if not cursor then
            local denom = fwd.z
            if denom < -0.05 then
                local t = (camPos.z - minZ) / -denom
                if t > 0 and t < 3000.0 then
                    cursor = vector3(camPos.x + fwd.x * t, camPos.y + fwd.y * t, minZ)
                end
            end
        end

        local n = #points
        for i = 1, n do
            local a = points[i]
            local b = points[i % n + 1]
            if n > 1 then
                DrawWallQuad(a, b, minZ, maxZ, 163, 230, 53, 55)
                DrawLine(a.x, a.y, minZ, b.x, b.y, minZ, 163, 230, 53, 220)
                DrawLine(a.x, a.y, maxZ, b.x, b.y, maxZ, 163, 230, 53, 160)
            end
            DrawLine(a.x, a.y, minZ, a.x, a.y, maxZ, 163, 230, 53, 130)
            DrawMarker(28, a.x, a.y, minZ + 0.4, 0.0,0.0,0.0, 0.0,0.0,0.0,
                0.5, 0.5, 0.5, 163, 230, 53, 200, false, false, 2, false, nil, nil, false)
        end
        if cursor then
            DrawMarker(28, cursor.x, cursor.y, cursor.z + 0.25, 0.0,0.0,0.0, 0.0,0.0,0.0,
                0.4, 0.4, 0.4, 255, 255, 255, 180, false, false, 2, false, nil, nil, false)
            if n > 0 then
                local last = points[n]
                DrawLine(last.x, last.y, minZ, cursor.x, cursor.y, cursor.z, 255, 255, 255, 120)
            end
        end

        if IsDisabledControlJustPressed(0, 237) and cursor and n < 24 then
            points[n + 1] = { x = math.floor(cursor.x * 100) / 100, y = math.floor(cursor.y * 100) / 100, z = math.floor(cursor.z * 100) / 100 }
            PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
        end
        if IsDisabledControlJustPressed(0, 238) and n > 0 then
            table.remove(points)
            PlaySoundFrontend(-1, 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
        end
        if IsDisabledControlJustPressed(0, 191) then
            draft.poly = #points >= 3 and points or {}
            draft.polyMinZ = #points >= 3 and minZ or nil
            draft.polyMaxZ = #points >= 3 and maxZ or nil
            break
        end
        if IsDisabledControlJustPressed(0, 194) then
            break
        end

        barTick = barTick + 1
        if barTick >= 15 then
            barTick = 0
            updatePlacementBar('poly', #points, 24, minZ, maxZ, speed)
            if RZ_DEBUG then
                print(('[lime_redzones] freecam pts=%d cursor=%s cam=%.1f,%.1f,%.1f')
                    :format(#points, cursor and 'yes' or 'NO', camPos.x, camPos.y, camPos.z))
            end
        end
    end

    RenderScriptCams(false, true, 400, true, true)
    dropCam(cam)
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    EnableAllControlActions(0)
    EnableAllControlActions(1)
    EnableAllControlActions(2)
    hidePlacementBar()
end

local function BeginPointPlacement(mode, draft, maxPoints, onFinish, onError)
    maxPoints = maxPoints or 5
    local existing
    if mode == 'tp' then existing = draft.tpPoints
    elseif mode == 'podium' then existing = draft.points
    elseif mode == 'npc' then existing = draft.teleportNpcs
    else existing = draft.exits end
    existing = existing or {}
    placing = { draft = draft, points = existing, mode = mode, max = maxPoints }

    CreateThread(function()
        local ok, err = pcall(function()
            updatePlacementBar(mode, #placing.points, maxPoints)
            local barTick = 0
            while placing do
                Wait(0)
                local ped = PlayerPedId()
                local pos = GetEntityCoords(ped)

                DisableControlAction(0, 38, true)
                DisableControlAction(0, 47, true)
                DisableControlAction(0, 73, true)
                DisableControlAction(0, 23, true)
                DisableControlAction(0, 75, true)
                DisableControlAction(0, 24, true)
                DisableControlAction(0, 25, true)
                DisableControlAction(0, 37, true)
                DisableControlAction(0, 194, true)

                for _, p in ipairs(placing.points) do
                    DrawMarker(1, p.x, p.y, (p.z or pos.z) - 0.95, 0.0,0.0,0.0, 0.0,0.0,0.0,
                        1.2, 1.2, 0.6, 163, 230, 53, 160, false, false, 2, false, nil, nil, false)
                end

                if IsDisabledControlJustReleased(0, 73) and #placing.points > 0 then
                    table.remove(placing.points)
                    PlaySoundFrontend(-1, 'BACK', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                end

                if IsDisabledControlJustReleased(0, 38) and #placing.points < placing.max then
                    placing.points[#placing.points+1] = {
                        x = math.floor(pos.x * 100) / 100,
                        y = math.floor(pos.y * 100) / 100,
                        z = math.floor(pos.z * 100) / 100,
                        h = math.floor(GetEntityHeading(ped) * 10) / 10,
                        model = (placing.mode == 'npc')
                                and (Config.TeleportNpcModels and Config.TeleportNpcModels[#placing.points+1])
                                or nil,
                    }
                    PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                end

                if IsDisabledControlJustPressed(0, 194) then
                    placing = nil
                    hidePlacementBar()
                    if onError then onError() end
                end

                if placing and IsDisabledControlJustReleased(0, 47) then
                    local finalDraft = placing.draft
                    if placing.mode == 'tp' then finalDraft.tpPoints = placing.points
                    elseif placing.mode == 'podium' then finalDraft.podiumPoints = placing.points
                    elseif placing.mode == 'npc' then finalDraft.teleportNpcs = placing.points
                    else finalDraft.exits = placing.points end
                    placing = nil
                    hidePlacementBar()
                    if onFinish then onFinish(finalDraft) end
                end

                barTick = barTick + 1
                if barTick >= 20 and placing then
                    barTick = 0
                    updatePlacementBar(placing.mode, #placing.points, maxPoints)
                end
            end
        end)

        if not ok then
            print('[lime_redzones] ^1point placement ERROR:^0 ' .. tostring(err))
            placing = nil
            hidePlacementBar()
            Notify('Placement editor error — check server console (F8).', 'error')
            if onError then onError() end
        end
    end)
end

RZBeginPointPlacement = BeginPointPlacement

RegisterNUICallback('startPlacement', function(d, cb)
    local mode = (d.mode == 'tp' and 'tp') or (d.mode == 'poly' and 'poly') or (d.mode == 'npc' and 'npc') or 'exit'
    print(('[lime_redzones] startPlacement received: mode=%s draft=%s')
        :format(tostring(d.mode), d.draft and 'yes' or 'NIL'))
    SetTablet(false)
    cb({})

    if mode == 'poly' then
        CreateThread(function()
            local draft = d.draft or {}
            print(('[lime_redzones] shape editor: opening (existing corners=%d)')
                :format(type(draft.poly) == 'table' and #draft.poly or 0))

            local ok, err = pcall(RunPolyFreecam, draft)
            if not ok then
                print('[lime_redzones] ^1shape editor ERROR:^0 ' .. tostring(err))
                RenderScriptCams(false, false, 0, true, true)
                reapCams('editor')
                local ped = PlayerPedId()
                FreezeEntityPosition(ped, false)
                SetEntityVisible(ped, true, false)
                EnableAllControlActions(0)
                EnableAllControlActions(1)
                EnableAllControlActions(2)
                hidePlacementBar()
                Notify('Shape editor error — check server console (F8).', 'error')
            end

            print(('[lime_redzones] shape editor: closed with %d corner(s)')
                :format(type(draft.poly) == 'table' and #draft.poly or 0))
            SetTablet(true, 'admin', 'zones')
            SendNUIMessage({ type = 'placementDone', draft = draft })
        end)
        return
    end

    local maxPoints = (mode == 'npc') and 4 or 5
    local draft = d.draft or {}
    BeginPointPlacement(mode, draft, maxPoints, function(finalDraft)
        SetTablet(true, 'admin', 'zones')
        SendNUIMessage({ type = 'placementDone', draft = finalDraft })
    end, function()
        SetTablet(true, 'admin', 'zones')
        SendNUIMessage({ type = 'placementDone', draft = draft })
    end)
end)

RegisterNetEvent('lime_redzones:client:beginNpcPlacement', function(zone)
    Notify(('Placing teleport NPCs for "%s" — E to place (max 4), X to undo, G to finish.')
        :format(zone.name or tostring(zone.id)), 'info')
    BeginPointPlacement('npc', zone, 4, function(finalDraft)
        TriggerServerEvent('lime_redzones:server:saveZone', finalDraft)
        Notify('Teleport NPC positions saved.', 'success')
    end)
end)

RegisterCommand('rz_addteleportnpc', function(_, args)
    local zoneId = args[1]
    if not zoneId then
        Notify('Usage: /rz_addteleportnpc <zoneId> — zone IDs are shown in the admin tablet\'s Zones tab.', 'error')
        return
    end
    TriggerServerEvent('lime_redzones:server:beginNpcPlacement', zoneId)
end, false)

local spawnedNpcs = {}
local npcGen       = {}
local npcTargetLib = nil

CreateThread(function()
    if GetResourceState('ox_target') == 'started' then npcTargetLib = 'ox'
    elseif GetResourceState('qb-target') == 'started' then npcTargetLib = 'qb'
    elseif GetResourceState('qtarget') == 'started' then npcTargetLib = 'qtarget'
    end
end)

local function AddNpcTarget(ped, zoneId, zoneName)
    local label = ('Teleport to %s'):format(zoneName or 'Redzone')
    if npcTargetLib == 'ox' then
        pcall(function()
            exports.ox_target:addLocalEntity(ped, {
                { name = 'rz_tp_' .. tostring(zoneId) .. '_' .. tostring(ped),
                  icon = 'fas fa-street-view', label = label,
                  onSelect = function() TriggerServerEvent('lime_redzones:server:teleportToZone', zoneId) end },
            })
        end)
    elseif npcTargetLib then
        local res = npcTargetLib == 'qb' and 'qb-target' or 'qtarget'
        pcall(function()
            exports[res]:AddTargetEntity(ped, {
                options = { { type = 'client', icon = 'fas fa-street-view', label = label,
                    action = function() TriggerServerEvent('lime_redzones:server:teleportToZone', zoneId) end } },
                distance = 2.5,
            })
        end)
    end
end

local function SpawnZoneNpcs(zoneId, zone)
    if spawnedNpcs[zoneId] then return end
    local gen = (npcGen[zoneId] or 0) + 1
    npcGen[zoneId] = gen
    local handles = {}
    spawnedNpcs[zoneId] = handles

    for i, npc in ipairs(zone.teleportNpcs) do
        if i <= 4 then
            CreateThread(function()
                local model = (type(npc.model) == 'string' and npc.model ~= '') and npc.model
                              or (Config.TeleportNpcModels and Config.TeleportNpcModels[i]) or 'a_m_y_business_01'
                local hash = GetHashKey(model)
                RequestModel(hash)
                local tries = 0
                while not HasModelLoaded(hash) and tries < 100 do Wait(10) tries = tries + 1 end

                if spawnedNpcs[zoneId] ~= handles or npcGen[zoneId] ~= gen or not HasModelLoaded(hash) then
                    SetModelAsNoLongerNeeded(hash)
                    return
                end

                local ped = CreatePed(4, hash, npc.x, npc.y, (npc.z or 0.0) - 1.0, npc.h or 0.0, false, true)
                SetEntityAsMissionEntity(ped, true, true)
                FreezeEntityPosition(ped, true)
                SetEntityInvincible(ped, true)
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedCanRagdoll(ped, false)
                SetPedDiesWhenInjured(ped, false)
                SetPedCanBeTargetted(ped, false)
                SetPedCanPlayAmbientAnims(ped, true)
                TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
                SetModelAsNoLongerNeeded(hash)

                if spawnedNpcs[zoneId] == handles and npcGen[zoneId] == gen then
                    handles[#handles+1] = ped
                    AddNpcTarget(ped, zoneId, zone.name)
                else
                    DeleteEntity(ped)
                end
            end)
        end
    end
end

local function DespawnZoneNpcs(zoneId)
    local handles = spawnedNpcs[zoneId]
    if not handles then return end
    spawnedNpcs[zoneId] = nil
    npcGen[zoneId] = (npcGen[zoneId] or 0) + 1
    for _, ped in ipairs(handles) do
        if npcTargetLib == 'ox' then
            pcall(function() exports.ox_target:removeLocalEntity(ped) end)
        elseif npcTargetLib == 'qb' then
            pcall(function() exports['qb-target']:RemoveTargetEntity(ped) end)
        elseif npcTargetLib == 'qtarget' then
            pcall(function() exports.qtarget:RemoveTargetEntity(ped) end)
        end
        if DoesEntityExist(ped) then
            SetEntityAsMissionEntity(ped, true, true)
            DeleteEntity(ped)
            if DoesEntityExist(ped) then DeletePed(ped) end
        end
    end
end

CreateThread(function()
    while true do
        Wait(1000)
        local pos = GetEntityCoords(PlayerPedId())
        for zoneId, z in pairs(Zones) do
            local hasNpcs = z.type ~= 'safezone' and z.enabled ~= false and z.allowTeleport == true
                            and type(z.teleportNpcs) == 'table' and #z.teleportNpcs > 0
            if hasNpcs then
                local d = #(pos - vector3(z.coords.x, z.coords.y, z.coords.z))
                local base = (z.radius or 60.0) + 100.0
                if spawnedNpcs[zoneId] then
                    if d > base + 40.0 then DespawnZoneNpcs(zoneId) end
                elseif d <= base then
                    SpawnZoneNpcs(zoneId, z)
                end
            elseif spawnedNpcs[zoneId] then
                DespawnZoneNpcs(zoneId)
            end
        end
    end
end)

CreateThread(function()
    while true do
        if npcTargetLib then
            Wait(2500)
            goto continue
        end

        local pos = GetEntityCoords(PlayerPedId())
        local closestPed, closestZone, closestD = nil, nil, 2.0
        for zoneId, handles in pairs(spawnedNpcs) do
            for _, npcPed in ipairs(handles) do
                if DoesEntityExist(npcPed) then
                    local dd = #(pos - GetEntityCoords(npcPed))
                    if dd < closestD then closestD = dd closestPed = npcPed closestZone = zoneId end
                end
            end
        end

        if closestPed then
            local z = Zones[closestZone]
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(('Press ~INPUT_CONTEXT~ to teleport to %s'):format(z and z.name or 'Redzone'))
            EndTextCommandDisplayHelp(0, false, false, -1)
            if IsControlJustReleased(0, 38) then
                TriggerServerEvent('lime_redzones:server:teleportToZone', closestZone)
            end
            Wait(0)
        else
            Wait(500)
        end
        ::continue::
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for zoneId in pairs(spawnedNpcs) do DespawnZoneNpcs(zoneId) end
end)

CreateThread(function()
    local frame = 0
    local nearest, nearestId, nDist = nil, nil, math.huge
    local safeZone, safeZoneId, safeDist = nil, nil, math.huge
    local nextScan = 0
    local nextSafeCheck = 0
    local nextDeathCheck = 0
    local function ZonePass()
        local renderDist = DynRenderDist or 120.0
        local cullDist = renderDist > 200.0 and renderDist or 200.0
        if not next(Zones) then Wait(2500) return end

        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)

        local now = GetGameTimer()

        if now >= nextDeathCheck then
            nextDeathCheck = now + 50
            CheckDeath(ped)
        end
        if now >= nextScan then
            nextScan = now + 250
            nearest, nearestId, nDist = nil, nil, math.huge
            safeZone, safeZoneId, safeDist = nil, nil, math.huge
            for id, z in pairs(Zones) do
                if z.enabled then
                    local d = #(pos - z.vec)
                    if z._safe then
                        if d < safeDist then safeZone, safeZoneId, safeDist = z, id, d end
                    else
                        if d < nDist then nearest, nearestId, nDist = z, id, d end
                    end
                end
            end
        else
            local px, py, pz = pos.x, pos.y, pos.z
            if nearest then
                local v = nearest.vec
                local dx, dy, dz = px - v.x, py - v.y, pz - v.z
                nDist = (dx*dx + dy*dy + dz*dz) ^ 0.5
            end
            if safeZone then
                local v = safeZone.vec
                local dx, dy, dz = px - v.x, py - v.y, pz - v.z
                safeDist = (dx*dx + dy*dy + dz*dz) ^ 0.5
            end
        end

        if now >= nextSafeCheck then
            nextSafeCheck = now + 100
            local inSafe = safeZone and InsideZone(safeZone, pos)
            if inSafe and currentSafeId ~= safeZoneId then
                currentSafeId = safeZoneId
                TriggerServerEvent('lime_redzones:server:syncSafePresence', currentSafeId)
                ApplySafeState(safeZone)
                if safeZone.hideHud ~= true then
                    SendNUIMessage({
                    type = 'safezone', display = true, name = safeZone.name,
                    speedLimit = tonumber(safeZone.speedLimit) or 0,
                    invincible = safeZone.invincible ~= false,
                    weapons = safeZone._wmode or 'holster',
                    phase = safeZone.phaseThrough ~= false,
                })
                end
                Notify(_U('entered_safezone', safeZone.name), 'success')

                if safeZone.deleteVehicleOnEntry == true then
                    local ped2 = PlayerPedId()
                    local veh = GetVehiclePedIsIn(ped2, false)
                    if veh ~= 0 and DoesEntityExist(veh) then
                        TaskLeaveVehicle(ped2, veh, 16)
                        SetTimeout(700, function()
                            if DoesEntityExist(veh) then
                                SetEntityAsMissionEntity(veh, true, true)
                                DeleteEntity(veh)
                            end
                        end)
                        Notify(_U('no_vehicles'), 'info')
                    end
                end
            elseif not inSafe and currentSafeId then
                local leftName = Zones[currentSafeId] and Zones[currentSafeId].name or 'safe zone'
                currentSafeId = nil
                TriggerServerEvent('lime_redzones:server:syncSafePresence', nil)
                ApplySafeState(nil)
                SendNUIMessage({ type = 'safezone', display = false })
                Notify(_U('left_safezone', leftName), 'info')
            end
        end

        if not nearest or nDist > (nearest.radius + renderDist) then
            if currentZoneId and not (wasDead and reviveRequest) then
                currentZoneId = nil
                UpdateHUD()
            end
            local safeVisible = safeZone and safeDist <= (safeZone.radius + renderDist) and safeZone.showMarker ~= false
            local safeCur = currentSafeId and Zones[currentSafeId] or nil
            local needsFrame = safeCur ~= nil and safeCur._wmode ~= 'off'
            if safeVisible then
                DrawSafeMarker(safeZone, pos.x, pos.y, cullDist)
                if needsFrame then ApplySafeControls(safeCur._holster) end
                Wait(0)
            elseif needsFrame then
                ApplySafeControls(safeCur._holster)
                Wait(0)
            elseif safeCur then
                Wait(50)
            else
                Wait(currentZoneId and 100 or (nDist > (nearest and nearest.radius or 0) + renderDist + 200.0 and 2000 or 1000))
            end
        else
            local showVisual = nearest.showMarker ~= false
            if showVisual then
                if nearest._isPoly then
                    DrawPolyWalls(nearest, pos.x, pos.y, cullDist)
                else
                    local rad = nearest.radius + 0.0
                    DrawMarker(28, nearest.vec.x, nearest.vec.y, nearest.vec.z,
                        0.0,0.0,0.0, 0.0,0.0,0.0,
                        rad, rad, rad,
                        nearest._dr or nearest._r, nearest._dg or nearest._g,
                        nearest._db or nearest._b, nearest._da or nearest._a or 80,
                        false, false, 2, false, nil, nil, false)
                end
            end

            frame = frame + (showVisual and 1 or 30)
            if frame >= 30 then
                frame = 0
                local inside = InsideZone(nearest, pos)

                if inside and currentZoneId ~= nearestId then
                    currentZoneId = nearestId
                    TriggerServerEvent('lime_redzones:server:requestMyStats')
                    UpdateHUD()

                    if nearest.deleteVehicleOnEntry ~= false then
                        local veh = GetVehiclePedIsIn(ped, false)
                        if veh ~= 0 and DoesEntityExist(veh) then
                            TaskLeaveVehicle(ped, veh, 16)
                            SetTimeout(700, function()
                                if DoesEntityExist(veh) then
                                    SetEntityAsMissionEntity(veh, true, true)
                                    DeleteEntity(veh)
                                end
                            end)
                            Notify(_U('no_vehicles'), 'info')
                        end
                    end
                elseif not inside and currentZoneId then
                    currentZoneId = nil
                    UpdateHUD()
                end

                if inside and nearest.infiniteStamina then
                    RestorePlayerStamina(PlayerId(), 1.0)
                end

                if inside and nearest._weapSet then
                    local cur = GetSelectedPedWeapon(PlayerPedId())
                    if not nearest._weapSet[cur] then
                        SetCurrentPedWeapon(PlayerPedId(), `WEAPON_UNARMED`, true)
                        if (GetGameTimer() - (lastWeapNotify or 0)) > 8000 then
                            lastWeapNotify = GetGameTimer()
                            Notify(_U('weapon_locked'), 'error')
                        end
                    end
                end
            end

            local safeVisible2 = safeZone and safeDist <= (safeZone.radius + renderDist) and safeZone.showMarker ~= false
            if safeVisible2 then DrawSafeMarker(safeZone, pos.x, pos.y, cullDist) end
            local safeCur2 = currentSafeId and Zones[currentSafeId] or nil
            local needsFrame2 = safeCur2 ~= nil and safeCur2._wmode ~= 'off'
            if needsFrame2 then ApplySafeControls(safeCur2._holster) end

            if showVisual or safeVisible2 or needsFrame2 then
                Wait(0)
            else
                Wait(safeCur2 and 50 or 300)
            end
        end
    end

    while true do
        local ok, err = pcall(ZonePass)
        if not ok then
            print('[lime_redzones] ERROR in zone loop (recovered): ' .. tostring(err))
            pcall(TriggerServerEvent, 'lime_redzones:server:clientDebug', 'ZONE LOOP ERROR: ' .. tostring(err))
            Wait(1000)
        end
    end
end)

CreateThread(function()
    local wasDeadGlobal = false
    while true do
        Wait(1500)
        local _t = GetGameTimer()
        for ped, ts in pairs(recentKills) do
            if _t - ts > 5000 then recentKills[ped] = nil end
        end
        if Opts.globalLbEnabled == false then
            wasDeadGlobal = false
        else
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
    end
end)

local function dbg(...)
    if RZ_DEBUG then print('[lime_redzones]', ...) end
end

RegisterCommand('rz_pools', function()
    local mine = 0
    for _, handles in pairs(spawnedNpcs) do
        for _, p in ipairs(handles) do
            if DoesEntityExist(p) then mine = mine + 1 end
        end
    end
    local cams = 0
    for _ in pairs(liveCams) do cams = cams + 1 end
    local line = ('%s | ourNpcs=%d ourCams=%d tabletProp=%s')
        :format(poolCensus(), mine, cams, tostring(tabletProp ~= nil))
    print('[lime_redzones] ' .. line)
    Notify(line, 'info', 12000)
end, false)

RegisterCommand('rz_debug', function()
    RZ_DEBUG_LOCAL = not RZ_DEBUG
    resolveDebug()
    Notify('Redzone debug ' .. (RZ_DEBUG and 'ON' or 'OFF') .. ' (local override). Check F8 console.', 'info')
    print('[lime_redzones] debug = ' .. tostring(RZ_DEBUG) .. ' (override) | server option = ' .. tostring(RZ_DEBUG_SERVER) .. ' | currentZoneId = ' .. tostring(currentZoneId))
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

    local function resolveVictimId(vped)
        local idx = NetworkGetPlayerIndexFromPed(vped)
        if idx and idx ~= -1 then return GetPlayerServerId(idx) end

        for _, pid in ipairs(GetActivePlayers()) do
            if GetPlayerPed(pid) == vped then return GetPlayerServerId(pid) end
        end

        if DoesEntityExist(vped) then
            local vpos, best, bestD = GetEntityCoords(vped), nil, 2.0
            for _, pid in ipairs(GetActivePlayers()) do
                local p = GetPlayerPed(pid)
                if p ~= 0 and p ~= PlayerPedId() and DoesEntityExist(p) then
                    local d = #(GetEntityCoords(p) - vpos)
                    if d < bestD then bestD = d; best = pid end
                end
            end
            if best then return GetPlayerServerId(best) end
        end
        return 0
    end

    local victimServerId = resolveVictimId(victim)
    dbg('victim resolved to server id: ' .. tostring(victimServerId))

    local function registerKill(reason)
        if recentKills[victim] and (GetGameTimer() - recentKills[victim]) < 3000 then return end
        recentKills[victim] = GetGameTimer()

        local zoneNow = ZoneAtPlayer() or currentZoneId
        dbg('registerKill via ' .. reason .. ' | zoneNow=' .. tostring(zoneNow))
        if zoneNow then
            currentZoneId = zoneNow
            kills = kills + 1
            killStreak = killStreak + 1
            UpdateHUD()
            TriggerServerEvent('lime_redzones:server:giveKillReward', zoneNow, victimServerId, weapon)
        else
            TriggerServerEvent('lime_redzones:server:globalKill')
        end
    end

    local victimIsPlayer = IsPedAPlayer(victim)
    if not victimIsPlayer then return end

    if isFatal == 1 or isFatal == true then
        registerKill('isFatal')
    elseif not pendingPoll[victim] and not recentKills[victim] then
        pendingPoll[victim] = true
        local v = victim
        CreateThread(function()
            for _ = 1, 15 do
                Wait(80)
                if not DoesEntityExist(v) then break end
                if IsEntityDead(v) then
                    registerKill('health-poll')
                    break
                end
            end
            pendingPoll[v] = nil
        end)
    end
end)
