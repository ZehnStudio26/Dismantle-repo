--!strict
-- UFOSpin: turns every saucer on this client, so a UFO reads as a UFO. The saucer's visuals hang off
-- its anchored root (BoundingBox) by a Motor6D; this sets that joint's Transform each frame, which
-- turns the dome and disc (with the lights and the beam) without touching the root the server flies.
-- Client-side only, nothing replicates. Speed: attribute SpinSpeed (degrees/s) on the model, set by
-- Server.UFO on a visit from EventConfig.UFO.Visit.SpinDegreesPerSecond.
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage.Config.Tags)

type Spin = { joint: Motor6D, speed: number, angle: number }
local spins: { [Model]: Spin } = {}

local function watch(inst: Instance)
	if not inst:IsA("Model") or spins[inst] then return end
	local speed = tonumber(inst:GetAttribute("SpinSpeed"))
	local root = inst.PrimaryPart
	if not speed or not root then return end
	-- the joint from the root to the visuals
	local joint: Motor6D? = nil
	for _, j in ipairs(root:GetChildren()) do
		if j:IsA("Motor6D") and j.Part0 == root then joint = j break end
	end
	if not joint then return end
	spins[inst] = { joint = joint, speed = math.rad(speed), angle = 0 }
	inst.Destroying:Once(function() spins[inst] = nil end)
end

workspace.ChildAdded:Connect(watch) -- a visiting UFO is parented straight to Workspace before it descends
for _, c in ipairs(workspace:GetChildren()) do watch(c) end
CollectionService:GetInstanceAddedSignal(Tags.UFO):Connect(watch) -- tagged saucers anywhere (the sandbox one)
for _, u in ipairs(CollectionService:GetTagged(Tags.UFO)) do watch(u) end

RunService.RenderStepped:Connect(function(dt)
	for model, s in pairs(spins) do
		if not model.Parent or not s.joint.Parent then
			spins[model] = nil
		else
			s.angle = (s.angle + s.speed * dt) % (2 * math.pi)
			s.joint.Transform = CFrame.Angles(0, s.angle, 0)
		end
	end
end)
