--!strict
-- Profile (R-3 / KJ-66, Shayan 2026-09-29): the player's saved progress, shared by the lobby and the
-- gameplay place (the SAME module in both; one experience, one DataStore). The sheet: "Earn: cutting /
-- rescue / clear reward. Spend: upgrades, shop. Coins and upgrades persist via DataStore".
-- Saved, as player attributes the rest of the game already reads and writes:
--   Cash            the one currency (earned in runs, spent on upgrades and in the lobby shop)
--   Upg_<Line>_<Stat> every upgrade tier (UpgradeConfig), except the run-only lines (UpgradeConfig.RunOnly,
--                     KJ-100: drones are bought again every run, never saved or loaded)
--   Medkits         healing items bought in the lobby, used in the run (R-4)
-- Safety rules (no lost progress):
--   * a profile that failed to load is NEVER saved (it would overwrite real data with defaults)
--   * every save bumps a version; before a teleport the server saves and passes that version in the
--     TeleportData, and the arriving server waits (up to LOAD_WAIT s) until the store has caught up
--   * saves on leave, every AUTOSAVE_SECONDS, and on shutdown (BindToClose)
-- In an unpublished place (or without Studio API access) the DataStore is unavailable: the profile runs
-- in memory for the session and says so once.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local UpgradeConfig = require(game:GetService("ReplicatedStorage").Config.UpgradeConfig)

-- an Upg_<Line>_<Stat> attribute that belongs in the profile (not a run-only line)
local function saved(name: string): boolean
	local line = name:match("^Upg_([^_]+)_")
	return line ~= nil and not UpgradeConfig.RunOnly[line]
end

local STORE_NAME = "DismantleProfile_v1"
local AUTOSAVE_SECONDS = 60
local LOAD_WAIT = 10
local TRIES = 3

local store: DataStore? = nil
do
	local ok, res = pcall(function() return DataStoreService:GetDataStore(STORE_NAME) end)
	if ok then store = res else warn("[Profile] DataStore unavailable (" .. tostring(res) .. "): progress lives in memory this session") end
end

type Data = { version: number, cash: number, tiers: { [string]: number }, medkits: number }
type State = { loaded: boolean, version: number, dirty: boolean }
local states: { [Player]: State } = {}

local Profile = {}
Profile.Loaded = Instance.new("BindableEvent") -- (player) once the saved values are on the player

local function key(player: Player): string return "u_" .. player.UserId end

local function retry<T>(what: string, fn: () -> T): (boolean, T | string)
	local ok, res
	for attempt = 1, TRIES do
		ok, res = pcall(fn)
		if ok then return true, res end
		warn(("[Profile] %s failed (%d/%d): %s"):format(what, attempt, TRIES, tostring(res)))
		if attempt < TRIES then task.wait(attempt) end
	end
	return false, res
end

local function snapshot(player: Player): Data
	local tiers = {}
	for name, v in pairs(player:GetAttributes()) do
		if saved(name) and typeof(v) == "number" then tiers[name] = v end
	end
	return {
		version = 0,
		cash = math.max(0, math.floor(tonumber(player:GetAttribute("Cash")) or 0)),
		tiers = tiers,
		medkits = math.max(0, math.floor(tonumber(player:GetAttribute("Medkits")) or 0)),
	}
end

-- put saved values on the player. Anything earned in the seconds before the load landed is kept:
-- cash adds up, tiers and medkits take the higher value.
local function apply(player: Player, d: Data)
	player:SetAttribute("Cash", (tonumber(d.cash) or 0) + (tonumber(player:GetAttribute("Cash")) or 0))
	for name, tier in pairs(d.tiers or {}) do
		if typeof(tier) == "number" and saved(name) then
			player:SetAttribute(name, math.max(tier, tonumber(player:GetAttribute(name)) or 1))
		end
	end
	player:SetAttribute("Medkits", math.max(tonumber(d.medkits) or 0, tonumber(player:GetAttribute("Medkits")) or 0))
end

-- the save version the sending server wrote just before the teleport (0 when joining normally)
local function expectedVersion(player: Player): number
	local ok, join = pcall(function() return player:GetJoinData() end)
	local td = ok and join and join.TeleportData
	local versions = typeof(td) == "table" and td.profileVersions
	local v = typeof(versions) == "table" and versions[tostring(player.UserId)]
	return tonumber(v) or 0
end

local function load(player: Player)
	local st: State = { loaded = false, version = 0, dirty = false }
	states[player] = st
	if not store then
		st.loaded = true -- memory only; nothing to overwrite
		Profile.Loaded:Fire(player)
		return
	end
	local want = expectedVersion(player)
	local deadline = os.clock() + LOAD_WAIT
	local data: Data? = nil
	while true do
		local ok, res = retry("load " .. player.Name, function() return (store :: DataStore):GetAsync(key(player)) end)
		if not ok then
			warn(("[Profile] %s: could not load, progress will NOT be saved this session"):format(player.Name))
			return
		end
		data = res :: Data?
		local have = data and tonumber(data.version) or 0
		if have >= want or os.clock() >= deadline then
			if have < want then warn(("[Profile] %s: store still at v%d, expected v%d from the teleport; loading what is there"):format(player.Name, have, want)) end
			break
		end
		task.wait(1) -- the sending server's save has not landed yet
	end
	if not player.Parent then return end
	if data then apply(player, data) end
	st.version = data and tonumber(data.version) or 0
	st.loaded = true
	Profile.Loaded:Fire(player)
end

-- save now; returns the new version, or nil when nothing was written
function Profile.Save(player: Player): number?
	local st = states[player]
	if not (st and st.loaded and store) then return nil end
	local d = snapshot(player)
	local ok, res = retry("save " .. player.Name, function()
		return (store :: DataStore):UpdateAsync(key(player), function(old: Data?)
			d.version = (old and tonumber(old.version) or 0) + 1
			return d
		end)
	end)
	if not ok then return nil end
	st.version = (res :: Data).version
	st.dirty = false
	return st.version
end

-- save everyone about to teleport; the result goes into TeleportData as profileVersions
function Profile.SaveForTeleport(players: { Player }): { [string]: number }
	local versions = {}
	for _, p in ipairs(players) do
		local v = Profile.Save(p)
		if v then versions[tostring(p.UserId)] = v end
	end
	return versions
end

function Profile.IsLoaded(player: Player): boolean
	local st = states[player]
	return st ~= nil and st.loaded
end

-- anything saved changes -> saved on the next autosave (and always on leave)
local function watch(player: Player)
	player.AttributeChanged:Connect(function(name)
		local st = states[player]
		if st and (name == "Cash" or name == "Medkits" or saved(name)) then st.dirty = true end
	end)
end

Players.PlayerAdded:Connect(function(p) watch(p); task.spawn(load, p) end)
for _, p in ipairs(Players:GetPlayers()) do watch(p); task.spawn(load, p) end
Players.PlayerRemoving:Connect(function(p)
	Profile.Save(p)
	states[p] = nil
end)
game:BindToClose(function()
	if RunService:IsStudio() and not store then return end
	local pending = 0
	for _, p in ipairs(Players:GetPlayers()) do
		pending += 1
		task.spawn(function() Profile.Save(p); pending -= 1 end)
	end
	local t = os.clock()
	while pending > 0 and os.clock() - t < 25 do task.wait(0.2) end
end)
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_SECONDS)
		for p, st in pairs(states) do
			if st.dirty and p.Parent then task.spawn(Profile.Save, p) end
		end
	end
end)

return Profile
