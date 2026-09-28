--!strict
-- SurvivorSpeech: the survivor's "THANK YOU!" bubble, in the game's UI style. The bubble is authored in
-- Studio on the survivor's head (Templates.Survivor.Head.Speech: a dark panel with the Arcade face, a
-- tail, a gold cash line and a green HP line, UITheme tokens). Server.Survivor only turns it on at a
-- rescue; this script Hydrates it with Fusion 0.3 (nothing is built here): it pops in on a spring
-- (UIScale 0.6 -> 1 with a little overshoot), fades in, and floats up a touch. The reward line reads
-- EventConfig.Survivor so the numbers match what the rescue pays.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Fusion)
local T = require(ReplicatedStorage.Config.UITheme)
local Tags = require(ReplicatedStorage.Config.Tags)
local Survivor = require(ReplicatedStorage.Config.EventConfig).Survivor

local REWARD = ('<font color="#%s">+$%d</font>   <font color="#%s">+%d HP</font>'):format(
	T.Palette.Gold:ToHex(), Survivor.Coins, T.Palette.Green:ToHex(), Survivor.Heal)

local bound: { [Instance]: boolean } = {}

local function bind(model: Instance)
	if bound[model] then return end
	bound[model] = true
	task.spawn(function()
		-- under StreamingEnabled the head can arrive after the model
		local head = model:WaitForChild("Head", 10)
		local speech = head and head:WaitForChild("Speech", 10)
		if not speech or not speech:IsA("BillboardGui") then return end
		local group = speech:FindFirstChild("Group") :: CanvasGroup?
		local scale = group and group:FindFirstChildOfClass("UIScale")
		local bubble = group and group:FindFirstChild("Bubble")
		local reward = bubble and bubble:FindFirstChild("Reward") :: TextLabel?
		if not group or not scale then return end

		local scope = Fusion.scoped(Fusion)
		local shown = scope:Value(speech.Enabled)
		local function target(on: any, off: any) return scope:Computed(function(use) return if use(shown) then on else off end) end
		scope:Hydrate(group) { GroupTransparency = scope:Tween(target(0, 1), TweenInfo.new(0.18, Enum.EasingStyle.Quad)) }
		scope:Hydrate(scale) { Scale = scope:Spring(target(1, 0.6), 28, 0.55) } -- under-damped: a small pop past full size
		scope:Hydrate(speech) { StudsOffset = scope:Spring(target(Vector3.new(0, 3.2, 0), Vector3.new(0, 2.4, 0)), 12, 0.8) }
		if reward then scope:Hydrate(reward) { Text = REWARD } end

		table.insert(scope, speech:GetPropertyChangedSignal("Enabled"):Connect(function() shown:set(speech.Enabled) end))
		model.Destroying:Once(function()
			bound[model] = nil
			Fusion.doCleanup(scope)
		end)
	end)
end

CollectionService:GetInstanceAddedSignal(Tags.Survivor):Connect(bind)
for _, s in ipairs(CollectionService:GetTagged(Tags.Survivor)) do bind(s) end
