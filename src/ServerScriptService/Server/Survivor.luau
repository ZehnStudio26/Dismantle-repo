--!strict
-- Survivor (E-3 / GDD 6.3, the "jackpot" event): a blue block can release a trapped survivor.
-- Metal Slug rule: he waits where he appeared until a player walks up to him, then thanks them, pays
-- coins and health to THAT player (C-3: rewards go to whoever picks them up) and leaves. Unrescued,
-- he leaves after ExpireSeconds. Same two halves as Egg, meeting only through the "Survivor" tag:
--   PLACEMENT  EventRoll "Survivor" clones ServerStorage.Templates.Survivor where the block was and tags it
--   BEHAVIOUR  TagBinder gives every tagged survivor inside Workspace a Waiting object below
-- Survivors live in Workspace.Pickups, not Hazards, so a waiting survivor is never counted as an
-- active crisis by EventRoll (EVT-16). Counts for the clear screen (H-2): RunState.SurvivorsRescued
-- and the player attribute Survivors. The "Thank you!" bubble is a BillboardGui authored on the template.
-- Client state (2026-10-01): attributes ExpiresAt (server-time deadline) and Rescued (set at the rescue,
-- before the thanks period) drive StarterPlayerScripts.SurvivorFX: light pillar, "!" marker with a
-- time-left bar, "SOS" edge arrow, "HELP!" bubble + call, confetti. The rescue also fires Server.FX
-- (coins to the rescuer, "<rescuer> RESCUED!" popup for everyone).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local EventConfig = require(ReplicatedStorage.Config.EventConfig)
local Tags = require(ReplicatedStorage.Config.Tags)
local Demolition = require(script.Parent.Demolition)
local EventRoll = require(script.Parent.EventRoll)
local FX = require(script.Parent.FX)
local TagBinder = require(script.Parent.TagBinder)

local Cfg = EventConfig.Survivor
local RunState = ReplicatedStorage:WaitForChild("RunState")
local folder = workspace:WaitForChild("Pickups")
local template = ServerStorage:WaitForChild("Templates"):WaitForChild("Survivor") :: Model
local rng = Random.new()

-- An animation of the survivor's own set (the Animation objects under its AnimateScript; that
-- LocalScript never runs on an NPC in Workspace, so the server plays them), loaded on its Animator.
local FALLBACK = { idle = "rbxassetid://16562317918", wave = "http://www.roblox.com/asset/?id=507770239" }
local function loadAnim(model: Model, name: string): AnimationTrack?
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = hum
	local set = model:FindFirstChild("AnimateScript")
	local slot = set and set:FindFirstChild(name)
	local anim: Animation? = slot and slot:FindFirstChildOfClass("Animation")
	if not anim and FALLBACK[name] then
		local a = Instance.new("Animation")
		a.AnimationId = FALLBACK[name]
		anim = a
	end
	if not anim then return nil end
	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	return if ok then track else nil
end

local function bump(inst: Instance, attr: string, by: number): number
	local v = (tonumber(inst:GetAttribute(attr)) or 0) + by
	inst:SetAttribute(attr, v)
	return v
end

-- ---- behaviour: one survivor waiting for a rescue ----

type Fields = { model: Model, thread: thread?, done: boolean, idle: AnimationTrack? }
local Waiting = {}
Waiting.__index = Waiting
local waiting: { [Model]: Fields } = {}

function Waiting.new(model: Model)
	local self = setmetatable({ model = model, thread = nil, done = false } :: Fields, Waiting)
	waiting[model] = self
	-- standing idle while he waits (the model's own idle clip, looped)
	self.idle = loadAnim(model, "idle")
	if self.idle then self.idle.Looped = true; self.idle:Play() end
	local expire = tonumber(model:GetAttribute("ExpireSeconds")) or Cfg.ExpireSeconds
	-- the deadline, for SurvivorFX's time-left bar (it counts down from GetServerTimeNow; no per-frame server work)
	model:SetAttribute("ExpiresAt", workspace:GetServerTimeNow() + expire)
	self.thread = task.delay(expire, function()
		if self.done then return end
		self.done = true
		model:Destroy()
	end)
	return self
end

function Waiting.rescue(self: Fields, player: Player)
	if self.done then return end
	self.done = true
	if self.thread then task.cancel(self.thread); self.thread = nil end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum.Health = math.min(hum.MaxHealth, hum.Health + Cfg.Heal) end
	local cash = bump(player, "Cash", Cfg.Coins)
	bump(player, "Survivors", 1)
	local total = bump(RunState, "SurvivorsRescued", 1)
	-- payoff: SurvivorFX drops his pillar / marker / arrow and bursts confetti on Rescued; coins fly to
	-- the rescuer's Cash label and everyone sees who saved him (visual only, Cash is paid above)
	self.model:SetAttribute("Rescued", true)
	local at = self.model:GetPivot().Position
	FX.coins(player, Cfg.Coins, at)
	FX.popup("all", player.DisplayName .. " RESCUED!", at + Vector3.new(0, 4, 0), EventConfig.Colors.Survivor)
	local speech = self.model:FindFirstChild("Speech", true)
	if speech and speech:IsA("BillboardGui") then speech.Enabled = true end
	-- he waves his thanks
	if self.idle then self.idle:Stop(0.2) end
	local wave = loadAnim(self.model, "wave")
	if wave then wave:Play(0.2) end
	local model = self.model
	task.delay(Cfg.ThanksSeconds, function() model:Destroy() end)
end

function Waiting.Destroy(self: Fields)
	waiting[self.model] = nil
	self.done = true
	if self.thread then task.cancel(self.thread); self.thread = nil end
end

TagBinder.bind(Tags.Survivor, function(inst) return Waiting.new(inst :: Model) end)

-- one loop for every waiting survivor: the first living player within RescueRange rescues him
task.spawn(function()
	while true do
		task.wait(0.25)
		for model, w in pairs(waiting) do
			if w.done or not model.Parent then continue end
			local pos = model:GetPivot().Position
			for _, p in ipairs(Players:GetPlayers()) do
				local char = p.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if root and root:IsA("BasePart") and hum and hum.Health > 0 and (root.Position - pos).Magnitude <= Cfg.RescueRange then
					Waiting.rescue(w, p)
					break
				end
			end
		end
	end
end)

-- ---- placement: a rolled Survivor stands where the block was ----

local function place(cf: CFrame, size: Vector3, source: string)
	local s = template:Clone()
	-- feet on the block's floor: the rig's pivot is its root, not its middle, so place it by the bottom
	-- of its bounding box; turned to a random heading
	s:PivotTo(CFrame.new(cf.Position) * CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), 0))
	local bcf, bsize = s:GetBoundingBox()
	local floorY = cf.Position.Y - size.Y / 2
	s:PivotTo(s:GetPivot() + Vector3.new(0, floorY - (bcf.Position.Y - bsize.Y / 2), 0))
	s.Parent = folder
	local root = s.PrimaryPart
	if root and not root.Anchored then pcall(function() root:SetNetworkOwner(nil) end) end
	s:AddTag(Tags.Survivor) -- tag last: TagBinder only binds what is already in Workspace
end

-- Rolled outcome from a seeded "Event" block (EVT-02) ...
EventRoll.Triggered.Event:Connect(function(kind: string, cf: CFrame, size: Vector3, source: string)
	if kind == "Survivor" then place(cf, size, source) end
end)
-- ... or a hand-placed block of material "Survivor" with a fixed outcome (showcase; never seeded).
Demolition.BlockBroken.Event:Connect(function(cf: CFrame, size: Vector3, material: string?, source: string)
	if material == "Survivor" then place(cf, size, source) end
end)

Demolition.Cleared.Event:Connect(function()
	for _, s in ipairs(CollectionService:GetTagged(Tags.Survivor)) do
		if s.Parent == folder then s:Destroy() end
	end
end)

return { Place = place }
