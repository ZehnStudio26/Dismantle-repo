--!strict
-- Scaffolding (Shayan 2026-09-29): getting onto the kaiju. Blocks are 12 studs tall, higher than a
-- jump, so three things carry a player up:
--   Towers   authored in Studio (Workspace.Scaffolding.Tower_*: steel poles, a deck flush with the top
--            of every layer, a TrussPart ladder, a gangway from each deck to that layer's edge). Once a
--            layer is cleared its gangways lead into the air, so they are removed here.
--   Pads     each tower's ReturnPad ("TO TOP"): touching it puts you on the open layer, on the intact
--            edge block nearest that tower (the "back to the surface" button of mining games).
--   Button   the rail's TO TOP button (Remotes.ToTop, StarterPlayerScripts.ToTopButton): the same move, but only
--            when you are OFF the open layer (on the ground, or on a lower layer after a fall) and once
--            every RunConfig.ToTopCooldown seconds, so it rescues a fall without dodging a UFO line.
--   Respawn  after a death during a run you come back on the open layer, near where you went down.
--            The first spawn of a session is left alone (spawn, brief, then walk to the kaiju).
-- The ladder climb is sped up on the client (StarterPlayerScripts.ClimbBoost, RunConfig.ClimbWalkSpeed).
-- Landing = an intact block (not cracked) of the open layer with an empty side neighbour, so nobody is
-- dropped into a dig or buried mid-layer; one of the three nearest the reference point, at random.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Demolition = require(script.Parent.Demolition)
local RunConfig = require(ReplicatedStorage.Config.RunConfig)
local ToTop: RemoteEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ToTop") :: RemoteEvent
local RunState = ReplicatedStorage:WaitForChild("RunState")
local folder = workspace:FindFirstChild("Scaffolding")
local rng = Random.new()

local PAD_COOLDOWN = 2
local SIDES = { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis }

-- ---------- gangways of cleared layers ----------
local function prune()
	local active = RunState:GetAttribute("ActiveLayer")
	if not folder or typeof(active) ~= "number" then return end
	local removed = 0
	for _, p in ipairs(folder:GetDescendants()) do
		local layer = p:GetAttribute("Layer")
		if (p.Name == "Gangway" or p.Name == "GangwayRail") and typeof(layer) == "number" and layer > active then
			p:Destroy()
			removed += 1
		end
	end
end

-- ---------- landing on the open layer ----------
local function landing(near: Vector3): Vector3?
	local active = RunState:GetAttribute("ActiveLayer")
	if typeof(active) ~= "number" then return nil end
	local B = Demolition.BlockSize()
	local picks: { { pos: Vector3, d: number } } = {}
	for _, h in ipairs(Demolition.AllBlockHolders()) do
		if h:IsA("BasePart") and h:GetAttribute("BY") == active and h:GetAttribute("Adopted") ~= true and h:IsDescendantOf(workspace) then
			local c = Demolition.CenterOf(h)
			if c and Demolition.BlockAt(c + Vector3.yAxis * B) == nil then
				local edge = false
				for _, s in ipairs(SIDES) do
					if Demolition.BlockAt(c + s * B) == nil then edge = true break end
				end
				if edge then table.insert(picks, { pos = c, d = (Vector3.new(c.X, 0, c.Z) - Vector3.new(near.X, 0, near.Z)).Magnitude }) end
			end
		end
	end
	if #picks == 0 then return nil end
	table.sort(picks, function(a, b) return a.d < b.d end)
	local p = picks[rng:NextInteger(1, math.min(3, #picks))].pos
	return p + Vector3.yAxis * (B / 2 + 3.2) -- the root stands ~3 studs above the feet (R6)
end

local function putOnTop(player: Player, near: Vector3, why: string): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not char or not root or not root:IsA("BasePart") then return false end
	local at = landing(near)
	if not at then
		return false
	end
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	char:PivotTo(CFrame.lookAt(at, at + (if look.Magnitude > 0.1 then look else Vector3.zAxis)))
	return true
end

-- ---------- pads ----------
local lastPad: { [Player]: number } = {}
local padCount = 0
if folder then
	for _, pad in ipairs(folder:GetDescendants()) do
		if pad:IsA("BasePart") and pad.Name == "ReturnPad" then
			padCount += 1
			local tower = pad:FindFirstAncestorOfClass("Model")
			pad.Touched:Connect(function(hit: BasePart)
				local char = hit:FindFirstAncestorOfClass("Model")
				local player = char and Players:GetPlayerFromCharacter(char)
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if not player or not hum or hum.Health <= 0 then return end
				if RunState:GetAttribute("State") ~= "Running" then return end
				local now = os.clock()
				if now - (lastPad[player] or -math.huge) < PAD_COOLDOWN then return end
				lastPad[player] = now
				local toward = if tower then tower:GetPivot().Position else pad.Position
				putOnTop(player, toward, "pad at " .. (pad:GetAttribute("Tower") or "?"))
			end)
		end
	end
end

-- ---------- the TO TOP button ----------
-- world height of the open layer's top face
local function openTop(): number?
	local active = RunState:GetAttribute("ActiveLayer")
	local kaiju = Demolition.GetKaiju()
	local origin = kaiju and kaiju:GetAttribute("Origin")
	if typeof(active) ~= "number" or typeof(origin) ~= "Vector3" then return nil end
	local B = Demolition.BlockSize()
	return origin.Y + active * B + B / 2
end

local lastButton: { [Player]: number } = {}
ToTop.OnServerEvent:Connect(function(player: Player)
	local cooldown = RunConfig.ToTopCooldown or 20
	local now = os.clock()
	local function reply(ok: boolean, why: string, wait: number)
		ToTop:FireClient(player, ok, why, wait)
	end
	if RunState:GetAttribute("State") ~= "Running" then return reply(false, "the run is not on", 0) end
	local left = cooldown - (now - (lastButton[player] or -math.huge))
	if left > 0 then return reply(false, ("cooling down, %ds left"):format(math.ceil(left)), left) end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or hum.Health <= 0 or not root or not root:IsA("BasePart") then return reply(false, "not alive", 0) end
	local top = openTop()
	if top and root.Position.Y - 3 >= top - 2 then return reply(false, "already on the open layer", 0) end
	if putOnTop(player, root.Position, "TO TOP button") then
		lastButton[player] = now
		reply(true, "moved to the open layer", cooldown)
	else
		reply(false, "no safe spot on the open layer", 0)
	end
end)

-- ---------- respawn on the open layer ----------
local diedAt: { [Player]: Vector3 } = {}
local spawnedOnce: { [Player]: boolean } = {}
local function onCharacter(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not hum or not root then return end
	hum.Died:Connect(function() diedAt[player] = root.Position end)
	if not spawnedOnce[player] then
		spawnedOnce[player] = true
		return
	end
	if RunState:GetAttribute("State") ~= "Running" then return end
	task.wait(0.2) -- let the spawn settle before moving the character
	if char.Parent then putOnTop(player, diedAt[player] or root.Position, "respawn") end
end
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char) onCharacter(player, char) end)
end)
for _, player in ipairs(Players:GetPlayers()) do
	spawnedOnce[player] = player.Character ~= nil
	player.CharacterAdded:Connect(function(char) onCharacter(player, char) end)
end
Players.PlayerRemoving:Connect(function(player)
	lastPad[player], diedAt[player], spawnedOnce[player], lastButton[player] = nil, nil, nil, nil
end)

if folder then
	local towers = 0
	for _, t in ipairs(folder:GetChildren()) do if t:IsA("Model") then towers += 1 end end
else
	warn("[Scaffolding] Workspace.Scaffolding is missing: nothing to climb onto the kaiju with")
end
RunState:GetAttributeChangedSignal("ActiveLayer"):Connect(prune)
prune()

return true
