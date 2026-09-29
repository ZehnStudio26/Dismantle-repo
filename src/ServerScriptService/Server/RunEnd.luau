--!strict
-- RunEnd (H-2 / KJ-67, Shayan 2026-09-29): the clear screen and the trip back to the lobby. The sheet: "Fires at
-- 100 %. Results (blocks cut, survivors, coins). Everyone returns to lobby". Modelled on the reference's
-- MOUNTAIN FLATTENED! screen (completion time, blocks mined, currency earned; flatten-themountain.wiki).
--   * the run ends when RunState.State becomes Cleared (Demolition, the last block) or Failed (Health,
--     everyone down). Either way: nobody can be hurt any more (hidden ForceField), larvae, gas and eggs
--     are removed, and every player gets a results payload (RunResults remote)
--   * Cleared pays RunConfig.ClearReward to everyone still in the server (R-3 "clear reward")
--   * after RunConfig.ResultsSeconds, or when a player presses BACK TO LOBBY, profiles are saved and players
--     teleport back to the place they came from (join data SourcePlaceId; RunConfig.LobbyPlaceId for anyone
--     who joined the gameplay place directly). TeleportAsync with retries (Roblox teleport guide: retry a
--     Flooded result after ~15 s, a Failure after ~1 s). Studio never teleports: the log says so.
-- Per-player numbers: blocks = blocks broken by the player or their drones (Demolition.BlockBroken actor);
-- earned = every Cash increase after the saved profile loaded (cutting, drones, survivors), so the loaded
-- balance and the clear bonus are not counted as earnings.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local RunConfig = require(ReplicatedStorage.Config.RunConfig)
local Demolition = require(script.Parent.Demolition)
local Profile = require(script.Parent.Profile)
local RunState = ReplicatedStorage:WaitForChild("RunState")
local RunResults: RemoteEvent = ReplicatedStorage.Remotes.RunResults

local CLEAR_REWARD = RunConfig.ClearReward or 500
local RESULTS_SECONDS = RunConfig.ResultsSeconds or 20
local TRIES = 3

type Stat = { blocks: number, earned: number, lastCash: number?, name: string }
local stats: { [Player]: Stat } = {}
local runStart: number? = nil
local ended = false
local returning: { [Player]: boolean } = {}

local function stat(p: Player): Stat
	local s = stats[p]
	if not s then
		s = { blocks = 0, earned = 0, lastCash = nil, name = p.DisplayName }
		stats[p] = s
	end
	return s
end

-- earnings: Cash increases once the profile is on the player (its load is not an earning)
local function track(p: Player)
	stat(p)
	runStart = runStart or os.clock()
	p:GetAttributeChangedSignal("Cash"):Connect(function()
		local s = stats[p]
		if not s or s.lastCash == nil then return end
		local now = tonumber(p:GetAttribute("Cash")) or 0
		if now > s.lastCash and not ended then s.earned += now - s.lastCash end
		s.lastCash = now
	end)
end
Profile.Loaded.Event:Connect(function(p: Player)
	stat(p).lastCash = tonumber(p:GetAttribute("Cash")) or 0
end)
Players.PlayerAdded:Connect(track)
for _, p in ipairs(Players:GetPlayers()) do track(p) end

Demolition.BlockBroken.Event:Connect(function(_cf, _size, _material, _source, actor: Player?)
	if actor and typeof(actor) == "Instance" and actor:IsA("Player") and not ended then stat(actor).blocks += 1 end
end)

-- nothing can hurt anyone once the run is over
local function protect(char: Model?)
	if char and not char:FindFirstChild("RunOverShield") then
		local ff = Instance.new("ForceField")
		ff.Name = "RunOverShield"
		ff.Visible = false
		ff.Parent = char
	end
end

local function lobbyFor(p: Player): number
	local ok, join = pcall(function() return p:GetJoinData() end)
	local src = ok and join and tonumber(join.SourcePlaceId)
	if src and src > 0 and src ~= game.PlaceId then return src end
	return tonumber(RunConfig.LobbyPlaceId) or 0
end

-- save, then teleport a group home; players with the same lobby go together
local function returnToLobby(list: { Player }, why: string)
	local groups: { [number]: { Player } } = {}
	for _, p in ipairs(list) do
		if p.Parent and not returning[p] then
			returning[p] = true
			local id = lobbyFor(p)
			groups[id] = groups[id] or {}
			table.insert(groups[id], p)
		end
	end
	for lobbyId, group in pairs(groups) do
		local versions = Profile.SaveForTeleport(group)
		if lobbyId == 0 then
			warn(("[RunEnd] no lobby place to return %d player(s) to (%s): set RunConfig.LobbyPlaceId or join through the lobby"):format(#group, why))
			for _, p in ipairs(group) do returning[p] = nil end
			continue
		end
		local options = Instance.new("TeleportOptions")
		options:SetTeleportData({ from = "Kaiju", profileVersions = versions })
		task.spawn(function()
			for attempt = 1, TRIES do
				local ok, err = pcall(function() TeleportService:TeleportAsync(lobbyId, group, options) end)
				if ok then
					print(("[RunEnd] %d player(s) returning to lobby %d (%s)"):format(#group, lobbyId, why))
					return
				end
				warn(("[RunEnd] teleport to lobby %d failed (%d/%d): %s"):format(lobbyId, attempt, TRIES, tostring(err)))
				if RunService:IsStudio() then
					warn("[RunEnd] teleports only work in the published experience, not in a Studio playtest")
					break
				end
				task.wait(attempt * 2)
			end
			for _, p in ipairs(group) do returning[p] = nil end
		end)
	end
end

TeleportService.TeleportInitFailed:Connect(function(p: Player, result: Enum.TeleportResult, message: string)
	if not returning[p] then return end
	returning[p] = nil
	warn(("[RunEnd] %s's return failed: %s %s"):format(p.Name, result.Name, message))
	if result == Enum.TeleportResult.Flooded then
		task.delay(15, function() if p.Parent then returnToLobby({ p }, "retry after Flooded") end end)
	elseif result == Enum.TeleportResult.Failure then
		task.delay(1, function() if p.Parent then returnToLobby({ p }, "retry after Failure") end end)
	end
end)

local function finish(state: string)
	if ended then return end
	ended = true
	local cleared = state == "Cleared"
	local seconds = math.floor(os.clock() - (runStart or os.clock()))
	-- the site is safe: shields on, enemies and hazards gone
	for _, p in ipairs(Players:GetPlayers()) do protect(p.Character) end
	for _, name in ipairs({ "Enemies", "Hazards" }) do
		local f = workspace:FindFirstChild(name)
		if f then f:ClearAllChildren() end
	end
	-- the clear bonus, outside the run's earnings
	local bonus = if cleared then CLEAR_REWARD else 0
	if bonus > 0 then
		for _, p in ipairs(Players:GetPlayers()) do
			p:SetAttribute("Cash", (tonumber(p:GetAttribute("Cash")) or 0) + bonus)
		end
	end
	-- the crew, most blocks first
	local crew = {}
	for p, s in pairs(stats) do
		table.insert(crew, { name = s.name, blocks = s.blocks, earned = s.earned, here = p.Parent ~= nil })
	end
	table.sort(crew, function(a, b) return a.blocks > b.blocks end)
	local survivors = tonumber(RunState:GetAttribute("SurvivorsRescued")) or 0
	local percent = tonumber(RunState:GetAttribute("DemolitionPercent")) or 0
	local deadline = os.time() + RESULTS_SECONDS
	RunState:SetAttribute("ReturnAt", deadline)
	for _, p in ipairs(Players:GetPlayers()) do
		local s = stat(p)
		RunResults:FireClient(p, {
			cleared = cleared, seconds = seconds, percent = percent, survivors = survivors,
			blocks = s.blocks, earned = s.earned, bonus = bonus, returnIn = RESULTS_SECONDS, crew = crew,
		})
		task.spawn(Profile.Save, p)
	end
	local lines = {}
	for _, c in ipairs(crew) do table.insert(lines, ("%s %d blocks $%d"):format(c.name, c.blocks, c.earned)) end
	print(("[RunEnd] %s after %d:%02d (%.1f%%), %d survivor(s), clear bonus $%d each; crew: %s; back to the lobby in %ds"):format(
		if cleared then "KAIJU DISMANTLED" else "SITE LOST", seconds // 60, seconds % 60, percent, survivors, bonus,
		table.concat(lines, ", "), RESULTS_SECONDS))
	task.delay(RESULTS_SECONDS, function() returnToLobby(Players:GetPlayers(), "results timer") end)
end

RunState:GetAttributeChangedSignal("State"):Connect(function()
	local s = RunState:GetAttribute("State")
	if s == "Cleared" or s == "Failed" then finish(s :: string) end
end)
-- a respawn during the results (Health brings downed players back) gets the shield too
Players.PlayerAdded:Connect(function(p) p.CharacterAdded:Connect(function(c) if ended then protect(c) end end) end)
for _, p in ipairs(Players:GetPlayers()) do p.CharacterAdded:Connect(function(c) if ended then protect(c) end end) end

-- BACK TO LOBBY: go now instead of waiting for the timer
RunResults.OnServerEvent:Connect(function(p: Player, action: any)
	if action == "lobby" and ended then returnToLobby({ p }, "pressed BACK TO LOBBY") end
end)
Players.PlayerRemoving:Connect(function(p) returning[p] = nil end)

return { Finish = finish }
