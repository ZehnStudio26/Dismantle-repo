--!strict
-- Pickups (design drawing p.2, the positive outcomes Q11 asked for): Survivor and Health results of
-- an event block. A rolled Survivor leaves a placeholder figure in the cavity; the first player to
-- reach them rescues them and is paid Cash (drawn as figure + coin), shown with the "+$" popup.
-- A rolled Health leaves a cross; reaching it heals. Both live in Workspace.Pickups, not Hazards or
-- Enemies, so they never count as active events for EVT-16 or the K3 event clock.
-- Placeholder Parts until M2 models exist; collection is a server-side distance check, no physics.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventConfig = require(ReplicatedStorage.Config.EventConfig)
local EventRoll = require(script.Parent.EventRoll)
local Demolition = require(script.Parent.Demolition)

local Cfg = EventConfig.Pickups
local BlockFX: RemoteEvent = ReplicatedStorage.Remotes.BlockFX

local folder = workspace:FindFirstChild("Pickups") or Instance.new("Folder")
folder.Name = "Pickups"
folder.Parent = workspace

type Pickup = { kind: string, part: BasePart, until_: number }
local live: { Pickup } = {}
local spawned, taken, expired = 0, 0, 0

local function place(kind: string, cf: CFrame, size: Vector3)
	local c = Cfg[kind]
	local part = Instance.new("Part")
	part.Name = kind
	part.Size = c.Size
	part.Position = cf.Position - Vector3.new(0, size.Y / 2 - c.Size.Y / 2, 0) -- standing on the cavity floor
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Color = c.Color
	part.Material = Enum.Material.Neon
	part.Parent = folder
	spawned += 1
	table.insert(live, { kind = kind, part = part, until_ = os.clock() + c.Lifetime })
	print(("[Pickup] %s at %s, gone in %ds if nobody reaches it"):format(kind, tostring(part.Position), c.Lifetime))
end

local function collect(p: Pickup, player: Player, hum: Humanoid)
	local c = Cfg[p.kind]
	if p.kind == "Survivor" then
		local cash = (tonumber(player:GetAttribute("Cash")) or 0) + c.Cash
		player:SetAttribute("Cash", cash)
		BlockFX:FireAllClients("Block", p.part.CFrame, p.part.Size, c.Cash, player.Name) -- same "+$N" popup as a block
		print(("[Pickup] %s rescued a survivor: +$%d (Cash %d)"):format(player.Name, c.Cash, cash))
	else
		local before = hum.Health
		hum.Health = math.min(hum.MaxHealth, hum.Health + c.Heal)
		print(("[Pickup] %s picked up health: %.0f -> %.0f"):format(player.Name, before, hum.Health))
	end
	taken += 1
end

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < Cfg.TickSeconds then return end
	acc = 0
	local now = os.clock()
	for i = #live, 1, -1 do
		local p = live[i]
		local gone = not p.part.Parent
		if not gone and now >= p.until_ then
			gone = true
			expired += 1
			print(("[Pickup] %s expired unreached"):format(p.kind))
		end
		if not gone then
			for _, player in ipairs(Players:GetPlayers()) do
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if root and root:IsA("BasePart") and hum and hum.Health > 0 and (root.Position - p.part.Position).Magnitude <= Cfg.Radius then
					collect(p, player, hum)
					gone = true
					break
				end
			end
		end
		if gone then
			if p.part.Parent then p.part:Destroy() end
			table.remove(live, i)
		end
	end
end)

EventRoll.Triggered.Event:Connect(function(kind: string, cf: CFrame, size: Vector3)
	if Cfg[kind] then place(kind, cf, size) end
end)
Demolition.Cleared.Event:Connect(function()
	folder:ClearAllChildren()
	table.clear(live)
end)

return {
	Place = place,
	Stats = function() return spawned, taken, expired end,
}
