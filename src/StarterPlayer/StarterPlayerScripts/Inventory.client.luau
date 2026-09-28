--!strict
-- Inventory (B5 / TOOL-05 / TOOL-06, D5): four slots on keys 1-4, slot 4 reserved and empty.
-- Switching costs exactly one action: one key press equips that slot (EquipTool swaps whatever
-- is held). Pressing the slot you already hold unequips it. Replaces the 10-slot default hotbar.
-- HUD art (M2f) will restyle the bar; this is a plain placeholder.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Slots = require(ReplicatedStorage.Config.ToolConfig).Slots
local SLOT_COUNT = 4
local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }
local NL = string.char(10)

local player = Players.LocalPlayer

pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false) end)

-- plain 4-slot bar
local gui = Instance.new("ScreenGui")
gui.Name = "InventoryBar"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")
local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -20)
bar.Size = UDim2.fromOffset(4 * 96 + 3 * 8, 64)
bar.BackgroundTransparency = 1
bar.Parent = gui
local labels: { TextLabel } = {}
for i = 1, SLOT_COUNT do
	local l = Instance.new("TextLabel")
	l.Name = "Slot" .. i
	l.Size = UDim2.fromOffset(96, 64)
	l.Position = UDim2.fromOffset((i - 1) * 104, 0)
	l.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	l.BackgroundTransparency = 0.3
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextSize = 14
	l.Font = Enum.Font.GothamBold
	l.TextWrapped = true
	l.Parent = bar
	labels[i] = l
end

local function character(): Model? return player.Character end
local function humanoid(): Humanoid?
	local char = character()
	return char and char:FindFirstChildOfClass("Humanoid")
end
local function findTool(name: string): Tool?
	local char = character()
	local t = (char and char:FindFirstChild(name)) or player.Backpack:FindFirstChild(name)
	return if t and t:IsA("Tool") then t else nil
end
local function heldName(): string?
	local char = character()
	local t = char and char:FindFirstChildOfClass("Tool")
	return t and t.Name
end

local function refresh()
	local held = heldName()
	for i = 1, SLOT_COUNT do
		local name = Slots[i]
		local l = labels[i]
		if not name then
			l.Text = i .. NL .. "(empty)"
			l.TextColor3 = Color3.fromRGB(110, 110, 120)
			l.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
		elseif not findTool(name) then
			l.Text = i .. NL .. name .. NL .. "(not owned)"
			l.TextColor3 = Color3.fromRGB(140, 140, 150)
			l.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
		else
			l.Text = i .. NL .. name
			l.TextColor3 = Color3.new(1, 1, 1)
			l.BackgroundColor3 = if held == name then Color3.fromRGB(200, 140, 30) else Color3.fromRGB(50, 50, 60)
		end
	end
end

local function select(i: number)
	local hum = humanoid()
	if not hum or hum.Health <= 0 then return end
	local name = Slots[i]
	if not name then
		print(("[Inventory] slot %d is reserved and empty (D5)"):format(i))
		return
	end
	local tool = findTool(name)
	if not tool then
		print(("[Inventory] slot %d: %s not owned"):format(i, name))
		return
	end
	if tool.Parent == character() then
		hum:UnequipTools()
		print(("[Inventory] unequipped %s"):format(name))
	else
		hum:EquipTool(tool) -- one action: swaps out whatever was held
		print(("[Inventory] slot %d -> %s"):format(i, name))
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	for i, key in ipairs(KEYS) do
		if input.KeyCode == key then select(i) end
	end
end)

local function watch(container: Instance)
	container.ChildAdded:Connect(function() task.defer(refresh) end)
	container.ChildRemoved:Connect(function() task.defer(refresh) end)
end
watch(player.Backpack)
player.CharacterAdded:Connect(function(char) watch(char); task.defer(refresh) end)
if player.Character then watch(player.Character) end
refresh()
