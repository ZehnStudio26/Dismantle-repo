--!strict
-- Server bootstrap. Order matters: event blocks are seeded before Demolition owns the kaiju,
-- and Demolition owns the kaiju before any tool can touch it.
local Demolition = require(script.Parent.Demolition)
local EventBlocks = require(script.Parent.EventBlocks)

local kaiju = workspace:WaitForChild("Kaiju")
assert(kaiju:IsA("Model"), "Workspace.Kaiju must be a Model of block Parts")
EventBlocks.Seed(kaiju)
Demolition.Init(kaiju)

require(script.Parent.BlockFX)
require(script.Parent.Upgrades) -- tiers on the player before any tool reads them
require(script.Parent.Profile) -- R-3: saved Cash, upgrade tiers and medkits (shared with the lobby)
require(script.Parent.Chainsaw)
require(script.Parent.Gun)
require(script.Parent.Health)
require(script.Parent.EventRoll)
require(script.Parent.Enemies) -- the one loop that ticks larvae; Larvae builds bodies into it
require(script.Parent.Egg)     -- tag "Egg": placed eggs incubate and hatch (Larvae, TagBinder come with it)
require(script.Parent.UFO)     -- tag "UFO": hovering saucers drop larvae
require(script.Parent.Survivor) -- tag "Survivor": rolled survivors wait for a rescue
require(script.Parent.HealthItem) -- E-4: rolled Health outcomes leave a green cross to pick up
require(script.Parent.Medkit)     -- R-4: use a lobby-bought medkit (H)
require(script.Parent.Gas)
require(script.Parent.Mask)
require(script.Parent.Drone)
require(script.Parent.Scaffolding) -- climbing towers: drops gangways of cleared layers
require(script.Parent.Brief)
require(script.Parent.Telemetry)
require(script.Parent.RunEnd) -- H-2: results, clear bonus, back to the lobby
require(script.Parent.Balance).Report(kaiju)

Demolition.Cleared.Event:Connect(function()
	-- the result screen, clear bonus and lobby return live in Server.RunEnd (H-2)
	print("[Dismantle] Kaiju cleared. Contribution:", Demolition.GetContribution())
end)

print(("[Dismantle] Run started. %d blocks."):format(game.ReplicatedStorage.RunState:GetAttribute("TotalBlocks")))

-- one status line every 30 s while the run is on (replaces the old per-block / per-swing logs)
local UpgradeConfig = require(game.ReplicatedStorage.Config.UpgradeConfig)
local RunState = game.ReplicatedStorage.RunState
task.spawn(function()
	while task.wait(30) do
		if RunState:GetAttribute("State") ~= "Running" or #game:GetService("Players"):GetPlayers() == 0 then continue end
		local who = {}
		for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			table.insert(who, ("%s $%d %s, %d drone(s)"):format(p.Name, tonumber(p:GetAttribute("Cash")) or 0,
				if p:GetAttribute("Down") == true then "DOWN" else ("%.0f HP"):format(hum and hum.Health or 0),
				UpgradeConfig.Value(p, "Drone", "Count")))
		end
		print(("[Run] %.1f%% demolished, layer %s open, %s block(s) left | %s"):format(tonumber(RunState:GetAttribute("DemolitionPercent")) or 0,
			tostring(RunState:GetAttribute("ActiveLayer")), tostring(RunState:GetAttribute("RemainingBlocks")), table.concat(who, "; ")))
	end
end)
