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
-- require(script.Parent.Scaffold) -- off since 2026-09-28 (Shayan: no ladders on the blocks; Q25 closed). Module kept for reference.
require(script.Parent.Upgrades) -- tiers on the player before any tool reads them
-- require(script.Parent.Cutter) -- laser cutter retired 2026-09-28 (Bee); tool parked in ServerStorage.Reference
require(script.Parent.Chainsaw)
require(script.Parent.Gun)
require(script.Parent.Health)
require(script.Parent.EventRoll)
require(script.Parent.Enemies) -- the one loop that ticks larvae; Larvae builds bodies into it
require(script.Parent.Egg)     -- tag "Egg": placed eggs incubate and hatch (Larvae, TagBinder come with it)
require(script.Parent.UFO)     -- tag "UFO": hovering saucers drop larvae
require(script.Parent.Survivor) -- tag "Survivor": rolled survivors wait for a rescue
require(script.Parent.Gas)
require(script.Parent.Mask)
require(script.Parent.TestArea) -- Studio only: standing gas cloud and larvae on the TestArea pads
require(script.Parent.Drone)
require(script.Parent.Brief)
require(script.Parent.Telemetry)
require(script.Parent.Balance).Report(kaiju)

Demolition.Cleared.Event:Connect(function()
	-- LOOP-03 / LOOP-04 (result screen, payout, lobby return) are open: Q06.
	print("[Dismantle] Kaiju cleared. Contribution:", Demolition.GetContribution())
end)

print(("[Dismantle] Run started. %d blocks."):format(game.ReplicatedStorage.RunState:GetAttribute("TotalBlocks")))
