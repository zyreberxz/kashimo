-- ============================================================
-- KASHIMO HAJIME — STAR RAGE
-- Jujutsu Shenanigans | Solara / Synapse X Compatible
-- Upload raw to GitHub, loadstring the URL
-- ============================================================

local Players         = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService      = game:GetService("RunService")
local TweenService    = game:GetService("TweenService")
local Debris          = game:GetService("Debris")

local player    = Players.LocalPlayer
local mouse     = player:GetMouse()
local character = player.Character or player.CharacterAdded:Wait()
local humanoid  = character:WaitForChild("Humanoid")
local rootPart  = character:WaitForChild("HumanoidRootPart")

-- ============================================================
-- CONFIG
-- ============================================================
local CFG = {
    -- Colors
    CoreColor       = Color3.fromRGB(255, 230, 60),
    ArcColor        = Color3.fromRGB(200, 100, 255),
    BurstColor      = Color3.fromRGB(255, 255, 180),

    -- Ranges
    StrikeRange     = 20,
    StarfallRange   = 40,
    NovaRange       = 30,
    AtlasRange      = 50,

    -- Damage
    StrikeDmg       = 32,
    StrikeDmgM2     = 20,
    StarfallDmg     = 55,
    NovaDmg         = 38,
    AtlasDmg        = 120,
    PassiveDmg      = 8,

    -- Cooldowns (seconds)
    M1CD            = 0.55,
    M2CD            = 1.1,
    StarfallCD      = 14,
    NovaCD          = 28,
    AtlasCD         = 90,

    -- Mobility
    DashSpeed       = 160,
    DashDuration    = 0.16,

    -- Passive: Electromagnetic Body
    PassiveInterval = 1.8,
    PassiveRange    = 10,

    -- Ultimate duration
    AtlasDuration   = 15,
}

-- ============================================================
-- STATE
-- ============================================================
local State = {
    cd          = {},
    attacking   = false,
    ultraActive = false,
    m1Combo     = 0,
    m1Timer     = 0,
    connections = {},
    chargeTime  = 0,
    charging    = false,
}

-- ============================================================
-- COOLDOWN HELPERS
-- ============================================================
local function onCD(id)
    local t = State.cd[id]
    return t ~= nil and (tick() - t) < (CFG[id .. "CD"] or 1)
end

local function setCD(id)
    State.cd[id] = tick()
end

local function cdLeft(id)
    local t = State.cd[id]
    if not t then return 0 end
    return math.max(0, (CFG[id .. "CD"] or 1) - (tick() - t))
end

-- ============================================================
-- TARGET HELPERS
-- ============================================================
local function nearest(range)
    local best, bestDist = nil, range
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then
            local r = p.Character:FindFirstChild("HumanoidRootPart")
            local h = p.Character:FindFirstChild("Humanoid")
            if r and h and h.Health > 0 then
                local d = (r.Position - rootPart.Position).Magnitude
                if d < bestDist then best, bestDist = p.Character, d end
            end
        end
    end
    return best
end

local function inRange(range)
    local t = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character then
            local r = p.Character:FindFirstChild("HumanoidRootPart")
            local h = p.Character:FindFirstChild("Humanoid")
            if r and h and h.Health > 0 then
                if (r.Position - rootPart.Position).Magnitude <= range then
                    table.insert(t, p.Character)
                end
            end
        end
    end
    return t
end

local function dmg(char, amount)
    local h = char:FindFirstChild("Humanoid")
    if h and h.Health > 0 then h:TakeDamage(amount) end
end

local function kb(char, force, yBias)
    local r = char:FindFirstChild("HumanoidRootPart")
    if not r then return end
    yBias = yBias or 0.35
    local dir = (r.Position - rootPart.Position).Unit
    local bv  = Instance.new("BodyVelocity")
    bv.Velocity  = (dir + Vector3.new(0, yBias, 0)) * force
    bv.MaxForce  = Vector3.new(1e5, 1e5, 1e5)
    bv.Parent    = r
    Debris:AddItem(bv, 0.18)
end

-- ============================================================
-- VFX
-- ============================================================
local function bolt(origin, target, color, width, segs)
    color = color or CFG.CoreColor
    width = width or 0.09
    segs  = segs  or 12
    local dir  = target - origin
    local len  = dir.Magnitude
    local step = len / segs
    for i = 0, segs - 1 do
        local off = (i < segs - 1)
            and Vector3.new(math.random(-10,10)*0.1, math.random(-10,10)*0.1, math.random(-10,10)*0.1)
            or  Vector3.zero
        local s = origin + dir.Unit * (step * i)
        local e = origin + dir.Unit * (step * (i+1)) + off
        local p = Instance.new("Part")
        p.Anchored   = true
        p.CanCollide = false
        p.CastShadow = false
        p.Material   = Enum.Material.Neon
        p.Color      = color
        p.Size       = Vector3.new(width, width, (e-s).Magnitude)
        p.CFrame     = CFrame.lookAt((s+e)/2, e)
        p.Parent     = workspace
        local tw = TweenService:Create(p, TweenInfo.new(0.14, Enum.EasingStyle.Linear), {Transparency=1})
        tw:Play()
        tw.Completed:Connect(function() p:Destroy() end)
    end
end

local function burst(pos, color, count, spread)
    color  = color  or CFG.CoreColor
    count  = count  or 10
    spread = spread or 6
    for _ = 1, count do
        local dir = Vector3.new(math.random(-10,10), math.random(2,10), math.random(-10,10)).Unit
        bolt(pos, pos + dir * math.random(3, spread), color, 0.07, 5)
    end
end

local function ring(center, radius, color, spokes)
    spokes = spokes or 16
    for i = 1, spokes do
        local a   = (i/spokes) * math.pi * 2
        local tip = center + Vector3.new(math.cos(a)*radius, 0, math.sin(a)*radius)
        bolt(center, tip, color, 0.055, 8)
    end
end

local function aura(char, duration, color)
    local r   = char:FindFirstChild("HumanoidRootPart")
    if not r  then return end
    color    = color    or CFG.CoreColor
    duration = duration or 0.7
    local endT = tick() + duration
    task.spawn(function()
        while tick() < endT do
            local a   = math.random() * math.pi * 2
            local rad = math.random(2, 5)
            local off = Vector3.new(math.cos(a)*rad, math.random(-3,3), math.sin(a)*rad)
            bolt(r.Position, r.Position + off, color, 0.055, 5)
            task.wait(0.04)
        end
    end)
end

local function starParticle(origin)
    -- 5-point star burst from origin outward
    for i = 1, 5 do
        local a   = (i/5) * math.pi * 2
        local tip = origin + Vector3.new(math.cos(a)*8, math.random(2,5), math.sin(a)*8)
        bolt(origin, tip, CFG.BurstColor, 0.12, 7)
    end
end

-- ============================================================
-- HUD
-- ============================================================
local HUDLabels = {}

local function buildHUD()
    local gui = player.PlayerGui:FindFirstChild("StarRageHUD")
    if gui then gui:Destroy() end

    local screen = Instance.new("ScreenGui")
    screen.Name           = "StarRageHUD"
    screen.ResetOnSpawn   = false
    screen.IgnoreGuiInset = true
    screen.Parent         = player.PlayerGui

    local frame = Instance.new("Frame")
    frame.Size                   = UDim2.new(0, 270, 0, 200)
    frame.Position               = UDim2.new(0, 12, 1, -215)
    frame.BackgroundColor3       = Color3.fromRGB(8, 8, 14)
    frame.BackgroundTransparency = 0.3
    frame.BorderSizePixel        = 0
    frame.Parent                 = screen
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local header = Instance.new("TextLabel")
    header.Size              = UDim2.new(1, 0, 0, 30)
    header.BackgroundColor3  = Color3.fromRGB(255, 215, 40)
    header.Text              = "★  STAR RAGE  [ KASHIMO ]"
    header.TextColor3        = Color3.fromRGB(10, 10, 10)
    header.Font              = Enum.Font.GothamBold
    header.TextScaled        = true
    header.Parent            = frame
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 8)

    local entries = {
        { key="M1",        label="M1 — Lightning Jab",        cd="M1"       },
        { key="M2",        label="M2 — Discharge Slam",       cd="M2"       },
        { key="E",         label="E  — Starfall Strike",      cd="Starfall" },
        { key="R",         label="R  — Nova Burst",           cd="Nova"     },
        { key="F",         label="F  — Atlas Collapse [ULT]", cd="Atlas"    },
        { key="PASSIVE",   label="⚡ Electromagnetic Passive", cd=nil        },
    }

    HUDLabels = {}
    for i, e in ipairs(entries) do
        local lbl = Instance.new("TextLabel")
        lbl.Size                   = UDim2.new(1, -10, 0, 25)
        lbl.Position               = UDim2.new(0, 5, 0, 30 + (i-1)*27)
        lbl.BackgroundTransparency = 1
        lbl.TextXAlignment         = Enum.TextXAlignment.Left
        lbl.Font                   = Enum.Font.Gotham
        lbl.TextSize               = 13
        lbl.TextColor3             = Color3.fromRGB(230, 230, 230)
        lbl.Text                   = e.label
        lbl.Parent                 = frame
        if e.cd then HUDLabels[e.cd] = { lbl = lbl, base = e.label } end
    end

    local conn = RunService.Heartbeat:Connect(function()
        for cdId, data in pairs(HUDLabels) do
            local rem = cdLeft(cdId)
            if rem > 0 then
                data.lbl.TextColor3 = Color3.fromRGB(210, 70, 70)
                data.lbl.Text = data.base .. string.format(" [%.1fs]", rem)
            else
                data.lbl.TextColor3 = Color3.fromRGB(100, 255, 120)
                data.lbl.Text = data.base
            end
        end
    end)
    table.insert(State.connections, conn)
end

-- ============================================================
-- PASSIVE — ELECTROMAGNETIC BODY
-- Kashimo's body is a living battery — periodic shock pulse
-- to anyone in melee range, no input required
-- ============================================================
local function startPassive()
    local conn = RunService.Heartbeat:Connect(function()
        if tick() - (State.passiveTick or 0) >= CFG.PassiveInterval then
            State.passiveTick = tick()
            local enemies = inRange(CFG.PassiveRange)
            for _, e in ipairs(enemies) do
                local r = e:FindFirstChild("HumanoidRootPart")
                if r then
                    bolt(rootPart.Position, r.Position, CFG.ArcColor, 0.06, 6)
                    dmg(e, CFG.PassiveDmg)
                end
            end
        end
    end)
    table.insert(State.connections, conn)
end

-- ============================================================
-- M1 — LIGHTNING JAB (3-hit combo)
-- Hit 3 launches with an uppercut bolt
-- ============================================================
local function m1()
    if onCD("M1") or State.attacking then return end
    setCD("M1")
    State.attacking = true

    State.m1Combo = (tick() - State.m1Timer < 1.8) and (State.m1Combo % 3) + 1 or 1
    State.m1Timer = tick()

    local enemy = nearest(CFG.StrikeRange)
    if enemy then
        local r = enemy:FindFirstChild("HumanoidRootPart")
        if r then
            if State.m1Combo == 3 then
                -- Finisher: uppercut launch
                bolt(rootPart.Position, r.Position + Vector3.new(0, 6, 0), CFG.CoreColor, 0.11, 9)
                burst(r.Position, CFG.CoreColor, 7, 5)
                dmg(enemy, CFG.StrikeDmg)
                kb(enemy, 75, 0.9)
                State.m1Combo = 0
            else
                bolt(rootPart.Position, r.Position, CFG.CoreColor, 0.08, 7)
                dmg(enemy, CFG.StrikeDmgM2)
                kb(enemy, 30, 0.2)
            end
        end
    end

    task.wait(0.15)
    State.attacking = false
end

-- ============================================================
-- M2 — DISCHARGE SLAM
-- Charge briefly, release a grounded shockwave
-- ============================================================
local function m2()
    if onCD("M2") or State.attacking then return end
    setCD("M2")
    State.attacking = true

    aura(character, 0.45, CFG.CoreColor)
    task.wait(0.35)

    local enemies = inRange(CFG.StrikeRange + 4)
    ring(rootPart.Position, CFG.StrikeRange + 4, CFG.ArcColor, 20)

    for _, e in ipairs(enemies) do
        local r = e:FindFirstChild("HumanoidRootPart")
        if r then
            bolt(rootPart.Position, r.Position, CFG.ArcColor, 0.1, 8)
            dmg(e, CFG.StrikeDmg - 8)
            kb(e, 55, 0.4)
        end
    end

    task.wait(0.2)
    State.attacking = false
end

-- ============================================================
-- E — STARFALL STRIKE
-- Kashimo hurls a condensed lightning star at nearest target
-- Explodes on impact, arcs to nearby enemies
-- ============================================================
local function starfall()
    if onCD("Starfall") or State.attacking then return end
    local enemy = nearest(CFG.StarfallRange)
    if not enemy then return end

    setCD("Starfall")
    State.attacking = true

    local r = enemy:FindFirstChild("HumanoidRootPart")
    if r then
        -- Travel bolt
        bolt(rootPart.Position, r.Position, CFG.BurstColor, 0.14, 14)
        task.wait(0.1)

        -- Impact
        starParticle(r.Position)
        burst(r.Position, CFG.BurstColor, 12, 7)
        dmg(enemy, CFG.StarfallDmg)
        kb(enemy, 85, 0.5)

        -- Arc to secondary targets
        local secondaries = inRange(14)
        for _, sec in ipairs(secondaries) do
            if sec ~= enemy then
                local sr = sec:FindFirstChild("HumanoidRootPart")
                if sr then
                    bolt(r.Position, sr.Position, CFG.ArcColor, 0.07, 6)
                    dmg(sec, CFG.StarfallDmg * 0.45)
                    kb(sec, 40, 0.3)
                end
            end
        end
    end

    task.wait(0.3)
    State.attacking = false
end

-- ============================================================
-- R — NOVA BURST
-- Omnidirectional lightning detonation centered on Kashimo
-- ============================================================
local function novaBurst()
    if onCD("Nova") or State.attacking then return end

    setCD("Nova")
    State.attacking = true

    -- Wind-up
    aura(character, 0.7, CFG.CoreColor)
    task.wait(0.6)

    -- Detonate
    ring(rootPart.Position, CFG.NovaRange, CFG.CoreColor, 24)
    ring(rootPart.Position, CFG.NovaRange * 0.5, CFG.ArcColor, 16)
    burst(rootPart.Position, CFG.BurstColor, 16, 8)

    local enemies = inRange(CFG.NovaRange)
    for _, e in ipairs(enemies) do
        local r = e:FindFirstChild("HumanoidRootPart")
        if r then
            bolt(rootPart.Position, r.Position, CFG.CoreColor, 0.1, 10)
            dmg(e, CFG.NovaDmg)
            kb(e, 100, 0.6)
        end
    end

    task.wait(0.35)
    State.attacking = false
end

-- ============================================================
-- F — ATLAS COLLAPSE [ULTIMATE]
-- Star Rage: full release. Kashimo becomes a living star.
-- Pulls all enemies inward, then detonates in a massive burst.
-- Passive damage triples during duration.
-- ============================================================
local function atlasCollapse()
    if onCD("Atlas") or State.ultraActive then return end

    setCD("Atlas")
    State.ultraActive = true

    -- Phase 1: Gravitational pull (1.5s)
    aura(character, 1.5, CFG.BurstColor)

    local pullStart = tick()
    local pullConn
    pullConn = RunService.Heartbeat:Connect(function()
        if tick() - pullStart >= 1.4 then
            pullConn:Disconnect()
            return
        end
        for _, e in ipairs(inRange(CFG.AtlasRange)) do
            local r = e:FindFirstChild("HumanoidRootPart")
            if r then
                local dir = (rootPart.Position - r.Position).Unit
                local bv  = Instance.new("BodyVelocity")
                bv.Velocity  = dir * 55
                bv.MaxForce  = Vector3.new(1e4, 1e4, 1e4)
                bv.Parent    = r
                Debris:AddItem(bv, 0.08)
            end
        end
    end)

    task.wait(1.5)

    -- Phase 2: Detonation
    ring(rootPart.Position, CFG.AtlasRange,       CFG.BurstColor, 32)
    ring(rootPart.Position, CFG.AtlasRange * 0.6, CFG.CoreColor,  24)
    ring(rootPart.Position, CFG.AtlasRange * 0.3, CFG.ArcColor,   16)

    for i = 1, 5 do
        task.spawn(function()
            starParticle(rootPart.Position + Vector3.new(
                math.random(-6, 6), math.random(0, 4), math.random(-6, 6)
            ))
        end)
    end

    local enemies = inRange(CFG.AtlasRange)
    for _, e in ipairs(enemies) do
        local r = e:FindFirstChild("HumanoidRootPart")
        if r then
            bolt(rootPart.Position, r.Position, CFG.BurstColor, 0.16, 16)
            dmg(e, CFG.AtlasDmg)
            kb(e, 150, 0.8)
        end
        task.wait(0.03)
    end

    -- Phase 3: Aftershock pulses (duration)
    local elapsed = 0
    local pulseInterval = 2.5

    while elapsed < CFG.AtlasDuration do
        task.wait(pulseInterval)
        elapsed = elapsed + pulseInterval

        ring(rootPart.Position, CFG.NovaRange, CFG.CoreColor, 18)
        for _, e in ipairs(inRange(CFG.NovaRange)) do
            local r = e:FindFirstChild("HumanoidRootPart")
            if r then
                bolt(rootPart.Position, r.Position, CFG.ArcColor, 0.09, 8)
                dmg(e, CFG.NovaDmg * 0.6)
                kb(e, 50, 0.4)
            end
        end
    end

    State.ultraActive = false
end

-- ============================================================
-- INPUT
-- ============================================================
local binds = {
    [Enum.UserInputType.MouseButton1] = m1,
    [Enum.UserInputType.MouseButton2] = m2,
}

local keyBinds = {
    [Enum.KeyCode.E] = starfall,
    [Enum.KeyCode.R] = novaBurst,
    [Enum.KeyCode.F] = atlasCollapse,
}

local inputConn = UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    local a = binds[input.UserInputType] or keyBinds[input.KeyCode]
    if a then task.spawn(a) end
end)
table.insert(State.connections, inputConn)

-- ============================================================
-- RESPAWN
-- ============================================================
player.CharacterAdded:Connect(function(newChar)
    character = newChar
    humanoid  = newChar:WaitForChild("Humanoid")
    rootPart  = newChar:WaitForChild("HumanoidRootPart")

    for _, c in ipairs(State.connections) do c:Disconnect() end
    State.connections = {}
    State.cd          = {}
    State.attacking   = false
    State.ultraActive = false
    State.m1Combo     = 0

    local rb = UserInputService.InputBegan:Connect(function(input, gp)
        if gp then return end
        local a = binds[input.UserInputType] or keyBinds[input.KeyCode]
        if a then task.spawn(a) end
    end)
    table.insert(State.connections, rb)

    startPassive()
    buildHUD()
end)

-- ============================================================
-- INIT
-- ============================================================
startPassive()
buildHUD()
print("[Star Rage] Kashimo loaded. M1 / M2 / E / R / F active.")
