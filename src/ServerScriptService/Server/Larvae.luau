--!strict
-- Larvae: the one place a larva BODY is built. Egg and UFO both call Spawn and neither knows what
-- a larva is made of. The body is ServerStorage.Templates.Larva (the creature model, 2026-09-28: an
-- R6 Humanoid, HumanoidRootPart with the mesh and a hitbox welded to it, tagged Enemy). Brain: Server.Larva. Tick loop and the server-wide cap:
-- Server.Enemies. Bodies live in Workspace.Enemies, which this module clears when the run ends.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local EventConfig = require(ReplicatedStorage.Config.EventConfig)
local Tags = require(ReplicatedStorage.Config.Tags)
local Demolition = require(script.Parent.Demolition)
local Larva = require(script.Parent.Larva)
local Enemies = require(script.Parent.Enemies)

local Cfg = EventConfig.Egg
local folder = workspace:WaitForChild("Enemies")
local template = ServerStorage:WaitForChild("Templates"):WaitForChild("Larva") :: Model
local spawned = 0

local Larvae = {}

-- One larva standing at pos, or nil when the server-wide cap is full. `source` is for the log only.
function Larvae.Spawn(pos: Vector3, source: string): Model?
	if not Enemies.CanSpawn() then
		return nil
	end
	spawned += 1
	local id = spawned
	local model = template:Clone()
	model.Name = "Larva"
	-- the template is authored anchored; a walking larva is a welded, unanchored assembly
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = false end
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	model.PrimaryPart = root
	model:PivotTo(CFrame.new(pos))
	local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.RequiresNeck = false
	hum.MaxHealth = Cfg.LarvaHP
	hum.Health = Cfg.LarvaHP
	hum.WalkSpeed = Cfg.LarvaSpeed
	-- no engine name / health tag: the readout is StarterGui.LarvaHealth, attached by the client (EnemyHealth)
	hum.DisplayName = ""
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.NameDisplayDistance = 0
	hum.HealthDisplayDistance = 0
	hum.BreakJointsOnDeath = false -- the corpse stays in one piece for the client's death pop (LarvaFX)
	model.Parent = folder
	model:AddTag(Tags.Enemy)
	root:SetNetworkOwner(nil)
	Enemies.Track(Larva.new(id, model, hum, root))
	return model
end

-- `count` larvae in a row centred on pos, 6 studs apart so they do not tangle. Returns how many spawned.
function Larvae.SpawnGroup(pos: Vector3, count: number, source: string): number
	local n = 0
	for i = 1, count do
		local offset = Vector3.new((i - 1) * 6 - (count - 1) * 3, 0, 0)
		if Larvae.Spawn(pos + offset, source) then n += 1 end
	end
	return n
end

Demolition.Cleared.Event:Connect(function() folder:ClearAllChildren() end)

return Larvae
