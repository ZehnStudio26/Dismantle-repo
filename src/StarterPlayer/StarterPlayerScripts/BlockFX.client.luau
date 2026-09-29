--!strict
-- BlockFX client (Cutting Polish Plan sections 1b and 4): the hit feel, all local presentation.
--   Hit    the WHOLE block punches: every chunk Part of the hit block scales together about the
--          block centre (in -> overshoot -> settle) from a snapshot, restored exactly; dust puff
--   Cell   shards fall from removed chunks, pooled and capped per hit; each removed chunk also
--          pops out (a ghost swells, then springs to nothing)
--   Reveal chunks and blocks the server revealed (RevealedAt attribute) pop in: they spring up from
--          small, overshoot and settle. Both springs are the mining pack's rock feel (FXConfig.PopSpring).
--   Block  completion: bigger dust burst and a "+$N" popup rising from the block
-- Nothing here is authoritative; the server decides what exists.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage.Config.FXConfig)
local KaijuConfig = require(ReplicatedStorage.Config.KaijuConfig)
local remote: RemoteEvent = ReplicatedStorage.Remotes.BlockFX

local fxFolder = Instance.new("Folder")
fxFolder.Name = "ClientFX"
fxFolder.Parent = workspace

-- ---------- whole-block punch + pop-in ----------
-- Every effect scales a part from its BASE size and place (recorded the first time an effect touches
-- it; the server never moves kaiju parts), so a punch landing mid pop-in cannot freeze a part small.
type Base = { size: Vector3, cf: CFrame }
local base: { [BasePart]: Base } = setmetatable({}, { __mode = "k" }) :: any
local function baseOf(part: BasePart): Base
	local b = base[part]
	if not b then b = { size = part.Size, cf = part.CFrame }; base[part] = b end
	return b
end
type BlockPop = { centre: Vector3, t0: number }
local pops: { [Instance]: BlockPop } = {}
type Spring = { x: number, v: number }
local grow: { [BasePart]: Spring } = {} -- pop-in springs, target 1
local S = Cfg.PopSpring
local OMEGA = math.sqrt(S.Stiffness)

-- one damped spring toward target, in fixed substeps so a slow frame cannot blow it up
local function stepSpring(sp: Spring, target: number, dt: number)
	local n = math.max(1, math.ceil(dt * 120))
	local h = dt / n
	for _ = 1, n do
		sp.v += (-S.Stiffness * (sp.x - target) - 2 * S.Damping * OMEGA * sp.v) * h
		sp.x += sp.v * h
	end
end

local IN, OUT, SETTLE = Cfg.Pop.In, Cfg.Pop.Out, Cfg.Pop.Settle
local T1, T2, T3 = IN[2], IN[2] + OUT[2], IN[2] + OUT[2] + SETTLE[2]

local function easeOut(x: number): number return 1 - (1 - x) * (1 - x) end
local function backOut(x: number): number local c = 1.7; local y = x - 1; return 1 + (c + 1) * y * y * y + c * y * y end

-- scale factor at time t into the timeline
local function scaleAt(t: number): number
	if t < T1 then return 1 + (IN[1] - 1) * easeOut(t / T1) end
	if t < T2 then return IN[1] + (OUT[1] - IN[1]) * backOut((t - T1) / OUT[2]) end
	if t < T3 then return OUT[1] + (SETTLE[1] - OUT[1]) * easeOut((t - T2) / SETTLE[2]) end
	return 1
end

-- place a part at punch scale (about the block centre) times its pop-in scale (about its own centre)
local function place(part: BasePart, punch: number?, centre: Vector3?)
	local b = baseOf(part)
	local g = grow[part]
	local s = if g then math.max(g.x, 0.01) else 1
	local pos = b.cf.Position
	if punch and centre then
		pos = centre + (pos - centre) * punch
		s *= punch
	end
	part.Size = b.size * s
	part.CFrame = CFrame.new(pos) * b.cf.Rotation
end

local function partsOf(block: Instance): { BasePart }
	local list = {}
	if block:IsA("BasePart") then table.insert(list, block) end
	for _, c in ipairs(block:GetChildren()) do if c:IsA("BasePart") then table.insert(list, c) end end
	return list
end

local function popBlock(block: Instance)
	local centre: Vector3
	if block:IsA("Model") then centre = block:GetPivot().Position
	elseif block:IsA("BasePart") then centre = baseOf(block).cf.Position
	else return end
	for _, part in ipairs(partsOf(block)) do baseOf(part) end -- record bases before the first frame scales them
	if not pops[block] then block.Destroying:Once(function() pops[block] = nil end) end
	pops[block] = { centre = centre, t0 = os.clock() } -- a re-hit restarts the punch; sizes always come from the base
end

local function popIn(part: BasePart)
	if grow[part] then return end
	baseOf(part)
	grow[part] = { x = S.RevealFrom, v = 0 }
	place(part) -- small from its first frame, no full-size flash
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	for part, sp in pairs(grow) do
		if not part.Parent then
			grow[part] = nil
		else
			stepSpring(sp, 1, dt)
			if math.abs(sp.x - 1) < 0.002 and math.abs(sp.v) < 0.02 then grow[part] = nil; place(part) end -- settled: back to the exact base
		end
	end
	local punched: { [BasePart]: boolean } = {}
	for block, p in pairs(pops) do
		local t = now - p.t0
		local done = t >= T3 or not block.Parent
		if done then pops[block] = nil end
		for _, part in ipairs(partsOf(block)) do
			punched[part] = true
			if done then place(part) else place(part, scaleAt(t), p.centre) end
		end
	end
	for part in pairs(grow) do if not punched[part] then place(part) end end
end)

-- ---------- pop-in: the parts the server revealed ----------
local kaiju = workspace:WaitForChild("Kaiju")
kaiju.DescendantAdded:Connect(function(d)
	if not d:IsA("BasePart") then return end
	local at = d:GetAttribute("RevealedAt")
	if typeof(at) == "number" and workspace:GetServerTimeNow() - at < S.RevealWindow then popIn(d) end
end)

-- ---------- pop-out ghosts (pooled) ----------
type Ghost = { part: Part, sp: Spring, born: number }
local ghostPool: { Part } = {}
local ghosts: { Ghost } = {}
for i = 1, S.MaxGhosts do
	local g = Instance.new("Part")
	g.Name = "PopGhost"
	g.Anchored = true
	g.CanCollide = false
	g.CanQuery = false
	g.CanTouch = false
	g.CastShadow = false
	g.Transparency = 1
	g.Parent = fxFolder
	ghostPool[i] = g
end
local ghostCF: { [Part]: CFrame } = {}
local ghostSize: { [Part]: Vector3 } = {}

local function popOut(cf: CFrame, size: Vector3, color: Color3, material: any)
	local part = table.remove(ghostPool)
	if not part then -- cap reached: recycle the oldest
		local oldest = table.remove(ghosts, 1)
		if not oldest then return end
		part = oldest.part
	end
	part.Color = color
	part.Material = if typeof(material) == "string" and typeof(KaijuConfig.Materials[material]) == "EnumItem" then KaijuConfig.Materials[material] else Enum.Material.SmoothPlastic
	part.Size = size
	part.CFrame = cf
	part.Transparency = 0
	ghostCF[part] = cf
	ghostSize[part] = size
	table.insert(ghosts, { part = part, sp = { x = 1, v = S.BreakImpulse }, born = os.clock() })
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	for i = #ghosts, 1, -1 do
		local g = ghosts[i]
		-- swell toward full size for SwellSeconds (the kick shows), then spring to nothing
		local swelling = now - g.born < S.SwellSeconds
		stepSpring(g.sp, if swelling then 1 else 0, dt)
		if not swelling and g.sp.x < S.HiddenScale and g.sp.v <= 0 then
			g.part.Transparency = 1
			table.remove(ghosts, i)
			table.insert(ghostPool, g.part)
		else
			g.part.Size = ghostSize[g.part] * math.max(g.sp.x, S.HiddenScale)
			g.part.CFrame = ghostCF[g.part]
		end
	end
end)
