--!strict
-- Health (B3 / LOOP-05, D4): fixed max HP, no passive regeneration (see StarterCharacterScripts.Health),
-- zero HP ends the run. Q09 (co-op death handling) is open, so until then the run fails when
-- nobody is left alive; a lone player's death therefore ends a solo run.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunConfig = require(ReplicatedStorage.Config.RunConfig)
local RunState = ReplicatedStorage:WaitForChild("RunState")

local function anyoneAlive(): boolean
	for _, p in ipairs(Players:GetPlayers()) do
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then return true end
	end
	return false
end

local function onCharacter(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	hum.MaxHealth = RunConfig.PlayerMaxHP
	hum.Health = RunConfig.PlayerMaxHP
	hum.Died:Connect(function()
		print(("[Health] %s went down"):format(player.Name))
		if RunState:GetAttribute("State") == "Running" and not anyoneAlive() then
			RunState:SetAttribute("State", "Failed")
			print("[Dismantle] Run failed: no one left standing (D4)")
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char) onCharacter(player, char) end)
	if player.Character then onCharacter(player, player.Character) end
end)
for _, player in ipairs(Players:GetPlayers()) do
	player.CharacterAdded:Connect(function(char) onCharacter(player, char) end)
	if player.Character then onCharacter(player, player.Character) end
end

return true
