--!strict
-- EventRoll (A12 / EVT-15..17, GDD 6.6): when a seeded "Event" block breaks, decide what comes out.
-- Egg and Gas subscribe to Triggered instead of reading block materials themselves.
--   EVT-15  no immediate repeat of the kind that just fired
--   EVT-16  single events early: below SingleEventBelowPercent a new event is suppressed while one is active
--   EVT-17  party scaling: larvae per egg scales with party size, event count does not
-- Active events are counted from Workspace.Hazards (gas clouds) and Workspace.Enemies (larvae),
-- so this module needs no dependency on Egg or Gas.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventConfig = require(ReplicatedStorage.Config.EventConfig)
local Demolition = require(script.Parent.Demolition)

local Cfg = EventConfig.Roll
local RunState = ReplicatedStorage:WaitForChild("RunState")
local hazards = workspace:WaitForChild("Hazards")
local enemies = workspace:WaitForChild("Enemies")

local EventRoll = {}
EventRoll.Triggered = Instance.new("BindableEvent") -- (kind, cframe, size, source, partySize)

local rng = Random.new()
local last: string? = nil
local count = 0
local suppressed = 0

local function activeEvents(): number
	local n = #hazards:GetChildren()
	for _, e in ipairs(enemies:GetChildren()) do
		local hum = e:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then n += 1 end
	end
	return n
end

function EventRoll.Pick(): string
	local total = 0
	local kinds: { string } = {}
	for kind, w in pairs(Cfg.Weights) do
		if not (Cfg.NoImmediateRepeat and kind == last) then
			table.insert(kinds, kind)
			total += w
		end
	end
	if #kinds == 0 then -- only one kind configured: repeats are unavoidable
		for kind in pairs(Cfg.Weights) do return kind end
	end
	local r = rng:NextNumber() * total
	for _, kind in ipairs(kinds) do
		r -= Cfg.Weights[kind]
		if r <= 0 then return kind end
	end
	return kinds[#kinds]
end

function EventRoll.PartySize(): number
	return math.max(1, #Players:GetPlayers())
end

Demolition.BlockBroken.Event:Connect(function(cf: CFrame, size: Vector3, material: string?, source: string)
	if material ~= "Event" then return end
	if RunState:GetAttribute("State") ~= "Running" then return end -- deferred signals can arrive after Cleared / Failed
	local pct = tonumber(RunState:GetAttribute("DemolitionPercent")) or 0
	local active = activeEvents()
	if pct < Cfg.SingleEventBelowPercent and active > 0 then
		suppressed += 1
		print(("[Roll] suppressed: single-event phase (%.1f%% < %d%%) with %d active. %d suppressed so far"):format(pct, Cfg.SingleEventBelowPercent, active, suppressed))
		return
	end
	local kind = EventRoll.Pick()
	last = kind
	count += 1
	RunState:SetAttribute("LastEvent", kind)
	RunState:SetAttribute("EventCount", count)
	local party = EventRoll.PartySize()
	print(("[Roll] #%d %s at %.1f%% (party %d, %d already active, broken by %s)"):format(count, kind, pct, party, active, source))
	EventRoll.Triggered:Fire(kind, cf, size, source, party)
end)

return EventRoll
