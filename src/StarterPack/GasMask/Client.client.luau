--!strict
-- GasMask client (TOOL-04 / T-4): while the mask is WORN (player attribute Masked, owned by Server.Mask;
-- worn since 2026-10-01 so the chainsaw and gun stay usable) the view narrows two ways, both by tier so an
-- upgrade is visible on screen: the camera FOV drops to the tier's value, and the goggle overlay shows.
-- The FOV is left alone in the top-down map view (it would only zoom the map). This script lives in the
-- tool, which stays in the backpack as the "you own a mask" marker; the camera itself is ViewToggle's.
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

-- The overlay may not have replicated yet on the very first wear; find it lazily, never yield.
local function overlay(): ScreenGui?
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local g = pg and pg:FindFirstChild("MaskOverlay")
	return if g and g:IsA("ScreenGui") then g else nil
end

local function imageScale(t: number): number
	return (Mask.ApertureByTier[t] or 1) / (Mask.ApertureByTier[1] or 1)
end

local function apply()
	local t = tier()
	camera.FieldOfView = if player:GetAttribute("TopView") == true then Mask.DefaultFOV else Mask.FOVByTier[t]
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
end

local function clear()
	camera.FieldOfView = Mask.DefaultFOV
	local gui = overlay()
	if gui then gui.Enabled = false end
end

local function refresh()
	if player:GetAttribute("Masked") == true then apply() else clear() end
end

local conns = {
	player:GetAttributeChangedSignal("Masked"):Connect(refresh),
	player:GetAttributeChangedSignal("MaskLevel"):Connect(refresh),
	player:GetAttributeChangedSignal("TopView"):Connect(refresh),
}
tool.Destroying:Connect(function() -- a new life brings a new tool (and starts unmasked)
	for _, c in ipairs(conns) do c:Disconnect() end
	clear()
end)
refresh()
