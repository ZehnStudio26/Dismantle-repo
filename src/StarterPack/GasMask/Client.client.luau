--!strict
-- GasMask client (TOOL-04 / T-4): while held, the camera goes first person (you look out through the
-- goggles, Shayan 2026-09-29) and the view narrows two ways, both by tier so an upgrade is visible on
-- screen: the camera FOV drops to the tier's value, and the goggle overlay shows. All of it restores
-- when the tool is put away, including the zoom you had: Roblox leaves the camera fully zoomed in
-- after LockFirstPerson -> Classic, so the old distance is forced back through CameraMinZoomDistance
-- for a couple of frames (the DevForum fix).
--
-- The overlay is StarterGui.MaskOverlay, authored in Studio (Shayan 2026-09-29): one full-screen
-- ImageLabel, Mask, the goggle art (rbxassetid://138611101429796), stretched so its frame always
-- reaches the screen edges. It draws under the HUD (DisplayOrder -1) so the hotbar stays readable.
-- Lv1 shows the whole frame; each higher tier scales the image up by ApertureByTier[t] /
-- ApertureByTier[1], pushing the frame out toward the edges, so the clearer view is the upgrade.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Mask = require(ReplicatedStorage.Config.ToolConfig).Mask

local tool = script.Parent :: Tool
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local function tier(): number
	local level = tonumber(player:GetAttribute("MaskLevel")) or Mask.StartingLevel
	return math.clamp(level, 1, #Mask.FOVByTier)
end

-- The overlay may not have replicated yet on the very first equip; find it lazily, never yield.
local function overlay(): ScreenGui?
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local g = pg and pg:FindFirstChild("MaskOverlay")
	return if g and g:IsA("ScreenGui") then g else nil
end

local function imageScale(t: number): number
	return (Mask.ApertureByTier[t] or 1) / (Mask.ApertureByTier[1] or 1)
end

-- first person while worn; savedZoom is the third-person distance to return to. The tool's own handle
-- would sit in front of the lens (the first-person fade does not cover it), so it is hidden on this
-- client only; everyone else still sees the mask in the hand.
local savedZoom: number? = nil
local hideConn: RBXScriptConnection? = nil
local function hideHandle(on: boolean)
	local handle = tool:FindFirstChild("Handle")
	if hideConn then hideConn:Disconnect(); hideConn = nil end
	if not (handle and handle:IsA("BasePart")) then return end
	if on then
		-- the camera's transparency controller rewrites the modifier each frame, so keep setting it
		hideConn = game:GetService("RunService").RenderStepped:Connect(function() handle.LocalTransparencyModifier = 1 end)
	else
		handle.LocalTransparencyModifier = 0
	end
end
local function enterFirstPerson()
	if player.CameraMode == Enum.CameraMode.LockFirstPerson then return end
	savedZoom = (camera.CFrame.Position - camera.Focus.Position).Magnitude
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	hideHandle(true)
end
local function leaveFirstPerson()
	hideHandle(false)
	if player.CameraMode ~= Enum.CameraMode.LockFirstPerson then return end
	player.CameraMode = Enum.CameraMode.Classic
	local minZoom = game:GetService("StarterPlayer").CameraMinZoomDistance
	local back = math.clamp(savedZoom or 12, math.max(minZoom, 4), player.CameraMaxZoomDistance)
	player.CameraMinZoomDistance = back
	task.delay(0.1, function() player.CameraMinZoomDistance = minZoom end)
	savedZoom = nil
end

local function apply()
	enterFirstPerson()
	local t = tier()
	camera.FieldOfView = Mask.FOVByTier[t]
	local gui = overlay()
	local img = gui and gui:FindFirstChild("Mask")
	local s = imageScale(t)
	if gui then
		gui.Enabled = true
		if img and img:IsA("ImageLabel") then
			local info = TweenInfo.new(Mask.ApertureTweenSeconds or 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(img, info, { Size = UDim2.fromScale(s, s) }):Play()
		end
	end
	print(("[Mask] worn (first person), Lv%d, FOV %d, goggle image x%.2f%s"):format(t, camera.FieldOfView, s,
		if not gui then " (no MaskOverlay in PlayerGui)" elseif not img then " (MaskOverlay has no Mask image)" else ""))
end

local function clear()
	camera.FieldOfView = Mask.DefaultFOV
	local gui = overlay()
	if gui then gui.Enabled = false end
	leaveFirstPerson()
end

tool.Equipped:Connect(apply)
tool.Unequipped:Connect(clear)
tool.Destroying:Connect(clear) -- dying with the mask on skips Unequipped; the next life starts in third person
player:GetAttributeChangedSignal("MaskLevel"):Connect(function()
	if tool.Parent == player.Character then apply() end
end)
