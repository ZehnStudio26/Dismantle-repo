-- Support drone (A10 / DRN-01..06, D6 / D7). Provisional numbers.
return {
	StartingLevel = 1,                     -- everyone gets a drone at run start until the shop decides otherwise
	DPS = 20,                              -- vs cutter 150: an assistant, not a replacement
	LevelMult = { 1, 1.65, 2.7, 4.5, 7.4 },-- DRN-07 axis (deferred), indexed by player attribute DroneLevel
	Range = 60,                            -- studs from drone to block centre before it can cut
	SearchRadius = 120,                    -- looks for blocks this far from its owner
	RetargetSeconds = 0.5,
	HitInterval = 0.25,                    -- discrete hits like the cutter; damage per hit = DPS * HitInterval
	HoverOffset = Vector3.new(6, 9, -4),   -- relative to the owner's facing
	HoverLerp = 4,                         -- per second, higher = snappier follow
	-- N4 / DRN-05 / DRN-06: drone share of broken blocks, Drone / (Drone + Player), must stay
	-- under MaxShare. Enforce = pause the drone while over it (Q07 provisional: enforce + log).
	MaxShare = 0.4,
	EnforceShareCap = true,
}
