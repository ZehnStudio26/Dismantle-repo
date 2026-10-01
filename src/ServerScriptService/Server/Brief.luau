--!strict
-- Brief (B13 / MAP-09 / MAP-10): remembers how many times each player has been briefed, so the
-- client narrates the first run and offers a skip from the second. Storage is a DataStore behind
-- pcall; in an unpublished place (no API access) it falls back to in-session memory and says so
-- once. Player attribute BriefRuns carries the count to the client.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage.Remotes
local BriefShow: RemoteEvent = Remotes.BriefShow
local BriefDone: RemoteEvent = Remotes.BriefDone

local store: DataStore? = nil
local storeWarned = false
pcall(function() store = DataStoreService:GetDataStore("DismantleProfile") end)

local function key(player: Player): string return "brief_" .. player.UserId end

local function storeUnavailable(err: any)
	if storeWarned then return end
	storeWarned = true
	warn(("[Brief] DataStore unavailable (%s). Brief counts live in memory for this session only. Publish the place and enable API access to persist."):format(tostring(err)))
end

local function load(player: Player): number
	if store then
		local ok, v = pcall(function() return (store :: DataStore):GetAsync(key(player)) end)
		if ok then return tonumber(v) or 0 end
		storeUnavailable(v)
	end
	return 0
end

local function save(player: Player, runs: number)
	if not store then return end
	local ok, err = pcall(function() (store :: DataStore):SetAsync(key(player), runs) end)
	if not ok then storeUnavailable(err) end
end

Players.PlayerAdded:Connect(function(player)
	local runs = load(player)
	player:SetAttribute("BriefRuns", runs)
	-- The client shows the brief itself once it sees the attribute; a remote fired here could
	-- land before the client script is listening. BriefShow stays for explicit replays.
end)

BriefDone.OnServerEvent:Connect(function(player: Player, skipped: boolean?)
	local runs = (tonumber(player:GetAttribute("BriefRuns")) or 0) + 1
	player:SetAttribute("BriefRuns", runs)
	save(player, runs)
end)

-- Replay the brief for a player (a lobby button later, tests now).
local Brief = {}
function Brief.Replay(player: Player)
	BriefShow:FireClient(player, tonumber(player:GetAttribute("BriefRuns")) or 0)
end

return Brief
