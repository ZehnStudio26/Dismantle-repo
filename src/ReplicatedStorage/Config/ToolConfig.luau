-- Handheld tools. Provisional (Q05).
return {
	-- D5 / TOOL-05: four inventory slots, keys 1-4 (T-1; the 4th slot was dropped 2026-09-29 and is back
	-- 2026-10-01 for the grappling hook, StarterPack.GrapplingHook, numbers in Config.HookConfig).
	-- 2026-09-28 (Bee): the chainsaw replaced the laser cutter; the LaserCutter tool, Server.Cutter and its
	-- config are retired to ServerStorage.Reference.
	Slots = { "Chainsaw", "Handgun", "GasMask", "GrapplingHook" }, -- slot 2: StarterPack.Handgun (auto lock-on, 2026-09-29)
	-- Chainsaw (Chainsaw Cutting Plan, 2026-09-28): melee cutter modelled on the free mining pack's
	-- pickaxe, animated with Shayan's ChainsawRig set (Equip, Idle, Slash1, Slash2). Hold the mouse to
	-- swing Slash1 then Slash2 as a combo; the hit lands at a fixed time into each slash. Timing and
	-- feel numbers are the pack's own tuning until the chainsaw has been felt in a playtest.
	Chainsaw = {
		HitTime = { Slash1 = 0.408, Slash2 = 0.442 }, -- seconds into each slash when the hit lands (the arm's fastest moment in the rig's AnimSaves)
		-- The hit (retuned 2026-09-28 after Shayan's playtest: 3 hits per block was far too fast). The
		-- reference removes a handful of voxels per swing (a dated wiki note: Damage I = three voxels), so
		-- here a hit takes at most ChunksPerHitByTier chunks of the 27, and DamagePerHit is sized so that
		-- cap dies on Skin (chunk HP 80/27 = 2.96): 10 damage kills 3 Skin chunks, 2 Ridge chunks (4.4 each).
		-- A Skin block therefore takes 9 hits at tier 1; a crit doubles both damage and the cap.
		DamagePerHit = 10,
		ChunksPerHitByTier = { 3, 4, 5 },   -- indexed by the Player.Damage tier (the reference's voxels per swing)
		-- KJ-25 area damage per cutter level: blocks one swing cuts, on the aimed block's layer. 1 = the
		-- aimed block only, 5 = plus its four side neighbours, 9 = the 3x3 around it. Each takes the same
		-- damage and chunk cap as the aimed block. Indexed by the Player.Damage tier.
		AreaByTier = { 1, 5, 9 },
		-- Larvae (T-2 / L-2: the cutter also kills larvae, weaker than the gun). Every swing's hit moment
		-- also strikes the nearest living larva within EnemyRange studs in front of the player (server check).
		-- 7 x the Player.Damage tier: a 40 HP larva takes 6 hits at tier 1 (the gun's base 10 takes 4).
		EnemyDamage = 7,
		EnemyRange = 8,                      -- studs from HumanoidRootPart to the larva's root
		EnemyArc = 0,                         -- dot of facing and direction: 0 = anywhere in front
		CritChance = 0.15,
		CritMultiplier = 2,
		-- Selection (the reference): the block under the mouse cursor, if its centre lies within the
		-- Player.Range tier in BLOCKS of the player's own cell on every axis (Shayan 2026-09-28: one
		-- block around the player to start; Bee: grows with upgrades). The server allows ServerSlack
		-- extra blocks for movement between the client's aim and the server's check.
		ReachFromFeet = 3,                  -- studs from HumanoidRootPart down to the feet (R6)
		ServerSlack = 0.5,
		SwingSeconds = { Slash1 = 1.167, Slash2 = 1.167 }, -- clip lengths (Balance estimate, clock fallback)
		MinHitInterval = 0.3,               -- server rejects hits closer together than this (a combo lands two hits ~1.2 s apart); divided by the Speed tier
		-- The Player.Speed tier multiplies swing playback and divides these three waits.
		ComboGap = 0.12,                    -- pause between Slash1 ending and Slash2 starting
		ComboWindow = 0.6,                  -- how long after that gap Slash2 still counts as the combo
		FinishCooldown = 0.5,               -- pause after Slash2 before the next Slash1
		-- One click = one swing; a click during a swing queues the next (Bee 2026-09-28). Holding the
		-- mouse keeps swinging only with the Player.AutoCut upgrade (UpgradeConfig).
		FadeInTime = 0.12,                  -- animation blend-in
		HitStopTime = 0.07,                 -- swing freezes this long when a hit lands...
		HitStopSpeed = 0.08,                -- ...at this playback speed (0 = full freeze)
		IdleFadeTime = 0.3,                 -- blend into Idle after the Equip animation (no Walk animation: Idle keys the legs, see the plan)
		-- step 4, body feel (the pack's numbers): slower while held, slower still mid-swing; tighter FOV;
		-- the camera follows the head bob.
		Movement = { DefaultWalkSpeed = 16, HeldWalkSpeed = 11, SwingWalkSpeed = 5, Sharpness = 6 },
		Camera = {
			HeldFOV = 62, DefaultFOV = 70, FOVSharpness = 5,
			HeadFollow = { RestOffset = Vector3.new(0, 1.5, 0), Strength = 0.6, MaxDistance = 1.25, Sharpness = 20 },
		},
	},
	-- Gun: D8 unlimited ammo, D9 enemies only. Damage / FireRate / Range are the Gun line in UpgradeConfig.
	Mask = {
		StartingLevel = 1,                  -- Q02: every player spawns with a Lv1 mask
		FOVByTier = { 40, 52, 62, 70 },     -- TOOL-04: camera FOV while the mask is held, Lv1 narrow to Lv4 full
		DefaultFOV = 70,
		-- T-4: the goggle overlay (StarterGui.MaskOverlay.Mask, image 138611101429796) shows while the
		-- mask is held. Per tier; the image is scaled by ApertureByTier[t] / ApertureByTier[1], so Lv1 shows
		-- the whole frame and higher tiers push it out toward the screen edges (Lv4 = x2).
		ApertureByTier = { 0.5, 0.64, 0.8, 1 },
		ApertureTweenSeconds = 0.25,
	},
}
