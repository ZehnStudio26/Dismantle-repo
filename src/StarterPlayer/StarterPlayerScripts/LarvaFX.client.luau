--!strict
-- LarvaFX (2026-10-01): client visuals for the egg / larva event, read only from what already
-- replicates (tags, attributes, Humanoid.Health). Nothing is sent back to the server.
--   EGG    every model tagged "Egg" gets a client-only visual: an anchored, non-querying clone of its
--          PrimaryPart parented INSIDE the egg model (the server's Destroy removes it too), with the
--          real part hidden by LocalTransparencyModifier. The real egg is unanchored and may be
--          physics-owned by a nearby client, so moving it would fight replication; the clone just
--          follows it. From HatchAt / HatchSeconds (set by Server.Egg) the clone rocks on its base,
--          harder and faster as the hatch nears, cracks at CrackAt[1] / CrackAt[2] (material swap
--          until crack decals exist), and the egg closest to hatching wears the one pooled Pulse
--          highlight. Burst = true (hatch, or popped by Server.Enemies.HitEgg) -> goo burst.
--          An EggHP drop flashes it white.
--   LARVA  a Humanoid.Health drop flashes the model white for FlashSeconds with the one pooled Flash
--          highlight (Roblox renders at most 31 Highlights); death squashes and shrinks the visible
--          parts and bursts goo (Server.Larvae turns BreakJointsOnDeath off so the corpse holds).
-- Authored children: Goo (ParticleEmitter, emitted from one pooled part), Flash / Pulse (Highlight).
-- Sound ids live in EventConfig.Egg (CrackSound / HatchSound / DeathSound); "" plays nothing.
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Cfg = require(ReplicatedStorage.Config.EventConfig).Egg
local Tags = require(ReplicatedStorage.Config.Tags)

local CRACK_MATERIAL = { Enum.Material.Slate, Enum.Material.CrackedLava } -- stage 1, stage 2
local WOBBLE_DEG = { 2, 14 }      -- rock amplitude at the start / at the hatch
local WOBBLE_SPEED = { 5, 22 }    -- rock rate (rad/s) at the start / at the hatch
local PULSE_FILL = 0.55           -- strongest pulse fill (1 - FillTransparency) right before the hatch
local GOO_HATCH, GOO_CRACK, GOO_DEATH = 40, 6, 24 -- particles per burst
local SQUASH_SECONDS, SHRINK_SECONDS = 0.1, 0.25

local fxFolder = workspace:FindFirstChild("ClientFX") or Instance.new("Folder")
fxFolder.Name = "ClientFX"
fxFolder.Parent = workspace

-- ---------- pooled pieces ----------
local gooPart = Instance.new("Part")
gooPart.Name = "LarvaGoo"
gooPart.Anchored, gooPart.CanCollide, gooPart.CanQuery, gooPart.CanTouch, gooPart.CastShadow = true, false, false, false, false
gooPart.Transparency = 1
gooPart.Size = Vector3.one * 0.2
gooPart.Parent = fxFolder
local goo = (script:WaitForChild("Goo") :: ParticleEmitter):Clone()
goo.Enabled = false
goo.Parent = gooPart

local flash = (script:WaitForChild("Flash") :: Highlight):Clone()
flash.Enabled = false
flash.Parent = fxFolder
local pulse = (script:WaitForChild("Pulse") :: Highlight):Clone()
pulse.Enabled = false
pulse.Parent = fxFolder

local function play(id: string, at: Instance)
	if id == "" then return end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Parent = at
	s:Play()
	Debris:AddItem(s, 5)
end

-- particles keep their world position once emitted, so one part serves every burst
local function burst(at: Vector3, count: number, soundId: string)
	gooPart.Position = at
	goo:Emit(count)
	play(soundId, gooPart)
end

local flashToken = 0
local function flashOn(target: Instance)
	flashToken += 1
	local mine = flashToken
	flash.Adornee = target
	flash.Enabled = true
	task.delay(Cfg.FlashSeconds, function()
		if flashToken ~= mine then return end -- a newer hit moved it
		flash.Enabled = false
		flash.Adornee = nil
	end)
end

-- ---------- eggs ----------
type Egg = { model: Model, real: BasePart?, visual: BasePart?, material: Enum.Material, stage: number, hp: number, lastPos: Vector3, conn: RBXScriptConnection? }
local eggs: { [Instance]: Egg } = {}

-- the visual clone, once the real part is there (built lazily from the frame loop)
local function build(e: Egg)
	local real = e.model.PrimaryPart or e.model:FindFirstChildWhichIsA("BasePart")
	if not real then return end
	local v = real:Clone()
	for _, c in ipairs(v:GetChildren()) do
		if not (c:IsA("Decal") or c:IsA("SurfaceAppearance")) then c:Destroy() end
	end
	v.Name = "EggVisual"
	v.Anchored, v.CanCollide, v.CanQuery, v.CanTouch = true, false, false, false
	v.Parent = e.model
	real.LocalTransparencyModifier = 1
	e.real, e.visual, e.material = real, v, v.Material
end

local function addEgg(inst: Instance)
	if eggs[inst] or not inst:IsA("Model") or not inst:IsDescendantOf(workspace) then return end
	local e: Egg = { model = inst, real = nil, visual = nil, material = Enum.Material.Plastic, stage = 0,
		hp = tonumber(inst:GetAttribute("EggHP")) or Cfg.EggHP, lastPos = inst:GetPivot().Position }
	eggs[inst] = e
	e.conn = inst:GetAttributeChangedSignal("EggHP"):Connect(function()
		local hp = tonumber(inst:GetAttribute("EggHP")) or e.hp
		if hp < e.hp and hp > 0 then flashOn(e.visual or inst) end
		e.hp = hp
	end)
end

local function removeEgg(inst: Instance)
	local e = eggs[inst]
	if not e then return end
	eggs[inst] = nil
	if e.conn then e.conn:Disconnect() end
	if pulse.Adornee == e.visual then pulse.Enabled, pulse.Adornee = false, nil end
	if inst:GetAttribute("Burst") == true then burst(e.lastPos, GOO_HATCH, Cfg.HatchSound) end
end

local function lerp(range: { number }, t: number): number
	return range[1] + (range[2] - range[1]) * t
end

local function stepEggs()
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()
	local soonest: Egg?, soonestP = nil, 0
	for _, e in pairs(eggs) do
		if not e.visual then build(e) end
		local real, v = e.real, e.visual
		if real and v and real.Parent then
			local at = tonumber(e.model:GetAttribute("HatchAt"))
			local secs = tonumber(e.model:GetAttribute("HatchSeconds")) or Cfg.HatchSeconds
			local p = if at then math.clamp(1 - (at - now) / math.max(secs, 0.01), 0, 1) else 0
			-- rock about the base, so it tips rather than spins
			local amp = math.rad(lerp(WOBBLE_DEG, p * p))
			local t = clock * lerp(WOBBLE_SPEED, p)
			local base = CFrame.new(0, -real.Size.Y / 2, 0)
			v.CFrame = real.CFrame * base * CFrame.Angles(math.sin(t) * amp, 0, math.cos(t * 1.3) * amp * 0.7) * base:Inverse()
			e.lastPos = real.Position
			local stage = if p >= Cfg.CrackAt[2] then 2 elseif p >= Cfg.CrackAt[1] then 1 else 0
			if stage > e.stage then
				e.stage = stage
				v.Material = CRACK_MATERIAL[stage] or e.material
				burst(real.Position + Vector3.yAxis * real.Size.Y * 0.3, GOO_CRACK, Cfg.CrackSound)
			end
			if p > soonestP then soonest, soonestP = e, p end
		end
	end
	if soonest then
		pulse.Adornee = soonest.visual
		pulse.Enabled = true
		local beat = 0.5 + 0.5 * math.sin(clock * lerp(WOBBLE_SPEED, soonestP) * 0.6)
		pulse.FillTransparency = 1 - PULSE_FILL * soonestP * beat
	elseif pulse.Enabled then
		pulse.Enabled, pulse.Adornee = false, nil
	end
end

for _, inst in ipairs(CollectionService:GetTagged(Tags.Egg)) do addEgg(inst) end
CollectionService:GetInstanceAddedSignal(Tags.Egg):Connect(addEgg)
CollectionService:GetInstanceRemovedSignal(Tags.Egg):Connect(removeEgg)

-- ---------- larvae ----------
local watched: { [Instance]: RBXScriptConnection } = {}

local function pop(model: Model)
	burst(model:GetPivot().Position, GOO_DEATH, Cfg.DeathSound)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local s = d.Size
			local squash = TweenService:Create(d, TweenInfo.new(SQUASH_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = Vector3.new(s.X * 1.4, s.Y * 0.35, s.Z * 1.4) })
			squash.Completed:Once(function()
				TweenService:Create(d, TweenInfo.new(SHRINK_SECONDS, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Size = s * 0.05 }):Play()
			end)
			squash:Play()
		end
	end
end

local function addLarva(inst: Instance)
	if watched[inst] or not inst:IsA("Model") or Players:GetPlayerFromCharacter(inst) then return end
	local hum = inst:FindFirstChildOfClass("Humanoid") or inst:WaitForChild("Humanoid", 5)
	if not hum or not hum:IsA("Humanoid") or watched[inst] or not inst:IsDescendantOf(workspace) then return end
	local last = hum.Health
	watched[inst] = hum.HealthChanged:Connect(function(health: number)
		if health < last then
			if health <= 0 then
				local c = watched[inst]
				if c then c:Disconnect() end
				pop(inst :: Model)
			else
				flashOn(inst)
			end
		end
		last = health
	end)
end

local function removeLarva(inst: Instance)
	local c = watched[inst]
	watched[inst] = nil
	if c then c:Disconnect() end
	if flash.Adornee == inst then flash.Enabled, flash.Adornee = false, nil end
end

for _, inst in ipairs(CollectionService:GetTagged(Tags.Enemy)) do task.spawn(addLarva, inst) end
CollectionService:GetInstanceAddedSignal(Tags.Enemy):Connect(addLarva)
CollectionService:GetInstanceRemovedSignal(Tags.Enemy):Connect(removeLarva)

RunService.PreRender:Connect(stepEggs)
