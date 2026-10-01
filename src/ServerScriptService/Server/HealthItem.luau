--!strict
-- HealthItem (E-4 / KJ-58, the sheet: "green cross object, pick up to restore health"; H-1 lists it as a
-- heal source; C-3: it goes to whoever picks it up). E-1 rolls Gas / Survivor / Health when a blue event
-- block breaks; a Health roll leaves ServerStorage.Templates.HealthItem (a glowing green 3D cross,
-- authored in Studio) standing in the block's cavity. The first living player within PickupRange who is
-- hurt takes it and heals Heal HP (a full-health player walks through without wasting it for the team).
-- Unclaimed crosses vanish after ExpireSeconds, and all of them when the kaiju is cleared. They live in
-- Workspace.Pickups (not Hazards), so they never count as an active crisis for the roll's single-event
-- rule. The client spins and bobs them (StarterPlayerScripts.PickupSpin); the server never moves them.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Cfg = require(ReplicatedStorage.Config.EventConfig).Health
local Demolition = require(script.Parent.Demolition)
local EventRoll = require(script.Parent.EventRoll)

local folder = workspace:WaitForChild("Pickups")
local template = ServerStorage:WaitForChild("Templates"):WaitForChild("HealthItem") :: Model

type Item = { model: Model, pos: Vector3, expires: number }
local live: { Item } = {}

local function place(cf: CFrame, size: Vector3, source: string)
	local m = template:Clone()
	local _, s = m:GetBoundingBox()
	local floorY = cf.Position.Y - size.Y / 2
	local pos = Vector3.new(cf.Position.X, floorY + s.Y / 2 + Cfg.FloatHeight, cf.Position.Z)
	m:PivotTo(CFrame.new(pos))
	m:SetAttribute("Spin", true)
	m.Parent = folder
	table.insert(live, { model = m, pos = pos, expires = os.clock() + Cfg.ExpireSeconds })
end

-- one loop for every cross on the kaiju
task.spawn(function()
	while true do
		task.wait(0.2)
		local now = os.clock()
		for i = #live, 1, -1 do
			local it = live[i]
			local gone = it.model.Parent == nil
			if not gone and now >= it.expires then
				gone = true
			end
			if not gone then
				for _, p in ipairs(Players:GetPlayers()) do
					local char = p.Character
					local root = char and char:FindFirstChild("HumanoidRootPart")
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					if root and root:IsA("BasePart") and hum and hum.Health > 0 and hum.Health < hum.MaxHealth
						and (root.Position - it.pos).Magnitude <= Cfg.PickupRange then
						local before = hum.Health
						hum.Health = math.min(hum.MaxHealth, hum.Health + Cfg.Heal)
						gone = true
						break
					end
				end
			end
			if gone then
				if it.model.Parent then it.model:Destroy() end
				table.remove(live, i)
			end
		end
	end
end)

-- a rolled Health outcome (E-1) ...
EventRoll.Triggered.Event:Connect(function(kind: string, cf: CFrame, size: Vector3, source: string)
	if kind == "Health" then place(cf, size, source) end
end)
-- ... or a hand-placed block of material "Health" (showcase; never seeded)
Demolition.BlockBroken.Event:Connect(function(cf: CFrame, size: Vector3, material: string?, source: string)
	if material == "Health" then place(cf, size, source) end
end)
Demolition.Cleared.Event:Connect(function()
	for _, it in ipairs(live) do if it.model.Parent then it.model:Destroy() end end
	table.clear(live)
end)

return { Place = place }
