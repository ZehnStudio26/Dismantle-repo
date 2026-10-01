--!strict
-- SurvivorFX (2026-10-01): makes a waiting survivor findable, client-side, for every model tagged
-- "Survivor" (Server.Survivor puts them in Workspace.Pickups). Per survivor, no per-frame script work:
--   MARKER  Head.Marker, authored on Templates.Survivor: one plain white "!" (pixel font, dark outline,
--           AlwaysOnTop; Ayesh 2026-10-01: no pillar, no disc, no timer bar). It bobs (one looping tween on
--           the billboard's StudsOffset) and pops (Fusion Spring on its Pulse UIScale) with every HELP call
--   ARROW   EventFX.arrow(model, "SOS" + distance) while he is off-screen
--   HELP    Head.Help (authored bubble, a small copy of Speech) pops in for HelpShowSeconds every
--           HelpEvery, Hydrated with Fusion 0.3 like SurvivorSpeech; plus a 3D Sound on his root when
--           HelpSoundId is set (RollOffMaxDistance HelpHearRange, so distance is audible)
-- Rescued (set by the server before the thanks period): all of the above goes, confetti bursts from a
-- Terrain attachment (it outlives the model) and RescueSoundId plays there. The model leaving (expired,
-- run cleared) tears it down too. The "THANK YOU!" bubble stays SurvivorSpeech's.
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Fusion = require(ReplicatedStorage.Fusion)
local EventFX = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("EventFX"))
local T = require(ReplicatedStorage.Config.UITheme)
local Tags = require(ReplicatedStorage.Config.Tags)
local EventConfig = require(ReplicatedStorage.Config.EventConfig)

local Cfg = EventConfig.Survivor
local ORANGE: Color3 = EventConfig.Colors.Survivor

local function sound(id: string, parent: Instance, volume: number, range: number?): Sound?
	if id == "" then return nil end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	if range then s.RollOffMaxDistance = range end
	s.Parent = parent
	return s
end

-- confetti + jingle at a world point, on a Terrain attachment so it survives the model's Destroy
local function celebrate(at: Vector3)
	local a = Instance.new("Attachment")
	a.Parent = workspace.Terrain
	a.WorldPosition = at
	local p = Instance.new("ParticleEmitter")
	p.Rate = 0
	p.Color = ColorSequence.new(ORANGE, T.Palette.Gold)
	p.LightEmission = 0.4
	p.Size = NumberSequence.new(0.35)
	p.Lifetime = NumberRange.new(0.8, 1.3)
	p.Speed = NumberRange.new(18, 28)
	p.SpreadAngle = Vector2.new(50, 50)
	p.Acceleration = Vector3.new(0, -40, 0)
	p.Drag = 2
	p.Rotation = NumberRange.new(0, 360)
	p.RotSpeed = NumberRange.new(-300, 300)
	p.Parent = a
	p:Emit(Cfg.ConfettiCount)
	local jingle = sound(Cfg.RescueSoundId, a, 0.8)
	if jingle then jingle:Play() end
	Debris:AddItem(a, 4) -- longest particle 1.3 s; leaves room for a short jingle
end

local seen: { [Instance]: boolean } = {}
local finishers: { [Instance]: (rescued: boolean) -> () } = {}

local function bind(model: Instance)
	if seen[model] or not model:IsA("Model") then return end
	seen[model] = true
	task.spawn(function()
		local root = model:WaitForChild("HumanoidRootPart", 10) :: BasePart?
		local head = model:WaitForChild("Head", 10)
		if not root or not head or not model.Parent or model:GetAttribute("Rescued") then return end
		local scope = Fusion.scoped(Fusion)

		-- ARROW
		local arrow = EventFX.arrow(model, { color = ORANGE, text = "SOS", showDistance = true })
		table.insert(scope, function() arrow:Destroy() end)

		-- MARKER: the white "!" bobs above his head
		local marker = head:FindFirstChild("Marker") :: BillboardGui?
		if marker then
			local bob = TweenService:Create(marker, TweenInfo.new(Cfg.MarkerBobSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ StudsOffset = marker.StudsOffset + Vector3.yAxis * Cfg.MarkerBobHeight })
			bob:Play()
			table.insert(scope, function() bob:Cancel() end)
		end

		-- HELP: bubble + marker pop + call, every HelpEvery
		local calling = scope:Value(false)
		local function target(on: any, off: any) return scope:Computed(function(use) return if use(calling) then on else off end) end
		local pulse = marker and marker:FindFirstChild("Pulse", true) :: UIScale?
		if pulse then scope:Hydrate(pulse) { Scale = scope:Spring(target(1.25, 1), 30, 0.45) } end
		local help = head:FindFirstChild("Help") :: BillboardGui?
		local group = help and help:FindFirstChild("Group") :: CanvasGroup?
		local helpScale = group and group:FindFirstChildOfClass("UIScale")
		if help and group and helpScale then
			scope:Hydrate(group) { GroupTransparency = scope:Tween(target(0, 1), TweenInfo.new(0.18, Enum.EasingStyle.Quad)) }
			scope:Hydrate(helpScale) { Scale = scope:Spring(target(1, 0.6), 28, 0.55) }
			help.Enabled = true -- shown / hidden by GroupTransparency from here on
		end
		local call = sound(Cfg.HelpSoundId, root, Cfg.HelpVolume, Cfg.HelpHearRange)
		if call then table.insert(scope, call) end
		local loop = task.spawn(function()
			task.wait(0.5) -- first call just after he appears
			while true do
				calling:set(true)
				if call then call:Play() end
				task.wait(Cfg.HelpShowSeconds)
				calling:set(false)
				task.wait(math.max(Cfg.HelpEvery - Cfg.HelpShowSeconds, 0))
			end
		end)
		table.insert(scope, function() task.cancel(loop) end)

		local function finish(rescued: boolean)
			if finishers[model] == nil then return end
			finishers[model] = nil
			if rescued then celebrate(root.Position) end
			Fusion.doCleanup(scope)
			if marker then marker.Enabled = false end
			if help then help.Enabled = false end
		end
		finishers[model] = finish
		table.insert(scope, model:GetAttributeChangedSignal("Rescued"):Connect(function()
			if model:GetAttribute("Rescued") then finish(true) end
		end))
		if not model.Parent then finish(false) end -- left while we were setting up
	end)
end

CollectionService:GetInstanceAddedSignal(Tags.Survivor):Connect(bind)
CollectionService:GetInstanceRemovedSignal(Tags.Survivor):Connect(function(model)
	seen[model] = nil
	local finish = finishers[model]
	if finish then finish(false) end
end)
for _, s in ipairs(CollectionService:GetTagged(Tags.Survivor)) do bind(s) end
