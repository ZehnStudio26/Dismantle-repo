--!strict
-- HUD (B9 / HUD-01..04): binds the Studio-authored StarterGui.HUD to the client stores with Fusion
-- 0.3 (Hydrate over existing instances; nothing is built here). Layout follows the reference
-- screenshot: cash top-left with a "+$N" income ticker, a vertical demolition meter on the left, a
-- heart with a segmented health bar top-right, event warnings at the edges, the run banner and the
-- event flash in the centre. Event-driven: every label is a Computed over a store Value, so nothing
-- polls per frame (the previous version ran a RenderStepped loop). Inventory draws its own bar.
local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Fusion)
local Stores = require(ReplicatedStorage.UI.Stores)
local T = require(ReplicatedStorage.Config.UITheme)

local scoped, peek = Fusion.scoped, Fusion.peek
local player = Players.LocalPlayer
local NL = string.char(10)

pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false) end)

local gui = player:WaitForChild("PlayerGui"):WaitForChild("HUD") :: ScreenGui
local cash = gui:WaitForChild("Cash") :: TextLabel
local income = gui:WaitForChild("Income") :: TextLabel
local meter = gui:WaitForChild("Meter") :: Frame
local meterValue = meter:WaitForChild("Value") :: TextLabel
local meterFill = (meter:WaitForChild("Track") :: Frame):WaitForChild("Fill") :: Frame
local health = gui:WaitForChild("Health") :: Frame
local hpBar = health:WaitForChild("Bar") :: Frame
local hpValue = health:WaitForChild("Value") :: TextLabel
local leftWarn = gui:WaitForChild("GasWarning") :: TextLabel
local rightWarn = gui:WaitForChild("LarvaWarning") :: TextLabel
local banner = gui:WaitForChild("Banner") :: TextLabel
local flash = gui:WaitForChild("EventFlash") :: TextLabel

local scope = scoped(Fusion)
local P = Stores.Player(scope, player)
local Rn = Stores.Run(scope)

local function withCommas(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (formatted:gsub("^,", ""))
end

-- cash, and the income ticker: gains within 1.5 s add up into one "+$N" that then clears
local pending = scope:Value(0)
local lastCash = peek(P.Cash)
local ticket = 0
scope:Observer(P.Cash):onChange(function()
	local now = peek(P.Cash)
	local delta = now - lastCash
	lastCash = now
	if delta <= 0 then return end
	pending:set(peek(pending) + delta)
	ticket += 1
	local mine = ticket
	task.delay(1.5, function() if mine == ticket then pending:set(0) end end)
end)
scope:Hydrate(cash) { Text = scope:Computed(function(use) return "$" .. withCommas(use(P.Cash)) end) }
scope:Hydrate(income) { Text = scope:Computed(function(use) local p = use(pending); return if p > 0 then ("+$%d"):format(p) else "" end) }

-- demolition meter: the fill is the true percent (on a 35k-block kaiju one block is 0.003 %, so it
-- moves slowly by design); the value shows two decimals, a blocks-cut counter ticks on every block,
-- and the value flashes white on each change so cutting is always visibly counted
local meterBlocks = meter:FindFirstChild("Blocks") :: TextLabel?
local meterPulse = scope:Value(false)
local meterTicket = 0
scope:Observer(Rn.Percent):onChange(function()
	meterPulse:set(true)
	meterTicket += 1
	local mine = meterTicket
	task.delay(0.08, function() if mine == meterTicket then meterPulse:set(false) end end)
end)
scope:Hydrate(meterValue) {
	Text = scope:Computed(function(use) return ("%.2f%%"):format(use(Rn.Percent)) end),
	TextColor3 = scope:Tween(scope:Computed(function(use) return if use(meterPulse) then T.Palette.Text else Color3.fromRGB(255, 120, 140) end), TweenInfo.new(0.25)),
}
if meterBlocks then
	scope:Hydrate(meterBlocks) { Text = scope:Computed(function(use) return ("%d CUT"):format(math.max(0, use(Rn.Total) - use(Rn.Remaining))) end) }
end
scope:Hydrate(meterFill) {
	Size = scope:Tween(scope:Computed(function(use) return UDim2.fromScale(1, math.clamp(use(Rn.Percent) / 100, 0, 1)) end), T.Tween.Open),
}

-- health: Ayesh's five-slot bar art (2026-09-25, uploads quality-5 = all lit, quality-1 = one lit).
-- Each Seg is a clipping frame holding the WHOLE bar image at five times its width, shifted in
-- Scale to the slot it shows: slot i of quality-5 when lit, slot 2 of quality-1 (an empty slot)
-- when not. No pixel sizes needed, so any resolution of the art works. Five segments on 100 HP
-- means one segment per two hits; the number beside the bar carries the exact value.
local FILLED = "rbxassetid://82367077662731"
local EMPTY = "rbxassetid://86471146186680"
local segments: { GuiObject } = {}
for _, s in ipairs(hpBar:GetChildren()) do
	if s:IsA("GuiObject") and s.Name:match("^Seg%d+$") then table.insert(segments, s) end
end
table.sort(segments, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
local fraction = scope:Computed(function(use) return math.clamp(use(P.Health) / math.max(1, use(P.MaxHealth)), 0, 1) end)
local lit = scope:Computed(function(use) return math.ceil(use(fraction) * #segments - 0.0001) end)
local segColor = scope:Computed(function(use)
	local f = use(fraction)
	return if f > 0.5 then T.Health.On elseif f > 0.25 then T.Health.Low else T.Health.Crit
end)
-- the bar's border flashes red on damage and green on a heal (the survivor's +30 included)
local pulse = scope:Value("none")
local lastHealth = peek(P.Health)
local pulseTicket = 0
scope:Observer(P.Health):onChange(function()
	local now = peek(P.Health)
	local kind = if now < lastHealth then "hurt" elseif now > lastHealth then "heal" else "none"
	lastHealth = now
	if kind == "none" then return end
	pulse:set(kind)
	pulseTicket += 1
	local mine = pulseTicket
	task.delay(0.35, function() if mine == pulseTicket then pulse:set("none") end end)
end)
local barStroke = hpBar:FindFirstChildOfClass("UIStroke")
if barStroke then
	scope:Hydrate(barStroke) {
		Color = scope:Tween(scope:Computed(function(use)
			local k = use(pulse)
			return if k == "hurt" then T.Health.Crit elseif k == "heal" then T.Health.On else Color3.fromRGB(30, 36, 51)
		end), TweenInfo.new(0.2)),
	}
end
for i, seg in ipairs(segments) do
	local img = seg:FindFirstChild("Img")
	local fillFrame = seg:FindFirstChild("Fill")
	if fillFrame and fillFrame:IsA("Frame") then
		-- partial fill: segment i holds the slice of health between (i-1)/n and i/n, so every hit and
		-- every heal moves the bar even when a whole segment does not change
		scope:Hydrate(fillFrame) {
			Size = scope:Tween(scope:Computed(function(use)
				local part = math.clamp(use(fraction) * #segments - (i - 1), 0, 1)
				return UDim2.fromScale(part, 1)
			end), TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)),
			BackgroundColor3 = segColor,
		}
	elseif img and img:IsA("ImageLabel") then
		scope:Hydrate(img) {
			Image = scope:Computed(function(use) return if i <= use(lit) then FILLED else EMPTY end),
			Position = scope:Computed(function(use) return if i <= use(lit) then UDim2.fromScale(-(i - 1), 0) else UDim2.fromScale(-1, 0) end),
		}
	else
		-- older authored bar: plain frames coloured by health
		scope:Hydrate(seg) { BackgroundColor3 = scope:Computed(function(use) return if i <= use(lit) then use(segColor) else T.Health.Off end) }
	end
end
scope:Hydrate(hpValue) { Text = scope:Computed(function(use) return tostring(math.ceil(use(P.Health))) end) }

-- edges: active event warnings
scope:Hydrate(leftWarn) {
	Text = scope:Computed(function(use)
		local clouds = use(Rn.Clouds)
		if clouds <= 0 then return "" end
		local tail = if use(P.InGas) then (NL .. (if use(P.Masked) then "masked" else "PUT ON MASK")) else ""
		return ("GAS x%d%s"):format(clouds, tail)
	end),
}
scope:Hydrate(rightWarn) { Text = scope:Computed(function(use) local n = use(Rn.Larvae); return if n > 0 then ("LARVA x%d"):format(n) else "" end) }

-- centre: run state banner, and a 3 s flash when an event fires
scope:Hydrate(banner) {
	Text = scope:Computed(function(use)
		local state = use(Rn.State)
		return if state == "Cleared" then "KAIJU DISMANTLED" elseif state == "Failed" then "RUN FAILED" else ""
	end),
}
local flashVisible = scope:Value(false)
local flashTicket = 0
scope:Observer(Rn.EventCount):onChange(function()
	flash.Text = ("EVENT: %s"):format(string.upper(peek(Rn.LastEvent)))
	flashVisible:set(true)
	flashTicket += 1
	local mine = flashTicket
	task.delay(3, function() if mine == flashTicket then flashVisible:set(false) end end)
end)
scope:Hydrate(flash) { Visible = flashVisible }