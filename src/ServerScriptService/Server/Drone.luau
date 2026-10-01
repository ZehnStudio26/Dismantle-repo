--!strict
-- Support drone (A10 / DRN-01..06). One per player. Hovers by its owner, picks the nearest
-- ordinary kaiju block in reach and cuts it through Demolition with source "Drone", so D7
-- (never event blocks) is enforced by Demolition.CanDamage, not here. It can peel the ordinary
-- blocks around a buried egg or organ and leaves the event block standing for the player (DRN-03/04).
-- Hits are discrete with the drone's own position as the hit point, so it carves the face nearest
-- to it. N4: pauses while Drone / (Drone + Player) share is over MaxShare.
-- Cube placeholder until the drone model lands; swap the body in spawnDrone.
-- ponytail: share cap is global across the server, not per owner.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DroneConfig = require(ReplicatedStorage.Config.DroneConfig)
local Demolition = require(script.Parent.Demolition)

local Cfg = DroneConfig
local folder = workspace:WaitForChild("Drones")

type Drone = { owner: Player, body: Part, beam: Beam, anchor: Attachment, target: PVInstance?, nextSearch: number, nextHit: number, paused: boolean }
local drones: { [Player]: Drone } = {}

local function ownerRoot(player: Player): BasePart?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and hum and hum.Health > 0 then return root end
	return nil
end

local function overShareCap(): boolean
	if not Cfg.EnforceShareCap then return false end
	local c = Demolition.GetContribution()
	local drone, player = c.Drone or 0, c.Player or 0
	if drone + player == 0 then return false end
	return drone / (drone + player) > Cfg.MaxShare
end

-- nearest live block (by block centre) the drone may cut, within SearchRadius of the owner
local function findTarget(d: Drone, root: BasePart): PVInstance?
	local kaiju = Demolition.GetKaiju()
	if not kaiju then return nil end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { kaiju }
	local best: PVInstance? = nil
	local bestD = math.huge
	local seen: { [PVInstance]: boolean } = {}
	for _, part in ipairs(workspace:GetPartBoundsInRadius(root.Position, Cfg.SearchRadius, params)) do
		local block = Demolition.Resolve(part)
		if block and not seen[block] and Demolition.CanDamage(block, "Drone") then
			seen[block] = true
			local dist = ((Demolition.CenterOf(block) or block:GetPivot().Position) - d.body.Position).Magnitude
			if dist < bestD then best, bestD = block, dist end
		end
	end
	return best
end

local function spawnDrone(player: Player): Drone
	local body = Instance.new("Part")
	body.Name = player.Name .. "_Drone"
	body.Size = Vector3.new(3, 1.5, 3)
	body.Color = Color3.fromRGB(80, 160, 220)
	body.Material = Enum.Material.Metal
	body.Anchored = true
	body.CanCollide = false
	body.CanQuery = false
	body.Parent = folder
	local a0 = Instance.new("Attachment")
	a0.Name = "Muzzle"
	a0.Position = Vector3.new(0, -0.75, 0)
	a0.Parent = body
	local anchorPart = Instance.new("Part")
	anchorPart.Name = "BeamAnchor"
	anchorPart.Size = Vector3.one
	anchorPart.Transparency = 1
	anchorPart.Anchored = true
	anchorPart.CanCollide = false
	anchorPart.CanQuery = false
	anchorPart.CanTouch = false
	anchorPart.Parent = folder
	local a1 = Instance.new("Attachment")
	a1.Parent = anchorPart
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 0.2
	beam.Width1 = 0.5
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.Color = ColorSequence.new(Color3.fromRGB(80, 200, 255))
	beam.Enabled = false
	beam.Parent = body
	local d: Drone = { owner = player, body = body, beam = beam, anchor = a1, target = nil, nextSearch = 0, nextHit = 0, paused = false }
	drones[player] = d
	if player:GetAttribute("DroneLevel") == nil then player:SetAttribute("DroneLevel", Cfg.StartingLevel) end
	return d
end

local function setBeam(d: Drone, pos: Vector3?)
	if pos then
		(d.anchor.Parent :: BasePart).Position = pos
		d.beam.Enabled = true
	else
		d.beam.Enabled = false
	end
end

RunService.Heartbeat:Connect(function(dt: number)
	local now = os.clock()
	for player, d in pairs(drones) do
		local root = ownerRoot(player)
		if not root then
			setBeam(d, nil)
			continue
		end
		-- follow
		local goal = root.CFrame:PointToWorldSpace(Cfg.HoverOffset)
		local lookAt = if d.target and d.target.Parent then (Demolition.CenterOf(d.target) or d.target:GetPivot().Position) else root.Position + root.CFrame.LookVector * 10
		d.body.CFrame = d.body.CFrame:Lerp(CFrame.lookAt(goal, lookAt), math.min(1, dt * Cfg.HoverLerp))
		-- share cap
		local paused = overShareCap()
		if paused ~= d.paused then
			d.paused = paused
			local c = Demolition.GetContribution()
		end
		if paused then
			setBeam(d, nil)
			continue
		end
		-- target
		local t = d.target
		if not t or not Demolition.CanDamage(t, "Drone") or ((Demolition.CenterOf(t) or t:GetPivot().Position) - d.body.Position).Magnitude > Cfg.Range then
			d.target = nil
			if now >= d.nextSearch then
				d.nextSearch = now + Cfg.RetargetSeconds
				local found = findTarget(d, root)
				if found and ((Demolition.CenterOf(found) or found:GetPivot().Position) - d.body.Position).Magnitude <= Cfg.Range then
					d.target = found
				end
			end
			t = d.target
		end
		if t then
			if now >= d.nextHit then
				d.nextHit = now + Cfg.HitInterval
				local level = math.clamp(tonumber(player:GetAttribute("DroneLevel")) or 1, 1, #Cfg.LevelMult)
				local _, hit = Demolition.Damage(t, Cfg.DPS * Cfg.LevelMult[level] * Cfg.HitInterval, "Drone", d.body.Position, 3, player)
				setBeam(d, if hit[1] then hit[1].Position else nil)
			end
		else
			setBeam(d, nil)
		end
	end
end)

Players.PlayerAdded:Connect(spawnDrone)
for _, p in ipairs(Players:GetPlayers()) do if not drones[p] then spawnDrone(p) end end
Players.PlayerRemoving:Connect(function(player)
	local d = drones[player]
	if d then d.body:Destroy(); if d.anchor.Parent then d.anchor.Parent:Destroy() end; drones[player] = nil end
end)

return { Get = function(player: Player) return drones[player] end }
