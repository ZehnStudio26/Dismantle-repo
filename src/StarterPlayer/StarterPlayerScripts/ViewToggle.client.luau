--!strict
-- ViewToggle (U-2 / KJ-52): the VIEW rail button or the V key flips between the normal third-person
-- camera and a TOP-DOWN map view like the reference's (Shayan 2026-09-29): high above, looking down,
-- set a little to the right, in the heading you had when you switched. The map view does NOT follow
-- the player: it opens centred on you and you pan it yourself, the mouse wheel moving it forward /
-- back on screen and a right-button drag moving it any way, kept within Margin studs of the kaiju.
-- Only V / VIEW brings the camera back to your character, placed behind you (ReturnBack / ReturnUp), and the
-- next top view re-centres on you.
-- You keep walking and cutting meanwhile: the chainsaw's cursor selection raycasts from the active
-- camera. Bound at the Camera render priority, before the chainsaw's camera step (+1), so hit shake
-- still plays. Numbers: RunConfig.TopView. Player attribute TopView carries the mode.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage.Config.RunConfig).TopView
local player = Players.LocalPlayer
local kaiju = workspace:WaitForChild("Kaiju") :: Model

local top = false
local heading = CFrame.new()          -- yaw-only frame captured when the map view opens
local focus = Vector3.zero            -- the ground point the camera looks at; panned by the player
local camPos: Vector3? = nil
local dragging = false
local boundsLo, boundsHi = Vector3.zero, Vector3.zero

local function rootPart(): BasePart?
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function clampFocus()
	focus = Vector3.new(math.clamp(focus.X, boundsLo.X, boundsHi.X), focus.Y, math.clamp(focus.Z, boundsLo.Z, boundsHi.Z))
end

-- move the focus by screen directions: right / forward in the view's heading
local function pan(right: number, forward: number)
	focus += heading.RightVector * right + heading.LookVector * forward
	clampFocus()
end

local function step(dt: number)
	local cam = workspace.CurrentCamera
	if not cam then return end
	if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
	local goal = focus + heading:VectorToWorldSpace(Vector3.new(Cfg.Right, Cfg.Height, Cfg.Back))
	camPos = if camPos then camPos:Lerp(goal, 1 - math.exp(-Cfg.Sharpness * dt)) else goal
	cam.CFrame = CFrame.lookAt(camPos :: Vector3, (camPos :: Vector3) - heading:VectorToWorldSpace(Vector3.new(Cfg.Right, Cfg.Height, Cfg.Back)))
end

local function setTop(on: boolean)
	top = on
	dragging = false
	local cam = workspace.CurrentCamera
	if on then
		local look = cam.CFrame.LookVector * Vector3.new(1, 0, 1)
		heading = CFrame.lookAt(Vector3.zero, if look.Magnitude > 0.05 then look.Unit else -Vector3.zAxis)
		local cf, size = kaiju:GetBoundingBox()
		local half = Vector3.new(size.X / 2 + Cfg.Margin, 0, size.Z / 2 + Cfg.Margin)
		boundsLo, boundsHi = cf.Position - half, cf.Position + half
		local root = rootPart()
		focus = if root then root.Position else cf.Position
		clampFocus()
		camPos = cam.CFrame.Position
		RunService:BindToRenderStep("TopView", Enum.RenderPriority.Camera.Value, step)
	else
		RunService:UnbindFromRenderStep("TopView")
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		camPos = nil
		-- back behind the player: the default camera takes its rotation from the current CFrame, so place it
		-- behind and a little above the character first, then hand control back
		local root = rootPart()
		if root then
			local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
			look = if look.Magnitude > 0.05 then look.Unit else -Vector3.zAxis
			cam.CFrame = CFrame.lookAt(root.Position - look * Cfg.ReturnBack + Vector3.yAxis * Cfg.ReturnUp, root.Position + Vector3.yAxis * 1.5)
		end
		cam.CameraType = Enum.CameraType.Custom
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then cam.CameraSubject = hum end
	end
	player:SetAttribute("TopView", on)
	print(("[View] %s"):format(if on then "top-down map view (wheel pans forward / back, right-drag pans; V or VIEW to return)" else "back to your character (third-person view)"))
end

local gui = player:WaitForChild("PlayerGui"):WaitForChild("Upgrades")
local button = (gui:WaitForChild("Rail") :: Frame):WaitForChild("Entry_ViewButton"):WaitForChild("ViewButton") :: TextButton
button.MouseButton1Click:Connect(function() setTop(not top) end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.V then setTop(not top) end
	if top and input.UserInputType == Enum.UserInputType.MouseButton2 then dragging = true end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then dragging = false end
end)
UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if not top then return end
	if input.UserInputType == Enum.UserInputType.MouseWheel and not gameProcessed then
		pan(0, input.Position.Z * Cfg.PanStep) -- wheel up moves the view forward (up the screen)
	elseif input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
		pan(-input.Delta.X * Cfg.DragSpeed, input.Delta.Y * Cfg.DragSpeed) -- grab-and-pull, like a map
	elseif input.UserInputType == Enum.UserInputType.Touch and not gameProcessed then
		-- phones / tablets: a one-finger drag on open screen pans the same way (touches that start on the
		-- thumbstick or a button are gameProcessed: they move the character or press the button)
		pan(-input.Delta.X * Cfg.DragSpeed, input.Delta.Y * Cfg.DragSpeed)
	end
end)

-- going down leaves top view, so spectating (StarterGui.SpectateGui) can take the camera
local function watchDeath(char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if hum then hum.Died:Connect(function() if top then setTop(false) end end) end
end
player.CharacterAdded:Connect(watchDeath)
if player.Character then task.spawn(watchDeath, player.Character) end

player:SetAttribute("TopView", false)
player:SetAttribute("FirstPerson", false) -- the old first-person mode is gone; Stores still reads the flag
