local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local findProbePart, scanProbes, updateProbeEsp

local myUserId = "0"
pcall(function()
    local base = getbase()
    local dm = memory_read("uintptr_t", memory_read("uintptr_t", base + 0x7B991D8) + 0x1D0)
    local function getChild(parent, name)
        local ptr = memory_read("uintptr_t", parent + 0x78)
        if ptr == 0 then return nil end
        local s, e = memory_read("uintptr_t", ptr), memory_read("uintptr_t", ptr + 0x8)
        for i = 0, (e - s) / 8 - 1 do
            local c = memory_read("uintptr_t", s + i * 8)
            if memory_read("string", memory_read("uintptr_t", c + 0xB0)) == name then return c end
        end
    end
    local lp = memory_read("uintptr_t", getChild(dm, "Players") + 0x130)
    local userId = memory_read("uintptr_t", lp + 0x2C8)
    myUserId = tostring(userId)
end)
print("[Storm Tracker] UserId:", myUserId)

local cfg = {
    TornadoESP      = { Visible = false },
    ProbeESP        = { Visible = false },
    CarFreeze       = { Enabled = false },
    CharacterFreeze = { Enabled = false },
    CarBoost        = { Enabled = false, Force = 50000 },
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

local espPool    = {}
local activeKeys = { tornado = {}, probe = {} }

local function getPoolEntry(key, withCircle, withLine)
    if espPool[key] then return espPool[key] end
    local entry = {}

    local isProbe    = not withCircle and not withLine
    local boxColor   = isProbe and cfg.Probe.BoxColor   or cfg.Tornado.BoxColor
    local labelColor = isProbe and cfg.Probe.TextColor  or cfg.Tornado.TextColor

    local box = Drawing.new("Square")
    box.Filled       = false
    box.Thickness    = 1
    box.Transparency = 1
    box.Color        = boxColor
    box.Visible      = false
    entry.box        = box

    local label = Drawing.new("Text")
    label.Center       = true
    label.Outline      = true
    label.Font         = 2
    label.Size         = 14
    label.Transparency = 1
    label.Color        = labelColor
    label.Visible      = false
    entry.label        = label

    if withCircle then
        local circle = Drawing.new("Circle")
        circle.Radius       = 10
        circle.Thickness    = 2
        circle.NumSides     = 32
        circle.Filled       = true
        circle.Transparency = 1
        circle.Color        = cfg.Tornado.CircleColor
        circle.Visible      = false
        entry.circle        = circle
    end

    if withLine then
        local line = Drawing.new("Line")
        line.Thickness    = 2
        line.Transparency = 1
        line.Color        = cfg.Tornado.LineColor
        line.Visible      = false
        entry.line        = line
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

local function toScreen(pos)
    if not pos then return nil, false end
    if type(WorldToScreen) == "function" then
        local ok, scr, on = pcall(WorldToScreen, pos)
        if ok and scr then return scr, on end
    end
    local cam = workspace.CurrentCamera
    if cam then
        local ok, v, vis = pcall(function() return cam:WorldToViewportPoint(pos) end)
        if ok and v then return Vector2.new(v.X, v.Y), vis end
    end
    return nil, false
end

local WIND_ATTRS = { "WindSpeed", "windspeed", "wind_speed", "Speed", "speed", "Intensity", "intensity", "EF", "EFRating" }
local prevPos    = {}
local prevTime   = {}
local moveVec    = {}
local speedBufs  = {}
local sizeCache  = {}

local function readWindAttr(storm)
    local targets = { storm, storm:FindFirstChild("rotation") }
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
    if not speedBufs[key] then speedBufs[key] = { s = {}, lp = pos, lt = now }; return end
    local b  = speedBufs[key]
    local dt = now - b.lt
    if dt < 0.5 then return end
    local dx, dz = pos.X - b.lp.X, pos.Z - b.lp.Z
    local mph    = math.sqrt(dx * dx + dz * dz) / dt * 0.627
    local s      = b.s
    s[#s + 1]    = mph
    if #s > 10 then table.remove(s, 1) end
    b.lp = pos
    b.lt = now
end

local function getSpeed(key)
    local b = speedBufs[key]
    if not b or #b.s == 0 then return 0 end
    local tw, ws = 0, 0
    for i, v in ipairs(b.s) do ws = ws + v * i; tw = tw + i end
    return ws / tw
end

local function getDir(key, pos)
    local now = tick()
    if not prevPos[key] then prevPos[key] = pos; prevTime[key] = now; return nil end
    local mov = pos - prevPos[key]
    local dt  = now - prevTime[key]
    prevPos[key]  = pos
    prevTime[key] = now
    local mag = mov.Magnitude
    if dt > 0 and mag > 0.01 then
        local nd  = mov / mag
        local old = moveVec[key]
        moveVec[key] = old and (old * 0.3 + nd * 0.7).Unit or nd
    end
    return moveVec[key]
end

local tornadoData  = {}
local probeData    = {}
local probeCounter = 0
local frameCount   = 0

function findProbePart(probe)
    if not probe or not probe:IsA("Model") then return nil end
    local mesh = probe:FindFirstChild("mesh")
    if not mesh then return nil end
    for _, child in ipairs(mesh:GetChildren()) do
        if child:IsA("MeshPart") and child.Name:find("Tower Probe_Cylinder") then return child end
    end
    for _, child in ipairs(mesh:GetChildren()) do
        if child:IsA("MeshPart") then return child end
    end
    for _, child in ipairs(mesh:GetChildren()) do
        if child:IsA("BasePart") then
            local ok, p = pcall(function() return child.Position end)
            if ok and p then return child end
        end
    end
    return nil
end

local function clearTornadoKey(key)
    prevPos[key]   = nil
    prevTime[key]  = nil
    moveVec[key]   = nil
    speedBufs[key] = nil
    sizeCache[key] = nil
    removeEntry(key)
    activeKeys.tornado[key] = nil
    tornadoData[key]        = nil
end

local function scanTornadoes()
    local sr     = workspace:FindFirstChild("storm_related")
    local storms = sr and sr:FindFirstChild("storms")

    if not storms then
        local dead = {}
        for key in pairs(tornadoData) do dead[#dead + 1] = key end
        for _, key in ipairs(dead) do clearTornadoKey(key) end
        return
    end

    local foundParts = {}
    for _, storm in ipairs(storms:GetChildren()) do
        if storm and storm:IsA("Model") then
            local rot = storm:FindFirstChild("rotation")
            local ts  = rot and rot:FindFirstChild("tornado_scan")
            if ts and ts:IsA("BasePart") then
                foundParts[ts] = storm
                if not tornadoData[ts] then
                    printl("[ScanTornadoes] New tornado: " .. storm.Name)
                    tornadoData[ts] = { part = ts, stormModel = storm }
                else
                    tornadoData[ts].stormModel = storm
                end
            end
        end
    end

    local dead = {}
    for key in pairs(tornadoData) do
        if not foundParts[key] or not key.Parent then
            dead[#dead + 1] = key
        end
    end
    for _, key in ipairs(dead) do clearTornadoKey(key) end
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

    local dead = {}
    for key, data in pairs(probeData) do
        if not liveSet[data.part] then dead[#dead + 1] = key end
    end
    for _, key in ipairs(dead) do
        removeEntry(key)
        activeKeys.probe[key] = nil
        probeData[key]        = nil
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
                local key    = probe.Name .. "_" .. probeCounter
                probeData[key] = { part = probe, realPart = part }
                printl("[ProbeESP] Added: " .. key)
            end
        end
    end
end

local function updateTornadoEsp(playerPos)
    if not cfg.TornadoESP.Visible then
        for key in pairs(activeKeys.tornado) do hideEntry(espPool[key]) end
        activeKeys.tornado = {}
        return
    end

    local seen = {}
    local tc   = cfg.Tornado

    for key, data in pairs(tornadoData) do
        local part = data.part
        if not part or not part.Parent then
            hideEntry(espPool[key])
        else
            local ok, pos = pcall(function() return part.Position end)
            if not ok or not pos then continue end

            sampleSpeed(key, pos)
            local scr, onScr = toScreen(pos)
            if not scr or not onScr then hideEntry(espPool[key]); continue end

            seen[key]               = true
            activeKeys.tornado[key] = true
            local entry = getPoolEntry(key, true, true)

            if entry.box    then entry.box.Color    = tc.BoxColor    end
            if entry.label  then entry.label.Color  = tc.TextColor   end
            if entry.circle then entry.circle.Color = tc.CircleColor end
            if entry.line   then entry.line.Color   = tc.LineColor   end

            if tc.ShowBox and (frameCount % 3 == 0) then
                if not sizeCache[key] then
                    local ok2, sz = pcall(function() return part.Size end)
                    sizeCache[key] = ok2 and sz or Vector3.new(60, 120, 60)
                end
                local sz = sizeCache[key]
                local tSc, tOn = toScreen(pos + Vector3.new(0, sz.Y / 2, 0))
                local bSc, bOn = toScreen(pos - Vector3.new(0, sz.Y / 2, 0))
                local lSc, lOn = toScreen(pos - Vector3.new(sz.X / 2, 0, 0))
                local rSc, rOn = toScreen(pos + Vector3.new(sz.X / 2, 0, 0))
                local h, w, boxY
                if tSc and bSc and lSc and rSc and tOn and bOn and lOn and rOn then
                    h    = math.max(math.abs(tSc.Y - bSc.Y), 20)
                    w    = math.max(math.abs(rSc.X - lSc.X), 20)
                    boxY = tSc.Y
                else
                    h = 120; w = 60; boxY = scr.Y - 60
                end
                entry.box.Size     = Vector2.new(w, h)
                entry.box.Position = Vector2.new(scr.X - w / 2, boxY)
                entry.box.Color    = tc.BoxColor
                entry.box.Visible  = true
            elseif not tc.ShowBox then
                entry.box.Visible = false
            end

            local wind = readWindAttr(data.stormModel) or getSpeed(key)
            local dist = (playerPos - pos).Magnitude
            entry.label.Text     = string.format("TORNADO [%dm] | %.1f mph", math.floor(dist), wind)
            entry.label.Position = Vector2.new(scr.X, scr.Y - 46)
            entry.label.Color    = tc.TextColor
            entry.label.Visible  = true

            local dir = getDir(key, pos)
            if dir and (tc.ShowLine or tc.ShowCircle) then
                local tgt         = pos + Vector3.new(dir.X * 1000, dir.Y * 500, dir.Z * 1000)
                local tScr, tOn2  = toScreen(tgt)
                if tScr and tOn2 then
                    if tc.ShowCircle then
                        entry.circle.Position = Vector2.new(tScr.X, tScr.Y)
                        entry.circle.Color    = tc.CircleColor
                        entry.circle.Visible  = true
                    else
                        entry.circle.Visible = false
                    end
                    if tc.ShowLine then
                        entry.line.From    = Vector2.new(scr.X, scr.Y)
                        entry.line.To      = Vector2.new(tScr.X, tScr.Y)
                        entry.line.Color   = tc.LineColor
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
    if not cfg.ProbeESP.Visible then
        for key in pairs(activeKeys.probe) do hideEntry(espPool[key]) end
        activeKeys.probe = {}
        return
    end

    local seen = {}
    local pc   = cfg.Probe

    for key, data in pairs(probeData) do
        local realPart = data.realPart
        if not realPart or not realPart.Parent then
            if data.part and data.part.Parent then
                realPart = findProbePart(data.part)
                if realPart then data.realPart = realPart
                else hideEntry(espPool[key]); continue end
            else
                hideEntry(espPool[key]); continue
            end
        end

        local ok, pos = pcall(function() return realPart.Position end)
        if not ok or not pos then continue end

        local scr, onScr = toScreen(pos)
        if not scr or not onScr then hideEntry(espPool[key]); continue end

        seen[key]             = true
        activeKeys.probe[key] = true
        local entry   = getPoolEntry(key, false, false)

        if entry.box   then entry.box.Color   = pc.BoxColor  end
        if entry.label then entry.label.Color = pc.TextColor end

        local dist    = (playerPos - pos).Magnitude
        local scale   = math.clamp(1000 / dist, 0.3, 2)
        local boxSize = math.floor(50 * scale)

        entry.box.Size     = Vector2.new(boxSize, boxSize)
        entry.box.Position = Vector2.new(scr.X - boxSize / 2, scr.Y - boxSize / 2)
        entry.box.Color    = pc.BoxColor
        entry.box.Visible  = true

        entry.label.Text     = string.format("PROBE [%dm]", math.floor(dist))
        entry.label.Position = Vector2.new(scr.X, scr.Y - boxSize / 2 - 15)
        entry.label.Color    = pc.TextColor
        entry.label.Visible  = true
    end

    cleanupBucket(activeKeys.probe, seen)
end

local function syncTornadoColors()
    local tc = cfg.Tornado
    for key in pairs(tornadoData) do
        local e = espPool[key]
        if e then
            if e.box    then e.box.Color    = tc.BoxColor    end
            if e.line   then e.line.Color   = tc.LineColor   end
            if e.circle then e.circle.Color = tc.CircleColor end
            if e.label  then e.label.Color  = tc.TextColor   end
        end
    end
end

local function syncProbeColors()
    local pc = cfg.Probe
    for key in pairs(probeData) do
        local e = espPool[key]
        if e then
            if e.box   then e.box.Color   = pc.BoxColor  end
            if e.label then e.label.Color = pc.TextColor end
        end
    end
end

local OFF_PRIMITIVE = 0x148
local OFF_CF        = 0xC0
local OFF_POS       = 0x24
local OFF_VEL       = 0xF0

local function readPrim(part)
    local ok, ptr = pcall(memory_read, "uintptr_t", part.Address + OFF_PRIMITIVE)
    if not ok or not ptr or ptr == 0 then return nil end
    return ptr
end

local function readPos(prim)
    local base = prim + OFF_CF + OFF_POS
    local ok1, x = pcall(memory_read, "float", base)
    local ok2, y = pcall(memory_read, "float", base + 0x4)
    local ok3, z = pcall(memory_read, "float", base + 0x8)
    if not ok1 or not ok2 or not ok3 then return nil end
    return Vector3.new(x, y, z)
end

local function writePos(prim, pos)
    local base = prim + OFF_CF + OFF_POS
    pcall(memory_write, "float", base,       pos.X)
    pcall(memory_write, "float", base + 0x4, pos.Y)
    pcall(memory_write, "float", base + 0x8, pos.Z)
end

local function zeroVel(prim)
    local base = prim + OFF_VEL
    pcall(memory_write, "float", base,       0)
    pcall(memory_write, "float", base + 0x4, 0)
    pcall(memory_write, "float", base + 0x8, 0)
end

local function writeVel(prim, vel)
    local base = prim + OFF_VEL
    pcall(memory_write, "float", base,       vel.X)
    pcall(memory_write, "float", base + 0x4, vel.Y)
    pcall(memory_write, "float", base + 0x8, vel.Z)
end

local function readVel(prim)
    local base = prim + OFF_VEL
    local ok1, x = pcall(memory_read, "float", base)
    local ok2, y = pcall(memory_read, "float", base + 0x4)
    local ok3, z = pcall(memory_read, "float", base + 0x8)
    if not ok1 or not ok2 or not ok3 then return nil end
    return Vector3.new(x, y, z)
end

local OFF_CF_ROT = 0xC0
local OFF_CF_POS = 0xE4

local function read_cframe(part)
    local ok, prim = pcall(memory_read, "uintptr_t", part.Address + 0x148)
    if not ok or not prim or prim == 0 then return nil end
    local rot = {}
    for i = 0, 8 do
        local okf, v = pcall(memory_read, "float", prim + OFF_CF_ROT + i * 4)
        rot[i + 1] = okf and v or 0
    end
    local ok1, px = pcall(memory_read, "float", prim + OFF_CF_POS)
    local ok2, py = pcall(memory_read, "float", prim + OFF_CF_POS + 0x4)
    local ok3, pz = pcall(memory_read, "float", prim + OFF_CF_POS + 0x8)
    if not ok1 or not ok2 or not ok3 then return nil end
    return { rot = rot, pos = Vector3.new(px, py, pz), prim = prim }
end

local function write_cframe(cf)
    if not cf or not cf.prim then return end
    if cf.rot then
        for i, v in ipairs(cf.rot) do
            pcall(memory_write, "float", cf.prim + OFF_CF_ROT + (i - 1) * 4, v)
        end
    end
    if cf.pos then
        pcall(memory_write, "float", cf.prim + OFF_CF_POS,       cf.pos.X)
        pcall(memory_write, "float", cf.prim + OFF_CF_POS + 0x4, cf.pos.Y)
        pcall(memory_write, "float", cf.prim + OFF_CF_POS + 0x8, cf.pos.Z)
    end
end

local function cancel_velocity_part(part)
    local ok, prim = pcall(memory_read, "uintptr_t", part.Address + 0x148)
    if not ok or not prim or prim == 0 then return end
    pcall(memory_write, "float", prim + 0xF0,       0)
    pcall(memory_write, "float", prim + 0xF0 + 0x4, 0)
    pcall(memory_write, "float", prim + 0xF0 + 0x8, 0)
end

local WORLD_OFF   = 0x408
local GRAVITY_OFF = 0x1D8

local function setGravity(g)
    pcall(function()
        local worldPtr = memory_read("uintptr_t", workspace.Address + WORLD_OFF)
        memory_write("float", worldPtr + GRAVITY_OFF, g)
    end)
end

local tweenActive = false
local tweenConn   = nil

local function cancelTween()
    tweenActive = false
    if tweenConn then tweenConn:Disconnect(); tweenConn = nil end
    setGravity(196.2)
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChild("Humanoid")
    if hrp then pcall(cancel_velocity_part, hrp) end
    if hum then pcall(function() hum.PlatformStand = false end) end
end

local function tweenToTarget(targetPos, isProbe)
    if tweenActive then cancelTween() end
    tweenActive = true
    setGravity(10)

    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local hum  = char and char:FindFirstChild("Humanoid")
    if not hrp then tweenActive = false; setGravity(196.2); return end

    if hum then pcall(function() hum.PlatformStand = true end) end

    local arrivalDist = isProbe and 5 or 10
    local decelDist   = isProbe and 30 or 40
    local minSpeed    = 12
    local startTime   = tick()
    local timeout     = 60

    task.spawn(function()
        while tweenActive do
            if tick() - startTime > timeout then cancelTween(); break end

            local c  = LocalPlayer.Character
            local rp = c and c:FindFirstChild("HumanoidRootPart")
            if not rp then cancelTween(); break end

            local curPos = rp.Position
            local dx     = targetPos.X - curPos.X
            local dz     = targetPos.Z - curPos.Z
            local hDist  = math.sqrt(dx * dx + dz * dz)

            if hDist < arrivalDist then
                if isProbe then
                    local prim = readPrim(rp)
                    if prim then writePos(prim, targetPos) end
                end
                pcall(function() rp.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end)
                cancelTween()
                notify("Arrived!", "", 2)
                break
            end

            local speed = cfg.Tween.Speed
            if hDist < decelDist then
                speed = math.max(speed * (hDist / decelDist), minSpeed)
            end

            local diff = targetPos - curPos
            local dir  = diff.Unit
            local vel  = Vector3.new(
                dir.X * speed,
                dir.Y * speed * cfg.Tween.Height,
                dir.Z * speed
            )

            pcall(function() rp.AssemblyLinearVelocity = vel end)

            task.wait(1 / 30)
        end
    end)
end

local function goToNearestTornado()
    if tweenActive then cancelTween(); notify("Cancelled", "", 2); return end
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then notify("No character", "", 2); return end
    local pp               = hrp.Position
    local bestDist, bestPos = math.huge, nil
    for _, data in pairs(tornadoData) do
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
    local hMag   = math.sqrt(dx * dx + dz * dz)
    local off    = cfg.Tween.Offset
    local target = hMag > 0
        and Vector3.new(bestPos.X + dx / hMag * off, bestPos.Y, bestPos.Z + dz / hMag * off)
        or  bestPos + Vector3.new(off, 0, 0)
    notify("Going: " .. math.floor(bestDist) .. "m", "", 3)
    tweenToTarget(target)
end

local function getMyProbesSorted(playerPos)
    local pr    = workspace:FindFirstChild("player_related")
    local pfold = pr and pr:FindFirstChild("probes")
    if not pfold then return {} end

    local list = {}
    for _, probe in ipairs(pfold:GetChildren()) do
        if probe:IsA("Model") then
            local isMine = (probe.Name == myUserId)
                or (myUserId ~= "0" and probe.Name:find(myUserId, 1, true))
            if isMine then
                local part = findProbePart(probe)
                if part and part.Parent then
                    local ok, pos = pcall(function() return part.Position end)
                    if ok and pos then
                        list[#list + 1] = {
                            pos  = pos,
                            dist = (playerPos - pos).Magnitude,
                            name = probe.Name,
                        }
                    end
                end
            end
        end
    end

    table.sort(list, function(a, b) return a.dist < b.dist end)
    return list
end

local function goToProbeByRank(rank)
    if tweenActive then cancelTween(); notify("Cancelled", "", 2); return end
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then notify("No character", "", 2); return end

    local list = getMyProbesSorted(hrp.Position)
    if #list == 0 then
        notify("No probes found for id: " .. myUserId, "", 3)
        return
    end

    local entry = list[math.min(rank, #list)]
    notify(string.format("Going to probe #%d | %.0fm", rank, entry.dist), "", 3)
    tweenToTarget(entry.pos, true)
end

local freeze = { chassis = nil, lockedPos = nil, prim = nil, active = false }

local function getPlayerChassis()
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local pr   = workspace:FindFirstChild("player_related")
    local cars = pr and pr:FindFirstChild("cars")
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
    local prim = readPrim(ch)
    if not prim then return end
    local pos = readPos(prim)
    if not pos then return end
    freeze.chassis   = ch
    freeze.lockedPos = pos
    freeze.prim      = prim
    freeze.active    = true
end

local function releaseCarFreeze()
    freeze.chassis   = nil
    freeze.lockedPos = nil
    freeze.prim      = nil
    freeze.active    = false
end

local function safeZeroVelocity(part)
    if not part or not part:IsA("BasePart") then return end
    local prim = readPrim(part)
    if prim then zeroVel(prim) end
end

local boost       = { chassis = nil, prim = nil }
local boostWidget = nil

local function getBoostChassis()
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, nil end
    local pr   = workspace:FindFirstChild("player_related")
    local cars = pr and pr:FindFirstChild("cars")
    if not cars then return nil, nil end
    local pp = hrp.Position
    for _, car in ipairs(cars:GetChildren()) do
        if car:IsA("Model") then
            local ch = car:FindFirstChild("chassis")
            if ch and ch:IsA("BasePart") then
                local ok, cp = pcall(function() return ch.Position end)
                if ok and cp and (cp - pp).Magnitude < 10 then
                    return ch, readPrim(ch)
                end
            end
        end
    end
    return nil, nil
end

local function applyCarBoost()
    local ch, prim = getBoostChassis()
    if not ch or not prim then return end
    boost.chassis = ch
    boost.prim    = prim

    local ok, lv = pcall(function() return ch.CFrame.LookVector end)
    if not ok or not lv then return end

    local curVel = readVel(prim)
    local vy     = curVel and curVel.Y or 0
    local speed  = cfg.CarBoost.Force * 0.016

    writeVel(prim, Vector3.new(lv.X * speed, vy, lv.Z * speed))
end

local function saveColor(prefix, color)
    if not color then return end
    pcall(function() UI.SetValue(prefix .. "R", tostring(color.R)) end)
    pcall(function() UI.SetValue(prefix .. "G", tostring(color.G)) end)
    pcall(function() UI.SetValue(prefix .. "B", tostring(color.B)) end)
end

local function loadColor(prefix, default)
    local ok1, r = pcall(function() return UI.GetValue(prefix .. "R") end)
    local ok2, g = pcall(function() return UI.GetValue(prefix .. "G") end)
    local ok3, b = pcall(function() return UI.GetValue(prefix .. "B") end)
    local nr     = ok1 and tonumber(r)
    local ng     = ok2 and tonumber(g)
    local nb     = ok3 and tonumber(b)
    if nr == nil then nr = default.R end
    if ng == nil then ng = default.G end
    if nb == nil then nb = default.B end
    return Color3.new(
        math.clamp(nr, 0, 1),
        math.clamp(ng, 0, 1),
        math.clamp(nb, 0, 1)
    )
end

local function saveConfig()
    local t = cfg.Tornado
    local p = cfg.Probe
    pcall(function() UI.SetValue("cfg_TornadoESP",  cfg.TornadoESP.Visible      and "1" or "0") end)
    pcall(function() UI.SetValue("cfg_ProbeESP",    cfg.ProbeESP.Visible        and "1" or "0") end)
    pcall(function() UI.SetValue("cfg_CarBoost",    cfg.CarBoost.Enabled        and "1" or "0") end)
    pcall(function() UI.SetValue("cfg_CarFreeze",   cfg.CarFreeze.Enabled       and "1" or "0") end)
    pcall(function() UI.SetValue("cfg_CharFreeze",  cfg.CharacterFreeze.Enabled and "1" or "0") end)
    pcall(function() UI.SetValue("cfg_T_Box",        t.ShowBox    and "1" or "0") end)
    pcall(function() UI.SetValue("cfg_T_Line",       t.ShowLine   and "1" or "0") end)
    pcall(function() UI.SetValue("cfg_T_Circle",     t.ShowCircle and "1" or "0") end)
    saveColor("cfg_TBoxC_",    t.BoxColor)
    saveColor("cfg_TLineC_",   t.LineColor)
    saveColor("cfg_TCircleC_", t.CircleColor)
    saveColor("cfg_TTextC_",   t.TextColor)
    saveColor("cfg_PBoxC_",    p.BoxColor)
    saveColor("cfg_PTextC_",   p.TextColor)
    pcall(function() UI.SetValue("cfg_TweenSpeed",  tostring(cfg.Tween.Speed))    end)
    pcall(function() UI.SetValue("cfg_TweenHeight", tostring(cfg.Tween.Height))   end)
    pcall(function() UI.SetValue("cfg_TweenOffset", tostring(cfg.Tween.Offset))   end)
    pcall(function() UI.SetValue("cfg_BoostForce",  tostring(cfg.CarBoost.Force)) end)
    notify("Config saved!", "", 3)
end

local function loadConfig()
    local function getBool(key, default)
        local ok, v = pcall(function() return UI.GetValue(key) end)
        if not ok or v == nil then return default end
        if v == "1" or v == 1 or v == true  then return true  end
        if v == "0" or v == 0 or v == false then return false end
        return default
    end
    local function getNum(key, default)
        local ok, v = pcall(function() return UI.GetValue(key) end)
        return (ok and tonumber(v)) or default
    end

    cfg.TornadoESP.Visible      = getBool("cfg_TornadoESP", false)
    cfg.ProbeESP.Visible        = getBool("cfg_ProbeESP",   false)
    cfg.CarBoost.Enabled        = getBool("cfg_CarBoost",   false)
    cfg.CarFreeze.Enabled       = getBool("cfg_CarFreeze",  false)
    cfg.CharacterFreeze.Enabled = getBool("cfg_CharFreeze", false)

    local t = cfg.Tornado
    t.ShowBox    = getBool("cfg_T_Box",    true)
    t.ShowLine   = getBool("cfg_T_Line",   true)
    t.ShowCircle = getBool("cfg_T_Circle", true)
    t.BoxColor    = loadColor("cfg_TBoxC_",    Color3.new(1, 0, 0))
    t.LineColor   = loadColor("cfg_TLineC_",   Color3.new(1, 1, 0))
    t.CircleColor = loadColor("cfg_TCircleC_", Color3.new(0, 1, 1))
    t.TextColor   = loadColor("cfg_TTextC_",   Color3.new(1, 0, 0))

    local p = cfg.Probe
    p.BoxColor  = loadColor("cfg_PBoxC_",  Color3.new(0, 1, 1))
    p.TextColor = loadColor("cfg_PTextC_", Color3.new(0, 1, 1))

    cfg.Tween.Speed    = getNum("cfg_TweenSpeed",  120)
    cfg.Tween.Height   = getNum("cfg_TweenHeight", 0.5)
    cfg.Tween.Offset   = getNum("cfg_TweenOffset", 30)
    cfg.CarBoost.Force = getNum("cfg_BoostForce",  50000)
end

local function BuildESP(Tab)
    local S = Tab:Section("ESP", "Left")
    S:Toggle("TornadoESP", "Tornado ESP", cfg.TornadoESP.Visible, function(state)
        cfg.TornadoESP.Visible = state
        notify(state and "Tornado ESP enabled" or "Tornado ESP disabled", "", 3)
        if state then
            scanTornadoes()
        else
            for key in pairs(activeKeys.tornado) do hideEntry(espPool[key]) end
        end
    end)
    S:Spacing()
    S:Toggle("ProbeESP", "Probe ESP", cfg.ProbeESP.Visible, function(state)
        cfg.ProbeESP.Visible = state
        notify(state and "Probe ESP enabled" or "Probe ESP disabled", "", 3)
        if state then scanProbes() else
            for key in pairs(activeKeys.probe) do hideEntry(espPool[key]) end
        end
    end)
    S:Spacing()
    S:Text("For fullbright, enable Custom Time = 12.00")
    S:Spacing()
    S:Button("Save Config", function() saveConfig() end)
end

local function BuildTornadoCustom(Tab)
    local t = cfg.Tornado
    local S = Tab:Section("Tornado Customization", "Left")
    S:Toggle("TornadoBox", "Box", t.ShowBox, function(state)
        t.ShowBox = state
        if not state then
            for _, e in pairs(espPool) do if e.box then e.box.Visible = false end end
        end
    end)
    S:ColorPicker("TornadoBoxColor", t.BoxColor.R, t.BoxColor.G, t.BoxColor.B, 1, function(c)
        t.BoxColor = c; syncTornadoColors()
    end)
    S:Spacing()
    S:Toggle("TornadoLine", "Direction Line", t.ShowLine, function(state)
        t.ShowLine = state
        if not state then
            for _, e in pairs(espPool) do if e.line then e.line.Visible = false end end
        end
    end)
    S:ColorPicker("TornadoLineColor", t.LineColor.R, t.LineColor.G, t.LineColor.B, 1, function(c)
        t.LineColor = c; syncTornadoColors()
    end)
    S:Spacing()
    S:Toggle("TornadoCircle", "Direction Circle", t.ShowCircle, function(state)
        t.ShowCircle = state
        if not state then
            for _, e in pairs(espPool) do if e.circle then e.circle.Visible = false end end
        end
    end)
    S:ColorPicker("TornadoCircleColor", t.CircleColor.R, t.CircleColor.G, t.CircleColor.B, 1, function(c)
        t.CircleColor = c; syncTornadoColors()
    end)
    S:Spacing()
    S:Text("Name / Distance Label")
    S:ColorPicker("TornadoTextColor", t.TextColor.R, t.TextColor.G, t.TextColor.B, 1, function(c)
        t.TextColor = c; syncTornadoColors()
    end)
end

local function BuildProbeCustom(Tab)
    local p = cfg.Probe
    local S = Tab:Section("Probe Customization", "Left")
    S:Text("Box Color")
    S:ColorPicker("ProbeBoxColor", p.BoxColor.R, p.BoxColor.G, p.BoxColor.B, 1, function(c)
        p.BoxColor = c; syncProbeColors()
    end)
    S:Spacing()
    S:Text("Name / Distance Label Color")
    S:ColorPicker("ProbeTextColor", p.TextColor.R, p.TextColor.G, p.TextColor.B, 1, function(c)
        p.TextColor = c; syncProbeColors()
    end)
end

local function BuildBoost(Tab)
    local S = Tab:Section("Car Boost", "Left")
    S:Text("Hold keybind to boost forward")
    S:Spacing()
    S:Toggle("boost_on", "Car Boost", false, function(state)
        cfg.CarBoost.Enabled = state
        notify(state and "Car Boost ON" or "Car Boost OFF", "", 2)
    end)
    boostWidget = S:Keybind("boost_kb", 0x05, "hold")
    boostWidget:AddToHotkey("Car Boost", "boost_on")
    S:Spacing()
    S:Text("5k=gentle  50k=normal  150k=rocket")
    S:SliderInt("boost_force", "Force Amount", 5000, 200000, cfg.CarBoost.Force, function(v)
        cfg.CarBoost.Force = v
    end)
    S:Spacing()
    S:Tip("Must be seated in the car.")
end

local function BuildTween(Tab)
    local S = Tab:Section("Tween to Tornado", "Right")
    S:Text("Fly fast to tornado position")
    S:Text("Press again while moving to cancel")
    S:Spacing()
    S:Text("Speed: 50=slow  120=normal  500=fast")
    S:SliderInt("TweenSpeed", "Speed (studs/s)", 50, 500, cfg.Tween.Speed, function(v)
        cfg.Tween.Speed = v
    end)
    S:Spacing()
    S:Text("Height: 0.1=ground  0.5=normal  2.0=high")
    S:SliderFloat("TweenHeight", "Height Multiplier", 0.1, 2.0, cfg.Tween.Height, "%.1f", function(v)
        cfg.Tween.Height = v
    end)
    S:Spacing()
    S:Text("Stop distance before center")
    S:SliderInt("TweenOffset", "Stop Distance (studs)", 10, 200, cfg.Tween.Offset, function(v)
        cfg.Tween.Offset = v
    end)
    S:Spacing()
    S:Button("Go to Nearest Tornado", function() goToNearestTornado() end)
end

local function BuildTweenProbe(Tab)
    local S = Tab:Section("Tween to Probe", "Right")
    S:Text("Your probes are named after your userId:")
    S:Text("id: " .. myUserId)
    S:Spacing()
    S:Text("Uses the same speed / height settings as tornado tween.")
    S:Spacing()
    S:Button("Go to Nearest Probe", function()
        if tweenActive then cancelTween(); notify("Cancelled", "", 2); return end
        local char = LocalPlayer.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local list = getMyProbesSorted(hrp.Position)
        if #list == 0 then notify("No probes found for id: " .. myUserId, "", 3); return end
        local entry = list[1]
        notify(string.format("Going to probe #1 | %.0fm", entry.dist), "", 3)
        tweenToTarget(entry.pos, true)
    end)
    S:Spacing()
    S:Button("Go to 2nd Closest Probe", function() goToProbeByRank(2) end)
    S:Spacing()
    S:Button("Go to 3rd Closest Probe", function() goToProbeByRank(3) end)
    S:Spacing()
    S:Button("List My Probes", function()
        local char = LocalPlayer.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then printl("[Probes] No character"); return end
        local list = getMyProbesSorted(hrp.Position)
        if #list == 0 then
            printl("[Probes] No probes found for userId: " .. myUserId)
            return
        end
        printl(string.format("[Probes] Found %d probe(s) for userId %s:", #list, myUserId))
        for i, entry in ipairs(list) do
            local p = entry.pos
            printl(string.format("  #%d | %.0fm away | %.0f, %.0f, %.0f",
                i, entry.dist, p.X, p.Y, p.Z))
        end
    end)
end

local function BuildFreeze(Tab)
    local S = Tab:Section("Anti-Sling / Freeze", "Right")
    S:Text("Prevents being flung by the tornado")
    S:Spacing()
    S:Toggle("CarFreeze", "Car Freeze", false, function(state)
        cfg.CarFreeze.Enabled = state
        if state then applyCarFreeze() else releaseCarFreeze() end
        notify(state and "Car Freeze ON" or "Car Freeze OFF", "", 3)
    end)
    S:Spacing()
    S:Toggle("CharFreeze", "Character Freeze", false, function(state)
        cfg.CharacterFreeze.Enabled = state
        notify(state and "Character Freeze ON" or "Character Freeze OFF", "", 3)
    end)
    S:Spacing()
    S:Tip("Car Freeze locks chassis CFrame every frame. Tornado cannot move it.")
end

local function BuildDebug(Tab)
    local S = Tab:Section("Debug", "Left")
    S:Button("Rescan Tornadoes", function()
        local before = 0
        for _ in pairs(tornadoData) do before = before + 1 end
        scanTornadoes()
        local after = 0
        for _ in pairs(tornadoData) do after = after + 1 end
        printl(string.format("[Debug] Rescan: %d → %d tornadoes", before, after))
        notify(string.format("Rescanned: %d tornado(s)", after), "", 3)
    end)
    S:Spacing()
    S:Button("Active Tornadoes", function()
        local count = 0
        for _ in pairs(tornadoData) do count = count + 1 end
        printl("[Debug] Tornadoes tracked: " .. count)
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
        local dead = {}
        for key in pairs(probeData) do dead[#dead + 1] = key end
        for _, key in ipairs(dead) do
            removeEntry(key)
            activeKeys.probe[key] = nil
            probeData[key]        = nil
        end
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

loadConfig()
syncTornadoColors()
syncProbeColors()

UI.AddTab("Storm Tracker", function(tab)
    BuildESP(tab)
    BuildTornadoCustom(tab)
    BuildProbeCustom(tab)
    BuildBoost(tab)
    BuildTween(tab)
    BuildTweenProbe(tab)
    BuildFreeze(tab)
    BuildDebug(tab)
end)

cfg.CarFreeze.Enabled       = false
cfg.CharacterFreeze.Enabled = false
cfg.CarBoost.Enabled        = false

printl("[Storm Tracker] Loaded")
task.wait(2)

RunService.RenderStepped:Connect(function()
    if not isrbxactive() then return end

    if cfg.CarFreeze.Enabled then
        if freeze.active then
            local ch = freeze.chassis
            if ch and ch.Parent and freeze.prim and freeze.lockedPos then
                writePos(freeze.prim, freeze.lockedPos)
                zeroVel(freeze.prim)
            else
                freeze.active = false
                applyCarFreeze()
            end
        else
            applyCarFreeze()
        end
    end

    if cfg.CharacterFreeze.Enabled then
        local char = LocalPlayer.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then safeZeroVelocity(hrp) end
    end

    if cfg.CarBoost.Enabled and boostWidget and boostWidget:IsEnabled() then
        pcall(applyCarBoost)
    end
end)

RunService.Heartbeat:Connect(function()
    if not isrbxactive() then return end
    frameCount = frameCount + 1
    if frameCount % 2 == 0 then return end

    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local playerPos = hrp.Position

    pcall(updateTornadoEsp, playerPos)
    pcall(updateProbeEsp, playerPos)
end)

task.spawn(function()
    local scanFrame = 0
    while true do
        pcall(function()
            if isrbxactive() then
                scanFrame = scanFrame + 1
                if scanFrame % 30 == 0 then
                    scanTornadoes()
                    scanProbes()
                end
            end
        end)
        task.wait(1 / 60)
    end
end)
