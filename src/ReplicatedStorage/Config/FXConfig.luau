-- Client-side hit feel (Cutting Polish Plan section 5). All visual, nothing here is authoritative.
return {
	-- whole-block punch: pop in -> overshoot out -> settle, scale factor and seconds, applied to every
	-- chunk of the hit block about the block centre from a snapshot (no drift). The in-phase must span 3-4 frames to read.
	Pop = { In = { 0.90, 0.07 }, Out = { 1.04, 0.09 }, Settle = { 1.00, 0.06 } }, -- 220 ms; a re-hit restarts it from the base
	-- "+$N" popup on block completion (reference: reward shown on completion only, never per hit)
	Popup = { Rise = 6, Lifetime = 1.1, MaxDistance = 250, MineColor = Color3.fromRGB(255, 220, 90), OtherColor = Color3.fromRGB(200, 200, 210) },
	-- hit flash on the aimed block's outline (local player's own hits)
	Flash = { Fill = 0.7, Seconds = 0.12 },
	Debris = {
		PerCell = 1,      -- shards per broken chunk
		MaxPerHit = 4,    -- a Skin hit removes ~7 chunks; cap the shards it throws
		Scale = 0.35,     -- shard size as a fraction of the cell
		Speed = 7,        -- studs/s outward: low, so pieces fall rather than fly
		Spin = 8,
		Lifetime = 1.2,
		FadeAt = 0.7,     -- fraction of lifetime before the fade starts
		MaxLive = 60,     -- pooled, oldest recycled first
	},
	Dust = { PerHit = 10, PerBlock = 40, Lifetime = 0.6 },
	-- Block health bar (StarterGui.BlockHealth, driven by StarterPlayerScripts.BlockHealth): shown over any
	-- block being cut, by any player or drone. Timings are the mining pack's HealthBar settings.
	BlockHealth = {
		Gap = 1.5,                 -- studs above the block's top face
		ShowSeconds = 3.5,         -- stays up this long after the last hit
		BrokenShowSeconds = 0.6,   -- after the block breaks
		FillSeconds = 0.25,        -- green fill catches up
		TrailDelay = 0.15, TrailSeconds = 0.9, -- red trail drains behind it
		FlashSeconds = 0.3,        -- white flash on each hit
		FadeSeconds = 0.35,
		MaxBars = 12,              -- oldest bar goes first past this (many drones)
	},

	-- Chainsaw hit feel (Chainsaw Cutting Plan step 3), the local player's own hits only; numbers are the
	-- mining pack's. The block pop, dust and shards come from BlockFX like every other hit.
	Chainsaw = {
		Flash = { Color = Color3.new(1, 1, 1), Fill = 0.55, Seconds = 0.35 },                  -- outline surface fill on a hit
		CritFlash = { Color = Color3.fromRGB(255, 55, 55), Fill = 0.35, Seconds = 0.35 },
		Screen = { Hit = { Transparency = 0.82, Seconds = 0.35 }, Crit = { Transparency = 0.5, Seconds = 0.6 } }, -- white full-screen flash
		Dip = { Hit = -5, Crit = -10, Stiffness = 180, DampingRatio = 0.7 },                      -- Humanoid.CameraOffset spring impulse
		Shake = { Hit = { Degrees = 0.3, Seconds = 0.2 }, Crit = { Degrees = 0.55, Seconds = 0.32 } }, -- camera rotation noise, decaying
		CritText = { Rise = 0.8, InSeconds = 0.2, HoldSeconds = 0.45, OutSeconds = 0.35 },       -- StarterGui.ChainsawFX.CritText billboard
	},
}
