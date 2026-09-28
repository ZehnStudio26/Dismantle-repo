--!strict
-- GasOverlay (EVT-04): when the server flags this player InGas, a green screen tint cuts
-- visibility. Heavy without the mask, light with it. Placeholder until M2c gas VFX.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "GasOverlay"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = -1
gui.Parent = player:WaitForChild("PlayerGui")
local tint = Instance.new("Frame")
tint.Name = "Tint"
tint.Size = UDim2.fromScale(1, 1)
tint.BackgroundColor3 = Color3.fromRGB(110, 190, 70)
tint.BackgroundTransparency = 1
tint.BorderSizePixel = 0
tint.Parent = gui

local UNMASKED, MASKED, CLEAR = 0.35, 0.8, 1

RunService.RenderStepped:Connect(function(dt)
	local char = player.Character
	local inGas = player:GetAttribute("InGas") == true
	local masked = char ~= nil and char:FindFirstChild("GasMask") ~= nil
	local target = if not inGas then CLEAR elseif masked then MASKED else UNMASKED
	tint.BackgroundTransparency += (target - tint.BackgroundTransparency) * math.min(1, dt * 6)
end)
