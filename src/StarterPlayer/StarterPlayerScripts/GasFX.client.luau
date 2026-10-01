--!strict
-- GasFX (2026-10-01): the world side of a gas cloud, on this client only. For every cloud Server.Gas
-- puts in Workspace.Hazards (a part with a TickPeriod attribute):
--   * puff-in: each emitter Emits a burst and its rate tweens up from 0 over what is left of the grace
--     period (DamageFrom), so the cloud visibly swells in before it can hurt; Cfg.HissSoundId plays at it
--   * mobile budget: on a phone / tablet (DeviceLayout's DeviceClass) or a graphics quality of 1-3 the
--     rate is scaled by Cfg.LowEndRateScale and particles grow by Cfg.LowEndSizeScale: fewer, larger
--     particles, the same fill, inside the ~100/s per emitter mobile budget. Desktop keeps the server rate.
--   * footprint: translucent green plates on the top faces of the kaiju blocks under the cloud, found by
--     a grid of down rays and re-scanned every FLOOR_REFRESH s (blocks get cut away under it), removed
--     when the cloud ends (EndsAt). Plates, not a recolour: Demolition / BlockFX own the block colours.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage.Config.EventConfig).Gas

local FLOOR_REFRESH = 0.5 -- s between footprint scans
local FLOOR_STEP = 3      -- studs between down rays: half a 6-stud block, so no block under the box is missed
local FLOOR_DEPTH = 6     -- studs the rays reach below the cloud's bottom (one block)
local PLATE_LIFT = 0.05   -- studs above the block top, against z-fighting

local player = Players.LocalPlayer
local hazards = workspace:WaitForChild("Hazards")

local function lowEnd(): boolean
	local class = player:GetAttribute("DeviceClass")
	if class == "Phone" or class == "Tablet" then return true end
	local ok, level = pcall(function() return UserSettings().GameSettings.SavedQualityLevel end)
	return ok and level ~= Enum.SavedQualitySetting.Automatic and (level :: any).Value <= 3
end

local function scaled(seq: NumberSequence, k: number): NumberSequence
	local points = {}
	for _, p in ipairs(seq.Keypoints) do
		table.insert(points, NumberSequenceKeypoint.new(p.Time, p.Value * k, p.Envelope * k))
	end
	return NumberSequence.new(points)
end

local function attr(inst: Instance, name: string): number
	local v = inst:GetAttribute(name)
	return if typeof(v) == "number" then v else 0
end

local function puff(cloud: BasePart)
	local low = lowEnd()
	local k = if low then Cfg.LowEndRateScale else 1
	local grace = attr(cloud, "DamageFrom") - workspace:GetServerTimeNow()
	for _, pe in ipairs(cloud:GetChildren()) do
		if pe:IsA("ParticleEmitter") then
			local rate = pe.Rate * k
			if low then pe.Size = scaled(pe.Size, Cfg.LowEndSizeScale) end
			if grace > 0 then -- arrived while puffing in (a late joiner just gets the settled cloud)
				pe:Emit(math.max(1, math.floor(Cfg.PuffBurst * k + 0.5)))
				pe.Rate = 0
				TweenService:Create(pe, TweenInfo.new(grace, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rate = rate }):Play()
			else
				pe.Rate = rate
			end
		end
	end
	if Cfg.HissSoundId ~= "" and grace > 0 then
		local s = Instance.new("Sound")
		s.SoundId = Cfg.HissSoundId
		s.Parent = cloud -- 3D at the cloud, gone with it
		s:Play()
	end
end

local rays = RaycastParams.new()
rays.FilterType = Enum.RaycastFilterType.Include

local function footprint(cloud: BasePart)
	local plates: { [BasePart]: Part } = {} -- block -> its plate
	local folder = Instance.new("Folder")
	folder.Name = "GasFloor"
	folder.Parent = workspace
	while cloud.Parent and workspace:GetServerTimeNow() < attr(cloud, "EndsAt") do
		local kaiju = workspace:FindFirstChild("Kaiju")
		if kaiju then
			rays.FilterDescendantsInstances = { kaiju }
			local half = cloud.Size / 2
			local centre = cloud.Position
			local down = Vector3.new(0, -(cloud.Size.Y + FLOOR_DEPTH), 0)
			local seen: { [BasePart]: boolean } = {}
			for x = -half.X + FLOOR_STEP / 2, half.X, FLOOR_STEP do
				for z = -half.Z + FLOOR_STEP / 2, half.Z, FLOOR_STEP do
					local hit = workspace:Raycast(centre + Vector3.new(x, half.Y, z), down, rays)
					local block = hit and (hit.Instance :: BasePart)
					if block and not seen[block] then
						seen[block] = true
						if not plates[block] then
							local p = Instance.new("Part")
							p.Anchored = true
							p.CanCollide = false
							p.CanQuery = false
							p.CanTouch = false
							p.CastShadow = false
							p.Material = Enum.Material.Neon
							p.Color = Cfg.FloorColor
							p.Transparency = Cfg.FloorTransparency
							p.Size = Vector3.new(block.Size.X, 0.1, block.Size.Z)
							p.CFrame = block.CFrame * CFrame.new(0, block.Size.Y / 2 + PLATE_LIFT, 0)
							p.Parent = folder
							plates[block] = p
						end
					end
				end
			end
			for block, p in pairs(plates) do -- cut away, or no longer the top under the cloud
				if not seen[block] then
					p:Destroy()
					plates[block] = nil
				end
			end
		end
		task.wait(FLOOR_REFRESH)
	end
	folder:Destroy()
end

local function onCloud(child: Instance)
	if not child:IsA("BasePart") or child:GetAttribute("TickPeriod") == nil then return end
	puff(child)
	task.spawn(footprint, child)
end
hazards.ChildAdded:Connect(onCloud)
for _, c in ipairs(hazards:GetChildren()) do onCloud(c) end
