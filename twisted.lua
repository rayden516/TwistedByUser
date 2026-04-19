-- =============================================
-- Storm Tracker — Tornado + Probe ESP + Freeze + Tween
-- =============================================

local RunService  = game:GetService("RunService")
local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- =============================================
-- FORWARD DECLARATIONS
-- =============================================

local findProbePart
local scanProbes
local updateProbeEsp

-- =============================================
-- USERID FROM MEMORY Credits to egowho in matcha discord server <3
-- =============================================

local function getUserIdFromMemory()
    if not getbase or not memory_read then return nil end
    local base = getbase()
    if not base or base == 0 then return nil end
    local success, result = pcall(function()
        local dm = memory_read("uintptr_t", memory_read("uintptr_t", base + 0x7a1d388) + 0x1c0)
        if dm == 0 then return nil end
        local function getChild(parent, name)
            local ptr = memory_read("uintptr_t", parent + 0x78)
            if ptr == 0 then return nil end
            local s = memory_read("uintptr_t", ptr)
            local e = memory_read("uintptr_t", ptr + 0x8)
            for i = 0, (e - s) / 8 - 1 do
                local c = memory_read("uintptr_t", s + i * 8)
                if c == 0 then continue end
                local namePtr = memory_read("uintptr_t", c + 0xb0)
                if namePtr == 0 then continue end
                local childName = memory_read("string", namePtr)
                if childName == name then return c end
            end
            return nil
        end
        local players = getChild(dm, "Players")
        if not players then return nil end
        local lp = memory_read("uintptr_t", players + 0x130)
        if lp == 0 then return nil end
        local userId = memory_read("uintptr_t", lp + 0x2c8)
        if userId and userId > 1000000 and userId < 10000000000 then
            return tostring(userId)
        end
        return nil
    end)
    if success and result then return result end
    return nil
end

local myUserId = nil
local attempts = 0
while not myUserId and attempts < 15 do
    myUserId = getUserIdFromMemory()
    attempts = attempts + 1
    if not myUserId then task.wait(0.1) end
end
if not myUserId then
    local lp = Players.LocalPlayer
    myUserId = (lp and lp.UserId) and tostring(lp.UserId) or "0"
end

-- =============================================
-- CONFIG
-- =============================================

local FeatureConfig = {
    TornadoESP      = { Visible = false },
    ProbeESP        = { Visible = false },
    CarFreeze       = { Enabled = false },
    CharacterFreeze = { Enabled = false },
    Tornado = {
        ShowBox    = true,
        ShowLine   = true,
        ShowCircle = true,
        BoxColor    = Color3.new(1, 0, 0),
        LineColor   = Color3.new(1, 1, 0),
        CircleColor = Color3.new(0, 1, 1),
        TextColor   = Color3.new(1, 0, 0),
    },
    Probe = {
        BoxColor  = Color3.new(0, 1, 1),
        TextColor = Color3.new(0, 1, 1),
    },
    Tween = {
        Speed  = 120,
        Height = 0.5,
        Offset = 30,
    },
}

-- =============================================
-- ESP OBJECT POOL
-- =============================================

local espPool    = {}
local activeKeys = {
    tornado = {},
    probe   = {},
}

local function getPoolEntry(key, withCircle, withLine)
    if espPool[key] then return espPool[key] end

    local entry = {}

    local box = Drawing.new("Square")
    box.Filled       = false
    box.Thickness    = 1
    box.Transparency = 1
    box.Visible      = false
    entry.box = box

    local label = Drawing.new("Text")
    label.Center       = true
    label.Outline      = true
    label.Font         = 2
    label.Size         = 14
    label.Transparency = 1
    label.Visible      = false
    entry.label = label

    if withCircle then
        local circle = Drawing.new("Circle")
        circle.Radius       = 10
        circle.Thickness    = 2
        circle.NumSides     = 32
        circle.Filled       = true
        circle.Transparency = 1
        circle.Visible      = false
        entry.circle = circle
    end

    if withLine then
        local line = Drawing.new("Line")
        line.Thickness    = 2
        line.Transparency = 1
        line.Visible      = false
        entry.line = line
    end

    espPool[key] = entry
    return entry
end

local function hideEntry(entry)
    if not entry then return end
    if entry.box    then entry.box.Visible    = false end
    if entry.label  then entry.label.Visible  = false end
    if entry.circle then entry.circle.Visible = false end
    if entry.line   then entry.line.Visible   = false end
end

local function removeEntry(key)
    local entry = espPool[key]
    if not entry then return end
    hideEntry(entry)
    pcall(function()
        if entry.box    then entry.box:Remove()    end
        if entry.label  then entry.label:Remove()  end
        if entry.circle then entry.circle:Remove() end
        if entry.line   then entry.line:Remove()   end
    end)
    espPool[key] = nil
end

local function cleanupBucket(bucket, seen)
    for key in pairs(bucket) do
        if not seen[key] then
            hideEntry(espPool[key])
            bucket[key] = nil
        end
    end
end

-- =============================================
-- WORLD TO SCREEN - CORREGIDO
-- =============================================

local function toScreen(pos)
    if not pos then return nil, false end
    
    if type(WorldToScreen) == "function" then
        local ok, scr, on = pcall(WorldToScreen, pos)
        if ok and scr then return scr, on end
    end
    
    local cam = workspace.CurrentCamera
    if cam then
        local ok, v, vis = pcall(function() return cam:WorldToViewportPoint(pos) end)
        if ok and v then 
            return Vector2.new(v.X, v.Y), vis 
        end
    end
    
    return nil, false
end

-- =============================================
-- WIND / SPEED HELPERS
-- =============================================

local WIND_ATTRS = {"WindSpeed","windspeed","wind_speed","Speed","speed","Intensity","intensity","EF","EFRating"}
local prevPos    = {}
local prevTime   = {}
local moveVec    = {}
local speedBufs  = {}
local sizeCache  = {}

local SPEED_BUF_MAX  = 10
local SPEED_INTERVAL = 0.5

local function readWindAttr(storm)
    local targets = {storm, storm:FindFirstChild("rotation")}
    for _, obj in ipairs(targets) do
        if obj and obj.GetAttribute then
            for _, a in ipairs(WIND_ATTRS) do
                local ok, v = pcall(function() return obj:GetAttribute(a) end)
                if ok and type(v) == "number" and v > 0 then
                    return v > 50 and v or v * 2.237
                end
            end
        end
    end
    return nil
end

local function sampleSpeed(key, pos)
    local now = tick()
    if not speedBufs[key] then speedBufs[key] = {s={}, lp=pos, lt=now}; return end
    local b = speedBufs[key]
    local dt = now - b.lt
    if dt < SPEED_INTERVAL then return end
    local dx, dz = pos.X - b.lp.X, pos.Z - b.lp.Z
    local mph = math.sqrt(dx*dx + dz*dz) / dt * 0.627
    local s = b.s; s[#s+1] = mph
    if #s > SPEED_BUF_MAX then table.remove(s, 1) end
    b.lp = pos; b.lt = now
end

local function getSpeed(key)
    local b = speedBufs[key]
    if not b or #b.s == 0 then return 0 end
    local tw, ws = 0, 0
    for i, v in ipairs(b.s) do ws = ws + v*i; tw = tw + i end
    return ws / tw
end

local function getDir(key, pos)
    local now = tick()
    if not prevPos[key] then prevPos[key] = pos; prevTime[key] = now; return nil end
    local mov = pos - prevPos[key]
    local dt  = now - prevTime[key]
    prevPos[key] = pos; prevTime[key] = now
    local mag = mov.Magnitude
    if dt > 0 and mag > 0.01 then
        local nd  = mov / mag
        local old = moveVec[key]
        moveVec[key] = old and (old*0.3 + nd*0.7).Unit or nd
    end
    return moveVec[key]
end

-- =============================================
-- DATA TABLES
-- =============================================

local tornadoData  = {}
local probeData    = {}
local probeCounter = 0
local frameCount   = 0

-- =============================================
-- PROBE PART FINDER
-- =============================================

function findProbePart(probe)
    if not probe or not probe:IsA("Model") then return nil end
    local meshFolder = probe:FindFirstChild("mesh")
    if not meshFolder then return nil end
    for _, child in ipairs(meshFolder:GetChildren()) do
        if child:IsA("MeshPart") and child.Name:find("Tower Probe_Cylinder") then return child end
    end
    for _, child in ipairs(meshFolder:GetChildren()) do
        if child:IsA("MeshPart") then return child end
    end
    for _, child in ipairs(meshFolder:GetChildren()) do
        if child:IsA("BasePart") then
            local ok, pos = pcall(function() return child.Position end)
            if ok and pos then return child end
        end
    end
    return nil
end

-- =============================================
-- SCAN FUNCTIONS
-- =============================================

local function scanTornadoes()
    local sr = workspace:FindFirstChild("storm_related")
    local storms = sr and sr:FindFirstChild("storms")
    if not storms then return end

    local alive = {}
    for _, storm in ipairs(storms:GetChildren()) do
        if storm:IsA("Model") then
            local rot = storm:FindFirstChild("rotation")
            local ts  = rot and rot:FindFirstChild("tornado_scan")
            if ts and ts:IsA("BasePart") then
                local key = storm.Name
                alive[key] = true
                if tornadoData[key] then
                    tornadoData[key].part       = ts
                    tornadoData[key].stormModel = storm
                else
                    tornadoData[key] = { part = ts, stormModel = storm }
                end
            end
        end
    end

    for key in pairs(tornadoData) do
        if not alive[key] then
            prevPos[key] = nil; prevTime[key] = nil
            moveVec[key] = nil; speedBufs[key] = nil; sizeCache[key] = nil
            removeEntry(key)
            activeKeys.tornado[key] = nil
            tornadoData[key] = nil
        end
    end
end

function scanProbes()
    local pr    = workspace:FindFirstChild("player_related")
    local pfold = pr and pr:FindFirstChild("probes")
    if not pfold then return end

    local liveSet = {}
    for _, probe in ipairs(pfold:GetChildren()) do
        if probe:IsA("Model") then
            local isMine = (probe.Name == myUserId)
                or (myUserId and probe.Name:find(myUserId, 1, true))
            if isMine then liveSet[probe] = true end
        end
    end

    for key, data in pairs(probeData) do
        if not liveSet[data.part] then
            removeEntry(key)
            activeKeys.probe[key] = nil
            probeData[key] = nil
        end
    end

    for probe in pairs(liveSet) do
        local exists = false
        for _, data in pairs(probeData) do
            if data.part == probe then exists = true; break end
        end
        if not exists then
            local part = findProbePart(probe)
            if part then
                probeCounter = probeCounter + 1
                local key = probe.Name .. "_" .. probeCounter
                probeData[key] = { part = probe, realPart = part }
                printl("[ProbeESP] Added: " .. key)
            end
        end
    end
end

-- =============================================
-- ESP UPDATE FUNCTIONS
-- =============================================

local TORNADO_BOX_SKIP = 3

local function updateTornadoEsp(playerPos)
    if not FeatureConfig.TornadoESP.Visible then
        for key in pairs(activeKeys.tornado) do
            hideEntry(espPool[key])
        end
        activeKeys.tornado = {}
        return
    end

    local seen = {}
    local cfg  = FeatureConfig.Tornado

    for key, data in pairs(tornadoData) do
        local part = data.part
        if not part or not part.Parent then
            prevPos[key] = nil; prevTime[key] = nil
            moveVec[key] = nil; speedBufs[key] = nil; sizeCache[key] = nil
        else
            local ok, pos = pcall(function() return part.Position end)
            if not ok or not pos then continue end

            sampleSpeed(key, pos)
            
            local scr, onScr = toScreen(pos)
            if not scr or not onScr then
                local entry = espPool[key]
                if entry then hideEntry(entry) end
                continue
            end

            seen[key]               = true
            activeKeys.tornado[key] = true
            local entry = getPoolEntry(key, true, true)

            if cfg.ShowBox and (frameCount % TORNADO_BOX_SKIP == 0) then
                if not sizeCache[key] then
                    local ok2, sz = pcall(function() return part.Size end)
                    sizeCache[key] = ok2 and sz or Vector3.new(60, 120, 60)
                end
                local sz = sizeCache[key]
                
                local tSc, tOn = toScreen(pos + Vector3.new(0,  sz.Y/2, 0))
                local bSc, bOn = toScreen(pos - Vector3.new(0,  sz.Y/2, 0))
                local lSc, lOn = toScreen(pos - Vector3.new(sz.X/2, 0, 0))
                local rSc, rOn = toScreen(pos + Vector3.new(sz.X/2, 0, 0))
                
                local h, w, boxY
                if tSc and bSc and lSc and rSc and tOn and bOn and lOn and rOn then
                    h    = math.max(math.abs(tSc.Y - bSc.Y), 20)
                    w    = math.max(math.abs(rSc.X - lSc.X), 20)
                    boxY = tSc.Y
                else
                    h = 120; w = 60; boxY = scr.Y - 60
                end
                entry.box.Size     = Vector2.new(w, h)
                entry.box.Position = Vector2.new(scr.X - w/2, boxY)
                entry.box.Color    = cfg.BoxColor
                entry.box.Visible  = true
            elseif not cfg.ShowBox then
                entry.box.Visible = false
            end

            local wind = readWindAttr(data.stormModel) or getSpeed(key)
            local dist = (playerPos - pos).Magnitude
            entry.label.Text     = string.format("TORNADO [%dm] | %.1f mph", math.floor(dist), wind)
            entry.label.Position = Vector2.new(scr.X, scr.Y - 46)
            entry.label.Color    = cfg.TextColor
            entry.label.Visible  = true

            local dir = getDir(key, pos)
            if dir and (cfg.ShowLine or cfg.ShowCircle) then
                local tgt = pos + Vector3.new(dir.X*1000, dir.Y*500, dir.Z*1000)
                local tScr, tOn2 = toScreen(tgt)
                if tScr and tOn2 then
                    if cfg.ShowCircle then
                        entry.circle.Position = Vector2.new(tScr.X, tScr.Y)
                        entry.circle.Color    = cfg.CircleColor
                        entry.circle.Visible  = true
                    else
                        entry.circle.Visible = false
                    end
                    if cfg.ShowLine then
                        entry.line.From    = Vector2.new(scr.X, scr.Y)
                        entry.line.To      = Vector2.new(tScr.X, tScr.Y)
                        entry.line.Color   = cfg.LineColor
                        entry.line.Visible = true
                    else
                        entry.line.Visible = false
                    end
                    continue
                end
            end
            if entry.circle then entry.circle.Visible = false end
            if entry.line   then entry.line.Visible   = false end
        end
    end

    cleanupBucket(activeKeys.tornado, seen)
end

function updateProbeEsp(playerPos)
    if not FeatureConfig.ProbeESP.Visible then
        for key in pairs(activeKeys.probe) do
            hideEntry(espPool[key])
        end
        activeKeys.probe = {}
        return
    end

    local seen = {}
    local cfg  = FeatureConfig.Probe

    for key, data in pairs(probeData) do
        local realPart = data.realPart

        if not realPart or not realPart.Parent then
            if data.part and data.part.Parent then
                realPart = findProbePart(data.part)
                if realPart then
                    data.realPart = realPart
                else
                    local entry = espPool[key]
                    if entry then hideEntry(entry) end
                    continue
                end
            else
                local entry = espPool[key]
                if entry then hideEntry(entry) end
                continue
            end
        end

        local ok, pos = pcall(function() return realPart.Position end)
        if not ok or not pos then continue end

        -- CORREGIDO: Verificar que scr no sea nil
        local scr, onScr = toScreen(pos)
        if not scr or not onScr then
            local entry = espPool[key]
            if entry then hideEntry(entry) end
            continue
        end

        seen[key]             = true
        activeKeys.probe[key] = true
        local entry = getPoolEntry(key, false, false)

        local dist    = (playerPos - pos).Magnitude
        local scale   = math.clamp(1000 / dist, 0.3, 2)
        local boxSize = math.floor(50 * scale)

        entry.box.Size     = Vector2.new(boxSize, boxSize)
        entry.box.Position = Vector2.new(scr.X - boxSize/2, scr.Y - boxSize/2)
        entry.box.Color    = cfg.BoxColor
        entry.box.Visible  = true

        entry.label.Text     = string.format("PROBE [%dm]", math.floor(dist))
        entry.label.Position = Vector2.new(scr.X, scr.Y - boxSize/2 - 15)
        entry.label.Color    = cfg.TextColor
        entry.label.Visible  = true
    end

    cleanupBucket(activeKeys.probe, seen)
end

-- =============================================
-- COLOR SYNC
-- =============================================

local function syncTornadoColors()
    local cfg = FeatureConfig.Tornado
    for key in pairs(tornadoData) do
        local e = espPool[key]
        if e then
            if e.box    then e.box.Color    = cfg.BoxColor    end
            if e.line   then e.line.Color   = cfg.LineColor   end
            if e.circle then e.circle.Color = cfg.CircleColor end
            if e.label  then e.label.Color  = cfg.TextColor   end
        end
    end
end

local function syncProbeColors()
    local cfg = FeatureConfig.Probe
    for key in pairs(probeData) do
        local e = espPool[key]
        if e then
            if e.box   then e.box.Color   = cfg.BoxColor  end
            if e.label then e.label.Color = cfg.TextColor end
        end
    end
end

-- =============================================
-- TWEEN
-- =============================================

local tweenActive = false
local tweenConn   = nil

local function cancelTween()
    tweenActive = false
    if tweenConn then tweenConn:Disconnect(); tweenConn = nil end
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end) end
end

local function tweenToTarget(targetPos)
    if tweenActive then cancelTween() end
    tweenActive = true
    tweenConn = RunService.Heartbeat:Connect(function()
        if not tweenActive then
            if tweenConn then tweenConn:Disconnect(); tweenConn = nil end
            return
        end
        local char = LocalPlayer.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then cancelTween(); return end
        local diff = targetPos - hrp.Position
        if diff.Magnitude < 10 then
            pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
            cancelTween()
            notify("Arrived!", "", 2)
            return
        end
        local speed = FeatureConfig.Tween.Speed
        local hMult = FeatureConfig.Tween.Height
        local dir   = diff.Unit
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.new(
                dir.X * speed,
                dir.Y * speed * hMult,
                dir.Z * speed
            )
        end)
    end)
end

local function goToNearestTornado()
    if tweenActive then cancelTween(); notify("Cancelled", "", 2); return end
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then notify("No character", "", 2); return end
    local pp = hrp.Position
    local bestDist, bestPos = math.huge, nil
    for key, data in pairs(tornadoData) do
        if data.part and data.part.Parent then
            local ok, pos = pcall(function() return data.part.Position end)
            if ok and pos then
                local d = (pp - pos).Magnitude
                if d < bestDist then bestDist = d; bestPos = pos end
            end
        end
    end
    if not bestPos then notify("No tornado found", "", 2); return end
    local dx, dz = pp.X - bestPos.X, pp.Z - bestPos.Z
    local hMag   = math.sqrt(dx*dx + dz*dz)
    local off    = FeatureConfig.Tween.Offset
    local target = hMag > 0
        and Vector3.new(bestPos.X + dx/hMag*off, bestPos.Y, bestPos.Z + dz/hMag*off)
        or  bestPos + Vector3.new(off, 0, 0)
    notify("Going: " .. math.floor(bestDist) .. "m", "", 3)
    tweenToTarget(target)
end

-- =============================================
-- FREEZE
-- =============================================

local freeze = { chassis = nil, lockedCF = nil, active = false }

local function getPlayerChassis()
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local pr   = workspace:FindFirstChild("player_related")
    local cars  = pr and pr:FindFirstChild("cars")
    if not cars then return nil end
    local pp = hrp.Position
    for _, car in ipairs(cars:GetChildren()) do
        if car:IsA("Model") then
            local ch = car:FindFirstChild("chassis")
            if ch and ch:IsA("BasePart") then
                local ok, cp = pcall(function() return ch.Position end)
                if ok and cp and (cp - pp).Magnitude < 10 then return ch end
            end
        end
    end
    return nil
end

local function applyCarFreeze()
    if freeze.active then return end
    local ch = getPlayerChassis()
    if not ch then return end
    local ok, cf = pcall(function() return ch.CFrame end)
    if not ok then return end
    freeze.chassis  = ch
    freeze.lockedCF = cf
    freeze.active   = true
end

local function releaseCarFreeze()
    freeze.chassis  = nil
    freeze.lockedCF = nil
    freeze.active   = false
end

local function safeZeroVelocity(part)
    if not part or not part:IsA("BasePart") then return end
    pcall(function() part.AssemblyLinearVelocity  = Vector3.zero end)
    pcall(function() part.AssemblyAngularVelocity = Vector3.zero end)
    pcall(function() part.Velocity    = Vector3.zero end)
    pcall(function() part.RotVelocity = Vector3.zero end)
end

-- =============================================
-- SAVE / LOAD
-- =============================================

local function colorToStr(c)
    if not c then return "1.000,0.000,0.000" end
    return string.format("%.3f,%.3f,%.3f", c.R, c.G, c.B)
end

local function strToColor(s, default)
    if not s or type(s) ~= "string" then return default end
    local r, g, b = s:match("([%d%.]+),([%d%.]+),([%d%.]+)")
    if not r then return default end
    local nr, ng, nb = tonumber(r), tonumber(g), tonumber(b)
    if not nr or not ng or not nb then return default end
    return Color3.new(math.clamp(nr, 0, 1), math.clamp(ng, 0, 1), math.clamp(nb, 0, 1))
end

local function saveConfig()
    pcall(function() UI.SetValue("cfg_TornadoESP", FeatureConfig.TornadoESP.Visible and "1" or "0") end)
    pcall(function() UI.SetValue("cfg_ProbeESP", FeatureConfig.ProbeESP.Visible and "1" or "0") end)
    
    local t = FeatureConfig.Tornado
    pcall(function() UI.SetValue("cfg_T_Box", t.ShowBox and "1" or "0") end)
    pcall(function() UI.SetValue("cfg_T_Line", t.ShowLine and "1" or "0") end)
    pcall(function() UI.SetValue("cfg_T_Circle", t.ShowCircle and "1" or "0") end)
    
    pcall(function() UI.SetValue("cfg_T_BoxC", colorToStr(t.BoxColor)) end)
    pcall(function() UI.SetValue("cfg_T_LineC", colorToStr(t.LineColor)) end)
    pcall(function() UI.SetValue("cfg_T_CircleC", colorToStr(t.CircleColor)) end)
    pcall(function() UI.SetValue("cfg_T_TextC", colorToStr(t.TextColor)) end)
    
    local p = FeatureConfig.Probe
    pcall(function() UI.SetValue("cfg_P_BoxC", colorToStr(p.BoxColor)) end)
    pcall(function() UI.SetValue("cfg_P_TextC", colorToStr(p.TextColor)) end)
    
    pcall(function() UI.SetValue("cfg_TweenSpeed", tostring(FeatureConfig.Tween.Speed)) end)
    pcall(function() UI.SetValue("cfg_TweenHeight", tostring(FeatureConfig.Tween.Height)) end)
    pcall(function() UI.SetValue("cfg_TweenOffset", tostring(FeatureConfig.Tween.Offset)) end)
    
    notify("Config saved!", "", 3)
    printl("[Config] Saved successfully")
end

local function loadConfig()
    local function getBool(key, default)
        local success, v = pcall(function() return UI.GetValue(key) end)
        if not success or v == nil then return default end
        if v == "1" or v == 1 or v == true then return true end
        if v == "0" or v == 0 or v == false then return false end
        return default
    end
    
    local function getNum(key, default)
        local success, v = pcall(function() return UI.GetValue(key) end)
        if not success or not v then return default end
        local n = tonumber(v)
        return n or default
    end
    
    local function getStr(key, default)
        local success, v = pcall(function() return UI.GetValue(key) end)
        if not success or not v then return default end
        return tostring(v)
    end

    FeatureConfig.TornadoESP.Visible = getBool("cfg_TornadoESP", false)
    FeatureConfig.ProbeESP.Visible   = getBool("cfg_ProbeESP", false)
    
    local t = FeatureConfig.Tornado
    t.ShowBox    = getBool("cfg_T_Box", true)
    t.ShowLine   = getBool("cfg_T_Line", true)
    t.ShowCircle = getBool("cfg_T_Circle", true)
    
    t.BoxColor    = strToColor(getStr("cfg_T_BoxC", nil), Color3.new(1, 0, 0))
    t.LineColor   = strToColor(getStr("cfg_T_LineC", nil), Color3.new(1, 1, 0))
    t.CircleColor = strToColor(getStr("cfg_T_CircleC", nil), Color3.new(0, 1, 1))
    t.TextColor   = strToColor(getStr("cfg_T_TextC", nil), Color3.new(1, 0, 0))
    
    local p = FeatureConfig.Probe
    p.BoxColor  = strToColor(getStr("cfg_P_BoxC", nil), Color3.new(0, 1, 1))
    p.TextColor = strToColor(getStr("cfg_P_TextC", nil), Color3.new(0, 1, 1))
    
    FeatureConfig.Tween.Speed  = getNum("cfg_TweenSpeed", 120)
    FeatureConfig.Tween.Height = getNum("cfg_TweenHeight", 0.5)
    FeatureConfig.Tween.Offset = getNum("cfg_TweenOffset", 30)
    
    printl("[Config] Loaded successfully")
end

-- =============================================
-- UI
-- =============================================

local function BuildESP(Tab)
    local S = Tab:Section("ESP", "Left")
    S:Toggle("TornadoESP", "Tornado ESP", FeatureConfig.TornadoESP.Visible, function(state)
        FeatureConfig.TornadoESP.Visible = state
        notify(state and "Tornado ESP enabled" or "Tornado ESP disabled", "", 3)
        if not state then
            for key in pairs(activeKeys.tornado) do hideEntry(espPool[key]) end
        end
    end)
    S:Spacing()
    S:Toggle("ProbeESP", "Probe ESP", FeatureConfig.ProbeESP.Visible, function(state)
        FeatureConfig.ProbeESP.Visible = state
        notify(state and "Probe ESP enabled" or "Probe ESP disabled", "", 3)
        if state then
            scanProbes()
        else
            for key in pairs(activeKeys.probe) do hideEntry(espPool[key]) end
        end
    end)
    S:Spacing()
    S:Text("For fullbright, enable Custom Time = 12.00")
    S:Spacing()
    S:Button("Save Config", function() saveConfig() end)
end

local function BuildTornadoCustom(Tab)
    local S = Tab:Section("Tornado Customization", "Left")
    S:Toggle("TornadoBox", "Box", FeatureConfig.Tornado.ShowBox, function(state)
        FeatureConfig.Tornado.ShowBox = state
        if not state then
            for _, e in pairs(espPool) do if e.box then e.box.Visible = false end end
        end
    end)
    S:ColorPicker("TornadoBoxColor", FeatureConfig.Tornado.BoxColor.R, FeatureConfig.Tornado.BoxColor.G, FeatureConfig.Tornado.BoxColor.B, 1, function(c)
        FeatureConfig.Tornado.BoxColor = c; syncTornadoColors()
    end)
    S:Spacing()
    S:Toggle("TornadoLine", "Direction Line", FeatureConfig.Tornado.ShowLine, function(state)
        FeatureConfig.Tornado.ShowLine = state
        if not state then
            for _, e in pairs(espPool) do if e.line then e.line.Visible = false end end
        end
    end)
    S:ColorPicker("TornadoLineColor", FeatureConfig.Tornado.LineColor.R, FeatureConfig.Tornado.LineColor.G, FeatureConfig.Tornado.LineColor.B, 1, function(c)
        FeatureConfig.Tornado.LineColor = c; syncTornadoColors()
    end)
    S:Spacing()
    S:Toggle("TornadoCircle", "Direction Circle", FeatureConfig.Tornado.ShowCircle, function(state)
        FeatureConfig.Tornado.ShowCircle = state
        if not state then
            for _, e in pairs(espPool) do if e.circle then e.circle.Visible = false end end
        end
    end)
    S:ColorPicker("TornadoCircleColor", FeatureConfig.Tornado.CircleColor.R, FeatureConfig.Tornado.CircleColor.G, FeatureConfig.Tornado.CircleColor.B, 1, function(c)
        FeatureConfig.Tornado.CircleColor = c; syncTornadoColors()
    end)
    S:Spacing()
    S:Text("Name / Distance Label")
    S:ColorPicker("TornadoTextColor", FeatureConfig.Tornado.TextColor.R, FeatureConfig.Tornado.TextColor.G, FeatureConfig.Tornado.TextColor.B, 1, function(c)
        FeatureConfig.Tornado.TextColor = c; syncTornadoColors()
    end)
end

local function BuildProbeCustom(Tab)
    local S = Tab:Section("Probe Customization", "Right")
    S:Text("Box Color")
    S:ColorPicker("ProbeBoxColor", FeatureConfig.Probe.BoxColor.R, FeatureConfig.Probe.BoxColor.G, FeatureConfig.Probe.BoxColor.B, 1, function(c)
        FeatureConfig.Probe.BoxColor = c; syncProbeColors()
    end)
    S:Spacing()
    S:Text("Name / Distance Label Color")
    S:ColorPicker("ProbeTextColor", FeatureConfig.Probe.TextColor.R, FeatureConfig.Probe.TextColor.G, FeatureConfig.Probe.TextColor.B, 1, function(c)
        FeatureConfig.Probe.TextColor = c; syncProbeColors()
    end)
end

local function BuildTween(Tab)
    local S = Tab:Section("Tween to Tornado", "Right")
    S:Text("Fly fast to tornado position")
    S:Text("Press again while moving to cancel")
    S:Spacing()
    S:Text("Speed: 50=slow  120=normal  500=fast")
    S:SliderInt("TweenSpeed", "Speed (studs/s)", 50, 500, FeatureConfig.Tween.Speed, function(v)
        FeatureConfig.Tween.Speed = v
    end)
    S:Spacing()
    S:Text("Height: 0.1=ground  0.5=normal  2.0=high")
    S:SliderFloat("TweenHeight", "Height Multiplier", 0.1, 2.0, FeatureConfig.Tween.Height, "%.1f", function(v)
        FeatureConfig.Tween.Height = v
    end)
    S:Spacing()
    S:Text("Stop distance before center")
    S:SliderInt("TweenOffset", "Stop Distance (studs)", 10, 200, FeatureConfig.Tween.Offset, function(v)
        FeatureConfig.Tween.Offset = v
    end)
    S:Spacing()
    S:Button("Go to Nearest Tornado", function() goToNearestTornado() end)
end

local function BuildFreeze(Tab)
    local S = Tab:Section("Anti-Sling / Freeze", "Right")
    S:Text("Prevents being flung by the tornado")
    S:Spacing()
    S:Toggle("CarFreeze", "Car Freeze", false, function(state)
        FeatureConfig.CarFreeze.Enabled = state
        if state then applyCarFreeze() else releaseCarFreeze() end
        notify(state and "Car Freeze ON" or "Car Freeze OFF", "", 3)
    end)
    S:Spacing()
    S:Toggle("CharFreeze", "Character Freeze", false, function(state)
        FeatureConfig.CharacterFreeze.Enabled = state
        notify(state and "Character Freeze ON" or "Character Freeze OFF", "", 3)
    end)
    S:Spacing()
    S:Tip("Car Freeze locks chassis CFrame every frame. Tornado cannot move it.")
end

local function BuildDebug(Tab)
    local S = Tab:Section("Debug", "Left")
    S:Button("Active Tornadoes", function()
        local tornadoCount = 0
        for _ in pairs(tornadoData) do tornadoCount = tornadoCount + 1 end
        printl("[Debug] Tornadoes tracked: " .. tornadoCount)
        for key, data in pairs(tornadoData) do
            if data.part and data.part.Parent then
                local p    = data.part.Position
                local wind = readWindAttr(data.stormModel) or getSpeed(key)
                printl(string.format("  %s | %.0f,%.0f,%.0f | %.1f mph", key, p.X, p.Y, p.Z, wind))
            end
        end
    end)
    S:Spacing()
    S:Button("Clear All Probe ESPs", function()
        for key in pairs(probeData) do
            removeEntry(key)
            activeKeys.probe[key] = nil
        end
        probeData    = {}
        probeCounter = 0
        scanProbes()
        printl("[Debug] Probe ESPs cleared and rescanned")
    end)
    S:Spacing()
    S:Button("Active Probes", function()
        local count = 0
        for key, data in pairs(probeData) do
            if data.realPart and data.realPart.Parent then
                local p    = data.realPart.Position
                local char = LocalPlayer.Character
                local hrp  = char and char:FindFirstChild("HumanoidRootPart")
                local d    = hrp and (p - hrp.Position).Magnitude or 0
                printl(string.format("  %s | %.0fm", key, d))
                count = count + 1
            end
        end
        printl("[Debug] Total probes: " .. count)
    end)
end

-- =============================================
-- INIT
-- =============================================

local function InitTab()
    loadConfig()
    UI.AddTab("Storm Tracker", function(tab)
        BuildESP(tab)
        BuildTornadoCustom(tab)
        BuildProbeCustom(tab)
        BuildTween(tab)
        BuildFreeze(tab)
        BuildDebug(tab)
    end)
    FeatureConfig.CarFreeze.Enabled       = false
    FeatureConfig.CharacterFreeze.Enabled = false
end

InitTab()
printl("[Storm Tracker] Loaded")
task.wait(2)

-- =============================================
-- RENDER STEPPED — Freeze
-- =============================================

RunService.RenderStepped:Connect(function()
    if not isrbxactive() then return end

    if FeatureConfig.CarFreeze.Enabled then
        if freeze.active then
            local ch = freeze.chassis
            if ch and ch.Parent then
                pcall(function() ch.CFrame = freeze.lockedCF end)
                safeZeroVelocity(ch)
            else
                freeze.active = false
                applyCarFreeze()
            end
        else
            applyCarFreeze()
        end
    end

    if FeatureConfig.CharacterFreeze.Enabled then
        local char = LocalPlayer.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then safeZeroVelocity(hrp) end
    end
end)

-- =============================================
-- HEARTBEAT — ESP update
-- =============================================

RunService.Heartbeat:Connect(function()
    if not isrbxactive() then return end
    frameCount = frameCount + 1
    if frameCount % 2 == 0 then return end

    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local playerPos = hrp.Position

    updateTornadoEsp(playerPos)
    updateProbeEsp(playerPos)
end)

-- =============================================
-- SCAN LOOP
-- =============================================

task.spawn(function()
    while true do
        if isrbxactive() then
            scanTornadoes()
            scanProbes()
        end
        task.wait(0.2)
    end
end)
