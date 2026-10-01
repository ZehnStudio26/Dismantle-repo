--!strict
-- Egg (A7 / EVT-06 / EVT-07, L-1): a placed egg incubates, then hatches larvae. Two halves that
-- only meet through the "Egg" tag:
--   PLACEMENT  an egg-kind event (rolled Event block, or a block of material "Egg") clones the egg
--              template where the block was and tags it. That is all the event side does.
--   BEHAVIOUR  TagBinder gives every tagged egg inside Workspace an Incubating object, whether it
--              came from an event or was placed by hand in Studio (Workspace.TestArea.Models.Egg).
-- So a designer can drop eggs anywhere, and the event path can change, without touching the
-- hatch logic. Bodies come from Larvae; this module never builds a larva itself.
--
-- Attributes on the egg model override the defaults: HatchSeconds, Count (default: EVT-17 party
-- scaling from EventConfig.Roll.LarvaePerParty), EggHP (default EventConfig.Egg.EggHP).
-- Set here for the client (StarterPlayerScripts.LarvaFX animates wobble / pulse / cracks from them):
-- HatchAt (server time of the hatch), HatchSeconds, Burst (true just before a hatch or a pop destroys it).
-- Shooting / sawing an egg to 0 EggHP pops it with no larvae: Server.Enemies.HitEgg.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventConfig = require(ReplicatedStorage.Config.EventConfig)
local Tags = require(ReplicatedStorage.Config.Tags)
local Demolition = require(script.Parent.Demolition)
local EventRoll = require(script.Parent.EventRoll)
local Larvae = require(script.Parent.Larvae)
local TagBinder = require(script.Parent.TagBinder)

local Cfg = EventConfig.Egg
-- An incubating egg is an event in progress, and EventRoll counts this folder for EVT-16.
local folder = workspace:WaitForChild("Hazards")
local template = ServerStorage:WaitForChild("Templates"):WaitForChild("Egg") :: Model

local function countForParty(party: number): number
	local perParty = EventConfig.Roll.LarvaePerParty
	return perParty[math.clamp(party, 1, #perParty)] or 1
end

-- ---- behaviour: one incubating egg ----

type Fields = { model: Model, thread: thread? }
local Incubating = {}
Incubating.__index = Incubating

function Incubating.new(model: Model)
	local self = setmetatable({ model = model, thread = nil } :: Fields, Incubating)
	local seconds = tonumber(model:GetAttribute("HatchSeconds")) or Cfg.HatchSeconds
	local count = tonumber(model:GetAttribute("Count")) or countForParty(EventRoll.PartySize())
	model.PrimaryPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true) -- the lock-on and hit checks aim at it
	if model:GetAttribute("EggHP") == nil then model:SetAttribute("EggHP", Cfg.EggHP) end
	model:SetAttribute("HatchSeconds", seconds)
	model:SetAttribute("HatchAt", workspace:GetServerTimeNow() + seconds)
	self.thread = task.delay(seconds, function()
		self.thread = nil -- so the Destroy triggered by model:Destroy() has nothing to cancel
		local pos = model:GetPivot().Position + Vector3.new(0, 3, 0)
		model:SetAttribute("Burst", true)
		model:Destroy()
		Larvae.SpawnGroup(pos, count, "Egg")
	end)
	return self
end

-- Tag removed, model destroyed, or run cleared before the hatch: the egg simply never hatches.
function Incubating.Destroy(self: Fields)
	if self.thread then
		task.cancel(self.thread)
		self.thread = nil
	end
end

TagBinder.bind(Tags.Egg, function(inst) return Incubating.new(inst :: Model) end)

-- ---- placement: an egg-kind event puts a tagged egg where the block was ----

local function place(cf: CFrame, size: Vector3, source: string)
	local egg = template:Clone()
	local _, eggSize = egg:GetBoundingBox()
	egg:PivotTo(CFrame.new(cf.Position - Vector3.new(0, size.Y / 2 - eggSize.Y / 2, 0))) -- resting on the block's floor
	egg.Parent = folder
	egg:AddTag(Tags.Egg) -- tag last: TagBinder only binds what is already in Workspace
end

-- Rolled outcome from a seeded "Event" block (EVT-02) ...
EventRoll.Triggered.Event:Connect(function(kind: string, cf: CFrame, size: Vector3, source: string)
	if kind == "Egg" then place(cf, size, source) end
end)
-- ... or a hand-placed block tagged "Egg" with a fixed outcome.
Demolition.BlockBroken.Event:Connect(function(cf: CFrame, size: Vector3, material: string?, source: string)
	if material == "Egg" then place(cf, size, source) end
end)

Demolition.Cleared.Event:Connect(function()
	for _, egg in ipairs(CollectionService:GetTagged(Tags.Egg)) do
		if egg.Parent == folder then egg:Destroy() end
	end
end)

return { Place = place }
