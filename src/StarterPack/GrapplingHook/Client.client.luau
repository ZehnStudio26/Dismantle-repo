--!strict
-- GrapplingHook client (Shayan 2026-10-01): the grappling hook tool, hotbar slot 4 (key 4). Aim at a kaiju
-- block, click / tap, the hook latches at the hit point and pulls you there, heavy rather than twitchy.
-- Numbers: ReplicatedStorage.Config.HookConfig.
--   Input    Tool.Activated while equipped. PC aims at the mouse cursor; touch aims at the tap that activated
--            the tool (the last unprocessed TouchStarted within TouchAimWindow), else the screen centre.
--            Jump cancels a pull; putting the tool away ends it.
--            Not while Down, in TopView, or with the Cutscene / Results screen up.
--   Throw    the aim ray only sees Workspace.Kaiju; a hit within MinRange..Range with a clear line from the
--            root (the server's own test) is a real throw: Remotes.Grapple "Fire" goes at once and a
--            client-only head flies from the Right Arm's RightGripAttachment at ThrowSpeed on a slack Beam
--            rope. Anything else (no block, too far, too near, blocked) throws and retracts, no remote.
--            The server's "Deny" retracts too.
--   Pull     on arrival the rope goes taut, the FOV kicks, the camera shakes a little, then WindUp seconds
--            of slow pull with a lift. The client owns its root, so it pulls: Humanoid in Physics (only the
--            owner can), FallingDown / Ragdoll off, AutoRotate off, a LinearVelocity at RootAttachment with a
--            finite mass-based MaxForce (math.huge flings off walls), an AlignOrientation facing the flat pull
--            direction (R6 twists otherwise). Each Heartbeat:
--              speed = min(speed + Accel*dt, MaxSpeed, sqrt(2*Decel*(dist - StopDist)))   (brakes, no overshoot)
--            The FOV widens with speed; the offset is added at Camera+20 (after the chainsaw / handgun camera
--            steps at Camera+1) and taken off again at First, so their own FOV easing never sees it.
--   Release  arrival (a small hop), jump (keeps JumpKeep of the speed plus JumpBoost up), the hooked part cut
--            away (a block cracking into chunks re-latches onto the chunk at the same point; otherwise keeps
--            AnchorLostKeep of the speed), something solid ahead (spherecast: stop), stuck against a wall,
--            the time limit, falling near FallenPartsDestroyHeight, death, Down / TopView / Cutscene / Results,
--            the tool put away, the server's "Release". Movers go, Freefall, states and AutoRotate back, FOV
--            eases back, "Release" to the server, Cooldown starts. The head flies back to the hand.
--   Cooldown a dark fill over hotbar Slot4 (StarterGui.Hotbar.Bar.Slot4.Cooldown, authored in Studio), Hydrated
--            here: full while the hook is out, shrinking to nothing as the cooldown runs.
-- Other players' ropes are drawn by StarterPlayerScripts.GrappleRopes.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Fusion)
local Cfg = require(ReplicatedStorage.Config.HookConfig)
local Grapple = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Grapple") :: RemoteEvent

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local kaiju = workspace:WaitForChild("Kaiju")
local tool = script.Parent :: Tool
local handle = tool:WaitForChild("Handle") :: BasePart
local fill = pg:WaitForChild("Hotbar"):WaitForChild("Bar"):WaitForChild("Slot4"):WaitForChild("Cooldown") :: Frame

local rng = Random.new()

-- ---------- helpers ----------
local function body(): (Model?, Humanoid?, BasePart?)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local r = c and c:FindFirstChild("HumanoidRootPart")
	if not h or h.Health <= 0 or not r or not r:IsA("BasePart") then return nil, nil, nil end
	return c, h, r
end

local function guiOn(name: string): boolean
	local g = pg:FindFirstChild(name)
	return g ~= nil and g:IsA("ScreenGui") and g.Enabled
end

-- the hook is off while any of these hold
local function blocked(): boolean
	return player:GetAttribute("Down") == true or player:GetAttribute("TopView") == true or guiOn("Cutscene") or guiOn("Results")
end

-- the R6 hand the rope leaves from
local function gripOf(c: Model?): Attachment?
	local arm = c and (c:FindFirstChild("Right Arm") or c:FindFirstChild("RightHand"))
	local a = arm and arm:FindFirstChild("RightGripAttachment")
	return if a and a:IsA("Attachment") then a else nil
end

-- the logical block a kaiju part belongs to: a cracked block Model or the intact block Part
local function holderOf(p: Instance): Instance
	local parent = p.Parent
	return if parent and parent ~= kaiju and parent.Parent == kaiju then parent else p
end

local function quadOut(x: number): number
	local t = math.clamp(x, 0, 1)
	return 1 - (1 - t) * (1 - t)
end

local function characters(): { Instance }
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(list, p.Character) end
	end
	return list
end

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Include
aimParams.FilterDescendantsInstances = { kaiju }

local sightParams = RaycastParams.new()
sightParams.FilterType = Enum.RaycastFilterType.Exclude
sightParams.RespectCanCollide = true

local castParams = RaycastParams.new()
castParams.FilterType = Enum.RaycastFilterType.Exclude
castParams.RespectCanCollide = true -- trigger volumes (gas, pickups) never stop a pull

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
overlap.FilterDescendantsInstances = { kaiju }

-- a kaiju part at (within RelatchRadius of) a world point: what is left of a block that cracked under the hook
local function partAt(pos: Vector3): BasePart?
	for _, p in ipairs(workspace:GetPartBoundsInRadius(pos, Cfg.RelatchRadius, overlap)) do
		if p.Parent then return p end
	end
	return nil
end

-- same test as Server.Hook: nothing solid between the root and the hit point but that block
local function clearLine(from: Vector3, to: Vector3, part: BasePart): boolean
	sightParams.FilterDescendantsInstances = characters()
	local d = to - from
	local hit = workspace:Raycast(from, d.Unit * (d.Magnitude + 1), sightParams)
	return hit == nil or holderOf(hit.Instance) == holderOf(part) or (hit.Position - to).Magnitude <= Cfg.LineSlack
end

-- the aim ray: the mouse cursor; on touch the tap that activated the tool, or the screen centre
local lastTap, lastTapAt = Vector2.zero, -math.huge
local function aimRay(cam: Camera): Ray
	if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then
		if os.clock() - lastTapAt <= Cfg.TouchAimWindow then return cam:ScreenPointToRay(lastTap.X, lastTap.Y) end -- GUI space
		return cam:ViewportPointToRay(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
	end
	local mouse = UserInputService:GetMouseLocation() -- viewport space, as the chainsaw aims
	return cam:ViewportPointToRay(mouse.X, mouse.Y)
end

-- the block under the aim: its part and the hit point, or nil and where a miss flies
local function aim(root: BasePart): (BasePart?, Vector3)
	local ray = aimRay(workspace.CurrentCamera)
	local dir = ray.Direction.Unit
	local far = (root.Position - ray.Origin).Magnitude + Cfg.Range
	local hit = workspace:Raycast(ray.Origin, dir * far, aimParams)
	local point = if hit then hit.Position else ray.Origin + dir * far
	local d = (point - root.Position).Magnitude
	local part = if hit and hit.Instance:IsA("BasePart") then hit.Instance :: BasePart else nil
	if part and d >= Cfg.MinRange and d <= Cfg.Range and clearLine(root.Position, point, part) then
		return part, point
	end
	if d < 0.01 then return nil, root.Position + dir * Cfg.MinRange end
	return nil, root.Position + (point - root.Position) / d * math.min(d, Cfg.Range)
end

-- ---------- visuals (client only) ----------
local function makeRope(a0: Attachment?, a1: Attachment): Beam
	local b = Instance.new("Beam")
	b.Name = "GrappleRope"
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Width0, b.Width1 = Cfg.RopeWidth, Cfg.RopeWidth
	b.Segments = 24
	b.FaceCamera = true
	b.LightInfluence = 1
	b.Texture = ""
	b.Color = ColorSequence.new(Cfg.RopeColor)
	b.Transparency = NumberSequence.new(0)
	return b
end

local head = Instance.new("Part")
head.Name = "GrappleHead"
head.Anchored = true
head.CanCollide = false
head.CanQuery = false
head.CanTouch = false
head.CastShadow = false
head.Size = Cfg.HeadSize
head.Color = Cfg.HeadColor
head.Material = Enum.Material.Metal
local headMesh = Instance.new("SpecialMesh") -- the gear's hook (HookConfig.Mesh)
headMesh.MeshType = Enum.MeshType.FileMesh
headMesh.MeshId = Cfg.Mesh.Hook
headMesh.TextureId = Cfg.Mesh.Texture
headMesh.Scale = Cfg.Mesh.Scale
headMesh.Parent = head
-- the gear's sounds: Fire from the launcher on a throw, Hit and Connect where the hook bites
local fireSound = handle:FindFirstChild("Fire") :: Sound?
local latchSounds: { Sound } = {}
for _, name in ipairs({ "Hit", "Connect" }) do
	local s = handle:FindFirstChild(name)
	if s and s:IsA("Sound") then
		local copy = s:Clone()
		copy.Parent = head
		table.insert(latchSounds, copy)
	end
end
local launcher = handle:FindFirstChildOfClass("SpecialMesh")
local headAtt = Instance.new("Attachment")
headAtt.Name = "Rope"
headAtt.Position = Vector3.new(0, 0, Cfg.HeadSize.Z / 2) -- the back end; the head flies -Z first
headAtt.Parent = head
local rope = makeRope(nil, headAtt)
rope.Parent = head

local function placeHead(pos: Vector3, facing: Vector3)
	head.CFrame = if facing.Magnitude > 1e-3 then CFrame.lookAt(pos, pos + facing) else CFrame.new(pos)
end

local function slack(amount: number)
	rope.CurveSize0, rope.CurveSize1 = amount, -amount
end

-- ---------- state ----------
type Phase = "Idle" | "Throw" | "Retract" | "Pull"
type Pull = {
	hum: Humanoid,
	root: BasePart,
	movers: { Instance },
	lv: LinearVelocity,
	ao: AlignOrientation,
	falling: boolean,
	ragdoll: boolean,
	autoRotate: boolean,
}
local phase: Phase = "Idle"
local owner: Model? = nil       -- the character that threw (a respawn ends everything)
local valid = false             -- this throw went to the server
local target: BasePart? = nil   -- the hooked part (nil once it is gone)
local offset = Vector3.zero     -- the hook point in target's space
local hookPoint = Vector3.zero  -- the hook point in the world (kept when the part goes)
local lostAt: number? = nil
local headPos = Vector3.zero
local cooldownEnd = 0
local pull: Pull? = nil
local speed, pullDir = 0, Vector3.zero
local latchedAt, pullDeadline, stuckFor = 0, 0, 0
-- camera
local fovOffset = 0
local releasedAt, releasedFov = -math.huge, 0
local shakeUntil = -math.huge

-- the flying pose (HookConfig.PullAnimation): loops on the character's Animator for the whole pull; loaded
-- once per character, and other players see it because the character's animations replicate
local pullAnim = Instance.new("Animation")
pullAnim.AnimationId = Cfg.PullAnimation
local pullTrack: AnimationTrack? = nil
local trackHum: Humanoid? = nil
local function poseOn(h: Humanoid)
	if trackHum ~= h then
		trackHum, pullTrack = h, nil
		local animator = h:FindFirstChildOfClass("Animator")
		if animator then
			local ok, t = pcall(function() return animator:LoadAnimation(pullAnim) end)
			if ok then
				t.Priority = Enum.AnimationPriority.Action4 -- over the tool hold and the default animations
				t.Looped = true
				pullTrack = t
			end
		end
	end
	if pullTrack then pullTrack:Play(Cfg.PullAnimFade) end
end
local function poseOff()
	if pullTrack and pullTrack.IsPlaying then pullTrack:Stop(Cfg.PullAnimFade) end
end

local function anchorPoint(): Vector3
	local t = target
	if t and t.Parent then hookPoint = t.CFrame:PointToWorldSpace(offset) end
	return hookPoint
end

local function setTarget(part: BasePart?)
	target = part
	if part then offset = part.CFrame:PointToObjectSpace(hookPoint) end
	local list: { Instance } = {}
	if player.Character then table.insert(list, player.Character :: Model) end
	if part then table.insert(list, holderOf(part)) end
	castParams.FilterDescendantsInstances = list
end

local function handPos(root: BasePart): Vector3
	local grip = gripOf(player.Character)
	return if grip then grip.WorldPosition else root.Position
end

-- ---------- ending ----------
-- how: "arrive" | "jump" | "lost" | "stop" | "keep" | "deny" (server refused) | "server" (server ended it) | "dead"
local function finish(how: string)
	local now = os.clock()
	local p = pull
	pull = nil
	if p then
		poseOff()
		for _, m in ipairs(p.movers) do m:Destroy() end
		local h, r = p.hum, p.root
		if h.Parent and h.Health > 0 then
			h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, p.falling)
			h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, p.ragdoll)
			h.AutoRotate = p.autoRotate
			local v = r.AssemblyLinearVelocity
			if how == "arrive" then
				r.AssemblyLinearVelocity = pullDir * Cfg.ArriveForward + Vector3.yAxis * Cfg.ArriveUp
			elseif how == "jump" then
				r.AssemblyLinearVelocity = v * Cfg.JumpKeep + Vector3.yAxis * Cfg.JumpBoost
			elseif how == "lost" then
				r.AssemblyLinearVelocity = v * Cfg.AnchorLostKeep
			elseif how == "stop" then
				r.AssemblyLinearVelocity = Vector3.zero
			end
			h:ChangeState(Enum.HumanoidStateType.Freefall)
		end
		releasedAt, releasedFov = now, fovOffset
	end
	if valid then
		if how ~= "deny" and how ~= "server" then Grapple:FireServer("Release") end
		if how ~= "deny" then cooldownEnd = now + Cfg.Cooldown end
	end
	valid = false
	target = nil
	lostAt = nil
	if how == "dead" then
		head.Parent = nil
		phase = "Idle"
	else
		slack(Cfg.RopeSlack)
		phase = "Retract"
	end
end

-- ---------- throw ----------
local function throw()
	if phase ~= "Idle" or os.clock() < cooldownEnd or blocked() then return end
	local c, h, r = body()
	if not c or not h or not r or h.SeatPart or tool.Parent ~= c then return end
	local part, point = aim(r)
	hookPoint = point
	valid = part ~= nil
	setTarget(part)
	if part then Grapple:FireServer("Fire", part, point) end
	owner = c
	rope.Attachment0 = gripOf(c) or r:FindFirstChildOfClass("Attachment")
	headPos = handPos(r)
	slack(Cfg.RopeSlack)
	placeHead(headPos, point - headPos)
	head.Parent = workspace
	if fireSound then fireSound:Play() end
	phase = "Throw"
end

local function latch(h: Humanoid, r: BasePart)
	local now = os.clock()
	for _, s in ipairs(latchSounds) do s:Play() end
	poseOn(h)
	phase = "Pull"
	latchedAt, speed, stuckFor = now, Cfg.WindUpSpeed, 0
	shakeUntil = now + Cfg.ShakeSeconds
	releasedAt = -math.huge
	local delta = anchorPoint() - r.Position
	pullDir = if delta.Magnitude > 1e-3 then delta.Unit else Vector3.zero
	pullDeadline = now + Cfg.WindUp + delta.Magnitude / Cfg.MaxSpeed * Cfg.PullTimeFactor + Cfg.PullTimeExtra
	local movers: { Instance } = {}
	local att = r:FindFirstChild("RootAttachment")
	if not att or not att:IsA("Attachment") then
		att = Instance.new("Attachment")
		att.Name = "HookRoot"
		att.Parent = r
		table.insert(movers, att :: Instance)
	end
	local lv = Instance.new("LinearVelocity")
	lv.Name = "HookPull"
	lv.Attachment0 = att :: Attachment
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	lv.MaxForce = r.AssemblyMass * (Cfg.Accel + workspace.Gravity) * Cfg.ForceFactor
	lv.VectorVelocity = pullDir * Cfg.WindUpSpeed + Vector3.yAxis * Cfg.WindUpLift
	lv.Parent = r
	local ao = Instance.new("AlignOrientation")
	ao.Name = "HookFacing"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att :: Attachment
	ao.Responsiveness = Cfg.TurnResponsiveness
	ao.MaxTorque = Cfg.TurnMaxTorque
	local flat = Vector3.new(pullDir.X, 0, pullDir.Z)
	ao.CFrame = if flat.Magnitude > 0.1 then CFrame.lookAt(Vector3.zero, flat) else r.CFrame.Rotation
	ao.Parent = r
	table.insert(movers, lv)
	table.insert(movers, ao)
	pull = {
		hum = h, root = r, movers = movers, lv = lv, ao = ao,
		falling = h:GetStateEnabled(Enum.HumanoidStateType.FallingDown),
		ragdoll = h:GetStateEnabled(Enum.HumanoidStateType.Ragdoll),
		autoRotate = h.AutoRotate,
	}
	h:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	h:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	h.AutoRotate = false
	h:ChangeState(Enum.HumanoidStateType.Physics)
end

-- the hooked part went (cut, or cracked into chunks): look for kaiju material at the hook point for
-- RelatchWindow seconds. Returns false when the hook has nothing left to hold.
local function holdAnchor(now: number): boolean
	local t = target
	if t and not t:IsDescendantOf(kaiju) then
		target = nil
		lostAt = now
	end
	if target then return true end
	local again = partAt(hookPoint)
	if again then
		setTarget(again)
		lostAt = nil
		return true
	end
	return now - (lostAt or now) <= Cfg.RelatchWindow
end

local function throwStep(r: BasePart, dt: number)
	local now = os.clock()
	if valid and (blocked() or not holdAnchor(now)) then finish("keep") return end
	local goal = anchorPoint()
	local delta = goal - headPos
	local step = Cfg.ThrowSpeed * dt
	if delta.Magnitude <= step then
		headPos = goal
		placeHead(goal, delta)
		local _, h = body()
		if valid and h then latch(h, r) else finish("keep") end
		return
	end
	headPos += delta.Unit * step
	placeHead(headPos, delta)
end

local function retractStep(r: BasePart, dt: number)
	local goal = handPos(r)
	local delta = goal - headPos
	local step = Cfg.RetractSpeed * dt
	if delta.Magnitude <= step then
		head.Parent = nil
		phase = "Idle"
		return
	end
	headPos += delta.Unit * step
	placeHead(headPos, -delta)
end

local function pullStep(p: Pull, dt: number)
	local now = os.clock()
	if blocked() then finish("keep") return end
	if not holdAnchor(now) then finish("lost") return end
	local goal = anchorPoint()
	local r = p.root
	local delta = goal - r.Position
	local dist = delta.Magnitude
	if dist <= Cfg.StopDist then finish("arrive") return end
	pullDir = delta / dist
	if now > pullDeadline or r.Position.Y < workspace.FallenPartsDestroyHeight + Cfg.FallMargin then finish("keep") return end
	-- the rope tightens over RopeTightenTime; the head sits at the hook point facing away from the hand
	slack(Cfg.RopeSlack * (1 - math.clamp((now - latchedAt) / Cfg.RopeTightenTime, 0, 1)))
	placeHead(goal, goal - handPos(r))
	local flat = Vector3.new(pullDir.X, 0, pullDir.Z)
	if flat.Magnitude > 0.1 then p.ao.CFrame = CFrame.lookAt(Vector3.zero, flat) end
	if now - latchedAt < Cfg.WindUp then
		speed = Cfg.WindUpSpeed
		p.lv.VectorVelocity = pullDir * speed + Vector3.yAxis * Cfg.WindUpLift
		return
	end
	speed = math.min(speed + Cfg.Accel * dt, Cfg.MaxSpeed, math.sqrt(2 * Cfg.Decel * math.max(dist - Cfg.StopDist, 0)))
	-- something solid head-on ahead that is not the hooked block (or right at the hook point): stop. A grazing
	-- hit (a wall you slide up along) is left to the stuck test.
	local hit = workspace:Spherecast(r.Position, Cfg.BlockRadius, pullDir * (speed * dt + Cfg.BlockLookahead), castParams)
	if hit and hit.Normal:Dot(pullDir) < -0.5 and (hit.Position - goal).Magnitude > Cfg.StopDist + 2 then finish("stop") return end
	p.lv.VectorVelocity = pullDir * speed
	-- stuck: pushing but not moving along the rope
	if speed > Cfg.StuckMinSpeed and r.AssemblyLinearVelocity:Dot(pullDir) < Cfg.StuckRatio * speed then
		stuckFor += dt
		if stuckFor >= Cfg.StuckTime then finish("stop") return end
	else
		stuckFor = 0
	end
end

-- ---------- the cooldown on hotbar Slot4 (Fusion Hydrate over the authored Cooldown fill) ----------
local scope = Fusion.scoped(Fusion)
local busy = scope:Value(0) -- 1 = not available, falling to 0 as the cooldown runs out
scope:Hydrate(fill) {
	Size = scope:Computed(function(use) return UDim2.fromScale(1, use(busy)) end),
	Visible = scope:Computed(function(use) return use(busy) > 0 end),
}

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	if phase ~= "Idle" then
		local c, _, r = body()
		if not c or not r or c ~= owner then
			finish("dead")
		elseif phase == "Throw" then
			throwStep(r, dt)
		elseif phase == "Retract" then
			retractStep(r, dt)
		elseif phase == "Pull" and pull then
			pullStep(pull, dt)
		end
	end
	-- the launcher shows the hook loaded only while it is in hand (Server.Hook does the same for everyone else)
	local want = if phase == "Idle" then Cfg.Mesh.Loaded else Cfg.Mesh.Empty
	if launcher and launcher.MeshId ~= want then launcher.MeshId = want end
	local f = if phase == "Pull" or (phase == "Throw" and valid) or blocked() then 1 else math.clamp((cooldownEnd - now) / Cfg.Cooldown, 0, 1)
	busy:set(math.ceil(f * 50) / 50)
end)

-- ---------- camera: FOV offset and the latch shake, after every other camera step ----------
local fovApplied, fovWritten = 0, 0
local function undoFov()
	local cam = workspace.CurrentCamera
	-- take last frame's offset off, unless something set the FOV outright since
	if fovApplied ~= 0 and cam and math.abs(cam.FieldOfView - fovWritten) < 1e-3 then cam.FieldOfView -= fovApplied end
	fovApplied = 0
end
RunService:BindToRenderStep("GrapplingHookFovUndo", Enum.RenderPriority.First.Value, undoFov)
RunService:BindToRenderStep("GrapplingHookCamera", Enum.RenderPriority.Camera.Value + 20, function()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local now = os.clock()
	if pull then
		fovOffset = Cfg.FovKick * quadOut((now - latchedAt) / Cfg.FovKickTime) + Cfg.FovSpeed * speed / Cfg.MaxSpeed
	else
		fovOffset = releasedFov * (1 - quadOut((now - releasedAt) / Cfg.FovReturnTime))
	end
	if fovOffset > 1e-3 then
		cam.FieldOfView += fovOffset
		fovApplied, fovWritten = fovOffset, cam.FieldOfView
	end
	if now < shakeUntil then
		local d = Cfg.ShakeDegrees * (shakeUntil - now) / Cfg.ShakeSeconds
		cam.CFrame *= CFrame.Angles(math.rad(rng:NextNumber(-d, d)), math.rad(rng:NextNumber(-d, d)), 0)
	end
end)

-- ---------- input ----------
-- touch: remember where the last world tap landed (Activated itself carries no position)
UserInputService.TouchStarted:Connect(function(input, processed)
	if not processed then lastTap, lastTapAt = Vector2.new(input.Position.X, input.Position.Y), os.clock() end
end)
tool.Activated:Connect(throw)
tool.Unequipped:Connect(function()
	if phase == "Throw" or phase == "Pull" then finish("keep") end
end)
-- Space / the touch jump button; ignored during the wind-up so a jump still held from before does not cancel it
UserInputService.JumpRequest:Connect(function()
	if phase == "Pull" and os.clock() - latchedAt >= Cfg.WindUp then finish("jump") end
end)

-- ---------- the server's verdicts on our own throws (other players' ropes: StarterPlayerScripts.GrappleRopes) ----------
Grapple.OnClientEvent:Connect(function(action: string, who: unknown)
	if not valid then return end
	if action == "Deny" then
		finish("deny")
	elseif action == "Release" and who == player then
		finish("server")
	end
end)

-- the tool goes with the character (death, respawn): end the hook and leave the camera as it was
tool.Destroying:Connect(function()
	if phase ~= "Idle" then finish("dead") end
	RunService:UnbindFromRenderStep("GrapplingHookFovUndo")
	RunService:UnbindFromRenderStep("GrapplingHookCamera")
	undoFov()
	head:Destroy()
	scope:doCleanup()
end)
