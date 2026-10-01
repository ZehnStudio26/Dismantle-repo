--!strict
-- GrappleRopes (Shayan 2026-10-01): other players' grappling hooks. Server.Hook broadcasts Remotes.Grapple
-- "Attach" (player, hitPart, offset in hitPart's space) when it accepts a throw and "Release" (player) when the
-- hook ends; this draws a rope (Beam) from that player's Right Arm RightGripAttachment to the hook point and
-- removes it again. The local player's own rope is the GrapplingHook tool's (StarterPack.GrapplingHook.Client).
-- Kaiju parts are anchored, so the rope's end is a Terrain attachment at the hook point: it outlives the part.
-- When the part goes, the rope stays only if kaiju material is still at that point RelatchWindow later (a block
-- cracking into chunks keeps it; a cut-away chunk drops it). Numbers: ReplicatedStorage.Config.HookConfig.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage.Config.HookConfig)
local Grapple = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Grapple") :: RemoteEvent

local player = Players.LocalPlayer
local kaiju = workspace:WaitForChild("Kaiju")

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
overlap.FilterDescendantsInstances = { kaiju }

type Rope = { att: Attachment, conn: RBXScriptConnection? }
local ropes: { [Player]: Rope } = {}

local function gripOf(c: Model?): Attachment?
	local arm = c and (c:FindFirstChild("Right Arm") or c:FindFirstChild("RightHand"))
	local a = arm and arm:FindFirstChild("RightGripAttachment")
	return if a and a:IsA("Attachment") then a else nil
end

local function drop(p: Player)
	local r = ropes[p]
	if not r then return end
	ropes[p] = nil
	if r.conn then r.conn:Disconnect() end
	r.att:Destroy() -- the beam is inside it
end

local function attach(p: Player, part: unknown, offset: unknown)
	drop(p)
	if typeof(part) ~= "Instance" or not (part :: Instance):IsA("BasePart") or typeof(offset) ~= "Vector3" then return end
	local hit = part :: BasePart
	local grip = gripOf(p.Character)
	if not grip then return end
	local world = hit.CFrame:PointToWorldSpace(offset :: Vector3)
	local att = Instance.new("Attachment")
	att.Name = "GrappleRopeEnd"
	att.Parent = workspace.Terrain
	att.WorldPosition = world
	local beam = Instance.new("Beam")
	beam.Name = "GrappleRope"
	beam.Attachment0 = grip
	beam.Attachment1 = att
	beam.Width0, beam.Width1 = Cfg.RopeWidth, Cfg.RopeWidth
	beam.Segments = 24
	beam.FaceCamera = true
	beam.LightInfluence = 1
	beam.Texture = ""
	beam.Color = ColorSequence.new(Cfg.RopeColor)
	beam.Transparency = NumberSequence.new(0)
	beam.Parent = att
	-- the gear's Connect sound where the hook bites (the thrower hears it from their own tool)
	local tool = p.Character and p.Character:FindFirstChild(Cfg.Tool)
	local handle = tool and tool:FindFirstChild("Handle")
	local connect = handle and handle:FindFirstChild("Connect")
	if connect and connect:IsA("Sound") then
		local s = connect:Clone()
		s.Parent = att
		s:Play()
	end
	local r: Rope = { att = att, conn = nil }
	r.conn = hit.AncestryChanged:Connect(function()
		if hit:IsDescendantOf(kaiju) then return end
		if r.conn then r.conn:Disconnect() end
		task.delay(Cfg.RelatchWindow, function()
			if ropes[p] == r and #workspace:GetPartBoundsInRadius(world, Cfg.RelatchRadius, overlap) == 0 then drop(p) end
		end)
	end)
	ropes[p] = r
end

Grapple.OnClientEvent:Connect(function(action: string, who: unknown, part: unknown, offset: unknown)
	if typeof(who) ~= "Instance" or not (who :: Instance):IsA("Player") or who == player then return end
	if action == "Attach" then
		attach(who :: Player, part, offset)
	elseif action == "Release" then
		drop(who :: Player)
	end
end)
Players.PlayerRemoving:Connect(drop)
