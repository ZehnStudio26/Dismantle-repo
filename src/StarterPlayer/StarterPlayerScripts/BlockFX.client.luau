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
local counts = { punch = 0, popIn = 0, popOut = 0 }

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
	counts.punch += 1
end

local function popIn(part: BasePart)
	if grow[part] then return end
	baseOf(part)
	grow[part] = { x = S.RevealFrom, v = 0 }
	place(part) -- small from its first frame, no full-size flash
	counts.popIn += 1
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
	counts.popOut += 1
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

-- a short summary for playtest logs, at most every 5 s and only while something popped
task.spawn(function()
	while true do
		task.wait(5)
		if counts.punch + counts.popIn + counts.popOut > 0 then
			print(("[BlockFX] last 5 s: %d block punch(es), %d chunk pop-out(s), %d pop-in(s)"):format(counts.punch, counts.popOut, counts.popIn))
			counts.punch, counts.popIn, counts.popOut = 0, 0, 0
		end
	end
end)

-- ---------- dust ----------
local dustPart = Instance.new("Part")
dustPart.Name = "Dust"
dustPart.Size = Vector3.one
dustPart.Transparency = 1
dustPart.Anchored = true
dustPart.CanCollide = false
dustPart.CanQuery = false
dustPart.CanTouch = false
dustPart.Parent = fxFolder
local dust = Instance.new("ParticleEmitter")
dust.Rate = 0
dust.Lifetime = NumberRange.new(Cfg.Dust.Lifetime * 0.6, Cfg.Dust.Lifetime)
dust.Speed = NumberRange.new(6, 14)
dust.SpreadAngle = Vector2.new(180, 180)
dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) })
dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
dust.Color = ColorSequence.new(Color3.fromRGB(200, 200, 190))
dust.LightEmission = 0.2
dust.Parent = dustPart

local function puff(pos: Vector3, count: number)
	dustPart.Position = pos
	dust:Emit(count)
end

-- ---------- shards (pooled) ----------
type Shard = { part: Part, born: number, life: number }
local pool: { Part } = {}
local live: { Shard } = {}
for i = 1, Cfg.Debris.MaxLive do
	local s = Instance.new("Part")
	s.Name = "Shard"
	s.Anchored = true
	s.CanCollide = false
	s.CanQuery = false
	s.CanTouch = false
	s.CastShadow = false
	s.Transparency = 1
	s.Parent = fxFolder
	pool[i] = s
end

local rng = Random.new()

local function recycle(sh: Shard)
	sh.part.Anchored = true
	sh.part.Transparency = 1
	sh.part.AssemblyLinearVelocity = Vector3.zero
	sh.part.AssemblyAngularVelocity = Vector3.zero
	table.insert(pool, sh.part)
end

local function shard(cf: CFrame, size: Vector3, color: Color3)
	local part = table.remove(pool)
	if not part then -- cap reached: recycle the oldest
		local oldest = table.remove(live, 1)
		if not oldest then return end
		recycle(oldest)
		part = table.remove(pool) :: Part
	end
	local d = Cfg.Debris
	part.Size = size * d.Scale * rng:NextNumber(0.7, 1.15)
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = 0
	part.CFrame = cf * CFrame.new(rng:NextNumber(-0.3, 0.3) * size.X, rng:NextNumber(-0.3, 0.3) * size.Y, rng:NextNumber(-0.3, 0.3) * size.Z)
		* CFrame.Angles(rng:NextNumber(0, math.pi), rng:NextNumber(0, math.pi), 0)
	part.Anchored = false
	local out = (part.Position - cf.Position)
	local dir = if out.Magnitude > 0.1 then out.Unit else Vector3.yAxis
	part.AssemblyLinearVelocity = dir * d.Speed + Vector3.new(0, d.Speed * 0.5, 0)
	part.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * d.Spin
	table.insert(live, { part = part, born = os.clock(), life = d.Lifetime })
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for i = #live, 1, -1 do
		local sh = live[i]
		local age = now - sh.born
		if age >= sh.life then
			recycle(sh)
			table.remove(live, i)
		elseif age >= sh.life * Cfg.Debris.FadeAt then
			sh.part.Transparency = (age - sh.life * Cfg.Debris.FadeAt) / (sh.life * (1 - Cfg.Debris.FadeAt))
		end
	end
end)

-- ---------- "+$N" popup on block completion ----------
local popupsShown = 0
local function popup(pos: Vector3, text: string, color: Color3)
	local P = Cfg.Popup
	popupsShown += 1
	local anchor = Instance.new("Part")
	anchor.Name = "Popup"
	anchor.Size = Vector3.one
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Position = pos
	anchor.Parent = fxFolder
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 40)
	gui.AlwaysOnTop = true
	gui.MaxDistance = P.MaxDistance
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
	local born = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local a = (os.clock() - born) / P.Lifetime
		if a >= 1 or not anchor.Parent then
			conn:Disconnect()
			anchor:Destroy()
			return
		end
		anchor.Position = pos + Vector3.new(0, P.Rise * easeOut(a), 0)
		local fade = math.max(0, (a - 0.5) * 2)
		label.TextTransparency = fade
		label.TextStrokeTransparency = 0.2 + 0.8 * fade
	end)
end

-- ---------- events ----------
local lastBurst, burstCount = 0, 0
remote.OnClientEvent:Connect(function(kind: string, a: any, b: any, c: any, d: any)
	if kind == "Hit" then
		-- a = first chunk, b = block (Model or Part), c = hit position
		if typeof(b) == "Instance" and b.Parent then popBlock(b) end
		if typeof(c) == "Vector3" then puff(c, Cfg.Dust.PerHit) end
	elseif kind == "Cell" then
		if typeof(a) == "CFrame" and typeof(b) == "Vector3" and typeof(c) == "Color3" then popOut(a, b, c, d) end
		local now = os.clock()
		if now - lastBurst > 0.05 then lastBurst = now; burstCount = 0 end
		if burstCount < (Cfg.Debris.MaxPerHit or 4) and typeof(a) == "CFrame" and typeof(b) == "Vector3" and typeof(c) == "Color3" then
			burstCount += 1
			for _ = 1, Cfg.Debris.PerCell do shard(a, b, c) end
		end
	elseif kind == "Block" then
		-- a = block cframe, b = size, c = cash awarded, d = actor name
		if typeof(a) == "CFrame" then
			puff(a.Position, Cfg.Dust.PerBlock)
			if typeof(c) == "number" and c > 0 then
				local mine = typeof(d) == "string" and d == Players.LocalPlayer.Name
				popup(a.Position, ("+$%d"):format(c), if mine then Cfg.Popup.MineColor else Cfg.Popup.OtherColor)
			end
		end
	end
end)

-- exposed for tests
_G.BlockFX = {
	LiveShards = function() return #live end,
	PoolSize = function() return #pool end,
	ActivePops = function() local n = 0 for _ in pairs(pops) do n += 1 end return n end,
	Growing = function() local n = 0 for _ in pairs(grow) do n += 1 end return n end,
	Ghosts = function() return #ghosts end,
	PopupsShown = function() return popupsShown end,
}
