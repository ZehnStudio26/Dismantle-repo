--!strict
-- Mask (A9 / TOOL-03 / TOOL-04): the GasMask is WORN, not held (Ayesh 2026-10-01: masked players must
-- still cut and shoot). Slot 3 / Remotes.Mask toggles it; the GasMask tool stays in the backpack as the
-- "you own a mask" marker and is never equipped. The server owns two player attributes:
--   MaskLevel  the tier. Read by the tool's client script for FOV and the overlay, and by the shop later (B11).
--   Masked     true while worn. Gas, HUD, GasOverlay and Telemetry read THIS, never the character.
-- Worn, a copy of the tool's Handle sits on the face (WornMask, welded to the Head) so teammates see it.
-- A new life starts unmasked.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ToolConfig = require(ReplicatedStorage.Config.ToolConfig)

local FACE = CFrame.new(0, -0.1, -0.6) -- on the Head: over the mouth and nose, front is -Z

local function setWorn(player: Player, on: boolean)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	local old = char and char:FindFirstChild("WornMask")
	if old then old:Destroy() end
	if on and head and head:IsA("BasePart") then
		local tool = player.Backpack:FindFirstChild("GasMask") or char:FindFirstChild("GasMask")
		local handle = tool and tool:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			local worn = handle:Clone()
			worn.Name = "WornMask"
			worn.CanCollide, worn.CanQuery, worn.CanTouch, worn.Massless = false, false, false, true
			worn.CFrame = head.CFrame * FACE
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = head, worn
			weld.Parent = worn
			worn.Parent = char
		end
	end
	player:SetAttribute("Masked", on)
end

local function owns(player: Player): boolean
	local char = player.Character
	return player.Backpack:FindFirstChild("GasMask") ~= nil or (char ~= nil and char:FindFirstChild("GasMask") ~= nil)
end

ReplicatedStorage.Remotes.Mask.OnServerEvent:Connect(function(player: Player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or not owns(player) then return end
	setWorn(player, player:GetAttribute("Masked") ~= true)
end)

local function setup(player: Player)
	if player:GetAttribute("MaskLevel") == nil then
		player:SetAttribute("MaskLevel", ToolConfig.Mask.StartingLevel)
	end
	player:SetAttribute("Masked", false)
	player.CharacterAdded:Connect(function() player:SetAttribute("Masked", false) end)
end

Players.PlayerAdded:Connect(setup)
for _, p in ipairs(Players:GetPlayers()) do setup(p) end

return true
