--!strict
-- Egg event (A7 / EVT-06 / EVT-07): an egg outcome spawns larvae that chase the nearest player
-- and damage on contact. Cube placeholder until M1c delivers the creature model: swap
-- spawnLarva's body for the rig, keep the brain.
-- ponytail: direct MoveTo with a pathfinding assist and a jump when stuck. A larva that cannot
-- reach a player on a higher terrace just waits below; that is acceptable for MVP.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventConfig = require(ReplicatedStorage.Config.EventConfig)
local Demolition = require(script.Parent.Demolition)
local EventRoll = require(script.Parent.EventRoll)

local Cfg = EventConfig.Egg
local folder = workspace:WaitForChild("Enemies")
local spawned = 0

local function nearestPlayerRoot(from: Vector3): (BasePart?, Humanoid?)
	local best: BasePart? = nil
	local bestHum: Humanoid? = nil
	local bestD = Cfg.AggroRange
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and hum and hum.Health > 0 then
			local d = (root.Position - from).Magnitude
			if d < bestD then best, bestHum, bestD = root, hum, d end
		end
	end
	return best, bestHum
end

local function brain(model: Model, hum: Humanoid, root: BasePart, id: number)
	local lastAttack = 0
	local lastPos = root.Position
	while model.Parent and hum.Health > 0 do
		local target, targetHum = nearestPlayerRoot(root.Position)
		if target and targetHum then
			local dist = (target.Position - root.Position).Magnitude
			if dist <= Cfg.AttackRange then
				if os.clock() - lastAttack >= Cfg.AttackCooldown then
					lastAttack = os.clock()
					targetHum:TakeDamage(Cfg.LarvaDamage)
					print(("[Larva] #%d bit %s for %d (%.0f HP left)"):format(id, (target.Parent :: Instance).Name, Cfg.LarvaDamage, targetHum.Health))
				end
				hum:MoveTo(root.Position)
			else
				local goal = target.Position
				local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 4, AgentCanJump = true })
				local ok = pcall(function() path:ComputeAsync(root.Position, goal) end)
				if ok and path.Status == Enum.PathStatus.Success then
					local wps = path:GetWaypoints()
					local wp = wps[math.min(2, #wps)]
					if wp then goal = wp.Position end
				end
				hum:MoveTo(goal)
				if (root.Position - lastPos).Magnitude < 1 then hum.Jump = true end
			end
		end
		lastPos = root.Position
		task.wait(Cfg.RepathSeconds)
	end
end

local function spawnLarva(pos: Vector3)
	spawned += 1
	local id = spawned
	local model = Instance.new("Model")
	model.Name = "Larva"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(4, 4, 4)
	root.Color = Color3.fromRGB(200, 40, 40)
	root.Material = Enum.Material.SmoothPlastic
	root.Position = pos
	root.Parent = model
	local hum = Instance.new("Humanoid")
	hum.RequiresNeck = false
	hum.HipHeight = 0
	hum.MaxHealth = Cfg.LarvaHP
	hum.Health = Cfg.LarvaHP
	hum.WalkSpeed = Cfg.LarvaSpeed
	hum.Parent = model
	model.PrimaryPart = root
	model.Parent = folder
	CollectionService:AddTag(model, "Enemy")
	root:SetNetworkOwner(nil)
	hum.Died:Connect(function()
		print(("[Larva] #%d died"):format(id))
		task.delay(Cfg.CorpseSeconds, function() model:Destroy() end)
	end)
	print(("[Larva] #%d hatched at %s"):format(id, tostring(pos)))
	task.spawn(brain, model, hum, root, id)
	return model
end

local function hatch(cf: CFrame, size: Vector3, source: string, party: number)
	local count = EventConfig.Roll.LarvaePerParty[math.clamp(party, 1, #EventConfig.Roll.LarvaePerParty)] or 1
	print(("[Egg] egg broken by %s at %s, %d larva(e) for a party of %d"):format(source, tostring(cf.Position), count, party))
	for i = 1, count do
		local offset = Vector3.new((i - 1) * 6 - (count - 1) * 3, 0, 0)
		spawnLarva(cf.Position - Vector3.new(0, size.Y / 2 - 3, 0) + offset)
	end
end

-- Rolled outcome from a seeded "Event" block (EVT-02) ...
EventRoll.Triggered.Event:Connect(function(kind: string, cf: CFrame, size: Vector3, source: string, party: number)
	if kind == "Egg" then hatch(cf, size, source, party) end
end)
-- ... or a hand-placed block tagged "Egg" with a fixed outcome.
Demolition.BlockBroken.Event:Connect(function(cf: CFrame, size: Vector3, material: string?, source: string)
	if material == "Egg" then hatch(cf, size, source, EventRoll.PartySize()) end
end)

Demolition.Cleared.Event:Connect(function() folder:ClearAllChildren() end)

return { SpawnLarva = spawnLarva }
