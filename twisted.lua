-- =============================================
-- Storm Tracker — Tornado + Probe ESP + Freeze
-- =============================================

local RunService  = game:GetService("RunService")
local Players     = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- =============================================
-- FEATURE TOGGLES
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
}

-- =============================================
-- SAVE / LOAD CONFIG
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

    notify("Config saved", "", 3)
    printl("[Config] Saved")
end

local function loadConfig()
    local function getBool(key, default)
        local v = UI.GetValue(key)
        if v == nil then return default end
        return v == "1" or v == true
    end

    FeatureConfig.TornadoESP.Visible  = getBool("cfg_TornadoESP", false)
    FeatureConfig.ProbeESP.Visible    = getBool("cfg_ProbeESP",   false)

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

    printl("[Config] Loaded")
end

-- =============================================
-- ESP STORAGE
-- =============================================

local tornadoESPs = {}
local probeESPs   = {}

local prevPos   = {}
local prevTime  = {}
local moveVec   = {}
local speedBufs = {}
local sizeCache = {}

local SPEED_BUF_MAX  = 10
local SPEED_INTERVAL = 0.5

local frameCount           = 0
local PROBE_REFRESH_FRAMES = 12
local probeSlotCounter     = 0
local TORNADO_BOX_FRAMES   = 3

-- =============================================
-- FREEZE
-- =============================================

local freeze = { chassis = nil, lockedCF = nil, active = false }

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
    local ok, cf = pcall(function() return ch.CFrame end)
    if not ok then return end
    freeze.chassis  = ch
    freeze.lockedCF = cf
    freeze.active   = true
    printl("[Freeze] Car ON")
end

local function releaseCarFreeze()
    freeze.chassis  = nil
    freeze.lockedCF = nil
    freeze.active   = false
    printl("[Freeze] Car OFF")
end

-- =============================================
-- DRAWING
-- =============================================

local function newText(color, size)
    local t = Drawing.new("Text")
    t.Color=color; t.Size=size; t.Center=true
    t.Outline=true; t.Visible=false; t.Text=""
    return t
end

local function newSquare(color, thickness, w, h)
    local b = Drawing.new("Square")
    b.Color=color; b.Thickness=thickness; b.Filled=false
    b.Visible=false; b.Size=Vector2.new(w or 0, h or 0)
    b.Position=Vector2.new(0, 0)
    return b
end

local function newCircle(color, radius)
    local c = Drawing.new("Circle")
    c.Color=color; c.Radius=radius; c.Thickness=2
    c.NumSides=32; c.Filled=true; c.Visible=false
    return c
end

local function newLine(color, thickness)
    local l = Drawing.new("Line")
    l.Color=color; l.Thickness=thickness; l.Visible=false
    return l
end

-- =============================================
-- WIND SPEED
-- =============================================

local WIND_ATTRS = {"WindSpeed","windspeed","wind_speed","Speed","speed","Intensity","intensity","EF","EFRating"}

local function readWindAttr(storm)
    local targets = {storm, storm:FindFirstChild("rotation")}
    for _, obj in ipairs(targets) do
        if obj and obj.GetAttribute then
            for _, a in ipairs(WIND_ATTRS) do
                local ok, v = pcall(function() return obj:GetAttribute(a) end)
                if ok and type(v)=="number" and v>0 then
                    return v>50 and v or v*2.237
                end
            end
        end
    end
    return nil
end

local function sampleSpeed(key, pos)
    local now = tick()
    if not speedBufs[key] then speedBufs[key]={s={},lp=pos,lt=now}; return end
    local b=speedBufs[key]; local dt=now-b.lt
    if dt<SPEED_INTERVAL then return end
    local dx,dz=pos.X-b.lp.X, pos.Z-b.lp.Z
    local mph=math.sqrt(dx*dx+dz*dz)/dt*0.627
    local s=b.s; s[#s+1]=mph
    if #s>SPEED_BUF_MAX then table.remove(s,1) end
    b.lp=pos; b.lt=now
end

local function getSpeed(key)
    local b=speedBufs[key]
    if not b or #b.s==0 then return 0 end
    local tw,ws=0,0
    for i,v in ipairs(b.s) do ws=ws+v*i; tw=tw+i end
    return ws/tw
end

local function getDir(key, pos)
    local now=tick()
    if not prevPos[key] then prevPos[key]=pos; prevTime[key]=now; return nil end
    local mov=pos-prevPos[key]; local dt=now-prevTime[key]
    prevPos[key]=pos; prevTime[key]=now
    local mag=mov.Magnitude
    if dt>0 and mag>0.01 then
        local nd=mov/mag; local old=moveVec[key]
        moveVec[key]=old and (old*0.3+nd*0.7).Unit or nd
    end
    return moveVec[key]
end

-- =============================================
-- TORNADO ESP
-- =============================================

local function hideTornado(e)
    e.text.Visible=false; e.box.Visible=false
    e.circle.Visible=false; e.line.Visible=false
end

local function updateTornado(key, entry, playerPos, frame)
    if not FeatureConfig.TornadoESP.Visible then hideTornado(entry.esp); return end
    local part=entry.part
    if not part or not part.Parent then return end
    local ok,pos=pcall(function() return part.Position end)
    if not ok then hideTornado(entry.esp); return end

    sampleSpeed(key, pos)
    local scr,onScr=WorldToScreen(pos)
    if not onScr then hideTornado(entry.esp); return end

    local esp=entry.esp; local cfg=FeatureConfig.Tornado
    local dist=(playerPos-pos).Magnitude

    if not entry.lastBoxFrame or (frame-entry.lastBoxFrame)>=TORNADO_BOX_FRAMES then
        entry.lastBoxFrame=frame
        if not sizeCache[key] then
            local ok2,sz=pcall(function() return part.Size end)
            sizeCache[key]=ok2 and sz or Vector3.new(60,120,60)
        end
        local sz=sizeCache[key]
        if cfg.ShowBox then
            local tSc,tOn=WorldToScreen(pos+Vector3.new(0,    sz.Y/2,0))
            local bSc,bOn=WorldToScreen(pos-Vector3.new(0,    sz.Y/2,0))
            local lSc,lOn=WorldToScreen(pos-Vector3.new(sz.X/2,0,   0))
            local rSc,rOn=WorldToScreen(pos+Vector3.new(sz.X/2,0,   0))
            if tOn and bOn and lOn and rOn then
                local h=math.max(math.abs(tSc.Y-bSc.Y),20)
                local w=math.max(math.abs(rSc.X-lSc.X),20)
                esp.box.Size=Vector2.new(w,h)
                esp.box.Position=Vector2.new(scr.X-w/2,tSc.Y)
            else
                esp.box.Size=Vector2.new(60,120)
                esp.box.Position=Vector2.new(scr.X-30,scr.Y-60)
            end
            esp.box.Visible=true
        else
            esp.box.Visible=false
        end
    end

    local wind=readWindAttr(entry.stormModel) or getSpeed(key)
    esp.text.Text=string.format("TORNADO [%dm] | %.1f mph",math.floor(dist),wind)
    esp.text.Position=Vector2.new(scr.X,scr.Y-42)
    esp.text.Visible=true

    local dir=getDir(key,pos)
    if dir and (cfg.ShowLine or cfg.ShowCircle) then
        local tgt=pos+Vector3.new(dir.X*1000,dir.Y*500,dir.Z*1000)
        local tScr,tOn2=WorldToScreen(tgt)
        if tOn2 then
            esp.circle.Position=Vector2.new(tScr.X,tScr.Y)
            esp.circle.Visible=cfg.ShowCircle
            esp.line.From=Vector2.new(scr.X,scr.Y)
            esp.line.To=Vector2.new(tScr.X,tScr.Y)
            esp.line.Visible=cfg.ShowLine
            return
        end
    end
    esp.circle.Visible=false; esp.line.Visible=false
end

-- =============================================
-- PROBE ESP
-- =============================================

local function hideProbe(e)
    e.box.Visible=false; e.text.Visible=false
end

local function updateProbe(entry, playerPos, frame)
    if not FeatureConfig.ProbeESP.Visible then hideProbe(entry.esp); return end
    local part=entry.part
    if not part or not part.Parent then return end
    local esp=entry.esp

    if entry.cachedScr==nil or (frame%PROBE_REFRESH_FRAMES==entry.frameSlot) then
        local ok,pos=pcall(function() return part.Position end)
        if not ok then hideProbe(esp); return end
        local scr,onScr=WorldToScreen(pos)
        if not onScr then entry.cachedScr=nil; hideProbe(esp); return end
        entry.cachedScr=scr
        entry.cachedDist=(playerPos-pos).Magnitude
    end

    if not entry.cachedScr then hideProbe(esp); return end
    local scr=entry.cachedScr
    esp.box.Position=Vector2.new(scr.X-25,scr.Y-25)
    esp.box.Visible=true
    esp.text.Text=string.format("PROBE [%dm]",math.floor(entry.cachedDist))
    esp.text.Position=Vector2.new(scr.X,scr.Y-35)
    esp.text.Visible=true
end

-- =============================================
-- CLEANUP
-- =============================================

local function removeTornado(key)
    if not tornadoESPs[key] then return end
    local e=tornadoESPs[key].esp
    pcall(function() e.text:Remove();e.box:Remove();e.circle:Remove();e.line:Remove() end)
    tornadoESPs[key]=nil; prevPos[key]=nil; prevTime[key]=nil
    moveVec[key]=nil; speedBufs[key]=nil; sizeCache[key]=nil
end

local function removeProbe(probeModel)
    if not probeESPs[probeModel] then return end
    pcall(function()
        probeESPs[probeModel].esp.box:Remove()
        probeESPs[probeModel].esp.text:Remove()
    end)
    probeESPs[probeModel]=nil
end

-- =============================================
-- COLOR SYNC
-- =============================================

local function syncTornadoColors()
    local cfg=FeatureConfig.Tornado
    for _,e in pairs(tornadoESPs) do
        e.esp.box.Color=cfg.BoxColor; e.esp.line.Color=cfg.LineColor
        e.esp.circle.Color=cfg.CircleColor; e.esp.text.Color=cfg.TextColor
    end
end

local function syncProbeColors()
    local cfg=FeatureConfig.Probe
    for _,e in pairs(probeESPs) do
        e.esp.box.Color=cfg.BoxColor; e.esp.text.Color=cfg.TextColor
    end
end

-- =============================================
-- SCAN
-- =============================================

local function scanTornadoes()
    local sr=workspace:FindFirstChild("storm_related")
    local storms=sr and sr:FindFirstChild("storms")
    if not storms then return end
    local alive={}
    for _,storm in ipairs(storms:GetChildren()) do
        if storm:IsA("Model") then
            local rot=storm:FindFirstChild("rotation")
            local ts=rot and rot:FindFirstChild("tornado_scan")
            if ts and ts:IsA("BasePart") then
                local key=storm.Name; alive[key]=true
                if not tornadoESPs[key] then
                    local cfg=FeatureConfig.Tornado
                    tornadoESPs[key]={
                        part=ts, stormModel=storm, lastBoxFrame=0,
                        esp={
                            text  =newText(cfg.TextColor,18),
                            box   =newSquare(cfg.BoxColor,1),
                            circle=newCircle(cfg.CircleColor,10),
                            line  =newLine(cfg.LineColor,2),
                        }
                    }
                    printl("[ESP] Tornado: "..key)
                else
                    tornadoESPs[key].part=ts
                    tornadoESPs[key].stormModel=storm
                end
            end
        end
    end
    for key in pairs(tornadoESPs) do
        if not alive[key] then removeTornado(key) end
    end
end

local function findProbePart(probe)
    local cam=probe:FindFirstChild("camera")
    if cam and cam:IsA("BasePart") then return cam end
    local pp=probe:FindFirstChild("PromptPart")
    if pp and pp:IsA("BasePart") then return pp end
    for _,c in ipairs(probe:GetChildren()) do
        if c:IsA("BasePart") then return c end
    end
    return nil
end

local function scanProbes()
    local pr=workspace:FindFirstChild("player_related")
    local pfold=pr and pr:FindFirstChild("probes")
    if not pfold then return end
    local alive={}
    for _,probe in ipairs(pfold:GetChildren()) do
        if probe:IsA("Model") then
            alive[probe]=true
            if not probeESPs[probe] then
                local part=findProbePart(probe)
                if part then
                    local cfg=FeatureConfig.Probe
                    probeESPs[probe]={
                        part=part,
                        frameSlot=probeSlotCounter%PROBE_REFRESH_FRAMES,
                        cachedScr=nil, cachedDist=0,
                        esp={
                            box =newSquare(cfg.BoxColor,2,50,50),
                            text=newText(cfg.TextColor,16),
                        }
                    }
                    probeSlotCounter=probeSlotCounter+1
                    printl("[ESP] Probe detected")
                end
            end
        end
    end
    for probeModel in pairs(probeESPs) do
        if not alive[probeModel] then removeProbe(probeModel) end
    end
end

-- =============================================
-- UI
-- =============================================

local function BuildESP(Tab)
    local S=Tab:Section("ESP","Left")
    S:Toggle("TornadoESP","Tornado ESP",FeatureConfig.TornadoESP.Visible,function(state)
        FeatureConfig.TornadoESP.Visible=state
        notify(state and "Tornado ESP enabled" or "Tornado ESP disabled","",3)
        if not state then for _,e in pairs(tornadoESPs) do hideTornado(e.esp) end end
    end)
    S:Spacing()
    S:Toggle("ProbeESP","Probe ESP",FeatureConfig.ProbeESP.Visible,function(state)
        FeatureConfig.ProbeESP.Visible=state
        notify(state and "Probe ESP enabled" or "Probe ESP disabled","",3)
        if not state then for _,e in pairs(probeESPs) do hideProbe(e.esp) end end
    end)
    S:Spacing()
    S:Text("For fullbright, enable Custom Time = 12.00")
    S:Spacing()
    S:Button("Save Config",function() saveConfig() end)
end

local function BuildTornadoCustom(Tab)
    local S=Tab:Section("Tornado Customization","Left")
    S:Toggle("TornadoBox","Box",FeatureConfig.Tornado.ShowBox,function(state)
        FeatureConfig.Tornado.ShowBox=state
        if not state then for _,e in pairs(tornadoESPs) do e.esp.box.Visible=false end end
    end)
    S:ColorPicker("TornadoBoxColor",1,0,0,1,function(c)
        FeatureConfig.Tornado.BoxColor=c; syncTornadoColors()
    end)
    S:Spacing()
    S:Toggle("TornadoLine","Direction Line",FeatureConfig.Tornado.ShowLine,function(state)
        FeatureConfig.Tornado.ShowLine=state
        if not state then for _,e in pairs(tornadoESPs) do e.esp.line.Visible=false end end
    end)
    S:ColorPicker("TornadoLineColor",1,1,0,1,function(c)
        FeatureConfig.Tornado.LineColor=c; syncTornadoColors()
    end)
    S:Spacing()
    S:Toggle("TornadoCircle","Direction Circle",FeatureConfig.Tornado.ShowCircle,function(state)
        FeatureConfig.Tornado.ShowCircle=state
        if not state then for _,e in pairs(tornadoESPs) do e.esp.circle.Visible=false end end
    end)
    S:ColorPicker("TornadoCircleColor",0,1,1,1,function(c)
        FeatureConfig.Tornado.CircleColor=c; syncTornadoColors()
    end)
    S:Spacing()
    S:Text("Name / Distance Label")
    S:ColorPicker("TornadoTextColor",1,0,0,1,function(c)
        FeatureConfig.Tornado.TextColor=c; syncTornadoColors()
    end)
end

local function BuildProbeCustom(Tab)
    local S=Tab:Section("Probe Customization","Right")
    S:Text("Box Color")
    S:ColorPicker("ProbeBoxColor",0,1,1,1,function(c)
        FeatureConfig.Probe.BoxColor=c; syncProbeColors()
    end)
    S:Spacing()
    S:Text("Name / Distance Label Color")
    S:ColorPicker("ProbeTextColor",0,1,1,1,function(c)
        FeatureConfig.Probe.TextColor=c; syncProbeColors()
    end)
end

local function BuildFreeze(Tab)
    local S=Tab:Section("Anti-Sling / Freeze","Right")
    S:Text("Prevents being flung by the tornado")
    S:Spacing()
    S:Toggle("CarFreeze","Car Freeze",false,function(state)
        FeatureConfig.CarFreeze.Enabled=state
        if state then applyCarFreeze() else releaseCarFreeze() end
        notify(state and "Car Freeze ON" or "Car Freeze OFF","",3)
    end)
    S:Spacing()
    S:Toggle("CharFreeze","Character Freeze",false,function(state)
        FeatureConfig.CharacterFreeze.Enabled=state
        notify(state and "Character Freeze ON" or "Character Freeze OFF","",3)
    end)
    S:Spacing()
    S:Tip("Car Freeze locks chassis CFrame every frame. Tornado cannot move it.")
end

local function BuildDebug(Tab)
    local S=Tab:Section("Debug","Left")
    S:Button("Active Tornadoes",function()
        local sr=workspace:FindFirstChild("storm_related")
        local storms=sr and sr:FindFirstChild("storms")
        if not storms then printl("[Debug] No storms"); return end
        local list=storms:GetChildren()
        printl("[Debug] Tornadoes: "..#list)
        for _,storm in ipairs(list) do
            if storm:IsA("Model") then
                local rot=storm:FindFirstChild("rotation")
                local ts=rot and rot:FindFirstChild("tornado_scan")
                if ts then
                    local p=ts.Position
                    local wind=readWindAttr(storm) or getSpeed(storm.Name)
                    printl(string.format("  %s | %.0f,%.0f,%.0f | %.1f mph",storm.Name,p.X,p.Y,p.Z,wind))
                end
            end
        end
    end)
    S:Spacing()
    S:Button("Active Probes",function()
        local pr=workspace:FindFirstChild("player_related")
        local pfold=pr and pr:FindFirstChild("probes")
        if not pfold then printl("[Debug] No probes"); return end
        local list=pfold:GetChildren()
        printl("[Debug] Probes: "..#list)
        local char=LocalPlayer.Character
        local hrp=char and char:FindFirstChild("HumanoidRootPart")
        for _,probe in ipairs(list) do
            if probe:IsA("Model") then
                local cam=probe:FindFirstChild("camera")
                if cam and hrp then
                    local d=(cam.Position-hrp.Position).Magnitude
                    local p=cam.Position
                    printl(string.format("  ID:%s | %.0f,%.0f,%.0f | %.0fm",probe.Name,p.X,p.Y,p.Z,d))
                end
            end
        end
    end)
end

local function InitTab()
    loadConfig()
    UI.AddTab("Storm Tracker",function(tab)
        BuildESP(tab)
        BuildTornadoCustom(tab)
        BuildProbeCustom(tab)
        BuildFreeze(tab)
        BuildDebug(tab)
    end)
    FeatureConfig.CarFreeze.Enabled       = false
    FeatureConfig.CharacterFreeze.Enabled = false
end

InitTab()

-- =============================================
-- LOOPS
-- =============================================

printl("[Storm Tracker] Loaded")

wait(2)

-- =============================================
-- FIX: Verify properties before using them
-- =============================================
local function safeSetVelocity(part)
    if not part or not part:IsA("BasePart") then return end
    
    -- Check which properties exist
    local hasAssemblyLin, _ = pcall(function() return part.AssemblyLinearVelocity end)
    local hasAssemblyAng, _ = pcall(function() return part.AssemblyAngularVelocity end)
    local hasVelocity, _ = pcall(function() return part.Velocity end)
    local hasRotVelocity, _ = pcall(function() return part.RotVelocity end)
    
    -- Apply CFrame first
    pcall(function()
        if part.CFrame then
            -- CFrame is already set outside
        end
    end)
    
    -- Apply velocities based on availability
    if hasAssemblyLin then
        pcall(function() part.AssemblyLinearVelocity = Vector3.zero end)
    elseif hasVelocity then
        pcall(function() part.Velocity = Vector3.zero end)
    end
    
    if hasAssemblyAng then
        pcall(function() part.AssemblyAngularVelocity = Vector3.zero end)
    elseif hasRotVelocity then
        pcall(function() part.RotVelocity = Vector3.zero end)
    end
end

RunService.RenderStepped:Connect(function()
    if not isrbxactive() then return end

    if FeatureConfig.CarFreeze.Enabled then
        if freeze.active then
            local ch=freeze.chassis
            if ch and ch.Parent then
                pcall(function()
                    ch.CFrame = freeze.lockedCF
                end)
                safeSetVelocity(ch)
            else
                freeze.active=false; applyCarFreeze()
            end
        else
            applyCarFreeze()
        end
    end

    if FeatureConfig.CharacterFreeze.Enabled then
        local char=LocalPlayer.Character
        if char then
            local hrp=char:FindFirstChild("HumanoidRootPart")
            if hrp then
                safeSetVelocity(hrp)
            end
        end
    end
end)

RunService.Heartbeat:Connect(function()
    if not isrbxactive() then return end
    frameCount=frameCount+1
    if frameCount%2==0 then return end

    local char=LocalPlayer.Character
    local hrp=char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local playerPos=hrp.Position

    for key,entry in pairs(tornadoESPs) do
        if entry.part and entry.part.Parent then
            updateTornado(key,entry,playerPos,frameCount)
        else removeTornado(key) end
    end

    for probeModel,entry in pairs(probeESPs) do
        if entry.part and entry.part.Parent then
            updateProbe(entry,playerPos,frameCount)
        else removeProbe(probeModel) end
    end
end)

task.spawn(function()
    while true do
        if isrbxactive() then
            scanTornadoes()
            scanProbes()
        end
        task.wait(1)
    end
end)
