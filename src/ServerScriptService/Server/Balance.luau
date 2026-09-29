--!strict
-- Balance (A16 / REL-04, KJ-25): a start-of-run estimate that turns the config numbers into minutes, so
-- retuning is a config edit plus one look at the output. It simulates a whole run for a solo player and
-- a full party (RunConfig.MaxPartySize): every player cuts with the chainsaw and their drones, earns
-- CashPerBlock per block and buys the cheapest affordable cutting upgrade as soon as they can. The
-- target (RunConfig.TargetRunMinutes) is a FULL-PARTY run; OverheadShare of it is reserved for
-- movement, events and layer changes. Counts hidden blocks too (Large Voxel Kaiju).
-- The same model lives in the KJ-25 notes (Progress/modules/Dismantle - Chainsaw Cutting Plan.md).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunConfig = require(ReplicatedStorage.Config.RunConfig)
local KaijuConfig = require(ReplicatedStorage.Config.KaijuConfig)
local ToolConfig = require(ReplicatedStorage.Config.ToolConfig)
local DroneConfig = require(ReplicatedStorage.Config.DroneConfig)
local UpgradeConfig = require(ReplicatedStorage.Config.UpgradeConfig)

-- ponytail: drone flight between blocks is a flat 0.25 s per block: a hop to a neighbour at
-- DroneConfig.ApproachSpeed with the ease-out reaches station in about 0.25 s (2026-09-28). Measure it
-- in a playtest (the drone's "finished a block" lines) and put the real number here if it drifts.
local DRONE_TRAVEL = 0.32 -- 2026-09-29: ApproachSpeed 40
-- the upgrades that change cutting speed; Range, AutoCut and the gun also cost cash but are left out
local SHOP = { { "Player", "Damage" }, { "Player", "Speed" }, { "Drone", "Count" }, { "Drone", "Damage" }, { "Drone", "Speed" } }

local Balance = {}

local function value(tiers: { [string]: number }, line: string, stat: string): number
	return UpgradeConfig.Ladders[line][stat].Values[tiers[line .. stat]]
end

-- blocks per second one player breaks at the given tiers: chainsaw (area splash included) + drones
local function rate(tiers: { [string]: number }, chunkHP: number, cells: number): (number, number)
	local cs = ToolConfig.Chainsaw
	local dmgTier = tiers.PlayerDamage
	local hitsPerSecond = 2 * value(tiers, "Player", "Speed") / (cs.SwingSeconds.Slash1 + cs.ComboGap + cs.SwingSeconds.Slash2 + cs.FinishCooldown)
	local damage = cs.DamagePerHit * value(tiers, "Player", "Damage")
	local cap = cs.ChunksPerHitByTier[math.min(dmgTier, #cs.ChunksPerHitByTier)]
	local c, m = cs.CritChance, cs.CritMultiplier
	local chunksPerHit = (1 - c) * math.min(cap, damage / chunkHP) + c * math.min(cap * m, damage * m / chunkHP)
	local area = if cs.AreaByTier then cs.AreaByTier[math.min(dmgTier, #cs.AreaByTier)] else 1
	local saw = hitsPerSecond * area * chunksPerHit / cells

	local dCaps = DroneConfig.ChunksPerHitByTier or { 3 }
	local dCap = dCaps[math.min(tiers.DroneDamage, #dCaps)]
	local perHit = math.min(dCap, DroneConfig.DPS * value(tiers, "Drone", "Damage") * DroneConfig.HitInterval / chunkHP)
	local secondsPerBlock = math.ceil(cells / perHit) * DroneConfig.HitInterval + DRONE_TRAVEL / value(tiers, "Drone", "Speed")
	local drones = value(tiers, "Drone", "Count") / secondsPerBlock
	return saw, drones
end

local function simulate(blocks: number, chunkHP: number, cells: number, party: number): (number, number, number, string)
	local tiers: { [string]: number } = {}
	for _, s in ipairs(SHOP) do tiers[s[1] .. s[2]] = 1 end
	local t, left, cash, bought = 0, blocks, 0, {}
	local dt = 0.5
	while left > 0 and t < 6 * 3600 do
		local saw, drones = rate(tiers, chunkHP, cells)
		local got = math.min(left, (saw + drones) * party * dt)
		left -= got
		local pay = RunConfig.CashPerBlock
		cash += got / party * ((saw * (pay.Player or 0) + drones * (pay.Drone or 0)) / math.max(saw + drones, 1e-9))
		t += dt
		local best, bestCost = nil, math.huge
		for _, s in ipairs(SHOP) do
			local key = s[1] .. s[2]
			local cost = UpgradeConfig.Ladders[s[1]][s[2]].Costs[tiers[key]]
			local open = UpgradeConfig.Unlocked(s[1], s[2], function(l, st) return tiers[l .. st] or 1 end)
			if open and cost and cash >= cost and cost < bestCost then best, bestCost = key, cost end
		end
		if best then
			cash -= bestCost
			tiers[best] += 1
			table.insert(bought, ("%s %d at %.1f min"):format(best, tiers[best], t / 60))
		end
	end
	local saw, drones = rate(tiers, chunkHP, cells)
	return t / 60 / (1 - RunConfig.OverheadShare), saw, drones, table.concat(bought, ", ")
end

function Balance.Report(kaiju: Model): { [string]: number }
	local totalHP, blocks = 0, 0
	local function count(container: Instance?)
		if not container then return end
		for _, b in ipairs(container:GetChildren()) do
			if (b:IsA("Model") or b:IsA("BasePart")) and b:GetAttribute("BlockMaterial") ~= nil and b:GetAttribute("Demolishable") ~= false then
				local mat = b:GetAttribute("BlockMaterial")
				totalHP += (typeof(mat) == "string" and KaijuConfig.BlockHP[mat]) or KaijuConfig.BlockHP.Default
				blocks += 1
			end
		end
	end
	count(kaiju)
	count(ServerStorage:FindFirstChild("KaijuHidden"))
	if blocks == 0 then return { blocks = 0, totalHP = 0, soloMinutes = 0, partyMinutes = 0 } end
	local cells = KaijuConfig.Cells.Grid ^ 3
	local chunkHP = totalHP / blocks / cells
	local party = RunConfig.MaxPartySize
	local solo, saw, drones = simulate(blocks, chunkHP, cells, 1)
	local full, _, _, bought = simulate(blocks, chunkHP, cells, party)
	print(("[Balance] %d blocks, %d total HP (%.2f HP a chunk). Simulated run: solo %.1f min, %d players %.1f min, against a %d min target for %d players (%d%% of it for walking and events). Fully upgraded, one player breaks %.2f blocks/s with the chainsaw and %.2f with drones."):format(
		blocks, totalHP, chunkHP, solo, party, full, RunConfig.TargetRunMinutes, party, RunConfig.OverheadShare * 100, saw, drones))
	print("[Balance] upgrade order in the party run: " .. bought)
	local target = RunConfig.TargetRunMinutes
	if full > target * 1.15 then
		warn(("[Balance] the %d-player run is %.1f min, %.0f%% over the %d min target: raise automation or area damage, or cut blocks (KJ-25)"):format(party, full, (full / target - 1) * 100, target))
	elseif full < target * 0.7 then
		warn(("[Balance] the %d-player run is %.1f min, under 70%% of the %d min target: the run may feel too short"):format(party, full, target))
	end
	return { blocks = blocks, totalHP = totalHP, soloMinutes = solo, partyMinutes = full }
end

return Balance
