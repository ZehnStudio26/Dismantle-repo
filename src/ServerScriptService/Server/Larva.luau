--!strict
-- Larva (EVT-06 / EVT-07, L-2): the brain of one larva. Egg builds the body and hands it here;
-- Enemies ticks every larva from one Heartbeat. Decide and execute run at different rates:
--   decide  at DecideHz: pick the nearest player in AggroRange, choose the state, repath on a TRIGGER
--   execute every frame: MoveTo the current waypoint, bite on cooldown
--
-- States, transitions inside decide():
--   Idle    nobody in range: drift back toward the hatch point past LeashRange, else stand
--   Chase   follow the cached path; recompute only when the target has moved RepathDistance from
--           where the path was computed, the path is exhausted, or the larva is stuck. Never on a clock:
--           per-larva pathfinding on a timer is the classic "NPCs lag as more spawn" shape.
--   Attack  in reach: a bite needs the target inside a box between the two AND line of sight to it,
--           so it can be sidestepped and cannot land through a block. Distance alone can do neither.
--   Dead    corpse lingers CorpseSeconds, then the model is destroyed. The last player to hit it
--           (Gun / Chainsaw through Enemies.Strike) is paid KillReward.
-- Hit reaction: hit() pushes the larva away from the attacker and freezes the brain for HitPause.

local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventConfig = require(ReplicatedStorage.Config.EventConfig)
local FX = require(script.Parent.FX)
local Cfg = EventConfig.Egg

type State = "Idle" | "Chase" | "Attack" | "Dead"

type Fields = {
	id: number,
	model: Model,
	hum: Humanoid,
	root: BasePart,
	home: Vector3,
	state: State,
	targetRoot: BasePart?,
	targetHum: Humanoid?,
	path: Path,
	waypoints: { PathWaypoint },
	wpIndex: number,
	pathFor: Vector3?,   -- target position the current path was computed for
	nextDecide: number,
	lastAttack: number,
	lastPos: Vector3,
	stuckSince: number,  -- last time the larva made progress
	pausedUntil: number, -- hit reaction: no decide / execute before this
	lastAttacker: Player?, -- paid KillReward on death
}

local Larva = {}
Larva.__index = Larva
export type Larva = typeof(setmetatable({} :: Fields, Larva))

local biteBox = OverlapParams.new()
biteBox.FilterType = Enum.RaycastFilterType.Include
local sight = RaycastParams.new()
sight.FilterType = Enum.RaycastFilterType.Include

function Larva.new(id: number, model: Model, hum: Humanoid, root: BasePart): Larva
	local now = os.clock()
	local self: Larva = setmetatable({
		id = id, model = model, hum = hum, root = root, home = root.Position,
		state = "Idle" :: State, targetRoot = nil, targetHum = nil,
		path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 4, AgentCanJump = true }),
		waypoints = {}, wpIndex = 0, pathFor = nil,
		nextDecide = 0, lastAttack = 0, lastPos = root.Position, stuckSince = now,
		pausedUntil = 0, lastAttacker = nil,
	}, Larva)
	hum.Died:Connect(function() self:die() end)
	return self
end

function Larva.alive(self: Larva): boolean
	return self.state ~= "Dead" and self.model.Parent ~= nil and self.hum.Health > 0
end

-- nearest living player within AggroRange, or nothing. A player still in the intro brief is not a
-- target (BriefComplete, set by Server.Brief), the same rule the drone and the UFO follow.
local function nearestPlayer(from: Vector3): (BasePart?, Humanoid?)
	local best: BasePart? = nil
	local bestHum: Humanoid? = nil
	local bestD = Cfg.AggroRange
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and hum and hum.Health > 0 and p:GetAttribute("BriefComplete") == true then
			local d = (root.Position - from).Magnitude
			if d < bestD then best, bestHum, bestD = root, hum, d end
		end
	end
	return best, bestHum
end

function Larva.repath(self: Larva, goal: Vector3)
	local ok = pcall(function() self.path:ComputeAsync(self.root.Position, goal) end)
	if ok and self.path.Status == Enum.PathStatus.Success then
		self.waypoints = self.path:GetWaypoints()
		self.wpIndex = math.min(2, #self.waypoints) -- waypoint 1 is where the larva already stands
	else
		-- no path: walk straight at the goal and let the stuck timer sort it out
		self.waypoints = {}
		self.wpIndex = 0
	end
	self.pathFor = goal
end

-- A bite lands only if the target overlaps a box between the larva and it AND nothing of the kaiju
-- is in the way. The box is aimed from larva to target, so which way the body faces is irrelevant.
function Larva.canBite(self: Larva): boolean
	local tr, th = self.targetRoot, self.targetHum
	if not tr or not th or th.Health <= 0 or not tr.Parent then return false end
	local from, to = self.root.Position, tr.Position
	local dir = to - from
	local dist = dir.Magnitude
	if dist > Cfg.AttackRange then return false end
	if dist < 0.5 then return true end -- inside each other; lookAt would degenerate
	local cf = CFrame.lookAt(from, to) * CFrame.new(0, 0, -Cfg.AttackBox.Z / 2)
	biteBox.FilterDescendantsInstances = { tr.Parent :: Instance }
	if #workspace:GetPartBoundsInBox(cf, Cfg.AttackBox, biteBox) == 0 then return false end
	local kaiju = workspace:FindFirstChild("Kaiju")
	sight.FilterDescendantsInstances = if kaiju then { kaiju } else {}
	return workspace:Raycast(from, dir, sight) == nil
end

function Larva.decide(self: Larva, now: number)
	local root, hum = nearestPlayer(self.root.Position)
	self.targetRoot, self.targetHum = root, hum
	if not root then
		if self.state ~= "Idle" then
			self.state = "Idle"
			self.waypoints, self.wpIndex, self.pathFor = {}, 0, nil
		end
		return
	end
	if (root.Position - self.root.Position).Magnitude <= Cfg.AttackRange then
		self.state = "Attack"
		return
	end
	self.state = "Chase"
	local moved = self.pathFor == nil or (root.Position - (self.pathFor :: Vector3)).Magnitude > Cfg.RepathDistance
	local exhausted = self.wpIndex > #self.waypoints
	local stuck = now - self.stuckSince > Cfg.StuckSeconds
	if moved or exhausted or stuck then
		if stuck then
			self.hum.Jump = true
			self.stuckSince = now
		end
		self:repath(root.Position)
	end
end

function Larva.execute(self: Larva, now: number)
	if self.state == "Chase" then
		local wp = self.waypoints[self.wpIndex]
		if wp and (wp.Position - self.root.Position).Magnitude <= Cfg.WaypointReach then
			self.wpIndex += 1
			wp = self.waypoints[self.wpIndex]
		end
		if wp and wp.Action == Enum.PathWaypointAction.Jump then self.hum.Jump = true end
		local goal = if wp then wp.Position elseif self.targetRoot then self.targetRoot.Position else nil
		if goal then self.hum:MoveTo(goal) end
		if (self.root.Position - self.lastPos).Magnitude > 0.5 then self.stuckSince = now end
		self.lastPos = self.root.Position

	elseif self.state == "Attack" then
		self.hum:MoveTo(self.root.Position) -- stand and bite
		if now - self.lastAttack >= Cfg.AttackCooldown and self:canBite() then
			self.lastAttack = now
			local th = self.targetHum :: Humanoid
			th:TakeDamage(Cfg.LarvaDamage)
		end

	elseif self.state == "Idle" then
		local away = (self.root.Position - self.home).Magnitude
		self.hum:MoveTo(if away > Cfg.LeashRange then self.home else self.root.Position)
		self.stuckSince = now
	end
end

-- a gun / chainsaw hit from `attacker`: remember them for the kill reward, knock back, pause the brain
function Larva.hit(self: Larva, attacker: Player)
	self.lastAttacker = attacker
	if self.state == "Dead" then return end
	self.pausedUntil = os.clock() + Cfg.HitPause
	self.hum:MoveTo(self.root.Position) -- drop the current walk goal so the push is not walked straight back
	local char = attacker.Character
	local from = char and char:FindFirstChild("HumanoidRootPart")
	if not from or not from:IsA("BasePart") then return end
	local away = (self.root.Position - from.Position) * Vector3.new(1, 0, 1)
	if away.Magnitude < 0.01 then return end
	-- a grounded Humanoid cancels a pushed velocity within a frame (playtest 2026-10-01: 0.9 studs moved vs 5 in
	-- the Physics state); tick() stands it back up when the pause ends
	self.hum:ChangeState(Enum.HumanoidStateType.Physics)
	self.root.AssemblyLinearVelocity = away.Unit * Cfg.KnockbackSpeed + Vector3.yAxis * Cfg.KnockbackUp
end

function Larva.tick(self: Larva, now: number)
	if self.state == "Dead" or now < self.pausedUntil then return end
	if self.hum:GetState() == Enum.HumanoidStateType.Physics then self.hum:ChangeState(Enum.HumanoidStateType.GettingUp) end -- back up after a knockback
	-- beamed down by a UFO (Server.UFO drop): no walking or biting in mid-air, and home is where it lands
	if self.model:GetAttribute("Descending") == true then
		(self :: any).landed = false
		return
	end
	if (self :: any).landed == false then
		(self :: any).landed = true
		self.home = self.root.Position
	end
	if now >= self.nextDecide then
		self.nextDecide = now + 1 / Cfg.DecideHz
		self:decide(now)
	end
	self:execute(now)
end

function Larva.die(self: Larva)
	if self.state == "Dead" then return end
	self.state = "Dead"
	local killer = self.lastAttacker
	if killer and killer.Parent then
		killer:SetAttribute("Cash", (tonumber(killer:GetAttribute("Cash")) or 0) + Cfg.KillReward)
		FX.coins(killer, Cfg.KillReward, self.root.Position)
	end
	task.delay(Cfg.CorpseSeconds, function() self.model:Destroy() end)
end

return Larva
