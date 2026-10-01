--!strict
-- GasOverlay (EVT-04): when the server flags this player InGas, the screen tints green and the world
-- fogs in, so gas "fills the screen and cuts visibility". Heavy without the mask, light with it.
-- Reads the Masked attribute owned by Server.Mask; never inspects the character.
-- Placeholder until M2c gas VFX. Lighting edits on the client are local to this player.
-- 2026-10-01, the gas HUD cues (timing published by Server.Gas, see its header):
--   * tick ring, StarterGui.HUD.GasTick (authored in Studio, Hydrated here with Fusion): while InGas it
--     fills clockwise toward the next damage tick of the cloud you stand in, from the part's StartedAt /
--     DamageFrom / TickPeriod / EndsAt (server time); during the grace period it fills toward the first
--     tick. The centre reads the seconds left. Two clipped halves, each a circle whose UIGradient has a
--     hard 50% step: turning the gradient sweeps the edge (Right 0-180 deg, then Left 180-360).
--   * GasBlocked rises (the mask took a tick): the ring flashes white and reads HELD, its Pulse UIScale
--     pops, Cfg.BreathHeldSoundId plays when set.
--   * GasHits rises (damage landed): a quick green edge flash; from the Cfg.HeavyHit-th hit of one
--     exposure on, a darker and longer vignette. No camera shake.
-- ponytail: the ScreenGui is built here rather than authored in StarterGui. Inherited, and it is one
-- full-screen Frame plus two edge Frames with no layout; the eyehole overlay for the mask is authored in
-- Studio instead.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fusion = require(ReplicatedStorage.Fusion)
local Cfg = require(ReplicatedStorage.Config.EventConfig).Gas

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "GasOverlay"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = -1
gui.Parent = playerGui
local tint = Instance.new("Frame")
tint.Name = "Tint"
tint.Size = UDim2.fromScale(1, 1)
tint.BackgroundColor3 = Color3.fromRGB(110, 190, 70)
tint.BackgroundTransparency = 1
tint.BorderSizePixel = 0
tint.Parent = gui

local UNMASKED, MASKED, CLEAR = 0.35, 0.8, 1

-- Visibility loss. An Atmosphere, when present, overrides Lighting fog, so drive whichever the place
-- uses: Atmosphere.Density if there is one, else FogEnd. Base values are what the place had at load.
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
local baseDensity = if atmosphere then atmosphere.Density else 0
local baseFogEnd, baseFogStart = Lighting.FogEnd, Lighting.FogStart
local DENSITY_UNMASKED, DENSITY_MASKED = 0.7, 0.45
local FOG_UNMASKED, FOG_MASKED = 60, 160

-- ---- edge flash: two full-screen frames, opaque at the edges through a UIGradient, clear inside ----
local EDGE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 1),
	NumberSequenceKeypoint.new(0.7, 1), NumberSequenceKeypoint.new(1, 0),
})
local edges: { Frame } = {}
for _, rotation in ipairs({ 0, 90 }) do
	local e = Instance.new("Frame")
	e.Name = "Edge"
	e.Size = UDim2.fromScale(1, 1)
	e.BackgroundTransparency = 1
	e.BorderSizePixel = 0
	e.Parent = gui
	local g = Instance.new("UIGradient")
	g.Rotation = rotation
	g.Transparency = EDGE
	g.Parent = e
	table.insert(edges, e)
end
local HIT_COLOR, HEAVY_COLOR = Color3.fromRGB(90, 210, 60), Color3.fromRGB(10, 35, 8)
local function flash(color: Color3, strength: number, seconds: number)
	for _, e in ipairs(edges) do
		e.BackgroundColor3 = color
		e.BackgroundTransparency = 1 - strength
		TweenService:Create(e, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
	end
end

-- ---- tick ring (HUD.GasTick) ----
local hazards = workspace:WaitForChild("Hazards")
local ring = playerGui:WaitForChild("HUD"):WaitForChild("GasTick") :: Frame
local pulse = ring:WaitForChild("Pulse") :: UIScale
local rightFill = ring:WaitForChild("Right"):WaitForChild("Fill") :: Frame
local leftFill = ring:WaitForChild("Left"):WaitForChild("Fill") :: Frame
local label = ring:WaitForChild("Hole"):WaitForChild("Label") :: TextLabel

local FILL, FILL_MASKED, FILL_HELD = Color3.fromRGB(140, 230, 90), Color3.fromRGB(120, 210, 230), Color3.fromRGB(255, 255, 255)
local HELD_SECONDS = 0.6 -- the ring reads HELD this long after a blocked tick
local MARGIN = 2 -- studs: the server counts any body part in the box, the ring looks from the root
local POP = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true) -- 1 -> 1.25 -> 1

local scope = Fusion.scoped(Fusion)
local shown = scope:Value(false)
local progress = scope:Value(0) -- 0..1 toward the next tick
local remain = scope:Value(0)   -- seconds to it
local maskedV = scope:Value(false)
local held = scope:Value(false)
local fillColor = scope:Computed(function(use)
	return if use(held) then FILL_HELD elseif use(maskedV) then FILL_MASKED else FILL
end)
scope:Hydrate(ring) { Visible = shown }
scope:Hydrate(rightFill) { BackgroundColor3 = fillColor }
scope:Hydrate(leftFill) { BackgroundColor3 = fillColor }
scope:Hydrate(rightFill:WaitForChild("UIGradient")) {
	Rotation = scope:Computed(function(use) return 360 * math.min(use(progress), 0.5) end),
}
scope:Hydrate(leftFill:WaitForChild("UIGradient")) {
	Rotation = scope:Computed(function(use) return 180 + 360 * math.clamp(use(progress) - 0.5, 0, 0.5) end),
}
scope:Hydrate(label) {
	Text = scope:Computed(function(use) return if use(held) then "HELD" else ("%.1f"):format(use(remain)) end),
	TextColor3 = fillColor,
}

local function num(inst: Instance, name: string): number?
	local v = inst:GetAttribute(name)
	return if typeof(v) == "number" then v else nil
end

-- the soonest upcoming tick of a live cloud holding `pos`: (fraction filled, seconds left), nil if none
local function nextTick(pos: Vector3, t: number): (number?, number)
	local bestAt, bestSpan = math.huge, 1
	for _, c in ipairs(hazards:GetChildren()) do
		if c:IsA("BasePart") then
			local period, from, started, ends = num(c, "TickPeriod"), num(c, "DamageFrom"), num(c, "StartedAt"), num(c, "EndsAt")
			if period and from and started and ends and t < ends then
				local rel = c.CFrame:PointToObjectSpace(pos)
				local half = c.Size / 2
				if math.abs(rel.X) <= half.X + MARGIN and math.abs(rel.Y) <= half.Y + MARGIN and math.abs(rel.Z) <= half.Z + MARGIN then
					local at, span
					if t < from then
						at, span = from, math.max(from - started, 1e-3)
					else
						at, span = from + (math.floor((t - from) / period) + 1) * period, period
					end
					if at < ends and at < bestAt then bestAt, bestSpan = at, span end -- a tick past EndsAt never lands
				end
			end
		end
	end
	if bestAt == math.huge then return nil, 0 end
	local left = bestAt - t
	return math.clamp(1 - left / bestSpan, 0, 1), left
end

-- ---- tick cues, from the counters Server.Gas keeps per exposure ----
local breath: Sound? = nil
if Cfg.BreathHeldSoundId ~= "" then
	local s = Instance.new("Sound")
	s.SoundId = Cfg.BreathHeldSoundId
	s.Parent = gui
	breath = s
end
local function counter(name: string, onRise: (n: number) -> ())
	local last = 0
	player:GetAttributeChangedSignal(name):Connect(function()
		local n = num(player, name) or 0
		if n > last then onRise(n) end
		last = n
	end)
end
local heldTicket = 0
counter("GasBlocked", function()
	held:set(true)
	heldTicket += 1
	local mine = heldTicket
	task.delay(HELD_SECONDS, function() if mine == heldTicket then held:set(false) end end)
	pulse.Scale = 1
	TweenService:Create(pulse, POP, { Scale = 1.25 }):Play()
	if breath then breath:Play() end
end)
counter("GasHits", function(n)
	if n >= Cfg.HeavyHit then flash(HEAVY_COLOR, 0.9, 1.0) else flash(HIT_COLOR, 0.6, 0.35) end
	pulse.Scale = 1
	TweenService:Create(pulse, POP, { Scale = 1.25 }):Play()
end)

RunService.RenderStepped:Connect(function(dt)
	local inGas = player:GetAttribute("InGas") == true
	local masked = player:GetAttribute("Masked") == true
	local k = math.min(1, dt * 6)
	local target = if not inGas then CLEAR elseif masked then MASKED else UNMASKED
	tint.BackgroundTransparency += (target - tint.BackgroundTransparency) * k
	if atmosphere then
		local d = if not inGas then baseDensity elseif masked then DENSITY_MASKED else DENSITY_UNMASKED
		atmosphere.Density += (d - atmosphere.Density) * k
	else
		local f = if not inGas then baseFogEnd elseif masked then FOG_MASKED else FOG_UNMASKED
		Lighting.FogEnd += (f - Lighting.FogEnd) * k
		Lighting.FogStart = math.min(baseFogStart, Lighting.FogEnd * 0.5)
	end
	local char = player.Character
	local root = if inGas and char then char:FindFirstChild("HumanoidRootPart") else nil
	local p: number?, left = nil, 0
	if root and root:IsA("BasePart") then p, left = nextTick(root.Position, workspace:GetServerTimeNow()) end
	shown:set(p ~= nil)
	if p then
		progress:set(p)
		remain:set(left)
	end
	maskedV:set(masked)
end)
