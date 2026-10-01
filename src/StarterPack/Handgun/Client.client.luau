--!strict
-- Handgun client (T-2 / U-4, Shayan 2026-09-29): auto lock-on. While the handgun is held, the nearest
-- living larva or incubating egg (tag "Egg", 2026-10-01; a larva wins when about as near) within the
-- Gun.Range tier that the muzzle can see is locked: a red outline and a ring
-- over it (Handgun.LockHighlight / Handgun.LockOn, authored in Studio), and the character turns to face
-- it. Q (gamepad L1, or the NEXT touch button) switches to the next larva in range, nearest first.
-- Click to fire, hold to keep firing at the Gun.FireRate tier. A crosshair sits in the middle of the
-- screen while the gun is out (StarterGui.Crosshair, authored in Studio; red while a larva is locked,
-- hidden in the top-down map view), and the camera moves over the right shoulder so the crosshair
-- sits past the character. With nothing locked the shot goes through the crosshair. D8 unlimited ammo: no clip, no reload. Server.Gun checks every shot (range,
-- rate, enemies only) and applies the damage; other players see the flash and tracer through GunFire.
-- Each shot kicks the right arm (Handgun.Animations.Recoil, an R6 KeyframeSequence authored in
-- Studio). Until it is published, it is registered at run time, which only plays in Studio; publish it
-- and put the id on Handgun.Recoil (an Animation) so every player sees it.
-- The model, sounds and muzzle flash come from the Handgun asset; its own scripts are removed.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local UpgradeConfig = require(ReplicatedStorage.Config.UpgradeConfig)
local Tags = require(ReplicatedStorage.Config.Tags)
local GunFire: RemoteEvent = ReplicatedStorage.Remotes.GunFire
local function stat(name: string): number return UpgradeConfig.Value(Players.LocalPlayer, "Gun", name) end

local LOCK_KEEP = 1.15      -- a held lock survives until the larva is this far past the range (no flicker at the edge)
local LOCK_HZ = 10          -- target checks per second
local EGG_BIAS = 1          -- studs added to an egg's distance when sorting, so an equally near larva is locked first
local TURN_SHARPNESS = 14   -- how fast the body swings round to face the lock
local SPIN_DEG = 120        -- ring spin, degrees per second
local AIM_DISTANCE = 1000
local TRACER_SECONDS, FLASH_SECONDS = 0.07, 0.05

local player = Players.LocalPlayer
local tool = script.Parent :: Tool
local camera = workspace.CurrentCamera
local handle = tool:WaitForChild("Handle") :: BasePart
local muzzle = handle:WaitForChild("MuzzleFX") :: Attachment
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
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Transparency = 1
	p.Size = Vector3.one * 0.2
	p.Parent = fxFolder
	return p
end

local impactPart = fxPart("HandgunImpact")
local sparks = sparkTemplate:Clone()
sparks.Enabled = false
sparks.Parent = impactPart

local tracers: { Part } = {}
for i = 1, 6 do
	local t = fxPart("HandgunTracer")
	t.Material = Enum.Material.Neon
	t.Color = Color3.fromRGB(255, 225, 150)
	tracers[i] = t
end
local nextTracer = 1

-- the lock marker: clones of the authored templates, re-adorned to each new target
local ring = (tool:WaitForChild("LockOn") :: BillboardGui):Clone()
ring.Parent = player:WaitForChild("PlayerGui")
local spinner = ring:WaitForChild("Spinner") :: Frame
local outline = (tool:WaitForChild("LockHighlight") :: Highlight):Clone()
outline.Parent = fxFolder

-- the crosshair (one per player: StarterGui.Crosshair has ResetOnSpawn off)
local crosshair = player.PlayerGui:WaitForChild("Crosshair", 5) :: ScreenGui?
local reticleParts: { GuiObject } = {}
if crosshair then
	for _, d in ipairs(crosshair:GetDescendants()) do
		if d:IsA("Frame") and d.Name ~= "Reticle" then table.insert(reticleParts, d) end
	end
end
local RETICLE_IDLE, RETICLE_LOCKED = Color3.fromRGB(245, 245, 250), Color3.fromRGB(225, 70, 60) -- UITheme Text / Red
local function paintReticle(isLocked: boolean)
	for _, f in ipairs(reticleParts) do f.BackgroundColor3 = if isLocked then RETICLE_LOCKED else RETICLE_IDLE end
end
local function showCrosshair(on: boolean)
	if crosshair then crosshair.Enabled = on and player:GetAttribute("TopView") ~= true end
end

-- muzzle flash (the asset's light and flipbook billboard), tracer, and sparks at the hit (red on an enemy)
local function playShot(gun: Instance?, from: Vector3, to: Vector3, hit: boolean, enemy: boolean)
	local h = gun and gun:FindFirstChild("Handle")
	local light = h and h:FindFirstChild("Flash")
	local flare = gun and gun:FindFirstChild("Flare")
	local flash = flare and flare:FindFirstChild("MuzzleFlash")
	if light and light:IsA("PointLight") then
		light.Enabled = true
		task.delay(FLASH_SECONDS, function() light.Enabled = false end)
	end
	if flash and flash:IsA("BillboardGui") then
		flash.Enabled = true
		task.delay(FLASH_SECONDS, function() flash.Enabled = false end)
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

local function params(): RaycastParams
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local list: { Instance } = { fxFolder }
	if player.Character then table.insert(list, player.Character) end
	p.FilterDescendantsInstances = list
	return p
end

local function isEnemy(inst: Instance?): boolean
	local model = inst and inst:FindFirstAncestorWhichIsA("Model")
	return model ~= nil and CollectionService:HasTag(model, Tags.Enemy)
end

-- ---------- lock-on ----------
local locked: Model? = nil
local lockedRoot: BasePart? = nil

local function myRoot(): BasePart?
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

-- an incubating egg: not yet hatched or popped (Server.Egg / Enemies set HatchAt, EggHP and Burst)
local function eggRoot(m: Instance): BasePart?
	if not m:IsA("Model") or not m:IsDescendantOf(workspace) or m:GetAttribute("Burst") == true then return nil end
	if (tonumber(m:GetAttribute("EggHP")) or 1) <= 0 then return nil end
	local at = tonumber(m:GetAttribute("HatchAt"))
	if at and workspace:GetServerTimeNow() >= at then return nil end
	return m.PrimaryPart
end

local function larvaRoot(m: Instance): BasePart?
	if CollectionService:HasTag(m, Tags.Egg) then return eggRoot(m) end
	if not m:IsA("Model") or not m:IsDescendantOf(workspace) or Players:GetPlayerFromCharacter(m) then return nil end
	if m:GetAttribute("Descending") == true then return nil end -- still floating down the UFO beam
	local hum = m:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return nil end
	return m.PrimaryPart or m:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- the muzzle sees the larva: the first thing the ray meets is part of it
local function inSight(m: Model, r: BasePart): boolean
	local from = muzzle.WorldPosition
	local hit = workspace:Raycast(from, r.Position - from, params())
	return hit == nil or hit.Instance:IsDescendantOf(m)
end

local function setLock(m: Model?, r: BasePart?)
	if m == locked then return end
	locked, lockedRoot = m, r
	ring.Adornee = r
	ring.Enabled = r ~= nil
	outline.Adornee = m
	outline.Enabled = m ~= nil
	paintReticle(m ~= nil)
	local me = myRoot()
end

-- every larva and egg the muzzle can see within the range, nearest first (eggs sorted EGG_BIAS further)
type Candidate = { model: Model, root: BasePart, d: number }
local function candidates(me: BasePart): { Candidate }
	local range = stat("Range")
	local list: { Candidate } = {}
	local function consider(m: Instance, bias: number)
		local r = larvaRoot(m)
		if r then
			local d = (r.Position - me.Position).Magnitude
			if d <= range and inSight(m :: Model, r) then table.insert(list, { model = m :: Model, root = r, d = d + bias }) end
		end
	end
	for _, m in ipairs(CollectionService:GetTagged(Tags.Enemy)) do consider(m, 0) end
	for _, m in ipairs(CollectionService:GetTagged(Tags.Egg)) do consider(m, EGG_BIAS) end
	table.sort(list, function(a, b) return a.d < b.d end)
	return list
end

local function pickTarget()
	local me = myRoot()
	if not me then setLock(nil, nil) return end
	-- keep the current lock (auto or switched to) while it is alive, near enough and in sight
	if locked and lockedRoot then
		local r = larvaRoot(locked)
		if r and (r.Position - me.Position).Magnitude <= stat("Range") * LOCK_KEEP and inSight(locked, r) then return end
	end
	local best = candidates(me)[1]
	setLock(best and best.model, best and best.root)
end

-- Q: the next larva in range after the locked one, nearest first, wrapping round
local function switchTarget()
	local me = myRoot()
	if not me then return end
	local list = candidates(me)
	if #list == 0 then return end
	local at = 0
	for i, c in ipairs(list) do if c.model == locked then at = i end end
	local nxt = list[at % #list + 1]
	if nxt.model == locked then return end -- only one larva in range
	setLock(nxt.model, nxt.root)
end

-- ---------- recoil ----------
-- the published clip when Handgun.Recoil has an id, else the authored KeyframeSequence registered for this session
local recoilTrack: AnimationTrack? = nil
local function loadRecoil(hum: Humanoid)
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then return end
	local anim = tool:FindFirstChild("Recoil")
	local id = if anim and anim:IsA("Animation") and anim.AnimationId ~= "" then anim.AnimationId else nil
	if not id then
		local folder = tool:FindFirstChild("Animations")
		local kfs = folder and folder:FindFirstChild("Recoil")
		if kfs and kfs:IsA("KeyframeSequence") then
			local ok, res = pcall(function() return KeyframeSequenceProvider:RegisterKeyframeSequence(kfs) end)
			if ok then id = res else warn("[Gun] could not register the recoil clip: " .. tostring(res)) end
		end
	end
	if not id then return end
	local a = Instance.new("Animation")
	a.AnimationId = id
	recoilTrack = animator:LoadAnimation(a)
	recoilTrack.Priority = Enum.AnimationPriority.Action
	recoilTrack.Looped = false
end

-- ---------- firing ----------
local equipped, holding = false, false
local lastShot = 0

local function fire()
	if os.clock() - lastShot < 1 / stat("FireRate") then return end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	lastShot = os.clock()
	if fireSound then
		fireSound.PlaybackSpeed = 0.9 + math.random() * 0.2
		fireSound:Play()
	end
	if recoilTrack then recoilTrack:Play(0.02, 1, 1) end
	local p = params()
	local aimPoint: Vector3
	if lockedRoot then
		aimPoint = lockedRoot.Position
	else
		local centre = camera.ViewportSize / 2 -- through the crosshair
		local ray = camera:ViewportPointToRay(centre.X, centre.Y)
		local aimHit = workspace:Raycast(ray.Origin, ray.Direction * AIM_DISTANCE, p)
		aimPoint = if aimHit then aimHit.Position else ray.Origin + ray.Direction * AIM_DISTANCE
	end
	local from = muzzle.WorldPosition
	local dir = aimPoint - from
	if dir.Magnitude < 0.01 then dir = camera.CFrame.LookVector end
	local range = stat("Range")
	local hit = workspace:Raycast(from, dir.Unit * range, p)
	local to = if hit then hit.Position else from + dir.Unit * range
	playShot(tool, from, to, hit ~= nil, hit ~= nil and isEnemy(hit.Instance))
	GunFire:FireServer(if hit then hit.Instance else nil, to)
end

local checkAcc = 0
local function step(dt: number)
	if not equipped then return end
	checkAcc += dt
	if checkAcc >= 1 / LOCK_HZ then
		checkAcc = 0
		pickTarget()
	end
	spinner.Rotation = (spinner.Rotation + SPIN_DEG * dt) % 360
	-- face the lock: the body turns on its own while a larva is locked, and walks normally without one
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local me = myRoot()
	if hum and me then
		if lockedRoot then
			hum.AutoRotate = false
			local look = (lockedRoot.Position - me.Position) * Vector3.new(1, 0, 1)
			if look.Magnitude > 0.1 then
				local goal = CFrame.lookAt(me.Position, me.Position + look)
				me.CFrame = me.CFrame:Lerp(goal, 1 - math.exp(-TURN_SHARPNESS * dt))
			end
		elseif not hum.AutoRotate then
			hum.AutoRotate = true
		end
	end
	if holding then fire() end
end
RunService.PreSimulation:Connect(step)

-- ---------- over-the-shoulder camera ----------
-- Like a third-person shooter (DevForum "camera boom"): while the gun is out the camera slides right and
-- up in its own space, so the centre crosshair sits past the character's shoulder instead of on the
-- character. It runs just after the default camera (Camera + 1), which rebuilds its CFrame from the
-- focus and look direction every frame, so the shift never accumulates. Humanoid.CameraOffset is not
-- used: it turns with the character, and the lock-on turns the character toward the larva.
local SHOULDER = Vector3.new(2.5, 0.8, 0)  -- studs right / up, camera space
local SHOULDER_SHARPNESS = 10               -- ease in on equip, out on unequip
local WALL_GAP = 0.4                        -- keep this far off a wall the shift would push into
local SHOULDER_BIND = "HandgunShoulder"
local shoulderAlpha, shoulderBound = 0, false

local function shoulderStep(dt: number)
	local wanted = equipped and player:GetAttribute("TopView") ~= true
	shoulderAlpha += ((if wanted then 1 else 0) - shoulderAlpha) * (1 - math.exp(-SHOULDER_SHARPNESS * dt))
	if not wanted and shoulderAlpha < 0.01 then
		shoulderAlpha, shoulderBound = 0, false
		RunService:UnbindFromRenderStep(SHOULDER_BIND)
		return
	end
	if camera.CameraType ~= Enum.CameraType.Custom then return end -- top view / spectating own the camera
	local cf = camera.CFrame
	if (cf.Position - camera.Focus.Position).Magnitude < 1.5 then return end -- zoomed into first person
	local offset = cf:VectorToWorldSpace(SHOULDER * shoulderAlpha)
	local hit = workspace:Raycast(cf.Position, offset, params())
	if hit then offset = offset.Unit * math.max(0, (hit.Position - cf.Position).Magnitude - WALL_GAP) end
	camera.CFrame = cf + offset
end

local function bindShoulder()
	if shoulderBound then return end
	shoulderBound = true
	RunService:BindToRenderStep(SHOULDER_BIND, Enum.RenderPriority.Camera.Value + 1, shoulderStep)
end

local SWITCH_ACTION = "HandgunNextTarget"
tool.Equipped:Connect(function()
	equipped = true
	paintReticle(locked ~= nil)
	showCrosshair(true)
	bindShoulder()
	checkAcc = 1 -- look for a target on the first frame
	if equipSound then equipSound:Play() end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and not recoilTrack then loadRecoil(hum) end
	ContextActionService:BindAction(SWITCH_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then switchTarget() end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonL1)
	ContextActionService:SetTitle(SWITCH_ACTION, "NEXT")
end)
tool.Unequipped:Connect(function()
	equipped, holding = false, false
	showCrosshair(false)
	ContextActionService:UnbindAction(SWITCH_ACTION)
	if recoilTrack then recoilTrack:Stop(0) end
	setLock(nil, nil)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum.AutoRotate = true end
end)
tool.Activated:Connect(function() holding = true; fire() end)
tool.Deactivated:Connect(function() holding = false end)
tool.Destroying:Connect(function() -- dying with the gun out skips Unequipped
	ContextActionService:UnbindAction(SWITCH_ACTION)
	if shoulderBound then RunService:UnbindFromRenderStep(SHOULDER_BIND) end
	showCrosshair(false)
	ring:Destroy(); outline:Destroy()
end)

-- the top-down map view hides the crosshair; back in third person it returns while the gun is out
player:GetAttributeChangedSignal("TopView"):Connect(function() showCrosshair(equipped) end)

-- other players' shots: the server relays them so everyone sees the flash and the tracer
GunFire.OnClientEvent:Connect(function(shooter: Player, from: Vector3, to: Vector3, hit: boolean, enemy: boolean)
	if shooter == player or typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then return end
	local char = shooter.Character
	playShot(char and char:FindFirstChild(tool.Name), from, to, hit == true, enemy == true)
end)
