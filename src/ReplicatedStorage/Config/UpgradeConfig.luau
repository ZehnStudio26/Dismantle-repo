--!strict
-- Upgrades (U-3 / U-4, KJ-27 / KJ-65): three lines, three stats each, three tiers per stat. Tier 1
-- is the baseline every player starts at; the sheet's gun row (4-3-2 shots, 2-3-4 per s, 20-30-40
-- studs) is the model for the rest. Values are exactly what the consumer reads. Costs[n] is the
-- coins to go from tier n to n+1. Q04 (economy) is open, so costs are provisional and sized to
-- today's income of $1 per block and $25 per survivor.
-- KJ-25 (2026-09-28, 12-stud kaiju of 10,720 blocks): a 4-player run pays each player about 2,700,
-- so the cutting stats cost 30 / 120 (drones 50 / 160, drone damage 40 / 140) and the tree fills over
-- the first third of the run. Server.Balance simulates the purchases and prints the minutes.
--
-- Names (optional) replaces the number in the tree's tooltip, for on / off upgrades.
--
-- Tiers live on the player as attributes "Upg_<Line>_<Stat>" = 1..3, written only by
-- Server.Upgrades. Consumers on either side read them through Tier / Value below.
-- Session-only until R-3 persistence is wired (Ayesh, 2026-09-25).

local UpgradeConfig = {}

UpgradeConfig.Lines = { "Player", "Drone", "Gun" } -- display order, left to right
UpgradeConfig.Stats = {
	Player = { "Damage", "Speed", "Range", "AutoCut" },
	Drone  = { "Count", "Damage", "Speed" },
	Gun    = { "Damage", "FireRate", "Range" },
}

-- Desc is the one-line tooltip text on the skill tree (reference: "20% chance a turret hit also
-- damages the block behind."). Keep it to one sentence.
UpgradeConfig.Ladders = {
	Player = {
		Damage   = { Label = "Cut damage",  Values = { 1, 1.4, 1.9 },       Costs = { 30, 120 }, Unit = "x",      Desc = "Every swing cuts harder and cuts the blocks around it too." }, -- multiplies DamagePerHit, picks ChunksPerHitByTier and ToolConfig.Chainsaw.AreaByTier
		Speed    = { Label = "Swing speed", Values = { 1, 1.25, 1.5 },      Costs = { 30, 120 }, Unit = "x",      Desc = "Faster swings and shorter rests between them." }, -- multiplies chainsaw swing playback, divides its waits
		Range    = { Label = "Cut reach",   Values = { 1, 2, 3 },           Costs = { 30, 100 }, Unit = " blocks", Desc = "Reach blocks further from where you stand." }, -- 2026-09-28: the block next to you to start (Shayan); Bee had said two
		AutoCut  = { Label = "Auto cut",    Values = { 0, 1 }, Names = { "OFF", "ON" }, Costs = { 100 }, Unit = "", Desc = "Hold the mouse to keep cutting, no more clicking." }, -- Bee 2026-09-28: auto-digging is an upgrade (reference: Auto Mine)
	},
	Drone = {
		Count    = { Label = "Drones",      Values = { 1, 2, 4 },           Costs = { 50, 160 }, Unit = "",       Desc = "More drones cutting for you." }, -- KJ-25: drones carry most of the cutting late in the run
		Damage   = { Label = "Drone damage",Values = { 1, 1.5, 3 },         Costs = { 40, 140 }, Unit = "x",      Desc = "Your drones cut harder." },                      -- multiplier on DroneConfig.DPS; picks DroneConfig.ChunksPerHitByTier (3 / 2 / 1 hits a block)
		Speed    = { Label = "Drone speed", Values = { 1, 1.25, 1.5 },      Costs = { 30, 120 }, Unit = "x",      Desc = "Your drones fly and track faster." },            -- multiplier on the three flight speeds
	},
	Gun = {
		Damage   = { Label = "Gun damage",  Values = { 10, 14, 20 },        Costs = { 25, 75 }, Unit = "",        Desc = "Fewer shots to put a larva down." },              -- 4 / 3 / 2 shots on a 40 HP larva
		FireRate = { Label = "Fire rate",   Values = { 2, 3, 4 },           Costs = { 25, 75 }, Unit = "/s",      Desc = "More shots per second." },
		Range    = { Label = "Gun range",   Values = { 20, 30, 40 },        Costs = { 25, 75 }, Unit = " studs",  Desc = "Shoot larvae from further away." },
	},
}

function UpgradeConfig.Attribute(line: string, stat: string): string
	return ("Upg_%s_%s"):format(line, stat)
end

function UpgradeConfig.Ladder(line: string, stat: string)
	local l = UpgradeConfig.Ladders[line]
	return if l then l[stat] else nil
end

-- current tier of a stat for a player, 1..#Values (1 when never set)
function UpgradeConfig.Tier(player: Player, line: string, stat: string): number
	local ladder = UpgradeConfig.Ladder(line, stat)
	local max = if ladder then #ladder.Values else 1
	return math.clamp(tonumber(player:GetAttribute(UpgradeConfig.Attribute(line, stat))) or 1, 1, max)
end

-- the value the consumer should use right now
function UpgradeConfig.Value(player: Player, line: string, stat: string): number
	local ladder = UpgradeConfig.Ladder(line, stat)
	assert(ladder, "unknown upgrade " .. line .. "." .. stat)
	return ladder.Values[UpgradeConfig.Tier(player, line, stat)]
end

return UpgradeConfig
