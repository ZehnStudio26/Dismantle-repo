--!strict
-- Mask (A9 / TOOL-03 / TOOL-04): the GasMask is a held tool in slot 3, so wearing it means not
-- cutting or shooting (D5 exclusivity, measured by K7). The server only owns the tier: player
-- attribute MaskLevel, read by the tool's client script for FOV and by the shop later (B11).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ToolConfig = require(ReplicatedStorage.Config.ToolConfig)

local function setup(player: Player)
	if player:GetAttribute("MaskLevel") == nil then
		player:SetAttribute("MaskLevel", ToolConfig.Mask.StartingLevel)
		print(("[Mask] %s starts with a Lv%d mask"):format(player.Name, ToolConfig.Mask.StartingLevel))
	end
end

Players.PlayerAdded:Connect(setup)
for _, p in ipairs(Players:GetPlayers()) do setup(p) end

return true
