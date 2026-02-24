-- Scripted by Breaking Coder in 2025

-- VARIABLES --

-- Services
local RS = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local CP = game:GetService("ContentProvider")

-- Player setup
local Plr = game.Players.LocalPlayer
local Char = Plr.Character or Plr.CharacterAdded:Wait()
local CharHum = Char:WaitForChild("Humanoid")
local Camera = workspace.CurrentCamera

-- Camera setup and disable mouse icon
Plr.CameraMode = Enum.CameraMode.LockFirstPerson
UIS.MouseIconEnabled = false

-- Folders
local WeaponHandlers = game.ReplicatedStorage:WaitForChild("WeaponHandlers")
local Modules = game.ReplicatedStorage:WaitForChild("Modules")
local Viewmodels = game.ReplicatedStorage:WaitForChild("Viewmodels")

-- Remotes
local ReplicateRemote = WeaponHandlers:WaitForChild("ReplicateWeapon")

-- Values
local EquippedWeapon = WeaponHandlers:WaitForChild("EquippedWeapon")

-- Modules
local WeaponConfigs = require(Modules:WaitForChild("WeaponConfigs"))

-- GUI
local ScopeGui = Plr.PlayerGui:WaitForChild("ScopeGui")
local ScopeFrame = ScopeGui:WaitForChild("Scope")
ScopeFrame.Visible = true

-- Bobbing settings
local BobScaleIdle = 0.02
local BobScaleWalk = 0.06
local BobScaleSprint = 0.12

-- Sway settings
local SwayIntensity = 0.002
local SwaySmoothness = 12
local MouseDelta = Vector2.zero
local CurrentSway = CFrame.new()

-- Aim settings
local Aiming = false
local AimConns = {}

-- FUNCTIONS AND EVENTS --

-- Tracks mouse movement
UIS.InputChanged:Connect(function(Input)
	if Input.UserInputType == Enum.UserInputType.MouseMovement then
		MouseDelta = Input.Delta
	end
end)

-- Tweaks to original position
RS.RenderStepped:Connect(function()
	MouseDelta = MouseDelta:Lerp(Vector3.zero, 0.15)
end)

-- Removes the old viewmodel and resets FOV
local function DestroyViewmodel()
	Aiming = false
	RS:UnbindFromRenderStep("Viewmodel")

	for _, v in pairs(AimConns) do
		if v ~= nil then
			v:Disconnect()
		end
	end

	TS:Create(Camera, TweenInfo.new(0.25), {FieldOfView = 70}):Play()

	if Camera:FindFirstChildWhichIsA("Model") then
		Camera:FindFirstChildWhichIsA("Model"):Destroy()
	end
end

-- Creates and plays the equip animation
local function EquipEffect()
	EquipOffset = CFrame.new(0, -3, -2)

	local OffsetValue = Instance.new("CFrameValue")
	OffsetValue.Value = EquipOffset

	local Info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local Tween = TS:Create(OffsetValue, Info, {Value = CFrame.new()})

	OffsetValue:GetPropertyChangedSignal("Value"):Connect(function()
		EquipOffset = OffsetValue.Value
	end)

	Tween:Play()
end

-- Aiming FOV effect when MB2 is pressed
local function AimEffect(Viewmodel:Model)
	table.insert(AimConns,
		UIS.InputBegan:Connect(function(Input, GP)
			if GP then return end
			if not Viewmodel:GetAttribute("CanAim") then return end

			if Input.UserInputType == Enum.UserInputType.MouseButton2 then			
				Aiming = true
				ScopeFrame.Visible = false
				TS:Create(Camera, TweenInfo.new(0.25), {FieldOfView = 50}):Play()
			end
		end))

	table.insert(AimConns,
		UIS.InputEnded:Connect(function(Input)
			if not Viewmodel:GetAttribute("CanAim") then return end

			if Input.UserInputType == Enum.UserInputType.MouseButton2 then
				Aiming = false
				ScopeFrame.Visible = true
				TS:Create(Camera, TweenInfo.new(0.25), {FieldOfView = 70}):Play()
			end
		end))
end

-- Loads player's clothing and puts it in the viewmodel's arms
local function LoadClothing(Viewmodel)
	local Shirt = Char:WaitForChild("Shirt"):Clone()
	Shirt.Parent = Viewmodel

	local BodyColors = Char:WaitForChild("Body Colors"):Clone()
	BodyColors.Parent = Viewmodel
end

-- Loads the idle animation and plays it in the viewmodel's humanoid
local function LoadAnim(Viewmodel, Hum, GunConfig)
	if GunConfig.IdleAnim ~= nil then
		local IdleAnim = Instance.new("Animation")
		IdleAnim.Name = "IdleAnim"
		IdleAnim.AnimationId = GunConfig.IdleAnim

		CP:PreloadAsync({IdleAnim})
		IdleAnim.Parent = Viewmodel

		local Track:AnimationTrack = Hum.Animator:LoadAnimation(IdleAnim)
		Track.Priority = Enum.AnimationPriority.Idle
		Track:Play()
	end
end

-- Creates the viewmodel based on the equipped weapon, or arms model if it's default
local function CreateViewmodel()
	local Viewmodel

	if EquippedWeapon.Value ~= "" then
		Viewmodel = Viewmodels:WaitForChild(EquippedWeapon.Value):Clone()
		Viewmodel.Parent = Camera

		local Hum = Char:WaitForChild("Humanoid"):Clone()
		Hum.Parent = Viewmodel
		Hum.PlatformStand = true

		LoadClothing(Viewmodel)
		LoadAnim(Viewmodel, Hum, WeaponConfigs[Viewmodel.Name])
	else
		for _, v in pairs(Viewmodels:GetChildren()) do
			if v:HasTag("Default") then
				Viewmodel = v:Clone()
				Viewmodel.Parent = Camera

				local Hum = Char:WaitForChild("Humanoid"):Clone()
				Hum.Parent = Viewmodel
				Hum.PlatformStand = true

				LoadClothing(Viewmodel)
				LoadAnim(Viewmodel, Hum, WeaponConfigs[Viewmodel.Name])
			end
		end
	end

	return Viewmodel
end

-- Render loop that handles viewmodel aiming, bobbing and sway
local function RunViewmodel(Viewmodel, GunConfig)
	local CurrentOffset = CFrame.new()
	local LastOffset = CFrame.new()

	local Walking = false
	local AimPart = not Viewmodel:HasTag("Default") and Viewmodel.Weapon:WaitForChild("AimPart")

	RS:BindToRenderStep("Viewmodel", 301, function(dt)
		if CharHum.MoveDirection.Magnitude > 0 then
			Walking = true
		else
			Walking = false
		end
		
		-- Calculates aiming offset
		local TargetOffset = CFrame.new()
		if Aiming then
			if AimPart then
				local AimOffset = Viewmodel.PrimaryPart.CFrame:ToObjectSpace(AimPart.CFrame)
				TargetOffset = AimOffset:Inverse()
			end
		else
			TargetOffset = CFrame.new()
		end

		CurrentOffset = CurrentOffset:Lerp(TargetOffset, dt * 10)

		-- Calculates movement bobbing
		local TargetBob = CFrame.new()
		if Walking then
			if CharHum.WalkSpeed < 17.5 then
				-- Walk
				if not Aiming then
					local SwayX = math.sin(tick() * 6) * BobScaleWalk
					local SwayY = math.cos(tick() * 10) * BobScaleWalk
					TargetBob = CFrame.new(SwayX, SwayY, 0)
				else
					local SwayX = math.sin(tick() * 6) * 0.02
					local SwayY = math.cos(tick() * 10) * 0.02
					TargetBob = CFrame.new(SwayX, SwayY, 0)
				end
			else
				-- Sprint
				local SwayX = math.sin(tick() * 6) * BobScaleSprint
				local SwayY = math.cos(tick() * 10) * BobScaleSprint
				local Sway = CFrame.new(SwayX, SwayY, 0)

				if not Aiming then
					local Tilt = CFrame.Angles(math.rad(0), math.rad(GunConfig.SprintTilt), 0)			
					TargetBob = Sway * Tilt
				else
					TargetBob = CFrame.new(SwayX, SwayY, 0)
				end
			end
		else
			if not Aiming then
				-- Idle
				local SwayX = math.sin(tick() * 2.5) * BobScaleIdle
				local SwayY = math.cos(tick() * 2.5) * BobScaleIdle
				TargetBob = CFrame.new(SwayX, SwayY, 0)
			end
		end

		LastOffset = LastOffset:Lerp(TargetBob, dt * 10)

		local TargetSway = CFrame.Angles(-MouseDelta.Y * SwayIntensity, MouseDelta.X * SwayIntensity, 0)
		CurrentSway = CurrentSway:Lerp(TargetSway, dt * SwaySmoothness)
		
		-- Updates viewmodel's position
		Viewmodel:PivotTo(Camera.CFrame * EquipOffset * CurrentOffset * LastOffset * CurrentSway)
	end)
end

-- Main function that basically handles viewmodel creation, aiming, equipping and viewmodel cleanup
local function Main()
	DestroyViewmodel()

	local Viewmodel = CreateViewmodel()
	local GunConfig = WeaponConfigs[Viewmodel.Name]

	if not Viewmodel:HasTag("Default") then
		ReplicateRemote:FireServer(Viewmodel.Name)
	end

	EquipEffect()
	AimEffect(Viewmodel)
	RunViewmodel(Viewmodel, GunConfig)

	if not Viewmodel:HasTag("Default") then
		ScopeFrame.Visible = true
	else
		ScopeFrame.Visible = false
	end

	Viewmodel:GetAttributeChangedSignal("CanAim"):Connect(function()
		if not Viewmodel:GetAttribute("CanAim") then
			TS:Create(Camera, TweenInfo.new(0.25), {FieldOfView = 70}):Play()
			Aiming = false
			ScopeFrame.Visible = true
		end
	end)
end

Main()
EquippedWeapon.Changed:Connect(Main)
