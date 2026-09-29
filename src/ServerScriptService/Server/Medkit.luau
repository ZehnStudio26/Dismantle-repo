--!strict
-- Medkit (R-4 / KJ-70, gameplay, Shayan 2026-09-29): "Buy in lobby, bring into the run, use to heal".
-- One remote, UseItem(itemId). Checked: a known item, alive, carrying one, not already at full health
-- (a wasted medkit is worse than a refused press), a short cooldown. Heals ShopConfig Heal (capped at
-- MaxHealth), takes one away, saves at once (Profile) so a crash never refunds or loses it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shop = require(ReplicatedStorage.Config.ShopConfig)
local Profile = require(script.Parent.Profile)
local UseItem: RemoteEvent = ReplicatedStorage.Remotes.UseItem

local COOLDOWN = 1
local lastUse: { [Player]: number } = {}

local function reply(player: Player, id: string, ok: boolean, reason: string)
	UseItem:FireClient(player, id, ok, reason)
	print(("[Medkit] %s %s: %s"):format(player.Name, id, reason))
end

UseItem.OnServerEvent:Connect(function(player: Player, id: any)
	if typeof(id) ~= "string" then return end
	local item = Shop.Items[id]
	if not item or not item.Heal then return end
	local now = os.clock()
	if now - (lastUse[player] or 0) < COOLDOWN then return end
	lastUse[player] = now
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	local have = tonumber(player:GetAttribute(item.Attribute)) or 0
	if have <= 0 then reply(player, id, false, "none left (buy them in the lobby shop)") return end
	if hum.Health >= hum.MaxHealth then reply(player, id, false, "already at full health") return end
	local before = hum.Health
	hum.Health = math.min(hum.MaxHealth, hum.Health + item.Heal)
	player:SetAttribute(item.Attribute, have - 1)
	task.spawn(Profile.Save, player)
	reply(player, id, true, ("%.0f -> %.0f HP, %d left"):format(before, hum.Health, have - 1))
end)

Players.PlayerRemoving:Connect(function(player) lastUse[player] = nil end)

return true
