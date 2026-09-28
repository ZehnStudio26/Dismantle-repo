--!strict
-- HUD (B9 / HUD-01..04): top = team demolition %, bottom-left = HP, edges = active event
-- warnings, centre = run state banner and a short flash when an event fires. The four inventory
-- slots at the bottom are drawn by Inventory. Plain text until M2f supplies HUD art.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunState = ReplicatedStorage:WaitForChild("RunState")
local hazards = workspace:WaitForChild("Hazards")
local enemies = workspace:WaitForChild("Enemies")
local player = Players.LocalPlayer
local NL = string.char(10)

pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false) end)

local gui = Instance.new("ScreenGui")
gui.Name = "HUD"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function label(name: string, size: UDim2, pos: UDim2, anchor: Vector2, textSize: number, align: Enum.TextXAlignment): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = pos
	l.AnchorPoint = anchor
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.4
	l.TextSize = textSize
	l.Font = Enum.Font.GothamBold
	l.TextXAlignment = align
	l.Text = ""
	l.Parent = gui
	return l
end

-- HUD-01 top: shared demolition %
local percent = label("Percent", UDim2.fromOffset(600, 40), UDim2.new(0.5, 0, 0, 12), Vector2.new(0.5, 0), 26, Enum.TextXAlignment.Center)
local percentBar = Instance.new("Frame")
percentBar.Name = "PercentBar"
percentBar.AnchorPoint = Vector2.new(0.5, 0)
percentBar.Position = UDim2.new(0.5, 0, 0, 54)
percentBar.Size = UDim2.fromOffset(400, 10)
percentBar.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
percentBar.BorderSizePixel = 0
percentBar.Parent = gui
local percentFill = Instance.new("Frame")
percentFill.Name = "Fill"
percentFill.Size = UDim2.fromScale(0, 1)
percentFill.BackgroundColor3 = Color3.fromRGB(230, 180, 40)
percentFill.BorderSizePixel = 0
percentFill.Parent = percentBar

-- HUD-02 bottom-left: HP
local hp = label("HP", UDim2.fromOffset(240, 30), UDim2.new(0, 20, 1, -110), Vector2.new(0, 1), 20, Enum.TextXAlignment.Left)
local hpBar = Instance.new("Frame")
hpBar.Name = "HPBar"
hpBar.Position = UDim2.new(0, 20, 1, -104)
hpBar.AnchorPoint = Vector2.new(0, 0)
hpBar.Size = UDim2.fromOffset(240, 12)
hpBar.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
hpBar.BorderSizePixel = 0
hpBar.Parent = gui
local hpFill = Instance.new("Frame")
hpFill.Name = "Fill"
hpFill.Size = UDim2.fromScale(1, 1)
hpFill.BackgroundColor3 = Color3.fromRGB(80, 200, 90)
hpFill.BorderSizePixel = 0
hpFill.Parent = hpBar

-- money (7.1 says it must be on screen); provisional Cash attribute until Q04
local cash = label("Cash", UDim2.fromOffset(240, 30), UDim2.new(0, 20, 1, -140), Vector2.new(0, 1), 22, Enum.TextXAlignment.Left)
cash.TextColor3 = Color3.fromRGB(255, 220, 90)

-- HUD-04 edges: active event warnings
local leftWarn = label("GasWarning", UDim2.fromOffset(200, 60), UDim2.new(0, 20, 0.5, 0), Vector2.new(0, 0.5), 22, Enum.TextXAlignment.Left)
leftWarn.TextColor3 = Color3.fromRGB(140, 230, 90)
local rightWarn = label("LarvaWarning", UDim2.fromOffset(200, 60), UDim2.new(1, -20, 0.5, 0), Vector2.new(1, 0.5), 22, Enum.TextXAlignment.Right)
rightWarn.TextColor3 = Color3.fromRGB(255, 110, 90)

-- centre: state banner and event flash
local banner = label("Banner", UDim2.fromOffset(800, 60), UDim2.new(0.5, 0, 0.35, 0), Vector2.new(0.5, 0.5), 40, Enum.TextXAlignment.Center)
local flash = label("EventFlash", UDim2.fromOffset(600, 40), UDim2.new(0.5, 0, 0.42, 0), Vector2.new(0.5, 0.5), 28, Enum.TextXAlignment.Center)
flash.TextColor3 = Color3.fromRGB(255, 220, 120)
local flashUntil = 0
RunState:GetAttributeChangedSignal("EventCount"):Connect(function()
	flash.Text = ("EVENT: %s"):format(string.upper(tostring(RunState:GetAttribute("LastEvent"))))
	flashUntil = os.clock() + 3
end)

local function aliveEnemies(): number
	local n = 0
	for _, e in ipairs(enemies:GetChildren()) do
		local h = e:FindFirstChildOfClass("Humanoid")
		if h and h.Health > 0 then n += 1 end
	end
	return n
end

RunService.RenderStepped:Connect(function()
	local pct = tonumber(RunState:GetAttribute("DemolitionPercent")) or 0
	local remaining = tonumber(RunState:GetAttribute("RemainingBlocks")) or 0
	local total = tonumber(RunState:GetAttribute("TotalBlocks")) or 0
	percent.Text = ("DISMANTLED %.2f%%   %d / %d blocks left"):format(pct, remaining, total)
	percentFill.Size = UDim2.fromScale(math.clamp(pct / 100, 0, 1), 1)

	cash.Text = ("$ %d"):format(tonumber(player:GetAttribute("Cash")) or 0)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hp.Text = ("HP %d / %d"):format(math.ceil(hum.Health), hum.MaxHealth)
		local f = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
		hpFill.Size = UDim2.fromScale(f, 1)
		hpFill.BackgroundColor3 = if f > 0.5 then Color3.fromRGB(80, 200, 90) elseif f > 0.25 then Color3.fromRGB(230, 180, 40) else Color3.fromRGB(220, 60, 50)
	end

	local clouds = #hazards:GetChildren()
	local larvae = aliveEnemies()
	local inGas = player:GetAttribute("InGas") == true
	local masked = char ~= nil and char:FindFirstChild("GasMask") ~= nil
	leftWarn.Text = if clouds > 0 then ("GAS x%d%s"):format(clouds, if inGas then (NL .. (if masked then "masked" else "PUT ON MASK")) else "") else ""
	rightWarn.Text = if larvae > 0 then ("LARVA x%d"):format(larvae) else ""

	local state = tostring(RunState:GetAttribute("State"))
	banner.Text = if state == "Cleared" then "KAIJU DISMANTLED" elseif state == "Failed" then "RUN FAILED" else ""
	flash.Visible = os.clock() < flashUntil
end)
