--!strict
-- Gun client: one shot per click, fired from the MUZZLE, not the camera.
--   aim   a long ray from the camera through the cursor finds what the player is pointing at
--   shot  a ray from the muzzle toward that point, out to the Gun.Range tier, decides the hit
-- (Before 2026-09-28 the Range-long ray started at the camera, which sits well behind the player in
-- third person, so most shots ended in the air before reaching the larva: "[Gun] shot nothing".)
-- The server decides whether the hit was an enemy and applies the damage.
-- VFX (authored on the tool): Handle.MuzzleFX holds Flash / Smoke / FlashLight; Handle.ImpactSparks is
-- the impact template. The tracer is a pooled neon Part. Other players' shots arrive from the server
-- through GunFire and play the same effects on their gun.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local UpgradeConfig = require(ReplicatedStorage.Config.UpgradeConfig)
local Tags = require(ReplicatedStorage.Config.Tags)
local GunFire: RemoteEvent = ReplicatedStorage.Remotes.GunFire
-- fire rate and range mirror the server's Gun tiers, read live from the player's attributes
local function stat(name: string): number return UpgradeConfig.Value(Players.LocalPlayer, "Gun", name) end

local AIM_DISTANCE = 1000
local TRACER_SECONDS = 0.07
local FLASH_SECONDS = 0.05

local player = Players.LocalPlayer
local tool = script.Parent :: Tool
local camera = workspace.CurrentCamera
local lastShot = 0

local handle = tool:WaitForChild("Handle") :: BasePart
local fireSound = handle:FindFirstChild("FireSound") :: Sound?
local equipSound = handle:FindFirstChild("EquipSound") :: Sound?
local sparkTemplate = handle:WaitForChild("ImpactSparks") :: ParticleEmitter

-- ---------- effects ----------
local fxFolder = workspace:FindFirstChild("ClientFX") or Instance.new("Folder")
fxFolder.Name = "ClientFX"
fxFolder.Parent = workspace

local function fxPart(name: string): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	p.Parent = fxFolder
	return p
end

local impactPart = fxPart("GunImpact")
local sparks = sparkTemplate:Clone()
sparks.Enabled = false
sparks.Parent = impactPart

local tracers: { Part } = {}
for i = 1, 6 do
	local t = fxPart("GunTracer")
	t.Material = Enum.Material.Neon
	t.Color = Color3.fromRGB(255, 225, 150)
	tracers[i] = t
end
local nextTracer = 1

local function muzzleOf(gun: Instance?): Attachment?
	local h = gun and gun:FindFirstChild("Handle")
	local a = h and h:FindFirstChild("MuzzleFX")
	return if a and a:IsA("Attachment") then a else nil
end

local function isEnemy(inst: Instance?): boolean
	local model = inst and inst:FindFirstAncestorWhichIsA("Model")
	return model ~= nil and CollectionService:HasTag(model, Tags.Enemy)
end

-- muzzle flash, smoke, light, tracer, and sparks at the hit point (red on an enemy)
local function playShot(gun: Instance?, from: Vector3, to: Vector3, hit: boolean, enemy: boolean)
	local m = muzzleOf(gun)
	if m then
		local flash = m:FindFirstChild("Flash") :: ParticleEmitter?
		local smoke = m:FindFirstChild("Smoke") :: ParticleEmitter?
		local light = m:FindFirstChild("FlashLight") :: PointLight?
		if flash then flash:Emit(6) end
		if smoke then smoke:Emit(2) end
		if light then
			light.Enabled = true
			task.delay(FLASH_SECONDS, function() light.Enabled = false end)
		end
	end
	local length = (to - from).Magnitude
	if length > 0.5 then
		local t = tracers[nextTracer]
		nextTracer = nextTracer % #tracers + 1
		t.Size = Vector3.new(0.12, 0.12, length)
		t.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -length / 2)
		t.Transparency = 0.1
		TweenService:Create(t, TweenInfo.new(TRACER_SECONDS), { Transparency = 1 }):Play()
	end
	if hit then
		impactPart.Position = to
		sparks.Color = ColorSequence.new(if enemy then Color3.fromRGB(255, 70, 60) else Color3.fromRGB(255, 220, 140))
		sparks:Emit(if enemy then 14 else 8)
	end
end

-- ---------- firing ----------
local function params(): RaycastParams
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local list: { Instance } = { fxFolder }
	if player.Character then table.insert(list, player.Character) end
	p.FilterDescendantsInstances = list
	return p
end

tool.Equipped:Connect(function()
	if equipSound then equipSound:Play() end
end)

tool.Activated:Connect(function()
	if os.clock() - lastShot < 1 / stat("FireRate") then return end
	lastShot = os.clock()
	if fireSound then fireSound:Play() end
	local muzzle = muzzleOf(tool)
	if not muzzle then return end
	local p = params()
	-- what is the cursor on?
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local aimHit = workspace:Raycast(ray.Origin, ray.Direction * AIM_DISTANCE, p)
	local aimPoint = if aimHit then aimHit.Position else ray.Origin + ray.Direction * AIM_DISTANCE
	-- the shot itself leaves the muzzle
	local from = muzzle.WorldPosition
	local dir = aimPoint - from
	if dir.Magnitude < 0.01 then dir = camera.CFrame.LookVector end
	local range = stat("Range")
	local hit = workspace:Raycast(from, dir.Unit * range, p)
	local to = if hit then hit.Position else from + dir.Unit * range
	local enemy = hit ~= nil and isEnemy(hit.Instance)
	playShot(tool, from, to, hit ~= nil, enemy)
	GunFire:FireServer(if hit then hit.Instance else nil, to)
end)

-- other players' shots: the server relays them so everyone sees the flash and the tracer
GunFire.OnClientEvent:Connect(function(shooter: Player, from: Vector3, to: Vector3, hit: boolean, enemy: boolean)
	if shooter == player or typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then return end
	local char = shooter.Character
	playShot(char and char:FindFirstChild("Gun"), from, to, hit == true, enemy == true)
end)
