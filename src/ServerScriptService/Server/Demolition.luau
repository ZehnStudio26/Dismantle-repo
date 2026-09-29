--!strict
-- Demolition v4 (Large Voxel Kaiju): the single entry point for removing kaiju material.
-- Two-level rendering, the way the reference reads:
--   block   an 8-stud voxel. Intact + exposed  -> one Part under Workspace.Kaiju
--                            Intact + hidden   -> a Part parked in ServerStorage.KaijuHidden (never replicated)
--                            Cracked           -> a Model of its exposed chunk Parts (Grid^3 chunks, lazy)
--   chunk   the unit of damage inside a cracked block. Exposed chunks are Parts; hidden ones are data.
-- A block cracks on its first hit. Removing a chunk reveals hidden neighbour chunks and un-parks hidden
-- neighbour blocks. A block completes when its last chunk goes. One hit spends its damage on the exposed
-- chunks nearest the hit point, chunk after chunk, so DPS stays exact.
-- D7 (drone never cuts event blocks) and D9 (gun never cuts the kaiju) are enforced once, in CanDamage.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local KaijuConfig = require(ReplicatedStorage.Config.KaijuConfig)
local RunConfig = require(ReplicatedStorage.Config.RunConfig)

local RunState = ReplicatedStorage:WaitForChild("RunState")
local G: number = (KaijuConfig.Cells and KaijuConfig.Cells.Grid) or 3
local UNITS = G * G * G
local DIRS = { Vector3.xAxis, -Vector3.xAxis, Vector3.yAxis, -Vector3.yAxis, Vector3.zAxis, -Vector3.zAxis }

local Demolition = {}
Demolition.Cleared = Instance.new("BindableEvent")     -- fired once when the last block goes
Demolition.BlockBroken = Instance.new("BindableEvent") -- (cframe, size, material, source, actor: Player?, cash) before the block is destroyed
Demolition.CellHit = Instance.new("BindableEvent")     -- (firstChunk, blockModel, hitPos, 0, source) once per hit that landed
Demolition.CellBroken = Instance.new("BindableEvent")  -- (cframe, size, color, material, source) per removed chunk

type Block = {
	key: Vector3,          -- block grid key (BX, BY, BZ)
	part: BasePart?,       -- intact voxel Part (in Kaiju when exposed, in KaijuHidden when hidden)
	model: Model?,         -- cracked block container
	chunks: { [Vector3]: number }?, -- cracked: remaining chunk key -> hp
	chunkParts: { [Vector3]: BasePart },
	left: number,
	deadPart: BasePart?,   -- the intact Part after cracking: still resolves, so an aim or drone target taken a tick earlier keeps working
	deadChunks: { BasePart }, -- removed chunk Parts: a client aim can be a frame stale; they still resolve to the block until it is gone
}

local kaiju: Model? = nil
local hiddenFolder: Folder? = nil
local B = 8
local C = B / G
local origin = Vector3.zero
local blocks: { [Vector3]: Block } = {}
local instToBlock: { [Instance]: Block } = {}
local contribution: { [string]: number } = {}
local remainingBlocks, totalBlocks = 0, 0
local unitsLeft, totalUnits = 0, 0

local function publish()
	RunState:SetAttribute("RemainingBlocks", remainingBlocks)
	-- 4 decimals: with ~950k chunks one chunk is 0.0001%, and the HUD rounds for display
	RunState:SetAttribute("DemolitionPercent", totalUnits > 0 and math.floor((1 - unitsLeft / totalUnits) * 1000000) / 10000 or 0)
end

local function holder(b: Block): Instance? return b.model or b.part end
local function material(b: Block): string?
	local h = holder(b)
	local m = h and h:GetAttribute("BlockMaterial")
	return if typeof(m) == "string" then m else nil
end
local function chunkMaxHP(b: Block): number
	local m = material(b)
	return ((m and KaijuConfig.BlockHP[m]) or KaijuConfig.BlockHP.Default) / UNITS
end
local function isEventBlock(b: Block): boolean
	local m = material(b)
	return m ~= nil and KaijuConfig.EventMaterials[m] == true
end
local function blockCFrame(b: Block): CFrame return CFrame.new(origin + b.key * B) end
local function surface(b: Block): Enum.Material
	local m = material(b)
	local mats = KaijuConfig.Materials
	return (mats and ((m and mats[m]) or mats.Default)) or Enum.Material.SmoothPlastic
end
local function blockKeyOf(chunkKey: Vector3): Vector3
	return Vector3.new(math.floor(chunkKey.X / G), math.floor(chunkKey.Y / G), math.floor(chunkKey.Z / G))
end
local function chunkKey(b: Block, x: number, y: number, z: number): Vector3
	return Vector3.new(b.key.X * G + x, b.key.Y * G + y, b.key.Z * G + z)
end
local function localIndex(b: Block, ck: Vector3): (number, number, number)
	return ck.X - b.key.X * G, ck.Y - b.key.Y * G, ck.Z - b.key.Z * G
end

-- occupancy at chunk resolution, without a chunk table for intact blocks
local function chunkOccupied(ck: Vector3): boolean
	local b = blocks[blockKeyOf(ck)]
	if not b then return false end
	if b.chunks == nil then return true end -- intact: all chunks present
	return b.chunks[ck] ~= nil
end
local function chunkExposed(ck: Vector3): boolean
	for _, d in ipairs(DIRS) do if not chunkOccupied(ck + d) then return true end end
	return false
end

local function tint(b: Block, x: number, y: number, z: number): Color3
	local h = holder(b)
	local base = h and h:GetAttribute("Color")
	if typeof(base) ~= "Color3" then base = Color3.fromRGB(150, 150, 150) end
	local r = Random.new(b.key.X * 73856093 + b.key.Y * 19349663 + b.key.Z * 83492791 + x * 7 + y * 131 + z * 1031)
	local t = 1 + r:NextNumber(-0.05, 0.05)
	return Color3.new(math.clamp(base.R * t, 0, 1), math.clamp(base.G * t, 0, 1), math.clamp(base.B * t, 0, 1))
end

-- an intact block becomes visible: move its Part from the hidden folder into the kaiju
local function showBlock(b: Block)
	if b.part and b.part.Parent ~= kaiju then
		b.part.CFrame = blockCFrame(b) -- hidden parts do not follow the model when it is moved in Studio
		b.part.Parent = kaiju
	end
end

local function createChunkPart(b: Block, ck: Vector3)
	if b.chunkParts[ck] or not b.model then return end
	local x, y, z = localIndex(b, ck)
	local p = Instance.new("Part")
	p.Name = ("C_%d_%d_%d"):format(x, y, z)
	p.Size = Vector3.new(C, C, C)
	p.CFrame = blockCFrame(b) * CFrame.new((x + 0.5) * C - B / 2, (y + 0.5) * C - B / 2, (z + 0.5) * C - B / 2)
	p.Anchored = true
	p.Material = surface(b) -- chunks wear the block skin (Phase 1 materials)
	p.Color = tint(b, x, y, z)
	p:SetAttribute("CX", x); p:SetAttribute("CY", y); p:SetAttribute("CZ", z)
	p.Parent = b.model
	b.chunkParts[ck] = p
	instToBlock[p] = b
end

-- split an intact block into its chunks (Parts for the exposed ones only)
local function crack(b: Block)
	if b.chunks then return end
	local part = b.part :: BasePart
	local m = Instance.new("Model")
	m.Name = part.Name
	for _, a in ipairs({ "BlockMaterial", "Region", "BlockId", "Demolishable", "Color", "BX", "BY", "BZ" }) do m:SetAttribute(a, part:GetAttribute(a)) end
	b.model = m
	b.chunks = {}
	local hp = chunkMaxHP(b)
	for x = 0, G - 1 do for y = 0, G - 1 do for z = 0, G - 1 do (b.chunks :: { [Vector3]: number })[chunkKey(b, x, y, z)] = hp end end end
	-- keep the old Part resolvable: clients and the drone may still reference it for a tick
	b.deadPart = part
	part:Destroy()
	b.part = nil
	m.Parent = kaiju
	instToBlock[m] = b
	for ck in pairs(b.chunks :: { [Vector3]: number }) do
		if chunkExposed(ck) then createChunkPart(b, ck) end
	end
	-- set the pivot AFTER the parts exist: a pivot written on an empty Model is discarded, and a lost
	-- pivot made every reach / range check fail after the first hit (one-hit-then-nothing bug)
	m.WorldPivot = blockCFrame(b)
	-- neighbours behind a cracked block can be seen through its holes
	for _, d in ipairs(DIRS) do
		local nb = blocks[b.key + d]
		if nb and nb.chunks == nil then showBlock(nb) end
	end
end

local function revealAround(ck: Vector3)
	for _, d in ipairs(DIRS) do
		local nk = ck + d
		local nb = blocks[blockKeyOf(nk)]
		if nb then
			if nb.chunks == nil then showBlock(nb)
			elseif nb.chunks[nk] ~= nil and not nb.chunkParts[nk] then createChunkPart(nb, nk) end
		end
	end
end

-- The block holder (intact Part or cracked Model) for any block or chunk instance, or nil.
function Demolition.Resolve(inst: Instance?): PVInstance?
	if not inst then return nil end
	local b = instToBlock[inst]
	if not b then return nil end
	return holder(b) :: PVInstance?
end

function Demolition.CanDamage(inst: Instance?, source: string): (boolean, string?)
	if RunState:GetAttribute("State") ~= "Running" then return false, "run is not running" end
	local b = inst and instToBlock[inst]
	if not b then return false, "not a live kaiju block" end
	if source == "Gun" then return false, "D9: gun does not cut the kaiju" end
	if source == "Drone" and isEventBlock(b) then return false, "D7: drone never cuts event blocks" end
	return true, nil
end

local function forgetBlock(b: Block, source: string?)
	if not blocks[b.key] then return end
	blocks[b.key] = nil
	for _, p in pairs(b.chunkParts) do instToBlock[p] = nil end
	if b.part then instToBlock[b.part] = nil end
	if b.deadPart then instToBlock[b.deadPart] = nil end
	for _, p in ipairs(b.deadChunks) do instToBlock[p] = nil end
	if b.model then instToBlock[b.model] = nil end
	unitsLeft -= b.left
	remainingBlocks -= 1
	if source then contribution[source] = (contribution[source] or 0) + 1 end
	-- everything around the gone block is now open air
	for _, d in ipairs(DIRS) do
		local nb = blocks[b.key + d]
		if nb then
			if nb.chunks == nil then showBlock(nb)
			else for ck in pairs(nb.chunks) do if not nb.chunkParts[ck] and chunkExposed(ck) then createChunkPart(nb, ck) end end end
		end
	end
	publish()
	if remainingBlocks == 0 then
		RunState:SetAttribute("State", "Cleared")
		Demolition.Cleared:Fire()
	end
end

function Demolition.Break(inst: Instance, source: string, actor: Player?)
	local b = instToBlock[inst]
	if not b then return end
	-- reward on completion only (reference); provisional until Q04
	local cash = 0
	if actor and actor.Parent then
		cash = RunConfig.CashPerBlock[source] or 0
		if cash > 0 then actor:SetAttribute("Cash", (tonumber(actor:GetAttribute("Cash")) or 0) + cash) end
	end
	Demolition.BlockBroken:Fire(blockCFrame(b), Vector3.new(B, B, B), material(b), source, actor, cash)
	local h = holder(b)
	forgetBlock(b, source)
	if h then h:Destroy() end
end

local function removeChunk(b: Block, ck: Vector3, source: string, actor: Player?)
	local p = b.chunkParts[ck]
	;(b.chunks :: { [Vector3]: number })[ck] = nil
	b.left -= 1
	unitsLeft -= 1
	if p then
		Demolition.CellBroken:Fire(p.CFrame, p.Size, p.Color, material(b), source)
		b.chunkParts[ck] = nil
		table.insert(b.deadChunks, p) -- keep resolvable (stale client aims), cleared when the block goes
		p:Destroy()
	end
	revealAround(ck)
	if b.left <= 0 then
		Demolition.Break(b.model :: Model, source, actor)
	else
		publish()
	end
end

-- One hit. amount is the damage budget spent on the exposed chunks nearest hitPos, up to maxChunks.
-- Returns damage applied and the chunk Parts touched (removed ones included).
function Demolition.Damage(inst: Instance?, amount: number, source: string, hitPos: Vector3?, maxChunks: number?, actor: Player?): (number, { BasePart })
	local ok = Demolition.CanDamage(inst, source)
	if not ok or amount <= 0 then return 0, {} end
	local b = instToBlock[inst :: Instance] :: Block
	if b.chunks == nil then crack(b) end
	local pos = hitPos or (if inst and inst:IsA("BasePart") and inst.Parent then inst.Position else blockCFrame(b).Position)
	local list: { { key: Vector3, part: BasePart, d: number } } = {}
	for ck, p in pairs(b.chunkParts) do table.insert(list, { key = ck, part = p, d = (p.Position - pos).Magnitude }) end
	table.sort(list, function(u, v) return u.d < v.d end)
	local budget = amount
	local hit: { BasePart } = {}
	local model = b.model
	for i = 1, math.min(math.max(1, maxChunks or 1), #list) do
		if budget <= 0 then break end
		local e = list[i]
		local hp = (b.chunks :: { [Vector3]: number })[e.key]
		if hp then
			local dmg = math.min(budget, hp)
			budget -= dmg
			hp -= dmg
			table.insert(hit, e.part)
			if hp <= 0 then
				removeChunk(b, e.key, source, actor)
				if not blocks[b.key] then break end -- block completed
			else
				(b.chunks :: { [Vector3]: number })[e.key] = hp
			end
		end
	end
	if hit[1] and model then Demolition.CellHit:Fire(hit[1], model, pos, 0, source) end
	return amount - math.max(budget, 0), hit
end

-- World centre of the block a holder or chunk belongs to (independent of Model pivots).
function Demolition.CenterOf(inst: Instance?): Vector3?
	local b = inst and instToBlock[inst]
	return b and blockCFrame(b).Position or nil
end

-- Live block holder whose volume contains pos, or nil (exact grid lookup, no physics query).
function Demolition.BlockAt(pos: Vector3): PVInstance?
	local k = (pos - origin) / B
	local b = blocks[Vector3.new(math.round(k.X), math.round(k.Y), math.round(k.Z))]
	return b and (holder(b) :: PVInstance?) or nil
end

function Demolition.Init(model: Model)
	kaiju = model
	B = tonumber(model:GetAttribute("BlockSize")) or B
	C = B / G
	local o = model:GetAttribute("Origin")
	origin = if typeof(o) == "Vector3" then o else Vector3.zero
	hiddenFolder = ServerStorage:FindFirstChild("KaijuHidden") :: Folder?
	blocks, instToBlock, contribution = {}, {}, {}
	totalBlocks = 0
	local function register(inst: Instance)
		if inst:IsA("BasePart") and inst:GetAttribute("BlockMaterial") ~= nil and inst:GetAttribute("Demolishable") ~= false then
			local key = Vector3.new(tonumber(inst:GetAttribute("BX")) or 0, tonumber(inst:GetAttribute("BY")) or 0, tonumber(inst:GetAttribute("BZ")) or 0)
			local b: Block = { key = key, part = inst, model = nil, chunks = nil, chunkParts = {}, left = UNITS, deadPart = nil, deadChunks = {} }
			blocks[key] = b
			instToBlock[inst] = b
			totalBlocks += 1
		end
	end
	for _, child in ipairs(model:GetChildren()) do register(child) end
	if hiddenFolder then for _, child in ipairs(hiddenFolder:GetChildren()) do register(child) end end
	-- The model may have been moved in Studio since generation (the hidden parts in ServerStorage do not
	-- move with it), so derive the grid origin from an exposed part: position = origin + key * B.
	for _, child in ipairs(model:GetChildren()) do
		local b = instToBlock[child]
		if b then
			local derived = child.Position - b.key * B
			if (derived - origin).Magnitude > 0.01 then
				warn(("[Demolition] Kaiju was moved since generation: origin %s -> %s (hidden blocks snap to the grid when exposed)"):format(tostring(origin), tostring(derived)))
				origin = derived
				model:SetAttribute("Origin", origin)
			end
			break
		end
	end
	remainingBlocks = totalBlocks
	totalUnits = totalBlocks * UNITS
	unitsLeft = totalUnits
	RunState:SetAttribute("TotalBlocks", totalBlocks)
	RunState:SetAttribute("State", "Running")
	publish()
	local exposed = #model:GetChildren()
	print(("[Demolition] %d blocks of %d chunks (%.2f-stud chunks, %d-stud blocks): %d exposed, %d hidden server-side"):format(totalBlocks, UNITS, C, B, exposed, totalBlocks - exposed))
	-- Blocks removed by anything that bypassed Damage() are still counted, so the percent cannot drift.
	model.ChildRemoved:Connect(function(child)
		local b = instToBlock[child]
		if b and holder(b) == child and blocks[b.key] then forgetBlock(b, "External") end
	end)
end

function Demolition.GetContribution(): { [string]: number } return table.clone(contribution) end
function Demolition.GetKaiju(): Model? return kaiju end
function Demolition.CellsPerBlock(): number return UNITS end
function Demolition.BlockSize(): number return B end
function Demolition.ChunkSize(): number return C end
-- every live block holder, exposed or hidden (for seeding and balance)
function Demolition.AllBlockHolders(): { Instance }
	local t = {}
	for _, b in pairs(blocks) do local h = holder(b); if h then table.insert(t, h) end end
	return t
end

return Demolition
