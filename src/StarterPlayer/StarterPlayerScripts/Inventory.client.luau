--!strict
-- Inventory (B5 / TOOL-05 / TOOL-06, D5): three slots on keys 1-3 (the 4th was dropped 2026-09-29).
-- Switching costs exactly one action: one key press equips that slot (EquipTool swaps whatever
-- is held). Pressing the slot you already hold unequips it. Replaces the default hotbar.
-- The bar is authored in Studio (StarterGui.Hotbar: Bar.Slot1..3, each with a 3D IconView of its tool
-- and a Key label); this script only styles the slots from UITheme: gold rim on the held tool, the
-- icon dimmed while the tool is not owned. Click a slot to select it too.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Slots = require(ReplicatedStorage.Config.ToolConfig).Slots
local T = require(ReplicatedStorage.Config.UITheme)
local SLOT_COUNT = #Slots
local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three }

local player = Players.LocalPlayer

pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false) end)

local bar = player:WaitForChild("PlayerGui"):WaitForChild("Hotbar"):WaitForChild("Bar")
type Slot = { frame: Frame, stroke: UIStroke?, icon: ViewportFrame?, key: TextLabel? }
local slots: { Slot } = {}
for i = 1, SLOT_COUNT do
	local f = bar:WaitForChild("Slot" .. i) :: Frame
	slots[i] = {
		frame = f,
		stroke = f:FindFirstChild("Stroke") :: UIStroke?,
		icon = f:FindFirstChild("IconView") :: ViewportFrame?,
		key = f:FindFirstChild("Key") :: TextLabel?,
	}
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
		local s = slots[i]
		local name = Slots[i]
		local owned = name ~= nil and findTool(name) ~= nil
		local isHeld = owned and held == name
		s.frame.BackgroundColor3 = if isHeld then T.Line.Gun:Lerp(T.Palette.Panel, 0.55) else T.Palette.Panel
		if s.stroke then
			s.stroke.Color = if isHeld then T.Palette.Gold else T.Palette.Edge
			s.stroke.Thickness = if isHeld then 3 else 2
		end
		if s.icon then s.icon.ImageTransparency = if owned then 0 else 0.65 end
		if s.key then s.key.TextColor3 = if isHeld then T.Palette.Gold elseif owned then T.Palette.Text else T.Palette.TextDim end
	end
end

local function select(i: number)
	local hum = humanoid()
	if not hum or hum.Health <= 0 then return end
	local name = Slots[i]
	if not name then return end
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
for i, s in ipairs(slots) do
	s.frame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then select(i) end
	end)
end

local function watch(container: Instance)
	container.ChildAdded:Connect(function() task.defer(refresh) end)
	container.ChildRemoved:Connect(function() task.defer(refresh) end)
end
watch(player.Backpack)
player.CharacterAdded:Connect(function(char) watch(char); task.defer(refresh) end)
if player.Character then watch(player.Character) end
refresh()
print(("[Inventory] hotbar: %d slots with icons (%s)"):format(SLOT_COUNT, table.concat(Slots, ", ")))
