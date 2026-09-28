-- Random events. Provisional; EVT-20 / N5 settle frequency.
return {
	-- EVT-01: at run start this many Flesh blocks are retagged "Event" (Q22). Their outcome is
	-- decided by the roll policy when they break (EVT-02). A16: 35 -> 24.
	Seed = { EventCount = 24, RandomSeed = 0 }, -- RandomSeed 0 = different every run
	Colors = { Event = Color3.fromRGB(190, 90, 200), Egg = Color3.fromRGB(235, 220, 150), Organ = Color3.fromRGB(150, 60, 160) },
	-- 6.6 roll policy (A12 / EVT-15..17)
	Roll = {
		Weights = { Gas = 2, Egg = 2, Survivor = 1, Health = 1 }, -- a third of rolls are positive (drawing p.2, Q11 / Q28); N5 settles the mix
		NoImmediateRepeat = true,          -- EVT-15
		SingleEventBelowPercent = 30,      -- EVT-16: below this demolition %, a new event is suppressed while one is active
		LarvaePerParty = { 1, 1, 2, 2 },   -- EVT-17: more enemies at 4 players, never 4x the events
	},
	-- EVT-03 / 05: gas bursts. Players inside without the mask held lose HP.
	Gas  = { DPS = 5, Radius = 60, Duration = 8, TickSeconds = 0.25 },
	-- Positive outcomes (drawing p.2): a survivor to rescue for Cash, a health cross. Placeholder Parts until M2 models.
	-- Collected by walking within Radius; unreached pickups vanish after Lifetime seconds.
	Pickups = {
		TickSeconds = 0.2, Radius = 6,
		Survivor = { Cash = 25, Lifetime = 90, Size = Vector3.new(2, 5, 2), Color = Color3.fromRGB(255, 200, 80) },
		Health   = { Heal = 30, Lifetime = 60, Size = Vector3.new(3, 3, 1), Color = Color3.fromRGB(240, 60, 60) },
	},
	Egg  = {
		LarvaHP = 50, LarvaDamage = 10, LarvaSpeed = 20,
		AttackRange = 6, AttackCooldown = 1.0, AggroRange = 250,
		RepathSeconds = 0.5, CorpseSeconds = 2,
	},
}
