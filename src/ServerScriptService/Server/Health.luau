--!strict
-- Health (B3 / LOOP-05, D4) and C-2 down handling: fixed max HP, no passive regeneration (see
-- StarterCharacterScripts.Health).
-- C-2 (Shayan 2026-09-29, the sheet's rule): health 0 during a run = you are DOWN and spectate your
-- teammates for the rest of the run (StarterGui.SpectateGui); there is no respawn while the run is on.
-- All players down = game over (RunState.State = "Failed"). A player leaving never ends the run while
-- someone is still up. When the run ends (Cleared or Failed) everyone who was down respawns.
-- The player attribute Down carries the state for the client. Respawns are held back by raising
-- Players.RespawnTime while the run is on (a player joining mid-run still spawns normally).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunConfig = require(ReplicatedStorage.Config.RunConfig)
local RunState = ReplicatedStorage:WaitForChild("RunState")

local NO_RESPAWN = 1e6 -- seconds; effectively never, until the run ends and we load characters ourselves
local normalRespawn = Players.RespawnTime

local function aliveCount(except: Player?): number
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		local hum = p ~= except and p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then n += 1 end
	end
	return n
end

local function checkWipe(why: string, except: Player?)
	if RunState:GetAttribute("State") == "Running" and aliveCount(except) == 0 then
		RunState:SetAttribute("State", "Failed")
		print(("[Dismantle] Run failed: no one left standing (D4, %s)"):format(why))
	end
end

local function onCharacter(player: Player, char: Model)
	player:SetAttribute("Down", nil)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	hum.MaxHealth = RunConfig.PlayerMaxHP
	hum.Health = RunConfig.PlayerMaxHP
	hum.Died:Connect(function()
		if RunState:GetAttribute("State") == "Running" then
			player:SetAttribute("Down", true)
			print(("[Health] %s is down: spectating for the rest of the run (%d teammate(s) still up)"):format(player.Name, aliveCount()))
		else
			print(("[Health] %s went down"):format(player.Name))
		end
		checkWipe(player.Name .. " went down")
	end)
end

-- respawns are held while the run is on; when it ends, bring back everyone who was down
local function syncRespawn()
	local running = RunState:GetAttribute("State") == "Running"
	Players.RespawnTime = if running then NO_RESPAWN else normalRespawn
	if running then return end
	for _, p in ipairs(Players:GetPlayers()) do
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if p:GetAttribute("Down") == true or not hum or hum.Health <= 0 then
			p:SetAttribute("Down", nil)
			task.spawn(function() p:LoadCharacter() end)
			print(("[Health] run over: %s respawns"):format(p.Name))
		end
	end
end
RunState:GetAttributeChangedSignal("State"):Connect(syncRespawn)
syncRespawn()

local function watch(player: Player)
	player.CharacterAdded:Connect(function(char) onCharacter(player, char) end)
	if player.Character then task.spawn(onCharacter, player, player.Character) end
end
Players.PlayerAdded:Connect(watch)
for _, player in ipairs(Players:GetPlayers()) do watch(player) end
-- the last player standing leaving is a wipe too (the ones left are all down)
Players.PlayerRemoving:Connect(function(player) checkWipe(player.Name .. " left", player) end)

return true
