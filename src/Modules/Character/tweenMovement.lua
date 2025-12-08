local getgenv = assert(getgenv, "~ Executer requires getgenv")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Client = Players.LocalPlayer
local Char = Client.Character
local Hrp = Char:WaitForChild("HumanoidRootPart")
local Camera = workspace.Camera or workspace:FindFirstChildWhichIsA("Camera")

local noclipThread
local movementConnection
local movement = {}
movement._Created = {}
movement._Keys = {W=false, A=false, S=false, D=false, Space=false, Shift=false}

local function tweenMove(character: Instance, enable_noclip)
    if not character then
        return false
    end

    local rootpart = character:WaitForChild("HumanoidRootPart")
    if not rootpart then
        return false
    end
    local hum = character:FindFirstChildOfClass("Humanoid")
    -- if hum then hum.PlatformStand = true end

    noclipThread = task.spawn(function()
        if enable_noclip then
            for _, parts in ipairs(character:GetDescendants()) do
                if typeof(parts) == "BasePart" then
                    parts.CanCollide = false
                end
            end
        end
    end)

    local down
    local up

    pcall(function()
        down = UserInputService.InputBegan:Connect(function(i)
            if i.KeyCode == Enum.KeyCode.W then movement._Keys.W = true end
            if i.KeyCode == Enum.KeyCode.A then movement._Keys.A = true end
            if i.KeyCode == Enum.KeyCode.S then movement._Keys.S = true end
            if i.KeyCode == Enum.KeyCode.D then movement._Keys.D = true end
            if i.KeyCode == Enum.KeyCode.Space then movement._Keys.Space = true end
            if i.KeyCode == Enum.KeyCode.LeftShift then movement._Keys.Shift = true end
        end)

        up = UserInputService.InputEnded:Connect(function(i)
            if i.KeyCode == Enum.KeyCode.W then movement._Keys.W = false end
            if i.KeyCode == Enum.KeyCode.A then movement._Keys.A = false end
            if i.KeyCode == Enum.KeyCode.S then movement._Keys.S = false end
            if i.KeyCode == Enum.KeyCode.D then movement._Keys.D = false end
            if i.KeyCode == Enum.KeyCode.Space then movement._Keys.Space = false end
            if i.KeyCode == Enum.KeyCode.LeftShift then movement._Keys.Shift = false end
        end)

        movementConnection = RunService.RenderStepped:Connect(function(x)
            local dir = Vector3.new()

            if movement._Keys.W then dir += Camera.CFrame.LookVector end
            if movement._Keys.S then dir -= Camera.CFrame.LookVector end
            if movement._Keys.A then dir -= Camera.CFrame.RightVector end
            if movement._Keys.D then dir += Camera.CFrame.RightVector end
            if movement._Keys.Space then dir += Vector3.new(0,1,0) end
            if movement._Keys.Shift then dir -= Vector3.new(0,1,0) end

            if dir.Magnitude > 0 then
                dir = dir.Unit * config.speed
            end

            local goal = rootpart.CFrame.Position + dir * x
            local tween = TweenService:Create(rootpart, TweenInfo.new(config.smooth, Enum.EasingStyle.Linear), {CFrame = CFrame.new(goal, goal + Camera.CFrame.LookVector)})
            tween:Play()
        end)
    end)

    movement._Created.Cleanup = function()
        if movementConnection then movementConnection:Disconnect() end
        if down then down:Disconnect() end
        if up then up:Disconnect() end
        if hum then hum.PlatformStand = false end
    end

    return true
end

tweenMove(Char, true)
local b = Client.CharacterAdded:Connect(function()
    tweenMove(Char, true)
end)
