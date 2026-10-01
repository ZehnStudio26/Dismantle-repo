--!strict
-- MedkitUse (R-4, gameplay, Shayan 2026-09-29): H (or tapping the rail's MEDKIT button) uses a medkit
-- bought in the lobby. The button is authored in Studio (StarterGui.Upgrades.Rail.Entry_MedkitButton, the
-- same build as the UPGRADE / VIEW / TO TOP buttons: glyph, caption, key badge, count badge; moved there from
-- the HUD 2026-09-30); Fusion 0.3 Hydrate binds its count and shows it only while the player carries one.
-- The server (Server.Medkit) decides and heals; the button flashes green when it heals, grey when refused.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Fusion = require(ReplicatedStorage.Fusion)
local Shop = require(ReplicatedStorage.Config.ShopConfig)
local T = require(ReplicatedStorage.Config.UITheme)
local UseItem: RemoteEvent = ReplicatedStorage.Remotes.UseItem

local ID = "Medkit"
local item = Shop.Items[ID]
local player = Players.LocalPlayer
local rail = player:WaitForChild("PlayerGui"):WaitForChild("Upgrades"):WaitForChild("Rail")
local entry = rail:WaitForChild("Entry_MedkitButton") :: Frame
local button = entry:WaitForChild("MedkitButton") :: TextButton
local countLabel = button:WaitForChild("Count"):WaitForChild("Text") :: TextLabel

local scope = Fusion.scoped(Fusion)
local count = scope:Value(tonumber(player:GetAttribute(item.Attribute)) or 0)
table.insert(scope, player:GetAttributeChangedSignal(item.Attribute):Connect(function()
	count:set(tonumber(player:GetAttribute(item.Attribute)) or 0)
end))
scope:Hydrate(entry) { Visible = scope:Computed(function(use) return use(count) > 0 end) }
scope:Hydrate(countLabel) { Text = scope:Computed(function(use) return tostring(use(count)) end) }

local function use()
	UseItem:FireServer(ID)
end
button.Activated:Connect(use)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == item.UseKey then use() end
end)

local rest = button.BackgroundColor3
UseItem.OnClientEvent:Connect(function(_id: string, ok: boolean, _reason: string)
	button.BackgroundColor3 = if ok then T.Palette.Green else T.Palette.Edge
	TweenService:Create(button, TweenInfo.new(0.4), { BackgroundColor3 = rest }):Play()
end)
