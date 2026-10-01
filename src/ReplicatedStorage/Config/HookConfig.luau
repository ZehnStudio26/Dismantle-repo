--!strict
-- HookConfig (Shayan 2026-10-01): the grappling hook, the GrapplingHook tool in hotbar slot 4. Aim at a kaiju
-- block, click / tap, the hook latches at the hit point and the player is pulled there. Read by Server.Hook
-- (validation), StarterPack.GrapplingHook.Client (throw, pull, feel) and StarterPlayerScripts.GrappleRopes
-- (other players' ropes). Distances in studs, speeds in studs/s, times in seconds.
return table.freeze({
	Tool = "GrapplingHook", -- the tool's name (StarterPack, ToolConfig.Slots[4]); the server requires it held
	TouchAimWindow = 0.5,   -- touch: a tap this recent aims where it landed, otherwise the screen centre

	-- reach
	Range = 140,           -- farthest hit point from the HumanoidRootPart
	MinRange = 8,          -- nearer than this is a miss (no point hooking the block you stand on)
	RangeSlack = 12,       -- server: extra range allowed for movement and latency
	BoundsSlack = 1,       -- server: the reported hit point may lie this far outside the part's box
	LineSlack = 3,         -- server: the line-of-sight ray may stop this far short of the hit point

	-- the pull (client physics: LinearVelocity on the root)
	MaxSpeed = 120,        -- top pull speed
	Accel = 200,           -- studs/s^2 while speeding up: heavy, not twitchy
	Decel = 350,           -- studs/s^2 braking: speed is capped at sqrt(2 * Decel * (dist - StopDist)), no overshoot
	StopDist = 4,          -- arrived when the root is this close to the hook point
	WindUp = 0.12,         -- after latching, this long at WindUpSpeed before accelerating
	WindUpSpeed = 10,      -- pull speed during the wind-up
	WindUpLift = 8,        -- extra upward speed during the wind-up (lifts the feet off the ground)
	ForceFactor = 1.5,     -- LinearVelocity.MaxForce = mass * (Accel + gravity) * this (finite: no wall flings)
	TurnResponsiveness = 40, -- AlignOrientation responsiveness facing the pull direction
	TurnMaxTorque = 1e6,   -- AlignOrientation torque cap
	PullTimeFactor = 1.5,  -- a pull lasts at most dist / MaxSpeed * this + PullTimeExtra ...
	PullTimeExtra = 1,     -- ... (the server adds the throw flight and WindUp to its own limit)
	FallMargin = 50,       -- release when the root is this close above workspace.FallenPartsDestroyHeight

	-- release
	Cooldown = 2,          -- from release to the next throw
	CooldownSlack = 0.25,  -- server: accept a throw this much early (the release reaches it a ping late)
	MinFireInterval = 0.25, -- server: rate limit between throw requests
	ArriveForward = 10,    -- hop on arrival: forward speed ...
	ArriveUp = 20,         -- ... and upward speed
	JumpKeep = 0.8,        -- jump cancels the pull and keeps this share of the velocity ...
	JumpBoost = 40,        -- ... plus this much upward speed
	AnchorLostKeep = 0.7,  -- the hooked block is cut away: keep this share of the velocity
	RelatchWindow = 0.25,  -- a hooked part that goes (a block cracking into chunks) is looked for again this long ...
	RelatchRadius = 0.3,   -- ... as any kaiju part within this distance of the hook point
	BlockRadius = 1.5,     -- spherecast radius ahead of the root; a hit (not at the target) stops the pull
	BlockLookahead = 3,    -- the spherecast reaches speed * dt + this ahead
	StuckRatio = 0.3,      -- stuck = velocity along the pull under this share of the commanded speed ...
	StuckTime = 0.25,      -- ... for this long ...
	StuckMinSpeed = 15,    -- ... while the commanded speed is above this

	-- throw visuals (client only)
	ThrowSpeed = 300,      -- hook head flight speed out
	RetractSpeed = 360,    -- hook head flight speed back (a miss or a refused throw)
	RopeWidth = 0.25,      -- Beam width
	RopeSlack = 3,         -- Beam CurveSize0 / -CurveSize1 while the head flies; 0 once it latches
	RopeTightenTime = 0.1, -- slack to taut on latch
	RopeColor = Color3.fromRGB(70, 56, 44), -- dark hemp brown
	HeadColor = Color3.fromRGB(60, 62, 70), -- gunmetal hook head (the tool's Handle uses the same colour)
	HeadSize = Vector3.new(0.6, 0.6, 1),    -- the flying hook head part
	-- the flying pose (Ayesh 2026-10-01): an R6 animation looped on the character for the whole pull. The first
	-- upload of 78601899356286 came out of an R15 -> R6 converter with no keyframes, so it plays nothing until
	-- it is re-published (from an R6 rig, to the group) and this id is replaced.
	PullAnimation = "rbxassetid://78601899356286",
	PullAnimFade = 0.15,   -- seconds to blend the pose in on latch and out on release
	-- the old Roblox Grapple Hook gear's art (Ayesh 2026-10-01): the launcher (Handle's SpecialMesh) shows the hook
	-- Loaded while it is in hand and Empty while the hook is out; the flying head wears Hook. Its sounds (Fire,
	-- Hit, Connect) are the Handle's children, copied from the gear.
	Mesh = {
		Loaded = "rbxassetid://33393806",
		Empty = "rbxassetid://30308256",
		Hook = "rbxassetid://30307623",
		Texture = "rbxassetid://30307531",
		Scale = Vector3.new(0.4, 0.4, 0.4),
	},

	-- camera
	FovKick = 8,           -- degrees added on latch ...
	FovKickTime = 0.12,    -- ... over this long (Quad Out)
	FovSpeed = 12,         -- extra degrees at MaxSpeed (scaled by speed / MaxSpeed)
	FovReturnTime = 0.3,   -- back to normal after release
	ShakeSeconds = 0.15,   -- latch shake length ...
	ShakeDegrees = 0.6,    -- ... and strength (fades out)
})
