-- =============================================
-- Storm Tracker — Tornado + Probe ESP + Freeze + Tween
-- Clean rewrite (no duplicates or corruption)
-- =============================================

local RunService  = game:GetService("RunService")
local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- =============================================
-- USERID FROM MEMORY
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
-- SAVE / LOAD
-- =============================================

local function colorToStr(c)
    return string.format("%.4f,%.4f,%.4f", c.R, c.G, c.B)
end

local function strToColor(s, default)
    if not s or type(s) ~= "string" then return default end
    local r, g, b = s:match("([^,]+),([^,]+),([^,]+)")
    if not r then return default end
    return Color3.new(tonumber(r) or 1, tonumber(g) or 0, tonumber(b) or 0)
end

local function saveConfig()
    UI.SetValue("cfg_TornadoESP",  FeatureConfig.TornadoESP.Visible and "1" or "0")
    UI.SetValue("cfg_ProbeESP",    FeatureConfig.ProbeESP.Visible    and "1" or "0")
    local t = FeatureConfig.Tornado
    UI.SetValue("cfg_T_Box",    t.ShowBox    and "1" or "0")
    UI.SetValue("cfg_T_Line",   t.ShowLine   and "1" or "0")
    UI.SetValue("cfg_T_Circle", t.ShowCircle and "1" or "0")
    UI.SetValue("cfg_T_BoxC",    colorToStr(t.BoxColor))
    UI.SetValue("cfg_T_LineC",   colorToStr(t.LineColor))
    UI.SetValue("cfg_T_CircleC", colorToStr(t.CircleColor))
    UI.SetValue("cfg_T_TextC",   colorToStr(t.TextColor))
    local p = FeatureConfig.Probe
    UI.SetValue("cfg_P_BoxC",  colorToStr(p.BoxColor))
    UI.SetValue("cfg_P_TextC", colorToStr(p.TextColor))
    UI.SetValue("cfg_TweenSpeed",  tostring(FeatureConfig.Tween.Speed))
    UI.SetValue("cfg_TweenHeight", tostring(FeatureConfig.Tween.Height))
    UI.SetValue("cfg_TweenOffset", tostring(FeatureConfig.Tween.Offset))
    notify("Config saved", "", 3)
    printl("[Config] Saved")
end

local function loadConfig()
    local function getBool(key, default)
        local v = UI.GetValue(key)
        if v == nil then return default end
        return v == "1" or v == true
    end
    local function getNum(key, default)
        return tonumber(UI.GetValue(key)) or default
    end
    FeatureConfig.TornadoESP.Visible = getBool("cfg_TornadoESP", false)
    FeatureConfig.ProbeESP.Visible   = getBool("cfg_ProbeESP",   false)
    local t = FeatureConfig.Tornado
    t.ShowBox    = getBool("cfg_T_Box",    true)
    t.ShowLine   = getBool("cfg_T_Line",   true)
    t.ShowCircle = getBool("cfg_T_Circle", true)
    t.BoxColor    = strToColor(UI.GetValue("cfg_T_BoxC"),    Color3.new(1,0,0))
    t.LineColor   = strToColor(UI.GetValue("cfg_T_LineC"),   Color3.new(1,1,0))
    t.CircleColor = strToColor(UI.GetValue("cfg_T_CircleC"), Color3.new(0,1,1))
    t.TextColor   = strToColor(UI.GetValue("cfg_T_TextC"),   Color3.new(1,0,0))
    local p = FeatureConfig.Probe
    p.BoxColor  = strToColor(UI.GetValue("cfg_P_BoxC"),  Color3.new(0,1,1))
    p.TextColor = strToColor(UI.GetValue("cfg_P_TextC"), Color3.new(0,1,1))
    FeatureConfig.Tween.Speed  = getNum("cfg_TweenSpeed",  120)
    FeatureConfig.Tween.Height = getNum("cfg_TweenHeight", 0.5)
    FeatureConfig.Tween.Offset = getNum("cfg_TweenOffset", 30)
    printl("[Config] Loaded")
end

-- =============================================
-- ESP STORAGE
-- =============================================

local tornadoESPs = {}
local probeESPs   = {}
local pendingProbes = {}
local probeCounter  = 0

local prevPos   = {}
local prevTime  = {}
local moveVec   = {}
local speedBufs = {}
local sizeCache = {}

local SPEED_BUF_MAX  = 10
local SPEED_INTERVAL = 0.5
local TORNADO_BOX_FRAMES = 3
local frameCount = 0

-- =============================================
-- DRAWING HELPERS
-- =============================================

local function newText(color, size)
    local t = Drawing.new("Text")
    t.Color = color; t.Size = size; t.Center = true
    t.Outline = true; t.Visible = false; t.Text = ""
    return t
end

local function newSquare(color, thickness)
    local b = Drawing.new("Square")
    b.Color = color; b.Thickness = thickness; b.Filled = false
    b.Visible = false; b.Size = Vector2.new(0, 0)
    b.Position = Vector2.new(0, 0)
    return b
end

local function newCircle(color, radius)
    local c = Drawing.new("Circle")
    c.Color = color; c.Radius = radius; c.Thickness = 2
    c.NumSides = 32; c.Filled = true; c.Visible = false
    return c
end

local function newLine(color, thickness)
    local l = Drawing.new("Line")
    l.Color = color; l.Thickness = thickness; l.Visible = false
    return l
end

-- =============================================
-- WIND / SPEED HELPERS
-- =============================================

local WIND_ATTRS = {"WindSpeed","windspeed","wind_speed","Speed","speed","Intensity","intensity","EF","EFRating"}

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
-- TORNADO ESP
-- =============================================

local function hideTornado(e)
    e.text.Visible = false; e.box.Visible = false
    e.circle.Visible = false; e.line.Visible = false
end

local function updateTornado(key, entry, playerPos, frame)
    if not FeatureConfig.TornadoESP.Visible then hideTornado(entry.esp); return end
    local part = entry.part
    if not part or not part.Parent then return end
    local ok, pos = pcall(function() return part.Position end)
    if not ok then hideTornado(entry.esp); return end

    sampleSpeed(key, pos)
    local scr, onScr = WorldToScreen(pos)
    if not onScr then hideTornado(entry.esp); return end

    local esp = entry.esp
    local cfg = FeatureConfig.Tornado
    local dist = (playerPos - pos).Magnitude

    -- Box (throttled)
    if not entry.lastBoxFrame or (frame - entry.lastBoxFrame) >= TORNADO_BOX_FRAMES then
        entry.lastBoxFrame = frame
        if not sizeCache[key] then
            local ok2, sz = pcall(function() return part.Size end)
            sizeCache[key] = ok2 and sz or Vector3.new(60, 120, 60)
        end
        local sz = sizeCache[key]
        if cfg.ShowBox then
            local tSc, tOn = WorldToScreen(pos + Vector3.new(0,  sz.Y/2, 0))
            local bSc, bOn = WorldToScreen(pos - Vector3.new(0,  sz.Y/2, 0))
            local lSc, lOn = WorldToScreen(pos - Vector3.new(sz.X/2, 0, 0))
            local rSc, rOn = WorldToScreen(pos + Vector3.new(sz.X/2, 0, 0))
            if tOn and bOn and lOn and rOn then
                local h = math.max(math.abs(tSc.Y - bSc.Y), 20)
                local w = math.max(math.abs(rSc.X - lSc.X), 20)
                esp.box.Size     = Vector2.new(w, h)
                esp.box.Position = Vector2.new(scr.X - w/2, tSc.Y)
            else
                esp.box.Size     = Vector2.new(60, 120)
                esp.box.Position = Vector2.new(scr.X - 30, scr.Y - 60)
            end
            esp.box.Visible = true
        else
            esp.box.Visible = false
        end
    end

    -- Label
    local wind = readWindAttr(entry.stormModel) or getSpeed(key)
    esp.text.Text     = string.format("TORNADO [%dm] | %.1f mph", math.floor(dist), wind)
    esp.text.Position = Vector2.new(scr.X, scr.Y - 42)
    esp.text.Visible  = true

    -- Direction line / circle
    local dir = getDir(key, pos)
    if dir and (cfg.ShowLine or cfg.ShowCircle) then
        local tgt = pos + Vector3.new(dir.X*1000, dir.Y*500, dir.Z*1000)
        local tScr, tOn2 = WorldToScreen(tgt)
        if tOn2 then
            esp.circle.Position = Vector2.new(tScr.X, tScr.Y)
            esp.circle.Visible  = cfg.ShowCircle
            esp.line.From       = Vector2.new(scr.X, scr.Y)
            esp.line.To         = Vector2.new(tScr.X, tScr.Y)
            esp.line.Visible    = cfg.ShowLine
            return
        end
    end
    esp.circle.Visible = false
    esp.line.Visible   = false
end

local function removeTornado(key)
    if not tornadoESPs[key] then return end
    local e = tornadoESPs[key].esp
    pcall(function() e.text:Remove(); e.box:Remove(); e.circle:Remove(); e.line:Remove() end)
    tornadoESPs[key] = nil
    prevPos[key]  = nil; prevTime[key]  = nil
    moveVec[key]  = nil; speedBufs[key] = nil; sizeCache[key] = nil
end

-- =============================================
-- PROBE ESP
-- =============================================

local function hideProbe(e)
    e.box.Visible = false; e.text.Visible = false
end

local function findProbePart(probe)
    if not probe:IsA("Model") then return nil end
    local meshFolder = probe:FindFirstChild("mesh")
    if not meshFolder then return nil end
    -- Prefer MeshPart with specific name
    for _, child in ipairs(meshFolder:GetChildren()) do
        if child:IsA("MeshPart") and child.Name:find("Tower Probe_Cylinder") then
            return child
        end
    end
    -- Any MeshPart
    for _, child in ipairs(meshFolder:GetChildren()) do
        if child:IsA("MeshPart") then return child end
    end
    -- Any BasePart with a valid Position
    for _, child in ipairs(meshFolder:GetChildren()) do
        if child:IsA("BasePart") then
            local ok, pos = pcall(function() return child.Position end)
            if ok and pos then return child end
        end
    end
    return nil
end

local function updateProbe(entry, playerPos)
    if not FeatureConfig.ProbeESP.Visible then hideProbe(entry.esp); return end

    local part = entry.realPart
    -- Retry if realPart is invalid
    if not part or not part.Parent then
        local probe = entry.part
        if probe and probe.Parent then
            part = findProbePart(probe)
            if part then entry.realPart = part end
        end
    end

    if not part or not part.Parent then hideProbe(entry.esp); return end

    local ok, pos = pcall(function() return part.Position end)
    if not ok or not pos then hideProbe(entry.esp); return end

    local scr, onScr = WorldToScreen(pos)
    if not onScr then hideProbe(entry.esp); return end

    local esp  = entry.esp
    local dist = (playerPos - pos).Magnitude
    local scale   = math.clamp(1000 / dist, 0.3, 2)
    local boxSize = math.floor(50 * scale)

    pcall(function()
        esp.box.Size     = Vector2.new(boxSize, boxSize)
        esp.box.Position = Vector2.new(scr.X - boxSize/2, scr.Y - boxSize/2)
        esp.box.Visible  = true
        esp.text.Text     = string.format("PROBE [%dm]", math.floor(dist))
        esp.text.Position = Vector2.new(scr.X, scr.Y - boxSize/2 - 15)
        esp.text.Visible  = true
    end)
end

local function removeProbe(key)
    if not probeESPs[key] then return end
    pcall(function()
        probeESPs[key].esp.box:Remove()
        probeESPs[key].esp.text:Remove()
    end)
    probeESPs[key] = nil
end

-- =============================================
-- COLOR SYNC
-- =============================================

local function syncTornadoColors()
    local cfg = FeatureConfig.Tornado
    for _, e in pairs(tornadoESPs) do
        e.esp.box.Color    = cfg.BoxColor
        e.esp.line.Color   = cfg.LineColor
        e.esp.circle.Color = cfg.CircleColor
        e.esp.text.Color   = cfg.TextColor
    end
end

local function syncProbeColors()
    local cfg = FeatureConfig.Probe
    for _, e in pairs(probeESPs) do
        e.esp.box.Color  = cfg.BoxColor
        e.esp.text.Color = cfg.TextColor
    end
end

-- =============================================
-- SCAN
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
                if not tornadoESPs[key] then
                    local cfg = FeatureConfig.Tornado
                    tornadoESPs[key] = {
                        part = ts, stormModel = storm, lastBoxFrame = 0,
                        esp = {
                            text   = newText(cfg.TextColor, 18),
                            box    = newSquare(cfg.BoxColor, 1),
                            circle = newCircle(cfg.CircleColor, 10),
                            line   = newLine(cfg.LineColor, 2),
                        }
                    }
                else
                    tornadoESPs[key].part       = ts
                    tornadoESPs[key].stormModel = storm
                end
            end
        end
    end
    for key in pairs(tornadoESPs) do
        if not alive[key] then removeTornado(key) end
    end
end

local function scanProbes()
    local pr    = workspace:FindFirstChild("player_related")
    local pfold = pr and pr:FindFirstChild("probes")
    if not pfold then return end

    for _, probe in ipairs(pfold:GetChildren()) do
        if probe:IsA("Model") then
            local isMine = (probe.Name == myUserId) or (myUserId and probe.Name:find(myUserId, 1, true))
            if isMine then
                -- Check if this probe already has an ESP assigned
                local existingKey = nil
                for key, entry in pairs(probeESPs) do
                    if entry.part == probe then existingKey = key; break end
                end

                if not existingKey then
                    local part = findProbePart(probe)
                    if part then
                        pendingProbes[probe] = nil
                        probeCounter = probeCounter + 1
                        local key = probe.Name .. "_" .. probeCounter
                        local cfg  = FeatureConfig.Probe
                        probeESPs[key] = {
                            part     = probe,
                            realPart = part,
                            esp = {
                                box  = newSquare(cfg.BoxColor, 2),
                                text = newText(cfg.TextColor, 16),
                            }
                        }
                        printl("[ProbeESP] Created ESP for probe key=" .. key)
                    else
                        pendingProbes[probe] = (pendingProbes[probe] or 0) + 1
                        if pendingProbes[probe] <= 10 then
                            printl("[ProbeESP] Part not ready, retry " .. pendingProbes[probe] .. "/10")
                        end
                    end
                end
            end
        end
    end

    -- Clean up orphaned pending probes
    for probe in pairs(pendingProbes) do
        if not probe.Parent then pendingProbes[probe] = nil end
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
    for _, entry in pairs(tornadoESPs) do
        if entry.part and entry.part.Parent then
            local ok, pos = pcall(function() return entry.part.Position end)
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
    local hasALV = pcall(function() return part.AssemblyLinearVelocity end)
    local hasAAV = pcall(function() return part.AssemblyAngularVelocity end)
    local hasV   = pcall(function() return part.Velocity end)
    local hasRV  = pcall(function() return part.RotVelocity end)
    if hasALV then pcall(function() part.AssemblyLinearVelocity  = Vector3.zero end) end
    if hasAAV then pcall(function() part.AssemblyAngularVelocity = Vector3.zero end) end
    if not hasALV and hasV  then pcall(function() part.Velocity    = Vector3.zero end) end
    if not hasAAV and hasRV then pcall(function() part.RotVelocity = Vector3.zero end) end
end

-- =============================================
-- UI
-- =============================================

local function BuildESP(Tab)
    local S = Tab:Section("ESP", "Left")
    S:Toggle("TornadoESP", "Tornado ESP", FeatureConfig.TornadoESP.Visible, function(state)
        FeatureConfig.TornadoESP.Visible = state
        notify(state and "Tornado ESP enabled" or "Tornado ESP disabled", "", 3)
        if not state then for _, e in pairs(tornadoESPs) do hideTornado(e.esp) end end
    end)
    S:Spacing()
    S:Toggle("ProbeESP", "Probe ESP", FeatureConfig.ProbeESP.Visible, function(state)
        FeatureConfig.ProbeESP.Visible = state
        notify(state and "Probe ESP enabled" or "Probe ESP disabled", "", 3)
        if not state then
            for _, e in pairs(probeESPs) do hideProbe(e.esp) end
        else
            scanProbes()
            for _, e in pairs(probeESPs) do
                pcall(function() e.esp.box.Visible = true; e.esp.text.Visible = true end)
            end
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
        if not state then for _, e in pairs(tornadoESPs) do e.esp.box.Visible = false end end
    end)
    S:ColorPicker("TornadoBoxColor", 1, 0, 0, 1, function(c)
        FeatureConfig.Tornado.BoxColor = c; syncTornadoColors()
    end)
    S:Spacing()
    S:Toggle("TornadoLine", "Direction Line", FeatureConfig.Tornado.ShowLine, function(state)
        FeatureConfig.Tornado.ShowLine = state
        if not state then for _, e in pairs(tornadoESPs) do e.esp.line.Visible = false end end
    end)
    S:ColorPicker("TornadoLineColor", 1, 1, 0, 1, function(c)
        FeatureConfig.Tornado.LineColor = c; syncTornadoColors()
    end)
    S:Spacing()
    S:Toggle("TornadoCircle", "Direction Circle", FeatureConfig.Tornado.ShowCircle, function(state)
        FeatureConfig.Tornado.ShowCircle = state
        if not state then for _, e in pairs(tornadoESPs) do e.esp.circle.Visible = false end end
    end)
    S:ColorPicker("TornadoCircleColor", 0, 1, 1, 1, function(c)
        FeatureConfig.Tornado.CircleColor = c; syncTornadoColors()
    end)
    S:Spacing()
    S:Text("Name / Distance Label")
    S:ColorPicker("TornadoTextColor", 1, 0, 0, 1, function(c)
        FeatureConfig.Tornado.TextColor = c; syncTornadoColors()
    end)
end

local function BuildProbeCustom(Tab)
    local S = Tab:Section("Probe Customization", "Right")
    S:Text("Box Color")
    S:ColorPicker("ProbeBoxColor", 0, 1, 1, 1, function(c)
        FeatureConfig.Probe.BoxColor = c; syncProbeColors()
    end)
    S:Spacing()
    S:Text("Name / Distance Label Color")
    S:ColorPicker("ProbeTextColor", 0, 1, 1, 1, function(c)
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
        local sr = workspace:FindFirstChild("storm_related")
        local storms = sr and sr:FindFirstChild("storms")
        if not storms then printl("[Debug] No storms"); return end
        printl("[Debug] Tornadoes: " .. #storms:GetChildren())
        for _, storm in ipairs(storms:GetChildren()) do
            if storm:IsA("Model") then
                local rot = storm:FindFirstChild("rotation")
                local ts  = rot and rot:FindFirstChild("tornado_scan")
                if ts then
                    local p    = ts.Position
                    local wind = readWindAttr(storm) or getSpeed(storm.Name)
                    printl(string.format("  %s | %.0f,%.0f,%.0f | %.1f mph", storm.Name, p.X, p.Y, p.Z, wind))
                end
            end
        end
    end)
    S:Spacing()
    S:Button("Clear All Probe ESPs", function()
        printl("[Debug] Clearing all probe ESPs...")
        for key, entry in pairs(probeESPs) do
            pcall(function() entry.esp.box:Remove(); entry.esp.text:Remove() end)
            probeESPs[key] = nil
        end
        probeCounter = 0
        scanProbes()
        printl("[Debug] Done. Rescanned.")
    end)
    S:Spacing()
    S:Button("Active Probes", function()
        local pr    = workspace:FindFirstChild("player_related")
        local pfold = pr and pr:FindFirstChild("probes")
        if not pfold then printl("[Debug] No probes"); return end
        local char = LocalPlayer.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        local count = 0
        printl("[Debug] Probes (userId: " .. myUserId .. "):")
        for _, probe in ipairs(pfold:GetChildren()) do
            if probe:IsA("Model") then
                local part = findProbePart(probe)
                if part and hrp then
                    local d = (part.Position - hrp.Position).Magnitude
                    local p = part.Position
                    local tag = (probe.Name == myUserId) and " [YOUR PROBE]" or ""
                    printl(string.format("  ID:%s | %.0f,%.0f,%.0f | %.0fm%s", probe.Name, p.X, p.Y, p.Z, d, tag))
                    if probe.Name == myUserId then count = count + 1 end
                end
            end
        end
        printl("[Debug] Your probes: " .. count)
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
-- HEARTBEAT — Update ESP
-- =============================================

RunService.Heartbeat:Connect(function()
    if not isrbxactive() then return end
    frameCount = frameCount + 1
    if frameCount % 2 == 0 then return end

    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local playerPos = hrp.Position

    -- Tornado ESP
    for key, entry in pairs(tornadoESPs) do
        if entry.part and entry.part.Parent then
            updateTornado(key, entry, playerPos, frameCount)
        else
            removeTornado(key)
        end
    end

    -- Probe ESP — update only, auto-loop handles add/remove
    for key, entry in pairs(probeESPs) do
        if entry.realPart and entry.realPart.Parent then
            updateProbe(entry, playerPos)
        end
    end
end)

-- =============================================
-- SCAN LOOP
-- =============================================

task.spawn(function()
    while true do
        if isrbxactive() then
            scanTornadoes()
        end
        task.wait(0.2)
    end
end)

-- =============================================
-- AUTO PROBE ESP — compare against pfold every 0.5s
-- =============================================

task.spawn(function()
    while true do
        task.wait(0.5)
        if not isrbxactive() then continue end

        local pr    = workspace:FindFirstChild("player_related")
        local pfold = pr and pr:FindFirstChild("probes")
        if not pfold then continue end

        -- Build set of probe objects currently in the folder that belong to me
        local liveSet = {}
        for _, probe in ipairs(pfold:GetChildren()) do
            if probe:IsA("Model") then
                local isMine = (probe.Name == myUserId)
                    or (myUserId and probe.Name:find(myUserId, 1, true))
                if isMine then liveSet[probe] = true end
            end
        end

        -- Remove ESPs whose probe is no longer in pfold
        local dead = {}
        for key, entry in pairs(probeESPs) do
            if not liveSet[entry.part] then
                table.insert(dead, key)
            end
        end
        for _, key in ipairs(dead) do
            printl("[ProbeESP] Removing ESP for probe no longer in folder: " .. key)
            removeProbe(key)
        end

        -- Create ESP for probes in pfold that don't have one yet
        for probe in pairs(liveSet) do
            local hasESP = false
            for _, entry in pairs(probeESPs) do
                if entry.part == probe then hasESP = true; break end
            end
            if not hasESP then
                local part = findProbePart(probe)
                if part then
                    probeCounter = probeCounter + 1
                    local key = probe.Name .. "_" .. probeCounter
                    local cfg = FeatureConfig.Probe
                    probeESPs[key] = {
                        part     = probe,
                        realPart = part,
                        esp = {
                            box  = newSquare(cfg.BoxColor, 2),
                            text = newText(cfg.TextColor, 16),
                        }
                    }
                    printl("[ProbeESP] Auto-created ESP: " .. key)
                end
                -- If part is nil, probe just appeared and its children haven't
                -- loaded yet — will retry automatically on the next tick (0.5s)
            end
        end
    end
end)
