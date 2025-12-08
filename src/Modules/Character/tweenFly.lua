local Fly = {}

local Player = game.Players.LocalPlayer
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")

local SPEED = 60
local TWEEN_TIME = 0.16
local flying = false
local activeTween = nil
local flyKey = Enum.KeyCode.F

local moveState = {W=false,A=false,S=false,D=false,Up=false,Down=false}

local keyMap = {
	[Enum.KeyCode.W] = "W",
	[Enum.KeyCode.A] = "A",
	[Enum.KeyCode.S] = "S",
	[Enum.KeyCode.D] = "D",
	[Enum.KeyCode.Space] = "Up",
	[Enum.KeyCode.LeftShift] = "Down"
}

local function stopTween()
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
end

local function getMoveVector(cam, HRP)
	local forward = cam.CFrame.LookVector
	local right = cam.CFrame.RightVector
	local m = Vector3.zero
	if moveState.W then m += forward end
	if moveState.S then m -= forward end
	if moveState.A then m -= right end
	if moveState.D then m += right end
	if moveState.Up then m += Vector3.yAxis end
	if moveState.Down then m -= Vector3.yAxis end
	if m.Magnitude > 0 then m = m.Unit end
	return m
end

local function noclip(char, state)
	for _,v in ipairs(char:GetDescendants()) do
		if v:IsA("BasePart") then
			v.CanCollide = not state
		end
	end
end

local HRP, Hum

local function setupCharacter(char)
	Hum = char:FindFirstChildWhichIsA("Humanoid")
	HRP = char:WaitForChild("HumanoidRootPart")
	if flying then
		Hum.PlatformStand = true
		noclip(char, true)
	end
end

-- handle respawn
Player.CharacterAdded:Connect(function(char)
	setupCharacter(char)
end)

function Fly.start()
	if flying then return end
	if not Player.Character then return end

	flying = true
	setupCharacter(Player.Character)

	RunService:BindToRenderStep("StableFly", 500, function()
		if not flying or not HRP or not Hum then return end

		HRP.AssemblyLinearVelocity = Vector3.zero
		HRP.AssemblyAngularVelocity = Vector3.zero
		HRP.CFrame = CFrame.new(HRP.Position, HRP.Position + workspace.CurrentCamera.CFrame.LookVector)

		local move = getMoveVector(workspace.CurrentCamera, HRP)
		if move.Magnitude == 0 then stopTween() return end

		local target = HRP.Position + move * SPEED
		stopTween()
		activeTween = TweenService:Create(
			HRP,
			TweenInfo.new(TWEEN_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{CFrame = CFrame.new(target, target + workspace.CurrentCamera.CFrame.LookVector)}
		)
		activeTween:Play()
	end)
end

function Fly.stop()
	flying = false
	stopTween()
	RunService:UnbindFromRenderStep("StableFly")
	if Hum then Hum.PlatformStand = false end
	if Player.Character then noclip(Player.Character, false) end
end

function Fly.setKey(key)
	flyKey = key
end

UIS.InputBegan:Connect(function(input,g)
	if g then return end
	if input.KeyCode == flyKey then
		if flying then Fly.stop() else Fly.start() end
		return
	end
	local k = keyMap[input.KeyCode]
	if k then moveState[k] = true end
end)

UIS.InputEnded:Connect(function(input)
	local k = keyMap[input.KeyCode]
	if k then moveState[k] = false end
end)

return Fly
