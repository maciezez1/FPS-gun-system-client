-- Discord: @maciezez || Roblox: @Maciezez

-- VARIABLES --

-- Services
local RS = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local CP = game:GetService("ContentProvider")

-- Player setup
local Plr = game.Players.LocalPlayer
local Char = Plr.Character or Plr.CharacterAdded:Wait()
local Camera = workspace.CurrentCamera

-- Locks the camera in first person and disables mouse
Plr.CameraMode = Enum.CameraMode.LockFirstPerson
UIS.MouseIconEnabled = false

-- Folders
local WeaponHandlers = game.ReplicatedStorage:WaitForChild("WeaponHandlers")
local Modules = game.ReplicatedStorage:WaitForChild("Modules")
local Viewmodels = game.ReplicatedStorage:WaitForChild("Viewmodels")

-- Remote for replicating viewmodel creation to the server
local ReplicateRemote = WeaponHandlers:WaitForChild("ReplicateWeapon")

-- Stores the current equipped weapon
local EquippedWeapon = WeaponHandlers:WaitForChild("EquippedWeapon")

-- A module containing weapon configurations
local WeaponConfigs = require(Modules:WaitForChild("WeaponConfigs"))

-- GUI
local ScopeGui = Plr.PlayerGui:WaitForChild("ScopeGui")
local ScopeFrame = ScopeGui:WaitForChild("Scope")
ScopeFrame.Visible = true

-- Current equipped viewmodel(weapon)
local CurrentController = nil

-- Metatable for viewmodel controller
local ViewmodelController = {}
ViewmodelController.__index = ViewmodelController

-- Creates a new controller and sets up the viewmodel
function ViewmodelController.new(Viewmodel)
	local self = setmetatable({}, ViewmodelController)
	
	self.Viewmodel = Viewmodel
	self.Camera = Camera
	
	self.Character = Char
	self.Humanoid = Char:WaitForChild("Humanoid")
	self.ViewmodelHumanoid = self.Humanoid:Clone() -- Clones the existing humanoid for the viewmodel
	self.ViewmodelHumanoid.PlatformStand = true
	self.ViewmodelHumanoid.Parent = self.Viewmodel
	
	self.GunConfig = WeaponConfigs[EquippedWeapon.Value] -- Config for the current weapon
	
	-- State
	
	self.Aiming = false
	self.Walking = false
	self.Colliding = false
	
	-- Viewmodel offsets
	
	self.CurrentOffset = CFrame.new()
	self.CurrentSway = CFrame.new()
	self.WallOffset = CFrame.new()
	self.MouseDelta = Vector3.zero
	self.ShakeOffset = CFrame.new()
	self.LastOffset = CFrame.new()
	self.EquipOffset = CFrame.new(0, -3, -2)  -- Offset before equipping the weapon
	
	-- Connections for this controller are stored here, so they can be later destroyed
	self.Connections = {}
	
	self:Init()
	
	return self
end

-- Initializes the controller by setting up events, animations and rendering

function ViewmodelController:Init()
	self:ConnectEvents()
	
	self:EquipEffect()
	self:LoadClothing()
	self:LoadAnim()

	self:RunViewmodel()
end

-- Function for destroying the controller

function ViewmodelController:Destroy()
	self.Aiming = false
	
	-- Stops the render loop
	RS:UnbindFromRenderStep("Viewmodel")
	
	
	-- Disconnects all the connections
	for _, v in pairs(self.Connections) do
		if v ~= nil then
			v:Disconnect()
		end
	end
	
	table.clear(self.Connections)
	
	
	-- Resets the camera
	TS:Create(
		self.Camera,
		TweenInfo.new(0.25),
		{FieldOfView = 70}
	):Play()
	
	-- Destroys the viewmodel
	if self.Viewmodel then
		self.Viewmodel:Destroy()
		self.Viewmodel = nil
	end
end

-- Connects the main events for the controller
function ViewmodelController:ConnectEvents()
	-- Aiming FOV effect when MB2 is pressed
	table.insert(self.Connections,
		UIS.InputBegan:Connect(function(Input, GP)
			if GP then return end
			if not self.Viewmodel:GetAttribute("CanAim") or self.Colliding then return end

			if Input.UserInputType == Enum.UserInputType.MouseButton2 then			
				self.Aiming = true
				ScopeFrame.Visible = false
				TS:Create(self.Camera, TweenInfo.new(0.25), {FieldOfView = 50}):Play()
			end
		end))
	-- Resets FOV when MB2 is released
	table.insert(self.Connections,
		UIS.InputEnded:Connect(function(Input)
			if not self.Viewmodel:GetAttribute("CanAim") then return end

			if Input.UserInputType == Enum.UserInputType.MouseButton2 then
				self.Aiming = false
				ScopeFrame.Visible = true
				TS:Create(self.Camera, TweenInfo.new(0.25), {FieldOfView = 70}):Play()
			end
		end))

	-- Tracks mouse movement and applies it to the viewmodel in the render loop
	table.insert(self.Connections, 
		UIS.InputChanged:Connect(function(Input)
			if Input.UserInputType == Enum.UserInputType.MouseMovement then
				self.MouseDelta = Input.Delta
			end
		end))
end

-- Creates and plays the equip animation
function ViewmodelController:EquipEffect()
	-- Creates a CFrameValue so we can access :GetPropertyChangedSignal() method
	local OffsetValue = Instance.new("CFrameValue")
	OffsetValue.Value = self.EquipOffset

	local Info = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	
	-- Tweens the offset value from start to zero value
	local Tween = TS:Create(OffsetValue, Info, {Value = CFrame.new()})

	OffsetValue:GetPropertyChangedSignal("Value"):Connect(function()
		-- Updates the equip offset to the value and later updates the viewmodel's CFrame
		self.EquipOffset = OffsetValue.Value
	end)

	Tween:Play()
	
	Tween.Completed:Connect(function()
		-- Destroyed when tween is completed
		OffsetValue:Destroy()
	end)
end

-- Loads the player's clothing + skin tone and puts it in the viewmodel's arms
function ViewmodelController:LoadClothing()
	local Shirt = Char:WaitForChild("Shirt"):Clone()
	Shirt.Parent = self.Viewmodel

	local BodyColors = Char:WaitForChild("Body Colors"):Clone()
	BodyColors.Parent = self.Viewmodel
end

-- Loads the idle animation and plays it in the viewmodel's humanoid
function ViewmodelController:LoadAnim()
	-- Checks if the viewmodel is a weapon(default viewmodel doesn't contain an idle animation)
	if self.GunConfig.IdleAnim ~= nil then
		local IdleAnim = Instance.new("Animation")
		IdleAnim.Name = "IdleAnim"
		IdleAnim.AnimationId = self.GunConfig.IdleAnim
		
		-- Animations are preloaded to prevent delays
		CP:PreloadAsync({IdleAnim})
		IdleAnim.Parent = self.Viewmodel

		local Track:AnimationTrack = self.ViewmodelHumanoid.Animator:LoadAnimation(IdleAnim)
		Track.Priority = Enum.AnimationPriority.Idle
		Track:Play()
	end
end

-- Pushes the weapon away when colliding with objects
function ViewmodelController:GetWallOffset()
	local MaxDistance = 4 -- in studs
	
	-- Excludes the viewmodel and the player's character from the params
	local Params = RaycastParams.new()
	Params.FilterType = Enum.RaycastFilterType.Exclude
	Params.FilterDescendantsInstances = {self.Character, self.Camera}
	
	-- Starts from the camera's position and goes forward by 4 studs
	local Origin = self.Camera.CFrame.Position
	local Direction = self.Camera.CFrame.LookVector * MaxDistance

	local Result = workspace:Raycast(Origin, Direction, Params)

	if Result then
		self.Colliding = true
		
		-- Calculates the distance between the camera and the object
		local PushAmount = MaxDistance - Result.Distance
		
		-- Limits the push amount to 0.4 studs max
		PushAmount = math.clamp(PushAmount, 0, 0.4)
		
		-- Tilts and pushes away the viewmodel
		local Tilt = CFrame.Angles(0, math.rad(50), 0)
		
		return Tilt * CFrame.new(0, 0, PushAmount)
	end
	
	self.Colliding = false
	
	return CFrame.new()
end

-- Renders a loop that handles viewmodel positioning, aiming, bobbing and sway
function ViewmodelController:RunViewmodel()
	-- Checks if the viewmodel contains an aim part
	local AimPart = not self.Viewmodel:HasTag("Default") and self.Viewmodel.Weapon:WaitForChild("AimPart")
	
	-- Handles the viewmodel's offset and tweening
	RS:BindToRenderStep("Viewmodel", 301, function(dt)
		-- Checks if the player is moving
		self.Walking = self.Humanoid.MoveDirection.Magnitude > 0
		
		-- Smoothly reduces the stored mouse delta back toward zero
		self.MouseDelta = self.MouseDelta:Lerp(Vector3.zero, 0.15)
		
		-- Calculates aiming offset
		local TargetOffset = CFrame.new()
		
		if self.Aiming and not self.Colliding then
			if AimPart then
				-- Converts the aim part's world CFrame to the PrimaryPart's local space
				local AimOffset = self.Viewmodel.PrimaryPart.CFrame:ToObjectSpace(AimPart.CFrame)
				-- Inverts the offset to properly aim the viewmodel
				TargetOffset = AimOffset:Inverse()
			end
		else
			TargetOffset = CFrame.new()
		end
		
		-- Interpolates the current offset toward the target offset by delta time * 10
		self.CurrentOffset = self.CurrentOffset:Lerp(TargetOffset, dt * 10)

		-- Calculates movement bobbing
		local TargetBob = CFrame.new()
		
		-- Applies bobbing only while walking
		if self.Walking then
			if self.Humanoid.WalkSpeed < 17.5 then
				-- Walk
				
				if not self.Aiming then
					-- Creates a stronger bobbing effect while walking and not aiming
					
					local SwayX = math.sin(tick() * 6) * self.GunConfig.BobScaleWalk
					local SwayY = math.cos(tick() * 10) * self.GunConfig.BobScaleWalk
					TargetBob = CFrame.new(SwayX, SwayY, 0)
				else
					-- Reduces bobbing while aiming for better weapon stability
					
					local SwayX = math.sin(tick() * 6) * 0.02
					local SwayY = math.cos(tick() * 10) * 0.02
					TargetBob = CFrame.new(SwayX, SwayY, 0)
				end
			else
				-- Sprint
				
				local SwayX = math.sin(tick() * 6) * self.GunConfig.BobScaleSprint
				local SwayY = math.cos(tick() * 10) * self.GunConfig.BobScaleSprint
				local Sway = CFrame.new(SwayX, SwayY, 0)

				if not self.Aiming or not self.Colliding then	
					-- Tilts the weapon during sprinting while not aiming nor colliding
					
					local Tilt = CFrame.Angles(math.rad(0), math.rad(self.GunConfig.SprintTilt), 0)	
					TargetBob = Sway * Tilt
				else
					TargetBob = CFrame.new(SwayX, SwayY, 0)
				end
			end
		else
			-- Idle
			
			if not self.Aiming then
				-- Creates a small breathing-like effect while idle
				
				local SwayX = math.sin(tick() * 2.5) * self.GunConfig.BobScaleIdle
				local SwayY = math.cos(tick() * 2.5) * self.GunConfig.BobScaleIdle
				TargetBob = CFrame.new(SwayX, SwayY, 0)
			end
		end
		
		-- Interpolates the current bobbing offset toward the target bobbing offset
		self.LastOffset = self.LastOffset:Lerp(TargetBob, dt * 10)
		
		-- Combines mouse delta and sway intensity to create a more dynamic sway effect
		local TargetSway = CFrame.Angles(-self.MouseDelta.Y * self.GunConfig.SwayIntensity, self.MouseDelta.X * self.GunConfig.SwayIntensity, 0)
		-- Interploates the current sway offset based on sway smoothness
		self.CurrentSway = self.CurrentSway:Lerp(TargetSway, dt * self.GunConfig.SwaySmoothness)
		
		-- Gets and tweens the wall collision offset
		local TargetWallOffset = self:GetWallOffset()
		self.WallOffset = self.WallOffset:Lerp(TargetWallOffset, dt * 10)
		
		-- Combines all the offsets to get the final offset for the viewmodel
		local Offsets = 
			self.CurrentOffset 
			* self.LastOffset 
			* self.CurrentSway 
			* self.WallOffset 
			* self.EquipOffset
		
		-- Updates viewmodel's CFrame
		self.Viewmodel:PivotTo(self.Camera.CFrame * Offsets)
	end)
end

local function EquipWeapon()
	-- Destroys the old controller
	if CurrentController then
		CurrentController:Destroy()
		CurrentController = nil
	end

	local Viewmodel
	
	-- Clones the viewmodel based on the equipped weapon while "Hand" is the default weapon
	if EquippedWeapon.Value ~= "Hand" then
		Viewmodel = Viewmodels:WaitForChild(EquippedWeapon.Value):Clone()
	else
		for _, v in Viewmodels:GetChildren() do
			if v:HasTag("Default") then
				Viewmodel = v:Clone()
				break
			end
		end
	end
	
	Viewmodel.Parent = Camera
	
	-- Replicates the viewmodel to the server, so other players can see it too
	ReplicateRemote:FireServer(Viewmodel.Name)

	-- Creates a new controller
	CurrentController = ViewmodelController.new(Viewmodel)
end

EquipWeapon()

-- Tracks weapon equipping
EquippedWeapon.Changed:Connect(EquipWeapon)
