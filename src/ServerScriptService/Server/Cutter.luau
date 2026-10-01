--!strict
-- Cutter (A5 / TOOL-01 + Voxel Kaiju Plan): server side of the LaserCutter tool.
-- The client reports the part under the cursor and the hit position; the server validates and
-- applies a discrete hit every HitInterval through Demolition. Damage per hit = DPS * HitInterval,
-- so throughput matches the old continuous laser. The cutter also cuts enemies ("for both" in the
-- design drawing) at EnemyDPS through the same Enemy check the gun uses; D9 is about the gun.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ToolConfig = require(ReplicatedStorage.Config.ToolConfig)
local Demolition = require(script.Parent.Demolition)
local Gun = require(script.Parent.Gun)

local Cfg = ToolConfig.Cutter
local CutterAim: RemoteEvent = ReplicatedStorage.Remotes.CutterAim

type Aim = { part: BasePart?, pos: Vector3?, at: number, nextHit: number }
local aims: { [Player]: Aim } = {}

-- one invisible anchor per player carries the beam's far end, so the beam survives the chunk it hit dying
local anchors: { [Player]: Attachment } = {}
local anchorFolder = workspace:FindFirstChild("FXAnchors") or Instance.new("Folder")
anchorFolder.Name = "FXAnchors"
anchorFolder.Parent = workspace

local function anchorFor(player: Player): Attachment
	local a = anchors[player]
	if a and a.Parent then return a end
	local part = Instance.new("Part")
	part.Name = player.Name .. "_CutAnchor"
	part.Size = Vector3.one
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Parent = anchorFolder
	a = Instance.new("Attachment")
	a.Parent = part
	anchors[player] = a
	return a
end

local function equippedTool(player: Player): Tool?
	local char = player.Character
	local tool = char and char:FindFirstChild("LaserCutter")
	return if tool and tool:IsA("Tool") then tool else nil
end

local function inReach(player: Player, block: PVInstance): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return false end
	local reach = Cfg.Range + Demolition.BlockSize() * 0.87
	local centre = Demolition.CenterOf(block) or block:GetPivot().Position
	return (root.Position - centre).Magnitude <= reach
end

local function alive(player: Player): boolean
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function setBeam(player: Player, tool: Tool, pos: Vector3?)
	local handle = tool:FindFirstChild("Handle")
	local beam = handle and handle:FindFirstChild("Beam")
	if not beam or not beam:IsA("Beam") then return end
	if pos then
		local a = anchorFor(player)
		;(a.Parent :: BasePart).Position = pos
		beam.Attachment1 = a
		beam.Enabled = true
	else
		beam.Enabled = false
	end
end

CutterAim.OnServerEvent:Connect(function(player: Player, part: Instance?, hitPos: Vector3?)
	if part ~= nil and not part:IsA("BasePart") then return end
	if hitPos ~= nil and typeof(hitPos) ~= "Vector3" then return end
	local prev = aims[player]
	aims[player] = { part = part :: BasePart?, pos = hitPos, at = os.clock(), nextHit = prev and prev.nextHit or 0 }
end)

Players.PlayerRemoving:Connect(function(player)
	aims[player] = nil
	local a = anchors[player]
	if a and a.Parent then a.Parent:Destroy() end
	anchors[player] = nil
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for player, aim in pairs(aims) do
		local tool = equippedTool(player)
		local block = Demolition.Resolve(aim.part)
		local enemy: Humanoid? = if block == nil then Gun.EnemyHumanoid(aim.part) else nil
		local target: PVInstance? = block or (if enemy then enemy.Parent :: PVInstance else nil)
		-- why a report is or is not cutting; published as CutState for the HUD hint and for tests
		local reason = if tool == nil then "NoTool"
			elseif target == nil or (enemy ~= nil and enemy.Health <= 0) then "NoBlock"
			elseif now - aim.at > Cfg.AimTimeout then "AimStale"
			elseif not alive(player) then "Dead"
			elseif not inReach(player, target) then "OutOfReach"
			elseif block ~= nil and not Demolition.CanDamage(block, "Player") then "Refused"
			else "OK"
		local cutting = reason == "OK"
		if player:GetAttribute("CutState") ~= reason then player:SetAttribute("CutState", reason) end
		local beamPos: Vector3? = if cutting then (aim.pos or (aim.part :: BasePart).Position) else nil
		if cutting and now >= aim.nextHit then
			aim.nextHit = now + Cfg.HitInterval
			local level = math.clamp(tonumber(player:GetAttribute("CutterLevel")) or 1, 1, #Cfg.LevelMult)
			local mult = Cfg.LevelMult[level]
			if block then
				local cap = Cfg.CellsPerHitByLevel[math.clamp(level, 1, #Cfg.CellsPerHitByLevel)]
				-- clamp the reported hit position to the block so a spoofed position cannot pick far chunks
				local centre = Demolition.CenterOf(block) or (block :: PVInstance):GetPivot().Position
				local pos = aim.pos or centre
				if (pos - centre).Magnitude > Demolition.BlockSize() then pos = centre end
				Demolition.Damage(aim.part, Cfg.DPS * mult * Cfg.HitInterval, "Player", pos, cap, player)
			elseif enemy then
				local dmg = Cfg.EnemyDPS * mult * Cfg.HitInterval
				enemy:TakeDamage(dmg)
			end
		end
		if tool then setBeam(player, tool, beamPos) end
		if (player:GetAttribute("Cutting") == true) ~= (cutting == true) then
			player:SetAttribute("Cutting", cutting == true) -- read by Telemetry for K3 / K4
		end
	end
end)

return true
