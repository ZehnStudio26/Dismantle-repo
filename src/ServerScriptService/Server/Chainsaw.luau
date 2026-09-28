--!strict
-- Chainsaw (Chainsaw Cutting Plan steps 2 and 5a; Bee 2026-09-28: the chainsaw replaces the laser):
-- server side of the Chainsaw tool.
-- The client reports one hit per swing (the part its melee box found and where the blade was); the
-- server validates and applies it through Demolition, so D7 / D9 and the percent / cash rules hold.
-- Each swing is one discrete hit, like the mining pack's MineHit.
--   Validates: tool held, alive, a real block, reach (the Player.Range tier in BLOCKS around the
--              player's cell, mirroring the client's cursor selection, plus ServerSlack),
--              minimum interval (divided by the Player.Speed tier), CanDamage.
--   Damage:    ToolConfig.Chainsaw.DamagePerHit x Player.Damage tier, 15% chance of a x2 crit
--              (a crit also doubles the chunk cap, so it takes two faces instead of one).
--   Area:      ToolConfig.Chainsaw.AreaByTier (KJ-25): at higher Damage tiers the same hit also lands
--              on the aimed block's side neighbours (5) or the 3x3 around it (9), on its own layer.
--              Each splash block passes Demolition.CanDamage on its own.
--   Replies:   ChainsawHit:FireClient(player, ok, reason, crit, damage) for the client's log and its
--              effects. Player attribute CutState carries the last verdict for the HUD.
-- Animated tool mount: Shayan's ChainsawRig animations key a "Handle" joint (Motor6D Right Arm ->
-- Handle, C0 = C1 = identity), so the saw's position comes from the animation, not from Tool.Grip.
-- On equip the server replaces Roblox's RightGrip weld with that Motor6D (server-side so every client
-- sees the saw where the animation puts it); on unequip it removes it again.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ToolConfig = require(ReplicatedStorage.Config.ToolConfig)
local UpgradeConfig = require(ReplicatedStorage.Config.UpgradeConfig)
local Demolition = require(script.Parent.Demolition)

local Cfg = ToolConfig.Chainsaw
local ChainsawHit: RemoteEvent = ReplicatedStorage.Remotes.ChainsawHit

local rng = Random.new()

-- side neighbours first, then the corners: the first AreaByTier[tier] - 1 of these are splashed
local AREA = { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
	Vector3.new(1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(-1, 0, -1) }
local lastHitAt: { [Player]: number } = {}
local cuttingUntil: { [Player]: number } = {}
local hits, refused = 0, 0

local function holdingChainsaw(player: Player): boolean
	local char = player.Character
	local tool = char and char:FindFirstChild("Chainsaw")
	return tool ~= nil and tool:IsA("Tool")
end

local function alive(player: Player): boolean
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function rootPosition(player: Player): Vector3?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- ---------- animated mount ----------
-- the arm the animation's Handle joint hangs from: R6 "Right Arm", R15 "RightHand"
local function gripArm(char: Model): BasePart?
	local arm = char:FindFirstChild("Right Arm") or char:FindFirstChild("RightHand")
	return if arm and arm:IsA("BasePart") then arm else nil
end

local function mount(player: Player, tool: Tool)
	local char = tool.Parent
	if not char or not char:IsA("Model") then return end
	local arm = gripArm(char)
	local handle = tool:FindFirstChild("Handle")
	if not arm or not handle or not handle:IsA("BasePart") then
		warn(("[Chainsaw] %s: cannot mount, arm=%s handle=%s"):format(player.Name, tostring(arm), tostring(handle)))
		return
	end
	-- Roblox creates RightGrip a moment after the tool enters the character; wait for it, then replace it
	local grip = arm:FindFirstChild("RightGrip")
	local deadline = os.clock() + 1
	while not grip and os.clock() < deadline and tool.Parent == char do
		task.wait()
		grip = arm:FindFirstChild("RightGrip")
	end
	if tool.Parent ~= char then return end
	if grip then grip:Destroy() end
	local old = arm:FindFirstChild("Handle")
	if old and old:IsA("Motor6D") and old.Part1 == handle then return end -- already mounted (Equipped can fire twice)
	if old then old:Destroy() end
	local motor = Instance.new("Motor6D")
	motor.Name = "Handle" -- the joint name the animations key
	motor.Part0 = arm
	motor.Part1 = handle
	motor.C0 = CFrame.identity
	motor.C1 = CFrame.identity
	motor.Parent = arm
	print(("[Chainsaw] %s equipped: RightGrip %s, Motor6D Handle on %s (%s rig)"):format(player.Name, if grip then "replaced" else "not found (none to replace)", arm.Name, tostring((char:FindFirstChildOfClass("Humanoid") :: Humanoid).RigType)))
end

local function unmount(player: Player, char: Model?)
	local arm = char and gripArm(char)
	local motor = arm and arm:FindFirstChild("Handle")
	if motor then motor:Destroy() end
end

local function watchTool(player: Player, tool: Tool)
	tool.Equipped:Connect(function() mount(player, tool) end)
	tool.Unequipped:Connect(function() unmount(player, player.Character) end)
end

local function watchPlayer(player: Player)
	local function watchBackpack(backpack: Instance)
		local tool = backpack:FindFirstChild("Chainsaw")
		if tool and tool:IsA("Tool") then watchTool(player, tool) end
		backpack.ChildAdded:Connect(function(child)
			if child.Name == "Chainsaw" and child:IsA("Tool") then watchTool(player, child) end
		end)
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then watchBackpack(backpack) end
	player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then watchBackpack(child) end
	end)
end
Players.PlayerAdded:Connect(watchPlayer)
for _, p in ipairs(Players:GetPlayers()) do watchPlayer(p) end

-- ---------- the hit ----------
-- Reach, mirroring the client: the block centre must lie within Range blocks of the cell the player's
-- body stands in (feet plus half a block) on every axis, plus ServerSlack for movement lag.
local function inReach(player: Player, from: Vector3, centre: Vector3): boolean
	local B = Demolition.BlockSize()
	local d = (centre - (from + Vector3.yAxis * (B / 2 - Cfg.ReachFromFeet))) / B
	return math.max(math.abs(d.X), math.abs(d.Y), math.abs(d.Z)) <= UpgradeConfig.Value(player, "Player", "Range") + 0.5 + Cfg.ServerSlack
end

-- why a reported hit is or is not accepted (same vocabulary as the old Cutter's CutState)
local function judge(player: Player, part: Instance?, now: number): (string, PVInstance?)
	if not holdingChainsaw(player) then return "NoTool", nil end
	if not alive(player) then return "Dead", nil end
	local block = Demolition.Resolve(part)
	if block == nil then return "NoBlock", nil end
	local from = rootPosition(player)
	local centre = Demolition.CenterOf(block) or block:GetPivot().Position
	if not from or not inReach(player, from, centre) then return "OutOfReach", block end
	local minInterval = Cfg.MinHitInterval / UpgradeConfig.Value(player, "Player", "Speed")
	if now - (lastHitAt[player] or -math.huge) < minInterval then return "TooSoon", block end
	local ok, why = Demolition.CanDamage(block, "Player")
	if not ok then return "Refused:" .. tostring(why), block end
	return "OK", block
end

-- what is left of the block at a grid centre after a hit, for the log
local function stateAfter(centre: Vector3): string
	local holder = Demolition.BlockAt(centre)
	if holder == nil then return "BROKEN" end
	if holder:IsA("Model") then return ("cracked, %d chunk(s) showing"):format(#holder:GetChildren()) end
	return "intact"
end

ChainsawHit.OnServerEvent:Connect(function(player: Player, part: Instance?, hitPos: Vector3?, swing: string?)
	if part ~= nil and not part:IsA("BasePart") then return end
	if hitPos ~= nil and typeof(hitPos) ~= "Vector3" then return end
	local now = os.clock()
	local reason, block = judge(player, part, now)
	player:SetAttribute("CutState", reason)
	if reason ~= "OK" or block == nil then
		refused += 1
		ChainsawHit:FireClient(player, false, reason, false, 0)
		print(("[Chainsaw] %s %s hit refused: %s (%s)"):format(player.Name, tostring(swing), reason, part and part.Name or "nil"))
		return
	end
	lastHitAt[player] = now
	local crit = rng:NextNumber() < Cfg.CritChance
	local damage = Cfg.DamagePerHit * UpgradeConfig.Value(player, "Player", "Damage") * (if crit then Cfg.CritMultiplier else 1)
	local tier = UpgradeConfig.Tier(player, "Player", "Damage")
	local cap = Cfg.ChunksPerHitByTier[math.clamp(tier, 1, #Cfg.ChunksPerHitByTier)]
	if crit then cap = cap * Cfg.CritMultiplier end -- a crit lifts the chunk cap too, or the doubled damage has nowhere to go
	-- clamp the reported hit position to the block so a spoofed position cannot pick far chunks
	local centre = Demolition.CenterOf(block) or block:GetPivot().Position
	local pos = hitPos or centre
	if (pos - centre).Magnitude > Demolition.BlockSize() then pos = centre end
	local blockName = block.Name
	local applied, chunks = Demolition.Damage(part, damage, "Player", pos, cap, player)
	-- area splash: same damage and cap on the neighbours, aimed at the same side of each block
	local area = if Cfg.AreaByTier then Cfg.AreaByTier[math.clamp(tier, 1, #Cfg.AreaByTier)] else 1
	local splashed = 0
	for i = 1, math.min(area - 1, #AREA) do
		local offset = AREA[i] * Demolition.BlockSize()
		local n = Demolition.BlockAt(centre + offset)
		if n and n:IsDescendantOf(workspace) and Demolition.CanDamage(n, "Player") then
			local a = Demolition.Damage(n, damage, "Player", pos + offset, cap, player)
			if a > 0 then splashed += 1 end
		end
	end
	hits += 1
	-- Telemetry reads the Cutting attribute at 4 Hz for K3 / K4: hold it for a second after each hit
	cuttingUntil[player] = now + 1
	if player:GetAttribute("Cutting") ~= true then player:SetAttribute("Cutting", true) end
	task.delay(1.05, function()
		if os.clock() >= (cuttingUntil[player] or 0) and player.Parent then player:SetAttribute("Cutting", false) end
	end)
	ChainsawHit:FireClient(player, true, "OK", crit, damage)
	print(("[Chainsaw] %s %s hit %s for %.0f%s: %.0f applied over %d chunk(s), block %s; area %d, splashed %d neighbour(s)"):format(
		player.Name, tostring(swing), blockName, damage, if crit then " CRIT" else "", applied, #chunks, stateAfter(centre), area, splashed))
end)

Players.PlayerRemoving:Connect(function(player)
	lastHitAt[player] = nil
	cuttingUntil[player] = nil
end)

return {
	Stats = function() return hits, refused end,
}
