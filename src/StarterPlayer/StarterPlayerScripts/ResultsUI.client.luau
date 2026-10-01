--!strict
-- ResultsUI (H-2 / KJ-67, Shayan 2026-09-29): the end screen, styled on the reference's MOUNTAIN FLATTENED! card
-- (green header band, inset stats box with divided rows, the time in lime, a full-width BACK TO LOBBY button).
-- The layout is StarterGui.Results, authored in Studio; Fusion 0.3 drives it with Hydrate only:
--   * one Value holds the server's RunResults payload (Server.RunEnd); every label is a Computed of it
--   * the numbers count up with scope:Tween (like the reference's cash count-up), the card pops in and the
--     button presses with scope:Spring
--   * a cleared run shows KAIJU DISMANTLED! on lime; a failed one SITE LOST on red, TIME SURVIVED, and how
--     much was dismantled in place of the clear bonus
--   * the countdown to the automatic return sits in the button: BACK TO LOBBY (20)
-- The HUD, hotbar and rail step aside (and stay hidden if a respawn re-adds them).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Fusion)
local RunResults: RemoteEvent = ReplicatedStorage.Remotes.RunResults

local scoped, peek, OnEvent = Fusion.scoped, Fusion.peek, Fusion.OnEvent
local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local gui = pg:WaitForChild("Results") :: ScreenGui
local card = gui:WaitForChild("Card") :: Frame
local header = card:WaitForChild("Header") :: Frame
local stats = card:WaitForChild("Stats") :: Frame
local lobby = card:WaitForChild("Lobby") :: TextButton

local HIDE = { "HUD", "Hotbar", "Upgrades", "Crosshair", "SpectateGui", "MaskOverlay", "Cutscene" }
local COUNT = TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local WIN = ColorSequence.new(Color3.fromRGB(255, 170, 80), Color3.fromRGB(230, 100, 20)) -- safety orange (Hazard Crew)
local RED = ColorSequence.new(Color3.fromRGB(250, 120, 95), Color3.fromRGB(196, 48, 38))
local NL = string.char(10)

type Crew = { name: string, blocks: number, earned: number, here: boolean }
type Payload = { cleared: boolean, seconds: number, percent: number, survivors: number, blocks: number, earned: number, bonus: number, returnIn: number, crew: { Crew } }

local function money(n: number): string
	local s = tostring(math.floor(n + 0.5))
	while true do
		local k
		s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
		if k == 0 then break end
	end
	return "$" .. s
end
local function clock(seconds: number): string
	local s = math.floor(seconds + 0.5)
	return ("%d:%02d"):format(s // 60, s % 60)
end
local function whole(n: number): string return money(n):sub(2) end

local scope = scoped(Fusion)
local result = scope:Value(nil :: Payload?)
local secondsLeft = scope:Value(0)
local returning = scope:Value(false)
local popGoal = scope:Value(0.85)
local pressGoal = scope:Value(1)

local cleared = scope:Computed(function(use) local r = use(result); return r ~= nil and r.cleared end)
-- counted-up numbers: each tweens from what it showed (0 at first) to the payload's value
local function counted(field: string)
	local goal = scope:Computed(function(use)
		local r = use(result) :: any
		return if r then tonumber(r[field]) or 0 else 0
	end)
	return scope:Tween(goal, COUNT)
end
local seconds, blocks, survivors, earned, bonus, percent =
	counted("seconds"), counted("blocks"), counted("survivors"), counted("earned"), counted("bonus"), counted("percent")

local function row(name: string): (TextLabel, TextLabel)
	local r = stats:WaitForChild(name)
	return r:WaitForChild("Label") :: TextLabel, r:WaitForChild("Value") :: TextLabel
end

scope:Hydrate(gui) { Enabled = scope:Computed(function(use) return use(result) ~= nil end) }
scope:Hydrate(card:WaitForChild("Pop") :: UIScale) { Scale = scope:Spring(popGoal, 28, 0.55) }
scope:Hydrate(header:WaitForChild("Fill") :: UIGradient) { Color = scope:Computed(function(use) return if use(cleared) then WIN else RED end) }
scope:Hydrate(header:WaitForChild("Title") :: TextLabel) {
	Text = scope:Computed(function(use) return if use(cleared) then "KAIJU" .. NL .. "DISMANTLED!" else "SITE" .. NL .. "LOST" end),
}

local timeLabel, timeValue = row("Row_Time")
scope:Hydrate(timeLabel) { Text = scope:Computed(function(use) return if use(cleared) then "TIME COMPLETED" else "TIME SURVIVED" end) }
scope:Hydrate(timeValue) { Text = scope:Computed(function(use) return clock(use(seconds)) end) }
local _, blocksValue = row("Row_Blocks")
scope:Hydrate(blocksValue) { Text = scope:Computed(function(use) return whole(use(blocks)) end) }
local _, survivorsValue = row("Row_Survivors")
scope:Hydrate(survivorsValue) { Text = scope:Computed(function(use) return whole(use(survivors)) end) }
local _, cashValue = row("Row_Cash")
scope:Hydrate(cashValue) { Text = scope:Computed(function(use) return money(use(earned)) end) }
local bonusLabel, bonusValue = row("Row_Bonus")
scope:Hydrate(bonusLabel) { Text = scope:Computed(function(use) return if use(cleared) then "CLEAR BONUS" else "DISMANTLED" end) }
scope:Hydrate(bonusValue) {
	Text = scope:Computed(function(use)
		if use(cleared) then return "+" .. money(use(bonus)) end
		return ("%.1f%%"):format(use(percent))
	end),
}

scope:Hydrate(lobby:WaitForChild("Caption") :: TextLabel) {
	Text = scope:Computed(function(use)
		if use(returning) then return "RETURNING..." end
		local left = use(secondsLeft)
		return if left > 0 then ("BACK TO LOBBY (%d)"):format(left) else "BACK TO LOBBY"
	end),
}
scope:Hydrate(lobby:WaitForChild("Press") :: UIScale) { Scale = scope:Spring(pressGoal, 40, 0.5) }
scope:Hydrate(lobby) {
	[OnEvent "MouseEnter"] = function() pressGoal:set(1.03) end,
	[OnEvent "MouseLeave"] = function() pressGoal:set(1) end,
	[OnEvent "MouseButton1Down"] = function() pressGoal:set(0.95) end,
	[OnEvent "MouseButton1Up"] = function() pressGoal:set(1.03) end,
	[OnEvent "Activated"] = function()
		if peek(result) == nil or peek(returning) then return end
		returning:set(true)
		RunResults:FireServer("lobby")
	end,
}

-- the HUD screens step aside, and stay aside if a respawn (a failed run brings the downed back) re-adds them
-- or another script (the intro cutscene finishing) turns them back on
local watched: { [ScreenGui]: boolean } = {}
local function hide(g: Instance)
	if not (g:IsA("ScreenGui") and table.find(HIDE, g.Name)) then return end
	g.Enabled = false
	if not watched[g] then
		watched[g] = true
		g:GetPropertyChangedSignal("Enabled"):Connect(function()
			if g.Enabled and peek(result) ~= nil then g.Enabled = false end
		end)
	end
end
pg.ChildAdded:Connect(function(g) if peek(result) ~= nil then hide(g) end end)

RunResults.OnClientEvent:Connect(function(r: Payload)
	for _, g in ipairs(pg:GetChildren()) do hide(g) end
	-- phones / tablets: no thumbstick or jump button over the card (the run is over)
	pcall(function() game:GetService("GuiService").TouchControlsEnabled = false end)
	popGoal:set(0.85)
	result:set(r)
	task.defer(function() popGoal:set(1) end)
	-- countdown to the automatic return, shown in the button
	local deadline = os.clock() + r.returnIn
	task.spawn(function()
		while peek(result) == r do
			local left = math.max(0, math.ceil(deadline - os.clock()))
			secondsLeft:set(left)
			if left <= 0 then break end
			task.wait(0.25)
		end
	end)
end)
