--!strict
-- UFO (F-1 / drawing p.2, Ayesh 2026-09-25): a hovering saucer that attacks every Interval while a
-- player is within ActivationRadius, choosing ONE of two attacks at random each time:
--   Sweep  the red line is the saucer's ROUTE. A Length x Width x Height box is laid through the
--          nearest player on their floor, pointing from the saucer toward them. A glowing red strip
--          shows it while the saucer flies to the near end, at least GraceSeconds. Then the saucer
--          passes along the line and everyone whose character is on the line takes Damage the moment
--          the saucer passes over them. The saucer then flies home.
--          The line part (Workspace.Hazards.UFOLine) carries PassAt = server time the pass starts
--          (workspace:GetServerTimeNow()); StarterPlayerScripts.UFOFX pulses it faster toward it and
--          points an off-screen arrow at it. Near miss (2026-10-01): a living player the pass goes by
--          within Sweep.DodgeRange of the box, unhit, gets Sweep.DodgeReward coins once per sweep.
--   Drop   larvae beamed down under the saucer (Larvae.SpawnGroup), Drop.WindupSeconds after the announce.
-- When the attack is chosen: a sting (Sounds.StingSweep / StingDrop) and a popup to everyone at the
-- saucer ("UFO: SWEEP!" / "UFO: ABDUCTION!"); Sounds.Commit plays Sounds.CommitLead before the pass /
-- the first larva. Sounds play only when their id is set (EventConfig.UFO.Sounds).
-- Behaviour only, attached by the "UFO" tag: anything tagged UFO inside Workspace does this from where
-- it was placed. The model needs an anchored PrimaryPart with the rest welded to it (the test one is);
-- flight tweens that part.
-- Visits (bottom of this file, EventConfig.UFO.Visit): during a run one UFO at a time clones
-- ServerStorage.Templates.UFO, descends over a player on the open layer (Sounds.Hum looping) while the
-- HUD flashes "EVENT: UFO INCOMING!", attacks Attacks times, then leaves (attribute LeaveWhenDone).
-- Its shadow is client-side (UFOFX).
--
-- Attributes on the model override EventConfig.UFO: Interval, ActivationRadius, MaxAttacks
-- (0 = no limit), DropCount.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local EventConfig = require(ReplicatedStorage.Config.EventConfig)
local Tags = require(ReplicatedStorage.Config.Tags)
local UITheme = require(ReplicatedStorage.Config.UITheme)
local Demolition = require(script.Parent.Demolition)
local Larvae = require(script.Parent.Larvae)
local TagBinder = require(script.Parent.TagBinder)
local FX = require(script.Parent.FX)

local Cfg = EventConfig.UFO
local Snd = Cfg.Sounds
local RunState = ReplicatedStorage:WaitForChild("RunState")
local hazards = workspace:WaitForChild("Hazards") -- the red line lives here, so it counts as an active event
local enemies = workspace:WaitForChild("Enemies")
local rng = Random.new()
local RED = Cfg.Sweep.LineColor
local GOLD = UITheme.Palette.Gold

local floorRay = RaycastParams.new()
floorRay.FilterType = Enum.RaycastFilterType.Exclude
local lineBox = OverlapParams.new()
lineBox.FilterType = Enum.RaycastFilterType.Include

local function characters(): { Instance }
	local list: { Instance } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(list, p.Character) end
	end
	return list
end

-- a 3D sound on `parent` (the saucer's root), or nil while its id is unset. One-shots clean themselves up.
local function sound(id: string, parent: Instance, looped: boolean?, volume: number?): Sound?
	if id == "" then return nil end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = looped == true
	s.Volume = volume or 1
	s.RollOffMaxDistance = Snd.RollOffMaxDistance
	s.Parent = parent
	s:Play()
	if not s.Looped then s.Ended:Once(function() s:Destroy() end) end
	return s
end

-- nearest living player's root within radius, or nil. A player still in the intro brief is not a
-- target (BriefComplete, set by Server.Brief): 2026-09-25 playtest, the saucer took 20 HP off a
-- player standing at spawn watching the narration.
local function nearestRoot(pos: Vector3, radius: number): BasePart?
	local best: BasePart? = nil
	local bestD = radius
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and hum and hum.Health > 0 and p:GetAttribute("BriefComplete") == true then
			local d = (root.Position - pos).Magnitude
			if d < bestD then best, bestD = root, d end
		end
	end
	return best
end

-- straight down from `from`, ignoring the saucer, larvae and players
local function floorBelow(from: Vector3, model: Model): Vector3?
	local exclude = characters()
	table.insert(exclude, model)
	table.insert(exclude, enemies)
	floorRay.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(from, Vector3.new(0, -200, 0), floorRay)
	return if hit then hit.Position else nil
end

-- How far the open layer reaches along `dir` from `p` (signed studs, lowest and highest block
-- centre), for a line that crosses the whole layer. nil when there is no open layer.
local function layerSpan(p: Vector3, dir: Vector3): (number?, number?)
	local active = RunState:GetAttribute("ActiveLayer")
	if typeof(active) ~= "number" then return nil, nil end
	local lo, hi = math.huge, -math.huge
	for _, h in ipairs(Demolition.AllBlockHolders()) do
		if h:GetAttribute("BY") == active and h:GetAttribute("Adopted") ~= true then
			local c = Demolition.CenterOf(h)
			if c then
				local t = Vector3.new(c.X - p.X, 0, c.Z - p.Z):Dot(dir)
				lo, hi = math.min(lo, t), math.max(hi, t)
			end
		end
	end
	if lo > hi then return nil, nil end
	return lo, hi
end

local function pickAttack(): string
	local total = 0
	for _, w in pairs(Cfg.Weights) do total += w end
	local r = rng:NextNumber() * total
	for kind, w in pairs(Cfg.Weights) do
		r -= w
		if r <= 0 then return kind end
	end
	return "Sweep" -- no weights configured (the larva drop was removed 2026-10-01)
end

-- tween the anchored root to `pos`, keeping its rotation; returns when it arrives
local function flyTo(root: BasePart, pos: Vector3, speed: number)
	local dist = (pos - root.Position).Magnitude
	local tween = TweenService:Create(root, TweenInfo.new(math.max(0.1, dist / speed), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = CFrame.new(pos) * root.CFrame.Rotation })
	tween:Play()
	while tween.PlaybackState == Enum.PlaybackState.Playing and root.Parent do task.wait() end
end

-- ---- the two attacks ----

-- one larva floating down the beam from `from` to `land`, turning; it lands upright and is let go
local function beamDown(larva: Model, from: Vector3, land: Vector3)
	local root = larva.PrimaryPart
	if not root then return end
	local D = Cfg.Drop
	-- `land` is 3 studs over the ground (where larvae always spawned); set it to this body's own feet
	local hum = larva:FindFirstChildOfClass("Humanoid")
	land = Vector3.new(land.X, land.Y - 3 + root.Size.Y / 2 + (if hum then hum.HipHeight else 0), land.Z)
	larva:SetAttribute("Descending", true)
	root.Anchored = true -- after Larvae.Spawn set the network owner (not allowed on an anchored part)
	root.CFrame = CFrame.new(from)
	local t0 = os.clock()
	while larva.Parent and root.Parent do
		local a = math.min(1, (os.clock() - t0) / D.DescendSeconds)
		local e = (1 - math.cos(a * math.pi)) / 2 -- sine in-out: eases off the saucer and settles onto the ground
		root.CFrame = CFrame.new(from:Lerp(land, e)) * CFrame.Angles(0, e * D.Turns * 2 * math.pi, 0)
		if a >= 1 then break end
		RunService.Heartbeat:Wait()
	end
	if not larva.Parent or not root.Parent then return end -- shot on the way down, or the run ended
	root.CFrame = CFrame.new(land)
	root.Anchored = false
	root:SetNetworkOwner(nil)
	larva:SetAttribute("Descending", nil)
end

-- larvae beamed down under the saucer, one after another, landing around the beam's foot
local function drop(model: Model, count: number)
	local D = Cfg.Drop
	local at = floorBelow(model:GetPivot().Position, model)
	if not at then return end
	local topY = model:GetPivot().Position.Y - D.StartBelow
	local spin = rng:NextNumber(0, 2 * math.pi)
	for i = 1, count do
		local a = spin + (i - 1) * 2 * math.pi / math.max(count, 1)
		local r = if count > 1 then D.Spread else 0
		local land = at + Vector3.new(math.cos(a) * r, 3, math.sin(a) * r) -- 3 studs up, where larvae always spawned (the 4-stud body settles onto the ground)
		local from = Vector3.new(land.X, topY, land.Z)
		local larva = Larvae.Spawn(from, "UFO")
		if larva then task.spawn(beamDown, larva, from, land) end
		if i < count then task.wait(D.StaggerSeconds) end
		if not model.Parent then break end
	end
	task.wait(D.DescendSeconds) -- hold the beam until the last one is down (a visit leaves right after)
end

type Fields = { model: Model, thread: thread?, cleanup: (() -> ())? }

-- near miss: `p` (alive, unhit) whose root is `rootPos` was just passed by the saucer. Pays if it was
-- within DodgeRange of the damage box (sideways / up, in the box's own space) but outside it.
local function judgeDodge(p: Player, rootPos: Vector3, cf: CFrame)
	local S = Cfg.Sweep
	local loc = cf:PointToObjectSpace(rootPos)
	local off = Vector2.new(math.max(math.abs(loc.X) - S.Width / 2, 0), math.max(math.abs(loc.Y) - S.Height / 2, 0)).Magnitude
	if off <= 0 or off > S.DodgeRange then return end
	p:SetAttribute("Cash", (tonumber(p:GetAttribute("Cash")) or 0) + S.DodgeReward)
	FX.coins(p, S.DodgeReward, rootPos)
	FX.popup(p, "+DODGE", rootPos + Vector3.new(0, 3, 0), GOLD)
end

-- Registers its cleanup on the saucer while it runs, so a saucer destroyed mid-sweep never strands
-- a red line.
local function sweep(self: Fields, model: Model, root: BasePart, target: BasePart)
	local S = Cfg.Sweep
	local home = root.Position
	local hover = home.Y
	local floor = floorBelow(target.Position + Vector3.new(0, 2, 0), model)
	local y = if floor then floor.Y else target.Position.Y - 3
	local flat = (target.Position - home) * Vector3.new(1, 0, 1)
	local dir = if flat.Magnitude > 1 then flat.Unit else Vector3.xAxis -- the route points from the saucer through the player
	local length = S.Length
	local centre = Vector3.new(target.Position.X, y + S.Height / 2, target.Position.Z)
	if model:GetAttribute("FullWidth") == true then
		-- the eagle's pass: the line crosses the whole open layer, edge to edge, through the player
		local lo, hi = layerSpan(target.Position, dir)
		if lo and hi then
			length = (hi - lo) + Demolition.BlockSize() + 2 * S.EdgeMargin
			centre += dir * ((lo + hi) / 2)
		end
	end
	local cf = CFrame.lookAt(centre, centre + dir)
	local size = Vector3.new(S.Width, S.Height, length) -- the line runs along the CFrame's look axis
	local nearEnd = centre - dir * (length / 2)
	local farEnd = centre + dir * (length / 2)
	local nearPos = Vector3.new(nearEnd.X, hover, nearEnd.Z)
	-- the pass starts after the flight to the near end (flyTo's own tween time) or GraceSeconds, whichever is longer
	local lead = math.max(S.GraceSeconds, math.max(0.1, (nearPos - root.Position).Magnitude / S.FlySpeed))

	-- telegraph (Shayan 2026-09-29: a light, not a red box): a thin glowing strip lying on the blocks along
	-- the route, lit from below, flaring during the pass. UFOFX pulses it from PassAt (faster as the pass
	-- nears). The damage zone is still the full Width x Height x length box (cf / size); only the look changed.
	local line = Instance.new("Part")
	line.Name = "UFOLine"
	line.Size = Vector3.new(S.Width, 0.3, length)
	line.CFrame = cf * CFrame.new(0, -S.Height / 2 + 0.2, 0)
	line.Anchored = true
	line.CanCollide = false
	line.CanQuery = false
	line.CanTouch = false
	line.CastShadow = false
	line.Color = S.LineColor
	line.Material = Enum.Material.Neon
	line.Transparency = 0.3
	line:SetAttribute("PassAt", workspace:GetServerTimeNow() + lead) -- before parenting: the client reads it on arrival
	local glow = Instance.new("SurfaceLight")
	glow.Face = Enum.NormalId.Top
	glow.Color = S.LineColor
	glow.Brightness = 3
	glow.Range = 10
	glow.Angle = 120
	glow.Parent = line
	line.Parent = hazards
	local function cleanup()
		line:Destroy()
		self.cleanup = nil
	end
	self.cleanup = cleanup
	task.delay(math.max(0, lead - Snd.CommitLead), function()
		if line.Parent and root.Parent then sound(Snd.Commit, root) end
	end)

	-- fly to the near end; the line stays red at least GraceSeconds either way
	local t0 = os.clock()
	flyTo(root, nearPos, S.FlySpeed)
	local left = lead - (os.clock() - t0)
	if left > 0 then task.wait(left) end

	-- the pass: damage each player the moment the saucer passes over them; the ones it passes close to
	-- without hitting get the near-miss reward
	line.Transparency = 0.05
	glow.Brightness = 8
	local hit: { [Player]: boolean } = {}
	local judged: { [Player]: boolean } = {}
	local passing = TweenService:Create(root, TweenInfo.new(length / S.PassSpeed, Enum.EasingStyle.Linear), { CFrame = CFrame.new(farEnd.X, hover, farEnd.Z) * root.CFrame.Rotation })
	passing:Play()
	while passing.PlaybackState == Enum.PlaybackState.Playing and root.Parent do
		local progress = (root.Position - centre):Dot(dir) -- how far along the route the saucer is
		lineBox.FilterDescendantsInstances = characters()
		for _, part in ipairs(workspace:GetPartBoundsInBox(cf, size, lineBox)) do
			local m = part:FindFirstAncestorOfClass("Model")
			local p = m and Players:GetPlayerFromCharacter(m)
			if p and not hit[p] then
				local pr = (m :: Model):FindFirstChild("HumanoidRootPart")
				local along = if pr and pr:IsA("BasePart") then (pr.Position - centre):Dot(dir) else -math.huge
				if along <= progress then
					hit[p] = true
					local hum = (m :: Model):FindFirstChildOfClass("Humanoid")
					if hum and hum.Health > 0 then
						hum:TakeDamage(S.Damage)
					end
				end
			end
		end
		-- judged once, the frame the saucer passes them (after the hit check above), only beside the line
		for _, p in ipairs(Players:GetPlayers()) do
			local char = p.Character
			local pr = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if not hit[p] and not judged[p] and pr and pr:IsA("BasePart") and hum and hum.Health > 0 then
				local along = (pr.Position - centre):Dot(dir)
				if along >= -length / 2 and along <= progress then
					judged[p] = true
					judgeDodge(p, pr.Position, cf)
				end
			end
		end
		RunService.Heartbeat:Wait()
	end
	cleanup()
	if model:GetAttribute("LeaveWhenDone") ~= true then flyTo(root, home, S.FlySpeed) end -- a visitor leaves from the far end
end

-- the attack is chosen: a sting and a popup to everyone at the saucer (the HUD flash stays the visit's)
local function announce(model: Model, root: BasePart?, kind: string)
	sound(if kind == "Sweep" then Snd.StingSweep else Snd.StingDrop, root or model)
	FX.popup("all", if kind == "Sweep" then "UFO: SWEEP!" else "UFO: ABDUCTION!", model:GetPivot().Position, RED)
end

-- ---- one saucer ----

local Saucer = {}
Saucer.__index = Saucer

function Saucer.new(model: Model, fixed: string?) -- fixed: "Sweep" or "Drop" from the model's tag
	local self = setmetatable({ model = model, thread = nil, cleanup = nil } :: Fields, Saucer)
	local root = model.PrimaryPart
	if not root or not root.Anchored then
		warn(("[UFO] %s needs an anchored PrimaryPart to fly; it will only drop larvae"):format(model:GetFullName()))
	end
	local interval = tonumber(model:GetAttribute("Interval")) or Cfg.Interval
	local radius = tonumber(model:GetAttribute("ActivationRadius")) or Cfg.ActivationRadius
	local maxAttacks = tonumber(model:GetAttribute("MaxAttacks")) or Cfg.MaxAttacks
	local dropCount = tonumber(model:GetAttribute("DropCount")) or Cfg.Drop.Count
	self.thread = task.spawn(function()
		local attacks = 0
		while maxAttacks <= 0 or attacks < maxAttacks do
			task.wait(interval)
			local target = nearestRoot(model:GetPivot().Position, radius)
			if not target then continue end
			attacks += 1
			local kind = fixed or (model:GetAttribute("Attack") :: string?) or pickAttack() -- a DamageUFO / LarvaUFO tag or a visit fixes the kind
			if kind == "Sweep" and not (root and root.Anchored) then kind = "Drop" end
			announce(model, root, kind)
			if kind == "Sweep" and root then
				sweep(self, model, root, target) -- inline: the next attack waits until the saucer is home again
			else
				local W = Cfg.Drop.WindupSeconds
				task.delay(math.max(0, W - Snd.CommitLead), function()
					if model.Parent then sound(Snd.Commit, root or model) end
				end)
				task.wait(W)
				drop(model, dropCount)
			end
		end
		if model:GetAttribute("LeaveWhenDone") == true then
			if root and root.Anchored then flyTo(root, root.Position + Vector3.new(0, Cfg.Visit.EntryHeight, 0), Cfg.Visit.LeaveSpeed) end
			self.thread = nil -- this thread is the one destroying the model: nothing left to cancel
			model:Destroy()
			return
		end
		self.thread = nil
	end)
	return self
end

function Saucer.Destroy(self: Fields)
	if self.thread then
		task.cancel(self.thread)
		self.thread = nil
	end
	if self.cleanup then self.cleanup() end -- removed mid-sweep: clear the line
end

TagBinder.bind(Tags.UFO, function(inst) return Saucer.new(inst :: Model) end)
TagBinder.bind(Tags.DamageUFO, function(inst) return Saucer.new(inst :: Model, "Sweep") end) -- Damage-UFO: red line only
TagBinder.bind(Tags.LarvaUFO, function(inst) return Saucer.new(inst :: Model, "Drop") end)   -- Larva-UFO: larvae only

-- ---- visits: how a UFO arrives in a real run (the reference's eagle) ----
local V = Cfg.Visit
local current: Model? = nil

-- a random living player who has finished the brief
local function randomTarget(): BasePart?
	local list: { BasePart } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and hum and hum.Health > 0 and p:GetAttribute("BriefComplete") == true then table.insert(list, root) end
	end
	return if #list > 0 then list[rng:NextInteger(1, #list)] else nil
end

-- world height of the open layer's top face
local function layerTop(): number?
	local kaiju = Demolition.GetKaiju()
	local active = RunState:GetAttribute("ActiveLayer")
	local origin = kaiju and kaiju:GetAttribute("Origin")
	if typeof(active) ~= "number" or typeof(origin) ~= "Vector3" then return nil end
	local B = Demolition.BlockSize()
	return origin.Y + active * B + B / 2
end

-- studs from the model's root down to the bottom of its "Kaiju-Skin-Identify" part (Shayan's marker at
-- the foot of the Larva-UFO's beam: it is what touches the kaiju skin), else the "Beam" mesh's foot
local function beamFootDrop(model: Model): number
	local root = model.PrimaryPart
	local beam = model:FindFirstChild("Kaiju-Skin-Identify", true) or model:FindFirstChild("Beam", true)
	if not root or not beam or not beam:IsA("BasePart") then return V.HoverHeight end
	local c = beam.CFrame
	local half = math.abs(c.UpVector.Y) * beam.Size.Y / 2 + math.abs(c.RightVector.Y) * beam.Size.X / 2 + math.abs(c.LookVector.Y) * beam.Size.Z / 2
	return root.Position.Y - (beam.Position.Y - half)
end

-- a circle around the open layer (centre, radius, height) for the arrival lap, or nil
local function layerCircle(): (Vector3?, number?)
	local active = RunState:GetAttribute("ActiveLayer")
	if typeof(active) ~= "number" then return nil, nil end
	local B = Demolition.BlockSize()
	local list, sum = {}, Vector3.zero
	for _, h in ipairs(Demolition.AllBlockHolders()) do
		if h:GetAttribute("BY") == active and h:GetAttribute("Adopted") ~= true then
			local c = Demolition.CenterOf(h)
			if c then table.insert(list, c); sum += c end
		end
	end
	if #list == 0 then return nil, nil end
	local centre = sum / #list
	local r = 0
	for _, c in ipairs(list) do r = math.max(r, Vector3.new(c.X - centre.X, 0, c.Z - centre.Z).Magnitude) end
	return Vector3.new(centre.X, 0, centre.Z), r + B / 2 + V.OrbitMargin
end

-- the arrival: down onto the circle, round it for OrbitSeconds (turning with the spin), then on to `hover`
local function arrive(model: Model, root: BasePart, hover: Vector3)
	local centre, r = layerCircle()
	if centre and r then
		local y = hover.Y + V.OrbitRise
		local a = math.atan2(hover.Z - centre.Z, hover.X - centre.X) + math.pi -- start on the far side of the circle
		local function at(angle: number) return centre + Vector3.new(math.cos(angle) * r, y, math.sin(angle) * r) end
		root.CFrame = CFrame.new(at(a) + Vector3.new(0, V.EntryHeight, 0)) * root.CFrame.Rotation
		flyTo(root, at(a), V.ArriveSpeed)
		local w = V.OrbitSpeed / math.max(r, 1)
		local t0 = os.clock()
		while model.Parent and os.clock() - t0 < V.OrbitSeconds do
			local dt = RunService.Heartbeat:Wait()
			a += w * dt
			root.CFrame = CFrame.new(at(a)) * root.CFrame.Rotation
		end
	end
	if model.Parent then flyTo(root, hover, V.ArriveSpeed) end
end

local function visit(): boolean -- false = nobody to visit yet (no briefed, living player)
	local target = randomTarget()
	local templates = ServerStorage:FindFirstChild("Templates")
	if not target or not templates then return false end
	local top = layerTop() or target.Position.Y
	local kind = pickAttack()
	local template = templates:FindFirstChild(if kind == "Drop" then "Larva-UFO" else "Damage-UFO") or templates:FindFirstChild("UFO")
	if not template then return false end
	local a = rng:NextNumber(0, 2 * math.pi)
	local offset = if kind == "Drop" then 0 else V.Offset -- larvae land at the player; a sweep needs a direction
	local hover = Vector3.new(target.Position.X + math.cos(a) * offset, top + V.HoverHeight, target.Position.Z + math.sin(a) * offset)
	local model = template:Clone() :: Model
	model.Name = "UFO"
	if kind == "Drop" then
		-- a larva visit comes down until the foot of its tractor beam touches the kaiju skin under the
		-- player (Shayan 2026-09-28): hover = the surface there + the root's height above the beam's foot
		local floor = floorBelow(Vector3.new(hover.X, top + V.EntryHeight, hover.Z), model)
		if floor then hover = Vector3.new(hover.X, floor.Y + beamFootDrop(model) + V.BeamGap, hover.Z) end
	end
	model:PivotTo(CFrame.new(hover + Vector3.new(0, V.EntryHeight, 0)))
	model:SetAttribute("Interval", V.AttackInterval)
	model:SetAttribute("MaxAttacks", V.Attacks)
	model:SetAttribute("ActivationRadius", V.ActivationRadius)
	model:SetAttribute("LeaveWhenDone", true)
	model:SetAttribute("Attack", kind)
	model:SetAttribute("FullWidth", true)
	model:SetAttribute("DropCount", rng:NextInteger(V.DropMin, V.DropMax))
	model:SetAttribute("SpinSpeed", V.SpinDegreesPerSecond)
	model.Parent = workspace
	current = model
	-- the warning: the HUD's event flash reads "EVENT: UFO INCOMING!"
	RunState:SetAttribute("LastEvent", "UFO incoming!")
	RunState:SetAttribute("EventCount", (tonumber(RunState:GetAttribute("EventCount")) or 0) + 1)
	local root = model.PrimaryPart
	local hum = if root then sound(Snd.Hum, root, true, Snd.HumVolume) else nil -- the arrival hum, on while it descends and circles
	if root and root.Anchored then arrive(model, root, hover) end
	if hum then hum:Destroy() end
	if model.Parent then model:AddTag(if kind == "Drop" then Tags.LarvaUFO else Tags.DamageUFO) end -- Saucer takes over from here
	return true
end

task.spawn(function()
	local nextAt = os.clock() + V.FirstAfter
	while true do
		task.wait(1)
		if RunState:GetAttribute("State") ~= "Running" then
			-- a run that ended takes its UFO with it; the next run starts the clock again
			if current and current.Parent then current:Destroy() end
			current = nil
			nextAt = os.clock() + V.FirstAfter
		elseif current and current.Parent then
			nextAt = os.clock() + rng:NextNumber(V.IntervalMin, V.IntervalMax) -- the gap counts from when it leaves
		elseif os.clock() >= nextAt then
			current = nil
			-- nobody to visit (everyone still in the brief, or down): try again shortly instead of a whole interval later
			nextAt = if visit() then os.clock() + rng:NextNumber(V.IntervalMin, V.IntervalMax) else os.clock() + 5
		end
	end
end)

return true
