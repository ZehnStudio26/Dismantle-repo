--!strict
-- EventBlocks (EVT-01, Q22): at run start, retag some Flesh blocks as "Event" so events are
-- buried inside the body and exposed by cutting. What comes out is decided by EventRoll when
-- the block breaks (EVT-02). Runs on the server only, so the saved model stays plain Flesh and
-- every run gets a fresh layout (unless RandomSeed is fixed).
-- Large Voxel Kaiju: hidden blocks live in ServerStorage.KaijuHidden and are candidates too (they
-- are the buried ones). The Color attribute drives chunks created later; the Part is recoloured now.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local EventConfig = require(ReplicatedStorage.Config.EventConfig)
local KaijuConfig = require(ReplicatedStorage.Config.KaijuConfig)

local EventBlocks = {}

function EventBlocks.Seed(kaiju: Model)
	local cfg = EventConfig.Seed
	local rng = if cfg.RandomSeed ~= 0 then Random.new(cfg.RandomSeed) else Random.new()
	local flesh: { Instance } = {}
	local function collect(container: Instance?)
		if not container then return end
		for _, b in ipairs(container:GetChildren()) do
			if (b:IsA("Model") or b:IsA("BasePart")) and b:GetAttribute("BlockMaterial") == "Flesh" then
				table.insert(flesh, b)
			end
		end
	end
	collect(kaiju)
	collect(ServerStorage:FindFirstChild("KaijuHidden"))
	for i = #flesh, 2, -1 do
		local j = rng:NextInteger(1, i)
		flesh[i], flesh[j] = flesh[j], flesh[i]
	end
	local n = math.min(cfg.EventCount, #flesh)
	local color = EventConfig.Colors.Event
	for i = 1, n do
		local b = flesh[i]
		b:SetAttribute("BlockMaterial", "Event")
		b:SetAttribute("Color", color)
		local mat = (KaijuConfig.Materials and KaijuConfig.Materials.Event) or Enum.Material.Neon
		if b:IsA("BasePart") then b.Color = color; b.Material = mat end
		for _, p in ipairs(b:GetChildren()) do
			if p:IsA("BasePart") then p.Color = color; p.Material = mat end
		end
	end
	print(("[EventBlocks] seeded %d event blocks into %d flesh blocks"):format(n, #flesh))
end

return EventBlocks
