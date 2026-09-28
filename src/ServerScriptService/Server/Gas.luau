--!strict
-- Gas event (A8 / EVT-03 / EVT-05): a gas outcome bursts a cloud in that cell. Players inside
-- lose HP unless they are holding the GasMask tool. Placeholder cloud is a translucent sphere
-- Part until M2c VFX. Sets the player attribute InGas for the client overlay and for K-metrics.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventConfig = require(ReplicatedStorage.Config.EventConfig)
local Demolition = require(script.Parent.Demolition)
local EventRoll = require(script.Parent.EventRoll)

local Cfg = EventConfig.Gas
local folder = workspace:WaitForChild("Hazards")

type Zone = { centre: Vector3, part: Part, until_: number }
local zones: { Zone } = {}
local clouds = 0

local function masked(player: Player): boolean
	local char = player.Character
	return char ~= nil and char:FindFirstChild("GasMask") ~= nil
end

local function spawnCloud(centre: Vector3)
	clouds += 1
	local part = Instance.new("Part")
	part.Name = "GasCloud"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * (Cfg.Radius * 2)
	part.Position = centre
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Color = Color3.fromRGB(120, 200, 80)
	part.Material = Enum.Material.ForceField
	part.Transparency = 0.5
	part.Parent = folder
	table.insert(zones, { centre = centre, part = part, until_ = os.clock() + Cfg.Duration })
	print(("[Gas] cloud #%d burst at %s, radius %d, %ds"):format(clouds, tostring(centre), Cfg.Radius, Cfg.Duration))
end

-- Rolled outcome from a seeded "Event" block (EVT-02) ...
EventRoll.Triggered.Event:Connect(function(kind: string, cf: CFrame)
	if kind == "Gas" then spawnCloud(cf.Position) end
end)
-- ... or a hand-placed block tagged "Organ" with a fixed outcome.
Demolition.BlockBroken.Event:Connect(function(cf: CFrame, size: Vector3, material: string?, source: string)
	if material == "Organ" then spawnCloud(cf.Position) end
end)

-- one tick loop for every cloud: damage, InGas flag, expiry
local lastLog: { [Player]: number } = {}
task.spawn(function()
	while true do
		task.wait(Cfg.TickSeconds)
		local now = os.clock()
		for i = #zones, 1, -1 do
			if now >= zones[i].until_ or zones[i].part.Parent == nil then -- expired, or the cloud part was removed by something else
				zones[i].part:Destroy()
				table.remove(zones, i)
				print("[Gas] cloud dissipated")
			end
		end
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local inside = false
			if root and root:IsA("BasePart") and hum and hum.Health > 0 then
				for _, z in ipairs(zones) do
					if (root.Position - z.centre).Magnitude <= Cfg.Radius then inside = true break end
				end
				if inside and not masked(player) then
					hum:TakeDamage(Cfg.DPS * Cfg.TickSeconds)
					if now - (lastLog[player] or 0) >= 1 then
						lastLog[player] = now
						print(("[Gas] %s breathing gas without a mask, %.0f HP"):format(player.Name, hum.Health))
					end
				end
			end
			if (player:GetAttribute("InGas") == true) ~= inside then
				player:SetAttribute("InGas", inside)
				print(("[Gas] %s %s gas%s"):format(player.Name, if inside then "entered" else "left", if inside and masked(player) then " (masked)" else ""))
			end
		end
	end
end)

Demolition.Cleared.Event:Connect(function()
	for _, z in ipairs(zones) do z.part:Destroy() end
	table.clear(zones)
end)

return { SpawnCloud = spawnCloud }
