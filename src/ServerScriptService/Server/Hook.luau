--!strict
-- Hook (Shayan 2026-10-01): server side of the grappling hook. The client owns its root and runs the pull
-- (only the owner can put its Humanoid in the Physics state); the server only decides whether a throw is
-- allowed and tells everyone, so other clients can draw the rope. Numbers: ReplicatedStorage.Config.HookConfig.
--   Grapple:FireServer("Fire", hitPart, hitPos)  accepted when: right types, alive, holding the GrapplingHook
--       tool (HookConfig.Tool), not Down, not already hooked, cooldown over (Cooldown from the last release,
--       minus CooldownSlack), not faster than MinFireInterval, hitPart is a live kaiju block or chunk
--       (Demolition.Resolve), hitPos inside the part's box + BoundsSlack, HumanoidRootPart -> hitPos within
--       Range + RangeSlack, and a ray HRP -> hitPos (characters and non-collidable volumes ignored) reaches that
--       block or stops within LineSlack of hitPos.
--       Accept: FireAllClients("Attach", player, hitPart, offset in hitPart's space). Refuse: FireClient("Deny").
--   Grapple:FireServer("Release")  ends the hook.
-- A hook also ends on death, a new character, Down, the tool put away, leaving, or when held past
-- dist / MaxSpeed * PullTimeFactor + PullTimeExtra (+ the throw flight and WindUp the client spends first).
-- Every end: FireAllClients("Release", player) and the cooldown starts.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage.Config.HookConfig)
local Demolition = require(script.Parent.Demolition)

local Grapple: RemoteEvent = ReplicatedStorage.Remotes.Grapple
local kaiju = workspace:WaitForChild("Kaiju")

type Hooked = { character: Model, deadline: number }
local hooked: { [Player]: Hooked } = {}
local cooldownUntil: { [Player]: number } = {}
local lastFireAt: { [Player]: number } = {}

local function rootAndHumanoid(player: Player): (BasePart?, Humanoid?)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return (if root and root:IsA("BasePart") then root else nil), hum
end

local function holdingHook(player: Player): boolean
	local char = player.Character
	local tool = char and char:FindFirstChild(Cfg.Tool)
	return tool ~= nil and tool:IsA("Tool")
end

-- the launcher as everyone sees it: the hook Loaded while it is in hand, Empty while it is out (HookConfig.Mesh)
local function showLoaded(player: Player, loaded: boolean)
	local char, pack = player.Character, player:FindFirstChildOfClass("Backpack")
	local tool = (char and char:FindFirstChild(Cfg.Tool)) or (pack and pack:FindFirstChild(Cfg.Tool))
	local handle = tool and tool:FindFirstChild("Handle")
	local mesh = handle and handle:FindFirstChildOfClass("SpecialMesh")
	if mesh then mesh.MeshId = if loaded then Cfg.Mesh.Loaded else Cfg.Mesh.Empty end
end

local function release(player: Player)
	if not hooked[player] then return end
	hooked[player] = nil
	cooldownUntil[player] = os.clock() + Cfg.Cooldown
	showLoaded(player, true)
	Grapple:FireAllClients("Release", player)
end

-- the hit point must be on the part (its box plus BoundsSlack)
local function onPart(part: BasePart, pos: Vector3): boolean
	local p = part.CFrame:PointToObjectSpace(pos)
	local h = part.Size / 2 + Vector3.one * Cfg.BoundsSlack
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end

-- nothing but that block (or something touching the hit point) between the root and the hit point
local function lineOfSight(from: Vector3, to: Vector3, block: PVInstance): boolean
	local chars = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(chars, p.Character) end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = chars
	params.RespectCanCollide = true -- gas volumes and pickups do not block the rope
	local d = to - from
	local hit = workspace:Raycast(from, d.Unit * (d.Magnitude + 1), params)
	if not hit then return true end
	return Demolition.Resolve(hit.Instance) == block or (hit.Position - to).Magnitude <= Cfg.LineSlack
end

local function judge(player: Player, part: BasePart, pos: Vector3, now: number): boolean
	local root, hum = rootAndHumanoid(player)
	if not root or not hum or hum.Health <= 0 or not holdingHook(player) then return false end
	if player:GetAttribute("Down") == true or hooked[player] then return false end
	if now < (cooldownUntil[player] or 0) - Cfg.CooldownSlack then return false end
	if not part:IsDescendantOf(kaiju) then return false end
	local block = Demolition.Resolve(part)
	if not block or not block:IsDescendantOf(workspace) then return false end
	if not onPart(part, pos) then return false end
	if (pos - root.Position).Magnitude > Cfg.Range + Cfg.RangeSlack then return false end
	return lineOfSight(root.Position, pos, block)
end

Grapple.OnServerEvent:Connect(function(player: Player, action: unknown, part: unknown, pos: unknown)
	if action == "Release" then
		release(player)
		return
	end
	if action ~= "Fire" then return end
	local now = os.clock()
	if now - (lastFireAt[player] or -math.huge) < Cfg.MinFireInterval then
		Grapple:FireClient(player, "Deny")
		return
	end
	lastFireAt[player] = now
	if typeof(part) ~= "Instance" or not (part :: Instance):IsA("BasePart") or typeof(pos) ~= "Vector3" then
		Grapple:FireClient(player, "Deny")
		return
	end
	local hitPart, hitPos = part :: BasePart, pos :: Vector3
	if not judge(player, hitPart, hitPos, now) then
		Grapple:FireClient(player, "Deny")
		return
	end
	local root = (rootAndHumanoid(player)) :: BasePart
	local dist = (hitPos - root.Position).Magnitude
	hooked[player] = {
		character = player.Character :: Model,
		deadline = now + dist / Cfg.MaxSpeed * Cfg.PullTimeFactor + Cfg.PullTimeExtra + dist / Cfg.ThrowSpeed + Cfg.WindUp,
	}
	showLoaded(player, false)
	Grapple:FireAllClients("Attach", player, hitPart, hitPart.CFrame:PointToObjectSpace(hitPos))
end)

-- one loop for every way a hook ends besides "Release": time, death, a new character, Down, the tool put away
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for player, h in pairs(hooked) do
		local _, hum = rootAndHumanoid(player)
		if now > h.deadline or player.Character ~= h.character or not hum or hum.Health <= 0
			or player:GetAttribute("Down") == true or not holdingHook(player) then
			release(player)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	release(player)
	hooked[player] = nil
	cooldownUntil[player] = nil
	lastFireAt[player] = nil
end)

return {}
