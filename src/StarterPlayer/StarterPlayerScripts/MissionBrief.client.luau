--!strict
-- MissionBrief client (B13 / MAP-09 / MAP-10): text brief in place of the opening movie.
-- First run: lines appear one at a time and the brief closes by itself, no skip.
-- Later runs: same narration, plus "SPACE to skip". Reports back to the server when done.
local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage.Config.BriefConfig)
local BriefShow: RemoteEvent = ReplicatedStorage.Remotes.BriefShow
local BriefDone: RemoteEvent = ReplicatedStorage.Remotes.BriefDone
local NL = string.char(10)

local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "MissionBrief"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 10
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local dim = Instance.new("Frame")
dim.Name = "Dim"
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.3
dim.BorderSizePixel = 0
dim.Parent = gui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0.12, 0)
title.Size = UDim2.new(0.8, 0, 0.08, 0)
title.TextScaled = true
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextColor3 = Color3.fromRGB(230, 180, 40)
title.Text = Cfg.Title
title.Parent = gui

local body = Instance.new("TextLabel")
body.Name = "Body"
body.AnchorPoint = Vector2.new(0.5, 0)
body.Position = UDim2.new(0.5, 0, 0.23, 0)
body.Size = UDim2.new(0.8, 0, 0.5, 0)
body.BackgroundTransparency = 1
body.Font = Enum.Font.Gotham
body.TextSize = 26
body.TextColor3 = Color3.new(1, 1, 1)
body.TextWrapped = true
body.TextYAlignment = Enum.TextYAlignment.Top
body.Text = ""
body.Parent = gui

local skipHint = Instance.new("TextButton")
skipHint.Name = "Skip"
skipHint.AutoButtonColor = false
skipHint.AnchorPoint = Vector2.new(0.5, 1)
skipHint.Position = UDim2.new(0.5, 0, 0.82, 0)
skipHint.Size = UDim2.new(0.5, 0, 0.05, 0)
skipHint.TextScaled = true
skipHint.BackgroundTransparency = 1
skipHint.Font = Enum.Font.GothamBold
skipHint.TextColor3 = Color3.fromRGB(180, 180, 190)
skipHint.Text = ""
skipHint.Parent = gui

local bindSkip: (boolean) -> () -- defined below, used by finish / show
local session = 0 -- bumps per showing so an old narration loop stops touching a new one
local skipAllowed = false
local showing = false

-- The HUD and inventory bar step aside while the brief is up so text never overlaps.
local function setOtherGuis(enabled: boolean)
	for _, name in ipairs({ "HUD", "InventoryBar" }) do
		local g = player.PlayerGui:FindFirstChild(name)
		if g and g:IsA("ScreenGui") then g.Enabled = enabled end
	end
end

local function finish(skipped: boolean)
	if not showing then return end
	showing = false
	session += 1
	gui.Enabled = false
	setOtherGuis(true)
	bindSkip(false)
	BriefDone:FireServer(skipped)
	print(("[Brief] %s"):format(if skipped then "skipped" else "finished"))
end

local function show(runs: number)
	session += 1
	local mine = session
	showing = true
	skipAllowed = runs > 0
	skipHint.Text = if skipAllowed then "SPACE to skip" else ""
	body.Text = ""
	gui.Enabled = true
	setOtherGuis(false)
	if skipAllowed then bindSkip(true) end
	print(("[Brief] showing, briefed %d time(s) before, skip %s"):format(runs, if skipAllowed then "offered" else "not offered (first run)"))
	task.spawn(function()
		local shown = {}
		for _, line in ipairs(Cfg.Lines) do
			if session ~= mine then return end
			table.insert(shown, line)
			body.Text = table.concat(shown, NL .. NL)
			task.wait(Cfg.SecondsPerLine)
		end
		if session ~= mine then return end
		task.wait(Cfg.HoldSeconds)
		if session == mine then finish(false) end
	end)
end

BriefShow.OnClientEvent:Connect(function(runs: number) show(tonumber(runs) or 0) end)

-- On join: wait for the server to publish BriefRuns (it may be loading from the DataStore), then show.
task.spawn(function()
	local runs = player:GetAttribute("BriefRuns")
	if runs == nil then
		player:GetAttributeChangedSignal("BriefRuns"):Wait()
		runs = player:GetAttribute("BriefRuns")
	end
	show(tonumber(runs) or 0)
end)

-- Space is also the jump key and reaches InputBegan as already processed, so the skip is bound
-- through ContextActionService at high priority while the brief is showing (it also sinks the
-- jump for that moment). The hint is a button too, for mouse and touch.
local SKIP_ACTION = "DismantleSkipBrief"
local function onSkipAction(_name: string, state: Enum.UserInputState)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	if showing and skipAllowed then finish(true) end
	return Enum.ContextActionResult.Sink
end
function bindSkip(on: boolean)
	if on then
		ContextActionService:BindActionAtPriority(SKIP_ACTION, onSkipAction, false, Enum.ContextActionPriority.High.Value, Cfg.SkipKey)
	else
		ContextActionService:UnbindAction(SKIP_ACTION)
	end
end
skipHint.Activated:Connect(function() if showing and skipAllowed then finish(true) end end)
