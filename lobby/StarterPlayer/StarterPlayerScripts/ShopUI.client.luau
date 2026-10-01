--!strict
-- ShopUI (R-1 / R-4, lobby, Shayan 2026-09-29): binds the Studio-authored StarterGui.Shop to the player's
-- saved Cash and items with Fusion 0.3 (Hydrate over existing instances; no layout is built here).
-- Opens from the rail's SHOP entry (StarterGui.Upgrades.Rail.Entry_ShopButton) or B; CLOSE or gamepad B
-- closes it. Opening it closes the upgrade panel so the two never overlap. The server (Shop) is the
-- only writer of Cash and the item counts; the card just follows them.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Fusion = require(ReplicatedStorage.Fusion)
local Stores = require(ReplicatedStorage.UI.Stores)
local Shop = require(ReplicatedStorage.Config.ShopConfig)
local T = require(ReplicatedStorage.Config.UITheme)
local BuyItem: RemoteEvent = ReplicatedStorage.Remotes.BuyItem

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local gui = pg:WaitForChild("Shop") :: ScreenGui
local panel = gui:WaitForChild("Panel") :: Frame
local win = panel:WaitForChild("Window") :: Frame
local pop = win:FindFirstChild("Pop") :: UIScale? or Instance.new("UIScale")
pop.Name = "Pop"
pop.Parent = win
local hint = panel:WaitForChild("Hint") :: TextLabel
local cashLabel = panel:WaitForChild("Cash") :: TextLabel
local closeButton = panel:WaitForChild("Close") :: TextButton
local upgrades = pg:WaitForChild("Upgrades") :: ScreenGui
local shopButton = upgrades:WaitForChild("Rail"):WaitForChild("Entry_ShopButton"):WaitForChild("ShopButton") :: TextButton

local scope = Fusion.scoped(Fusion)
local P = Stores.Player(scope, player)

scope:Hydrate(cashLabel) { Text = scope:Computed(function(use) return ("$ %d"):format(use(P.Cash)) end) }

-- one card per item, named Item_<id> in the Window
for _, id in ipairs(Shop.Order) do
	local item = Shop.Items[id]
	local card = win:FindFirstChild("Item_" .. id)
	if not card then warn("[Shop] no card for " .. id) continue end
	local count = scope:Value(tonumber(player:GetAttribute(item.Attribute)) or 0)
	table.insert(scope, player:GetAttributeChangedSignal(item.Attribute):Connect(function()
		count:set(tonumber(player:GetAttribute(item.Attribute)) or 0)
	end))
	local full = scope:Computed(function(use) return use(count) >= item.Max end)
	local affordable = scope:Computed(function(use) return use(P.Cash) >= item.Price end)
	scope:Hydrate(card:WaitForChild("Owned") :: TextLabel) {
		Text = scope:Computed(function(use) return ("CARRYING %d/%d"):format(use(count), item.Max) end),
	}
	local buy = card:WaitForChild("Buy") :: TextButton
	-- the text sits in an outlined Caption label, like the rail buttons (2026-09-30)
	scope:Hydrate(buy:WaitForChild("Caption") :: TextLabel) {
		Text = scope:Computed(function(use) return if use(full) then "FULL" else ("BUY  $%d"):format(item.Price) end),
	}
	scope:Hydrate(buy) {
		BackgroundColor3 = scope:Computed(function(use)
			return if use(full) then T.Palette.Edge elseif use(affordable) then T.Palette.Accent else T.Palette.Red
		end),
	}
	buy.Activated:Connect(function() BuyItem:FireServer(id) end)
end

BuyItem.OnClientEvent:Connect(function(id: string, ok: boolean, reason: string)
	local item = Shop.Items[id]
	hint.Text = ("%s %s: %s"):format(if ok then "Bought" else "Not bought,", if item then item.Label else id, reason)
	hint.TextColor3 = if ok then T.Palette.Gold else T.Palette.RedText
end)

local function setOpen(open: boolean)
	if open then
		local up = upgrades:FindFirstChild("Panel")
		if up and up:IsA("GuiObject") then up.Visible = false end
		hint.Text = ""
		panel.BackgroundTransparency = 1
		pop.Scale = 0.9 -- pop through a UIScale: the window keeps its authored (or phone / tablet) Size
		panel.Visible = true
		TweenService:Create(panel, T.Tween.Open, { BackgroundTransparency = 0.45 }):Play()
		TweenService:Create(pop, T.Tween.Open, { Scale = 1 }):Play()
	else
		panel.Visible = false
	end
	print(("[Shop] panel %s"):format(if open then "opened" else "closed"))
end
shopButton.Activated:Connect(function() setOpen(not panel.Visible) end)
closeButton.Activated:Connect(function() setOpen(false) end)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.ButtonB and panel.Visible then setOpen(false) return end
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.B then setOpen(not panel.Visible) end
end)
