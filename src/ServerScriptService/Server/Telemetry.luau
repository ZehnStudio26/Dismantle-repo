--!strict
-- Telemetry (A15 / KPI-01..11): structured "[KPI] <name> <json>" lines for K1-K9, hooked onto
-- signals the other modules already expose. Nothing here changes gameplay. Swap emit() for
-- AnalyticsService / HTTP later; the event shapes stay.
--   K1 RunEnd.state              K2 RunEnd.seconds + party        K3 RunEnd.cuttingSeconds vs eventSeconds
--   K4 ReturnToCutting.seconds   K5 RunEnd.contribution           K6 RunEnd.last1PercentSeconds
--   K7 RunEnd.wrongToolDamage    K8 Down + RunEnd.downs           K9 PlayerJoined.userId (replay computed offline)

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Demolition = require(script.Parent.Demolition)
local EventRoll = require(script.Parent.EventRoll)

local RunState = ReplicatedStorage:WaitForChild("RunState")
local hazards = workspace:WaitForChild("Hazards")
local enemies = workspace:WaitForChild("Enemies")

local Telemetry = {}

local runId = HttpService:GenerateGUID(false)
local runStart = os.clock()
local ended = false
local maxParty = math.max(1, #Players:GetPlayers())

local cuttingSeconds: { [string]: number } = {}
local eventSeconds = 0
local eventPhaseSince: number? = nil
local lastEventEnd: number? = nil
local returnTimes: { number } = {}
local events: { [string]: number } = {}
local downs = 0
local wrongToolDamage = { GasUnmasked = 0, LarvaWithoutGun = 0 }
local last1Start: number? = nil
local last1Seconds: number? = nil

local function now(): number return math.floor((os.clock() - runStart) * 100) / 100 end

function Telemetry.Emit(name: string, data: { [string]: any }?)
	local d = data or {}
	d.t = now()
	d.run = runId
	print(("[KPI] %s %s"):format(name, HttpService:JSONEncode(d)))
end

local function activeEvents(): number
	local n = #hazards:GetChildren()
	for _, e in ipairs(enemies:GetChildren()) do
		local h = e:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 then n += 1 end
	end
	return n
end

local function held(player: Player): string?
	local char = player.Character
	local t = char and char:FindFirstChildOfClass("Tool")
	return t and t.Name
end

function Telemetry.Snapshot(): { [string]: any }
	local totalCut = 0
	for _, s in pairs(cuttingSeconds) do totalCut += s end
	local avgReturn = 0
	for _, r in ipairs(returnTimes) do avgReturn += r end
	avgReturn = if #returnTimes > 0 then avgReturn / #returnTimes else 0
	return {
		state = RunState:GetAttribute("State"),
		seconds = now(),
		party = maxParty,
		percent = RunState:GetAttribute("DemolitionPercent"),
		cuttingSeconds = math.floor(totalCut * 10) / 10,
		eventSeconds = math.floor(eventSeconds * 10) / 10,
		returnToCuttingAvg = math.floor(avgReturn * 100) / 100,
		returnSamples = #returnTimes,
		events = events,
		contribution = Demolition.GetContribution(),
		last1PercentSeconds = last1Seconds,
		wrongToolDamage = wrongToolDamage,
		downs = downs,
	}
end

local function endRun(state: string)
	if ended then return end
	ended = true
	Telemetry.Emit("RunEnd", Telemetry.Snapshot())
end

-- K1 / K2 / K5 / K6: run lifecycle
RunState:GetAttributeChangedSignal("State"):Connect(function()
	local s = RunState:GetAttribute("State")
	if s == "Cleared" or s == "Failed" then endRun(s) end
end)
RunState:GetAttributeChangedSignal("DemolitionPercent"):Connect(function()
	local pct = tonumber(RunState:GetAttribute("DemolitionPercent")) or 0
	if pct >= 99 and not last1Start then
		last1Start = os.clock()
		Telemetry.Emit("Last1PercentStart", { remaining = RunState:GetAttribute("RemainingBlocks") })
	end
	if pct >= 100 and last1Start and not last1Seconds then
		last1Seconds = math.floor((os.clock() - last1Start) * 10) / 10
	end
end)

-- events
EventRoll.Triggered.Event:Connect(function(kind: string, _cf, _size, source: string, party: number)
	events[kind] = (events[kind] or 0) + 1
	Telemetry.Emit("Event", { kind = kind, party = party, percent = RunState:GetAttribute("DemolitionPercent"), source = source })
end)

-- K7 / K8: per player damage classification and downs
local function watch(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid") :: Humanoid
	local lastHealth = hum.Health
	hum.HealthChanged:Connect(function(h)
		local delta = lastHealth - h
		lastHealth = h
		if delta <= 0 then return end
		local tool = held(player)
		if player:GetAttribute("InGas") == true and player:GetAttribute("Masked") ~= true then
			wrongToolDamage.GasUnmasked += delta
		elseif tool ~= "Handgun" and activeEvents() > 0 then
			wrongToolDamage.LarvaWithoutGun += delta
		end
	end)
	hum.Died:Connect(function()
		downs += 1
		Telemetry.Emit("Down", { player = player.Name, party = #Players:GetPlayers(), percent = RunState:GetAttribute("DemolitionPercent"), inGas = player:GetAttribute("InGas") == true, held = held(player) })
	end)
end
local function onPlayer(player: Player)
	maxParty = math.max(maxParty, #Players:GetPlayers())
	Telemetry.Emit("PlayerJoined", { player = player.Name, userId = player.UserId, party = #Players:GetPlayers() }) -- K9 replay rate is computed offline from these
	player.CharacterAdded:Connect(function(c) watch(player, c) end)
	if player.Character then watch(player, player.Character) end
end
Players.PlayerAdded:Connect(onPlayer)
for _, p in ipairs(Players:GetPlayers()) do onPlayer(p) end

-- K3 / K4: 4 Hz clock for cutting time, event phases and return-to-cutting
local TICK = 0.25
task.spawn(function()
	while not ended do
		task.wait(TICK)
		local active = activeEvents()
		local t = os.clock()
		if active > 0 then
			eventSeconds += TICK
			if not eventPhaseSince then
				eventPhaseSince = t
				Telemetry.Emit("EventPhaseStart", { active = active })
			end
		elseif eventPhaseSince then
			Telemetry.Emit("EventPhaseEnd", { seconds = math.floor((t - eventPhaseSince) * 10) / 10 })
			eventPhaseSince = nil
			lastEventEnd = t
		end
		for _, p in ipairs(Players:GetPlayers()) do
			if p:GetAttribute("Cutting") == true then
				cuttingSeconds[p.Name] = (cuttingSeconds[p.Name] or 0) + TICK
				if lastEventEnd then
					local r = math.floor((t - lastEventEnd) * 100) / 100
					table.insert(returnTimes, r)
					Telemetry.Emit("ReturnToCutting", { player = p.Name, seconds = r })
					lastEventEnd = nil
				end
			end
		end
	end
end)

local names = {}
for _, p in ipairs(Players:GetPlayers()) do table.insert(names, p.Name) end
Telemetry.Emit("RunStart", { players = names, blocks = RunState:GetAttribute("TotalBlocks"), kaiju = "Octopus" })

return Telemetry
