-- Support drone (A10 / DRN-01..06, D6 / D7). Provisional numbers.
return {
	-- KJ-25 (2026-09-28): drones carry most of the late cutting on the 12-stud kaiju (10,720 blocks). A drone hit is
	-- DPS * Drone.Damage * HitInterval: 23 / 34.5 / 69 HP, which is 3 / 2 / 1 hits a block (a chunk is
	-- about 2.55 HP), capped by ChunksPerHitByTier. Was 2 (a visible helper, 2026-09-25).
	DPS = 20,                              -- 2026-10-01: 40 -> 20 (Ayesh: too strong vs the reference); tier-1 drone about 4 s a block
	ChunksPerHitByTier = { 9, 18, 27 },     -- indexed by the Drone.Damage tier; 9 = one face, 27 = the block
	                                       -- Count, damage and speed tiers live in UpgradeConfig.Drone (KJ-27).
	SearchRadius = 120,                    -- fallback search radius before a layer orbit exists (drones search the whole open layer)
	RetargetSeconds = 0.5,
	HitInterval = 0.25,                    -- discrete hits like the cutter; damage per hit = DPS * HitInterval
	MuzzleOffset = Vector3.new(0, -0.7, -0.8), -- beam origin on the body: the Recon Drone's camera gimbal, under the nose (-Z)
	-- Flight (Server.Drone: PATROL / APPROACH / CUT).
	Standoff = 8,                          -- studs the drone holds ABOVE the chunk it is cutting (off the block's open top;
	                                       -- an open side when the top is covered); the beam drops from there
	ApproachSpeed = 24,                    -- 2026-10-01: 40 -> 24 (too fast vs the reference). studs/s top flight speed: out to a block and every hop between blocks
	                                       -- (Drone.Speed multiplies it; separate from damage, as in the reference)
	ArriveEase = 8,                        -- per second: near the goal speed = ArriveEase x distance + MinSpeed, so
	MinSpeed = 6,                          -- the drone eases in instead of overshooting or crawling (research 2026-09-28)
	OnStationDistance = 1,                 -- studs from the hold point before damage starts at a new block (the beam is already on)
	-- Patrol (Shayan 2026-09-28: drones do not follow the player): with nothing to cut, circle the open
	-- layer like the reference's turrets orbit the mountain.
	OrbitSpeed = 10,                       -- studs/s around the orbit (x Drone.Speed); 2026-10-01: 15 -> 10
	OrbitMargin = 12,                      -- studs outside the layer's widest block
	PatrolSearchSeconds = 1.5,             -- a patrolling drone looks over the whole layer this often
	NextBlockRadius = 11,                  -- after finishing a block, take another within this distance without
	                                       -- dropping the beam, so a seam is cleared in one visit. 11 = a face or
	                                       -- diagonal neighbour of a 6-stud block; the drone hops there at
	                                       -- ApproachSpeed with the beam on
	ArriveDistance = 3,                    -- how close to the hover point before cutting starts
	ApproachTimeout = 8,                   -- seconds before an unreachable block is abandoned (escape hatch)
}