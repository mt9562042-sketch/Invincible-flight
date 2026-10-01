-- LocalScript placed inside StarterPlayerScripts
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local camera = workspace.CurrentCamera

-- CONFIGURATION
local FLIGHT_TOGGLE_KEY = Enum.KeyCode.E
local BOOST_CYCLE_KEY = Enum.KeyCode.LeftControl
local CRUISE_SPEED = 20            

-- THE 4 BOOST SPEEDS
local BOOST_SPEEDS = {
	[0] = CRUISE_SPEED, 
	[1] = 50,           
	[2] = 100,          
	[3] = 250,          
	[4] = 500           
}

local ACCELERATION = 0.05          
local DEFAULT_FOV = 70             
local MAX_FOV_BOOST = 110          

-- ANIMATION IDs
local IDLE_FLY_ID = "rbxassetid://82836237559853"   
local SPEED_FLY_ID = "rbxassetid://127916698574790" 

-- STATE VARIABLES
local isFlying = false
local boostLevel = 0 
local currentSpeed = 0
local moveDirection = Vector3.zero
local currentAnimTrack = nil
local flightSound = nil
local isAscending = false 

-- PHYSICS SETUP
local linearVelocity = nil
local attachment = nil

local function setupPhysics()
	local oldAttachment = rootPart:FindFirstChild("FlightAttachment")
	if oldAttachment then oldAttachment:Destroy() end

	attachment = Instance.new("Attachment")
	attachment.Name = "FlightAttachment"
	attachment.Parent = rootPart

	linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.MaxForce = math.huge
	linearVelocity.VectorVelocity = Vector3.zero
	linearVelocity.Attachment0 = attachment
	linearVelocity.Enabled = false
	linearVelocity.Parent = rootPart
	
	flightSound = SoundService:FindFirstChild("FlightSound")
end

setupPhysics()

local function lerp(start, goal, alpha)
	return start + (goal - start) * alpha
end

-- Create Mobile UI Panel containing Fly and Boost buttons
local function createMobileUI()
	local playerGui = player:WaitForChild("PlayerGui")
	local oldGui = playerGui:FindFirstChild("FlightMobileUI")
	if oldGui then oldGui:Destroy() end
	
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "FlightMobileUI"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui
	
	local container = Instance.new("Frame")
	container.Name = "ButtonPanel"
	container.Size = UDim2.new(0, 180, 0, 90)
	container.Position = UDim2.new(0.75, -190, 0.65, 0) 
	container.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	container.BackgroundTransparency = 0.4
	container.BorderSizePixel = 2
	container.Parent = screenGui
	
	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0, 20)
	containerCorner.Parent = container
	
	local flyButton = Instance.new("TextButton")
	flyButton.Name = "FlyButton"
	flyButton.Size = UDim2.new(0, 70, 0, 70)
	flyButton.Position = UDim2.new(0, 10, 0, 10)
	flyButton.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
	flyButton.Text = "Fly"
	flyButton.TextSize = 20
	flyButton.Font = Enum.Font.SourceSansBold
	flyButton.Parent = container
	
	local flyCorner = Instance.new("UICorner")
	flyCorner.CornerRadius = UDim.new(1, 0)
	flyCorner.Parent = flyButton
	
	local boostButton = Instance.new("TextButton")
	boostButton.Name = "BoostButton"
	boostButton.Size = UDim2.new(0, 70, 0, 70)
	boostButton.Position = UDim2.new(0, 100, 0, 10)
	boostButton.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
	boostButton.Text = "Boost\nOff"
	boostButton.TextSize = 14
	boostButton.Font = Enum.Font.SourceSansBold
	boostButton.Parent = container
	
	local boostCorner = Instance.new("UICorner")
	boostCorner.CornerRadius = UDim.new(1, 0)
	boostCorner.Parent = boostButton
	
	local function updateBoostButtonText()
		if boostLevel == 0 then
			boostButton.Text = "Boost\nOff"
			boostButton.BackgroundColor3 = Color3.fromRGB(240, 240, 240)
		else
			boostButton.Text = "Boost\nLvl " .. boostLevel
			boostButton.BackgroundColor3 = Color3.fromRGB(150, 255, 150)
		end
	end

	flyButton.MouseButton1Click:Connect(function()
		toggleFlight()
		updateBoostButtonText()
	end)
	
	boostButton.MouseButton1Click:Connect(function()
		if isFlying then
			cycleBoost()
			updateBoostButtonText()
		end
	end)
end

createMobileUI()

local function playFlightAnimation(animationId)
	if currentAnimTrack and currentAnimTrack.Animation.AnimationId == animationId then
		return 
	end
	if currentAnimTrack then
		currentAnimTrack:Stop(0.25) 
	end
	
	local animObject = Instance.new("Animation")
	animObject.AnimationId = animationId
	
	local animator = humanoid:WaitForChild("Animator")
	currentAnimTrack = animator:LoadAnimation(animObject)
	currentAnimTrack.Priority = Enum.AnimationPriority.Action
	currentAnimTrack.Looped = true
	currentAnimTrack:Play(0.25) 
end

local function updateFlightState(speedRatio)
	local lookDirection = camera.CFrame.LookVector
	
	if boostLevel > 0 and moveDirection.Magnitude > 0 then
		playFlightAnimation(SPEED_FLY_ID)
	else
		playFlightAnimation(IDLE_FLY_ID)
	end
	
	-- FULL 3D SHIFT-LOCK TILTING
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	
	-- Calculate the pitch angle (looking up or down) from the camera's front vector
	local pitchAngle = math.asin(lookDirection.Y)
	
	-- Build a baseline orientation facing the camera's horizontal direction
	local horizontalLook = CFrame.lookAt(rootPart.Position, rootPart.Position + Vector3.new(lookDirection.X, 0, lookDirection.Z))
	
	-- Apply the up/down pitch angle directly into the body rotation matrix
	local targetCFrame = horizontalLook * CFrame.Angles(pitchAngle, 0, 0)
	rootPart.CFrame = lerp(rootPart.CFrame, targetCFrame, 0.15)

	-- DYNAMIC FOV CALCULATION
	if moveDirection.Magnitude > 0 then
		local targetFOV = lerp(DEFAULT_FOV, MAX_FOV_BOOST, speedRatio)
		camera.FieldOfView = lerp(camera.FieldOfView, targetFOV, 0.1)
	else
		camera.FieldOfView = lerp(camera.FieldOfView, DEFAULT_FOV, 0.1)
	end

	if flightSound then
		if moveDirection.Magnitude > 0 then
			flightSound.Volume = lerp(flightSound.Volume, 0.4 + (speedRatio * 0.6), 0.1)
			flightSound.PlaybackSpeed = lerp(flightSound.PlaybackSpeed, 0.8 + (boostLevel * 0.2), 0.1)
		else
			flightSound.Volume = lerp(flightSound.Volume, 0.25, 0.1)
			flightSound.PlaybackSpeed = lerp(flightSound.PlaybackSpeed, 0.75, 0.1)
		end
	end
end

local function getMovementDirection()
	local dir = Vector3.zero
	
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + camera.CFrame.LookVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - camera.CFrame.LookVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - camera.CFrame.RightVector end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + camera.CFrame.RightVector end
	
	if isAscending then 
		dir = dir + Vector3.new(0, 1, 0) 
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then 
		dir = dir - Vector3.new(0, 1, 0) 
	end
	
	if dir.Magnitude > 0 then return dir.Unit end
	return Vector3.zero
end

function cycleBoost()
	boostLevel = boostLevel + 1
	if boostLevel > 4 then
		boostLevel = 0 
	end
end

function toggleFlight()
	isFlying = not isFlying
	
	if isFlying then
		humanoid.PlatformStand = true
		humanoid.AutoRotate = false 
		linearVelocity.Enabled = true
		if flightSound then flightSound:Play() end
	else
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true 
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		camera.FieldOfView = DEFAULT_FOV 
		linearVelocity.Enabled = false
		currentSpeed = 0
		boostLevel = 0
		isAscending = false
		if currentAnimTrack then
			currentAnimTrack:Stop(0.2)
			currentAnimTrack = nil
		end
		if flightSound then flightSound:Stop() end
	end
end

UserInputService.JumpRequest:Connect(function()
	if isFlying then
		isAscending = true
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == FLIGHT_TOGGLE_KEY then
		toggleFlight()
	elseif input.KeyCode == BOOST_CYCLE_KEY and isFlying then
		cycleBoost()
	elseif input.KeyCode == Enum.KeyCode.Space then
		isAscending = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Space then
		isAscending = false
	end
end)

RunService.RenderStepped:Connect(function()
	if not isFlying then return end
	
	local targetDir = getMovementDirection()
	local targetSpeed = 0
	
	if targetDir.Magnitude > 0 then
		targetSpeed = BOOST_SPEEDS[boostLevel]
	end
	
	currentSpeed = lerp(currentSpeed, targetSpeed, ACCELERATION)
	
	if targetDir.Magnitude > 0 then
		moveDirection = targetDir
	end
	
	linearVelocity.VectorVelocity = moveDirection * currentSpeed
	
	local speedRatio = currentSpeed / 500
	updateFlightState(speedRatio)
	
	if not UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		isAscending = false
	end
end)

player.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
	humanoid = character:WaitForChild("Humanoid")
	rootPart = character:WaitForChild("HumanoidRootPart")
	isFlying = false
	boostLevel = 0
	isAscending = false
	setupPhysics()
	createMobileUI()
end)
