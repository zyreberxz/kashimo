-- ============================================================
-- KASHIMO STAR RAGE — CLIENT ILLUSION BUILD
-- YOU see: Kashimo staff VFX + lightning effects
-- OTHERS see: default Star Rage animations (untouched)
-- No remote calls. No server writes. Pure local render.
-- Solara / Synapse X compatible
-- ============================================================

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris           = game:GetService("Debris")

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid  = character:WaitForChild("Humanoid")
local rootPart  = character:WaitForChild("HumanoidRootPart")
local animator  = humanoid:WaitForChild("Animator")

-- ============================================================
-- CONFIG
-- ============================================================
local CFG = {
    CoreColor    = Color3.fromRGB(255, 230, 60),
    ArcColor     = Color3.fromRGB(200, 100, 255),
    BurstColor   = Color3.fromRGB(255, 255, 180),
    StaffColor   = Color3.fromRGB(220, 180, 80),
    StaffLength  = 5.5,
    StaffWidth   = 0.18,
    PassiveRange = 10,
    PassiveInterval = 1.8,
}

local State = {
    connections  = {},
    staff        = nil,
    passiveTick  = 0,
    tracking     = {},  -- animation name → last known state
}

-- ============================================================
-- STAFF MODEL — visible only to local client
-- Replaces Star Rage weapon appearance client-side
-- Others still see their own render of your equipped tool
-- ============================================================
local function buildStaff()
    if State.staff then State.staff:Destroy() end

    local rightHand = character:FindFirstChild("RightHand")
        or character:FindFirstChild("Right Arm")
    if not rightHand then return end

    local staff = Instance.new("Model")
    staff.Name = "KashimoStaff"

    -- Main shaft
    local shaft = Instance.new("Part")
    shaft.Name        = "Shaft"
    shaft.Size        = Vector3.new(CFG.StaffWidth, CFG.StaffWidth, CFG.StaffLength)
    shaft.Material    = Enum.Material.SmoothPlastic
    shaft.Color       = CFG.StaffColor
    shaft.CanCollide  = false
    shaft.CastShadow  = false
    shaft.Parent      = staff

    -- Grip wrap bands
    for _, offset in ipairs({-1.2, -0.6, 0, 0.6, 1.2}) do
        local band = Instance.new("Part")
        band.Size       = Vector3.new(CFG.StaffWidth + 0.06, CFG.StaffWidth + 0.06, 0.12)
        band.Material   = Enum.Material.SmoothPlastic
        band.Color      = Color3.fromRGB(60, 40, 20)
        band.CanCollide = false
        band.CastShadow = false
        band.Parent     = staff

        local bWeld = Instance.new("WeldConstraint")
        bWeld.Part0  = shaft
        bWeld.Part1  = band
        bWeld.Parent = staff
        band.CFrame  = shaft.CFrame * CFrame.new(0, 0, offset)
    end

    -- Top orb — glowing lightning core
    local orb = Instance.new("Part")
    orb.Shape      = Enum.PartType.Ball
    orb.Size       = Vector3.new(0.45, 0.45, 0.45)
    orb.Material   = Enum.Material.Neon
    orb.Color      = CFG.CoreColor
    orb.CanCollide = false
    orb.CastShadow = false
    orb.Parent     = staff

    local orbWeld = Instance.new("WeldConstraint")
    orbWeld.Part0  = shaft
    orbWeld.Part1  = orb
    orbWeld.Parent = staff
    orb.CFrame     = shaft.CFrame * CFrame.new(0, 0, -(CFG.StaffLength / 2) - 0.2)

    -- Bottom cap
    local cap = Instance.new("Part")
    cap.Shape      = Enum.PartType.Ball
    cap.Size       = Vector3.new(0.28, 0.28, 0.28)
    cap.Material   = Enum.Material.SmoothPlastic
    cap.Color      = Color3.fromRGB(180, 140, 60)
    cap.CanCollide = false
    cap.CastShadow = false
    cap.Parent     = staff

    local capWeld = Instance.new("WeldConstraint")
    capWeld.Part0  = shaft
    capWeld.Part1  = cap
    capWeld.Parent = staff
    cap.CFrame     = shaft.CFrame * CFrame.new(0, 0, CFG.StaffLength / 2 + 0.1)

    -- Weld shaft to right hand
    shaft.Parent = staff
    local handWeld = Instance.new("Motor6D")
    handWeld.Name   = "StaffGrip"
    handWeld.Part0  = rightHand
    handWeld.Part1  = shaft
    handWeld.C0     = CFrame.new(0, -0.15, -CFG.StaffLength * 0.38)
                    * CFrame.Angles(0, 0, math.rad(90))
    handWeld.Parent = rightHand

    staff.Parent = character
    State.staff  = staff

    -- Orb idle pulse loop — client only, no server touch
    task.spawn(function()
        while State.staff and State.staff.Parent do
            local tw = TweenService:Create(
                orb,
                TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
                { Color = CFG.ArcColor }
            )
            tw:Play()
            task.wait(1.4)
            tw:Cancel()
            orb.Color = CFG.CoreColor
            task.wait(0.05)
        end
    end)
end

-- ============================================================
-- VFX — local render only
-- No Part.Parent = workspace calls replicate to server in
-- a way that other clients see — these are ephemeral unanchored
-- parts destroyed before replication matters
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
            and Vector3.new(
                math.random(-10,10)*0.1,
                math.random(-10,10)*0.1,
                math.random(-10,10)*0.1)
            or Vector3.zero
        local s = origin + dir.Unit*(step*i)
        local e = origin + dir.Unit*(step*(i+1)) + off
        local p = Instance.new("Part")
        p.Anchored   = true
        p.CanCollide = false
        p.CastShadow = false
        p.Material   = Enum.Material.Neon
        p.Color      = color
        p.Size       = Vector3.new(width, width, (e-s).Magnitude)
        p.CFrame     = CFrame.lookAt((s+e)/2, e)
        p.Parent     = workspace
        local tw = TweenService:Create(
            p,
            TweenInfo.new(0.13, Enum.EasingStyle.Linear),
            { Transparency = 1 }
        )
        tw:Play()
        tw.Completed:Connect(function() p:Destroy() end)
    end
end

local function burst(pos, color, count, spread)
    color  = color  or CFG.CoreColor
    count  = count  or 10
    spread = spread or 6
    for _ = 1, count do
        local dir = Vector3.new(
            math.random(-10,10),
            math.random(2,10),
            math.random(-10,10)
        ).Unit
        bolt(pos, pos + dir * math.random(3, spread), color, 0.07, 5)
    end
end

local function ring(center, radius, color, spokes)
    spokes = spokes or 16
    color  = color  or CFG.CoreColor
    for i = 1, spokes do
        local a   = (i/spokes) * math.pi * 2
        local tip = center + Vector3.new(math.cos(a)*radius, 0, math.sin(a)*radius)
        bolt(center, tip, color, 0.05, 7)
    end
end

local function aura(char, duration, color)
    local r = char:FindFirstChild("HumanoidRootPart")
    if not r then return end
    color    = color    or CFG.CoreColor
    duration = duration or 0.7
    local endT = tick() + duration
    task.spawn(function()
        while tick() < endT do
            local a   = math.random() * math.pi * 2
            local rad = math.random(2, 5)
            local off = Vector3.new(math.cos(a)*rad, math.random(-3,3), math.sin(a)*rad)
            bolt(r.Position, r.Position + off, color, 0.05, 5)
            task.wait(0.04)
        end
    end)
end

local function starBurst(origin)
    for i = 1, 5 do
        local a   = (i/5) * math.pi * 2
        local tip = origin + Vector3.new(math.cos(a)*8, math.random(2,5), math.sin(a)*8)
        bolt(origin, tip, CFG.BurstColor, 0.12, 7)
    end
end

-- ============================================================
-- ANIMATION TRACKER
-- Reads the Animator's playing tracks each frame.
-- Maps Star Rage animation names → Kashimo VFX responses.
-- This is the core of the illusion: no remotes, no input hooks.
-- The game's own animation state drives the local VFX layer.
-- ============================================================
local ANIM_VFX_MAP = {
    -- Key: substring to match in AnimationTrack.Name or Animation.AnimationId
    -- Val: function(track) that fires local VFX once per activation

    ["M1"]          = function() bolt(rootPart.Position, rootPart.Position + rootPart.CFrame.LookVector * 6, CFG.CoreColor, 0.1, 7) end,
    ["M2"]          = function() aura(character, 0.5, CFG.CoreColor) ring(rootPart.Position, 14, CFG.ArcColor, 18) end,
    ["StarFall"]    = function()
        local orb = State.staff and State.staff:FindFirstChild("Shaft")
        local origin = orb and orb.Position or rootPart.Position
        burst(origin, CFG.BurstColor, 12, 7)
        starBurst(origin)
    end,
    ["Nova"]        = function()
        ring(rootPart.Position, 20, CFG.CoreColor, 24)
        ring(rootPart.Position, 10, CFG.ArcColor, 16)
        burst(rootPart.Position, CFG.BurstColor, 14, 8)
    end,
    ["Atlas"]       = function()
        ring(rootPart.Position, 35, CFG.BurstColor, 32)
        ring(rootPart.Position, 20, CFG.CoreColor, 24)
        burst(rootPart.Position, CFG.BurstColor, 20, 10)
        starBurst(rootPart.Position)
    end,
    ["Block"]       = function() bolt(rootPart.Position, rootPart.Position + Vector3.new(0,4,0), CFG.ArcColor, 0.08, 5) end,
    ["Dash"]        = function() aura(character, 0.3, CFG.CoreColor) end,
    ["Hit"]         = function() burst(rootPart.Position, CFG.ArcColor, 6, 4) end,
}

-- Tracks which animations already fired this activation
local firedThisPlay = {}

local function trackAnimations()
    local conn = RunService.Heartbeat:Connect(function()
        local playing = animator:GetPlayingAnimationTracks()
        local activeIds = {}

        for _, track in ipairs(playing) do
            local name = track.Name or ""
            local id   = tostring(track.Animation and track.Animation.AnimationId or "")
            activeIds[track] = true

            for keyword, vfxFn in pairs(ANIM_VFX_MAP) do
                local matchName = name:lower():find(keyword:lower())
                local matchId   = id:lower():find(keyword:lower())

                if (matchName or matchId) and not firedThisPlay[track] then
                    firedThisPlay[track] = true
                    task.spawn(vfxFn)
                end
            end
        end

        -- Clean up stopped tracks
        for track in pairs(firedThisPlay) do
            if not activeIds[track] then
                firedThisPlay[track] = nil
            end
        end
    end)
    table.insert(State.connections, conn)
end

-- ============================================================
-- PASSIVE VISUAL — Electromagnetic Body
-- Client-side arc pulse. Others see nothing extra.
-- ============================================================
local function startPassiveVFX()
    local conn = RunService.Heartbeat:Connect(function()
        if tick() - State.passiveTick < CFG.PassiveInterval then return end
        State.passiveTick = tick()
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= player and p.Character then
                local r = p.Character:FindFirstChild("HumanoidRootPart")
                if r and (r.Position - rootPart.Position).Magnitude <= CFG.PassiveRange then
                    bolt(rootPart.Position, r.Position, CFG.ArcColor, 0.055, 6)
                end
            end
        end
    end)
    table.insert(State.connections, conn)
end

-- ============================================================
-- STAFF ORB — follows animation pose each frame
-- Keeps the orb glowing at the tip regardless of hand position
-- ============================================================
local function startStaffTracking()
    local conn = RunService.RenderStepped:Connect(function()
        if not State.staff then return end
        local rh = character:FindFirstChild("RightHand")
              or  character:FindFirstChild("Right Arm")
        if not rh then return end
        -- Weld handles position; this just keeps the orb pulse alive
        local orb = State.staff:FindFirstChildWhichIsA("Part", true)
        if orb and orb.Material == Enum.Material.Neon then
            -- Subtle flicker
            orb.Transparency = math.abs(math.sin(tick() * 3)) * 0.25
        end
    end)
    table.insert(State.connections, conn)
end

-- ============================================================
-- HUD — minimal, client-only indicator
-- ============================================================
local function buildHUD()
    local gui = player.PlayerGui:FindFirstChild("KashimoIllusionHUD")
    if gui then gui:Destroy() end

    local screen = Instance.new("ScreenGui")
    screen.Name           = "KashimoIllusionHUD"
    screen.ResetOnSpawn   = false
    screen.IgnoreGuiInset = true
    screen.Parent         = player.PlayerGui

    local frame = Instance.new("Frame")
    frame.Size                   = UDim2.new(0, 220, 0, 52)
    frame.Position               = UDim2.new(0, 12, 1, -70)
    frame.BackgroundColor3       = Color3.fromRGB(8, 8, 14)
    frame.BackgroundTransparency = 0.3
    frame.BorderSizePixel        = 0
    frame.Parent                 = screen
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

    local header = Instance.new("TextLabel")
    header.Size             = UDim2.new(1, 0, 0, 26)
    header.BackgroundColor3 = Color3.fromRGB(255, 215, 40)
    header.Text             = "★  KASHIMO ILLUSION  [ ACTIVE ]"
    header.TextColor3       = Color3.fromRGB(10, 10, 10)
    header.Font             = Enum.Font.GothamBold
    header.TextScaled       = true
    header.Parent           = frame
    Instance.new("UICorner", header).CornerRadius = UDim.new(0, 8)

    local sub = Instance.new("TextLabel")
    sub.Size                   = UDim2.new(1, -8, 0, 22)
    sub.Position               = UDim2.new(0, 4, 0, 28)
    sub.BackgroundTransparency = 1
    sub.Text                   = "You: Kashimo VFX  |  Others: Star Rage"
    sub.TextColor3             = Color3.fromRGB(180, 180, 180)
    sub.Font                   = Enum.Font.Gotham
    sub.TextSize               = 12
    sub.Parent                 = frame
end

-- ============================================================
-- INIT + RESPAWN
-- ============================================================
local function init()
    character = player.Character or player.CharacterAdded:Wait()
    humanoid  = character:WaitForChild("Humanoid")
    rootPart  = character:WaitForChild("HumanoidRootPart")
    animator  = humanoid:WaitForChild("Animator")

    for _, c in ipairs(State.connections) do c:Disconnect() end
    State.connections = {}
    firedThisPlay     = {}

    buildStaff()
    startStaffTracking()
    trackAnimations()
    startPassiveVFX()
    buildHUD()

    print("[Kashimo Illusion] Staff rendered. Animation tracker live.")
end

player.CharacterAdded:Connect(init)
init()
