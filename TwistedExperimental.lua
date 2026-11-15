local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Http = game:GetService("HttpService")
local player = Players.LocalPlayer
local userId = tostring(player.UserId)
if type(_G.StormTrackerCleanup) == "function" then
    pcall(_G.StormTrackerCleanup)
end
UI.RemoveTab("Storm Tracker")
UI.RemoveTab("Storm Tracker 2")

local function log(message)
    print("[Storm Tracker] " .. message)
end

local function alert(message, seconds)
    notify(message, "Storm Tracker", seconds or 2)
end

local function getOffsets()
    local body = httpget("https://offsets.imtheo.lol/offsets.json")
    assert(type(body) == "string" and #body > 0, "Empty offsets response")
    local json = Http:JSONDecode(body)
    assert(type(json) == "table" and type(json.Offsets) == "table", "Invalid offsets payload")
    local o = json.Offsets
    assert(o.BasePart and o.Primitive and o.Workspace and o.World, "Missing offsets groups")
    for _, offset in ipairs({
        o.BasePart.Primitive, o.Primitive.Rotation, o.Primitive.Position,
        o.Primitive.AssemblyLinearVelocity, o.Primitive.AssemblyAngularVelocity,
        o.Workspace.World, o.World.Gravity
    }) do
        assert(type(offset) == "number" and offset >= 0, "Invalid memory offset")
    end
    return o
end

local okOffsets, offsets = pcall(getOffsets)
if not okOffsets then
    log("Offsets unavailable: " .. tostring(offsets))
    alert("Offsets unavailable. See console.", 4)
    return
end

local OFF = {
    primitive = offsets.BasePart.Primitive,
    position = offsets.Primitive.Position,
    rotation = offsets.Primitive.Rotation,
    linear = offsets.Primitive.AssemblyLinearVelocity,
    angular = offsets.Primitive.AssemblyAngularVelocity,
    world = offsets.Workspace.World,
    gravity = offsets.World.Gravity
}

local cfg = {
    TornadoESP = {Visible = false},
    ProbeESP = {Visible = false},
    SpeedHUD = {Visible = false},
    MaxESPDist = 5000,
    Tornado = {
        BoxScale = 1,
        ShowBox = true, ShowLine = true, ShowCircle = true, ShowText = true,
        BoxColor = Color3.new(1, 0, 0), LineColor = Color3.new(1, 1, 0),
        CircleColor = Color3.new(0, 1, 1), TextColor = Color3.new(1, 0, 0)
    },
    Probe = {
        BoxScale = 1, ShowBox = true, ShowText = true,
        BoxColor = Color3.new(0, 1, 1), TextColor = Color3.new(0, 1, 1)
    },
    CarBoost = {Enabled = false, Force = 50000, LatDamp = 0.5, KeyVK = 0x05},
    CarBrake = {Enabled = false, Force = 5000, KeyVK = 0x58},
    CarFreeze = {Enabled = false, Soft = false, KeyVK = 0x4B},
    CharacterFreeze = {Enabled = false, KeyVK = 0x4C},
    CharBoost = {Enabled = false, Force = 30000, KeyVK = 0x47},
    Tween = {Enabled = false, Speed = 120, Height = 0.5, Offset = 30, KeyVK = 0x54},
    Performance = {
        ESPHz = 15, FarESPHz = 5, FarDistance = 1200,
        BoxHz = 6, ScanMs = 1250, HUDHz = 8
    }
}

local CONFIG_PATH = "storm_tracker_cfg.json"
local settings = {
    {"TornadoESP", cfg.TornadoESP, "Visible", "boolean"},
    {"ProbeESP", cfg.ProbeESP, "Visible", "boolean"},
    {"SpeedHUD", cfg.SpeedHUD, "Visible", "boolean"},
    {"MaxESPDist", cfg, "MaxESPDist", "number", 100, 500000},
    {"T_BoxScale", cfg.Tornado, "BoxScale", "number", 0.25, 4},
    {"P_BoxScale", cfg.Probe, "BoxScale", "number", 0.25, 4},
    {"T_Box", cfg.Tornado, "ShowBox", "boolean"},
    {"T_Line", cfg.Tornado, "ShowLine", "boolean"},
    {"T_Circle", cfg.Tornado, "ShowCircle", "boolean"},
    {"T_Text", cfg.Tornado, "ShowText", "boolean"},
    {"P_Box", cfg.Probe, "ShowBox", "boolean"},
    {"P_Text", cfg.Probe, "ShowText", "boolean"},
    {"TBoxC", cfg.Tornado, "BoxColor", "color"},
    {"TLineC", cfg.Tornado, "LineColor", "color"},
    {"TCircleC", cfg.Tornado, "CircleColor", "color"},
    {"TTextC", cfg.Tornado, "TextColor", "color"},
    {"PBoxC", cfg.Probe, "BoxColor", "color"},
    {"PTextC", cfg.Probe, "TextColor", "color"},
    {"CarBoost", cfg.CarBoost, "Enabled", "boolean"},
    {"CarBrake", cfg.CarBrake, "Enabled", "boolean"},
    {"CarFreeze", cfg.CarFreeze, "Enabled", "boolean"},
    {"CarFreezeSoft", cfg.CarFreeze, "Soft", "boolean"},
    {"CharFreeze", cfg.CharacterFreeze, "Enabled", "boolean"},
    {"CharBoost", cfg.CharBoost, "Enabled", "boolean"},
    {"TweenEnabled", cfg.Tween, "Enabled", "boolean"},
    {"BoostForce", cfg.CarBoost, "Force", "number", 5000, 500000},
    {"BrakeForce", cfg.CarBrake, "Force", "number", 100, 100000},
    {"CharBoostForce", cfg.CharBoost, "Force", "number", 5000, 200000},
    {"LatDamp", cfg.CarBoost, "LatDamp", "number", 0, 1},
    {"TweenSpeed", cfg.Tween, "Speed", "number", 50, 500},
    {"TweenHeight", cfg.Tween, "Height", "number", 0.1, 2},
    {"TweenOffset", cfg.Tween, "Offset", "number", 10, 200},
    {"PerfESPRate", cfg.Performance, "ESPHz", "number", 5, 30},
    {"PerfFarRate", cfg.Performance, "FarESPHz", "number", 2, 15},
    {"PerfFarDist", cfg.Performance, "FarDistance", "number", 300, 10000},
    {"PerfBoxRate", cfg.Performance, "BoxHz", "number", 2, 20},
    {"PerfScanMs", cfg.Performance, "ScanMs", "number", 500, 5000},
    {"PerfHUDRate", cfg.Performance, "HUDHz", "number", 2, 20}
}

local keyFields = {
    {"BoostKB", cfg.CarBoost}, {"BrakeKB", cfg.CarBrake},
    {"CarFrzKB", cfg.CarFreeze}, {"CharFrzKB", cfg.CharacterFreeze},
    {"CharBoostKB", cfg.CharBoost}, {"TweenKB", cfg.Tween}
}
local widgets, uiBindings = {}, {}
local syncConfigFromUI

local function loadConfig()
    if not isfile(CONFIG_PATH) then return end
    local ok, data = pcall(function()
        return Http:JSONDecode(readfile(CONFIG_PATH))
    end)
    if not ok or type(data) ~= "table" then
        log("Saved config could not be decoded")
        return
    end

    for _, field in ipairs(settings) do
        local key, parent, name, expected, min, max = unpack(field)
        local value = data[key]
        if expected == "color" then
            if type(value) == "table" then
                local old = parent[name]
                parent[name] = Color3.new(
                    math.clamp(tonumber(value[1]) or old.R, 0, 1),
                    math.clamp(tonumber(value[2]) or old.G, 0, 1),
                    math.clamp(tonumber(value[3]) or old.B, 0, 1)
                )
            end
        elseif expected == "boolean" then
            if type(value) == "boolean" then parent[name] = value end
        elseif type(value) == "number" and value == value and value < math.huge and value > -math.huge then
            parent[name] = math.clamp(value, min or -math.huge, max or math.huge)
        end
    end
    for _, field in ipairs(keyFields) do
        local value = data[field[1]]
        if type(value) == "number" and value >= 0 and value <= 255 then
            field[2].KeyVK = value
        end
    end
end

local function saveConfig()
    if syncConfigFromUI then syncConfigFromUI() end
    local data = {}
    for _, field in ipairs(settings) do
        local value = field[2][field[3]]
        if field[4] == "color" then
            value = {value.R, value.G, value.B}
        end
        data[field[1]] = value
    end
    for _, field in ipairs(keyFields) do
        local key, parent = field[1], field[2]
        local widget = widgets[key]
        local value = widget and widget:GetKey() or parent.KeyVK
        if type(value) ~= "number" then value = parent.KeyVK end
        data[key] = value
        parent.KeyVK = value
    end
    local ok, err = pcall(function()
        writefile(CONFIG_PATH, Http:JSONEncode(data))
    end)
    if ok then
        alert("Configuration saved", 3)
    else
        log("Save failed: " .. tostring(err))
        alert("Failed to save config", 3)
    end
end

loadConfig()
local function readPointer(part)
    if not part or not part.Parent then return nil end
    local ok, address = pcall(memory_read, "uintptr_t", part.Address + OFF.primitive)
    if ok and type(address) == "number" and address > 0 then return address end
end

local function readVector(address)
    return Vector3.new(
        memory_read("float", address),
        memory_read("float", address + 4),
        memory_read("float", address + 8)
    )
end

local function writeVector(address, vector)
    memory_write("float", address, vector.X)
    memory_write("float", address + 4, vector.Y)
    memory_write("float", address + 8, vector.Z)
end

local ZERO = Vector3.new(0, 0, 0)
local function zeroVelocity(primitive, angular)
    writeVector(primitive + OFF.linear, ZERO)
    if angular then writeVector(primitive + OFF.angular, ZERO) end
end

local function getWorldPointer()
    local ok, address = pcall(memory_read, "uintptr_t", workspace.Address + OFF.world)
    if ok and type(address) == "number" and address > 0 then return address end
end

local function getGravity()
    local world = getWorldPointer()
    if world then
        local ok, gravity = pcall(memory_read, "float", world + OFF.gravity)
        if ok and type(gravity) == "number" and gravity > 0 and gravity < 1000 then
            return gravity
        end
    end
end

local function setGravity(value)
    local world = getWorldPointer()
    if not world then return false end
    local ok = pcall(memory_write, "float", world + OFF.gravity, value)
    return ok
end

local function getRoot()
    local character = player.Character
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function getHumanoid()
    local character = player.Character
    return character and character:FindFirstChild("Humanoid")
end
local car = {owner = nil, chassis = nil, primitive = nil, nextSearch = 0}
local function getCarOwner()
    local related = workspace:FindFirstChild("player_related")
    local cars = related and related:FindFirstChild("cars")
    return cars and cars:FindFirstChild(userId)
end

local function getChassis()
    if car.owner and car.chassis and car.owner:IsDescendantOf(workspace)
        and car.chassis:IsDescendantOf(car.owner) then
        return car.chassis
    end
    local now = tick()
    if now < car.nextSearch then return nil end
    car.nextSearch = now + 0.4
    local owner = getCarOwner()
    if not owner then
        car.owner, car.chassis, car.primitive = nil, nil, nil
        return nil
    end
    car.owner, car.chassis, car.primitive = owner, nil, nil
    for _, desc in ipairs(owner:GetDescendants()) do
        if desc.Name == "chassis" and desc:IsA("BasePart") then
            car.chassis = desc
            return desc
        end
    end
end

local function getCarPrimitive()
    local chassis = getChassis()
    if not chassis then return nil end
    if not car.primitive then car.primitive = readPointer(chassis) end
    return car.primitive
end

local function findProbePart(probe)
    if not probe or not probe:IsA("Model") then return nil end
    local mesh = probe:FindFirstChild("mesh")
    if not mesh then return nil end
    local base, meshPart
    for _, child in ipairs(mesh:GetChildren()) do
        if child:IsA("MeshPart") then
            if child.Name:find("Tower Probe_Cylinder", 1, true) then return child end
            meshPart = meshPart or child
        elseif child:IsA("BasePart") then
            base = base or child
        end
    end
    return meshPart or base
end

local function isMyProbe(model)
    return model:IsA("Model") and (model.Name == userId or
        (userId ~= "0" and model.Name:find(userId, 1, true) ~= nil))
end
local drawings = {}
local storms, probes = {}, {}
local scanSequence = {storm = 0, probe = 0}
local paletteVersion = {storm = 0, probe = 0}
local stats = {stormScans = 0, probeScans = 0, espTicks = 0, projects = 0, uiSyncs = 0, started = tick()}
local uiSyncInterval = 0.25
local WIND_ATTRS = {"WindSpeed", "windspeed", "wind_speed", "Speed", "speed", "Intensity", "intensity", "EF", "EFRating"}

local function createDrawing(shape, properties)
    local draw = Drawing.new(shape)
    for key, value in pairs(properties) do draw[key] = value end
    draw.Visible = false
    return draw
end

local function getDrawing(key, tornado)
    local entry = drawings[key]
    if entry then return entry end
    entry = {
        box = createDrawing("Square", {Filled = false, Transparency = 1}),
        text = createDrawing("Text", {Center = true, Outline = true, Font = 2, Size = 14, Transparency = 1})
    }
    if tornado then
        entry.line = createDrawing("Line", {Thickness = 2, Transparency = 1})
        entry.circle = createDrawing("Circle", {Radius = 10, Thickness = 2, NumSides = 32, Transparency = 1})
    end
    entry.paletteVersion = -1
    entry.hidden = true
    drawings[key] = entry
    return entry
end

local function hideDrawing(entry)
    if not entry or entry.hidden then return end
    for _, name in ipairs({"box", "text", "line", "circle"}) do
        if entry[name] then entry[name].Visible = false end
    end
    entry.hidden = true
end

local function removeDrawing(key)
    local entry = drawings[key]
    if not entry then return end
    for _, name in ipairs({"box", "text", "line", "circle"}) do
        if entry[name] then entry[name]:Remove() end
    end
    drawings[key] = nil
end

local function hideGroup(group)
    for key in pairs(group) do hideDrawing(drawings[key]) end
end

local function removeRecord(group, key)
    removeDrawing(key)
    group[key] = nil
end

local function scanStorms()
    stats.stormScans = stats.stormScans + 1
    scanSequence.storm = scanSequence.storm + 1
    local generation = scanSequence.storm
    local related = workspace:FindFirstChild("storm_related")
    local folder = related and related:FindFirstChild("storms")
    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            if model:IsA("Model") then
                local rotation = model:FindFirstChild("rotation")
                local part = rotation and rotation:FindFirstChild("tornado_scan")
                if part and part:IsA("BasePart") then
                    local key = "storm:" .. tostring(part.Address)
                    local record = storms[key]
                    if record then
                        if record.part ~= part then
                            record.nextVisual, record.nextBox = 0, 0
                        end
                        record.part, record.model, record.seen = part, model, generation
                    else
                        storms[key] = {part = part, model = model, seen = generation}
                        log("Tornado detected: " .. model.Name)
                    end
                end
            end
        end
    end
    for key, record in pairs(storms) do
        if record.seen ~= generation or not record.part:IsDescendantOf(workspace) then
            removeRecord(storms, key)
        end
    end
end

local function scanProbes()
    stats.probeScans = stats.probeScans + 1
    scanSequence.probe = scanSequence.probe + 1
    local generation = scanSequence.probe
    local related = workspace:FindFirstChild("player_related")
    local folder = related and related:FindFirstChild("probes")
    if folder then
        for _, model in ipairs(folder:GetChildren()) do
            if isMyProbe(model) then
                local key = "probe:" .. tostring(model.Address)
                local record = probes[key]
                if record and record.model == model and record.part:IsDescendantOf(workspace) then
                    record.seen = generation
                else
                    local part = findProbePart(model)
                    if part then
                        if record then
                            record.model, record.part, record.seen = model, part, generation
                            record.nextVisual = 0
                        else
                            probes[key] = {model = model, part = part, seen = generation}
                            log("Probe detected: " .. model.Name)
                        end
                    end
                end
            end
        end
    end
    for key, record in pairs(probes) do
        if record.seen ~= generation or not record.part:IsDescendantOf(workspace) then
            removeRecord(probes, key)
        end
    end
end

local function windSpeed(model)
    if not model then return nil end
    local rotation = model:FindFirstChild("rotation")
    for index = 1, 2 do
        local object = index == 1 and model or rotation
        if object then
            for _, attr in ipairs(WIND_ATTRS) do
                local value = object:GetAttribute(attr)
                if type(value) == "number" and value > 0 then
                    return value > 50 and value or value * 2.237
                end
            end
        end
    end
end

local function updateMotion(record, pos, now)
    if not record.motionPos then
        record.motionPos, record.speedPos, record.speedAt = pos, pos, now
        record.speed = 0
        return
    end
    local movement = pos - record.motionPos
    if movement.Magnitude > 0.01 then
        local direction = movement.Unit
        local old = record.direction
        local blended = old and (old * 0.3 + direction * 0.7) or direction
        if blended.Magnitude > 0.0001 then record.direction = blended.Unit end
    end
    record.motionPos = pos
    local elapsed = now - record.speedAt
    if elapsed >= 0.5 then
        local delta = pos - record.speedPos
        local mph = math.sqrt(delta.X * delta.X + delta.Z * delta.Z) / elapsed * 0.627
        record.speed = record.speed and (record.speed * 0.6 + mph * 0.4) or mph
        record.speedPos, record.speedAt = pos, now
    end
end

local function project(pos)
    stats.projects = stats.projects + 1
    local screen, onScreen = WorldToScreen(pos)
    if onScreen then return screen end
end

local function screenEntity(key, record, playerPos, tornado, now)
    if record.nextVisual and now < record.nextVisual then return end
    local part = record.part
    local entry = drawings[key]
    if not part or not part:IsDescendantOf(workspace) then
        hideDrawing(entry)
        record.nextVisual = now + 0.3
        return
    end
    local pos = part.Position
    local distance = (pos - playerPos).Magnitude
    local perf = cfg.Performance
    local rate = distance > perf.FarDistance and math.min(perf.ESPHz, perf.FarESPHz) or perf.ESPHz
    record.nextVisual = now + 1 / rate
    if distance > cfg.MaxESPDist then
        hideDrawing(entry)
        return
    end
    local style = tornado and cfg.Tornado or cfg.Probe
    if tornado then updateMotion(record, pos, now) end
    local center = project(pos)
    if not center then
        hideDrawing(entry)
        return
    end
    if not (style.ShowBox or style.ShowText or (tornado and (style.ShowLine or style.ShowCircle))) then
        hideDrawing(entry)
        return
    end
    entry = getDrawing(key, tornado)
    entry.hidden = false
    local entityType = tornado and "storm" or "probe"
    if entry.paletteVersion ~= paletteVersion[entityType] then
        entry.box.Color, entry.text.Color = style.BoxColor, style.TextColor
        if tornado then
            entry.line.Color, entry.circle.Color = style.LineColor, style.CircleColor
        end
        entry.paletteVersion = paletteVersion[entityType]
    end
    local scale = math.clamp(1000 / math.max(distance, 1), 0.3, 2)
    local boxSize = math.floor(50 * scale * style.BoxScale)
    entry.box.Visible = style.ShowBox
    if style.ShowBox then
        local width, height, topOffset = boxSize, boxSize, -boxSize / 2
        if tornado then
            if not record.nextBox or now >= record.nextBox or not record.boxWidth then
                record.nextBox = now + 1 / perf.BoxHz
                local size = part.Size
                local high = project(pos + Vector3.new(0, size.Y / 2, 0))
                local low = project(pos - Vector3.new(0, size.Y / 2, 0))
                local left = project(pos - Vector3.new(size.X / 2, 0, 0))
                local right = project(pos + Vector3.new(size.X / 2, 0, 0))
                if high and low and left and right then
                    record.boxWidth = math.max(math.abs(right.X - left.X), 20)
                    record.boxHeight = math.max(math.abs(high.Y - low.Y), 20)
                    record.boxTopOffset = high.Y - center.Y
                else
                    record.boxWidth, record.boxHeight, record.boxTopOffset = 60, 120, -60
                end
            end
            width = record.boxWidth * style.BoxScale
            height = record.boxHeight * style.BoxScale
            topOffset = record.boxTopOffset + (record.boxHeight - height) / 2
        end
        entry.box.Size = Vector2.new(width, height)
        entry.box.Position = Vector2.new(center.X - width / 2, center.Y + topOffset)
    end
    entry.text.Visible = style.ShowText
    if style.ShowText then
        if tornado and (not record.nextWind or now >= record.nextWind) then
            record.wind = windSpeed(record.model)
            record.nextWind = now + 1
        end
        entry.text.Text = tornado
            and string.format("TORNADO [%dm] | %.1f mph", math.floor(distance), record.wind or record.speed or 0)
            or string.format("PROBE [%dm]", math.floor(distance))
        entry.text.Position = Vector2.new(center.X, tornado and center.Y - 46 or center.Y - boxSize / 2 - 15)
    end
    if not tornado then return end
    entry.line.Visible, entry.circle.Visible = false, false
    if not record.direction or not (style.ShowLine or style.ShowCircle) then return end
    local direction = record.direction
    local target = pos + Vector3.new(direction.X * 1000, direction.Y * 500, direction.Z * 1000)
    local projected = project(target)
    if not projected then return end
    if style.ShowLine then
        entry.line.From, entry.line.To = center, projected
        entry.line.Visible = true
    end
    if style.ShowCircle then
        entry.circle.Position = projected
        entry.circle.Visible = true
    end
end

local function updateESP(playerPos, now)
    stats.espTicks = stats.espTicks + 1
    if cfg.TornadoESP.Visible then
        for key, record in pairs(storms) do screenEntity(key, record, playerPos, true, now) end
    end
    if cfg.ProbeESP.Visible then
        for key, record in pairs(probes) do screenEntity(key, record, playerPos, false, now) end
    end
end

local speedText = createDrawing("Text", {
    Center = true, Outline = true, Font = 2, Size = 16,
    Transparency = 1, Color = Color3.new(1, 1, 1)
})

local function updateSpeedHUD()
    if not cfg.SpeedHUD.Visible then
        speedText.Visible = false
        return
    end
    speedText.Visible = false
    local primitive = getCarPrimitive()
    local camera = workspace.CurrentCamera
    if not primitive or not camera then return end
    local velocity = readVector(primitive + OFF.linear)
    speedText.Text = string.format("%d st/s", math.floor(math.sqrt(velocity.X ^ 2 + velocity.Z ^ 2)))
    speedText.Position = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y - 60)
    speedText.Visible = true
end
local locks = {car = {}, character = {}}
local function readRotation(primitive)
    local rotation = {}
    for i = 1, 9 do
        rotation[i] = memory_read("float", primitive + OFF.rotation + (i - 1) * 4)
    end
    return rotation
end

local function writeRotation(primitive, rotation)
    for i = 1, 9 do
        memory_write("float", primitive + OFF.rotation + (i - 1) * 4, rotation[i])
    end
end

local function freezeStep(state, part, soft, withRotation)
    if not part or not part:IsDescendantOf(workspace) then
        state.part, state.primitive = nil, nil
        return
    end
    if state.part ~= part then
        local primitive = readPointer(part)
        if not primitive then return end
        state.part, state.primitive = part, primitive
        state.position = readVector(primitive + OFF.position)
        state.rotation = withRotation and readRotation(primitive) or nil
    end
    if soft then
        zeroVelocity(state.primitive, withRotation)
    else
        writeVector(state.primitive + OFF.position, state.position)
        if state.rotation then writeRotation(state.primitive, state.rotation) end
        zeroVelocity(state.primitive, withRotation)
    end
end

local function updateLock(state, enabled, part, soft, rotate)
    if not enabled then
        if state.part then state.part, state.primitive = nil, nil end
        return
    end
    freezeStep(state, part, soft, rotate)
end

local function applyBoost()
    local primitive = getCarPrimitive()
    local chassis = car.chassis
    if not primitive or not chassis then return end
    local look, right = chassis.CFrame.LookVector, chassis.CFrame.RightVector
    local velocity = readVector(primitive + OFF.linear)
    local maxSpeed = cfg.CarBoost.Force * 0.016
    local forward = velocity.X * look.X + velocity.Z * look.Z
    local gap = math.max(0, maxSpeed - forward)
    local acceleration = gap * (0.3 + 0.5 * gap / (maxSpeed + 1))
    local lateral = velocity.X * right.X + velocity.Z * right.Z
    local vx = velocity.X + look.X * acceleration - right.X * lateral * cfg.CarBoost.LatDamp
    local vz = velocity.Z + look.Z * acceleration - right.Z * lateral * cfg.CarBoost.LatDamp
    local speed = math.sqrt(vx * vx + vz * vz)
    if speed > maxSpeed then
        vx, vz = vx * maxSpeed / speed, vz * maxSpeed / speed
    end
    writeVector(primitive + OFF.linear, Vector3.new(vx, velocity.Y, vz))
    writeVector(primitive + OFF.angular, ZERO)
end
local function applyBrake(dt)
    local primitive = getCarPrimitive()
    if not primitive then return false end
    local velocity = readVector(primitive + OFF.linear)
    local elapsed = math.clamp(dt or (1 / 60), 1 / 240, 0.1)
    local strength = cfg.CarBrake.Force / 5000
    local factor = math.exp(-160 * strength * elapsed)
    local stopped = Vector3.new(
        math.abs(velocity.X * factor) < 1 and 0 or velocity.X * factor,
        math.abs(velocity.Y) < 1 and 0 or velocity.Y,
        math.abs(velocity.Z * factor) < 1 and 0 or velocity.Z * factor
    )
    if cfg.CarBrake.Force >= 30000 then stopped = ZERO end
    writeVector(primitive + OFF.linear, stopped)
    writeVector(primitive + OFF.angular, ZERO)
    return true
end

local characterPrimitive = {part = nil, address = nil}
local function applyCharacterBoost(dt)
    local root, camera = getRoot(), workspace.CurrentCamera
    if not root or not camera then return end
    local delta = root.Position - camera.Position
    local length = math.sqrt(delta.X ^ 2 + delta.Z ^ 2)
    if length < 0.01 then return end
    local forward = Vector3.new(delta.X / length, 0, delta.Z / length)
    local right = Vector3.new(-forward.Z, 0, forward.X)
    local movement = ZERO
    if iskeypressed(0x57) then movement = movement + forward end
    if iskeypressed(0x53) then movement = movement - forward end
    if iskeypressed(0x41) then movement = movement - right end
    if iskeypressed(0x44) then movement = movement + right end
    if movement.Magnitude < 0.01 then return end
    if characterPrimitive.part ~= root then
        characterPrimitive.part, characterPrimitive.address = root, readPointer(root)
    end
    local primitive = characterPrimitive.address
    if not primitive then return end
    local shift = movement.Unit * (cfg.CharBoost.Force * 0.016 * math.min(dt, 0.1))
    local position = primitive + OFF.position
    memory_write("float", position, memory_read("float", position) + shift.X)
    memory_write("float", position + 8, memory_read("float", position + 8) + shift.Z)
    writeVector(primitive + OFF.linear, ZERO)
end
local travel = {active = false, generation = 0}
local running = true

local function stopTravel(arrived)
    if not travel.active then return end
    travel.active = false
    travel.generation = travel.generation + 1
    if travel.gravity then setGravity(travel.gravity) end
    if travel.humanoid and travel.humanoid.Parent then
        travel.humanoid.PlatformStand = travel.platformStand
    end
    local root = getRoot()
    if root then
        local primitive = readPointer(root)
        if primitive then zeroVelocity(primitive, false) end
    end
    travel.gravity, travel.humanoid, travel.platformStand = nil, nil, nil
    if arrived then alert("Arrived!", 2) end
end

local function startTravel(target, probe)
    if travel.active then stopTravel(false) end
    local root = getRoot()
    if not root then alert("No character", 2); return end
    local humanoid = getHumanoid()
    travel.active, travel.generation = true, travel.generation + 1
    travel.gravity = getGravity()
    travel.humanoid, travel.platformStand = humanoid, humanoid and humanoid.PlatformStand or false
    if travel.gravity then setGravity(10) end
    if humanoid then humanoid.PlatformStand = true end

    local token = travel.generation
    local startedAt = tick()
    local arriveAt = probe and 5 or 10
    local slowAt = probe and 30 or 40
    task.spawn(function()
        while running and travel.active and travel.generation == token do
            if tick() - startedAt >= 60 then
                log("Travel timed out")
                stopTravel(false)
                break
            end
            local current = getRoot()
            if not current then stopTravel(false); break end
            local diff = target - current.Position
            local horizontal = math.sqrt(diff.X ^ 2 + diff.Z ^ 2)
            if horizontal < arriveAt then
                if probe then
                    local primitive = readPointer(current)
                    if primitive then writeVector(primitive + OFF.position, target) end
                end
                stopTravel(true)
                break
            end
            local speed = cfg.Tween.Speed
            if horizontal < slowAt then
                speed = math.max(12, speed * horizontal / slowAt)
            end
            local direction = diff.Unit
            current.AssemblyLinearVelocity = Vector3.new(
                direction.X * speed, direction.Y * speed * cfg.Tween.Height, direction.Z * speed
            )
            task.wait(1 / 30)
        end
    end)
end

local function toggleTravel()
    if travel.active then
        stopTravel(false)
        alert("Travel cancelled")
        return true
    end
    return false
end

local function goToNearestTornado()
    if toggleTravel() then return end
    local root = getRoot()
    if not root then alert("No character"); return end
    scanStorms()
    local origin, closest, nearest = root.Position, math.huge, nil
    for _, record in pairs(storms) do
        local pos = record.part.Position
        local distance = (pos - origin).Magnitude
        if distance < closest then closest, nearest = distance, pos end
    end
    if not nearest then alert("No tornado found"); return end
    local delta = origin - nearest
    local horizontal = Vector3.new(delta.X, 0, delta.Z)
    local offset = horizontal.Magnitude > 0 and horizontal.Unit * cfg.Tween.Offset
        or Vector3.new(cfg.Tween.Offset, 0, 0)
    alert(string.format("Going: %dm", math.floor(closest)), 3)
    startTravel(nearest + offset, false)
end

local function sortedProbes(origin)
    scanProbes()
    local list = {}
    for _, record in pairs(probes) do
        local pos = record.part.Position
        list[#list + 1] = {pos = pos, dist = (origin - pos).Magnitude}
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    return list
end

local function goToProbeByRank(rank)
    if toggleTravel() then return end
    local root = getRoot()
    if not root then alert("No character"); return end
    local list = sortedProbes(root.Position)
    if #list == 0 then alert("No probes found for " .. userId, 3); return end
    local item = list[math.min(rank, #list)]
    alert(string.format("Going to probe #%d | %.0fm", rank, item.dist), 3)
    startTravel(item.pos, true)
end

local function listProbes()
    local root = getRoot()
    if not root then log("No character"); return end
    local list = sortedProbes(root.Position)
    log(string.format("%d probe(s) for %s", #list, userId))
    for index, item in ipairs(list) do
        local pos = item.pos
        print(string.format("  #%d | %.0fm | %.0f, %.0f, %.0f", index, item.dist, pos.X, pos.Y, pos.Z))
    end
end

local function countKeys(tbl)
    local count = 0
    for _ in pairs(tbl) do count = count + 1 end
    return count
end
local function bindUI(id, object, property, kind)
    if not uiBindings[id] then
        uiBindings[id] = {object = object, property = property, kind = kind}
    end
end

local function applyUIValue(id, binding, value)
    local kind = binding.kind
    if kind == "color" then
        if typeof(value) ~= "Color3" then return end
        local old = binding.object[binding.property]
        if old.R == value.R and old.G == value.G and old.B == value.B then return end
        binding.object[binding.property] = value
        local bucket = binding.object == cfg.Tornado and "storm" or "probe"
        paletteVersion[bucket] = paletteVersion[bucket] + 1
        return
    end
    if kind == "boolean" then
        if type(value) ~= "boolean" then return end
    elseif type(value) ~= "number" or value ~= value then
        return
    end
    if binding.object[binding.property] == value then return end
    binding.object[binding.property] = value
    if id == "TornadoESP" and not value then hideGroup(storms) end
    if id == "ProbeESP" and not value then hideGroup(probes) end
    if id == "SpeedHUD" and not value then speedText.Visible = false end
end

syncConfigFromUI = function()
    stats.uiSyncs = stats.uiSyncs + 1
    for id, binding in pairs(uiBindings) do
        local ok, value = pcall(UI.GetValue, id)
        if ok then applyUIValue(id, binding, value) end
    end
end
local function toggle(section, id, label, object, property, message, callback)
    bindUI(id, object, property, "boolean")
    return section:Toggle(id, label, object[property], function(value)
        applyUIValue(id, uiBindings[id], value)
        if message then alert(message .. (value and " ON" or " OFF")) end
        if callback then callback(value) end
    end)
end

local function slider(section, id, label, object, property, minimum, maximum, format)
    bindUI(id, object, property, "number")
    local callback = function(value) applyUIValue(id, uiBindings[id], value) end
    if format then
        return section:SliderFloat(id, label, minimum, maximum, object[property], format, callback)
    end
    return section:SliderInt(id, label, minimum, maximum, object[property], callback)
end

local function colorPicker(section, id, object, property)
    bindUI(id, object, property, "color")
    local c = object[property]
    section:ColorPicker(id, c.R, c.G, c.B, 1, function(value)
        applyUIValue(id, uiBindings[id], value)
    end)
end

local function hotkey(section, id, record, mode, label, toggleId, saveId)
    local widget = section:Keybind(id, record.KeyVK, mode)
    widget:AddToHotkey(label, toggleId)
    widgets[saveId] = widget
    return widget
end

local function buildESP(tab)
    local s = tab:Section("ESP", "Left")
    toggle(s, "TornadoESP", "Tornado ESP", cfg.TornadoESP, "Visible", "Tornado ESP", function(value)
        if value then scanStorms() else hideGroup(storms) end
    end)
    toggle(s, "ProbeESP", "Probe ESP", cfg.ProbeESP, "Visible", "Probe ESP", function(value)
        if value then scanProbes() else hideGroup(probes) end
    end)
    s:Text("For fullbright, enable Custom Time = 12.00")
    toggle(s, "SpeedHUD", "Speed HUD", cfg.SpeedHUD, "Visible", nil, function(value)
        if not value then speedText.Visible = false end
    end)
    slider(s, "MaxESPDist", "Max Render Distance (m)", cfg, "MaxESPDist", 100, 500000)
    s:Tip("Applies immediately to both Tornado and Probe ESP")
    s:Button("Save Config", saveConfig)
end

local function buildTornadoColors(tab)
    local s = tab:Section("Tornado Customization", "Left")
    local t = cfg.Tornado
    toggle(s, "TornadoBox", "Box", t, "ShowBox", nil, function(value)
        if not value then
            for key in pairs(storms) do
                local entry = drawings[key]
                if entry then entry.box.Visible = false end
            end
        end
    end)
    colorPicker(s, "TornadoBoxColor", t, "BoxColor")
    slider(s, "TornadoBoxScale", "Box Scale", t, "BoxScale", 0.25, 4, "%.2f")
    s:Spacing()
    toggle(s, "TornadoLine", "Direction Line", t, "ShowLine")
    colorPicker(s, "TornadoLineColor", t, "LineColor")
    s:Spacing()
    toggle(s, "TornadoCircle", "Direction Circle", t, "ShowCircle")
    colorPicker(s, "TornadoCircleColor", t, "CircleColor")
    s:Spacing()
    toggle(s, "TornadoShowText", "Name / Distance Label", t, "ShowText")
    colorPicker(s, "TornadoTextColor", t, "TextColor")
end

local function buildProbeColors(tab)
    local s = tab:Section("Probe Customization", "Left")
    local p = cfg.Probe
    toggle(s, "ProbeShowBox", "Box", p, "ShowBox")
    colorPicker(s, "ProbeBoxColor", p, "BoxColor")
    slider(s, "ProbeBoxScale", "Box Scale", p, "BoxScale", 0.25, 4, "%.2f")
    s:Spacing()
    toggle(s, "ProbeShowText", "Name / Distance Label", p, "ShowText")
    colorPicker(s, "ProbeTextColor", p, "TextColor")
end

local function buildPerformance(tab)
    local s = tab:Section("Experimental Performance", "Right")
    s:Text("Lower values reduce ESP CPU usage, but updates may look less smooth")
    local p = cfg.Performance
    slider(s, "PerfESP", "Nearby ESP Hz", p, "ESPHz", 5, 30)
    slider(s, "PerfFar", "Far ESP Hz", p, "FarESPHz", 2, 15)
    slider(s, "PerfFarDistance", "Far Distance (m)", p, "FarDistance", 300, 10000)
    slider(s, "PerfBox", "Tornado Box Hz", p, "BoxHz", 2, 20)
    slider(s, "PerfScan", "World Scan Interval (ms)", p, "ScanMs", 500, 5000)
    slider(s, "PerfHUD", "Speed HUD Hz", p, "HUDHz", 2, 20)
    s:Tip("Vehicle and freeze controls still run every active game frame")
    s:Button("Performance Stats", function()
        local elapsed = math.max(0.01, tick() - stats.started)
        log(string.format("Performance (%.0fs): tornado scans=%d probe scans=%d esp ticks=%d projections=%d ui syncs=%d",
            elapsed, stats.stormScans, stats.probeScans, stats.espTicks, stats.projects, stats.uiSyncs))
        log(string.format("Rates /s: scans=%.2f esp=%.2f projection=%.2f ui=%.2f",
            (stats.stormScans + stats.probeScans) / elapsed, stats.espTicks / elapsed,
            stats.projects / elapsed, stats.uiSyncs / elapsed))
        alert("Performance counters printed to console", 3)
    end)
end

local function buildCarBoost(tab)
    local s = tab:Section("Car Boost", "Left")
    s:Text("Hold keybind to boost forward")
    toggle(s, "boost_on", "Car Boost", cfg.CarBoost, "Enabled", "Car Boost")
    hotkey(s, "boost_kb", cfg.CarBoost, "hold", "Car Boost", "boost_on", "BoostKB")
    s:Text("5k=gentle  150k=normal  500k=rocket")
    slider(s, "boost_force", "Force Amount", cfg.CarBoost, "Force", 5000, 500000)
    s:Text("0=no damping  0.5=normal  1=locked")
    slider(s, "lat_damp", "Wind Resistance", cfg.CarBoost, "LatDamp", 0, 1, "%.2f")
    s:Tip("Works with trucks and large chassis. Must be seated.")
end

local function buildCarBrake(tab)
    local s = tab:Section("Super Brake", "Left")
    s:Text("Hold keybind to brake")
    toggle(s, "brake_on", "Super Brake", cfg.CarBrake, "Enabled", "Brake")
    hotkey(s, "brake_kb", cfg.CarBrake, "hold", "Super Brake", "brake_on", "BrakeKB")
    s:Text("100=gentle  5k=normal  100k=instant")
    slider(s, "brake_force", "Brake Force", cfg.CarBrake, "Force", 100, 100000)
    s:Tip("Hold X by default. The car's chassis and current offsets must be available.")
    s:Button("Test Brake (1 sec)", function()
        if not getCarPrimitive() then
            alert("Vehicle chassis / primitive not found", 3)
            log("Brake test: no car primitive for user " .. userId)
            return
        end
        local started = tick()
        task.spawn(function()
            while running and tick() - started < 1 do
                applyBrake(1 / 60)
                task.wait(1 / 60)
            end
            log("Brake test completed")
        end)
        alert("Brake test started", 2)
    end)
end

local function buildTween(tab)
    local s = tab:Section("Tween to Tornado", "Right")
    toggle(s, "TweenEnabled", "Tween to Tornado", cfg.Tween, "Enabled", "Tween to Tornado")
    hotkey(s, "tween_kb", cfg.Tween, "hold", "Tween to Tornado", "TweenEnabled", "TweenKB")
    s:Text("Fly to tornado position. Press again to cancel.")
    slider(s, "TweenSpeed", "Speed (studs/s)", cfg.Tween, "Speed", 50, 500)
    slider(s, "TweenHeight", "Height Multiplier", cfg.Tween, "Height", 0.1, 2, "%.1f")
    slider(s, "TweenOffset", "Stop Distance (studs)", cfg.Tween, "Offset", 10, 200)
    s:Button("Go to Nearest Tornado", goToNearestTornado)
end

local function buildProbeTween(tab)
    local s = tab:Section("Tween to Probe", "Right")
    s:Text("Your probes are named after your userId: " .. userId)
    s:Text("Uses the same speed / height as tornado travel")
    s:Button("Go to Nearest Probe", function() goToProbeByRank(1) end)
    s:Button("Go to 2nd Closest Probe", function() goToProbeByRank(2) end)
    s:Button("Go to 3rd Closest Probe", function() goToProbeByRank(3) end)
    s:Button("List My Probes", listProbes)
end

local function buildCharacterBoost(tab)
    local s = tab:Section("Character Boost", "Left")
    s:Text("Hold keybind to boost on foot (WASD)")
    toggle(s, "charboost_on", "Character Boost", cfg.CharBoost, "Enabled", "Character Boost")
    hotkey(s, "charboost_kb", cfg.CharBoost, "hold", "Character Boost", "charboost_on", "CharBoostKB")
    s:Text("5k=gentle  30k=normal  200k=fast")
    slider(s, "charboost_force", "Force Amount", cfg.CharBoost, "Force", 5000, 200000)
    s:Tip("Boosts on foot using the camera direction.")
end

local function buildFreeze(tab)
    local s = tab:Section("Anti-Sling / Freeze", "Right")
    s:Text("Prevents being flung by the tornado")
    toggle(s, "CarFreeze", "Car Freeze", cfg.CarFreeze, "Enabled", "Car Freeze")
    hotkey(s, "carfreeze_kb", cfg.CarFreeze, "toggle", "Car Freeze", "CarFreeze", "CarFrzKB")
    toggle(s, "CarFreezeSoft", "Soft (anti-fling)", cfg.CarFreeze, "Soft")
    toggle(s, "CharFreeze", "Character Freeze", cfg.CharacterFreeze, "Enabled", "Character Freeze")
    hotkey(s, "charfreeze_kb", cfg.CharacterFreeze, "toggle", "Character Freeze", "CharFreeze", "CharFrzKB")
    s:Tip("Hard lock pins the chassis pose; soft freeze zeroes velocity.")
end

local function buildDebug(tab)
    local s = tab:Section("Debug", "Left")
    s:Button("Rescan Tornadoes", function()
        local before = countKeys(storms)
        scanStorms()
        local after = countKeys(storms)
        log(string.format("Rescan: %d -> %d tornadoes", before, after))
        alert(string.format("Rescanned: %d tornado(s)", after), 3)
    end)
    s:Button("Active Tornadoes", function()
        log(string.format("Tornadoes tracked: %d", countKeys(storms)))
        for key, record in pairs(storms) do
            local pos = record.part.Position
            local wind = windSpeed(record.model) or record.speed or 0
            print(string.format("  %s | %.0f,%.0f,%.0f | %.1f mph", key, pos.X, pos.Y, pos.Z, wind))
        end
    end)
    s:Button("Clear All Probe ESPs", function()
        for key in pairs(probes) do removeRecord(probes, key) end
        scanProbes()
        log("Probe ESPs cleared and rescanned")
    end)
    s:Button("Inspect ESP Settings", function()
        syncConfigFromUI()
        log(string.format("ESP visible: tornado=%s probe=%s | max=%.0f",
            tostring(cfg.TornadoESP.Visible), tostring(cfg.ProbeESP.Visible), cfg.MaxESPDist))
        log(string.format("Tornado box=%s scale=%.2f line=%s circle=%s | Probe box=%s scale=%.2f",
            tostring(cfg.Tornado.ShowBox), cfg.Tornado.BoxScale,
            tostring(cfg.Tornado.ShowLine), tostring(cfg.Tornado.ShowCircle),
            tostring(cfg.Probe.ShowBox), cfg.Probe.BoxScale))
        alert("ESP settings printed to console", 3)
    end)
    s:Button("Inspect Car Physics", function()
        local owner, chassis = getCarOwner(), getChassis()
        local primitive = getCarPrimitive()
        log("Car model: " .. (owner and owner.Name or "missing"))
        log("Chassis: " .. (chassis and chassis.Name or "missing"))
        log("Primitive: " .. (primitive and tostring(primitive) or "missing"))
        if primitive then
            local velocity = readVector(primitive + OFF.linear)
            log(string.format("Linear velocity: %.2f, %.2f, %.2f | Brake toggle: %s",
                velocity.X, velocity.Y, velocity.Z, tostring(cfg.CarBrake.Enabled)))
        end
        alert("Car physics printed to console", 3)
    end)
    s:Button("Active Probes", function()
        local root = getRoot()
        local origin = root and root.Position
        local count = 0
        for key, record in pairs(probes) do
            local part = record.part
            if part and part:IsDescendantOf(workspace) then
                local distance = origin and (part.Position - origin).Magnitude or 0
                print(string.format("  %s | %.0fm", key, distance))
                count = count + 1
            end
        end
        log(string.format("Total probes: %d", count))
    end)
end

UI.AddTab("Storm Tracker", function(tab)
    buildESP(tab)
    buildTornadoColors(tab)
    buildProbeColors(tab)
    buildPerformance(tab)
    buildCarBoost(tab)
    buildCarBrake(tab)
    buildTween(tab)
    buildProbeTween(tab)
    buildFreeze(tab)
    buildDebug(tab)
end)
UI.AddTab("Storm Tracker 2", buildCharacterBoost)

local connections = {}
local lastScan, lastESP, lastHUD, lastUISync = 0, 0, 0, 0
local previous = {carFreeze = false, charFreeze = false, tween = false}

local function keyActive(setting, key)
    if not setting.Enabled then return false end
    local widget = widgets[key]
    if widget and widget:IsEnabled() then return true end
    local mode = widget and widget:GetType() or "hold"
    local vk = widget and widget:GetKey() or setting.KeyVK
    return mode == "hold" and type(vk) == "number" and vk > 0 and iskeypressed(vk)
end

local function updateHotkeyStates(dt)
    local carOn = keyActive(cfg.CarFreeze, "CarFrzKB")
    local charOn = keyActive(cfg.CharacterFreeze, "CharFrzKB")
    if carOn ~= previous.carFreeze then
        previous.carFreeze = carOn
        alert(carOn and "Car Freeze ON" or "Car Freeze OFF", 3)
    end
    if charOn ~= previous.charFreeze then
        previous.charFreeze = charOn
        alert(charOn and "Character Freeze ON" or "Character Freeze OFF", 3)
    end
    updateLock(locks.car, carOn, carOn and getChassis() or nil, cfg.CarFreeze.Soft, true)
    updateLock(locks.character, charOn, charOn and getRoot() or nil, false, false)
    if keyActive(cfg.CarBoost, "BoostKB") then applyBoost() end
    if keyActive(cfg.CarBrake, "BrakeKB") then applyBrake(dt) end
    if keyActive(cfg.CharBoost, "CharBoostKB") then applyCharacterBoost(dt) end
    local tweenOn = keyActive(cfg.Tween, "TweenKB")
    if tweenOn and not previous.tween then goToNearestTornado() end
    previous.tween = tweenOn
end

local function cleanup()
    if not running then return end
    running = false
    stopTravel(false)
    for _, connection in ipairs(connections) do connection:Disconnect() end
    for key in pairs(drawings) do removeDrawing(key) end
    speedText:Remove()
    for _, widget in pairs(widgets) do
        if widget.RemoveFromHotkey then widget:RemoveFromHotkey() end
    end
    UI.RemoveTab("Storm Tracker")
    UI.RemoveTab("Storm Tracker 2")
    if _G.StormTrackerCleanup == cleanup then _G.StormTrackerCleanup = nil end
    log("Cleaned up")
end
_G.StormTrackerCleanup = cleanup

connections[#connections + 1] = RunService.Heartbeat:Connect(function(dt)
    if not running or not isrbxactive() then return end
    local now = tick()
    if now - lastUISync >= uiSyncInterval then
        lastUISync = now
        syncConfigFromUI()
    end
    updateHotkeyStates(dt)
    if now - lastScan >= cfg.Performance.ScanMs / 1000 then
        lastScan = now
        if cfg.TornadoESP.Visible then scanStorms() end
        if cfg.ProbeESP.Visible then scanProbes() end
    end
    if (cfg.TornadoESP.Visible or cfg.ProbeESP.Visible) and
        now - lastESP >= 1 / cfg.Performance.ESPHz then
        lastESP = now
        local root = getRoot()
        if root then
            updateESP(root.Position, now)
        else
            hideGroup(storms)
            hideGroup(probes)
        end
    end
    if cfg.SpeedHUD.Visible and now - lastHUD >= 1 / cfg.Performance.HUDHz then
        lastHUD = now
        updateSpeedHUD()
    end
end)

log("Loaded successfully for user " .. userId)
