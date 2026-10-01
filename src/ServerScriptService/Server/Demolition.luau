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
-- So is the layer rule (RunConfig.OneLayerAtATime): drones cut only the highest layer with blocks left;
-- the player cuts anywhere (Ayesh 2026-10-01). RunState.ActiveLayer / ActiveLayerLeft publish it for clients.

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
Demolition.CellHit = Instance.new("BindableEvent")     -- (firstChunk, blockModel, hitPos, healthFraction, source, hp, maxHp) once per hit that landed
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
	adopted: boolean?,     -- placed by Demolition.Adopt (Studio sandbox): outside the layer rule
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
-- one layer at a time: live block count per layer (grid BY), adopted blocks excluded
local layerCount: { [number]: number } = {}
local activeLayer = -math.huge
local function topLayer(): number
	local top = -math.huge
	for y, n in pairs(layerCount) do if n > 0 and y > top then top = y end end
	return top
end
local function publishLayer()
	local has = activeLayer > -math.huge
	RunState:SetAttribute("ActiveLayer", if has then activeLayer else nil)
	RunState:SetAttribute("ActiveLayerLeft", if has then (layerCount[activeLayer] or 0) else 0)
end

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
		b.part.Size = Vector3.one * B -- nor when it is scaled
		b.part.CFrame = blockCFrame(b) -- hidden parts do not follow the model when it is moved in Studio
		b.part:SetAttribute("RevealedAt", workspace:GetServerTimeNow()) -- BlockFX pops it in
		b.part.Parent = kaiju
	end
end

local function createChunkPart(b: Block, ck: Vector3, revealed: boolean?)
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
	if revealed then p:SetAttribute("RevealedAt", workspace:GetServerTimeNow()) end -- BlockFX pops it in
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
	for _, a in ipairs({ "BlockMaterial", "Region", "BlockId", "Demolishable", "Color", "BX", "BY", "BZ", "Adopted" }) do m:SetAttribute(a, part:GetAttribute(a)) end
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
			elseif nb.chunks[nk] ~= nil and not nb.chunkParts[nk] then createChunkPart(nb, nk, true) end
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
	if RunConfig.OneLayerAtATime and not b.adopted and source == "Drone" and b.key.Y < activeLayer then
		return false, ("layer: clear layer %d first"):format(activeLayer)
	end
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
	if not b.adopted then
		layerCount[b.key.Y] = (layerCount[b.key.Y] or 1) - 1
		if b.key.Y == activeLayer and layerCount[b.key.Y] <= 0 then
			activeLayer = topLayer()
		end
		publishLayer()
	end
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
	-- The hit spends its damage chunk by chunk, nearest first, up to maxChunks. Removing a chunk can
	-- reveal the one behind it, and the leftover damage carries on into those too (KJ-25: before, a hit
	-- stopped at the chunks showing when it landed, so a block open only on top took three hits whatever
	-- the cap said).
	local budget = amount
	local cap = math.max(1, maxChunks or 1)
	local hit: { BasePart } = {}
	local model = b.model
	while budget > 0 and #hit < cap and blocks[b.key] do
		local list: { { key: Vector3, part: BasePart, d: number } } = {}
		for ck, p in pairs(b.chunkParts) do
			if (b.chunks :: { [Vector3]: number })[ck] then table.insert(list, { key = ck, part = p, d = (p.Position - pos).Magnitude }) end
		end
		if #list == 0 then break end
		table.sort(list, function(u, v) return u.d < v.d end)
		for _, e in ipairs(list) do
			if budget <= 0 or #hit >= cap or not blocks[b.key] then break end
			local hp = (b.chunks :: { [Vector3]: number })[e.key]
			if hp then
				local dmg = math.min(budget, hp)
				budget -= dmg
				hp -= dmg
				table.insert(hit, e.part)
				if hp <= 0 then
					removeChunk(b, e.key, source, actor)
				else
					(b.chunks :: { [Vector3]: number })[e.key] = hp
				end
			end
		end
	end
	if hit[1] and model then
		-- block health for the health bar: the chunks left, out of the block's full HP
		local maxHp = chunkMaxHP(b) * UNITS
		local hp = 0
		if blocks[b.key] and b.chunks then for _, h in pairs(b.chunks) do hp += h end end
		Demolition.CellHit:Fire(hit[1], model, pos, if maxHp > 0 then hp / maxHp else 0, source, hp, maxHp)
	end
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
	layerCount = {}
	local function register(inst: Instance)
		if inst:IsA("BasePart") and inst:GetAttribute("BlockMaterial") ~= nil and inst:GetAttribute("Demolishable") ~= false then
			local key = Vector3.new(tonumber(inst:GetAttribute("BX")) or 0, tonumber(inst:GetAttribute("BY")) or 0, tonumber(inst:GetAttribute("BZ")) or 0)
			local b: Block = { key = key, part = inst, model = nil, chunks = nil, chunkParts = {}, left = UNITS, deadPart = nil, deadChunks = {} }
			blocks[key] = b
			instToBlock[inst] = b
			totalBlocks += 1
			layerCount[key.Y] = (layerCount[key.Y] or 0) + 1
		end
	end
	for _, child in ipairs(model:GetChildren()) do register(child) end
	if hiddenFolder then for _, child in ipairs(hiddenFolder:GetChildren()) do register(child) end end
	-- The model may have been scaled or moved in Studio since generation (the hidden parts in ServerStorage
	-- do not follow it; 2026-09-29 it was scaled to 0.9). Take the block size from an exposed part, then
	-- derive the origin from it: position = origin + key * B. Hidden blocks take both when revealed.
	for _, child in ipairs(model:GetChildren()) do
		local b = instToBlock[child]
		if b and child:IsA("BasePart") and math.abs(child.Size.X - B) > 0.01 then
			warn(("[Demolition] Kaiju was scaled since generation: blocks %.2f -> %.2f studs (hidden blocks are resized when exposed)"):format(B, child.Size.X))
			B = child.Size.X
			C = B / G
			model:SetAttribute("BlockSize", B)
			break
		elseif b then
			break
		end
	end
	for _, child in ipairs(model:GetChildren()) do
		local b = instToBlock[child]
		if b then
			local derived = child.Position - b.key * B
			if (derived - origin).Magnitude > 0.05 then -- above float drift; a real move is studs
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
	activeLayer = topLayer()
	publishLayer()
	-- Blocks removed by anything that bypassed Damage() are still counted, so the percent cannot drift.
	model.ChildRemoved:Connect(function(child)
		local b = instToBlock[child]
		if b and holder(b) == child and blocks[b.key] then forgetBlock(b, "External") end
	end)
end

-- Adopt a block Part authored outside the kaiju (a test rig, a hand-placed set piece) into the grid
-- at run time: snap it to the nearest cell, key it, move it under the kaiju and count it. The block
-- then behaves exactly like a generated one (cracks, chunks, D7, BlockBroken). Needs BlockMaterial.
function Demolition.Adopt(part: BasePart): boolean
	if not kaiju or instToBlock[part] or part:GetAttribute("BlockMaterial") == nil then return false end
	local k = (part.Position - origin) / B
	local key = Vector3.new(math.round(k.X), math.round(k.Y), math.round(k.Z))
	if blocks[key] then return false end -- the cell is already a block (TestArea counts these)
	part.Size = Vector3.new(B, B, B)
	part.CFrame = CFrame.new(origin + key * B)
	part.Anchored = true
	part:SetAttribute("BX", key.X); part:SetAttribute("BY", key.Y); part:SetAttribute("BZ", key.Z)
	part:SetAttribute("Demolishable", true)
	part:SetAttribute("Adopted", true) -- sandbox block: outside the layer rule (clients read this too)
	if part:GetAttribute("Color") == nil then part:SetAttribute("Color", part.Color) end -- chunks tint from this
	part.Parent = kaiju
	local b: Block = { key = key, part = part, model = nil, chunks = nil, chunkParts = {}, left = UNITS, deadPart = nil, deadChunks = {}, adopted = true }
	blocks[key] = b
	instToBlock[part] = b
	totalBlocks += 1
	remainingBlocks += 1
	totalUnits += UNITS
	unitsLeft += UNITS
	RunState:SetAttribute("TotalBlocks", totalBlocks)
	publish()
	return true
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
