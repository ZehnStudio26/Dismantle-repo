--!strict
-- PadManagers (Lobby, R-2 / KJ-69, Shayan 2026-09-29): matching pads. Step onto a pad to take one of its
-- MaxPlayers slots (the pads hold 1, 2, 3 and 4). The first player starts the pad's countdown; when the pad
-- fills up the countdown drops to FULL_COUNTDOWN. At zero everyone on the pad teleports TOGETHER into a
-- fresh reserved server of the gameplay place, so each party gets its own kaiju run.
-- Built on the free "Lobby System" kit (Workspace.Pads: Pad / Hitbox / Out per pad, the billboard, the
-- LobbyGui Leave button over Packets). Changed from the kit: a full pad deploys early; a player who
-- leaves, dies, walks off or quits frees the slot and the countdown keeps going for the rest; the
-- countdown resets to each pad's own value; TeleportAsync with ShouldReserveServer and retries.
-- Teleports never work in Studio: the log says so, and the pad resets.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local Packets = require(ReplicatedStorage.Modules.Packets)
local Profile = require(script.Parent.Profile) -- saved before the teleport so the run loads it (R-3)

local GAMEPLAY_PLACE_ID = 96604275292994 -- the "Kaiju" gameplay place; the lobby must be published into the same experience
local FULL_COUNTDOWN = 3                 -- seconds left once every slot is taken
local TELEPORT_TRIES = 3

type PadState = { model: Model, pad: BasePart, hitbox: BasePart, out: BasePart?, countdown: number, max: number, players: { Player }, token: number, deploying: boolean }
local pads: { PadState } = {}
local playerPad: { [Player]: PadState } = {}

local function rootOf(player: Player): BasePart?
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function alive(player: Player): boolean
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

local function onPad(st: PadState, player: Player): boolean
	local r = rootOf(player)
	if not r then return false end
	local p = st.hitbox.CFrame:PointToObjectSpace(r.Position)
	local h = st.hitbox.Size / 2
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end

local function setGui(player: Player, on: boolean)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local gui = pg and pg:FindFirstChild("LobbyGui")
	if gui and gui:IsA("ScreenGui") then gui.Enabled = on end
end

local function publish(st: PadState)
	st.model:SetAttribute("Players", #st.players)
end

local function resetCountdown(st: PadState)
	st.token += 1 -- stops a running countdown
	st.model:SetAttribute("Countdown", st.countdown)
end

-- free the player's slot; moveOut puts them on the pad's Out spot (the Leave button)
local function removePlayer(player: Player, why: string, moveOut: boolean?)
	local st = playerPad[player]
	if not st then return end
	playerPad[player] = nil
	local i = table.find(st.players, player)
	if i then table.remove(st.players, i) end
	local char = player.Character
	if char then char:SetAttribute("InPad", false) end
	local r = rootOf(player)
	if moveOut and r and st.out then r.CFrame = st.out.CFrame + Vector3.new(0, 3, 0) end
	setGui(player, false)
	publish(st)
	if #st.players == 0 and not st.deploying then resetCountdown(st) end
	print(("[Lobby] %s left the %d-slot pad (%s): %d/%d"):format(player.Name, st.max, why, #st.players, st.max))
end

local function deploy(st: PadState)
	st.deploying = true
	local party = table.clone(st.players)
	for _, p in ipairs(party) do
		if p.Character then p.Character:SetAttribute("Teleporting", true) end
	end
	local names = {}
	for _, p in ipairs(party) do table.insert(names, p.Name) end
	print(("[Lobby] deploying %d player(s) from the %d-slot pad: %s"):format(#party, st.max, table.concat(names, ", ")))
	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = true -- a fresh server: this party's own run
	-- save first: the gameplay server waits for these versions before it loads (no lost purchases)
	local versions = Profile.SaveForTeleport(party)
	options:SetTeleportData({ from = "Lobby", partySize = #party, profileVersions = versions })
	local ok, err = false, nil
	for attempt = 1, TELEPORT_TRIES do
		ok, err = pcall(function() TeleportService:TeleportAsync(GAMEPLAY_PLACE_ID, party, options) end)
		if ok then break end
		warn(("[Lobby] teleport attempt %d/%d failed: %s"):format(attempt, TELEPORT_TRIES, tostring(err)))
		if RunService:IsStudio() then break end -- Studio never teleports; no point retrying
		task.wait(2)
	end
	for _, p in ipairs(party) do
		if p.Character then p.Character:SetAttribute("Teleporting", false) end
	end
	st.deploying = false
	if ok then
		print(("[Lobby] teleport started for %d player(s) to place %d"):format(#party, GAMEPLAY_PLACE_ID))
		return -- they leave the server; PlayerRemoving frees the slots
	end
	if RunService:IsStudio() then
		warn("[Lobby] teleports only work in the published experience, not in a Studio playtest: the pad resets")
	end
	for _, p in ipairs(party) do removePlayer(p, "teleport failed", true) end
	resetCountdown(st)
end

local function runCountdown(st: PadState)
	st.token += 1
	local my = st.token
	task.spawn(function()
		local t = if #st.players >= st.max then math.min(FULL_COUNTDOWN, st.countdown) else st.countdown
		while true do
			if st.token ~= my then return end
			-- drop anyone who walked off, died or lost their character
			for i = #st.players, 1, -1 do
				local p = st.players[i]
				if not alive(p) then removePlayer(p, "down")
				elseif not onPad(st, p) then removePlayer(p, "walked off") end
			end
			if st.token ~= my or #st.players == 0 then return end
			if #st.players >= st.max then t = math.min(t, FULL_COUNTDOWN) end -- full: go soon
			st.model:SetAttribute("Countdown", t)
			if t <= 0 then break end
			task.wait(1)
			t -= 1
		end
		if st.token == my and #st.players > 0 then deploy(st) end
	end)
end

local function join(st: PadState, player: Player)
	if playerPad[player] or st.deploying or #st.players >= st.max then return end
	local char = player.Character
	local r = rootOf(player)
	if not (char and r and alive(player)) or char:GetAttribute("Teleporting") then return end
	table.insert(st.players, player)
	playerPad[player] = st
	char:SetAttribute("InPad", true)
	r.CFrame = st.pad.CFrame + Vector3.new(0, 3, 0)
	setGui(player, true)
	publish(st)
	print(("[Lobby] %s took a slot on the %d-slot pad: %d/%d"):format(player.Name, st.max, #st.players, st.max))
	if #st.players == 1 then runCountdown(st) end -- the first player starts the clock; later ones join it
end

for _, model in ipairs(workspace:WaitForChild("Pads"):GetChildren()) do
	if not model:IsA("Model") then continue end
	local pad = model:FindFirstChild("Pad") :: BasePart?
	local hitbox = model:FindFirstChild("Hitbox") :: BasePart?
	if not (pad and hitbox) then warn("[Lobby] " .. model:GetFullName() .. " has no Pad / Hitbox") continue end
	local st: PadState = {
		model = model, pad = pad, hitbox = hitbox, out = model:FindFirstChild("Out") :: BasePart?,
		countdown = tonumber(model:GetAttribute("Countdown")) or 15,
		max = tonumber(model:GetAttribute("MaxPlayers")) or 4,
		players = {}, token = 0, deploying = false,
	}
	table.insert(pads, st)
	local att = pad:FindFirstChild("BillboardAttachment")
	local bb = att and att:FindFirstChildOfClass("BillboardGui")
	local playersText = bb and bb:FindFirstChild("PlayersText") :: TextLabel?
	local countdownText = bb and bb:FindFirstChild("Countdown") :: TextLabel?
	local function show()
		if playersText then playersText.Text = ("PLAYERS %d/%d"):format(#st.players, st.max) end
		if countdownText then
			local c = tonumber(model:GetAttribute("Countdown")) or st.countdown
			countdownText.Text = if st.deploying or (c <= 0 and #st.players > 0) then "DEPLOYING" else tostring(c)
		end
	end
	model:GetAttributeChangedSignal("Players"):Connect(show)
	model:GetAttributeChangedSignal("Countdown"):Connect(show)
	model:SetAttribute("Players", 0)
	model:SetAttribute("Countdown", st.countdown)
	show()
	hitbox.Touched:Connect(function(hit: BasePart)
		local char = hit.Parent
		local player = char and Players:GetPlayerFromCharacter(char)
		if player then join(st, player) end
	end)
end

Packets.Leave.OnServerEvent:Connect(function(player: Player) removePlayer(player, "pressed LEAVE", true) end)
Players.PlayerRemoving:Connect(function(player) removePlayer(player, "left the game") end)
local function watch(player: Player)
	player.CharacterRemoving:Connect(function() removePlayer(player, "respawned") end)
end
Players.PlayerAdded:Connect(watch)
for _, p in ipairs(Players:GetPlayers()) do watch(p) end
-- a teleport that starts but fails on the way (full server, network): back off the pad, try again
TeleportService.TeleportInitFailed:Connect(function(player: Player, result: Enum.TeleportResult, message: string)
	warn(("[Lobby] teleport of %s failed: %s %s"):format(player.Name, result.Name, message))
	removePlayer(player, "teleport failed", true)
end)

print(("[Lobby] %d pad(s) ready (slots %s), deploying to place %d"):format(#pads, (function()
	local s = {}
	for _, st in ipairs(pads) do table.insert(s, tostring(st.max)) end
	table.sort(s)
	return table.concat(s, "/")
end)(), GAMEPLAY_PLACE_ID))
