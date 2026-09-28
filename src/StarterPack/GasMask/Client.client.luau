--!strict
-- GasMask client: while held, the camera FOV narrows to the tier's value (TOOL-04: safety traded
-- against sight, so an upgrade is visible on screen). Restores the default FOV when put away.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Mask = require(ReplicatedStorage.Config.ToolConfig).Mask

local tool = script.Parent :: Tool
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local function tierFOV(): number
	local level = tonumber(player:GetAttribute("MaskLevel")) or Mask.StartingLevel
	return Mask.FOVByTier[math.clamp(level, 1, #Mask.FOVByTier)]
end

tool.Equipped:Connect(function()
	camera.FieldOfView = tierFOV()
	print(("[Mask] worn, Lv%s, FOV %d"):format(tostring(player:GetAttribute("MaskLevel")), camera.FieldOfView))
end)
tool.Unequipped:Connect(function()
	camera.FieldOfView = Mask.DefaultFOV
end)
player:GetAttributeChangedSignal("MaskLevel"):Connect(function()
	if tool.Parent == player.Character then camera.FieldOfView = tierFOV() end
end)
