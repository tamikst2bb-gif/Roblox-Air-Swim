local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local guiName = "AirSwimPanel"
local oldGui = playerGui:FindFirstChild(guiName)
if oldGui then oldGui:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = guiName
gui.ResetOnSpawn = false
gui.DisplayOrder = 20

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -14, 0, 14)
panel.Size = UDim2.fromOffset(240, 110)
panel.BackgroundColor3 = Color3.fromRGB(22, 26, 34)
panel.BorderSizePixel = 0
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 9)

local function label(text, size, position)
    local item = Instance.new("TextLabel")
    item.Text = text
    item.Size = size
    item.Position = position
    item.BackgroundTransparency = 1
    item.TextColor3 = Color3.fromRGB(228, 235, 245)
    item.TextSize = 13
    item.Font = Enum.Font.GothamMedium
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.Parent = panel
    return item
end

local title = label("AIR SWIM", UDim2.fromOffset(214, 23), UDim2.fromOffset(12, 6))
title.Font = Enum.Font.GothamBold
title.TextSize = 14

local input = Instance.new("TextBox")
input.Position = UDim2.fromOffset(12, 33)
input.Size = UDim2.fromOffset(165, 30)
input.BackgroundColor3 = Color3.fromRGB(38, 44, 55)
input.TextColor3 = Color3.fromRGB(240, 245, 252)
input.PlaceholderColor3 = Color3.fromRGB(162, 175, 193)
input.PlaceholderText = "swim 25 / unswim"
input.ClearTextOnFocus = false
input.Text = ""
input.Font = Enum.Font.Code
input.TextSize = 14
input.Parent = panel
Instance.new("UICorner", input).CornerRadius = UDim.new(0, 6)

local runButton = Instance.new("TextButton")
runButton.Position = UDim2.fromOffset(184, 33)
runButton.Size = UDim2.fromOffset(44, 30)
runButton.BackgroundColor3 = Color3.fromRGB(54, 104, 172)
runButton.TextColor3 = Color3.fromRGB(255, 255, 255)
runButton.Font = Enum.Font.GothamBold
runButton.TextSize = 12
runButton.Text = "RUN"
runButton.Parent = panel
Instance.new("UICorner", runButton).CornerRadius = UDim.new(0, 6)

local status = label("Готово", UDim2.fromOffset(216, 17), UDim2.fromOffset(12, 67))
local hint = label("WASD  ·  Space ↑  ·  Ctrl ↓", UDim2.fromOffset(216, 17), UDim2.fromOffset(12, 86))
hint.TextColor3 = Color3.fromRGB(162, 175, 193)
hint.TextSize = 11

local defaultSpeed = 25
local minSpeed, maxSpeed = 1, 100
local state = Enum.HumanoidStateType
local blockedStates = {
    state.Running, state.RunningNoPhysics, state.Freefall, state.Landed,
    state.Jumping, state.GettingUp, state.Climbing, state.FallingDown,
}
local active

local function setStatus(message, failed)
    status.Text = message
    status.TextColor3 = failed and Color3.fromRGB(255, 178, 112) or Color3.fromRGB(143, 225, 195)
end

local function stop(message)
    local swim = active
    if swim then
        active = nil
        swim.step:Disconnect()
        swim.died:Disconnect()
        swim.mover:Destroy()
        swim.attachment:Destroy()

        local humanoid = swim.humanoid
        if humanoid.Parent then
            for kind, enabled in pairs(swim.originalStates) do
                humanoid:SetStateEnabled(kind, enabled)
            end
            if humanoid.Health > 0 and humanoid:GetState() == state.Swimming then
                local nextState = humanoid.FloorMaterial == Enum.Material.Air and state.Freefall or state.Running
                if swim.previousState ~= state.Swimming then
                    humanoid:ChangeState(humanoid:GetStateEnabled(nextState) and nextState or swim.previousState)
                end
            end
        end
    end
    setStatus(message or "Плавание выключено")
end

local function movement(humanoid)
    if Input:GetFocusedTextBox() then return Vector3.zero end

    local keys = Enum.KeyCode
    local forward = (Input:IsKeyDown(keys.W) and 1 or 0) - (Input:IsKeyDown(keys.S) and 1 or 0)
    local side = (Input:IsKeyDown(keys.D) and 1 or 0) - (Input:IsKeyDown(keys.A) and 1 or 0)
    local up = Input:IsKeyDown(keys.Space) and 1 or 0
    local down = (Input:IsKeyDown(keys.LeftControl) or Input:IsKeyDown(keys.RightControl)) and 1 or 0
    local camera = Workspace.CurrentCamera
    local direction = humanoid.MoveDirection
    if camera and (forward ~= 0 or side ~= 0) then
        direction = camera.CFrame.LookVector * forward + camera.CFrame.RightVector * side
    end
    direction += Vector3.new(0, up - down, 0)
    return direction / math.max(1, direction.Magnitude)
end

local function start(speed)
    if active then
        active.speed = speed
        setStatus(string.format("Плавание · %g студ/с", speed))
        return
    end

    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = humanoid and humanoid.RootPart
    if not root or humanoid.Health <= 0 or root.Anchored or humanoid.SeatPart or humanoid.PlatformStand then
        setStatus("Встань на ноги и попробуй снова", true)
        return
    end

    local attachment = Instance.new("Attachment")
    attachment.Name = "AirSwimAttachment"
    attachment.Parent = root

    local mover = Instance.new("LinearVelocity")
    mover.Name = "AirSwimVelocity"
    mover.Attachment0 = attachment
    mover.RelativeTo = Enum.ActuatorRelativeTo.World
    mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
    mover.ForceLimitsEnabled = true
    mover.MaxForce = root.AssemblyMass * (Workspace.Gravity + 700)
    mover.VectorVelocity = Vector3.zero
    mover.Parent = root

    local originalStates = {}
    local swim = {
        character = character,
        humanoid = humanoid,
        previousState = humanoid:GetState(),
        originalStates = originalStates,
        attachment = attachment,
        mover = mover,
        speed = speed,
    }
    originalStates[state.Swimming] = humanoid:GetStateEnabled(state.Swimming)
    humanoid:SetStateEnabled(state.Swimming, true)
    for _, kind in ipairs(blockedStates) do
        originalStates[kind] = humanoid:GetStateEnabled(kind)
        humanoid:SetStateEnabled(kind, false)
    end
    humanoid:ChangeState(state.Swimming)

    swim.step = RunService.PreSimulation:Connect(function(delta)
        if not gui.Parent or player.Character ~= character or humanoid.Health <= 0
            or not root.Parent or humanoid.RootPart ~= root or root.Anchored
            or humanoid.SeatPart or humanoid.PlatformStand then
            stop()
            return
        end
        if humanoid:GetState() ~= state.Swimming then humanoid:ChangeState(state.Swimming) end
        local target = movement(humanoid) * swim.speed
        mover.VectorVelocity = mover.VectorVelocity:Lerp(target, 1 - math.exp(-12 * delta))
    end)
    swim.died = humanoid.Died:Connect(function() stop() end)
    active = swim
    setStatus(string.format("Плавание · %g студ/с", speed))
end

local function runCommand()
    local command, value = input.Text:lower():match("^%s*(%S+)%s*(.-)%s*$")
    if command == "unswim" and value == "" then
        stop()
    elseif command == "swim" then
        local speed = value == "" and (active and active.speed or defaultSpeed) or tonumber(value)
        if not speed or speed ~= speed or speed < minSpeed or speed > maxSpeed then
            setStatus("Скорость от 1 до 100", true)
            return
        end
        start(speed)
    else
        setStatus("Команды: swim 25 и unswim", true)
        return
    end
    input.Text = ""
end

input.FocusLost:Connect(function(enterPressed)
    if enterPressed then runCommand() end
end)
runButton.Activated:Connect(runCommand)

local characterRemoving = player.CharacterRemoving:Connect(function(character)
    if active and active.character == character then stop() end
end)
gui.Destroying:Once(function()
    characterRemoving:Disconnect()
    if active then stop() end
end)
gui.Parent = playerGui
