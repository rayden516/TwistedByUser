local RunService  = game:GetService("RunService")
local Players     = game:GetService("Players")
local Http        = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

local O = Http:JSONDecode(game:HttpGet("https://offsets.imtheo.lol/offsets.json")).Offsets
if not O then print("[AutoFarm] offsets failed to load"); return end

local myUserId = "0"
pcall(function()
    local base = getbase()
    local dm = memory_read("uintptr_t", memory_read("uintptr_t", base + O.FakeDataModel.Pointer) + O.FakeDataModel.RealDataModel)
    local function getChild(parent, name)
        local ptr = memory_read("uintptr_t", parent + O.Instance.ChildrenStart)
        if ptr == 0 then return nil end
        local s, e = memory_read("uintptr_t", ptr), memory_read("uintptr_t", ptr + O.Instance.ChildrenEnd)
        for i = 0, (e - s) / 8 - 1 do
            local c = memory_read("uintptr_t", s + i * 8)
            if memory_read("string", memory_read("uintptr_t", c + O.Instance.Name)) == name then return c end
        end
    end
    local lp     = memory_read("uintptr_t", getChild(dm, "Players") + O.Player.LocalPlayer)
    local userId = memory_read("uintptr_t", lp + O.Player.UserId)
    myUserId = tostring(userId)
end)
print("[AutoFarm] UserId:", myUserId)

local WORLD_OFF     = O.Workspace.World
local GRAVITY_OFF   = O.World.Gravity
local OFF_PRIMITIVE = O.BasePart.Primitive
local OFF_CF        = O.Primitive.Rotation
local OFF_POS       = O.Primitive.Position - O.Primitive.Rotation

local function setGravity(g)
    pcall(function()
        local ptr = memory_read("uintptr_t", workspace.Address + WORLD_OFF)
        memory_write("float", ptr + GRAVITY_OFF, g)
    end)
end

local function readPrim(part)
    local ok, ptr = pcall(memory_read, "uintptr_t", part.Address + OFF_PRIMITIVE)
    if not ok or not ptr or ptr == 0 then return nil end
    return ptr
end

local function writePos(prim, pos)
    local base = prim + OFF_CF + OFF_POS
    pcall(function()
        memory_write("float", base,       pos.X)
        memory_write("float", base + 0x4, pos.Y)
        memory_write("float", base + 0x8, pos.Z)
    end)
end

local cfg = {
    AutoCollect     = false,
    AutoCycle       = false,
    ProbeCount      = 1,
    FrontOffset     = 250,
    HeightOffset    = 8,
    Speed           = 150,
    SafeRadius      = 300,
    Selected        = nil,
    TargetMode      = "manual",
    RetargetInterval = 2.0,
    WindPriority    = 60,
    CollectCooldown = 20,
    CollectHold     = 3.0,
    InteractKey     = 0x45,
    PlaceHold       = 5.0,
    WindThreshold   = 0,
    ShowHUD         = true,
    ShowCompass     = true,
    CollectKeyVK    = 0x71,
    CycleKeyVK      = 0x72,
    ProbeVK         = { 0x32, 0x33, 0x34, 0x35 },
}

local tornadoList    = {}
local collectActive  = false
local cycleActive    = false
local _cyclePhase    = "place"
local cycleKb        = nil
local _cycleKbPrev   = false
local farmTweenLock  = false
local farmDir        = Vector3.new(0, 0, 1)

local collectVisited = {}
local _curTargetName = nil
local _lastRetarget  = 0
local _hudActivity   = "Idle"

local collectKb       = nil
local probeKeyWidgets = {}
local probeKeyPrev    = { false, false, false, false }
local _collectKbPrev  = false

local AVOID_MARGIN = 1.35
local NAV_PREDICT   = 0.8
local NAV_W_WIND    = 3
local NAV_W_DIST    = 0.2
local NAV_W_BLOCK   = 150
local NAV_OMEGA_MIN = 0.15
local NAV_CONF_MIN  = 0.6

local hudLabel        = Drawing.new("Text")
hudLabel.Center       = true
hudLabel.Outline      = true
hudLabel.Font         = 2
hudLabel.Size         = 16
hudLabel.Transparency = 1
hudLabel.Color        = Color3.new(1, 1, 1)
hudLabel.Visible      = false

local compassArrow        = Drawing.new("Triangle")
compassArrow.Filled       = true
compassArrow.Thickness    = 1
compassArrow.Transparency = 1
compassArrow.Color        = Color3.new(1, 0.5, 0)
compassArrow.Visible      = false

local compassText        = Drawing.new("Text")
compassText.Center       = true
compassText.Outline      = true
compassText.Font         = 2
compassText.Size         = 14
compassText.Transparency = 1
compassText.Color        = Color3.new(1, 0.5, 0)
compassText.Visible      = false

local lastCompass = 0

local CONFIG_FILE = "autofarm_cfg.json"

local function saveKeyVK(widget, default)
    if widget then
        local k = widget:GetKey()
        if type(k) == "number" then return k end
    end
    return default
end

local function saveConfig()
    local data = {
        ProbeCount      = cfg.ProbeCount,
        FrontOffset     = cfg.FrontOffset,
        HeightOffset    = cfg.HeightOffset,
        Speed           = cfg.Speed,
        SafeRadius      = cfg.SafeRadius,
        TargetMode      = cfg.TargetMode,
        RetargetInterval = cfg.RetargetInterval,
        WindPriority    = cfg.WindPriority,
        CollectCooldown = cfg.CollectCooldown,
        CollectHold     = cfg.CollectHold,
        PlaceHold       = cfg.PlaceHold,
        WindThreshold   = cfg.WindThreshold,
        ShowHUD         = cfg.ShowHUD,
        ShowCompass     = cfg.ShowCompass,
        Selected        = cfg.Selected,
        CollectKB       = saveKeyVK(collectKb, cfg.CollectKeyVK),
        CycleKB         = saveKeyVK(cycleKb,   cfg.CycleKeyVK),
        ProbeKB1        = saveKeyVK(probeKeyWidgets[1], cfg.ProbeVK[1]),
        ProbeKB2        = saveKeyVK(probeKeyWidgets[2], cfg.ProbeVK[2]),
        ProbeKB3        = saveKeyVK(probeKeyWidgets[3], cfg.ProbeVK[3]),
        ProbeKB4        = saveKeyVK(probeKeyWidgets[4], cfg.ProbeVK[4]),
    }
    pcall(function()
        writefile(CONFIG_FILE, Http:JSONEncode(data))
    end)
    notify("Config saved!", "", 3)
end

local function loadConfig()
    pcall(function()
        if not isfile(CONFIG_FILE) then return end
        local raw = readfile(CONFIG_FILE)
        if not raw or raw == "" then return end
        local data = Http:JSONDecode(raw)
        if type(data) ~= "table" then return end

        local function getNum(key, default) return tonumber(data[key]) or default end
        local function getBool(key, default)
            local v = data[key]
            return type(v) == "boolean" and v or default
        end
        local function getStr(key, default)
            local v = data[key]
            return type(v) == "string" and v or default
        end

        cfg.ProbeCount      = math.floor(getNum("ProbeCount", cfg.ProbeCount))
        cfg.FrontOffset     = getNum("FrontOffset",  cfg.FrontOffset)
        cfg.HeightOffset    = getNum("HeightOffset", cfg.HeightOffset)
        cfg.Speed           = getNum("Speed",        cfg.Speed)
        cfg.SafeRadius      = getNum("SafeRadius",   cfg.SafeRadius)
        cfg.RetargetInterval = getNum("RetargetInterval", cfg.RetargetInterval)
        cfg.WindPriority    = getNum("WindPriority", cfg.WindPriority)
        cfg.CollectCooldown = getNum("CollectCooldown", cfg.CollectCooldown)
        cfg.CollectHold     = getNum("CollectHold", cfg.CollectHold)
        cfg.PlaceHold       = getNum("PlaceHold", cfg.PlaceHold)
        cfg.WindThreshold   = getNum("WindThreshold", cfg.WindThreshold)
        cfg.ShowHUD         = getBool("ShowHUD", cfg.ShowHUD)
        cfg.ShowCompass     = getBool("ShowCompass", cfg.ShowCompass)

        local mode = getStr("TargetMode", cfg.TargetMode)
        if mode == "manual" or mode == "nearest" or mode == "strongest" or mode == "smart" then
            cfg.TargetMode = mode
        end
        cfg.Selected = getStr("Selected", nil)

        cfg.CollectKeyVK = getNum("CollectKB", cfg.CollectKeyVK)
        cfg.CycleKeyVK   = getNum("CycleKB",   cfg.CycleKeyVK)
        cfg.ProbeVK[1]   = getNum("ProbeKB1",  cfg.ProbeVK[1])
        cfg.ProbeVK[2]   = getNum("ProbeKB2",  cfg.ProbeVK[2])
        cfg.ProbeVK[3]   = getNum("ProbeKB3",  cfg.ProbeVK[3])
        cfg.ProbeVK[4]   = getNum("ProbeKB4",  cfg.ProbeVK[4])
    end)
end

local function scanTornadoes()
    local sr = workspace:FindFirstChild("storm_related")
    local st = sr and sr:FindFirstChild("storms")
    if not st then tornadoList = {}; return end

    local found = {}
    for _, model in ipairs(st:GetChildren()) do
        if model:IsA("Model") then
            local rot = model:FindFirstChild("rotation")
            if rot then
                local ts = rot:FindFirstChild("tornado_scan")
                if ts and ts:IsA("BasePart") then
                    found[#found + 1] = { name = model.Name, part = ts, storm = model }
                end
            end
        end
    end
    table.sort(found, function(a, b) return a.name < b.name end)
    tornadoList = found
end

local function getStormWind(stormModel)
    if not stormModel or not stormModel.Parent then return 0 end
    local wind = 0
    local configs = stormModel:FindFirstChild("configs")
    if configs then
        local w = configs:FindFirstChild("winds")
        if w and w:IsA("ValueBase") then
            local v = w.Value
            if type(v) == "number" then wind = v end
        end
    end
    local windFolder = stormModel:FindFirstChild("wind")
    if windFolder then
        for _, part in ipairs(windFolder:GetChildren()) do
            local v = part:GetAttribute("winds")
            if type(v) == "number" and v > wind then wind = v end
        end
    end
    return wind
end

local function getStormSpeed(stormModel)
    if not stormModel or not stormModel.Parent then return 0 end
    local configs = stormModel:FindFirstChild("configs")
    local motion  = configs and configs:FindFirstChild("motion")
    if not motion then return 0 end
    local v = motion:GetAttribute("speed")
    if type(v) == "number" then return v end
    return 0
end

local nav = {
    samples = {},
    MAX     = 6,
    ALPHA   = 0.4,
}

local function navSample(d)
    local part = d.part
    if not part or not part.Parent then return Vector3.new(0, 0, 0) end
    local pos = part.Position

    local key = d.name
    local h = nav.samples[key]
    if not h then
        h = { pts = {}, vx = 0, vy = 0, vz = 0, omega = 0, theta = 0,
              thetaTime = 0, hasTheta = false, conf = 0, lastSeen = 0,
              dirX = 0, dirZ = 0, hasDir = false }
        nav.samples[key] = h
    end

    local now = tick()
    h.lastSeen = now
    local n = #h.pts
    if n == 0 or (now - h.pts[n].t) >= 0.03 then
        h.pts[n + 1] = { x = pos.X, y = pos.Y, z = pos.Z, t = now }
        while #h.pts > nav.MAX do table.remove(h.pts, 1) end
    end

    if #h.pts >= 2 then
        local a  = h.pts[1]
        local b  = h.pts[#h.pts]
        local dt = b.t - a.t
        if dt > 0.01 then
            local ivx = (b.x - a.x) / dt
            local ivy = (b.y - a.y) / dt
            local ivz = (b.z - a.z) / dt
            h.vx = h.vx * (1 - nav.ALPHA) + ivx * nav.ALPHA
            h.vy = h.vy * (1 - nav.ALPHA) + ivy * nav.ALPHA
            h.vz = h.vz * (1 - nav.ALPHA) + ivz * nav.ALPHA
        end

        local sp = math.sqrt(h.vx * h.vx + h.vz * h.vz)
        if sp > 2 then
            local theta = math.atan2(h.vz, h.vx)
            if h.hasTheta and (now - h.thetaTime) > 0.01 then
                local dth = theta - h.theta
                while dth > math.pi do dth = dth - 2 * math.pi end
                while dth < -math.pi do dth = dth + 2 * math.pi end
                h.omega = h.omega * (1 - nav.ALPHA) + (dth / (now - h.thetaTime)) * nav.ALPHA
            end
            h.theta     = theta
            h.thetaTime = now
            h.hasTheta  = true
            h.dirX      = h.vx / sp
            h.dirZ      = h.vz / sp
            h.hasDir    = true
        else
            h.omega = h.omega * 0.8
        end
        h.conf = math.min((#h.pts - 1) / (nav.MAX - 1), 1)
    end
    return Vector3.new(h.vx, h.vy, h.vz)
end

local function navPredict(d, t)
    local h = nav.samples[d.name]
    if not h then return 0, 0 end
    local s = math.sqrt(h.vx * h.vx + h.vz * h.vz)
    if s < 1 then return 0, 0 end
    local conf = h.conf or 0
    local ox, oz
    if math.abs(h.omega) > NAV_OMEGA_MIN and conf > NAV_CONF_MIN then
        local th0 = math.atan2(h.vz, h.vx)
        local w   = h.omega
        ox = (s / w) * (math.sin(th0 + w * t) - math.sin(th0))
        oz = (s / w) * (math.cos(th0) - math.cos(th0 + w * t))
    else
        ox = h.vx * t
        oz = h.vz * t
    end
    return ox * conf, oz * conf
end

local function navSweep()
    local now = tick()
    for key, h in pairs(nav.samples) do
        if now - h.lastSeen > 5 then nav.samples[key] = nil end
    end
end

local function getTargetData()
    for _, d in ipairs(tornadoList) do
        if d.name == cfg.Selected and d.part and d.part.Parent then
            return d
        end
    end
    for _, d in ipairs(tornadoList) do
        if d.part and d.part.Parent then return d end
    end
    return nil
end

local function getTarget()
    local d = getTargetData()
    return d and d.part or nil
end

local function tornadoRadiusOf(d)
    local part = d.part
    if not part then return 30 end
    local sz = part.Size
    return math.max(sz.X, sz.Z) * 0.5
end

local _circles     = {}
local _circlesTime = 0

local function getDangerCircles()
    local now = tick()
    if now - _circlesTime < 0.1 then return _circles end
    local circles = {}
    for _, d in ipairs(tornadoList) do
        local part = d.part
        if part and part.Parent then
            local pos   = part.Position
            local vel   = navSample(d)
            local wind  = getStormWind(d.storm)
            local speed = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
            local lx, lz = navPredict(d, NAV_PREDICT)
            local lm   = math.sqrt(lx * lx + lz * lz)
            local cap  = cfg.SafeRadius * 0.6
            if lm > cap then
                lx = lx / lm * cap
                lz = lz / lm * cap
            end
            circles[#circles + 1] = {
                x = pos.X + lx,
                z = pos.Z + lz,
                r = tornadoRadiusOf(d) + cfg.SafeRadius * (1 + wind / 80) * AVOID_MARGIN + speed * 0.25,
                killR = tornadoRadiusOf(d) + cfg.SafeRadius * 0.35,
            }
        end
    end
    _circles     = circles
    _circlesTime = now
    navSweep()
    return circles
end

local function pointInKillZone(pos)
    for _, c in ipairs(getDangerCircles()) do
        local dx, dz = pos.X - c.x, pos.Z - c.z
        if dx * dx + dz * dz < c.killR * c.killR then return true end
    end
    return false
end

local function avoidPenalty(x, z, tight)
    local pen = 0
    for _, c in ipairs(getDangerCircles()) do
        local cr = tight and c.killR or c.r
        local dx, dz = x - c.x, z - c.z
        local d2 = dx * dx + dz * dz
        if d2 < cr * cr then pen = pen + (cr - math.sqrt(d2)) end
    end
    return pen
end

local function avoidanceTarget(fromPos, goal, tight)
    local fx, fz = fromPos.X, fromPos.Z
    local gx, gz = goal.X, goal.Z
    local sx, sz = gx - fx, gz - fz
    local segLen2 = sx * sx + sz * sz
    if segLen2 < 1e-4 then return goal end

    local bestT, blocker = math.huge, nil
    for _, c in ipairs(getDangerCircles()) do
        local cr = tight and c.killR or c.r
        local gdx, gdz = gx - c.x, gz - c.z
        if (gdx * gdx + gdz * gdz) > cr * cr then
            local proj = ((c.x - fx) * sx + (c.z - fz) * sz) / segLen2
            if proj > 0 and proj < 1 then
                local px, pz = fx + sx * proj, fz + sz * proj
                local ddx, ddz = px - c.x, pz - c.z
                if ddx * ddx + ddz * ddz < cr * cr and proj < bestT then
                    bestT   = proj
                    blocker = c
                end
            end
        end
    end
    if not blocker then return goal end

    local c = blocker
    local dx, dz = c.x - fx, c.z - fz
    local d2 = dx * dx + dz * dz
    local r  = tight and c.killR or c.r
    if d2 <= r * r then
        local d = math.sqrt(math.max(d2, 1e-6))
        return Vector3.new(fx - dx / d * r * 1.2, goal.Y, fz - dz / d * r * 1.2)
    end

    local d        = math.sqrt(d2)
    local invD     = 1 / d
    local tangLen2 = d2 - r * r
    local along    = tangLen2 * invD
    local perp     = r * math.sqrt(tangLen2) * invD
    local uX, uZ   = dx * invD, dz * invD
    local vX, vZ   = -uZ, uX
    local apX, apZ = fx + along * uX, fz + along * uZ
    local lX, lZ   = apX + perp * vX, apZ + perp * vZ
    local rX, rZ   = apX - perp * vX, apZ - perp * vZ

    local lPen = avoidPenalty(lX, lZ, tight)
    local rPen = avoidPenalty(rX, rZ, tight)
    local cX, cZ
    if math.abs(lPen - rPen) > 1 then
        if lPen < rPen then cX, cZ = lX, lZ else cX, cZ = rX, rZ end
    else
        local lg = (lX - gx) * (lX - gx) + (lZ - gz) * (lZ - gz)
        local rg = (rX - gx) * (rX - gx) + (rZ - gz) * (rZ - gz)
        if lg < rg then cX, cZ = lX, lZ else cX, cZ = rX, rZ end
    end

    for _, oc in ipairs(getDangerCircles()) do
        local ocr = tight and oc.killR or oc.r
        local odx, odz = cX - oc.x, cZ - oc.z
        local od2 = odx * odx + odz * odz
        if od2 < ocr * ocr then
            local od = math.sqrt(math.max(od2, 1e-6))
            cX = oc.x + odx / od * ocr * 1.1
            cZ = oc.z + odz / od * ocr * 1.1
        end
    end

    return Vector3.new(cX, goal.Y, cZ)
end

local function getSafeTarget(playerPos, d)
    local part = d.part
    if not part then return playerPos end
    local torPos = part.Position
    local stormModel = d.storm

    local wind         = getStormWind(stormModel)
    local stormSpeed   = getStormSpeed(stormModel)
    local windScale    = 1 + wind / 80
    local r            = tornadoRadiusOf(d) + cfg.SafeRadius * windScale
    local r2           = r * r

    local h = nav.samples[d.name]
    local vH, dirX, dirZ = 0, farmDir.X, farmDir.Z
    if h then
        vH = math.sqrt(h.vx * h.vx + h.vz * h.vz)
        if vH > 1 then dirX, dirZ = h.vx / vH, h.vz / vH end
    end

    local dxRaw = torPos.X - playerPos.X
    local dzRaw = torPos.Z - playerPos.Z
    local dRaw  = math.sqrt(dxRaw * dxRaw + dzRaw * dzRaw)
    local tLook = math.min(dRaw / math.max(cfg.Speed, 1), 1.5)

    local lx, lz = navPredict(d, tLook)
    if (lx * lx + lz * lz) < 1 and stormSpeed > 0 then
        lx = dirX * stormSpeed * tLook
        lz = dirZ * stormSpeed * tLook
    end
    local tx = torPos.X + lx
    local tz = torPos.Z + lz

    local frontOffset = math.max(cfg.FrontOffset * windScale, r * 1.15)
    local frontPos = Vector3.new(
        tx + dirX * frontOffset,
        torPos.Y + cfg.HeightOffset,
        tz + dirZ * frontOffset
    )

    local dx = tx - playerPos.X
    local dz = tz - playerPos.Z
    local d2 = dx * dx + dz * dz
    local y  = torPos.Y + cfg.HeightOffset

    if d2 < r2 then
        if d2 < 1e-6 then
            return Vector3.new(tx + dirX * r * 1.4, y, tz + dirZ * r * 1.4)
        end
        local invD = 1 / math.sqrt(d2)
        return Vector3.new(tx - dx * invD * r * 1.4, y, tz - dz * invD * r * 1.4)
    end

    local sx = frontPos.X - playerPos.X
    local sz = frontPos.Z - playerPos.Z
    local segLen2 = sx * sx + sz * sz
    if segLen2 < 1e-4 then return frontPos end

    local proj = dx * sx + dz * sz
    local t = proj / segLen2
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local cx = playerPos.X + sx * t - tx
    local cz = playerPos.Z + sz * t - tz
    if (cx * cx + cz * cz) >= r2 then
        return frontPos
    end

    local tangLen2 = d2 - r2
    local tangLen  = math.sqrt(tangLen2)
    local d        = math.sqrt(d2)
    local invD     = 1 / d
    local along    = tangLen2 * invD
    local perp     = r * tangLen * invD

    local uX, uZ = dx * invD, dz * invD
    local vX, vZ = -uZ, uX

    local apX = playerPos.X + along * uX
    local apZ = playerPos.Z + along * uZ
    local lX, lZ = apX + perp * vX, apZ + perp * vZ
    local rX, rZ = apX - perp * vX, apZ - perp * vZ

    local lFx, lFz = lX - frontPos.X, lZ - frontPos.Z
    local rFx, rFz = rX - frontPos.X, rZ - frontPos.Z

    if (lFx * lFx + lFz * lFz) < (rFx * rFx + rFz * rFz) then
        return Vector3.new(lX, y, lZ)
    else
        return Vector3.new(rX, y, rZ)
    end
end

local function navBlocked(fromPos, goal)
    local steer = avoidanceTarget(fromPos, goal)
    local dx = steer.X - goal.X
    local dz = steer.Z - goal.Z
    return (dx * dx + dz * dz) > 1
end

local function navScore(d, playerPos)
    if not d.part then return -math.huge end
    local pos = d.part.Position
    local wind = getStormWind(d.storm)
    local dist = (playerPos - pos).Magnitude
    local bias = cfg.WindPriority / 100
    local score = wind * bias * NAV_W_WIND - dist * (1 - bias) * NAV_W_DIST
    if navBlocked(playerPos, pos) then score = score - NAV_W_BLOCK end
    return score
end

local function pickTarget(playerPos)
    if cfg.TargetMode == "manual" then
        return getTargetData()
    end

    local now = tick()
    local cur = nil
    if _curTargetName then
        for _, d in ipairs(tornadoList) do
            if d.name == _curTargetName and d.part and d.part.Parent then cur = d; break end
        end
    end
    if cur and (now - _lastRetarget) < cfg.RetargetInterval then
        return cur
    end
    _lastRetarget = now

    local best, bestScore = nil, nil
    for _, d in ipairs(tornadoList) do
        if d.part and d.part.Parent then
            local pos = d.part.Position
            local score
            if cfg.TargetMode == "strongest" then
                score = getStormWind(d.storm)
            elseif cfg.TargetMode == "smart" then
                score = navScore(d, playerPos)
            else
                score = -(playerPos - pos).Magnitude
            end
            if not bestScore or score > bestScore then best, bestScore = d, score end
        end
    end
    if best then _curTargetName = best.name; cfg.Selected = best.name end
    return best or cur
end

local function cancelFarmTween()
    farmTweenLock = false
    setGravity(196.2)
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end
end

local function tweenTo(target, onDone, timeout, tight)
    if farmTweenLock then cancelFarmTween() end
    farmTweenLock = true
    setGravity(10)

    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then farmTweenLock = false; setGravity(196.2); return end

    local tmax      = timeout or 60
    local startTime = tick()
    local lastProg  = tick()
    local lastPos   = hrp.Position
    task.spawn(function()
        while farmTweenLock do
            if tick() - startTime > tmax then cancelFarmTween(); break end

            local c  = LocalPlayer.Character
            local rp = c and c:FindFirstChild("HumanoidRootPart")
            if not rp then cancelFarmTween(); break end

            local rpPos = rp.Position
            local diff  = target - rpPos
            local hDist = math.sqrt(diff.X * diff.X + diff.Z * diff.Z)

            if hDist < 5 then
                local prim = readPrim(rp)
                if prim then writePos(prim, target) end
                rp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                cancelFarmTween()
                if onDone then onDone() end
                break
            end

            local now = tick()
            if (rpPos - lastPos).Magnitude > 3 then
                lastPos  = rpPos
                lastProg = now
            elseif now - lastProg > 2.5 then
                rp.AssemblyLinearVelocity = Vector3.new(0, 70, 0)
                lastProg = now
                task.wait(0.2)
            end

            local steer  = avoidanceTarget(rpPos, target, tight)
            local mdiff  = steer - rpPos
            local mDistH = math.sqrt(mdiff.X * mdiff.X + mdiff.Z * mdiff.Z)
            local dir    = (mDistH > 1e-3) and (mdiff / mdiff.Magnitude) or diff.Unit

            local spd = hDist < 40
                and math.max(cfg.Speed * (hDist / 40), 12)
                or  cfg.Speed
            local maxStep = hDist * 22
            if spd > maxStep then spd = maxStep end

            rp.AssemblyLinearVelocity = Vector3.new(
                dir.X * spd,
                dir.Y * spd * 0.5,
                dir.Z * spd
            )
            task.wait(1 / 30)
        end
    end)
end

local probePartCache = {}

local function findProbePart_local(probe)
    if not probe or not probe:IsA("Model") then return nil end
    local mesh = probe:FindFirstChild("mesh")
    if not mesh then return nil end
    local fallbackMesh, fallbackBase = nil, nil
    for _, child in ipairs(mesh:GetChildren()) do
        if child:IsA("MeshPart") then
            if child.Name:find("Tower Probe_Cylinder") then return child end
            if not fallbackMesh then fallbackMesh = child end
        elseif child:IsA("BasePart") and not fallbackBase then
            fallbackBase = child
        end
    end
    return fallbackMesh or fallbackBase
end

local function resolveProbePart(probe)
    local cached = probePartCache[probe]
    if cached and cached.Parent then return cached end
    local part = findProbePart_local(probe)
    probePartCache[probe] = part
    return part
end

local function isMineName(name)
    return (name == myUserId) or (myUserId ~= "0" and name:find(myUserId, 1, true) ~= nil)
end

local function collectMyProbes(pfold)
    local mine = {}
    for _, probe in ipairs(pfold:GetChildren()) do
        if probe:IsA("Model") and isMineName(probe.Name) then
            mine[#mine + 1] = probe
        end
    end
    if #mine == 0 then
        for _, desc in ipairs(pfold:GetDescendants()) do
            if desc:IsA("Model") and isMineName(desc.Name) then
                mine[#mine + 1] = desc
            end
        end
    end
    return mine
end

local function getProbesSorted()
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return {} end
    local pp   = hrp.Position

    local pr    = workspace:FindFirstChild("player_related")
    local pfold = pr and pr:FindFirstChild("probes")
    if not pfold then return {} end

    local list = {}
    for _, probe in ipairs(collectMyProbes(pfold)) do
        local part = resolveProbePart(probe)
        if part and part.Parent then
            local pos = part.Position
            list[#list + 1] = {
                pos     = pos,
                dist    = (pp - pos).Magnitude,
                name    = probe.Name,
                blocked = pointInKillZone(pos),
            }
        end
    end
    table.sort(list, function(a, b)
        if a.blocked ~= b.blocked then return not a.blocked end
        return a.dist < b.dist
    end)
    return list
end

local function goToProbe(rank)
    if farmTweenLock then cancelFarmTween(); notify("Cancelled", "", 2); return end
    local list = getProbesSorted()
    if #list == 0 then notify("No probes found", "", 3); return end
    local e = list[math.min(rank, #list)]
    notify(string.format("Probe #%d | %.0fm", rank, e.dist), e.blocked and "near tornado" or "", 3)
    tweenTo(e.pos, nil, nil, true)
end

local function updateHud()
    if not cfg.ShowHUD then hudLabel.Visible = false; return end
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    local tgt  = cfg.Selected or "-"
    local dist = "-"
    local tp   = getTarget()
    if tp and hrp then dist = string.format("%.0fm", (hrp.Position - tp.Position).Magnitude) end
    local cam = workspace.CurrentCamera
    if cam then hudLabel.Position = Vector2.new(cam.ViewportSize.X / 2, 60) end
    hudLabel.Text    = string.format("AutoFarm | %s | mode: %s | %s | %s",
        _hudActivity, cfg.TargetMode, tgt, dist)
    hudLabel.Visible = true
end

local COMPASS_RADIUS = 120
local COMPASS_LEN    = 18
local COMPASS_WIDTH  = 11

local function hideCompass()
    compassArrow.Visible = false
    compassText.Visible  = false
end

local function updateCompass()
    if not cfg.ShowCompass then hideCompass(); return end

    local d = getTargetData()
    if not d or not d.part or not d.part.Parent then hideCompass(); return end

    local cam = workspace.CurrentCamera
    if not cam or type(WorldToScreen) ~= "function" then hideCompass(); return end

    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then hideCompass(); return end

    local targetPos = d.part.Position
    local vp = cam.ViewportSize
    local cx, cy = vp.X / 2, vp.Y / 2

    local scr, onScreen = WorldToScreen(targetPos)
    if not scr then hideCompass(); return end

    local dx = scr.X - cx
    local dy = scr.Y - cy
    local insideRect = scr.X >= 0 and scr.X <= vp.X and scr.Y >= 0 and scr.Y <= vp.Y
    if (not onScreen) and insideRect then
        dx = -dx
        dy = -dy
    end

    local mag = math.sqrt(dx * dx + dy * dy)
    if mag < 1e-3 then dx, dy, mag = 0, -1, 1 end
    local nx, ny = dx / mag, dy / mag
    local px, py = -ny, nx

    local baseX = cx + nx * COMPASS_RADIUS
    local baseY = cy + ny * COMPASS_RADIUS
    local tipX  = baseX + nx * COMPASS_LEN
    local tipY  = baseY + ny * COMPASS_LEN

    compassArrow.PointA  = Vector2.new(tipX, tipY)
    compassArrow.PointB  = Vector2.new(baseX + px * COMPASS_WIDTH, baseY + py * COMPASS_WIDTH)
    compassArrow.PointC  = Vector2.new(baseX - px * COMPASS_WIDTH, baseY - py * COMPASS_WIDTH)
    compassArrow.Visible = true

    local dist = (hrp.Position - targetPos).Magnitude
    local wind = getStormWind(d.storm)
    compassText.Position = Vector2.new(
        cx + nx * (COMPASS_RADIUS + COMPASS_LEN + 16),
        cy + ny * (COMPASS_RADIUS + COMPASS_LEN + 16)
    )
    compassText.Text     = string.format("%.0fm  w=%.0f", dist, wind)
    compassText.Visible  = true
end

local function startCollect()
    if collectActive then return end
    collectActive = true
    collectVisited = {}
    _hudActivity = "Collecting"

    task.spawn(function()
        while collectActive do
            local list = getProbesSorted()
            local now  = tick()
            local pick, anyUnblocked = nil, false
            for _, e in ipairs(list) do
                if not e.blocked then
                    anyUnblocked = true
                    if (now - (collectVisited[e.name] or 0)) > cfg.CollectCooldown then
                        pick = e
                        break
                    end
                end
            end

            if pick then
                collectVisited[pick.name] = now
                _hudActivity = "Collecting"
                tweenTo(pick.pos, nil, 12, true)
                while collectActive and farmTweenLock do task.wait(0.1) end
                if collectActive and isrbxactive() then
                    keypress(cfg.InteractKey)
                    local t0 = tick()
                    while collectActive and (tick() - t0) < cfg.CollectHold do task.wait(0.05) end
                    keyrelease(cfg.InteractKey)
                end
                task.wait(0.2)
            elseif anyUnblocked then
                collectVisited = {}
                task.wait(0.3)
            else
                _hudActivity = "Waiting"
                task.wait(1)
            end
        end
        if farmTweenLock then cancelFarmTween() end
        if not cycleActive then _hudActivity = "Idle" end
    end)
end

local function stopCollect()
    collectActive = false
    cfg.AutoCollect = false
    if farmTweenLock then cancelFarmTween() end
    if not cycleActive then _hudActivity = "Idle" end
end

local function steerToward(rp, goal)
    local diff   = goal - rp.Position
    local hDist  = math.sqrt(diff.X * diff.X + diff.Z * diff.Z)
    local steer  = avoidanceTarget(rp.Position, goal)
    local mdiff  = steer - rp.Position
    local mDistH = math.sqrt(mdiff.X * mdiff.X + mdiff.Z * mdiff.Z)
    local dir    = (mDistH > 1e-3) and (mdiff / mdiff.Magnitude) or diff.Unit
    local spd    = hDist < 40 and math.max(cfg.Speed * (hDist / 40), 12) or cfg.Speed
    rp.AssemblyLinearVelocity = Vector3.new(dir.X * spd, dir.Y * spd * 0.5, dir.Z * spd)
    return hDist
end

local function myProbeCount()
    local pr = workspace:FindFirstChild("player_related")
    local pfold = pr and pr:FindFirstChild("probes")
    if not pfold then return 0 end
    return #collectMyProbes(pfold)
end

local function placeProbes()
    for i = 1, cfg.ProbeCount do
        if not cycleActive then return end
        if isrbxactive() then
            local vk = cfg.ProbeVK[i]
            local before = myProbeCount()
            local tries  = 0
            repeat
                keypress(vk)
                task.wait(0.08)
                keyrelease(vk)
                task.wait(0.15)
                mouse1press()
                local t0 = tick()
                while cycleActive and (tick() - t0) < cfg.PlaceHold do task.wait(0.05) end
                mouse1release()
                task.wait(0.4)
                tries = tries + 1
            until (not cycleActive) or (myProbeCount() > before) or (tries >= 2)
        end
    end
end

local function cycleChar()
    local c = LocalPlayer.Character
    return c, c and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChild("Humanoid")
end

local function frontSpot(td)
    if not td.part then return nil end
    local tp = td.part.Position
    local h = nav.samples[td.name]
    local dirX, dirZ = 0, 1
    if h then
        local v = math.sqrt(h.vx * h.vx + h.vz * h.vz)
        if v > 1 then
            dirX, dirZ = h.vx / v, h.vz / v
        elseif h.hasDir then
            dirX, dirZ = h.dirX, h.dirZ
        end
    end
    local wind    = getStormWind(td.storm)
    local dangerR = tornadoRadiusOf(td) + cfg.SafeRadius * (1 + wind / 80) * AVOID_MARGIN
    local dist    = math.max(cfg.FrontOffset, dangerR * 1.15)
    return Vector3.new(tp.X + dirX * dist, tp.Y, tp.Z + dirZ * dist)
end

local function waitGrounded(timeout)
    local t0 = tick()
    local _, rp = cycleChar()
    if not rp then return end
    local lastY  = rp.Position.Y
    local stable = 0
    while cycleActive and (tick() - t0) < timeout do
        task.wait(0.1)
        local _, r = cycleChar()
        if not r then return end
        local y = r.Position.Y
        if math.abs(y - lastY) < 0.4 then
            stable = stable + 0.1
            if stable >= 0.4 then return end
        else
            stable = 0
        end
        lastY = y
    end
end

local function startCycle()
    if cycleActive then return end
    cycleActive  = true
    _cyclePhase  = "place"
    _hudActivity = "Farm"
    setGravity(10)

    task.spawn(function()
        while cycleActive do
            local _, rp = cycleChar()
            if not rp then
                task.wait(0.2)
            else
                local td = pickTarget(rp.Position)
                local weak = td and td.part and getStormWind(td.storm) < cfg.WindThreshold
                if not td or not (td.part and td.part.Parent) or weak then
                    _hudActivity = weak and "Farm: weak storm, waiting" or "Farm: searching"
                    task.wait(0.4)
                else
                    _cyclePhase = "place"
                    _hudActivity = "Farm: to front"
                    setGravity(10)
                    navSample(td)
                    local warm = 0
                    while cycleActive and warm < 0.6 do
                        task.wait(0.05)
                        navSample(td)
                        local h = nav.samples[td.name]
                        if h and h.hasDir then break end
                        warm = warm + 0.05
                    end
                    local front = frontSpot(td)
                    if front then
                        tweenTo(front, nil, 30)
                        while cycleActive and farmTweenLock do task.wait(0.1) end
                    end
                    if not cycleActive then break end

                    _, rp = cycleChar()
                    if rp then
                        _hudActivity = "Farm: landing"
                        setGravity(196.2)
                        rp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                        waitGrounded(6)

                        for _, e in ipairs(tornadoList) do
                            if e.name == td.name and e.part and e.part.Parent then td = e; break end
                        end
                        local wind = getStormWind(td.storm)
                        if cycleActive and wind >= cfg.WindThreshold then
                            _hudActivity = string.format("Farm: place w=%.0f", wind)
                            placeProbes()
                        end
                    end

                    setGravity(10)
                    _, rp = cycleChar()
                    local placedX = rp and rp.Position.X or 0
                    local placedZ = rp and rp.Position.Z or 0

                    _cyclePhase = "follow"
                    local reached = false
                    local dStart  = nil
                    local fStart  = tick()
                    while cycleActive do
                        local _, frp = cycleChar()
                        if not frp then
                            task.wait(0.1)
                        else
                            local cur = nil
                            for _, e in ipairs(tornadoList) do
                                if e.name == td.name and e.part and e.part.Parent then cur = e; break end
                            end
                            if not cur then break end
                            if tick() - fStart > 60 then break end

                            local tp2 = cur.part.Position
                            local dx2, dz2 = tp2.X - placedX, tp2.Z - placedZ
                            local dProbe = math.sqrt(dx2 * dx2 + dz2 * dz2)
                            if not dStart then dStart = dProbe end
                            local tr = tornadoRadiusOf(cur)
                            local cw = getStormWind(cur.storm)
                            if dProbe < tr + 40 then reached = true end
                            if reached and not pointInKillZone(Vector3.new(placedX, 0, placedZ)) then break end
                            if (not reached) and dProbe > dStart + 500 then break end

                            _hudActivity = string.format("Farm: %s w=%.0f",
                                reached and "storm passing" or "waiting storm", cw)
                            navSample(cur)
                            steerToward(frp, getSafeTarget(frp.Position, cur))
                            task.wait(1 / 30)
                        end
                    end
                    if not cycleActive then break end

                    _cyclePhase = "collect"
                    local guard  = 0
                    local cStart = tick()
                    while cycleActive and guard <= cfg.ProbeCount + 1 and (tick() - cStart) < 45 do
                        local list = getProbesSorted()
                        if #list == 0 then break end
                        local e = list[1]
                        if e.blocked then
                            _hudActivity = "Farm: probe in storm, waiting"
                            task.wait(0.5)
                        else
                            _hudActivity = "Farm: collecting"
                            tweenTo(e.pos, nil, 15, true)
                            while cycleActive and farmTweenLock do task.wait(0.1) end
                            if cycleActive and isrbxactive() then
                                keypress(cfg.InteractKey)
                                local t0 = tick()
                                while cycleActive and (tick() - t0) < cfg.CollectHold do task.wait(0.05) end
                                keyrelease(cfg.InteractKey)
                            end
                            setGravity(10)
                            local _, crp = cycleChar()
                            if crp then crp.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end
                            task.wait(0.3)
                            guard = guard + 1
                        end
                    end
                end
            end
        end

        setGravity(196.2)
        local _, rp = cycleChar()
        if rp then rp.AssemblyLinearVelocity = Vector3.new(0, 0, 0) end
        mouse1release()
        keyrelease(cfg.InteractKey)
    end)
end

local function stopCycle()
    cycleActive   = false
    cfg.AutoCycle = false
    if farmTweenLock then cancelFarmTween() end
    if not collectActive then _hudActivity = "Idle" end
end

local function setCollect(state)
    if state == collectActive then return end
    cfg.AutoCollect = state
    if state then
        if cycleActive then stopCycle(); UI.SetValue("auto_cycle", false) end
        startCollect()
        notify("Auto Collect ON", "", 2)
    else
        stopCollect()
        notify("Auto Collect OFF", "", 2)
    end
end

local function setCycle(state)
    if state == cycleActive then return end
    cfg.AutoCycle = state
    if state then
        if collectActive then stopCollect(); UI.SetValue("auto_collect", false) end
        if #tornadoList == 0 then scanTornadoes() end
        if cfg.TargetMode == "manual" and not cfg.Selected and #tornadoList > 0 then
            cfg.Selected = tornadoList[1].name
        end
        startCycle()
        notify("Auto Farm ON", "place/follow/collect", 3)
    else
        stopCycle()
        notify("Auto Farm OFF", "", 2)
    end
end

loadConfig()

UI.AddTab("Auto Farm", function(tab)
    local TS = tab:Section("Target", "Left")

    local tp   = getTarget()
    local char = LocalPlayer.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if tp and hrp then
        local d = (hrp.Position - tp.Position).Magnitude
        TS:Text(string.format("[ %s ] | %.0fm", cfg.Selected or "?", d))
    else
        TS:Text("Target: " .. (cfg.Selected or "none"))
    end
    TS:Text(string.format("Mode: %s | Tornadoes: %d", cfg.TargetMode, #tornadoList))
    TS:Spacing()

    TS:Button("Scan Tornadoes", function()
        scanTornadoes()
        if #tornadoList > 0 and not cfg.Selected then
            cfg.Selected = tornadoList[1].name
        end
        notify(#tornadoList .. " tornado(s) found", "", 3)
    end)
    TS:Spacing()

    TS:Button("Mode: Nearest",  function() cfg.TargetMode = "nearest";   _curTargetName = nil; notify("Mode: Nearest", "", 2) end)
    TS:Button("Mode: Strongest", function() cfg.TargetMode = "strongest"; _curTargetName = nil; notify("Mode: Strongest", "", 2) end)
    TS:Button("Mode: Smart",    function() cfg.TargetMode = "smart";    _curTargetName = nil; notify("Mode: Smart", "", 2) end)
    TS:Button("Mode: Manual",   function() cfg.TargetMode = "manual"; notify("Mode: Manual", "", 2) end)
    TS:Spacing()

    for _, d in ipairs(tornadoList) do
        local label = (cfg.Selected == d.name) and (">> " .. d.name .. " <<") or d.name
        TS:Button(label, function()
            cfg.TargetMode = "manual"
            cfg.Selected   = d.name
            notify("Target: " .. d.name, "", 3)
        end)
    end
    TS:Spacing()

    local CS = tab:Section("Config", "Left")
    CS:SliderInt("farm_front",  "Front Distance (studs)", 10, 500, cfg.FrontOffset,  function(v) cfg.FrontOffset  = v end)
    CS:SliderInt("farm_height", "Height Offset (studs)", -300, 150, cfg.HeightOffset, function(v) cfg.HeightOffset = v end)
    CS:SliderInt("farm_speed",  "Move Speed (studs/s)",   50, 800, cfg.Speed,        function(v) cfg.Speed        = v end)
    CS:SliderInt("farm_safe",   "Safe Radius (studs)",    30, 2000, cfg.SafeRadius,  function(v) cfg.SafeRadius   = v end)
    CS:SliderInt("smart_wind",  "Smart Wind Priority",     0, 100, cfg.WindPriority, function(v) cfg.WindPriority = v end)
    CS:Spacing()
    CS:Toggle("show_hud", "Status HUD", cfg.ShowHUD, function(state)
        cfg.ShowHUD = state
        if not state then hudLabel.Visible = false end
    end)
    CS:Spacing()
    CS:Toggle("show_compass", "Tornado Compass", cfg.ShowCompass, function(state)
        cfg.ShowCompass = state
        if not state then compassArrow.Visible = false; compassText.Visible = false end
    end)
    CS:Spacing()
    CS:Button("Save Config", function() saveConfig() end)

    local PS = tab:Section("Probes", "Right")
    PS:Text("Press a probe key to fly to it (press again to cancel)")
    PS:Spacing()
    PS:Toggle("auto_collect", "Auto Collect Probes", cfg.AutoCollect, function(state)
        setCollect(state)
    end)
    collectKb = PS:Keybind("collect_kb", cfg.CollectKeyVK, "toggle")
    collectKb:AddToHotkey("Auto Collect", "auto_collect")
    PS:Spacing()
    PS:SliderInt("probe_count", "Probe Count", 1, 4, cfg.ProbeCount, function(v)
        cfg.ProbeCount = v
    end)
    PS:SliderInt("collect_cd", "Collect Revisit (s)", 0, 120, cfg.CollectCooldown, function(v)
        cfg.CollectCooldown = v
    end)
    PS:SliderFloat("collect_hold", "Collect Hold E (s)", 0.5, 10, cfg.CollectHold, "%.1f", function(v)
        cfg.CollectHold = v
    end)
    PS:Spacing()

    PS:Toggle("auto_cycle", "Auto Farm (place+collect+repeat)", cfg.AutoCycle, function(state)
        setCycle(state)
    end)
    cycleKb = PS:Keybind("cycle_kb", cfg.CycleKeyVK, "toggle")
    cycleKb:AddToHotkey("Auto Farm", "auto_cycle")
    PS:SliderFloat("place_hold", "Place Hold M1 (s)", 0.5, 12, cfg.PlaceHold, "%.1f", function(v)
        cfg.PlaceHold = v
    end)
    PS:SliderInt("wind_thresh", "Min Winds to Place", 0, 200, cfg.WindThreshold, function(v)
        cfg.WindThreshold = v
    end)
    PS:Spacing()

    for i = 1, cfg.ProbeCount do
        PS:Text("Probe #" .. i)
        probeKeyWidgets[i] = PS:Keybind("probe_kb_" .. i, cfg.ProbeVK[i], "hold")
        PS:Spacing()
    end

    PS:Button("List My Probes", function()
        print("[AutoFarm] myUserId = " .. tostring(myUserId))
        local pr = workspace:FindFirstChild("player_related")
        if not pr then
            print("[AutoFarm] workspace.player_related NOT FOUND")
            notify("player_related not found", "Check console", 3); return
        end
        print("[AutoFarm] player_related children:")
        for _, c in ipairs(pr:GetChildren()) do
            print(string.format("    %s : %s", c.Name, c.ClassName))
        end

        local pfold = pr:FindFirstChild("probes")
        if not pfold then
            print("[AutoFarm] player_related.probes NOT FOUND")
            notify("Probes folder not found", "Check console", 3); return
        end

        local kids = pfold:GetChildren()
        print(string.format("[AutoFarm] probes has %d direct child(ren):", #kids))
        for _, c in ipairs(kids) do
            local hasMesh = c:FindFirstChild("mesh") and "mesh" or "no-mesh"
            print(string.format("    %s : %s  [%s] mine=%s",
                c.Name, c.ClassName, hasMesh, tostring(isMineName(c.Name))))
        end

        local desc = pfold:GetDescendants()
        local descModels = 0
        for _, d in ipairs(desc) do
            if d:IsA("Model") then descModels = descModels + 1 end
        end
        print(string.format("[AutoFarm] probes GetDescendants: %d total, %d Model(s)", #desc, descModels))

        local mine = collectMyProbes(pfold)
        print(string.format("[AutoFarm] collectMyProbes found %d mine", #mine))
        for _, p in ipairs(mine) do
            local part = resolveProbePart(p)
            print(string.format("    mine: %s  part=%s", p.Name, part and part.Name or "nil"))
        end

        local list = getProbesSorted()
        if #list == 0 then notify("No probes found", "Check console", 3); return end
        for i, e in ipairs(list) do
            print(string.format("[AutoFarm] #%d %s | %.0fm%s | %.0f %.0f %.0f",
                i, e.name or "?", e.dist, e.blocked and " [in tornado]" or "", e.pos.X, e.pos.Y, e.pos.Z))
        end
        notify(#list .. " probe(s) listed", "Check console", 3)
    end)
end)

RunService.RenderStepped:Connect(function()
    if not isrbxactive() then return end

    for i = 1, 4 do
        local kb = probeKeyWidgets[i]
        if kb and i <= cfg.ProbeCount then
            local cur = kb:IsEnabled()
            if cur and not probeKeyPrev[i] and not cycleActive then goToProbe(i) end
            probeKeyPrev[i] = cur
        end
    end

    if cycleKb then
        local kbState = cycleKb:IsEnabled()
        if kbState ~= _cycleKbPrev then
            _cycleKbPrev = kbState
            UI.SetValue("auto_cycle", kbState)
            setCycle(kbState)
        end
    end

    if not cycleActive and cfg.AutoCycle then
        cfg.AutoCycle = false
        UI.SetValue("auto_cycle", false)
    end

    if collectKb then
        local kbState = collectKb:IsEnabled()
        if kbState ~= _collectKbPrev then
            _collectKbPrev = kbState
            UI.SetValue("auto_collect", kbState)
            setCollect(kbState)
        end
    end

    if not collectActive and cfg.AutoCollect then
        cfg.AutoCollect = false
        UI.SetValue("auto_collect", false)
    end

    updateHud()

    local nowC = tick()
    if nowC - lastCompass >= 0.05 then
        lastCompass = nowC
        updateCompass()
    end
end)

task.spawn(function()
    while true do
        task.wait(2)
        if isrbxactive() then
            local prev = #tornadoList
            scanTornadoes()
            if #tornadoList ~= prev then
                notify("Tornadoes updated: " .. #tornadoList, "", 3)
            end
        end
    end
end)

notify("Auto Farm loaded", "Twisted", 3)
