--!strict
-- Shop (R-1 / R-4, lobby, Shayan 2026-09-29): one remote, BuyItem(itemId). The item id is checked as a
-- known string before any lookup, then: profile loaded, not at the carry limit, affordable (Cash),
-- charge, +1, save right away. Every answer goes back to the client for the shop's hint line.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shop = require(ReplicatedStorage.Config.ShopConfig)
local Profile = require(script.Parent.Profile)
require(script.Parent.Upgrades) -- the in-game upgrade server (same module as the gameplay place): BuyUpgrade in the lobby too
local BuyItem: RemoteEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BuyItem")

local lastBuy: { [Player]: number } = {}

local function reply(player: Player, item: string, ok: boolean, reason: string)
	BuyItem:FireClient(player, item, ok, reason)
end

BuyItem.OnServerEvent:Connect(function(player: Player, itemId: any)
	if typeof(itemId) ~= "string" then return end
	local item = Shop.Items[itemId]
	if not item then return end -- forged or malformed: nothing to index
	local now = os.clock()
	if now - (lastBuy[player] or 0) < 0.25 then return end
	lastBuy[player] = now
	if not Profile.IsLoaded(player) then reply(player, itemId, false, "still loading your save") return end
	local have = tonumber(player:GetAttribute(item.Attribute)) or 0
	if have >= item.Max then reply(player, itemId, false, ("you can carry %d"):format(item.Max)) return end
	local cash = tonumber(player:GetAttribute("Cash")) or 0
	if cash < item.Price then reply(player, itemId, false, ("need $%d, have $%d"):format(item.Price, cash)) return end
	player:SetAttribute("Cash", cash - item.Price)
	player:SetAttribute(item.Attribute, have + 1)
	task.spawn(Profile.Save, player) -- a purchase is saved at once
	reply(player, itemId, true, ("bought for $%d (%d/%d carried, $%d left)"):format(item.Price, have + 1, item.Max, cash - item.Price))
end)

Players.PlayerRemoving:Connect(function(player) lastBuy[player] = nil end)
