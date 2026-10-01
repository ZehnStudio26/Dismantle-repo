--!strict
-- UFOFX (client): the UFO's readability layer. Client-side only, nothing replicates. (2026-10-01)
--   Sweep line: Server.UFO puts Workspace.Hazards.UFOLine down with PassAt (server time the pass
--     starts). Until then the strip pulses (transparency + its SurfaceLight), speeding up from
--     Sweep.PulseSlowHz to PulseFastHz over the last PulseRampSeconds; from PassAt it holds bright.
--     While the line's point nearest you is off-screen an EventFX arrow ("UFO", red) points at it;
--     it goes with the line.
--   Shadow: a dark disc on whatever is under each saucer (a Model "UFO" in Workspace, or one tagged
--     UFO / DamageUFO / LarvaUFO), raycast straight down CASTS_PER_SECOND; darker and tighter the
--     lower the saucer (EventConfig.UFO.Shadow). Removed with the saucer.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventConfig = require(ReplicatedStorage.Config.EventConfig)
local Tags = require(ReplicatedStorage.Config.Tags)
local EventFX = require(ReplicatedStorage.UI.EventFX)

local S = EventConfig.UFO.Sweep
local SH = EventConfig.UFO.Shadow
local player = Players.LocalPlayer
local hazards = workspace:WaitForChild("Hazards")

local DIM, BRIGHT = 0.6, 0.05     -- line transparency at the pulse's low / high (and from PassAt on)
local GLOW_DIM, GLOW_BRIGHT = 1, 8 -- its SurfaceLight brightness, likewise (the server's pass value is 8)
local CASTS_PER_SECOND = 15       -- shadow raycasts per saucer per second (the disc follows every frame)
local RAY_DOWN = 400              -- studs: a visit enters about 200 over the layer
local FLAT = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder's axis is X; this lays it flat

-- ---- the sweep line ----
type Line = { part: BasePart, arrow: any, phase: number }
local lines: { [BasePart]: Line } = {}

-- the point of the line nearest my character (camera when dead), for the arrow
local function nearestOnLine(part: BasePart): Vector3?
	if not part.Parent then return nil end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local from = if root and root:IsA("BasePart") then root.Position else workspace.CurrentCamera.CFrame.Position
	local loc = part.CFrame:PointToObjectSpace(from)
	local h = part.Size / 2
	return part.CFrame:PointToWorldSpace(Vector3.new(math.clamp(loc.X, -h.X, h.X), 0, math.clamp(loc.Z, -h.Z, h.Z)))
end

local function addLine(inst: Instance)
	if inst.Name ~= "UFOLine" or not inst:IsA("BasePart") then return end
	local part = inst :: BasePart
	if lines[part] then return end
	lines[part] = {
		part = part,
		phase = 0,
		arrow = EventFX.arrow(function() return nearestOnLine(part) end, { color = S.LineColor, text = "UFO" }),
	}
end

hazards.ChildAdded:Connect(addLine)
for _, c in ipairs(hazards:GetChildren()) do addLine(c) end

-- ---- shadows ----
type Shadow = { root: BasePart, disc: Part, width: number, floorY: number? }
local shadows: { [Model]: Shadow } = {}
local ray = RaycastParams.new()
ray.FilterType = Enum.RaycastFilterType.Exclude

local function watch(inst: Instance)
	if not inst:IsA("Model") or shadows[inst] then return end
	local root = inst.PrimaryPart
	if not root then return end
	local disc = Instance.new("Part")
	disc.Name = "UFOShadow"
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Material = Enum.Material.SmoothPlastic
	disc.Color = Color3.new(0, 0, 0)
	disc.Transparency = 1
	disc.Parent = workspace
	shadows[inst] = { root = root, disc = disc, width = math.max(root.Size.X, root.Size.Z), floorY = nil }
end

workspace.ChildAdded:Connect(function(c) if c.Name == "UFO" then watch(c) end end) -- a visit parents straight to Workspace
for _, c in ipairs(workspace:GetChildren()) do if c.Name == "UFO" then watch(c) end end
for _, tag in ipairs({ Tags.UFO, Tags.DamageUFO, Tags.LarvaUFO }) do -- tagged saucers anywhere (the sandbox ones)
	CollectionService:GetInstanceAddedSignal(tag):Connect(watch)
	for _, u in ipairs(CollectionService:GetTagged(tag)) do watch(u) end
end

-- ---- the one loop ----
local castEvery = 1 / CASTS_PER_SECOND
local sinceCast = castEvery
RunService.RenderStepped:Connect(function(dt)
	local now = workspace:GetServerTimeNow()
	for part, l in pairs(lines) do
		if not part.Parent then
			l.arrow:Destroy()
			lines[part] = nil
			continue
		end
		local glow = part:FindFirstChildOfClass("SurfaceLight")
		local passAt = part:GetAttribute("PassAt")
		local left = if typeof(passAt) == "number" then passAt - now else math.huge
		if left <= 0 then
			part.Transparency = BRIGHT
			if glow then glow.Brightness = GLOW_BRIGHT end
			continue
		end
		local ramp = 1 - math.clamp(left / S.PulseRampSeconds, 0, 1)
		l.phase = (l.phase + dt * (S.PulseSlowHz + (S.PulseFastHz - S.PulseSlowHz) * ramp)) % 1
		local k = (1 - math.cos(l.phase * 2 * math.pi)) / 2 -- 0 -> 1 -> 0 per pulse
		part.Transparency = DIM + (BRIGHT - DIM) * k
		if glow then glow.Brightness = GLOW_DIM + (GLOW_BRIGHT - GLOW_DIM) * k end
	end

	if next(shadows) == nil then return end
	sinceCast += dt
	local cast = sinceCast >= castEvery
	if cast then sinceCast = 0 end
	for model, s in pairs(shadows) do
		if not model.Parent or not s.root.Parent then
			s.disc:Destroy()
			shadows[model] = nil
			continue
		end
		local pos = s.root.Position
		if cast then
			local exclude: { Instance } = { model }
			for _, p in ipairs(Players:GetPlayers()) do
				if p.Character then table.insert(exclude, p.Character) end
			end
			local enemies = workspace:FindFirstChild("Enemies")
			if enemies then table.insert(exclude, enemies) end
			ray.FilterDescendantsInstances = exclude
			local hit = workspace:Raycast(pos, Vector3.new(0, -RAY_DOWN, 0), ray)
			s.floorY = if hit then hit.Position.Y else nil
			if s.floorY then
				local a = math.clamp((pos.Y - s.floorY - SH.NearHeight) / (SH.FarHeight - SH.NearHeight), 0, 1)
				local d = s.width * (1 + (SH.FarGrow - 1) * a)
				s.disc.Size = Vector3.new(0.1, d, d)
				s.disc.Transparency = SH.NearTransparency + (SH.FarTransparency - SH.NearTransparency) * a
			else
				s.disc.Transparency = 1
			end
		end
		if s.floorY then s.disc.CFrame = CFrame.new(pos.X, s.floorY + 0.08, pos.Z) * FLAT end -- just over the surface
	end
end)
