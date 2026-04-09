-- =============================================
-- Storm Tracker — Tornado + Probe ESP + Freeze
-- Optimized build
-- =============================================

local RunService    = game:GetService("RunService")
local Players       = game:GetService("Players")
local LocalPlayer   = Players.LocalPlayer

-- =============================================
-- FEATURE TOGGLES  (all OFF by default)
-- =============================================

local FeatureConfig = {
    TornadoESP      = { Visible = false },
    ProbeESP        = { Visible = false },
    CarFreeze       = { Enabled = false },
    CharacterFreeze = { Enabled = false },
}

-- =============================================
-- ESP STORAGE
-- =============================================

local espObjects      = {}   -- tornado ESPs
local probeEspObjects = {}   -- probe ESPs

-- Movement / speed tracking (keyed by storm name)
local prevPos   = {}
local prevTime  = {}
local moveVec   = {}
local speedBufs = {}

-- Cached part sizes so we don't read .Size every frame
local partSizeCache = {}

local SPEED_BUF_MAX = 15
local SPEED_INTERVAL = 0.4

-- =============================================
-- FREEZE STATE
-- =============================================

local freeze = {
    chassis     = nil,   -- the chassis BasePart
    cf          = nil,   -- locked CFrame
    extraParts  = {},    -- other vehicle parts to zero out
}

-- =============================================
-- HELPERS
-- =============================================

local function safePos(part)
    if not part or not part.Parent then return nil end
    local ok, p = pcall(function() return part.Position end)
    return ok and p or nil
end

local function safeCF(part)
    if not part or not part.Parent then return nil end
    local ok, c = pcall(function() return part.CFrame end)
    return ok and c or nil
end

local function dist3(a, b)
    local d = a - b
    return math.sqrt(d.X*d.X + d.Y*d.Y + d.Z*d.Z)
end

local function dist2(a, b)
    local dx, dy = a.X-b.X, a.Y-b.Y
    return math.sqrt(dx*dx + dy*dy)
end

-- =============================================
-- CAR FREEZE (improved)
--
-- Strategy:
--   • Lock chassis CFrame to the position it was at when freeze was enabled.
--   • Zero AssemblyLinearVelocity + AssemblyAngularVelocity on chassis every frame.
--   • Also zero velocity on up to N largest sibling parts (body panels, etc.)
--     so the whole car stays put, not just the physics root.
--   • Runs on RenderStepped (every frame, ~60/s) for maximum responsiveness.
-- =============================================

local MAX_EXTRA_PARTS = 6  -- how many extra parts to zero besides chassis

local function buildExtraParts(vehicle, chassis)
    local list = {}
    local seen = {[chassis] = true}
    -- Collect large BaseParts (volume > 10) that are not wheels/suspension
    for _, obj in ipairs(vehicle:GetDescendants()) do
        if #list >= MAX_EXTRA_PARTS then break end
        if obj:IsA("BasePart") and not seen[obj] then
            local ok, sz = pcall(function() return obj.Size end)
            if ok and sz then
                local vol = sz.X * sz.Y * sz.Z
                local n   = obj.Name:lower()
                if vol > 10
                   and not n:find("wheel") and not n:find("tire")
                   and not n:find("suspension") and not n:find("axle") then
                    table.insert(list, obj)
                    seen[obj] = true
                end
            end
        end
    end
    return list
end

local function getPlayerVehicle()
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, nil end

    local pr   = workspace:FindFirstChild("player_related")
    local cars = pr and pr:FindFirstChild("cars")
    if not cars then return nil, nil end

    local playerPos = hrp.Position
    for _, car in ipairs(cars:GetChildren()) do
        if car:IsA("Model") then
            local ch = car:FindFirstChild("chassis")
            if ch and ch:IsA("BasePart") then
                local p = safePos(ch)
                if p and (p - playerPos).Magnitude < 10 then
                    return car, ch
                end
            end
        end
    end
    return nil, nil
end

local function tickFreeze()
    -- ── CAR FREEZE ──
    if FeatureConfig.CarFreeze.Enabled then
        -- Acquire chassis on first call
        if not freeze.chassis or not freeze.chassis.Parent then
            local veh, ch = getPlayerVehicle()
            if ch then
                local cf = safeCF(ch)
                if cf then
                    freeze.chassis    = ch
                    freeze.cf         = cf
                    freeze.extraParts = buildExtraParts(veh, ch)
                    printl("[Freeze] Locked " .. veh.Name
                        .. " (" .. #freeze.extraParts .. " extra parts)")
                end
            end
        else
            -- Lock chassis every frame
            pcall(function()
                local ch = freeze.chassis
                ch.CFrame                  = freeze.cf
                ch.AssemblyLinearVelocity  = Vector3.zero
                ch.AssemblyAngularVelocity = Vector3.zero
            end)
            -- Zero velocity on extra parts (don't lock their CFrame so
            -- doors/wheels can still animate, but they can't fly away)
            for _, part in ipairs(freeze.extraParts) do
                if part and part.Parent then
                    pcall(function()
                        part.AssemblyLinearVelocity  = Vector3.zero
                        part.AssemblyAngularVelocity = Vector3.zero
                    end)
                end
            end
        end
    else
        -- Release
        if freeze.chassis then
            freeze.chassis    = nil
            freeze.cf         = nil
            freeze.extraParts = {}
        end
    end

    -- ── CHARACTER FREEZE ──
    if FeatureConfig.CharacterFreeze.Enabled then
        local char = LocalPlayer.Character
        if char then
            local function zv(name)
                local p = char:FindFirstChild(name)
                if p and p:IsA("BasePart") then
                    pcall(function()
                        p.AssemblyLinearVelocity  = Vector3.zero
                        p.AssemblyAngularVelocity = Vector3.zero
                    end)
                end
            end
            zv("HumanoidRootPart")
            zv("UpperTorso")
            zv("Torso")
        end
    end
end

-- =============================================
-- DRAWING CREATORS
-- =============================================

local function newText(color, size)
    local t = Drawing.new("Text")
    t.Color = color; t.Size = size
    t.Center = true; t.Outline = true
    t.Visible = false; t.Text = ""
    return t
end

local function newSquare(color, thickness)
    local b = Drawing.new("Square")
    b.Color = color; b.Thickness = thickness
    b.Filled = false; b.Visible = false
    b.Size = Vector2.new(0,0); b.Position = Vector2.new(0,0)
    return b
end

local function newCircle(color, radius, filled)
    local c = Drawing.new("Circle")
    c.Color = color; c.Radius = radius
    c.Thickness = 2; c.NumSides = 32
    c.Filled = filled; c.Visible = false
    return c
end

local function newLine(color, thickness)
    local l = Drawing.new("Line")
    l.Color = color; l.Thickness = thickness
    l.Visible = false
    return l
end

-- =============================================
-- WIND SPEED
-- =============================================

local WIND_ATTRS = {"WindSpeed","windspeed","wind_speed","Speed","speed","Intensity","intensity","EF","EFRating"}

local function readWindAttr(stormModel)
    for _, obj in ipairs({stormModel, stormModel:FindFirstChild("rotation") or {}}) do
        if obj.GetAttribute then
            for _, a in ipairs(WIND_ATTRS) do
                local ok, v = pcall(function() return obj:GetAttribute(a) end)
                if ok and type(v)=="number" and v > 0 then
                    return v > 50 and v or v * 2.237  -- convert m/s→mph if small
                end
            end
        end
    end
    return nil
end

local function sampleSpeed(key, pos)
    local now = tick()
    if not speedBufs[key] then
        speedBufs[key] = {s={}, lp=pos, lt=now}; return
    end
    local b = speedBufs[key]
    local dt = now - b.lt
    if dt < SPEED_INTERVAL then return end
    local dx, dz = pos.X-b.lp.X, pos.Z-b.lp.Z
    local mph = math.sqrt(dx*dx+dz*dz) / dt * 0.627
    local s = b.s
    s[#s+1] = mph
    if #s > SPEED_BUF_MAX then table.remove(s,1) end
    b.lp = pos; b.lt = now
end

local function getSpeed(key)
    local b = speedBufs[key]
    if not b or #b.s == 0 then return 0 end
    local tw, ws = 0, 0
    for i, v in ipairs(b.s) do ws=ws+v*i; tw=tw+i end
    return ws/tw
end

-- =============================================
-- MOVEMENT DIRECTION (smoothed)
-- =============================================

local function getDir(key, pos)
    local now = tick()
    if not prevPos[key] then
        prevPos[key]=pos; prevTime[key]=now; return nil
    end
    local mov = pos - prevPos[key]
    local dt  = now - prevTime[key]
    prevPos[key]=pos; prevTime[key]=now

    local mag = math.sqrt(mov.X*mov.X + mov.Y*mov.Y + mov.Z*mov.Z)
    if dt > 0 and mag > 0.01 then
        local nd = mov / mag
        local old = moveVec[key]
        moveVec[key] = old
            and ((old*0.3 + nd*0.7).Unit)
            or  nd
    end
    return moveVec[key]
end

-- =============================================
-- TORNADO ESP — update
-- =============================================

local function hideTornado(e)
    e.text.Visible=false; e.box.Visible=false
    e.circle.Visible=false; e.line.Visible=false
end

local function updateTornado(key, entry, playerPos)
    if not FeatureConfig.TornadoESP.Visible then
        hideTornado(entry.esp); return
    end

    local part = entry.part
    if not part or not part.Parent then return end

    local pos = safePos(part)
    if not pos then hideTornado(entry.esp); return end

    sampleSpeed(key, pos)

    local scr, onScr = WorldToScreen(pos)
    if not onScr then hideTornado(entry.esp); return end

    local esp  = entry.esp
    local dist = dist3(playerPos, pos)

    -- Cache part size (doesn't change after spawn)
    if not partSizeCache[key] then
        local ok, sz = pcall(function() return part.Size end)
        partSizeCache[key] = ok and sz or Vector3.new(60, 120, 60)
    end
    local sz = partSizeCache[key]

    -- Project bounding box corners
    local tSc, tOn = WorldToScreen(pos + Vector3.new(0,   sz.Y/2, 0))
    local bSc, bOn = WorldToScreen(pos - Vector3.new(0,   sz.Y/2, 0))
    local lSc, lOn = WorldToScreen(pos - Vector3.new(sz.X/2, 0,  0))
    local rSc, rOn = WorldToScreen(pos + Vector3.new(sz.X/2, 0,  0))

    if tOn and bOn and lOn and rOn then
        local h = math.max(math.abs(tSc.Y - bSc.Y), 20)
        local w = math.max(math.abs(rSc.X - lSc.X), 20)
        esp.box.Size     = Vector2.new(w, h)
        esp.box.Position = Vector2.new(scr.X - w/2, tSc.Y)
    else
        esp.box.Size     = Vector2.new(60, 120)
        esp.box.Position = Vector2.new(scr.X-30, scr.Y-60)
    end
    esp.box.Visible = true

    -- Wind speed label
    local wind = readWindAttr(entry.stormModel) or getSpeed(key)
    esp.text.Text     = string.format("TORNADO [%dm] | %.1f mph", math.floor(dist), wind)
    esp.text.Position = Vector2.new(scr.X, scr.Y - 42)
    esp.text.Visible  = true

    -- Direction indicator
    local dir = getDir(key, pos)
    if dir then
        local tgt = pos + Vector3.new(dir.X*1000, dir.Y*500, dir.Z*1000)
        local tScr, tOn2 = WorldToScreen(tgt)
        if tOn2 then
            esp.circle.Position = Vector2.new(tScr.X, tScr.Y)
            esp.circle.Visible  = true
            esp.line.From    = Vector2.new(scr.X, scr.Y)
            esp.line.To      = Vector2.new(tScr.X, tScr.Y)
            esp.line.Visible = true
            return
        end
    end
    esp.circle.Visible = false
    esp.line.Visible   = false
end

-- =============================================
-- PROBE ESP — update
-- =============================================

local function hideProbe(e)
    e.box.Visible=false; e.text.Visible=false
end

local function updateProbe(entry, playerPos)
    if not FeatureConfig.ProbeESP.Visible then
        hideProbe(entry.esp); return
    end

    local part = entry.part
    if not part or not part.Parent then return end

    local pos = safePos(part)
    if not pos then hideProbe(entry.esp); return end

    local scr, onScr = WorldToScreen(pos)
    if not onScr then hideProbe(entry.esp); return end

    local esp  = entry.esp
    local dist = dist3(playerPos, pos)

    esp.box.Position  = Vector2.new(scr.X-25, scr.Y-25)
    esp.box.Visible   = true
    esp.text.Text     = string.format("PROBE [%dm]", math.floor(dist))
    esp.text.Position = Vector2.new(scr.X, scr.Y-35)
    esp.text.Visible  = true
end

-- =============================================
-- CLEANUP
-- =============================================

local function removeTornado(key)
    if not espObjects[key] then return end
    local e = espObjects[key].esp
    pcall(function()
        e.text:Remove(); e.box:Remove()
        e.circle:Remove(); e.line:Remove()
    end)
    espObjects[key]=nil; prevPos[key]=nil; prevTime[key]=nil
    moveVec[key]=nil; speedBufs[key]=nil; partSizeCache[key]=nil
end

local function removeProbe(key)
    if not probeEspObjects[key] then return end
    local e = probeEspObjects[key].esp
    pcall(function() e.box:Remove(); e.text:Remove() end)
    probeEspObjects[key] = nil
end

-- =============================================
-- SCAN TORNADOES
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
                if not espObjects[key] then
                    printl("[ESP] Tornado: " .. key)
                    espObjects[key] = {
                        part       = ts,
                        stormModel = storm,
                        esp = {
                            text   = newText(Color3.new(1,0,0), 18),
                            box    = newSquare(Color3.new(1,0,0), 1),
                            circle = newCircle(Color3.new(0,1,1), 10, true),
                            line   = newLine(Color3.new(1,1,0), 2),
                        }
                    }
                else
                    espObjects[key].part       = ts
                    espObjects[key].stormModel = storm
                end
            end
        end
    end
    for key in pairs(espObjects) do
        if not alive[key] then removeTornado(key) end
    end
end

-- =============================================
-- SCAN PROBES
-- Key = tostring(part) — guaranteed unique per instance
-- =============================================

local function findProbePart(probe)
    local mesh = probe:FindFirstChild("mesh")
    if mesh then
        local cam = mesh:FindFirstChild("CustomProbe360Cam")
        if cam then
            local p = cam:FindFirstChild("CustomProbe360CamScreen")
                   or cam:FindFirstChild("CustomProbe360CamPlastic")
                   or cam:FindFirstChildWhichIsA("BasePart", true)
            if p then return p end
        end
        local p = mesh:FindFirstChildWhichIsA("BasePart", true)
        if p then return p end
    end
    return probe:FindFirstChildWhichIsA("BasePart", true)
end

local function scanProbes()
    local pr    = workspace:FindFirstChild("player_related")
    local pfold = pr and pr:FindFirstChild("probes")
    if not pfold then return end

    local alive = {}
    for _, probe in ipairs(pfold:GetChildren()) do
        local part = findProbePart(probe)
        if part then
            local key = tostring(part)
            alive[key] = true
            if not probeEspObjects[key] then
                printl("[ESP] Probe: " .. probe.Name)
                probeEspObjects[key] = {
                    part = part,
                    esp  = {
                        box  = newSquare(Color3.new(0,1,1), 2),
                        text = newText(Color3.new(0,1,1), 16),
                    }
                }
                -- Set probe box size once
                probeEspObjects[key].esp.box.Size = Vector2.new(50,50)
            end
        end
    end
    for key in pairs(probeEspObjects) do
        if not alive[key] then removeProbe(key) end
    end
end

-- =============================================
-- UI
-- =============================================

local function BuildESP(Tab)
    local S = Tab:Section("ESP", "Left")

    S:Toggle("TornadoESP", "Tornado ESP", false, function(state)
        FeatureConfig.TornadoESP.Visible = state
        notify(state and "Tornado ESP enabled" or "Tornado ESP disabled", "", 3)
        if not state then for _, e in pairs(espObjects) do hideTornado(e.esp) end end
    end)

    S:Toggle("ProbeESP", "Probe ESP", false, function(state)
        FeatureConfig.ProbeESP.Visible = state
        notify(state and "Probe ESP enabled" or "Probe ESP disabled", "", 3)
        if not state then for _, e in pairs(probeEspObjects) do hideProbe(e.esp) end end
    end)
end

local function BuildFreeze(Tab)
    local S = Tab:Section("Anti-Sling / Freeze", "Right")

    S:Text("Prevents being flung by the tornado")
    S:Spacing()

    S:Toggle("CarFreeze", "Car Freeze", false, function(state)
        FeatureConfig.CarFreeze.Enabled = state
        if not state then
            freeze.chassis = nil; freeze.cf = nil; freeze.extraParts = {}
        end
        notify(state and "Car Freeze ON" or "Car Freeze OFF", "", 3)
    end)

    S:Spacing()

    S:Toggle("CharFreeze", "Character Freeze", false, function(state)
        FeatureConfig.CharacterFreeze.Enabled = state
        notify(state and "Character Freeze ON" or "Character Freeze OFF", "", 3)
    end)

    S:Spacing()
    S:Tip("Car Freeze locks CFrame + zeros velocity on chassis and body every frame.")
end

local function InitTab()
    UI.AddTab("Storm Tracker", function(tab)
        BuildESP(tab)
        BuildFreeze(tab)
    end)
    FeatureConfig.TornadoESP.Visible      = UI.GetValue("TornadoESP")  or false
    FeatureConfig.ProbeESP.Visible        = UI.GetValue("ProbeESP")    or false
    FeatureConfig.CarFreeze.Enabled       = UI.GetValue("CarFreeze")   or false
    FeatureConfig.CharacterFreeze.Enabled = UI.GetValue("CharFreeze")  or false
end

InitTab()

-- =============================================
-- RENDER LOOP  (RenderStepped — runs every frame)
-- All visual updates + freeze here for max smoothness
-- =============================================

printl("[Storm Tracker] Loaded")

wait(2)

local scanTimer = 0
local SCAN_INTERVAL = 0.5   -- scan workspace every 0.5s (not every frame)

RunService.RenderStepped:Connect(function(dt)
    if not isrbxactive() then return end

    -- Freeze runs every frame
    tickFreeze()

    -- Throttled workspace scan
    scanTimer = scanTimer + dt
    if scanTimer >= SCAN_INTERVAL then
        scanTimer = 0
        scanTornadoes()
        scanProbes()
    end

    -- Get player position once per frame
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local playerPos = hrp.Position

    -- Update tornado ESPs
    for key, entry in pairs(espObjects) do
        if entry.part and entry.part.Parent then
            updateTornado(key, entry, playerPos)
        else
            removeTornado(key)
        end
    end

    -- Update probe ESPs
    for key, entry in pairs(probeEspObjects) do
        if entry.part and entry.part.Parent then
            updateProbe(entry, playerPos)
        else
            removeProbe(key)
        end
    end
end)