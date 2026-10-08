-- Paste this entire script into your Roblox executor.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MIN_SPEED = 16
local MAX_SPEED = 200
local speed = 30
local speedEnabled = false
local menuOpen = true
local currentMode = "CFrame" -- Options: "CFrame" or "WalkSpeed"

local oldGui = playerGui:FindFirstChild("SpeedControlDeck")
if oldGui then
    oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "SpeedControlDeck"
gui.ResetOnSpawn = false
gui.DisplayOrder = 20
gui.Parent = playerGui

local function make(className, properties, parent)
    local object = Instance.new(className)
    for property, value in pairs(properties) do
        object[property] = value
    end
    object.Parent = parent
    return object
end

local function addCorner(object, radius)
    make("UICorner", { CornerRadius = UDim.new(0, radius) }, object)
end

local colors = {
    background = Color3.fromRGB(8, 8, 9),
    surface = Color3.fromRGB(19, 19, 21),
    surfaceLight = Color3.fromRGB(34, 34, 37),
    border = Color3.fromRGB(68, 68, 72),
    white = Color3.fromRGB(248, 248, 250),
    muted = Color3.fromRGB(158, 158, 164),
    cyan = Color3.fromRGB(225, 225, 230),
    blue = Color3.fromRGB(190, 190, 198),
    green = Color3.fromRGB(238, 238, 242),
}

local window = make("Frame", {
    Name = "Window",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(440, 300),
    BackgroundColor3 = colors.background,
    BorderSizePixel = 0,
    ClipsDescendants = true,
}, gui)
addCorner(window, 18)
make("UIStroke", {
    Color = colors.border,
    Thickness = 1.5,
    Transparency = 0.12,
}, window)
make("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(24, 24, 28)),
        ColorSequenceKeypoint.new(0.52, colors.background),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(13, 13, 15)),
    }),
    Rotation = 32,
}, window)

local starfield = make("Frame", {
    Name = "Starfield",
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
}, window)

local stars = {}
local random = Random.new()
for index = 1, 42 do
    local x = random:NextNumber(0.025, 0.975)
    local y = random:NextNumber(0.025, 0.975)
    local dotSize = random:NextInteger(3, 6)
    local star = make("Frame", {
        Name = "Star" .. index,
        Position = UDim2.fromScale(x, y),
        Size = UDim2.fromOffset(dotSize, dotSize),
        BackgroundColor3 = colors.white,
        BackgroundTransparency = random:NextNumber(0.25, 0.75),
        BorderSizePixel = 0,
    }, starfield)
    addCorner(star, 10)
    table.insert(stars, {
        label = star,
        x = x,
        y = y,
        speed = random:NextNumber(0.018, 0.055),
        phase = random:NextNumber(0, math.pi * 2),
    })
end

make("Frame", {
    Position = UDim2.new(0, 24, 0, 68),
    Size = UDim2.new(1, -48, 0, 1),
    BackgroundColor3 = colors.white,
    BackgroundTransparency = 0.55,
    BorderSizePixel = 0,
}, window)

local dragHandle = make("TextButton", {
    Name = "DragHandle",
    Size = UDim2.new(1, 0, 0, 68),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Text = "",
    AutoButtonColor = false,
    Active = true,
    ZIndex = 2,
}, window)

make("TextLabel", {
    Position = UDim2.fromOffset(24, 17),
    Size = UDim2.new(1, -110, 0, 26),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBlack,
    Text = "Vitality - Scripts",
    TextColor3 = colors.white,
    TextSize = 18,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 3,
}, window)

make("TextLabel", {
    Position = UDim2.fromOffset(25, 44),
    Size = UDim2.new(1, -115, 0, 16),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = "HYBRID SPEED PANEL  •  PRESS M TO TOGGLE",
    TextColor3 = colors.muted,
    TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 3,
}, window)

local hotkey = make("TextLabel", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -24, 0, 23),
    Size = UDim2.fromOffset(58, 25),
    BackgroundColor3 = colors.surfaceLight,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold,
    Text = "M  /  UI",
    TextColor3 = colors.white,
    TextSize = 10,
    ZIndex = 3,
}, window)
addCorner(hotkey, 8)

local dragging = false
local dragStart = nil
local windowStart = nil
dragHandle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        windowStart = window.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not dragging or not dragStart or not windowStart then
        return
    end
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
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
        dragging = false
        dragStart = nil
        windowStart = nil
    end
end)

local speedPanel = make("Frame", {
    Position = UDim2.fromOffset(24, 87),
    Size = UDim2.new(1, -48, 0, 143),
    BackgroundColor3 = colors.surface,
    BackgroundTransparency = 0.08,
    BorderSizePixel = 0,
}, window)
addCorner(speedPanel, 14)
make("UIStroke", {
    Color = colors.border,
    Thickness = 1,
    Transparency = 0.2,
}, speedPanel)

make("TextLabel", {
    Position = UDim2.fromOffset(18, 15),
    Size = UDim2.new(1, -36, 0, 18),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold,
    Text = "SPEED VALUE",
    TextColor3 = colors.muted,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
}, speedPanel)

-- Mode Switch Button
local modeButton = make("TextButton", {
    AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -18, 0, 12),
    Size = UDim2.fromOffset(112, 24),
    BackgroundColor3 = colors.surfaceLight,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBold,
    Text = "MODE: CFRAME",
    TextColor3 = colors.cyan,
    TextSize = 10,
    AutoButtonColor = true,
}, speedPanel)
addCorner(modeButton, 6)
local modeStroke = make("UIStroke", {
    Color = colors.cyan,
    Thickness = 1,
}, modeButton)

local speedValue = make("TextLabel", {
    Position = UDim2.fromOffset(17, 37),
    Size = UDim2.fromOffset(180, 52),
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamBlack,
    Text = tostring(speed),
    TextColor3 = colors.white,
    TextSize = 42,
    TextXAlignment = Enum.TextXAlignment.Left,
}, speedPanel)

local rangeLabel = make("TextLabel", {
    Position = UDim2.fromOffset(20, 85),
    Size = UDim2.fromOffset(120, 16),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = string.format("RANGE  %d–%d", MIN_SPEED, MAX_SPEED),
    TextColor3 = colors.muted,
    TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
}, speedPanel)

local toggleButton = make("TextButton", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -18, 0.5, 1),
    Size = UDim2.fromOffset(112, 42),
    BackgroundColor3 = colors.surfaceLight,
    BorderSizePixel = 0,
    Font = Enum.Font.GothamBlack,
    Text = "OFF",
    TextColor3 = colors.white,
    TextSize = 14,
    AutoButtonColor = true,
}, speedPanel)
addCorner(toggleButton, 11)
local toggleStroke = make("UIStroke", {
    Color = colors.border,
    Thickness = 1.2,
}, toggleButton)

local sliderTrack = make("Frame", {
    Position = UDim2.new(0, 20, 1, -22),
    Size = UDim2.new(1, -40, 0, 6),
    BackgroundColor3 = colors.border,
    BorderSizePixel = 0,
}, speedPanel)
addCorner(sliderTrack, 4)

local sliderFill = make("Frame", {
    Size = UDim2.new(0, 0, 1, 0),
    BackgroundColor3 = colors.cyan,
    BorderSizePixel = 0,
}, sliderTrack)
addCorner(sliderFill, 4)
make("UIGradient", {
    Color = ColorSequence.new(colors.blue, colors.cyan),
}, sliderFill)

local sliderKnob = make("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0, 0, 0.5, 0),
    Size = UDim2.fromOffset(18, 18),
    BackgroundColor3 = colors.white,
    BorderSizePixel = 0,
}, sliderTrack)
addCorner(sliderKnob, 9)
make("UIStroke", {
    Color = colors.cyan,
    Thickness = 2,
}, sliderKnob)

local sliderInput = make("TextButton", {
    Position = UDim2.new(0, -8, 0, -13),
    Size = UDim2.new(1, 16, 0, 32),
    BackgroundTransparency = 1,
    Text = "",
    AutoButtonColor = false,
}, sliderTrack)

local status = make("TextLabel", {
    Position = UDim2.new(0, 25, 1, -43),
    Size = UDim2.new(1, -50, 0, 20),
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = "HYBRID EXECUTOR  •  READY",
    TextColor3 = colors.green,
    TextSize = 9,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
}, window)

local function setSpeedValue(value)
    speed = math.clamp(math.floor(value + 0.5), MIN_SPEED, MAX_SPEED)
    local alpha = (speed - MIN_SPEED) / math.max(1, MAX_SPEED - MIN_SPEED)
    speedValue.Text = tostring(speed)
    sliderFill.Size = UDim2.fromScale(alpha, 1)
    sliderKnob.Position = UDim2.new(alpha, 0, 0.5, 0)
end

setSpeedValue(speed)

local function updateSpeedFromPointer(xPosition)
    local width = sliderTrack.AbsoluteSize.X
    if width <= 0 then
        return
    end
    local alpha = math.clamp((xPosition - sliderTrack.AbsolutePosition.X) / width, 0, 1)
    setSpeedValue(MIN_SPEED + (MAX_SPEED - MIN_SPEED) * alpha)
end

local draggingSlider = false
sliderInput.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        draggingSlider = true
        updateSpeedFromPointer(input.Position.X)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if draggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        updateSpeedFromPointer(input.Position.X)
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        draggingSlider = false
    end
end)

local function updateToggle()
    toggleButton.Text = speedEnabled and "ON" or "OFF"
    toggleButton.BackgroundColor3 = speedEnabled and colors.white or colors.surfaceLight
    toggleButton.TextColor3 = speedEnabled and colors.background or colors.white
    toggleStroke.Color = speedEnabled and colors.green or colors.border
    status.Text = speedEnabled and ("ACTIVE [" .. string.upper(currentMode) .. "]") or "HYBRID EXECUTOR  •  READY"
    status.TextColor3 = speedEnabled and colors.white or colors.green
end

toggleButton.Activated:Connect(function()
    speedEnabled = not speedEnabled
    updateToggle()
end)

-- Switch between CFrame and WalkSpeed modes
modeButton.Activated:Connect(function()
    if currentMode == "CFrame" then
        currentMode = "WalkSpeed"
        modeButton.Text = "MODE: WALKSPEED"
        modeButton.TextColor3 = colors.green
        modeStroke.Color = colors.green
    else
        currentMode = "CFrame"
        modeButton.Text = "MODE: CFRAME"
        modeButton.TextColor3 = colors.cyan
        modeStroke.Color = colors.cyan
    end
    if speedEnabled then
        status.Text = "ACTIVE [" .. string.upper(currentMode) .. "]"
    end
end)

-- Execution Loop handling both modes
RunService.Heartbeat:Connect(function(dt)
    if speedEnabled then
        local character = player.Character
        if character then
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            if humanoid and rootPart then
                if currentMode == "CFrame" then
                    if humanoid.MoveDirection.Magnitude > 0 then
                        rootPart.CFrame = rootPart.CFrame + (humanoid.MoveDirection * speed * dt)
                    end
                elseif currentMode == "WalkSpeed" then
                    if humanoid.WalkSpeed ~= speed then
                        humanoid.WalkSpeed = speed
                    end
                end
            end
        end
    end
end)

UserInputService.InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.M then
        menuOpen = not menuOpen
        if menuOpen then
            window.Visible = true
            window.Size = UDim2.fromOffset(420, 286)
            TweenService:Create(window, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Size = UDim2.fromOffset(440, 300),
            }):Play()
        else
            window.Visible = false
        end
    end
end)

-- Starfield animation loop
local elapsed = 0
RunService.RenderStepped:Connect(function(deltaTime)
    if not menuOpen then
        return
    end

    elapsed += deltaTime
    for _, star in ipairs(stars) do
        star.y += star.speed * deltaTime
