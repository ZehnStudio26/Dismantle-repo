--!strict
-- Chainsaw client (Chainsaw Cutting Plan steps 1-4, on Shayan's ChainsawRig animations; Bee
-- 2026-09-28: the chainsaw is THE cutter): hold to swing, animate, time the hit, report the block
-- under the cursor to the server, play the feel of the hit, and carry the body feel.
--   * Equip plays once when the tool comes out, then Idle loops while it is held. The animations
--     key the "Handle" joint, so the saw's position is theirs; the server mounts the Motor6D.
--     The uploaded ids on Animations.<name> play (live and in Studio). Animations.UpperBody holds copies
--     of the rig's AnimSaves with the leg keys removed, so the default walk and idle move the legs; they
--     are registered as temporary ids only in Studio for a clip with no uploaded id. On R6 the legs hang off the
--     torso and the slashes twist it up to ~88 deg, so while the saw is out the hips are turned back
--     by that twist every frame (keepLegs): the legs walk where you move, the torso swings.
--   * Each click swings once (Bee 2026-09-28): Slash1, then Slash2 as a combo (ComboGap /
--     ComboWindow), then a rest of FinishCooldown. A click during a swing queues the next one.
--     Holding the mouse keeps swinging only with the Player.AutoCut upgrade. The Player.Speed tier
--     multiplies swing playback and divides the waits.
--   * Selection works like the reference: the block under the mouse cursor is outlined white if it
--     is within reach, and the swing's hit lands on it at the ray's hit point. Reach is the
--     Player.Range tier in BLOCKS around the player's own cell (1 = the ring around you, the floor
--     under you and the step above). A block out of reach gets no outline and the swing whiffs.
--     Any block in reach can be cut, at any height (Ayesh 2026-10-01: only the drones go layer by layer).
--     The hit lands HitTime seconds into each slash (the arm's fastest moment in the rig's saves).
--   * Feel (own hits only, from the server's reply): outline flash (red on a crit), white screen
--     flash, camera dip and shake, "CRITICAL!" billboard at the hit point, hitstop. The block pop,
--     dust and shards come from BlockFX like every other hit.
--   * Body: walk speed drops while held and again mid-swing, the FOV tightens while held, the
--     camera follows the head bob.
-- Sounds on the Handle: EquipSound on equip, IdleSound loops while held, SwingSound per swing,
-- HitSound when the hit lands. The FX gui is StarterGui.ChainsawFX, authored in Studio.
-- Every decision prints with a [Chainsaw] prefix so a pasted Output log answers the questions.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local ToolConfig = require(ReplicatedStorage.Config.ToolConfig)
local FXConfig = require(ReplicatedStorage.Config.FXConfig)
local UpgradeConfig = require(ReplicatedStorage.Config.UpgradeConfig)
local RunConfig = require(ReplicatedStorage.Config.RunConfig)
local RunState = ReplicatedStorage:WaitForChild("RunState")
local Cfg = ToolConfig.Chainsaw
local FX = FXConfig.Chainsaw
local MOVE, CAM = Cfg.Movement, Cfg.Camera
local ChainsawHit: RemoteEvent = ReplicatedStorage.Remotes.ChainsawHit

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local tool = script.Parent :: Tool
local animFolder = tool:WaitForChild("Animations")
local handle = tool:WaitForChild("Handle")

local fxGui = player:WaitForChild("PlayerGui"):WaitForChild("ChainsawFX")
local hitFlash = fxGui:WaitForChild("HitFlash") :: Frame
local critTemplate = fxGui:WaitForChild("CritText") :: BillboardGui

local function sound(name: string): Sound?
	local s = handle:FindFirstChild(name)
	return if s and s:IsA("Sound") then s else nil
end
local equipSound, idleSound, swingSound, hitSound = sound("EquipSound"), sound("IdleSound"), sound("SwingSound"), sound("HitSound")

-- grid geometry, read once (Demolition derives the same values the same way)
local kaijuModel = workspace:WaitForChild("Kaiju")
local BLOCK = tonumber(kaijuModel:GetAttribute("BlockSize")) or 8
local ORIGIN = if typeof(kaijuModel:GetAttribute("Origin")) == "Vector3" then kaijuModel:GetAttribute("Origin") :: Vector3 else Vector3.zero

-- upgrade tiers, read live so a purchase applies at once
local function speedMult(): number return UpgradeConfig.Value(player, "Player", "Speed") end
local function reachBlocks(): number return UpgradeConfig.Value(player, "Player", "Range") end
local function autoCut(): boolean return UpgradeConfig.Value(player, "Player", "AutoCut") >= 1 end
type Swing = "Slash1" | "Slash2"

-- rig for the current equip; nil while unequipped
type Rig = {
	humanoid: Humanoid,
	root: BasePart,
	head: BasePart?,
	tracks: { [string]: AnimationTrack },
	conns: { RBXScriptConnection },
}
local rig: Rig? = nil

-- swing state (the pack's MiningRules.SwingState)
local held = false
local queued = false              -- a click waiting for the next swing (one click = one swing)
local current: Swing? = nil       -- swing playing right now
local currentMult = 1             -- speed multiplier the current swing started with
local nextSwing: Swing = "Slash1" -- what the next click gives
local readyAt = 0                 -- no swing before this
local comboExpiresAt = math.huge  -- after this, a pending Slash2 falls back to Slash1
local hitStopUntil = -math.huge
local hitFired = false
local swingCount = 0
local swingStartedAt = 0
local lastHitPos = Vector3.zero   -- where the last reported hit landed, for the crit text

-- camera feel state
local dip, dipVelocity = 0, 0
local shakeUntil, shakeSeconds, shakeDegrees = -math.huge, 1, 0
local headMotion = Vector3.zero
local rng = Random.new()


-- frame-rate independent lerp factor (the pack's MathUtil.ExponentialAlpha)
local function alpha(sharpness: number, dt: number): number
	return 1 - math.exp(-sharpness * dt)
end

-- ---------- selection: the block under the cursor, within reach ----------
-- the logical block a part belongs to: a cracked block Model or the intact block Part
local function holderOf(part: BasePart): Instance
	return if part.Parent and part.Parent.Parent == kaijuModel then part.Parent :: Instance else part
end

-- centre of the logical block a holder occupies, from its grid key (independent of surviving chunks)
local function blockCentre(holder: Instance): Vector3?
	local bx, by, bz = holder:GetAttribute("BX"), holder:GetAttribute("BY"), holder:GetAttribute("BZ")
	if typeof(bx) ~= "number" or typeof(by) ~= "number" or typeof(bz) ~= "number" then return nil end
	return ORIGIN + Vector3.new(bx, by, bz) * BLOCK
end

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Include
aimParams.FilterDescendantsInstances = { kaijuModel }

-- Index of cracked blocks keyed by name, kept by ChildAdded / ChildRemoved. NOT FindFirstChild:
-- Workspace.Kaiju has ~8,000 children and FindFirstChild scans them (measured 100 us per call).
local crackedBlocks: { [string]: Instance } = {}
local function trackChild(child: Instance)
	if child:IsA("Model") and child.Name:sub(1, 6) == "Block_" then crackedBlocks[child.Name] = child end
end
for _, child in ipairs(kaijuModel:GetChildren()) do trackChild(child) end
kaijuModel.ChildAdded:Connect(trackChild)
kaijuModel.ChildRemoved:Connect(function(child)
	if crackedBlocks[child.Name] == child then crackedBlocks[child.Name] = nil end
end)

local function crackedBlockAt(pos: Vector3): Instance?
	local k = (pos - ORIGIN) / BLOCK
	return crackedBlocks[("Block_%d_%d_%d"):format(math.round(k.X), math.round(k.Y), math.round(k.Z))]
end

-- ray vs axis-aligned cube: where the ray first enters it, or nil (the face the player looks at)
local function slab(o: number, d: number, c: number, half: number, tmin: number, tmax: number): (number, number)
	if math.abs(d) < 1e-6 then
		if math.abs(o - c) > half then return math.huge, -math.huge end
		return tmin, tmax
	end
	local t1, t2 = (c - half - o) / d, (c + half - o) / d
	if t1 > t2 then t1, t2 = t2, t1 end
	return math.max(tmin, t1), math.min(tmax, t2)
end
local function rayEntersCube(origin: Vector3, dir: Vector3, centre: Vector3, half: number): Vector3?
	local tmin, tmax = -math.huge, math.huge
	tmin, tmax = slab(origin.X, dir.X, centre.X, half, tmin, tmax)
	tmin, tmax = slab(origin.Y, dir.Y, centre.Y, half, tmin, tmax)
	tmin, tmax = slab(origin.Z, dir.Z, centre.Z, half, tmin, tmax)
	if tmin > tmax then return nil end
	return origin + dir * math.max(tmin, 0)
end

-- first cracked block whose cell the ray crosses within `limit` studs (half-block steps cannot skip a cell)
local STEP = BLOCK * 0.5
local function firstCrackedAlongRay(origin: Vector3, dir: Vector3, limit: number): (Instance?, Vector3?)
	local t = 0
	while t <= limit do
		local sample = origin + dir * t
		local model = crackedBlockAt(sample)
		if model then
			local centre = blockCentre(model)
			return model, (if centre then rayEntersCube(origin, dir, centre, BLOCK * 0.5) else nil) or sample
		end
		t += STEP
	end
	return nil, nil
end

-- the centre of the cell the player's body stands in (feet plus half a block); reach is measured from here
local function bodyCell(root: BasePart): Vector3
	return root.Position + Vector3.yAxis * (BLOCK / 2 - Cfg.ReachFromFeet)
end

-- Reach test, mirrored by Server.Chainsaw: the block's centre must lie within Range blocks of the
-- body cell on every axis (a cube, so the ring around you, the floor and the step above all count).
local function inReach(root: BasePart, centre: Vector3): boolean
	local d = (centre - bodyCell(root)) / BLOCK
	return math.max(math.abs(d.X), math.abs(d.Y), math.abs(d.Z)) <= reachBlocks() + 0.5
end

-- Returns the part to report, the hit position and its holder for the block under the cursor, or nil.
-- The raycast alone loses a cracked block (a ray into one of its holes lands on what is behind), so
-- the grid walk runs on every aim and wins whenever it finds a cracked block nearer than the hit.
local function aimed(root: BasePart): (BasePart?, Vector3?, Instance?, boolean?)
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local dir = ray.Direction.Unit
	local limit = (root.Position - ray.Origin).Magnitude + (reachBlocks() + 1) * BLOCK * 1.8
	local hit = workspace:Raycast(ray.Origin, dir * limit, aimParams)
	local hitPart: BasePart? = if hit and hit.Instance:IsA("BasePart") then hit.Instance else nil
	local hitPos: Vector3? = if hit then hit.Position else nil
	local hitHolder: Instance? = if hitPart then holderOf(hitPart) else nil
	local walkLimit = if hitPos then (hitPos - ray.Origin).Magnitude else limit
	local model, entry = firstCrackedAlongRay(ray.Origin, dir, walkLimit)
	if model and model ~= hitHolder then
		local chunk = model:FindFirstChildWhichIsA("BasePart")
		if chunk then hitPart, hitPos, hitHolder = chunk, entry, model end
	end
	local centre = if hitHolder then blockCentre(hitHolder) else nil
	if not centre or not inReach(root, centre) then return nil, nil, nil end
	return hitPart, hitPos, hitHolder
end

-- outline of the selected block (one client-only box moved onto it)
local aimBox = Instance.new("Part")
aimBox.Name = "ChainsawAimBox"
aimBox.Anchored = true
aimBox.CanCollide = false
aimBox.CanQuery = false -- must never be hit by our own raycast
aimBox.CanTouch = false
aimBox.CastShadow = false
aimBox.Transparency = 1
aimBox.Size = Vector3.one * (BLOCK + 0.1)
aimBox.Parent = workspace
local outline = Instance.new("SelectionBox")
outline.Name = "BlockOutline"
outline.Color3 = Color3.new(1, 1, 1)
outline.LineThickness = 0.08
outline.SurfaceTransparency = 1
outline.Adornee = aimBox
outline.Visible = false
outline.Parent = tool

-- ---------- feel ----------
local function flashOutline(crit: boolean)
	local f = if crit then FX.CritFlash else FX.Flash
	outline.SurfaceColor3 = f.Color
	outline.SurfaceTransparency = f.Fill
	TweenService:Create(outline, TweenInfo.new(f.Seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { SurfaceTransparency = 1 }):Play()
end

local function screenFlash(crit: boolean)
	local s = if crit then FX.Screen.Crit else FX.Screen.Hit
	hitFlash.BackgroundTransparency = s.Transparency
	TweenService:Create(hitFlash, TweenInfo.new(s.Seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

local function kickCamera(crit: boolean)
	dipVelocity += if crit then FX.Dip.Crit else FX.Dip.Hit
	local s = if crit then FX.Shake.Crit else FX.Shake.Hit
	shakeSeconds, shakeDegrees = s.Seconds, s.Degrees
	shakeUntil = os.clock() + s.Seconds
end

local function critText(pos: Vector3)
	local c = FX.CritText
	local anchor = Instance.new("Attachment")
	anchor.Name = "ChainsawCritAnchor"
	anchor.WorldPosition = pos
	anchor.Parent = workspace.Terrain
	local gui = critTemplate:Clone()
	local label = gui:FindFirstChild("Label") :: TextLabel
	local stroke = label:FindFirstChildOfClass("UIStroke")
	local scale = label:FindFirstChildOfClass("UIScale")
	local rest = gui.StudsOffset
	gui.StudsOffset = rest - Vector3.xAxis * c.Rise
	gui.Adornee = anchor
	gui.Enabled = true
	gui.Parent = anchor
	local enter = TweenInfo.new(c.InSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local appear = TweenInfo.new(c.InSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local leave = TweenInfo.new(c.OutSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, c.HoldSeconds)
	TweenService:Create(gui, enter, { StudsOffset = rest }):Play()
	TweenService:Create(label, appear, { TextTransparency = 0 }):Play()
	if stroke then TweenService:Create(stroke, appear, { Transparency = 0.2 }):Play() end
	if scale then TweenService:Create(scale, enter, { Scale = 1 }):Play() end
	task.delay(c.InSeconds, function()
		TweenService:Create(gui, leave, { StudsOffset = rest + Vector3.yAxis * c.Rise }):Play()
		TweenService:Create(label, leave, { TextTransparency = 1 }):Play()
		if stroke then TweenService:Create(stroke, leave, { Transparency = 1 }):Play() end
	end)
	task.delay(c.InSeconds + c.HoldSeconds + c.OutSeconds + 0.1, function() anchor:Destroy() end)
end

-- runs after the camera scripts each frame while equipped: FOV, head follow and dip on
-- Humanoid.CameraOffset, rotation noise on the camera
local function cameraStep(dt: number)
	local r = rig
	if not r then return end
	local cam = workspace.CurrentCamera
	if cam then
		cam.FieldOfView += (CAM.HeldFOV - cam.FieldOfView) * alpha(CAM.FOVSharpness, dt)
	end
	local target = Vector3.zero
	if r.head then
		local restCF = r.root.CFrame * CFrame.new(CAM.HeadFollow.RestOffset)
		local offset = restCF:PointToObjectSpace(r.head.Position) * CAM.HeadFollow.Strength
		if offset.Magnitude > CAM.HeadFollow.MaxDistance then offset = offset.Unit * CAM.HeadFollow.MaxDistance end
		target = offset
	end
	headMotion = headMotion:Lerp(target, alpha(CAM.HeadFollow.Sharpness, dt))
	local k = FX.Dip.Stiffness
	local c = 2 * FX.Dip.DampingRatio * math.sqrt(k)
	dipVelocity += (-k * dip - c * dipVelocity) * dt
	dip += dipVelocity * dt
	r.humanoid.CameraOffset = headMotion + Vector3.new(0, dip, 0)
	local now = os.clock()
	if now < shakeUntil and cam then
		local d = shakeDegrees * (shakeUntil - now) / shakeSeconds
		cam.CFrame = cam.CFrame * CFrame.Angles(math.rad(rng:NextNumber(-d, d)), math.rad(rng:NextNumber(-d, d)), math.rad(rng:NextNumber(-d, d) * 0.5))
	end
end

-- ---------- the hit ----------
local function onHit(swing: Swing, track: AnimationTrack, r: Rig)
	hitStopUntil = os.clock() + Cfg.HitStopTime
	if hitSound then hitSound:Play() end
	local part, pos = aimed(r.root)
	local at = if track.Length > 0 then track.TimePosition else (os.clock() - swingStartedAt) * currentMult
	if part and pos then
		lastHitPos = pos
		ChainsawHit:FireServer(part, pos, swing)
	else
		ChainsawHit:FireServer(nil, nil, swing) -- no block, but the swing can still strike a larva
	end
end

ChainsawHit.OnClientEvent:Connect(function(ok: boolean, reason: string, crit: boolean, damage: number)
	if ok then
		flashOutline(crit)
		screenFlash(crit)
		kickCamera(crit)
		if crit then critText(lastHitPos) end
	end
end)

-- ---------- swings ----------
local function afterSwing(finished: Swing)
	local now = os.clock()
	local mult = speedMult()
	if finished == "Slash1" then
		nextSwing = "Slash2"
		readyAt = now + Cfg.ComboGap / mult
		comboExpiresAt = readyAt + Cfg.ComboWindow
	else
		nextSwing = "Slash1"
		readyAt = now + Cfg.FinishCooldown / mult
		comboExpiresAt = math.huge
	end
end

local function endSwing(swing: Swing)
	if current ~= swing then return end
	current = nil
	afterSwing(swing)
end

local function startSwing(r: Rig, swing: Swing)
	local track = r.tracks[swing]
	current = swing
	currentMult = speedMult()
	hitFired = false
	local byClick = queued
	queued = false
	swingCount += 1
	swingStartedAt = os.clock()
	track.Stopped:Once(function()
		if track.Length <= 0 then return end -- unloaded track: the clock fallback in step() ends the swing
		endSwing(swing)
	end)
	track:Play(Cfg.FadeInTime, 1, currentMult)
	if swingSound then swingSound:Play() end
end

local function wantsSwing(): boolean
	return queued or (held and autoCut())
end

-- which swing is due now, or nil (the pack's MiningRules.NextSwing)
local function dueSwing(now: number): Swing?
	if current ~= nil or not wantsSwing() or now < readyAt then return nil end
	if nextSwing == "Slash2" and now > comboExpiresAt then return "Slash1" end
	return nextSwing
end

local function step(r: Rig, dt: number)
	local now = os.clock()
	-- Idle loops under everything once Equip has finished
	local equipTrack, idle = r.tracks.Equip, r.tracks.Idle
	if not idle.IsPlaying and not equipTrack.IsPlaying then idle:Play(Cfg.IdleFadeTime) end
	-- walk speed: slower while held, slower still mid-swing, eased so a swing ending does not jerk
	local targetSpeed = if current then MOVE.SwingWalkSpeed else MOVE.HeldWalkSpeed
	r.humanoid.WalkSpeed += (targetSpeed - r.humanoid.WalkSpeed) * alpha(MOVE.Sharpness, dt)
	-- swing in progress: hitstop and the hit itself
	local swing = current
	if swing then
		local track = r.tracks[swing]
		local loaded = track.Length > 0
		local t = if loaded then track.TimePosition else (now - swingStartedAt) * currentMult
		track:AdjustSpeed(if now < hitStopUntil then Cfg.HitStopSpeed else currentMult)
		if not hitFired and t >= Cfg.HitTime[swing] then
			hitFired = true
			onHit(swing, track, r)
		end
		if not loaded and t >= Cfg.SwingSeconds[swing] then endSwing(swing) end
	end
	local due = dueSwing(now)
	if due then startSwing(r, due) end
end

-- the outline follows the cursor every rendered frame (cheap: one raycast and a few table lookups)
local function outlineStep()
	local r = rig
	if not r then return end
	local _, _, holder = aimed(r.root)
	local centre = if holder then blockCentre(holder) else nil
	if centre and aimBox.Position ~= centre then aimBox.CFrame = CFrame.new(centre) end
	outline.Visible = centre ~= nil
end

-- an upper-body clip (leg keys removed) as an Animation, registered once per session. Studio only, and only
-- for a clip with no uploaded id: registered ids are temporary and never load in the live game (2026-09-30)
local upperIds: { [string]: string } = {}
local function upperBody(name: string): Animation?
	if not RunService:IsStudio() then return nil end
	local folder = animFolder:FindFirstChild("UpperBody")
	local kfs = folder and folder:FindFirstChild(name)
	if not kfs or not kfs:IsA("KeyframeSequence") then return nil end
	if not upperIds[name] then
		local ok, id = pcall(function() return KeyframeSequenceProvider:RegisterKeyframeSequence(kfs) end)
		if not ok then
			warn(("[Chainsaw] could not register the upper-body %s clip (%s): using the full-body one"):format(name, tostring(id)))
			return nil
		end
		upperIds[name] = id
	end
	local a = Instance.new("Animation")
	a.AnimationId = upperIds[name]
	return a
end

-- R6: counter the torso's twist at the hips so the legs keep walking straight. Motor6D.Transform is
-- written by the Animator before PreSimulation, so this runs after it every frame. A hip no track
-- animates keeps the value written last frame; that is detected so the correction never stacks.
local restoreLegs: (() -> ())? = nil
local function keepLegs(char: Model, root: BasePart, conns: { RBXScriptConnection })
	local rootJoint = root:FindFirstChild("RootJoint")
	local torso = char:FindFirstChild("Torso")
	if not (rootJoint and rootJoint:IsA("Motor6D") and torso) then return end
	type Hip = { motor: Motor6D, a: CFrame, base: CFrame?, written: CFrame? }
	local hips: { Hip } = {}
	for _, n in ipairs({ "Left Hip", "Right Hip" }) do
		local m = torso:FindFirstChild(n)
		if m and m:IsA("Motor6D") then table.insert(hips, { motor = m, a = (rootJoint.C1:Inverse() * m.C0).Rotation }) end
	end
	local function same(x: CFrame, y: CFrame): boolean
		return (x.Position - y.Position).Magnitude < 1e-4 and x.LookVector:Dot(y.LookVector) > 0.99999 and x.UpVector:Dot(y.UpVector) > 0.99999
	end
	table.insert(conns, RunService.PreSimulation:Connect(function()
		local untwist = rootJoint.Transform.Rotation:Inverse()
		for _, h in ipairs(hips) do
			local cur = h.motor.Transform
			local base = if h.written and same(cur, h.written) then h.base :: CFrame else cur
			local fixed = CFrame.new(base.Position) * (h.a:Inverse() * untwist * h.a) * base.Rotation
			h.base, h.written = base, fixed
			h.motor.Transform = fixed
		end
	end))
	restoreLegs = function()
		for _, h in ipairs(hips) do if h.base then h.motor.Transform = h.base end end
	end
end

local function equip()
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local head = char and char:FindFirstChild("Head")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not humanoid or not animator or not root or not root:IsA("BasePart") then
		warn("[Chainsaw] equip: no humanoid / animator / root on the character")
		return
	end
	local tracks: { [string]: AnimationTrack } = {}
	for _, name in ipairs({ "Equip", "Idle", "Slash1", "Slash2" }) do
		local anim = animFolder:FindFirstChild(name)
		if not anim or not anim:IsA("Animation") then
			warn("[Chainsaw] missing animation " .. name)
			return
		end
		local track = animator:LoadAnimation(if anim.AnimationId ~= "" then anim else (upperBody(name) or anim))
		track.Looped = name == "Idle"
		-- Idle sits under Equip and the slashes: Action < Action2 < Action3
		track.Priority = if name == "Idle" then Enum.AnimationPriority.Action elseif name == "Equip" then Enum.AnimationPriority.Action2 else Enum.AnimationPriority.Action3
		tracks[name] = track
	end
	local r: Rig = { humanoid = humanoid, root = root, head = if head and head:IsA("BasePart") then head else nil, tracks = tracks, conns = {} }
	rig = r
	current, nextSwing, readyAt, comboExpiresAt, hitFired = nil, "Slash1", 0, math.huge, false
	dip, dipVelocity, shakeUntil, headMotion = 0, 0, -math.huge, Vector3.zero
	table.insert(r.conns, RunService.Heartbeat:Connect(function(dt)
		if rig == r then step(r, dt) end
	end))
	table.insert(r.conns, RunService.RenderStepped:Connect(outlineStep))
	RunService:BindToRenderStep("ChainsawCamera", Enum.RenderPriority.Camera.Value + 1, cameraStep)
	if humanoid.RigType == Enum.HumanoidRigType.R6 then keepLegs(char :: Model, root, r.conns) end
	tracks.Equip:Play(Cfg.FadeInTime)
	if equipSound then equipSound:Play() end
	if idleSound then idleSound:Play() end
	-- load checks: a track that stays at length 0 did not load; the server should have mounted the saw
	task.delay(1.5, function()
		if rig ~= r then return end
		for name, track in pairs(tracks) do
			if track.Length <= 0 then
				warn(("[Chainsaw] animation %s has length 0 after 1.5 s: it did not load (share access to the experience)"):format(name))
			end
		end
		for _, s in ipairs({ equipSound, idleSound, swingSound, hitSound }) do
			if s and not s.IsLoaded then warn(("[Chainsaw] sound %s (%s) has not loaded"):format(s.Name, s.SoundId)) end
		end
		local arm = char:FindFirstChild("Right Arm") or char:FindFirstChild("RightHand")
		local motor = arm and arm:FindFirstChild("Handle")
		if not (motor and motor:IsA("Motor6D")) then warn("[Chainsaw] mount check: no Motor6D Handle on " .. (arm and arm.Name or "?")) end
	end)
end

local function unequip()
	local r = rig
	rig = nil
	held = false
	queued = false
	outline.Visible = false
	if idleSound then idleSound:Stop() end
	RunService:UnbindFromRenderStep("ChainsawCamera")
	local cam = workspace.CurrentCamera
	if cam then cam.FieldOfView = CAM.DefaultFOV end
	if not r then return end
	r.humanoid.CameraOffset = Vector3.zero
	r.humanoid.WalkSpeed = MOVE.DefaultWalkSpeed
	for _, c in ipairs(r.conns) do c:Disconnect() end
	if restoreLegs then restoreLegs(); restoreLegs = nil end
	for _, track in pairs(r.tracks) do track:Stop(0) end
	current = nil
end

tool.Equipped:Connect(equip)
tool.Unequipped:Connect(unequip)
tool.Activated:Connect(function()
	held = true
	queued = true
end)
tool.Deactivated:Connect(function()
	held = false
end)
-- the tool being in the character on script start (respawn with it equipped) is covered by Equipped
if tool.Parent == player.Character then equip() end
