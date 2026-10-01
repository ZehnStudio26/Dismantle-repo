--!strict
-- EventFX (client only): shared screen-space event effects over the Studio-authored StarterGui.EventFX
-- (Templates: Arrow / Popup / Coin, cloned into Layer; nothing is built here). One RenderStepped loop
-- drives every arrow and popup. Positions are written in Scale (fractions of Layer).
--
-- API
--   EventFX.arrow(target: Instance | Vector3 | () -> Vector3?, opts: { color: Color3?, text: string?, showDistance: boolean? })
--     -> { Destroy: (self) -> (), setText: (self, string) -> () }
--     Edge-of-screen pointer to the target while it is off-screen or behind the camera, hidden while
--     it is on screen. BasePart -> Position, Model -> GetPivot().Position, a function may return nil
--     (= hidden). A target Instance that is destroyed / loses its Parent destroys the arrow. Label is
--     `text`; with showDistance it reads "Nm" (studs / 3, from your character), or "<text> Nm" when
--     both are given. color tints the tip and rim (default Palette.Gold). At most 4 arrows show at once,
--     oldest first; a 5th waits until one is destroyed. Callers must :Destroy() arrows they own.
--   EventFX.popup(text: string, at: Vector3 | UDim2, opts: { color: Color3?, seconds: number? }?) -> ()
--     Floating text at a world point (projected every frame) or a Layer UDim2. Rises ~5% of the screen
--     and fades out over `seconds` (default 1.2). Skipped when the world point is off-screen.
--   EventFX.coins(amount: number, from: Vector3) -> ()
--     min(amount, 8) coins (halved on low-end devices) burst out at `from` on screen (screen centre if
--     off-screen), then fly to the HUD Cash label (PlayerGui.HUD.Cash) and bounce it via its "Bounce"
--     UIScale. Visual only: it never changes Cash.
-- Server code fires these through Server.FX (Remotes.FX -> StarterPlayerScripts.EventFXClient).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local T = require(ReplicatedStorage.Config.UITheme)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("EventFX") :: ScreenGui
local templates = gui:WaitForChild("Templates")
local layer = gui:WaitForChild("Layer") :: Frame
local ARROW = templates:WaitForChild("Arrow") :: Frame
local POPUP = templates:WaitForChild("Popup") :: TextLabel
local COIN = templates:WaitForChild("Coin") :: Frame

local MAX_ARROWS = 4
local EDGE_INSET = 0.06 -- of screen height, both axes
local POPUP_RISE = 0.05
local MAX_COINS = 8
local SCATTER = 0.04 -- of screen height
local SCATTER_TIME = 0.15
local COIN_STAGGER = 0.04
local FLY_TIME = 0.45

local EventFX = {}

-- ---- helpers ----
local function toScale(p: Vector2): UDim2
	local size = layer.AbsoluteSize
	return UDim2.fromScale(p.X / math.max(size.X, 1), p.Y / math.max(size.Y, 1))
end

-- world -> Layer pixels; Layer covers the whole screen (IgnoreGuiInset, ScreenInsets None) so viewport
-- pixels are Layer pixels
local function project(world: Vector3): (Vector2, boolean)
	local cam = workspace.CurrentCamera
	local v, onScreen = cam:WorldToViewportPoint(world)
	return Vector2.new(v.X, v.Y), onScreen and v.Z > 0
end

local function myPosition(): Vector3
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root.Position end
	return workspace.CurrentCamera.CFrame.Position
end

-- frame-rate estimate for the low-end check
local avgDt = 1 / 60
local function lowEnd(): boolean
	local ok, level = pcall(function() return UserSettings().GameSettings.SavedQualityLevel end)
	if ok and level ~= Enum.SavedQualitySetting.Automatic then
		return level.Value >= 1 and level.Value <= 3
	end
	return avgDt > 1 / 30
end

-- ---- arrows ----
type Arrow = {
	resolve: () -> Vector3?,
	inst: Instance?,
	frame: Frame,
	pointer: GuiObject,
	label: TextLabel,
	text: string?,
	showDistance: boolean,
	dead: boolean,
	Destroy: (self: Arrow) -> (),
	setText: (self: Arrow, text: string) -> (),
}
local arrows: { Arrow } = {}

local ArrowMethods = {}
function ArrowMethods.Destroy(self: Arrow)
	if self.dead then return end
	self.dead = true
	self.frame:Destroy()
	local i = table.find(arrows, self)
	if i then table.remove(arrows, i) end
end
function ArrowMethods.setText(self: Arrow, text: string)
	self.text = text
end

function EventFX.arrow(target: Instance | Vector3 | () -> Vector3?, opts: { color: Color3?, text: string?, showDistance: boolean? }): Arrow
	local resolve: () -> Vector3?
	local inst: Instance? = nil
	if typeof(target) == "Vector3" then
		resolve = function() return target end
	elseif typeof(target) == "Instance" then
		inst = target
		resolve = function()
			if target:IsA("BasePart") then return target.Position end
			if target:IsA("Model") then return target:GetPivot().Position end
			return nil
		end
	else
		resolve = target :: () -> Vector3?
	end
	local frame = ARROW:Clone()
	local color = opts.color or T.Palette.Gold
	local pointer = frame:FindFirstChild("Pointer") :: Frame
	local tip = pointer:FindFirstChild("Tip") :: Frame
	tip.BackgroundColor3 = color
	local rim = (frame:FindFirstChild("Disc") :: Frame):FindFirstChildOfClass("UIStroke")
	if rim then rim.Color = color end
	local label = frame:FindFirstChild("Label") :: TextLabel
	label.Text = ""
	frame.Visible = false
	frame.Parent = layer
	local self = setmetatable({
		resolve = resolve,
		inst = inst,
		frame = frame,
		pointer = pointer,
		label = label,
		text = opts.text,
		showDistance = opts.showDistance == true,
		dead = false,
	}, { __index = ArrowMethods }) :: any
	table.insert(arrows, self)
	return self :: Arrow
end

local function stepArrow(a: Arrow, shown: boolean)
	if a.inst and not a.inst.Parent then a:Destroy(); return end
	local world = if shown then a.resolve() else nil
	if not world then a.frame.Visible = false; return end
	local cam = workspace.CurrentCamera
	local _, onScreen = project(world)
	if onScreen then a.frame.Visible = false; return end
	-- direction in camera space works in front of and behind the camera alike
	local rel = cam.CFrame:PointToObjectSpace(world)
	local dir = Vector2.new(rel.X, -rel.Y)
	if dir.Magnitude < 1e-3 then dir = Vector2.new(0, 1) end
	local size = layer.AbsoluteSize
	local inset = EDGE_INSET * size.Y
	local half = size / 2
	local hx, hy = math.max(half.X - inset, 1), math.max(half.Y - inset, 1)
	local t = math.min(if dir.X ~= 0 then hx / math.abs(dir.X) else math.huge, if dir.Y ~= 0 then hy / math.abs(dir.Y) else math.huge)
	a.frame.Position = toScale(half + dir * t)
	a.pointer.Rotation = math.deg(math.atan2(dir.Y, dir.X))
	local text = a.text
	if a.showDistance then
		local dist = ("%dm"):format(math.floor((world - myPosition()).Magnitude / 3 + 0.5))
		text = if text and text ~= "" then text .. " " .. dist else dist
	end
	a.label.Text = text or ""
	a.frame.Visible = true
end

-- ---- popups ----
type Popup = { label: TextLabel, stroke: UIStroke?, world: Vector3?, screen: UDim2?, born: number, seconds: number }
local popups: { Popup } = {}

function EventFX.popup(text: string, at: Vector3 | UDim2, opts: { color: Color3?, seconds: number? }?)
	if typeof(at) == "Vector3" then
		local _, onScreen = project(at)
		if not onScreen then return end
	end
	local label = POPUP:Clone()
	label.Text = text
	if opts and opts.color then label.TextColor3 = opts.color end
	label.Visible = false
	label.Parent = layer
	table.insert(popups, {
		label = label,
		stroke = label:FindFirstChildOfClass("UIStroke"),
		world = if typeof(at) == "Vector3" then at else nil,
		screen = if typeof(at) == "UDim2" then at else nil,
		born = os.clock(),
		seconds = math.max((opts and opts.seconds) or 1.2, 0.05),
	})
end

local function stepPopup(p: Popup): boolean
	local alpha = (os.clock() - p.born) / p.seconds
	if alpha >= 1 then p.label:Destroy(); return false end
	local base: UDim2
	if p.world then
		local pos, onScreen = project(p.world)
		if not onScreen then p.label.Visible = false; return true end
		base = toScale(pos)
	else
		base = p.screen :: UDim2
	end
	local rise = POPUP_RISE * (1 - (1 - alpha) ^ 2) -- ease out
	p.label.Position = base - UDim2.fromScale(0, rise)
	local fade = math.clamp((alpha - 0.4) / 0.6, 0, 1) -- hold, then fade
	p.label.TextTransparency = fade
	if p.stroke then p.stroke.Transparency = fade end
	p.label.Visible = true
	return true
end

-- ---- coins ----
local POP = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true) -- 1 -> 1.15 -> 1
local function bounceCash(cash: GuiObject)
	local scale = cash:FindFirstChild("Bounce")
	if not scale or not scale:IsA("UIScale") then return end
	scale.Scale = 1
	TweenService:Create(scale, POP, { Scale = 1.15 }):Play()
end

function EventFX.coins(amount: number, from: Vector3)
	local n = math.min(math.floor(amount), MAX_COINS)
	if n <= 0 then return end
	if lowEnd() then n = math.max(1, math.ceil(n / 2)) end
	local size = layer.AbsoluteSize
	local start, onScreen = project(from)
	if not onScreen then start = size / 2 end
	for i = 1, n do
		local coin = COIN:Clone()
		coin.Position = toScale(start)
		coin.Visible = true
		coin.Parent = layer
		local angle = math.random() * math.pi * 2
		local r = SCATTER * size.Y * (0.6 + 0.4 * math.random())
		local burst = start + Vector2.new(math.cos(angle), math.sin(angle)) * r
		TweenService:Create(coin, TweenInfo.new(SCATTER_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = toScale(burst) }):Play()
		task.delay(SCATTER_TIME + (i - 1) * COIN_STAGGER, function()
			local hud = playerGui:FindFirstChild("HUD")
			local cash = hud and hud:FindFirstChild("Cash")
			if not cash or not cash:IsA("GuiObject") or not coin.Parent then coin:Destroy(); return end
			local goal = cash.AbsolutePosition + cash.AbsoluteSize / 2 - layer.AbsolutePosition
			local fly = TweenService:Create(coin, TweenInfo.new(FLY_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = toScale(goal) })
			fly.Completed:Once(function()
				coin:Destroy()
				bounceCash(cash)
			end)
			fly:Play()
		end)
	end
end

-- ---- the one loop ----
RunService.RenderStepped:Connect(function(dt)
	avgDt += (dt - avgDt) * 0.05
	-- iterate a copy: stepArrow may Destroy (and remove) an arrow
	for i, a in ipairs(table.clone(arrows)) do
		stepArrow(a, i <= MAX_ARROWS)
	end
	local i = 1
	while i <= #popups do
		if stepPopup(popups[i]) then i += 1 else table.remove(popups, i) end
	end
end)

return EventFX
