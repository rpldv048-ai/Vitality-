-- Military Tycoon | Modern Menu (UI only)
-- Menu toggle is configurable from the Keybinds tab.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local T = {
    Bg      = Color3.fromRGB(4, 4, 5),
    Panel   = Color3.fromRGB(9, 9, 10),
    Card    = Color3.fromRGB(13, 13, 14),
    CardHi  = Color3.fromRGB(21, 21, 22),
    Line    = Color3.fromRGB(31, 31, 32),
    Accent  = Color3.fromRGB(245, 245, 245),
    Accent2 = Color3.fromRGB(150, 150, 150),
    Accent3 = Color3.fromRGB(220, 220, 220),
    Danger  = Color3.fromRGB(190, 190, 192),
    Text    = Color3.fromRGB(245, 245, 246),
    Sub     = Color3.fromRGB(145, 145, 148),
}

-- Animated accent gradient, ticked from the render loop below
local accentPhase = 0
local accentStrokes = {}   -- strokes that get the "live accent" look
local accentDots    = {}   -- blinking status dots
local animatedGui   = nil  -- ScreenGui that owns the menu animation
local window
local anim = { Enabled = true }
local activeTweens = {}
local notificationsEnabled = true

-- ===================================================================
-- HTML config bridge
-- ===================================================================
-- The menu is described by an HTML file on GitHub. The loader line:
--
--   getgenv().VitalityHTML = game:HttpGet(".../yourfile.html")
--   loadstring(game:HttpGet(".../robloxscript.lua"))()
--
-- stashes the fetched HTML in getgenv().VitalityHTML *before* this script
-- runs, so we read it from there first and only fall back to fetching the
-- URL ourselves when it is missing. The page is parsed for its
-- <script id="vitality-config" type="application/json"> block, which
-- mirrors the browser preview's own data (script.html), keeping the two in
-- sync from a single source of truth.

local CONFIG_URL = "https://raw.githubusercontent.com/rpldv048-ai/Vitality-/refs/heads/main/yourfile.html"
local HttpService = game:GetService("HttpService")

local htmlConfig = nil        -- decoded config table, or nil
local htmlConfigSource = ""   -- where the HTML came from, for notifications

local function fetchHtml()
    -- 1) Prefer whatever the loader already stored for us.
    local injected
    local ok = pcall(function()
        if type(getgenv) == "function" then
            injected = getgenv().VitalityHTML
        end
    end)
    if ok and type(injected) == "string" and #injected > 0 then
        htmlConfigSource = "loader"
        return injected
    end

    -- 2) Otherwise fetch it ourselves.
    local fetched
    ok = pcall(function()
        fetched = game:HttpGet(CONFIG_URL)
    end)
    if ok and type(fetched) == "string" and #fetched > 0 then
        htmlConfigSource = "HttpGet"
        return fetched
    end

    htmlConfigSource = ""
    return nil
end

local function parseHtmlConfig(html)
    if type(html) ~= "string" or #html == 0 then return nil end

    -- Robust to attribute order: find the opening tag, then take everything
    -- up to the next </script> as the JSON payload.
    local json = html:match("<script[^>]-id%s*=%s*[\"']vitality%-config[\"'][^>]*>(.-)</script>")
    if not json then
        -- Fallback: some hosts minify to a bare "vitality-config" marker.
        json = html:match("vitality%-config[^>]*>(.-)</script>")
    end
    if not json then return nil end

    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(json)
    end)
    if not ok or type(decoded) ~= "table" then
        warn("Vitality config: could not decode the JSON block.")
        return nil
    end
    return decoded
end

local function tween(o, t, p)
    if not anim.Enabled then
        for property, value in pairs(p) do
            o[property] = value
        end
        return
    end
    local tw = TweenService:Create(o, TweenInfo.new(t, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), p)
    local entry = {Tween = tw, Object = o, Properties = p}
    table.insert(activeTweens, entry)
    tw.Completed:Connect(function()
        for index = #activeTweens, 1, -1 do
            if activeTweens[index] == entry then
                table.remove(activeTweens, index)
                break
            end
        end
    end)
    tw:Play()
end

local function stopActiveTweens()
    local pending = activeTweens
    activeTweens = {}
    for _, entry in ipairs(pending) do
        entry.Tween:Cancel()
        for property, value in pairs(entry.Properties) do
            entry.Object[property] = value
        end
    end
end

-- Cheap "is the menu actually being looked at" guard so the visual
-- animation costs nothing while the GUI is closed or destroyed
local function uiLive()
    return animatedGui ~= nil and animatedGui.Parent ~= nil and window ~= nil and window.Parent ~= nil
end

local function gradientColor()
    -- Rotating monochrome accent gradient, wrapped seamlessly
    local t = accentPhase % 1
    local a, b, c = T.Accent, T.Accent2, T.Accent3
    local function mix(x, y, k)
        return x:Lerp(y, k)
    end
    if t < 1 / 3 then
        local k = t * 3
        return mix(a, b, k), mix(b, a, k)
    elseif t < 2 / 3 then
        local k = (t - 1 / 3) * 3
        return mix(b, c, k), mix(c, b, k)
    end
    local k = (t - 2 / 3) * 3
    return mix(c, a, k), mix(a, c, k)
end

local function accentLive(st, speed)
    accentStrokes[st] = { speed = speed or 1, phase = 0 }
    return st
end

local function accentDot(dot, speed)
    accentDots[dot] = speed or 1
    return dot
end

local function glowBehind(frame)
    -- Soft accent bloom parented *inside* the target so corners clip it
    local g = Instance.new("Frame")
    g.Name = "__Glow"
    g.Size = UDim2.new(1, 14, 1, 14)
    g.Position = UDim2.new(0, -7, 0, -7)
    g.BackgroundColor3 = T.Accent
    g.BackgroundTransparency = 0.94
    g.BorderSizePixel = 0
    g.ZIndex = 0
    g.Parent = frame
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 22)
    c.Parent = g
    local s = Instance.new("UIStroke")
    s.Color = T.Accent
    s.Thickness = 1
    s.Transparency = 0.85
    s.Parent = g
    accentLive(s, 0.7)
    return g
end

local function noise(parentFrame, transparency)
    -- Faint scanline overlay; sells the "hardware UI" look without images
    local f = Instance.new("Frame")
    f.Name = "__Noise"
    f.Size = UDim2.new(1, 0, 1, 0)
    f.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    f.BackgroundTransparency = transparency or 0.98
    f.BorderSizePixel = 0
    f.ZIndex = 0
    f.Parent = parentFrame
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 19)
    c.Parent = f
    local s = Instance.new("UIStroke")
    s.Color = T.Line
    s.Thickness = 1
    s.Transparency = 0.7
    s.Parent = f
    return f
end
local function corner(o, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = o; return c
end

-- Registered corners get a gentle, continuous radius "breathe" while
-- animations are on, so the rounded corners feel alive rather than static.
local animatedCorners = {}
local animatedCornerSerial = 0
local function liveCorner(o, r)
    local c = corner(o, r)
    animatedCornerSerial += 1
    animatedCorners[c] = {
        Base = r,
        Phase = ((animatedCornerSerial - 1) % 100) / 100 * math.pi * 2,
    }
    return c
end
local function stroke(o, col, th, tr)
    local s = Instance.new("UIStroke")
    s.Color = col; s.Thickness = th or 1; s.Transparency = tr or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = o; return s
end
local function gradient(o, rot, a, b)
    local g = Instance.new("UIGradient")
    g.Rotation = rot or 0
    g.Color = ColorSequence.new(a or T.Accent, b or T.Accent2)
    g.Parent = o; return g
end
local function label(parent, text, size, font, color, xalign)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = text; l.TextSize = size; l.Font = font; l.TextColor3 = color
    l.TextXAlignment = xalign or Enum.TextXAlignment.Left
    l.Parent = parent; return l
end

-- Root ---------------------------------------------------------------
local parent = (gethui and gethui()) or player:WaitForChild("PlayerGui")
if parent:FindFirstChild("MTMenu") then parent.MTMenu:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "MTMenu"; gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 100
gui.Parent = parent
animatedGui = gui

local notificationLayer = Instance.new("Frame")
notificationLayer.Name = "Notifications"
notificationLayer.AnchorPoint = Vector2.new(1, 0)
notificationLayer.Position = UDim2.new(1, -18, 0, 18)
notificationLayer.Size = UDim2.fromOffset(300, 300)
notificationLayer.BackgroundTransparency = 1
notificationLayer.ZIndex = 20
notificationLayer.Parent = gui
local notificationLayout = Instance.new("UIListLayout")
notificationLayout.Padding = UDim.new(0, 8)
notificationLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
notificationLayout.VerticalAlignment = Enum.VerticalAlignment.Top
notificationLayout.SortOrder = Enum.SortOrder.LayoutOrder
notificationLayout.Parent = notificationLayer

local notificationSerial = 0
local function notify(title, message, duration)
    if not notificationsEnabled or not gui.Parent then return end
    notificationSerial += 1
    local existing = notificationLayer:GetChildren()
    local cards = {}
    for _, child in ipairs(existing) do
        if child:IsA("Frame") then table.insert(cards, child) end
    end
    table.sort(cards, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
    while #cards >= 4 do
        cards[1]:Destroy()
        table.remove(cards, 1)
    end

    local card = Instance.new("Frame")
    card.Name = "Toast"
    card.LayoutOrder = notificationSerial
    card.Size = UDim2.new(1, 0, 0, 64)
    card.BackgroundColor3 = T.Panel
    card.BackgroundTransparency = anim.Enabled and 1 or 0.08
    card.BorderSizePixel = 0
    card.ZIndex = 20
    card.Parent = notificationLayer
    liveCorner(card, 12)
    local edge = stroke(card, T.Line, 1, 0.05)
    edge.Color = T.Accent2

    local titleLabel = label(card, tostring(title), 13, Enum.Font.GothamBold, T.Text)
    titleLabel.Position = UDim2.fromOffset(14, 8)
    titleLabel.Size = UDim2.new(1, -26, 0, 18)
    titleLabel.ZIndex = 21
    local messageLabel = label(card, tostring(message), 11, Enum.Font.Gotham, T.Sub)
    messageLabel.Position = UDim2.fromOffset(14, 30)
    messageLabel.Size = UDim2.new(1, -26, 0, 24)
    messageLabel.TextWrapped = true
    messageLabel.ZIndex = 21
    if anim.Enabled then
        tween(card, 0.18, {BackgroundTransparency = 0.08})
    end

    task.delay(duration or 2.6, function()
        if not card.Parent then return end
        if anim.Enabled then
            tween(card, 0.16, {BackgroundTransparency = 1})
            task.delay(0.18, function()
                if card.Parent then card:Destroy() end
            end)
        else
            card:Destroy()
        end
    end)
end

gui.Destroying:Connect(function()
    for _, child in ipairs(notificationLayer:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
end)

window = Instance.new("Frame")
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.new(0.5, 0, 0.5, 0)
window.Size = UDim2.new(0, 780, 0, 470)
window.BackgroundColor3 = T.Bg
window.BorderSizePixel = 0
window.ClipsDescendants = true
window.Parent = gui
liveCorner(window, 16)
local winStroke = stroke(window, T.Line, 1, 0)
accentLive(winStroke, 0.8)

local uiScale = Instance.new("UIScale"); uiScale.Parent = window

local dragGrip = Instance.new("TextButton")
dragGrip.Name = "DragGrip"
dragGrip.AnchorPoint = Vector2.new(0.5, 0)
dragGrip.Size = UDim2.fromOffset(76, 14)
dragGrip.Position = UDim2.new(0.5, 0, 0, 13)
dragGrip.BackgroundColor3 = Color3.fromRGB(18, 18, 19)
dragGrip.BackgroundTransparency = 0.12
dragGrip.Text = ""
dragGrip.AutoButtonColor = false
dragGrip.ZIndex = 10
dragGrip.Parent = window
liveCorner(dragGrip, 7)
stroke(dragGrip, T.Line, 1, 0.15)

for column = 0, 2 do
    local gripDot = Instance.new("Frame")
    gripDot.Size = UDim2.fromOffset(3, 3)
    gripDot.Position = UDim2.new(0.5, (column - 1) * 7 - 1.5, 0.5, -1.5)
    gripDot.BackgroundColor3 = T.Sub
    gripDot.BorderSizePixel = 0
    gripDot.ZIndex = 11
    gripDot.Parent = dragGrip
    corner(gripDot, 2)
end

local draggingWindow = false
local dragStart
local windowStart
dragGrip.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        draggingWindow = true
        dragStart = input.Position
        windowStart = window.Position
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if draggingWindow and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        window.Position = UDim2.new(
            windowStart.X.Scale,
            windowStart.X.Offset + delta.X,
            windowStart.Y.Scale,
            windowStart.Y.Offset + delta.Y
        )
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        draggingWindow = false
    end
end)

-- Deep monochrome galaxy backdrop
local baseGrad = Instance.new("UIGradient")
baseGrad.Rotation = 135
baseGrad.Color = ColorSequence.new(Color3.fromRGB(4, 4, 4), Color3.fromRGB(6, 6, 6))
baseGrad.Parent = window

local galaxyLayer = Instance.new("Frame")
galaxyLayer.Name = "Galaxy"
galaxyLayer.Size = UDim2.new(1, 0, 1, 0)
galaxyLayer.BackgroundTransparency = 1
galaxyLayer.BorderSizePixel = 0
galaxyLayer.ClipsDescendants = true
galaxyLayer.ZIndex = 1
galaxyLayer.Parent = window
liveCorner(galaxyLayer, 16)

local nebula = Instance.new("Frame")
nebula.Name = "Nebula"
nebula.Size = UDim2.new(1, 0, 1, 0)
nebula.BackgroundColor3 = Color3.fromRGB(175, 175, 180)
nebula.BackgroundTransparency = 0.98
nebula.BorderSizePixel = 0
nebula.ZIndex = 1
nebula.Parent = galaxyLayer
liveCorner(nebula, 16)
local nebulaGradient = Instance.new("UIGradient")
nebulaGradient.Rotation = 32
nebulaGradient.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.48),
    NumberSequenceKeypoint.new(0.32, 0.96),
    NumberSequenceKeypoint.new(0.68, 0.93),
    NumberSequenceKeypoint.new(1, 0.35),
})
nebulaGradient.Parent = nebula

local galaxyRandom = Random.new()
local galaxyStars = {}
for index = 1, 48 do
    local star = Instance.new("Frame")
    star.Name = "Star"
    local size = index <= 8 and galaxyRandom:NextInteger(2, 3) or 1
    star.Size = UDim2.fromOffset(size, size)
    star.Position = UDim2.new(galaxyRandom:NextNumber(0.02, 0.98), 0, galaxyRandom:NextNumber(0.03, 0.97), 0)
    star.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    star.BackgroundTransparency = galaxyRandom:NextNumber(0.2, 0.76)
    star.BorderSizePixel = 0
    star.ZIndex = 2
    star.Parent = galaxyLayer
    corner(star, size)
    galaxyStars[index] = {
        Object = star,
        Base = star.BackgroundTransparency,
        Phase = galaxyRandom:NextNumber(0, math.pi * 2),
        Rate = galaxyRandom:NextNumber(0.7, 1.8),
        X = star.Position.X.Scale,
        Y = star.Position.Y.Scale,
        DriftX = galaxyRandom:NextNumber(-0.006, 0.006),
        DriftY = galaxyRandom:NextNumber(-0.0045, 0.0045),
    }
end

local shootingStar = Instance.new("Frame")
shootingStar.Name = "ShootingStar"
shootingStar.AnchorPoint = Vector2.new(0.5, 0.5)
shootingStar.Size = UDim2.fromOffset(54, 2)
shootingStar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
shootingStar.BackgroundTransparency = 1
shootingStar.BorderSizePixel = 0
shootingStar.Visible = false
shootingStar.ZIndex = 2
shootingStar.Parent = galaxyLayer
corner(shootingStar, 1)

local galaxyTime = 0
local galaxyTwinkleAccumulator = 0
local shootingStarCooldown = galaxyRandom:NextNumber(3, 7)
local shootingStarRemaining = 0
local shootingStarDuration = 0.72
local shootingStarStart = Vector2.zero
local shootingStarFinish = Vector2.zero
local function startShootingStar()
    local route = galaxyRandom:NextInteger(1, 4)
    local startX, startY, endX, endY
    if route == 1 then
        startX, startY = galaxyRandom:NextNumber(0.08, 0.86), -0.08
        endX, endY = startX + galaxyRandom:NextNumber(0.18, 0.42), 1.08
    elseif route == 2 then
        startX, startY = 1.08, galaxyRandom:NextNumber(0.08, 0.76)
        endX, endY = -0.08, startY + galaxyRandom:NextNumber(0.18, 0.38)
    elseif route == 3 then
        startX, startY = galaxyRandom:NextNumber(0.14, 0.94), -0.08
        endX, endY = startX - galaxyRandom:NextNumber(0.2, 0.46), 1.08
    else
        startX, startY = -0.08, galaxyRandom:NextNumber(0.08, 0.76)
        endX, endY = 1.08, startY + galaxyRandom:NextNumber(0.18, 0.38)
    end
    shootingStarStart = Vector2.new(startX, startY)
    shootingStarFinish = Vector2.new(endX, endY)
    shootingStarDuration = galaxyRandom:NextNumber(0.45, 0.95)
    shootingStar.Size = UDim2.fromOffset(galaxyRandom:NextInteger(34, 76), galaxyRandom:NextInteger(1, 2))
    shootingStar.Rotation = math.deg(math.atan2(endY - startY, endX - startX))
    shootingStarRemaining = shootingStarDuration
    shootingStar.Visible = true
end

local function updateGalaxy(dt)
    galaxyTime += dt
    if shootingStarRemaining > 0 then
        shootingStarRemaining = math.max(0, shootingStarRemaining - dt)
        local progress = 1 - shootingStarRemaining / shootingStarDuration
        local position = shootingStarStart:Lerp(shootingStarFinish, progress)
        shootingStar.Position = UDim2.new(position.X, 0, position.Y, 0)
        shootingStar.BackgroundTransparency = 1 - math.sin(progress * math.pi) * 0.86
        if shootingStarRemaining == 0 then
            shootingStar.Visible = false
            shootingStarCooldown = galaxyRandom:NextNumber(2.5, 8)
        end
    else
        shootingStarCooldown -= dt
        if shootingStarCooldown <= 0 then
            startShootingStar()
        end
    end

    galaxyTwinkleAccumulator += dt
    local updateTwinkle = galaxyTwinkleAccumulator >= 0.12
    if updateTwinkle then
        galaxyTwinkleAccumulator %= 0.12
    end
    for _, data in ipairs(galaxyStars) do
        if updateTwinkle then
            local twinkle = (math.sin(galaxyTime * data.Rate + data.Phase) + 1) * 0.5
            data.Object.BackgroundTransparency = math.clamp(data.Base + (twinkle - 0.5) * 0.22, 0.08, 0.9)
        end
        data.X += data.DriftX * dt
        data.Y += data.DriftY * dt
        if data.X < 0.02 then data.X = 0.98 elseif data.X > 0.98 then data.X = 0.02 end
        if data.Y < 0.03 then data.Y = 0.97 elseif data.Y > 0.97 then data.Y = 0.03 end
        data.Object.Position = UDim2.new(data.X, 0, data.Y, 0)
    end
end

-- Accent glow in the corner
local glow = Instance.new("Frame")
glow.Size = UDim2.new(1, 0, 1, 0)
glow.BackgroundColor3 = T.Accent
glow.BorderSizePixel = 0
glow.Parent = window
liveCorner(glow, 16)
local gg = Instance.new("UIGradient")
gg.Rotation = 45
gg.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.93),
    NumberSequenceKeypoint.new(0.45, 1),
    NumberSequenceKeypoint.new(1, 0.95),
})
gg.Parent = glow
accentLive(gg)

-- Second, opposing bloom for depth
local glow2 = Instance.new("Frame")
glow2.Size = UDim2.new(1, 0, 1, 0)
glow2.BackgroundColor3 = T.Accent3
glow2.BorderSizePixel = 0
glow2.Parent = window
liveCorner(glow2, 16)
local gg2 = Instance.new("UIGradient")
gg2.Rotation = 225
gg2.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.95),
    NumberSequenceKeypoint.new(0.5, 1),
    NumberSequenceKeypoint.new(1, 0.9),
})
gg2.Parent = glow2
accentLive(gg2, 0.5)

-- Top hairline: the animated accent rule that makes it feel "live"
-- Vignette / scanline wash across the whole menu
local vignette = Instance.new("Frame")
vignette.Name = "Vignette"
vignette.Size = UDim2.new(1, 0, 1, 0)
vignette.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
vignette.BackgroundTransparency = 0.97
vignette.BorderSizePixel = 0
vignette.ZIndex = 1
vignette.Parent = window
liveCorner(vignette, 16)
local vg = Instance.new("UIGradient")
vg.Rotation = 90
vg.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.75),
    NumberSequenceKeypoint.new(0.35, 1),
    NumberSequenceKeypoint.new(1, 0.85),
})
vg.Parent = vignette

-- Sidebar ------------------------------------------------------------
local SB_W = 88

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, SB_W, 1, 0)
sidebar.BackgroundColor3 = Color3.fromRGB(8, 8, 8)
sidebar.BackgroundTransparency = 0.06
sidebar.Parent = window
sidebar.ZIndex = 2

local logoBar = Instance.new("Frame")
logoBar.Size = UDim2.new(0, 4, 0, 24)
logoBar.Position = UDim2.new(0, 22, 0, 18)
logoBar.BackgroundColor3 = T.Accent
logoBar.BorderSizePixel = 0
logoBar.Parent = sidebar
corner(logoBar, 2)
local logoGrad = gradient(logoBar, 90, T.Accent, T.Accent3)
accentLive(logoGrad, 1.1)

local logoText = label(sidebar, "MILITARY", 17, Enum.Font.GothamBold, T.Text)
logoText.Position = UDim2.new(0, 38, 0, 18)
logoText.Size = UDim2.new(1, -48, 0, 24)
logoText.TextTransparency = 0.05

-- Blinking "online" pip next to the logo
local statusDot = Instance.new("Frame")
statusDot.Size = UDim2.new(0, 6, 0, 6)
statusDot.Position = UDim2.new(0, 12, 0, 27)
statusDot.BackgroundColor3 = T.Accent
statusDot.BorderSizePixel = 0
statusDot.Parent = sidebar
corner(statusDot, 3)
accentDot(statusDot, 2.2)

local logoDiv = Instance.new("Frame")
logoDiv.Size = UDim2.new(1, -32, 0, 1)
logoDiv.Position = UDim2.new(0, 16, 0, 56)
logoDiv.BackgroundColor3 = T.Line
logoDiv.BorderSizePixel = 0
logoDiv.Parent = sidebar
corner(logoDiv, 1)
logoBar.Visible = false
logoText.Visible = false
statusDot.Visible = false
logoDiv.Visible = false

local nav = Instance.new("ScrollingFrame")
nav.Size = UDim2.new(1, -8, 1, -70)
nav.Position = UDim2.new(0, 4, 0, 8)
nav.BackgroundTransparency = 1
nav.BorderSizePixel = 0
nav.ScrollBarThickness = 0
nav.AutomaticCanvasSize = Enum.AutomaticSize.Y
nav.CanvasSize = UDim2.new(0, 0, 0, 0)
nav.Parent = sidebar
local navLayout = Instance.new("UIListLayout")
navLayout.Padding = UDim.new(0, 8); navLayout.Parent = nav

local sideTexts = {}

local function sideButton(parentFrame, icon, text)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(1, 0, 0, 58)
    b.BackgroundColor3 = T.Accent
    b.BackgroundTransparency = 1
    b.Text = ""; b.AutoButtonColor = false
    b.Parent = parentFrame
    corner(b, 8)
    local ic = label(b, icon, 22, Enum.Font.GothamBold, T.Sub, Enum.TextXAlignment.Center)
    ic.Size = UDim2.new(1, 0, 0, 35)
    ic.Position = UDim2.new(0, 0, 0, 0)
    ic.ZIndex = 2
    ic.Name = "SideIcon"
    local tx = label(b, text, 11, Enum.Font.GothamMedium, T.Sub, Enum.TextXAlignment.Center)
    tx.Position = UDim2.new(0, -2, 0, 35)
    tx.Size = UDim2.new(1, 4, 0, 16)
    tx.ZIndex = 2
    tx.Name = "SideLabel"
    table.insert(sideTexts, tx)
    return b, ic, tx
end

-- Top bar: search ----------------------------------------------------
local searchBox = Instance.new("Frame")
searchBox.AnchorPoint = Vector2.new(0.5, 0)
searchBox.Size = UDim2.new(0, 360, 0, 38)
searchBox.Position = UDim2.new(0.5, 40, 0, 11)
searchBox.BackgroundColor3 = T.Panel
searchBox.Parent = window
searchBox.Visible = false
liveCorner(searchBox, 19)
local searchStroke = stroke(searchBox, T.Line, 1, 0)
noise(searchBox, 0.985)

local sIcon = label(searchBox, "🔍", 14, Enum.Font.Gotham, T.Sub, Enum.TextXAlignment.Center)
sIcon.Size = UDim2.new(0, 36, 1, 0)
sIcon.ZIndex = 2

local search = Instance.new("TextBox")
search.Size = UDim2.new(1, -50, 1, 0)
search.Position = UDim2.new(0, 36, 0, 0)
search.BackgroundTransparency = 1
search.Text = ""
search.PlaceholderText = "Search options..."
search.PlaceholderColor3 = T.Sub
search.TextColor3 = T.Text
search.TextXAlignment = Enum.TextXAlignment.Left
search.Font = Enum.Font.Gotham
search.TextSize = 14
search.ClearTextOnFocus = false
search.ZIndex = 2
search.Parent = searchBox
search.Focused:Connect(function()
    tween(searchStroke, 0.2, {Color = T.Accent, Transparency = 0})
    tween(sIcon, 0.2, {TextColor3 = T.Accent})
end)
search.FocusLost:Connect(function()
    tween(searchStroke, 0.2, {Color = T.Line})
    tween(sIcon, 0.2, {TextColor3 = T.Sub})
end)

-- Badge
local badge = Instance.new("Frame")
badge.AnchorPoint = Vector2.new(1, 0)
badge.Size = UDim2.new(0, 84, 0, 26)
badge.Position = UDim2.new(1, -16, 0, 17)
badge.BackgroundColor3 = T.Accent
badge.Parent = window
badge.Visible = false
corner(badge, 6)
local badgeGrad = gradient(badge, 20, T.Accent, T.Accent3)
accentLive(badgeGrad, 0.45)
local badgeText = label(badge, "✦  v1.0", 12, Enum.Font.GothamBold, T.Text, Enum.TextXAlignment.Center)
badgeText.Size = UDim2.new(1, 0, 1, 0)

-- Content panel ------------------------------------------------------
local content = Instance.new("Frame")
content.Position = UDim2.new(0, SB_W, 0, 0)
content.Size = UDim2.new(1, -SB_W, 1, 0)
content.BackgroundColor3 = T.Panel
content.BackgroundTransparency = 0.48
content.ZIndex = 2
content.ClipsDescendants = true
content.Parent = window
local contentGrad = Instance.new("UIGradient")
contentGrad.Rotation = 145
contentGrad.Color = ColorSequence.new(Color3.fromRGB(9, 9, 9), Color3.fromRGB(9, 9, 9))
contentGrad.Transparency = NumberSequence.new(0.55)
contentGrad.Parent = content

-- Tabs ---------------------------------------------------------------
local tabs, currentTab = {}, nil
local pageTitle = label(content, "", 13, Enum.Font.GothamBold, T.Text)
pageTitle.Position = UDim2.new(0, 78, 0, 32)
pageTitle.Size = UDim2.new(0, 180, 0, 20)
pageTitle.ZIndex = 5

local titleUnderline = Instance.new("Frame")
titleUnderline.Size = UDim2.new(0, 88, 0, 3)
titleUnderline.Position = UDim2.new(0, 48, 0, 83)
titleUnderline.BackgroundColor3 = T.Accent
titleUnderline.BorderSizePixel = 0
titleUnderline.ZIndex = 5
titleUnderline.Parent = content
corner(titleUnderline, 2)
local titleUnderlineGradient = gradient(titleUnderline, 0, T.Accent, T.Accent2)
accentLive(titleUnderlineGradient, 0.7)

local function createTab(name, icon, displayName)
    displayName = displayName or name
    local btn, ic, tx = sideButton(nav, icon, displayName)

    local page = Instance.new("ScrollingFrame")
    page.Position = UDim2.new(0, 0, 0, 94)
    page.Size = UDim2.new(1, 0, 1, -94)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 2
    page.ScrollBarImageColor3 = T.Accent
    page.AutomaticCanvasSize = Enum.AutomaticSize.None
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.Visible = false
    page.Parent = content
    local l = Instance.new("UIListLayout"); l.Padding = UDim.new(0, 2); l.Parent = page
    local p = Instance.new("UIPadding")
    p.PaddingTop = UDim.new(0, 4); p.PaddingLeft = UDim.new(0, 12)
    p.PaddingRight = UDim.new(0, 24); p.PaddingBottom = UDim.new(0, 20)
    p.Parent = page
    local function updateCanvasSize()
        page.CanvasSize = UDim2.new(0, 0, 0, l.AbsoluteContentSize.Y + p.PaddingTop.Offset + p.PaddingBottom.Offset)
    end
    l:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasSize)
    updateCanvasSize()

    local tab = {Btn = btn, Icon = ic, Text = tx, Page = page, Items = {}, IconParts = {}, DisplayName = displayName}
    tabs[name] = tab
    local iconScale

    local function addIconPart(part, parent)
        part.BorderSizePixel = 0
        part.BackgroundColor3 = T.Sub
        part.ZIndex = 3
        part.Parent = parent or btn
        table.insert(tab.IconParts, {Object = part, Property = "BackgroundColor3"})
        return part
    end

    if name == "Aimbot" or name == "Main" then
        ic.Visible = false
        local iconScaleFrame = Instance.new("Frame")
        iconScaleFrame.Name = "CustomIcon"
        iconScaleFrame.Size = UDim2.fromOffset(27, 27)
        iconScaleFrame.Position = UDim2.new(0.5, -13.5, 0, 0)
        iconScaleFrame.BackgroundTransparency = 1
        iconScaleFrame.ZIndex = 3
        iconScaleFrame.Parent = btn

        if name == "Aimbot" then
            local ring = Instance.new("Frame")
            ring.Size = UDim2.fromOffset(17, 17)
            ring.Position = UDim2.fromOffset(7.5, 7.5)
            ring.BackgroundTransparency = 1
            ring.BorderSizePixel = 0
            ring.ZIndex = 3
            ring.Parent = iconScaleFrame
            corner(ring, 9)
            local ringStroke = Instance.new("UIStroke")
            ringStroke.Color = T.Sub
            ringStroke.Thickness = 1.6
            ringStroke.Parent = ring
            table.insert(tab.IconParts, {Object = ringStroke, Property = "Color"})

            local function aimTick(size, position)
                local tick = Instance.new("Frame")
                tick.Size = size
                tick.Position = position
                addIconPart(tick, iconScaleFrame)
                corner(tick, math.min(size.X.Offset, size.Y.Offset) / 2)
            end
            aimTick(UDim2.fromOffset(2, 7), UDim2.new(0.5, -1, 0, 0))
            aimTick(UDim2.fromOffset(2, 7), UDim2.new(0.5, -1, 1, -7))
            aimTick(UDim2.fromOffset(7, 2), UDim2.new(0, 0, 0.5, -1))
            aimTick(UDim2.fromOffset(7, 2), UDim2.new(1, -7, 0.5, -1))
            local centerDot = Instance.new("Frame")
            centerDot.Size = UDim2.fromOffset(4, 4)
            centerDot.Position = UDim2.new(0.5, -2, 0.5, -2)
            addIconPart(centerDot, iconScaleFrame)
            corner(centerDot, 2)
        else
            for index = 1, 3 do
                local y = 2 + (index - 1) * 7
                local track = Instance.new("Frame")
                track.Size = UDim2.fromOffset(22, 2)
                track.Position = UDim2.fromOffset(2.5, y + 2)
                addIconPart(track, iconScaleFrame)
                corner(track, 1)

                local knob = Instance.new("Frame")
                knob.Size = UDim2.fromOffset(6, 6)
                knob.Position = UDim2.fromOffset(index == 2 and 16 or 6, y)
                addIconPart(knob, iconScaleFrame)
                corner(knob, 3)
            end
        end

        iconScale = Instance.new("UIScale")
        iconScale.Scale = 1
        iconScale.Parent = iconScaleFrame
        tab.IconScale = iconScale
    else
        iconScale = Instance.new("UIScale")
        iconScale.Scale = 1
        iconScale.Parent = ic
        tab.IconScale = iconScale
    end

    local function tintIcon(color, duration)
        if #tab.IconParts == 0 then
            tween(ic, duration, {TextColor3 = color})
            return
        end
        for _, entry in ipairs(tab.IconParts) do
            tween(entry.Object, duration, {[entry.Property] = color})
        end
    end

    local function setHover(on)
        if currentTab == tab then return end
        tween(btn, 0.18, {BackgroundTransparency = on and 0.82 or 1})
        tintIcon(on and T.Text or T.Sub, 0.18)
    end

    btn.MouseEnter:Connect(function()
        setHover(true)
        if currentTab ~= tab then
            tintIcon(T.Text, 0.18)
            tween(tx, 0.18, {TextColor3 = T.Text})
            tween(iconScale, 0.18, {Scale = 1.12})
        end
    end)
    btn.MouseLeave:Connect(function()
        setHover(false)
        if currentTab ~= tab then
            tintIcon(T.Sub, 0.18)
            tween(tx, 0.18, {TextColor3 = T.Sub})
            tween(iconScale, 0.18, {Scale = 1})
        end
    end)

    local function selectTab()
        if currentTab == tab then return end
        if currentTab then
            currentTab.Page.Visible = false
            for _, entry in ipairs(currentTab.IconParts) do
                tween(entry.Object, 0.25, {[entry.Property] = T.Sub})
            end
            if #currentTab.IconParts == 0 then
                tween(currentTab.Icon, 0.25, {TextColor3 = T.Sub})
            end
            tween(currentTab.Text, 0.25, {TextColor3 = T.Sub})
            tween(currentTab.Btn, 0.25, {BackgroundTransparency = 1})
            tween(currentTab.IconScale, 0.25, {Scale = 1})
        end
        currentTab = tab
        page.Visible = true
        pageTitle.Text = displayName
        tween(tx, 0.25, {TextColor3 = T.Text})
        tween(btn, 0.25, {BackgroundTransparency = 0.88})
        tintIcon(T.Accent, 0.25)
        tween(iconScale, 0.25, {Scale = 1.1})
        search.Text = ""

        -- Page entry: slide + fade the list layout
        l.Padding = UDim.new(0, 0)
        tween(l, 0.3, {Padding = UDim.new(0, 2)})
        page.CanvasPosition = anim.Enabled and Vector2.new(0, 6) or Vector2.new(0, 0)
        tween(page, 0.3, {CanvasPosition = Vector2.new(0, 0)})
    end
    tab.Select = selectTab
    btn.MouseButton1Click:Connect(selectTab)
    return tab
end

-- Search filter
search:GetPropertyChangedSignal("Text"):Connect(function()
    if not currentTab then return end
    local q = search.Text:lower()
    for _, item in ipairs(currentTab.Items) do
        item.Frame.Visible = (q == "") or (item.Name:lower():find(q, 1, true) ~= nil)
    end
end)

-- Components ---------------------------------------------------------
local function section(tab, title)
    local h = Instance.new("Frame")
    h.Size = UDim2.new(1, 0, 0, 24)
    h.BackgroundTransparency = 1
    h.Parent = tab.Page
    -- Small accent tick to the left of the header text
    local tick = Instance.new("Frame")
    tick.Size = UDim2.new(0, 3, 0, 12)
    tick.Position = UDim2.new(0, 0, 0, 3)
    tick.BackgroundColor3 = T.Accent
    tick.BorderSizePixel = 0
    tick.Parent = h
    corner(tick, 2)
    local tickGrad = gradient(tick, 90, T.Accent, T.Accent3)
    accentLive(tickGrad, 0.9)

    local t = label(h, title:upper(), 11, Enum.Font.GothamBold, T.Sub)
    t.Position = UDim2.new(0, 12, 0, 0)
    t.Size = UDim2.new(1, -12, 0, 18)

    local line = Instance.new("Frame")
    line.Size = UDim2.new(1, 0, 0, 1)
    line.Position = UDim2.new(0, 0, 1, -1)
    line.BackgroundColor3 = T.Line
    line.BorderSizePixel = 0
    line.Parent = h
    corner(line, 1)
    local lg = Instance.new("UIGradient")
    lg.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.2),
        NumberSequenceKeypoint.new(1, 1),
    })
    lg.Parent = line
end

local function setCardSelected(card, on)
    local txt = card:FindFirstChild("Txt")
    local fill = card:FindFirstChild("__Fill")
    tween(card, 0.25, {BackgroundColor3 = on and Color3.fromRGB(18, 18, 20) or T.Card})
    tween(txt, 0.25, {TextColor3 = on and T.Accent or T.Text})
    card.UIStroke.Color = on and T.Accent or T.Line
    card.UIStroke.Transparency = on and 0.55 or 0.3
    if fill then tween(fill, 0.25, {BackgroundTransparency = on and 0.9 or 1}) end
    if on then
        -- Selection kick: brief scale pop
        local base = card.Size
        card.Size = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, base.Y.Offset + 2)
        tween(card, 0.22, {Size = base})
    end
end

-- Grid of selectable cards (single choice)
local function selectGrid(tab, options, default, callback, columns)
    columns = columns or 4
    local grid = Instance.new("Frame")
    grid.Size = UDim2.new(1, 0, 0, 0)
    grid.AutomaticSize = Enum.AutomaticSize.Y
    grid.BackgroundTransparency = 1
    grid.Parent = tab.Page
    local gl = Instance.new("UIGridLayout")
    gl.CellPadding = UDim2.new(0, 8, 0, 8)
    gl.CellSize = UDim2.new(1 / columns, -8 * (columns - 1) / columns, 0, 40)
    gl.SortOrder = Enum.SortOrder.LayoutOrder
    gl.Parent = grid

    local cards = {}
    for i, opt in ipairs(options) do
        local c = Instance.new("TextButton")
        c.LayoutOrder = i
        c.BackgroundColor3 = T.Card
        c.Text = ""; c.AutoButtonColor = false
        c.Parent = grid
        liveCorner(c, 10)
        stroke(c, T.Line, 1, 0.3)
        local fill = Instance.new("Frame")
        fill.Name = "__Fill"
        fill.Size = UDim2.new(1, 0, 1, 0)
        fill.BackgroundColor3 = T.Accent
        fill.BackgroundTransparency = 1
        fill.ZIndex = 0
        fill.Parent = c
        corner(fill, 8)
        local t = label(c, opt, 14, Enum.Font.GothamMedium, T.Text)
        t.Name = "Txt"
        t.Position = UDim2.new(0, 14, 0, 0)
        t.Size = UDim2.new(1, -20, 1, 0)
        cards[opt] = c
        table.insert(tab.Items, {Frame = c, Name = opt})

        c.MouseEnter:Connect(function()
            if c.BackgroundColor3 == T.Card then tween(c, 0.15, {BackgroundColor3 = T.CardHi}) end
        end)
        c.MouseLeave:Connect(function()
            if c.Txt.TextColor3 ~= T.Accent then tween(c, 0.15, {BackgroundColor3 = T.Card}) end
        end)
        c.MouseButton1Click:Connect(function()
            for name, other in pairs(cards) do setCardSelected(other, name == opt) end
            if callback then callback(opt) end
        end)
    end
    if default and cards[default] then setCardSelected(cards[default], true) end
end

local optionDescriptions = {
    ["Enable Aimbot"] = "Enable target tracking and aim assistance.",
    ["Enable ESP"] = "Display visual information for other players.",
    ["Show Names"] = "Display player names above their characters.",
    ["Tracers"] = "Draw lines from the screen to visible players.",
    ["Health Bar"] = "Show each player's remaining health.",
    ["Unlimited Distance"] = "Remove the maximum ESP distance limit.",
    ["FPS Counter"] = "Show a live client frame-rate readout.",
    ["Clock"] = "Show your local time on screen.",
    ["Center Crosshair"] = "Show a small, rounded screen-center crosshair.",
    ["Target Indicator"] = "Display the current aimbot target while the menu is hidden.",
    ["Animations"] = "Enable animated menu accents.",
    ["Godmode"] = "Prevent death by restoring your health whenever you would die.",
    ["Optimize Game"] = "Hide world and sky textures and disable shadows; toggle off to restore them.",
    ["Menu Blur / Vignette"] = "Add a soft vignette around the menu.",
    ["Noclip"] = "Disable character collisions while enabled.",
    ["Strength (1 = assist, 100 = snap)"] = "Adjust how strongly aim follows the target.",
    ["FOV"] = "Set the radius used to find targets.",
    ["Max Distance"] = "Set the maximum distance for player visuals.",
    ["UI Scale (%)"] = "Resize the interface to fit your screen.",
    ["Movement Speed"] = "Set character movement speed.",
}

local function toggle(tab, text, default, callback)
    local state = default or false
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 54)
    row.BackgroundColor3 = T.Card
    row.BackgroundTransparency = 1
    row.Text = ""; row.AutoButtonColor = false
    row.Parent = tab.Page
    table.insert(tab.Items, {Frame = row, Name = text})

    local l = label(row, text, 14, Enum.Font.GothamMedium, T.Text)
    l.Position = UDim2.new(0, 0, 0, 3); l.Size = UDim2.new(1, -84, 0, 20)
    l.ZIndex = 2

    local description = label(row, optionDescriptions[text] or "", 12, Enum.Font.Gotham, T.Sub)
    description.Position = UDim2.new(0, 0, 0, 24)
    description.Size = UDim2.new(1, -84, 0, 17)
    description.ZIndex = 2

    local sw = Instance.new("Frame")
    sw.Size = UDim2.new(0, 50, 0, 20)
    sw.Position = UDim2.new(1, -50, 0.5, -10)
    sw.BackgroundColor3 = state and T.Accent or Color3.fromRGB(26, 26, 28)
    sw.Parent = row
    liveCorner(sw, 11)
    if state then
        local sg = gradient(sw, 0, T.Accent, T.Accent2)
        accentLive(sg, 1.5)
    end
    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.Position = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.Parent = sw
    liveCorner(knob, 8)

    -- Glow halo behind the switch when active
    local halo = Instance.new("Frame")
    halo.Name = "__Halo"
    halo.Size = UDim2.new(1, 8, 1, 8)
    halo.Position = UDim2.new(0, -4, 0, -4)
    halo.BackgroundColor3 = T.Accent
    halo.BackgroundTransparency = 1
    halo.BorderSizePixel = 0
    halo.ZIndex = 0
    halo.Parent = sw
    corner(halo, 14)

    local function apply(on, animate)
        local t = animate and 0.25 or 0
        if t > 0 then
            tween(sw, t, {BackgroundColor3 = on and T.Accent or Color3.fromRGB(26, 26, 28)})
            tween(knob, t, {Position = on and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)})
            tween(halo, t, {BackgroundTransparency = on and 0.85 or 1})
            tween(l, t, {TextColor3 = on and T.Text or Color3.fromRGB(200, 200, 202)})
        else
            sw.BackgroundColor3 = on and T.Accent or Color3.fromRGB(26, 26, 28)
            knob.Position = on and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
            halo.BackgroundTransparency = on and 0.85 or 1
        end
    end
    apply(state, false)

    row.MouseEnter:Connect(function() tween(description, 0.15, {TextColor3 = T.Text}) end)
    row.MouseLeave:Connect(function() tween(description, 0.15, {TextColor3 = T.Sub}) end)
    local function setValue(value, animate)
        if state == value then return end
        state = value
        if callback then callback(state) end
        apply(state, animate ~= false)
    end
    row.MouseButton1Click:Connect(function()
        setValue(not state, true)
    end)
    return function(value)
        setValue(value, false)
    end
end

local function slider(tab, text, min, max, default, callback)
    local value = default or min
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 58)
    row.BackgroundColor3 = T.Card
    row.BackgroundTransparency = 1
    row.Parent = tab.Page
    table.insert(tab.Items, {Frame = row, Name = text})

    local l = label(row, text, 14, Enum.Font.GothamMedium, T.Text)
    l.Position = UDim2.new(0, 0, 0, 5); l.Size = UDim2.new(0.6, -70, 0, 20)

    local description = label(row, optionDescriptions[text] or "", 12, Enum.Font.Gotham, T.Sub)
    description.Position = UDim2.new(0, 0, 0, 27)
    description.Size = UDim2.new(0.62, -70, 0, 18)

    -- Value chip
    local chip = Instance.new("Frame")
    chip.Name = "__Chip"
    chip.Size = UDim2.new(0, 52, 0, 22)
    chip.Position = UDim2.new(1, -52, 0.5, -11)
    chip.BackgroundColor3 = Color3.fromRGB(20, 20, 21)
    chip.Parent = row
    liveCorner(chip, 6)
    stroke(chip, T.Accent, 1, 0.75)
    local v = label(chip, tostring(value), 13, Enum.Font.GothamBold, T.Accent, Enum.TextXAlignment.Center)
    v.Size = UDim2.new(1, 0, 1, 0)

    local track = Instance.new("Frame")
    track.Size = UDim2.new(0.24, 0, 0, 6)
    track.Position = UDim2.new(0.70, 0, 0.5, -3)
    track.BackgroundColor3 = Color3.fromRGB(26, 26, 28)
    track.Parent = row
    liveCorner(track, 3)
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((value - min) / (max - min), 0, 1, 0)
    fill.BackgroundColor3 = T.Accent
    fill.Parent = track
    corner(fill, 3)
    local fillGrad = gradient(fill, 0, T.Accent, T.Accent2)
    accentLive(fillGrad, 1.3)

    -- Draggable thumb riding the fill edge
    local thumb = Instance.new("Frame")
    thumb.Name = "__Thumb"
    thumb.Size = UDim2.new(0, 10, 0, 10)
    thumb.AnchorPoint = Vector2.new(0.5, 0.5)
    thumb.Position = UDim2.new((value - min) / (max - min), 0, 0.5, 0)
    thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    thumb.BorderSizePixel = 0
    thumb.ZIndex = 3
    thumb.Parent = track
    corner(thumb, 5)
    local thumbStroke = stroke(thumb, T.Accent, 2, 0)

    local dragging = false
    local function update(x)
        local rel = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        value = math.floor(min + (max - min) * rel + 0.5)
        v.Text = tostring(value)
        tween(fill, 0.08, {Size = UDim2.new(rel, 0, 1, 0)})
        tween(thumb, 0.08, {Position = UDim2.new(rel, 0, 0.5, 0)})
        if callback then callback(value) end
    end
    local function beginDrag(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            if dragging then return end
            dragging = true
            tween(thumb, 0.15, {Size = UDim2.new(0, 14, 0, 14)})
            tween(row, 0.15, {BackgroundColor3 = T.CardHi})
            update(i.Position.X)
        end
    end
    track.InputBegan:Connect(beginDrag)
    thumb.InputBegan:Connect(beginDrag)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            update(i.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            tween(thumb, 0.15, {Size = UDim2.new(0, 10, 0, 10)})
            tween(row, 0.15, {BackgroundColor3 = T.Card})
        end
    end)
end

-- Build tabs ---------------------------------------------------------
local esp      = createTab("ESP",        "◉", "Visuals")
local aimbot   = createTab("Aimbot",     "")
local main     = createTab("Main",       "", "Misc")
local settings = createTab("Settings",   "⚙")
local config   = createTab("Config",     "▤", "Configs")
local keybinds = createTab("Keybinds",   "⌘")

-- Shared overlay GUI for aim visuals, ESP, and optional Misc widgets.
-- It stays below the menu and remains visible when the menu is hidden.
local espGui = Instance.new("ScreenGui")
espGui.Name = "MT_ESP"
espGui.ResetOnSpawn = false
espGui.IgnoreGuiInset = true
espGui.DisplayOrder = 5
espGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
espGui.Parent = (gethui and gethui()) or player:WaitForChild("PlayerGui")

-- Aimbot --------------------------------------------------------------
local Aim = {
    Enabled   = false,        -- master on/off
    Target    = "Head",       -- Head / Legs / Chest
    Mode      = "Hold",       -- Hold / Toggle / Always
    Strength  = 50,           -- 1 = barely helps, 100 = instant snap
    FOV       = 120,          -- screen radius in pixels that locks on
    Holding   = false,
    Toggled   = false,
    Locked    = nil,          -- current target Player
}

-- FOV circle drawn in the ESP gui so it matches the tracer layer
local aimFovCircle = Instance.new("Frame")
aimFovCircle.Name = "AimFOV"
aimFovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
aimFovCircle.BackgroundTransparency = 1
aimFovCircle.BorderSizePixel = 0
aimFovCircle.Visible = false
aimFovCircle.ZIndex = 4
aimFovCircle.Parent = espGui
corner(aimFovCircle, 999)
local aimFovStroke = stroke(aimFovCircle, T.Accent, 1, 0.45)

-- Crosshair dot in the middle of the FOV ring
local aimDot = Instance.new("Frame")
aimDot.Name = "AimDot"
aimDot.AnchorPoint = Vector2.new(0.5, 0.5)
aimDot.Size = UDim2.fromOffset(4, 4)
aimDot.BackgroundColor3 = T.Accent
aimDot.BorderSizePixel = 0
aimDot.ZIndex = 5
aimDot.Visible = false
aimDot.Parent = espGui
corner(aimDot, 2)

local function aimActive()
    if not Aim.Enabled then return false end
    if Aim.Mode == "Always" then return true end
    if Aim.Mode == "Toggle" then return Aim.Toggled end
    return Aim.Holding
end

-- Closest point on a character to the screen centre, in pixels
local function screenDistanceTo(part)
    local sp, onScreen = camera:WorldToViewportPoint(part.Position)
    if not onScreen or sp.Z <= 0 then return nil end
    local centre = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    return (Vector2.new(sp.X, sp.Y) - centre).Magnitude
end

-- Where on the body to aim
local function getAimPart(char)
    if Aim.Target == "Head" then
        return char:FindFirstChild("Head")
            or char:FindFirstChild("UpperTorso")
            or char:FindFirstChild("Torso")
    elseif Aim.Target == "Chest" then
        return char:FindFirstChild("UpperTorso")
            or char:FindFirstChild("Torso")
            or char:FindFirstChild("Head")
    elseif Aim.Target == "Legs" then
        local candidates = {
            char:FindFirstChild("LeftUpperLeg"),
            char:FindFirstChild("RightUpperLeg"),
            char:FindFirstChild("Left Leg"),
            char:FindFirstChild("Right Leg"),
            char:FindFirstChild("LeftLowerLeg"),
            char:FindFirstChild("RightLowerLeg"),
        }
        local closest, closestDistance = nil, math.huge
        for _, part in ipairs(candidates) do
            if part then
                local distance = screenDistanceTo(part)
                if distance and distance < closestDistance then
                    closest, closestDistance = part, distance
                end
            end
        end
        if closest then return closest end
    end

    -- Fall back to a central body part if the requested part is unavailable.
    return char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso")
        or char:FindFirstChild("Head")
        or char:FindFirstChild("HumanoidRootPart")
end

local Esp

local function isWithinEspDistance(char)
    if not char then return false end
    if Esp.UnlimitedDistance then return true end

    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    local dist = (hrp.Position - camera.CFrame.Position).Magnitude
    return dist <= Esp.MaxDist
end

local function canAimAt(char)
    if not char then return false end
    if not Esp.Enabled then return true end
    return isWithinEspDistance(char)
end

local function getTargetPart(p)
    if p == player then return nil end

    local char = p.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not hum or hum.Health <= 0 then return nil end

    local part = getAimPart(char)
    if not part then return nil end

    if not canAimAt(char) then return nil end

    local distance = screenDistanceTo(part)
    if not distance or distance > Aim.FOV then
        return nil
    end

    return part, distance
end

local function pickTarget()
    local best, bestDist = nil, math.huge
    for _, p in ipairs(Players:GetPlayers()) do
        local _, distance = getTargetPart(p)
        if distance and distance < bestDist then
            bestDist, best = distance, p
        end
    end
    return best
end

-- The actual aim step, run on the camera priority so it always wins
local function aimStep(dt)
    local vp = camera.ViewportSize
    local centre = Vector2.new(vp.X / 2, vp.Y / 2)

    -- Keep the FOV ring glued to the crosshair
    if Aim.Enabled then
        aimFovCircle.Size = UDim2.fromOffset(Aim.FOV * 2, Aim.FOV * 2)
        aimFovCircle.Position = UDim2.fromOffset(centre.X, centre.Y)
        aimFovCircle.Visible = true
        aimDot.Position = UDim2.fromOffset(centre.X, centre.Y)
        aimDot.Visible = true
    else
        aimFovCircle.Visible = false
        aimDot.Visible = false
    end

    if not aimActive() then
        Aim.Locked = nil
        return
    end

    local target = pickTarget()
    Aim.Locked = target
    if not target then return end

    local char = target.Character
    if not char then return end
    local part = getAimPart(char)
    if not part then return end

    -- Rotate the camera toward the aim point.
    -- Strength 1  -> alpha ~0.02 (a gentle nudge, like aim assist)
    -- Strength 100 -> alpha 1    (instant snap)
    local alpha = math.clamp(Aim.Strength / 100, 0.01, 1)
    -- Frame-rate independent easing so 1-100 feels the same at any FPS
    local k = 1 - (1 - alpha) ^ (dt * 60)

    local current = camera.CFrame
    local goal = CFrame.lookAt(current.Position, part.Position)
    camera.CFrame = current:Lerp(goal, k)
end

-- Priority 200 = Camera: runs after the default camera updates, so our
-- rotation is not overwritten by the built-in mouse-look each frame.
RunService:BindToRenderStep("MT_Aimbot", Enum.RenderPriority.Camera.Value + 1, aimStep)

-- Aimbot tab
section(aimbot, "Target selection")
selectGrid(aimbot, {"Head", "Legs", "Chest"}, "Head", function(v)
    Aim.Target = v
    print("Target:", v)
end, 3)
section(aimbot, "Activation")
selectGrid(aimbot, {"Hold", "Toggle", "Always"}, "Hold", function(v)
    Aim.Mode = v
    print("Mode:", v)
end, 3)
section(aimbot, "Options")
local setAimEnabledToggle = toggle(aimbot, "Enable Aimbot", false, function(v)
    Aim.Enabled = v
    if not v then
        Aim.Locked = nil
        Aim.Holding = false
        Aim.Toggled = false
    end
    notify("Aimbot", v and "Aimbot enabled." or "Aimbot disabled.")
    print("Aimbot:", v)
end)
slider(aimbot, "Strength (1 = assist, 100 = snap)", 1, 100, 50, function(v)
    Aim.Strength = v
    print("Strength:", v)
end)
slider(aimbot, "FOV", 10, 500, 120, function(v)
    Aim.FOV = v
    print("FOV:", v)
end)

-- ESP (real, working draw engine) ------------------------------------
Esp = {
    Enabled  = false,
    Style    = "Box",
    Names    = false,
    Health   = false,
    Tracers  = false,
    MaxDist  = 1000,
    UnlimitedDistance = false,
    Objects  = {},   -- [Player] = {Frame, Stroke, Name, Hp, Fill, Line}
}

local function espColor(p)
    if p.Team then return p.Team.TeamColor.Color end
    return T.Accent
end

local function boxVisible()
    return Esp.Enabled and (Esp.Style == "Box" or Esp.Style == "Outline" or Esp.Style == "Corner")
end

local function setTracerLine(line, from, to)
    local delta = to - from
    line.Position = UDim2.fromOffset(from.X, from.Y)
    line.Size = UDim2.fromOffset(delta.Magnitude, line.Size.Y.Offset)
    line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
end

local function createEsp(p)
    local col = espColor(p)

    -- Main box frame (also the visual anchor for name + health bar)
    local f = Instance.new("Frame")
    f.Name = p.Name
    f.BackgroundTransparency = 1
    f.BorderSizePixel = 0
    f.ClipsDescendants = false
    f.Visible = boxVisible()
    f.Parent = espGui
    corner(f, 7)
    if Esp.Style == "Outline" then
        f.BackgroundTransparency = 0.7
        f.BackgroundColor3 = col
    end
    local s = Instance.new("UIStroke")
    s.Color = col
    s.Thickness = Esp.Style == "Outline" and 2 or 1.5
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = f

    -- Name
    local name = Instance.new("TextLabel")
    name.BackgroundTransparency = 1
    name.Text = p.Name
    name.TextSize = 12
    name.Font = Enum.Font.GothamBold
    name.TextColor3 = col
    name.TextStrokeTransparency = 0.35
    name.TextStrokeColor3 = Color3.new(0, 0, 0)
    name.Size = UDim2.new(1, 0, 0, 14)
    name.Position = UDim2.new(0, 0, 0, -16)
    name.Visible = Esp.Names
    name.Parent = f

    -- Health bar
    local hp = Instance.new("Frame")
    hp.Name = "Hp"
    hp.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    hp.BackgroundTransparency = 0.4
    hp.BorderSizePixel = 0
    hp.Size = UDim2.new(0, 3, 1, 0)
    hp.Position = UDim2.new(0, 4, 0, 0)
    hp.Visible = Esp.Health
    hp.Parent = f
    corner(hp, 2)
    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    fill.BorderSizePixel = 0
    fill.AnchorPoint = Vector2.new(0, 1)
    fill.Position = UDim2.new(0, 0, 1, 0)
    fill.Size = UDim2.new(1, 0, 1, 0)
    fill.Parent = hp
    corner(fill, 2)

    -- Tracer rendered as a thin rotated frame in the ESP ScreenGui.
    -- ZIndex must be >= 2: the menu ScreenGui has DisplayOrder 100 and
    -- covers the screen, so anything drawn at ZIndex 1 would be hidden.
    local tr = Instance.new("Frame")
    tr.Name = p.Name
    tr.AnchorPoint = Vector2.new(0, 0.5)
    tr.Size = UDim2.fromOffset(0, 1.5)
    tr.BackgroundColor3 = col
    tr.BackgroundTransparency = 0.4
    tr.BorderSizePixel = 0
    tr.ZIndex = 4
    tr.Visible = false
    tr.Parent = espGui
    corner(tr, 2)

    Esp.Objects[p] = {Frame = f, Stroke = s, Name = name, Hp = hp, Fill = fill, Line = tr}

    -- Never let a freshly added player's tracer sit on a degenerate line
    if Esp.Origin and Esp.Origin2 then
        setTracerLine(tr, Esp.Origin, Esp.Origin2)
    end
end

local function removeEsp(p)
    local o = Esp.Objects[p]
    if o then
        if o.Frame then o.Frame:Destroy() end
        if o.Line then o.Line:Destroy() end
    end
    Esp.Objects[p] = nil
end

local function refreshEsp()
    for p, o in pairs(Esp.Objects) do
        if o.Frame and o.Frame.Parent ~= nil then
            local col = espColor(p)
            local box = boxVisible()
            o.Frame.Visible = box
            o.Stroke.Color = col
            o.Stroke.Thickness = Esp.Style == "Outline" and 2 or 1.5
            o.Frame.BackgroundTransparency = Esp.Style == "Outline" and 0.7 or 1
            o.Frame.BackgroundColor3 = col
            o.Name.Visible = Esp.Names
            o.Name.TextColor3 = col
            o.Hp.Visible = Esp.Health
            o.Line.BackgroundColor3 = col
            o.Line.Visible = Esp.Tracers and Esp.Enabled
        else
            Esp.Objects[p] = nil
        end
    end
end

local function clearEsp()
    for p in pairs(Esp.Objects) do removeEsp(p) end
    Esp.Enabled = false
end

-- Player lifecycle
local function onPlayer(p)
    if p ~= player then createEsp(p) end
end
for _, p in ipairs(Players:GetPlayers()) do onPlayer(p) end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(removeEsp)

game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)

local function setTracerOrigin()
    if not camera then return end
    local vp = camera.ViewportSize
    -- Top-center = tracer start; keep it inside the viewport bounds.
    local origin = Vector2.new(math.clamp(vp.X / 2, 1, math.max(vp.X - 1, 1)), 1)
    local origin2 = Vector2.new(math.max(origin.X + 1, 2), origin.Y)
    Esp.Origin, Esp.Origin2 = origin, origin2
    for _, o in pairs(Esp.Objects) do
        if o.Line then
            setTracerLine(o.Line, origin, origin2)
        end
    end
end
setTracerOrigin()
if camera then
    camera:GetPropertyChangedSignal("ViewportSize"):Connect(setTracerOrigin)
    workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        camera = workspace.CurrentCamera
        setTracerOrigin()
    end)
end

-- Render loop ---------------------------------------------------------
local reportedEspErrors = {}
RunService.RenderStepped:Connect(function()
    -- Fail loudly instead of silently: if the camera is gone, rebuild the ref
    if not camera or not camera.Parent then
        camera = workspace.CurrentCamera
        if not camera then return end
    end

    if not Esp.Enabled then
        for _, o in pairs(Esp.Objects) do
            if o.Frame and o.Frame.Visible then o.Frame.Visible = false end
            if o.Line and o.Line.Visible then o.Line.Visible = false end
        end
        return
    end

    local origin = Esp.Origin or Vector2.new(1, 1)

    for p, o in pairs(Esp.Objects) do
        -- One bad character must never abort the whole ESP pass
        local ok, err = pcall(function()
        local char = p.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")

        local onScreen =
            char ~= nil and hrp ~= nil and hum ~= nil and hum.Health > 0 and
            p ~= player and
            not (char == player.Character)

        if onScreen and not Esp.UnlimitedDistance then
            local dist = (hrp.Position - camera.CFrame.Position).Magnitude
            if dist > Esp.MaxDist then onScreen = false end
        end

        local topLeft, botRight, boundsCFrame, boundsSize
        if onScreen then
            boundsCFrame, boundsSize = char:GetBoundingBox()
            local halfX = boundsSize.X * 0.5
            local halfY = boundsSize.Y * 0.5
            local halfZ = boundsSize.Z * 0.5

            local corners = {
                boundsCFrame * CFrame.new(-halfX,  halfY, -halfZ),
                boundsCFrame * CFrame.new( halfX,  halfY, -halfZ),
                boundsCFrame * CFrame.new(-halfX,  halfY,  halfZ),
                boundsCFrame * CFrame.new( halfX,  halfY,  halfZ),
                boundsCFrame * CFrame.new(-halfX, -halfY, -halfZ),
                boundsCFrame * CFrame.new( halfX, -halfY, -halfZ),
                boundsCFrame * CFrame.new(-halfX, -halfY,  halfZ),
                boundsCFrame * CFrame.new( halfX, -halfY,  halfZ),
            }

            local minX, minY = math.huge, math.huge
            local maxX, maxY = -math.huge, -math.huge
            local anyOnScreen = false

            for _, corner in ipairs(corners) do
                local sp, onScr = camera:WorldToViewportPoint(corner.Position)
                if onScr and sp.Z > 0 then anyOnScreen = true end
                if sp.X < minX then minX = sp.X end
                if sp.X > maxX then maxX = sp.X end
                if sp.Y < minY then minY = sp.Y end
                if sp.Y > maxY then maxY = sp.Y end
            end

            if anyOnScreen then
                topLeft = Vector2.new(minX, minY)
                botRight = Vector2.new(maxX, maxY)
            else
                onScreen = false
            end
        end

        if p == player or char == player.Character then
            o.Frame.Visible = false
            o.Line.Visible = false
        elseif onScreen and topLeft and botRight then
            local px = topLeft.X
            local py = topLeft.Y
            local sx = botRight.X - topLeft.X
            local sy = botRight.Y - topLeft.Y

            o.Frame.Visible = boxVisible()
            o.Frame.Position = UDim2.fromOffset(px, py)
            o.Frame.Size = UDim2.fromOffset(sx, sy)
            o.Frame.ZIndex = 2

            o.Name.Visible = Esp.Names
            o.Name.ZIndex = 3
            o.Hp.Visible = Esp.Health
            o.Hp.ZIndex = 3

            if Esp.Health and hum then
                local ratio = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                o.Fill.Size = UDim2.new(1, 0, ratio, 0)
                local shade = math.floor(255 * ratio)
                o.Fill.BackgroundColor3 = Color3.fromRGB(shade, shade, shade)
            end

            -- Tracer: bottom-center of the screen -> character's feet
            if Esp.Tracers then
                local feetWorld = (boundsCFrame * CFrame.new(0, -(boundsSize.Y * 0.5), 0)).Position
                local feet = camera:WorldToViewportPoint(feetWorld)
                if feet.Z > 0 then
                    local viewport = camera.ViewportSize
                    local endpoint = Vector2.new(
                        math.clamp(feet.X, 0, viewport.X),
                        math.clamp(feet.Y, 0, viewport.Y)
                    )
                    setTracerLine(o.Line, origin, endpoint)
                    o.Line.BackgroundColor3 = espColor(p)
                    o.Line.Visible = true
                    o.Line.Parent = espGui
                else
                    o.Line.Visible = false
                end
            else
                o.Line.Visible = false
            end
        else
            o.Frame.Visible = false
            o.Line.Visible = false
        end
        end)
        if not ok then
            if not reportedEspErrors[p] then
                warn("ESP update failed for " .. p.Name .. ": " .. tostring(err))
                reportedEspErrors[p] = true
            end
            -- Character was mid-despawn/reparent; skip it this frame
            if o.Frame then o.Frame.Visible = false end
            if o.Line then o.Line.Visible = false end
        else
            reportedEspErrors[p] = nil
        end
    end
end)

-- Clean up the ESP overlay if the menu GUI is destroyed externally
gui.Destroying:Connect(function()
    clearEsp()
    if espGui then espGui:Destroy() end
end)

-- ESP tab -------------------------------------------------------------
section(esp, "Style")
selectGrid(esp, {"Box", "Outline", "Corner", "None"}, "Box", function(v)
    Esp.Style = v
    refreshEsp()
    print("Style:", v)
end, 4)
section(esp, "Options")
toggle(esp, "Enable ESP", false, function(v)
    Esp.Enabled = v
    refreshEsp()
    notify("ESP", v and "Player visuals enabled." or "Player visuals disabled.")
    print("ESP:", v)
end)
toggle(esp, "Show Names", false, function(v)
    Esp.Names = v
    refreshEsp()
end)
toggle(esp, "Tracers", false, function(v)
    Esp.Tracers = v
    refreshEsp()
end)
toggle(esp, "Health Bar", false, function(v)
    Esp.Health = v
    refreshEsp()
end)
slider(esp, "Max Distance", 100, 2000, 1000, function(v)
    Esp.MaxDist = v
end)
toggle(esp, "Unlimited Distance", false, function(v)
    Esp.UnlimitedDistance = v
end)

-- Main
local fpsCard = Instance.new("Frame")
fpsCard.Name = "FPSCounter"
fpsCard.AnchorPoint = Vector2.new(1, 1)
fpsCard.Size = UDim2.fromOffset(112, 30)
fpsCard.Position = UDim2.new(1, -16, 1, -16)
fpsCard.BackgroundColor3 = T.Bg
fpsCard.BackgroundTransparency = 0.12
fpsCard.BorderSizePixel = 0
fpsCard.Visible = false
fpsCard.ZIndex = 6
fpsCard.Parent = espGui
liveCorner(fpsCard, 9)
stroke(fpsCard, T.Line, 1, 0.15)
local fpsText = label(fpsCard, "FPS  --", 12, Enum.Font.GothamBold, T.Text, Enum.TextXAlignment.Center)
fpsText.Size = UDim2.new(1, 0, 1, 0)
fpsText.ZIndex = 7

local clockCard = Instance.new("Frame")
clockCard.Name = "Clock"
clockCard.AnchorPoint = Vector2.new(1, 0)
clockCard.Size = UDim2.fromOffset(112, 30)
clockCard.Position = UDim2.new(1, -16, 0, 16)
clockCard.BackgroundColor3 = T.Bg
clockCard.BackgroundTransparency = 0.12
clockCard.BorderSizePixel = 0
clockCard.Visible = false
clockCard.ZIndex = 6
clockCard.Parent = espGui
liveCorner(clockCard, 9)
stroke(clockCard, T.Line, 1, 0.15)
local clockText = label(clockCard, "", 12, Enum.Font.GothamBold, T.Text, Enum.TextXAlignment.Center)
clockText.Size = UDim2.new(1, 0, 1, 0)
clockText.ZIndex = 7

local crosshair = Instance.new("Frame")
crosshair.Name = "CenterCrosshair"
crosshair.AnchorPoint = Vector2.new(0.5, 0.5)
crosshair.Size = UDim2.fromOffset(16, 16)
crosshair.BackgroundTransparency = 1
crosshair.Visible = false
crosshair.ZIndex = 6
crosshair.Parent = espGui
local crosshairH = Instance.new("Frame")
crosshairH.AnchorPoint = Vector2.new(0.5, 0.5)
crosshairH.Size = UDim2.fromOffset(14, 2)
crosshairH.Position = UDim2.new(0.5, 0, 0.5, 0)
crosshairH.BackgroundColor3 = T.Text
crosshairH.BorderSizePixel = 0
crosshairH.ZIndex = 7
crosshairH.Parent = crosshair
corner(crosshairH, 1)
local crosshairV = Instance.new("Frame")
crosshairV.AnchorPoint = Vector2.new(0.5, 0.5)
crosshairV.Size = UDim2.fromOffset(2, 14)
crosshairV.Position = UDim2.new(0.5, 0, 0.5, 0)
crosshairV.BackgroundColor3 = T.Text
crosshairV.BorderSizePixel = 0
crosshairV.ZIndex = 7
crosshairV.Parent = crosshair
corner(crosshairV, 1)

local targetCard = Instance.new("Frame")
targetCard.Name = "TargetIndicator"
targetCard.AnchorPoint = Vector2.new(0.5, 0)
targetCard.Size = UDim2.fromOffset(220, 30)
targetCard.Position = UDim2.new(0.5, 0, 0, 16)
targetCard.BackgroundColor3 = T.Bg
targetCard.BackgroundTransparency = 0.12
targetCard.BorderSizePixel = 0
targetCard.Visible = false
targetCard.ZIndex = 6
targetCard.Parent = espGui
liveCorner(targetCard, 9)
stroke(targetCard, T.Line, 1, 0.15)
local targetText = label(targetCard, "", 12, Enum.Font.GothamBold, T.Text, Enum.TextXAlignment.Center)
targetText.Size = UDim2.new(1, -12, 1, 0)
targetText.Position = UDim2.new(0, 6, 0, 0)
targetText.ZIndex = 7

local coordinateCard = Instance.new("Frame")
coordinateCard.Name = "Coordinates"
coordinateCard.AnchorPoint = Vector2.new(0, 1)
coordinateCard.Size = UDim2.fromOffset(220, 30)
coordinateCard.Position = UDim2.new(0, 16, 1, -16)
coordinateCard.BackgroundColor3 = T.Bg
coordinateCard.BackgroundTransparency = 0.12
coordinateCard.BorderSizePixel = 0
coordinateCard.Visible = false
coordinateCard.ZIndex = 6
coordinateCard.Parent = espGui
liveCorner(coordinateCard, 9)
stroke(coordinateCard, T.Line, 1, 0.15)
local coordinateText = label(coordinateCard, "X --  Y --  Z --", 11, Enum.Font.GothamBold, T.Text, Enum.TextXAlignment.Center)
coordinateText.Size = UDim2.new(1, 0, 1, 0)
coordinateText.ZIndex = 7

local freecamEnabled = false
local freecamSpeed = 48
local freecamKeys = {}
local freecamSnapshot
local freecamPosition
local freecamYaw, freecamPitch = 0, 0
local freecamActionKeys = {
    Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
    Enum.KeyCode.Space, Enum.KeyCode.LeftControl, Enum.KeyCode.LeftShift,
}

local function setFreecam(enabled)
    if freecamEnabled == enabled then return end
    local activeCamera = workspace.CurrentCamera
    if enabled then
        if not activeCamera then
            notify("Freecam", "Camera is unavailable.")
            return
        end
        freecamSnapshot = {
            Camera = activeCamera,
            CameraType = activeCamera.CameraType,
            CameraSubject = activeCamera.CameraSubject,
            CFrame = activeCamera.CFrame,
            Focus = activeCamera.Focus,
            FieldOfView = activeCamera.FieldOfView,
            MouseBehavior = UserInputService.MouseBehavior,
            MouseIconEnabled = UserInputService.MouseIconEnabled,
        }
        freecamPosition = activeCamera.CFrame.Position
        local look = activeCamera.CFrame.LookVector
        freecamYaw = math.atan2(-look.X, -look.Z)
        freecamPitch = math.asin(math.clamp(look.Y, -1, 1))
        table.clear(freecamKeys)
        freecamEnabled = true
        activeCamera.CameraType = Enum.CameraType.Scriptable
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        UserInputService.MouseIconEnabled = false
        ContextActionService:BindActionAtPriority(
            "MT_FreecamInput",
            function()
                return Enum.ContextActionResult.Sink
            end,
            false,
            Enum.ContextActionPriority.High.Value,
            table.unpack(freecamActionKeys)
        )
        RunService:BindToRenderStep("MT_Freecam", Enum.RenderPriority.Camera.Value + 5, function(dt)
            local cam = workspace.CurrentCamera
            if not freecamEnabled or not cam then return end
            local mouseDelta = UserInputService:GetMouseDelta()
            freecamYaw -= mouseDelta.X * 0.0025
            freecamPitch = math.clamp(freecamPitch - mouseDelta.Y * 0.0025, -1.52, 1.52)
            local rotation = CFrame.fromOrientation(freecamPitch, freecamYaw, 0)
            local movement = Vector3.new(
                (freecamKeys[Enum.KeyCode.D] and 1 or 0) - (freecamKeys[Enum.KeyCode.A] and 1 or 0),
                (freecamKeys[Enum.KeyCode.Space] and 1 or 0) - (freecamKeys[Enum.KeyCode.LeftControl] and 1 or 0),
                (freecamKeys[Enum.KeyCode.S] and 1 or 0) - (freecamKeys[Enum.KeyCode.W] and 1 or 0)
            )
            if movement.Magnitude > 0 then
                local speedMultiplier = freecamKeys[Enum.KeyCode.LeftShift] and 2 or 1
                freecamPosition += rotation:VectorToWorldSpace(movement.Unit) * freecamSpeed * speedMultiplier * dt
            end
            cam.CameraType = Enum.CameraType.Scriptable
            cam.CFrame = CFrame.new(freecamPosition) * rotation
            cam.Focus = cam.CFrame * CFrame.new(0, 0, -128)
        end)
        notify("Freecam", "WASD to move, mouse to look, Space/Ctrl to rise or descend.")
    else
        freecamEnabled = false
        table.clear(freecamKeys)
        RunService:UnbindFromRenderStep("MT_Freecam")
        ContextActionService:UnbindAction("MT_FreecamInput")
        if freecamSnapshot then
            local cam = workspace.CurrentCamera or freecamSnapshot.Camera
            if cam then
                local subject = freecamSnapshot.CameraSubject
                if not subject or not subject.Parent then
                    local character = player.Character
                    subject = character and character:FindFirstChildOfClass("Humanoid")
                end
                cam.CameraSubject = subject
                cam.CameraType = freecamSnapshot.CameraType
                cam.FieldOfView = freecamSnapshot.FieldOfView
                if cam == freecamSnapshot.Camera then
                    cam.CFrame = freecamSnapshot.CFrame
                    cam.Focus = freecamSnapshot.Focus
                end
            end
            UserInputService.MouseBehavior = freecamSnapshot.MouseBehavior
            UserInputService.MouseIconEnabled = freecamSnapshot.MouseIconEnabled
        end
        freecamSnapshot = nil
        notify("Freecam", "Camera restored to your character.")
    end
end

local freecamInputBegan = UserInputService.InputBegan:Connect(function(input, processed)
    if not freecamEnabled or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    if not UserInputService:GetFocusedTextBox() then
        freecamKeys[input.KeyCode] = true
    end
end)
local freecamInputEnded = UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        freecamKeys[input.KeyCode] = nil
    end
end)

local setGodmode
local setOptimizeGame = (function()
    local enabled = false
    local connections = {}
    local originalsByInstance = setmetatable({}, {__mode = "k"})
    local originalGlobalShadows
    local originalTerrainDecoration
    local scanGeneration = 0
    local lighting = game:GetService("Lighting")

    local function assign(instance, property, value)
        local ok, err = pcall(function()
            instance[property] = value
        end)
        if not ok then
            warn(("Optimize Game could not set %s.%s: %s"):format(
                instance.ClassName,
                property,
                tostring(err)
            ))
        end
        return ok
    end

    local function optimizeInstance(instance)
        local properties = {}
        if instance:IsA("BasePart") then
            properties.CastShadow = false
        end
        if instance:IsA("MeshPart") then
            properties.RenderFidelity = Enum.RenderFidelity.Performance
            properties.TextureID = ""
        elseif instance:IsA("SpecialMesh") then
            properties.TextureId = ""
        elseif instance:IsA("Decal") or instance:IsA("Texture") then
            properties.Texture = ""
        elseif instance:IsA("SurfaceAppearance") then
            properties.ColorMap = ""
            properties.MetalnessMap = ""
            properties.NormalMap = ""
            properties.RoughnessMap = ""
        elseif instance:IsA("Sky") then
            properties.SkyboxBk = ""
            properties.SkyboxDn = ""
            properties.SkyboxFt = ""
            properties.SkyboxLf = ""
            properties.SkyboxRt = ""
            properties.SkyboxUp = ""
            properties.SunTextureId = ""
            properties.MoonTextureId = ""
        end

        if next(properties) == nil then return end
        local originals = originalsByInstance[instance]
        if not originals then
            originals = {}
            originalsByInstance[instance] = originals
        end
        for property, value in pairs(properties) do
            local hadOriginal = originals[property] ~= nil
            local original = originals[property]
            local canApply = true
            if not hadOriginal then
                local readOk
                readOk, original = pcall(function()
                    return instance[property]
                end)
                if not readOk then
                    canApply = false
                    warn(("Optimize Game could not read %s.%s"):format(instance.ClassName, property))
                end
            end
            if canApply and assign(instance, property, value) and not hadOriginal then
                originals[property] = original
            end
        end
    end

    return function(on)
        if enabled == on then return end
        enabled = on
        scanGeneration += 1
        local currentGeneration = scanGeneration

        local terrain = workspace.Terrain
        if on then
            originalGlobalShadows = lighting.GlobalShadows
            originalTerrainDecoration = terrain.Decoration
            assign(lighting, "GlobalShadows", false)
            assign(terrain, "Decoration", false)

            local roots = {workspace, lighting}
            for _, root in ipairs(roots) do
                table.insert(connections, root.DescendantAdded:Connect(function(instance)
                    if enabled then
                        optimizeInstance(instance)
                    end
                end))
            end
            task.spawn(function()
                local processed = 0
                for _, root in ipairs(roots) do
                    for _, instance in ipairs(root:GetDescendants()) do
                        if not enabled or scanGeneration ~= currentGeneration then return end
                        optimizeInstance(instance)
                        processed += 1
                        if processed % 100 == 0 then
                            task.wait()
                        end
                    end
                end
            end)
            notify("Optimize Game", "Shadows and textures reduced.")
        else
            for _, connection in ipairs(connections) do
                connection:Disconnect()
            end
            table.clear(connections)
            for instance, originals in pairs(originalsByInstance) do
                for property, value in pairs(originals) do
                    assign(instance, property, value)
                end
                originalsByInstance[instance] = nil
            end
            assign(lighting, "GlobalShadows", originalGlobalShadows)
            assign(terrain, "Decoration", originalTerrainDecoration)
            originalGlobalShadows = nil
            originalTerrainDecoration = nil
            notify("Optimize Game", "Original shadows and textures restored.")
        end
    end
end)()

toggle(main, "Notifications", true, function(v)
    notificationsEnabled = v
    if v then notify("Notifications", "Notifications enabled.") end
end)
toggle(main, "Optimize Game", false, setOptimizeGame)
local setFreecamToggle = toggle(main, "Freecam", false, setFreecam)
slider(main, "Freecam Speed", 8, 160, freecamSpeed, function(v)
    freecamSpeed = v
end)
local setGodmodeToggle
setGodmodeToggle = toggle(main, "Godmode", false, function(v)
    if setGodmode then setGodmode(v) end
end)
toggle(main, "FPS Counter", false, function(v)
    fpsCard.Visible = v
    notify("FPS counter", v and "Counter enabled." or "Counter disabled.")
end)
toggle(main, "Clock", false, function(v)
    clockCard.Visible = v
    notify("Clock", v and "Clock enabled." or "Clock disabled.")
end)
toggle(main, "Center Crosshair", false, function(v)
    crosshair.Visible = v
    notify("Crosshair", v and "Crosshair enabled." or "Crosshair disabled.")
end)
toggle(main, "Target Indicator", false, function(v)
    targetCard.Visible = v
    notify("Target indicator", v and "Target readout enabled." or "Target readout disabled.")
end)
toggle(main, "Coordinates", false, function(v)
    coordinateCard.Visible = v
    notify("Coordinates", v and "Position readout enabled." or "Position readout disabled.")
end)
local overlayElapsed, overlayFrames = 0, 0
local overlayUiElapsed = 0
local lastClockSecond
local lastTargetName
local lastViewport
local overlayConnection = RunService.RenderStepped:Connect(function(dt)
    if not espGui.Parent then return end
    if fpsCard.Visible then
        overlayElapsed += dt
        overlayFrames += 1
        if overlayElapsed >= 0.5 then
            fpsText.Text = string.format("FPS  %d", math.floor(overlayFrames / overlayElapsed + 0.5))
            overlayElapsed, overlayFrames = 0, 0
        end
    end
    if clockCard.Visible or targetCard.Visible or coordinateCard.Visible or crosshair.Visible then
        overlayUiElapsed += dt
        if overlayUiElapsed < 0.15 then return end
        overlayUiElapsed %= 0.15
        if clockCard.Visible then
            local now = os.date("%H:%M:%S")
            if now ~= lastClockSecond then
                clockText.Text = now
                lastClockSecond = now
            end
        end
        if targetCard.Visible then
            local target = Aim.Enabled and Aim.Locked
            local targetName = target and target.Name or nil
            if targetName ~= lastTargetName then
                targetText.Text = targetName and ("TARGET  " .. targetName) or "TARGET  --"
                lastTargetName = targetName
            end
        end
        if coordinateCard.Visible then
            local character = player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if root then
                local position = root.Position
                coordinateText.Text = string.format("X %.0f   Y %.0f   Z %.0f", position.X, position.Y, position.Z)
            else
                coordinateText.Text = "X --   Y --   Z --"
            end
        end
        if crosshair.Visible and camera then
            local viewport = camera.ViewportSize
            if viewport ~= lastViewport then
                crosshair.Position = UDim2.fromOffset(viewport.X / 2, viewport.Y / 2)
                lastViewport = viewport
            end
        end
    end
end)

-- Settings
section(settings, "Interface")
slider(settings, "UI Scale (%)", 60, 130, 100, function(v) uiScale.Scale = v / 100 end)
toggle(settings, "Animations", true, function(v)
    anim.Enabled = v
    if not v then
        stopActiveTweens()
        shootingStar.Visible = false
    end
end)
toggle(settings, "Menu Blur / Vignette", false, function(v) vignette.Visible = v end)
section(settings, "Movement")
local movementSpeed = 16
local movementSpeedConnection
local noclipConnection
local originalCollisions = {}
local noclipActive = false

local function restoreCharacterCollisions()
    for part, canCollide in pairs(originalCollisions) do
        if part.Parent then
            part.CanCollide = canCollide
        end
        originalCollisions[part] = nil
    end
end

local function applyNoclip()
    local character = player.Character
    if not character then return end

    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            if originalCollisions[part] == nil then
                originalCollisions[part] = part.CanCollide
            end
            part.CanCollide = false
        end
    end
end

local function bindNoclipCharacter(character)
    if noclipConnection then
        noclipConnection:Disconnect()
        noclipConnection = nil
    end
    if not character then return end
    noclipConnection = character.DescendantAdded:Connect(function(part)
        if not noclipActive or not part:IsA("BasePart") then return end
        if originalCollisions[part] == nil then
            originalCollisions[part] = part.CanCollide
        end
        part.CanCollide = false
    end)
end

local function setNoclip(enabled)
    if noclipActive == enabled then return end
    noclipActive = enabled
    if enabled then
        applyNoclip()
        bindNoclipCharacter(player.Character)
    else
        if noclipConnection then
            noclipConnection:Disconnect()
            noclipConnection = nil
        end
        restoreCharacterCollisions()
    end
    notify("Noclip", enabled and "Noclip enabled." or "Noclip disabled.")
end

local function applyMovementSpeed(character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then humanoid.WalkSpeed = movementSpeed end
end
slider(settings, "Movement Speed", 16, 100, movementSpeed, function(v)
    movementSpeed = v
    local character = player.Character
    if character then applyMovementSpeed(character) end
end)
local setNoclipToggle = toggle(settings, "Noclip", false, setNoclip)
movementSpeedConnection = player.CharacterAdded:Connect(function(character)
    restoreCharacterCollisions()
    if noclipActive then
        applyNoclip()
        bindNoclipCharacter(character)
    end
    local humanoid = character:WaitForChild("Humanoid", 10)
    if humanoid then humanoid.WalkSpeed = movementSpeed end
end)

-- Godmode -------------------------------------------------------------
-- Keeps you alive by topping your health back up every frame, before the
-- engine can ever process a lethal hit. Reacting to Humanoid.Died is not
-- reliable (the engine may already be respawning you), so we clamp health
-- continuously instead. The humanoid is never replaced, so nothing else
-- has to be rebound.
local GOD_HEALTH = 100
local godmodeEnabled = false
local godmodeCharacterConnection
local godmodeRenderConnection
local godmodeCharacter

local function godmodeStep()
    if not godmodeEnabled then return end
    local character = player.Character
    if not character or character ~= godmodeCharacter then
        godmodeCharacter = character
    end
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid or not humanoid.Parent then return end
    if humanoid.Health <= 0 or humanoid.Health < humanoid.MaxHealth then
        humanoid.Health = humanoid.MaxHealth
    end
end

local function applyGodmode()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    if humanoid.MaxHealth < GOD_HEALTH then
        humanoid.MaxHealth = GOD_HEALTH
    end
    humanoid.Health = humanoid.MaxHealth
end

setGodmode = function(enabled)
    if godmodeEnabled == enabled then return end
    godmodeEnabled = enabled
    if enabled then
        applyGodmode()
        -- Re-apply the instant a new character loads in
        if godmodeCharacterConnection then godmodeCharacterConnection:Disconnect() end
        godmodeCharacterConnection = player.CharacterAdded:Connect(function()
            if not godmodeEnabled then return end
            task.wait()
            applyGodmode()
        end)
        -- Continuous guard: runs on the render loop so a lethal hit can
        -- never land, regardless of what damaged us or how much it did.
        if not godmodeRenderConnection then
            godmodeRenderConnection = RunService.RenderStepped:Connect(godmodeStep)
        end
        notify("Godmode", "You can no longer die.")
    else
        if godmodeCharacterConnection then
            godmodeCharacterConnection:Disconnect()
            godmodeCharacterConnection = nil
        end
        if godmodeRenderConnection then
            godmodeRenderConnection:Disconnect()
            godmodeRenderConnection = nil
        end
        notify("Godmode", "Godmode disabled.")
    end
end

-- Keybinds
local keybindsByAction = {
    Menu = Enum.KeyCode.RightShift,
    AimEnabled = Enum.KeyCode.F6,
    AimToggle = Enum.KeyCode.E,
    AimHold = Enum.UserInputType.MouseButton2,
    Noclip = Enum.KeyCode.N,
    Godmode = Enum.KeyCode.G,
    Freecam = Enum.KeyCode.F8,
}
local bindingRows = {}
local listeningForBind
local function displayBinding(binding)
    return tostring(binding):gsub("^Enum%.[^%.]+%.", "")
end
local function matchesBinding(input, binding)
    if binding == Enum.UserInputType.MouseButton1 or binding == Enum.UserInputType.MouseButton2 then
        return input.UserInputType == binding
    end
    return input.KeyCode == binding
end
local function bindRow(title, action)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, 0, 0, 48)
    row.BackgroundTransparency = 1
    row.Parent = keybinds.Page
    table.insert(keybinds.Items, {Frame = row, Name = title})
    local name = label(row, title, 13, Enum.Font.GothamMedium, T.Text)
    name.Size = UDim2.new(1, -132, 1, 0)
    local button = Instance.new("TextButton")
    button.Name = "Binding"
    button.AnchorPoint = Vector2.new(1, 0.5)
    button.Size = UDim2.fromOffset(112, 32)
    button.Position = UDim2.new(1, 0, 0.5, 0)
    button.BackgroundColor3 = T.Card
    button.TextColor3 = T.Text
    button.Font = Enum.Font.GothamBold
    button.TextSize = 12
    button.AutoButtonColor = false
    button.Text = displayBinding(keybindsByAction[action])
    button.Parent = row
    liveCorner(button, 10)
    stroke(button, T.Line, 1, 0.1)
    bindingRows[action] = button
    button.MouseButton1Click:Connect(function()
        listeningForBind = action
        button.Text = "PRESS A KEY"
        button.TextColor3 = T.Accent2
    end)
end
section(keybinds, "Rebind controls")
bindRow("Toggle menu", "Menu")
bindRow("Enable / disable aimbot", "AimEnabled")
bindRow("Toggle aim activation", "AimToggle")
bindRow("Hold aim activation", "AimHold")
bindRow("Toggle noclip", "Noclip")
bindRow("Toggle godmode", "Godmode")
bindRow("Toggle freecam", "Freecam")
local bindHint = label(keybinds.Page, "Aim activation keys follow the selected Hold or Toggle mode.", 11, Enum.Font.Gotham, T.Sub)
bindHint.Size = UDim2.new(1, 0, 0, 28)

-- Config
section(config, "Slots")
selectGrid(config, {"Slot 1", "Slot 2", "Slot 3", "Slot 4"}, "Slot 1", function(v) print("Config:", v) end, 4)

-- ===================================================================
-- Dynamic menu, built from the HTML config
-- ===================================================================
-- Every control in the fetched HTML becomes a real Roblox component here.
-- Handlers are looked up by the control label so the HTML-driven controls
-- behave exactly like the hand-written ones above (aimbot, ESP, noclip...).

-- Per-label behaviour for the config page. Each entry gets (value, context)
-- and applies the same state change as the matching hard-coded control.
local htmlHandlers = {
    ["Enable ESP"] = function(v)
        Esp.Enabled = v
        refreshEsp()
        notify("ESP", v and "Player visuals enabled." or "Player visuals disabled.")
    end,
    ["Show Names"] = function(v)
        Esp.Names = v
        refreshEsp()
    end,
    ["Tracers"] = function(v)
        Esp.Tracers = v
        refreshEsp()
    end,
    ["Health Bar"] = function(v)
        Esp.Health = v
        refreshEsp()
    end,
    ["Unlimited Distance"] = function(v)
        Esp.UnlimitedDistance = v
    end,
    ["Max Distance"] = function(v)
        Esp.MaxDist = v
    end,
    ["ESP Style"] = function(v)
        Esp.Style = v
        refreshEsp()
    end,
    ["Enable Aimbot"] = function(v)
        Aim.Enabled = v
        if not v then
            Aim.Locked, Aim.Holding, Aim.Toggled = nil, false, false
        end
        notify("Aimbot", v and "Aimbot enabled." or "Aimbot disabled.")
    end,
    ["Target"] = function(v) Aim.Target = v end,
    ["Activation mode"] = function(v) Aim.Mode = v end,
    ["Strength (1 = assist, 100 = snap)"] = function(v) Aim.Strength = v end,
    ["FOV"] = function(v) Aim.FOV = v end,
    ["Notifications"] = function(v)
        notificationsEnabled = v
        if v then notify("Notifications", "Notifications enabled.") end
    end,
    ["FPS Counter"] = function(v)
        fpsCard.Visible = v
        notify("FPS counter", v and "Counter enabled." or "Counter disabled.")
    end,
    ["Clock"] = function(v)
        clockCard.Visible = v
        notify("Clock", v and "Clock enabled." or "Clock disabled.")
    end,
    ["Center Crosshair"] = function(v)
        crosshair.Visible = v
        notify("Crosshair", v and "Crosshair enabled." or "Crosshair disabled.")
    end,
    ["Target Indicator"] = function(v)
        targetCard.Visible = v
        notify("Target indicator", v and "Target readout enabled." or "Target readout disabled.")
    end,
    ["Coordinates"] = function(v)
        coordinateCard.Visible = v
        notify("Coordinates", v and "Position readout enabled." or "Position readout disabled.")
    end,
    ["Optimize Game"] = function(v) setOptimizeGame(v) end,
    ["Freecam"] = function(v) setFreecamToggle(v) end,
    ["Freecam Speed"] = function(v) freecamSpeed = v end,
    ["Godmode"] = function(v) setGodmodeToggle(v) end,
    ["UI Scale (%)"] = function(v) uiScale.Scale = v / 100 end,
    ["Animations"] = function(v)
        anim.Enabled = v
        if not v then
            stopActiveTweens()
            shootingStar.Visible = false
        end
    end,
    ["Menu Blur / Vignette"] = function(v) vignette.Visible = v end,
    ["Movement Speed"] = function(v)
        movementSpeed = v
        local character = player.Character
        if character then applyMovementSpeed(character) end
    end,
    ["Noclip"] = function(v) setNoclip(v) end,
}

local function runHtmlHandler(label, value)
    local handler = htmlHandlers[label]
    if handler then
        local ok, err = pcall(handler, value)
        if not ok then
            warn("Vitality config: handler for '" .. tostring(label) .. "' failed: " .. tostring(err))
        end
    end
end

-- Builds one tab's worth of sections/controls onto a fresh tab.
local function buildTabFromConfig(tabDef)
    local tabName = tabDef.label or tabDef.id or "HTML"
    local icon = tabDef.icon or "#"
    local tab = createTab("HTML_" .. tostring(tabDef.id or tabName), icon, tabName)

    for _, sectionDef in ipairs(tabDef.sections or {}) do
        section(tab, sectionDef.title or "")
        for _, control in ipairs(sectionDef.controls or {}) do
            local ctype = control.type
            local clabel = tostring(control.label or "")
            if ctype == "toggle" then
                local setter = toggle(tab, clabel, control.value == true, function(v)
                    runHtmlHandler(clabel, v)
                end)
                -- Keep the visual in sync without re-firing the callback.
                if control.value == true and setter then setter(true) end
            elseif ctype == "slider" then
                slider(
                    tab,
                    clabel,
                    tonumber(control.min) or 0,
                    tonumber(control.max) or 100,
                    tonumber(control.value) or tonumber(control.min) or 0,
                    function(v) runHtmlHandler(clabel, v) end
                )
            elseif ctype == "choice" then
                local options = control.options or {}
                selectGrid(tab, options, control.value, function(v)
                    runHtmlHandler(clabel, v)
                end, math.min(#options, 4))
            elseif ctype == "key" then
                -- Rendered as an info row; live rebinding stays in Keybinds.
                local info = label(tab.Page, clabel .. "  ·  " .. tostring(control.value or ""), 13, Enum.Font.GothamMedium, T.Sub)
                info.Size = UDim2.new(1, 0, 0, 24)
                table.insert(tab.Items, {Frame = info, Name = clabel})
            end
        end
    end
    return tab
end

local function applyConfig(decoded)
    if type(decoded) ~= "table" or type(decoded.tabs) ~= "table" then return false end
    local built = 0
    for _, tabDef in ipairs(decoded.tabs) do
        local ok, err = pcall(buildTabFromConfig, tabDef)
        if ok then
            built += 1
        else
            warn("Vitality config: tab '" .. tostring(tabDef.label or tabDef.id) .. "' failed: " .. tostring(err))
        end
    end
    return built > 0
end

-- Load once at startup so the HTML-driven tab exists immediately.
local function loadHtmlConfig()
    local html = fetchHtml()
    local decoded = parseHtmlConfig(html)
    if decoded then
        htmlConfig = decoded
        return applyConfig(decoded)
    end
    return false
end

-- Bottom sidebar buttons ---------------------------------------------
local bottom = Instance.new("Frame")
bottom.AnchorPoint = Vector2.new(0, 1)
bottom.Size = UDim2.new(1, -8, 0, 52)
bottom.Position = UDim2.new(0, 4, 1, -6)
bottom.BackgroundTransparency = 1
bottom.Parent = sidebar

-- Bottom-left X closes the menu; right-click keeps the full teardown available.
local terminateBtn, terminateIcon, terminateText = sideButton(bottom, "✖", "Terminate")
terminateBtn.Name = "Terminate"
terminateBtn.Size = UDim2.new(1, 0, 0, 46)
terminateBtn.Position = UDim2.new(0, 0, 1, -46)
terminateBtn.SideLabel.Visible = false
terminateBtn.SideIcon.Size = UDim2.new(1, 0, 1, 0)
terminateBtn.SideIcon.Position = UDim2.new(0, 0, 0, 0)
terminateBtn.SideIcon.TextSize = 18
terminateBtn.BackgroundColor3 = T.Danger
terminateIcon.TextColor3 = T.Sub
terminateText.TextColor3 = T.Sub
terminateText.Font = Enum.Font.GothamBold

terminateBtn.MouseEnter:Connect(function()
    tween(terminateBtn, 0.2, {BackgroundTransparency = 0.88})
    tween(terminateIcon, 0.2, {TextColor3 = T.Text})
end)
terminateBtn.MouseLeave:Connect(function()
    tween(terminateBtn, 0.2, {BackgroundTransparency = 1})
    tween(terminateIcon, 0.2, {TextColor3 = T.Sub})
end)

-- Full teardown: kills every loop and both GUIs
local function terminate()
    if terminate._done then return end
    terminate._done = true
    if movementSpeedConnection then movementSpeedConnection:Disconnect() end
    if overlayConnection then overlayConnection:Disconnect() end
    freecamInputBegan:Disconnect()
    freecamInputEnded:Disconnect()
    if freecamEnabled then setFreecam(false) end
    setNoclip(false)
    setGodmode(false)
    setOptimizeGame(false)
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid then humanoid.WalkSpeed = 16 end
    clearEsp()
    pcall(function() RunService:UnbindFromRenderStep("MT_Aimbot") end)
    if aimHighlight then aimHighlight:Destroy() end
    Aim.Locked, Aim.Holding, Aim.Toggled = nil, false, false
    if espGui then espGui:Destroy() end
    if gui then gui:Destroy() end
end

local function fadeAndTerminate()
    if terminate._done then return end
    if not anim.Enabled then
        terminate()
        return
    end
    tween(uiScale, 0.28, {Scale = 0.9})
    tween(window, 0.28, {BackgroundTransparency = 1})
    task.delay(0.3, terminate)
end

-- Start ---------------------------------------------------------------
-- Default to the reference's Misc page while leaving every feature off.
Esp.Enabled = false
Aim.Enabled = false
-- Animations start ON: the accent ticker, galaxy drift and corner breathe
-- all run from load without the user having to flip a toggle.
anim.Enabled = true
vignette.Visible = true

-- Pull the HTML page and build its tabs. Done before the first tab is
-- selected so the config-driven pages are part of the finished menu.
local htmlOk = loadHtmlConfig()
if htmlOk then
    notify("Config loaded", "Menu built from HTML (" .. htmlConfigSource .. ").")
else
    notify("Config missing", "Could not load the HTML config; using built-in tabs.")
end

-- Expose a manual rebuild so the menu can be refreshed without reloading
-- the whole script: getgenv().VitalityReload()
pcall(function()
    if type(getgenv) == "function" then
        getgenv().VitalityReload = function()
            htmlConfig = nil
            local ok = loadHtmlConfig()
            notify("Config reload", ok and "Menu rebuilt from HTML." or "Reload failed; check the URL.")
            return ok
        end
    end
end)

tabs["Main"].Select()
notify("Menu ready", "Galaxy theme active. Open Keybinds to customize controls.")

-- Force the "all off" state onto anything built during load
refreshEsp()
for _, o in pairs(Esp.Objects) do
    o.Frame.Visible = false
    o.Name.Visible = false
    o.Hp.Visible = false
    o.Line.Visible = false
end

local menuOpen = true
local function setMenuOpen(open)
    menuOpen = open
    if open then
        window.Visible = true
        uiScale.Scale = 0.94
        tween(uiScale, 0.22, {Scale = 1})
        vignette.Visible = true
    else
        window.Visible = false
        vignette.Visible = false
    end
end

local function closeMenu()
    setMenuOpen(false)
end

terminateBtn.MouseButton1Click:Connect(closeMenu)
terminateBtn.MouseButton2Click:Connect(fadeAndTerminate)

UserInputService.InputBegan:Connect(function(i, processed)
    if listeningForBind then
        if i.KeyCode == Enum.KeyCode.Escape then
            local button = bindingRows[listeningForBind]
            button.Text = displayBinding(keybindsByAction[listeningForBind])
            button.TextColor3 = T.Text
            listeningForBind = nil
            return
        end
        local binding
        if i.UserInputType == Enum.UserInputType.Keyboard and i.KeyCode ~= Enum.KeyCode.Unknown then
            binding = i.KeyCode
        elseif i.UserInputType == Enum.UserInputType.MouseButton1
            or i.UserInputType == Enum.UserInputType.MouseButton2 then
            binding = i.UserInputType
        end
        if binding then
            local action = listeningForBind
            local inUse = false
            for otherAction, otherBinding in pairs(keybindsByAction) do
                if otherAction ~= action and otherBinding == binding then
                    inUse = true
                    break
                end
            end
            local button = bindingRows[action]
            if inUse then
                button.Text = "ALREADY USED"
                task.delay(1, function()
                    if button.Parent then
                        button.Text = displayBinding(keybindsByAction[action])
                    end
                end)
            else
                keybindsByAction[action] = binding
                button.Text = displayBinding(binding)
                notify("Keybind updated", action .. " is now " .. displayBinding(binding) .. ".")
            end
            button.TextColor3 = T.Text
            listeningForBind = nil
            return
        end
    end

    if not UserInputService:GetFocusedTextBox() then
        if matchesBinding(i, keybindsByAction.AimEnabled) then
            setAimEnabledToggle(not Aim.Enabled)
        elseif matchesBinding(i, keybindsByAction.AimHold) then
            Aim.Holding = true
        elseif keybindsByAction.AimHold == Enum.UserInputType.MouseButton2
            and i.UserInputType == Enum.UserInputType.Touch then
            Aim.Holding = true
        elseif matchesBinding(i, keybindsByAction.AimToggle) then
            Aim.Toggled = not Aim.Toggled
            if not Aim.Toggled then Aim.Locked = nil end
        elseif matchesBinding(i, keybindsByAction.Noclip) then
            setNoclipToggle(not noclipActive)
        elseif matchesBinding(i, keybindsByAction.Godmode) then
            setGodmodeToggle(not godmodeEnabled)
        elseif matchesBinding(i, keybindsByAction.Freecam) then
            setFreecamToggle(not freecamEnabled)
        end
    end

    if processed then return end
    if matchesBinding(i, keybindsByAction.Menu) then
        setMenuOpen(not menuOpen)
    elseif i.KeyCode == Enum.KeyCode.Escape and menuOpen then
        setMenuOpen(false)
    end
end)

UserInputService.InputEnded:Connect(function(i)
    if matchesBinding(i, keybindsByAction.AimHold)
        or (keybindsByAction.AimHold == Enum.UserInputType.MouseButton2
            and i.UserInputType == Enum.UserInputType.Touch) then
        Aim.Holding = false
    end
end)

-- Highlight the player the aimbot is currently locked onto, so the
-- FOV behaviour is visible and not just felt.
local aimHighlight = Instance.new("Highlight")
aimHighlight.Name = "MT_AimTarget"
aimHighlight.FillColor = T.Danger
aimHighlight.OutlineColor = T.Danger
aimHighlight.FillTransparency = 0.75
aimHighlight.OutlineTransparency = 0.15
aimHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
aimHighlight.Parent = espGui

local lastHighlighted = nil
local highlightEnabled = false
RunService.RenderStepped:Connect(function()
    local t = Aim.Locked
    local char = t and t.Character
    if char and char.Parent then
        if lastHighlighted ~= char then
            aimHighlight.Adornee = char
            lastHighlighted = char
        end
        if not highlightEnabled then
            aimHighlight.Enabled = true
            highlightEnabled = true
        end
    elseif highlightEnabled then
        aimHighlight.Enabled = false
        aimHighlight.Adornee = nil
        highlightEnabled = false
        lastHighlighted = nil
    end
end)

-- Open animation
uiScale.Scale = 0.98
tween(uiScale, 0.35, {Scale = 1})

-- Live accent ticker -------------------------------------------------
-- Batch decorative updates to 30 Hz instead of rewriting the whole UI each frame.
local animationAccumulator = 0
RunService.RenderStepped:Connect(function(dt)
    if not uiLive() or not menuOpen then return end
    if not anim.Enabled then return end
    animationAccumulator += dt
    if animationAccumulator < 1 / 30 then return end
    local animationDt = animationAccumulator
    animationAccumulator = 0
    updateGalaxy(animationDt)
    accentPhase = (accentPhase + animationDt * 0.18) % 1

    local c1, c2 = gradientColor()
    for st, info in pairs(accentStrokes) do
        if st.Parent == nil then
            accentStrokes[st] = nil
        else
            info.phase = (info.phase + animationDt * info.speed) % 1
            local k = (math.sin(info.phase * math.pi * 2) + 1) * 0.5
            local col = c1:Lerp(c2, k)
            local ok = pcall(function()
                if st:IsA("UIStroke") then
                    st.Color = col
                elseif st:IsA("UIGradient") then
                    st.Color = ColorSequence.new(col, c1:Lerp(c2, 1 - k))
                else
                    st.BackgroundColor3 = col
                end
            end)
            if not ok then accentStrokes[st] = nil end
        end
    end

    for dot in pairs(accentDots) do
        if dot.Parent == nil then
            accentDots[dot] = nil
        end
    end

    -- Corner "breathe": the rounded corners gently swell and settle, which
    -- reads as the whole interface being softly alive.
    for c, info in pairs(animatedCorners) do
        if c.Parent == nil then
            animatedCorners[c] = nil
        else
            info.Phase = (info.Phase + animationDt * 0.9) % (math.pi * 2)
            local swell = (math.sin(info.Phase) + 1) * 0.5
            c.CornerRadius = UDim.new(0, info.Base + swell * 3)
        end
    end
end)
