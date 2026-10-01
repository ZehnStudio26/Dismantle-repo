-- Random events. Provisional; EVT-20 / N5 settle frequency.
return {
	-- EVT-01: at run start this many Flesh blocks are retagged "Event" (Q22). Their outcome is
	-- decided by the roll policy when they break (EVT-02). A16: 35 -> 24.
	-- P-3: eggs are their own block kind and also take random slots (EggCount, added 2026-09-25 after the
	-- showcase validated). Egg stays in the roll below until Survivor / Health exist (KJ-24 / KJ-26).
	Seed = { EventCount = 24, EggCount = 8, RandomSeed = 0 }, -- RandomSeed 0 = different every run
	-- Block colour IS the telegraph (KJ-26): a player reads the kind before cutting. Sheet P-3 / E-1
	-- say event blocks are BLUE (the meeting drawing says green; sheet wins, one line to change).
	-- Egg keeps the pale yellow of the reference; Organ (fixed gas) is gas-green; red is reserved for the UFO.
	Colors = { Event = Color3.fromRGB(60, 130, 235), Egg = Color3.fromRGB(235, 220, 150), Organ = Color3.fromRGB(110, 200, 80), Survivor = Color3.fromRGB(240, 150, 50) },
	-- 6.6 roll policy (A12 / EVT-15..17)
	Roll = {
		Weights = { Gas = 1, Survivor = 1, Health = 1 }, -- E-1 is Gas / Survivor / Health; Health waits on the cross item
		NoImmediateRepeat = true,          -- EVT-15
		SingleEventBelowPercent = 30,      -- EVT-16: below this demolition %, a new event is suppressed while one is active
		LarvaePerParty = { 1, 1, 2, 2 },   -- EVT-17: more enemies at 4 players, never 4x the events
	},
	-- EVT-03 / 05, E-2: a gas burst is a BOX the size of the visible collider (4x4 blocks by 3
	-- high on 6-stud blocks) and the damage volume is that same box. Unmasked players inside take
	-- Damage every DamageInterval, against RunConfig.PlayerMaxHP = 100. At 8 s and 2.5 s a full
	-- unmasked exposure costs 30 HP: gas alone never ends a run, it sets one up.
	-- Look: ServerStorage.Templates.GasCloud (the authored "Gas vfx" part), sized to Size by Server.Gas;
	-- each of its emitters is capped at MaxEmitterRate particles/s after area scaling.
	-- 2026-10-01 polish: damage ticks are phase-locked to the cloud (DamageFrom + k * DamageInterval,
	-- published on the part) so the HUD ring (GasOverlay) can count down to them; GasFX does the puff-in,
	-- the floor footprint and the mobile particle budget. Ticks land at 0.5 / 3.0 / 5.5 s: still 30 HP.
	Gas  = {
		Size = Vector3.new(24, 18, 24), Damage = 10, DamageInterval = 2.5, Duration = 8, TickSeconds = 0.25, MaxEmitterRate = 600,
		GraceSeconds = 0.5,      -- no damage this long after spawn while the cloud puffs in (the first tick lands then)
		PuffBurst = 30,          -- particles each emitter Emit()s at spawn on desktop (scaled down with the rate on low end)
		LowEndRateScale = 0.25,  -- emitter rate on touch devices / graphics quality <= 3: ~74/s per emitter vs ~296 (mobile ~100/s cap)
		LowEndSizeScale = 1.5,   -- ... with particles this much larger, so the box still reads as full
		FloorColor = Color3.fromRGB(110, 200, 80), -- footprint plates on the blocks under the cloud (Organ's gas-green)
		FloorTransparency = 0.65, -- of those plates (Neon, so they glow through the particles)
		HeavyHit = 3,            -- this damage tick of one exposure (and later) flashes a darker, longer vignette
		HissSoundId = "",        -- played at the cloud when it spawns (client); "" = silent
		BreathHeldSoundId = "",  -- played when the mask blocks a tick (client); "" = silent
	},
	Egg  = {
		LarvaHP = 40,           -- U-4: the base gun (10) kills in 4 shots
		LarvaDamage = 1,        -- per bite, one bite per AttackCooldown (Shayan 2026-09-28: 10 -> 1; a 100 HP player survives 100 unanswered bites)
		LarvaSpeed = 20,
		HatchSeconds = 3,       -- a placed egg (Server.Egg) incubates this long before its larvae appear
		AttackRange = 6, AttackCooldown = 1.0,
		AggroRange = 80,        -- was 250: a hatch anywhere pulled every player on the kaiju. "Rampages nearby"
		CorpseSeconds = 2,
		-- Brain rates (Server.Larva, ticked by Server.Enemies). Decide slowly, execute every frame.
		DecideHz = 5,                      -- target selection and repath checks per second
		RepathDistance = 8,                -- recompute the path only once the target has moved this far from where it was computed
		WaypointReach = 3,                 -- advance to the next waypoint within this distance
		StuckSeconds = 2,                  -- no progress for this long: jump and repath
		AttackBox = Vector3.new(6, 6, 6),  -- bite volume between larva and target; a bite needs overlap AND line of sight
		LeashRange = 24,                   -- an idle larva drifts back toward its hatch point beyond this
		MaxAlive = 8,                      -- server-wide cap on living larvae; a hatch past it spawns nothing
		-- Polish 2026-10-01 (shootable egg, hit reactions, rewards; Server.Enemies, client LarvaFX).
		EggHP = 20,                        -- a placed egg takes this much gun / chainsaw damage before it pops (2 base gun shots)
		EggReward = 5,                     -- coins to whoever pops an egg before it hatches (no larvae then)
		KillReward = 3,                    -- coins to a larva's last attacker when it dies (UFO larvae too)
		KnockbackSpeed = 25,               -- studs/s push away from the attacker on every gun / chainsaw hit
		KnockbackUp = 8,                   -- studs/s upward part of that push, so the larva hops off the ground
		HitPause = 0.2,                    -- seconds a hit larva's brain stops (no walking, no biting)
		FlashSeconds = 0.08,               -- client: white hit flash on a larva or egg
		CrackAt = { 0.5, 0.85 },           -- client: incubation fractions for crack stage 1 and 2
		CrackSound = "",                   -- client: sound id at each crack stage ("" = silent until the sound task adds one)
		HatchSound = "",                   -- client: sound id when an egg bursts (hatched or popped)
		DeathSound = "",                   -- client: sound id when a larva dies
	},
	-- E-3 / GDD 6.3, the "jackpot" event (Server.Survivor). Metal Slug rule: the survivor waits where he
	-- appeared until a player walks up, then pays THAT player and leaves. Ayesh 2026-09-25: he gives
	-- health as well as coins (no document says so; recorded in the Event Block Design doc).
	Survivor = {
		Coins = 25,          -- to the rescuer (KJ-24's number)
		Heal = 30,           -- HP to the rescuer, capped at MaxHealth
		RescueRange = 6,     -- studs from the survivor to the rescuer's root
		ExpireSeconds = 60,  -- unrescued, he leaves (EVT-11 answered: a timer)
		ThanksSeconds = 1.5, -- "Thank you!" shows this long before he disappears
		-- findability (2026-10-01, StarterPlayerScripts.SurvivorFX; all client-side, colour = Colors.Survivor)
		MarkerBobSeconds = 0.6, -- the white "!" over his head bobs up and back down in this many seconds each way
		MarkerBobHeight = 0.6,  -- studs it rises (Ayesh 2026-10-01: the light pillar was cut, it did not fit the look)
		HelpEvery = 4,       -- seconds between "HELP!" bubbles while he waits
		HelpShowSeconds = 1.6, -- each "HELP!" bubble stays up this long
		HelpSoundId = "",    -- rbxassetid for the "Help!" call; "" = silent (the sound task fills it)
		HelpVolume = 0.8,    -- of that sound
		HelpHearRange = 120, -- studs: RollOffMaxDistance of the call, so distance is audible
		RescueSoundId = "",  -- rbxassetid for the rescue jingle (local, at him); "" = silent
		ConfettiCount = 30,  -- particles in the one client-side burst when he is rescued
	},
	-- F-1 + drawing p.2 + Ayesh 2026-09-25: the saucer (Server.UFO) attacks every Interval while a
	-- player is in range, picking ONE of two attacks at random by Weights:
	--   Sweep  the sheet's red line is the saucer's ROUTE: a one-block-wide line through the nearest
	--          player turns red, the saucer flies to the near end, then passes along it and everyone
	--          it passes over takes Damage. Intact kaiju blocks under the line tint red meanwhile.
	--   Drop   larvae beamed down under the saucer
	-- Per-model attributes Interval / ActivationRadius / MaxAttacks / DropCount override these.
	-- E-4 health item (KJ-58): a rolled Health outcome leaves a green cross in the cavity
	Health = {
		Heal = 30,           -- HP restored
		PickupRange = 6,     -- studs from the cross to the player's root
		ExpireSeconds = 60,  -- unclaimed, it vanishes
		FloatHeight = 0.5,   -- studs above the cavity floor
	},
	UFO = {
		Interval = 8,            -- seconds between attacks
		ActivationRadius = 120,  -- attacks only while a player is within this many studs
		MaxAttacks = 0,          -- 0 = keeps attacking while it exists (the Enemies cap still limits drops)
		Weights = { Sweep = 1 }, -- Ayesh 2026-10-01: the larva-drop UFO is removed; every visit sweeps (add Drop = 1 to bring it back)
		Drop = {
			Count = 1,             -- larvae per drop (a visit sets its own: Visit.DropMin / DropMax)
			-- beamed down (Shayan 2026-09-28): each larva appears just under the saucer and floats down the
			-- tractor beam, turning, then lands and starts hunting
			DescendSeconds = 2.2,  -- saucer belly to the ground
			StaggerSeconds = 0.45, -- between one larva and the next
			Spread = 3,            -- studs from the beam's centre where they land (the beam is about 8 wide)
			Turns = 1.5,           -- full turns on the way down
			StartBelow = 3,        -- studs under the saucer's root where a larva appears
			WindupSeconds = 1,     -- from the "UFO: ABDUCTION!" announce to the first larva (room for the commit tone)
		},
		-- audio hooks (2026-10-01): no assets yet; each plays only when its id is set ("rbxassetid://...")
		Sounds = {
			Hum = "",                -- looped on the saucer while a visit descends and circles
			HumVolume = 0.6,         -- 0..1
			StingSweep = "",         -- when a sweep is chosen
			StingDrop = "",          -- when a larva drop is chosen
			Commit = "",             -- CommitLead before the pass / the first larva
			CommitLead = 0.5,        -- seconds
			RollOffMaxDistance = 300, -- studs: all UFO sounds are 3D on the saucer, silent past this
		},
		-- the saucer's shadow (client, StarterPlayerScripts.UFOFX): a dark disc on whatever is under it
		Shadow = {
			NearHeight = 15,         -- studs above the ground: at or below this the shadow is darkest and tightest
			FarHeight = 160,         -- at or above this it is faintest and widest (a visit enters from 160 up)
			NearTransparency = 0.35, -- disc transparency when near
			FarTransparency = 0.9,   -- when far
			FarGrow = 1.8,           -- disc diameter / saucer width when far (1 when near): a soft, spread shadow
		},
		-- Visits (2026-09-28, the reference's eagle: it comes "periodically", "EAGLE INCOMING!" on screen,
		-- a red path, one pass across, dodge by stepping out, no reward). One UFO per server at a time.
		Visit = {
			FirstAfter = 120,       -- seconds into a run before the first visit
			IntervalMin = 120,      -- then a random wait between visits (from one leaving to the next arriving)
			IntervalMax = 180,
			HoverHeight = 36,      -- studs above the open layer's top where a SWEEP visit hovers
			BeamGap = 0,           -- a LARVA visit hovers so its beam's foot is this far above the kaiju skin (0 = touching)
			Offset = 30,           -- studs sideways from the player it comes for, so the sweep has a direction
			                       -- (a larva visit hovers straight over the player instead)
			EntryHeight = 160,     -- studs above the hover point it descends from and leaves to
			ArriveSpeed = 35,      -- studs/s down to the hover point (the warning runs meanwhile)
			LeaveSpeed = 45,
			Attacks = 1,           -- then it leaves. Each visit is ONE kind (Shayan 2026-09-28): a sweep OR a larva drop,
			                       -- picked by Weights; never both, so a larva visit has no red line
			DropMin = 3, DropMax = 4, -- larvae a drop visit lands
			AttackInterval = 5,    -- seconds between attacks (the first comes this long after it arrives)
			ActivationRadius = 160,
			-- before attacking, the saucer circles the open layer so everyone sees it coming (Shayan 2026-09-29)
			OrbitSeconds = 8,      -- time on the circle
			OrbitSpeed = 70,       -- studs/s along it
			OrbitMargin = 20,      -- studs outside the open layer's widest block
			OrbitRise = 10,        -- studs above the attack hover height
			SpinDegreesPerSecond = 45, -- the saucer turns while it flies (client-side, StarterPlayerScripts.UFOSpin)
		},
		Sweep = {
			Length = 36, Width = 6, Height = 6, -- studs: one block wide and tall (6-stud blocks since 2026-09-29). Length is for a
			                                     -- saucer off the kaiju; a visiting UFO (FullWidth) lays the line across
			                                     -- the WHOLE open layer through its player, like the eagle's pass
			LineColor = Color3.fromRGB(235, 30, 30), -- the warning: a glowing RED strip on the blocks (2026-10-01: was orange,
			                                     -- too close to the Survivor orange; red is the UFO's colour, see Colors)
			-- the strip's pulse (client, StarterPlayerScripts.UFOFX, from the line's PassAt attribute)
			PulseSlowHz = 1.5,                   -- pulses per second when the pass is PulseRampSeconds or more away
			PulseFastHz = 7,                     -- pulses per second right before the pass
			PulseRampSeconds = 3,                -- the pulse speeds up over this last stretch before the pass
			-- near miss (2026-10-01): the pass goes by a living player within DodgeRange of the damage box
			-- without hitting them -> DodgeReward coins, once per sweep per player
			DodgeRange = 10,                     -- studs from the damage box (sideways / up), at the moment the saucer passes them
			DodgeReward = 5,                     -- coins (Cash attribute)
			EdgeMargin = 7,                      -- a full-width line runs this far past the layer's edge blocks
			GraceSeconds = 2,                   -- the line shows at least this long before the pass begins
			Damage = 5,                        -- to everyone the saucer passes over (sheet: one of four hits)
			FlySpeed = 50,                     -- studs/s to the line's near end and back home (the line shows meanwhile)
			PassSpeed = 35,                     -- studs/s along the line (a 400-stud layer is about 4.5 s)
		},
	},
}
