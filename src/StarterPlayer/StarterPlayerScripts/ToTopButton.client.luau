--!strict
-- ToTopButton: the rail's TO TOP button (StarterGui.Upgrades.Rail.Entry_TopButton, authored in Studio) or
-- the T key asks the server (Remotes.ToTop, Server.Scaffolding) to put you on the open layer. It only
-- works while you are OFF the open layer and once every RunConfig.ToTopCooldown seconds; the server
-- decides, this script only shows it. Fusion 0.3 Hydrate over the authored button: bright when it would
-- work, dimmed otherwise, and the caption counts the cooldown down ("12s").
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Fusion)
local T = require(ReplicatedStorage.Config.UITheme)
local ToTop = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ToTop") :: RemoteEvent
local RunState = ReplicatedStorage:WaitForChild("RunState")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("Upgrades")
local button = gui:WaitForChild("Rail"):WaitForChild("Entry_TopButton"):WaitForChild("TopButton") :: TextButton
local caption = button:WaitForChild("Caption") :: TextLabel
local kaiju = workspace:WaitForChild("Kaiju")

local BASE = button.BackgroundColor3
local scope = Fusion.scoped(Fusion)
local offLayer = scope:Value(false)
local cooldownLeft = scope:Value(0)

-- off the open layer = feet more than 2 studs under its top face (the server applies the same rule)
local function isOff(): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local active = RunState:GetAttribute("ActiveLayer")
	local origin = kaiju:GetAttribute("Origin")
	local B = tonumber(kaiju:GetAttribute("BlockSize")) or 12
	if not root or not root:IsA("BasePart") or typeof(active) ~= "number" or typeof(origin) ~= "Vector3" then return false end
	return root.Position.Y - 3 < origin.Y + active * B + B / 2 - 2
end

local until_ = 0
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.2 then return end
	acc = 0
	offLayer:set(isOff())
	cooldownLeft:set(math.max(0, math.ceil(until_ - os.clock())))
end)

local ready = scope:Computed(function(use) return use(offLayer) and use(cooldownLeft) <= 0 and RunState:GetAttribute("State") == "Running" end)
scope:Hydrate(button) {
	BackgroundColor3 = scope:Computed(function(use) return if use(ready) then BASE else BASE:Lerp(T.Palette.Panel, 0.6) end),
	AutoButtonColor = ready,
}
scope:Hydrate(caption) {
	Text = scope:Computed(function(use)
		local left = use(cooldownLeft)
		return if left > 0 then ("%ds"):format(left) else "TO TOP"
	end),
	TextColor3 = scope:Computed(function(use) return if use(ready) then T.Palette.Text else T.Palette.TextDim end),
}

local function press()
	ToTop:FireServer()
end
button.MouseButton1Click:Connect(press)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.T then press() end
end)
ToTop.OnClientEvent:Connect(function(ok: boolean, why: string, wait: number)
	if (ok or wait > 0) and wait > 0 then until_ = os.clock() + wait end
end)
