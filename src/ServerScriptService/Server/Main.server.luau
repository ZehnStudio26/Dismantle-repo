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
require(script.Parent.Hook)        -- grappling hook: validates throws, broadcasts ropes (the client pulls)
require(script.Parent.Scaffolding) -- climbing towers: drops gangways of cleared layers
require(script.Parent.Brief)
require(script.Parent.Telemetry)
require(script.Parent.RunEnd) -- H-2: results, clear bonus, back to the lobby
require(script.Parent.Balance).Report(kaiju)
