--!strict
-- BlockHealth: the mining pack's rock health bar, for kaiju blocks. Every hit that lands on a block,
-- by any player's chainsaw or any drone, arrives as BlockFX "Hit" with the block's health after the
-- hit (Server.Demolition -> Server.BlockFX). The bar appears over that block: HEALTH and "hp / max",
-- the green fill catching up fast, a red trail draining behind it, a white flash per hit. It stays up
-- ShowSeconds after the last hit (BrokenShowSeconds once the block is gone), then fades.
-- The BillboardGui is authored in Studio (StarterGui.BlockHealth, copied into PlayerGui on join); this
-- script only clones it per block and moves its parts. Numbers: FXConfig.BlockHealth.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage.Config.FXConfig).BlockHealth
local remote: RemoteEvent = ReplicatedStorage.Remotes.BlockFX

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local template = playerGui:WaitForChild("BlockHealth") :: BillboardGui

local kaiju = workspace:WaitForChild("Kaiju")
local BLOCK = tonumber(kaiju:GetAttribute("BlockSize")) or 8
local ORIGIN = if typeof(kaiju:GetAttribute("Origin")) == "Vector3" then kaiju:GetAttribute("Origin") :: Vector3 else Vector3.zero

type Bar = {
	board: BillboardGui,
	anchor: Attachment,
	group: CanvasGroup,
	value: TextLabel,
	fill: Frame,
	trail: Frame,
	flash: Frame,
	untilAt: number,
	shownAt: number,
	fading: boolean,
}
local bars: { [string]: Bar } = {} -- keyed by block grid key, stable while a block cracks into a Model

local function tween(inst: Instance, seconds: number, goal: { [string]: any }, delay: number?)
	TweenService:Create(inst, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay or 0), goal):Play()
end

local function drop(key: string)
	local b = bars[key]
	if not b then return end
	bars[key] = nil
	b.board:Destroy()
	b.anchor:Destroy()
end

local function oldestKey(): string?
	local key, at = nil, math.huge
	for k, b in pairs(bars) do if b.shownAt < at then key, at = k, b.shownAt end end
	return key
end

local function barFor(key: string, centre: Vector3): Bar
	local b = bars[key]
	if b then return b end
	local count = 0
	for _ in pairs(bars) do count += 1 end
	if count >= Cfg.MaxBars then
		local k = oldestKey()
		if k then drop(k) end
	end
	local anchor = Instance.new("Attachment")
	anchor.Name = "BlockHealthAnchor"
	anchor.WorldPosition = centre + Vector3.yAxis * (BLOCK / 2 + Cfg.Gap)
	anchor.Parent = workspace.Terrain
	local board = template:Clone()
	board.Name = "BlockHealth_" .. key
	board.Adornee = anchor
	board.Enabled = true
	board.Parent = playerGui
	local group = board:FindFirstChild("Group") :: CanvasGroup
	local bar = group:FindFirstChild("Bar") :: Frame
	b = {
		board = board,
		anchor = anchor,
		group = group,
		value = group:FindFirstChild("Value") :: TextLabel,
		fill = bar:FindFirstChild("Fill") :: Frame,
		trail = bar:FindFirstChild("Trail") :: Frame,
		flash = bar:FindFirstChild("Flash") :: Frame,
		untilAt = 0,
		shownAt = os.clock(),
		fading = false,
	}
	bars[key] = b
	return b
end

local function onHit(block: Instance?, frac: number, hp: number, maxHp: number)
	if typeof(block) ~= "Instance" then return end
	-- grid key from the block's attributes (still readable when the Model was destroyed by this hit)
	local bx, by, bz = block:GetAttribute("BX"), block:GetAttribute("BY"), block:GetAttribute("BZ")
	if typeof(bx) ~= "number" or typeof(by) ~= "number" or typeof(bz) ~= "number" then return end
	local key = ("%d_%d_%d"):format(bx, by, bz)
	local isNew = bars[key] == nil
	local b = barFor(key, ORIGIN + Vector3.new(bx, by, bz) * BLOCK)
	if isNew then print(("[BlockHealth] bar over %s: %d / %d"):format(block.Name, math.ceil(math.max(hp, 0)), math.ceil(maxHp))) end
	local f = math.clamp(frac, 0, 1)
	b.value.Text = ("%d / %d"):format(math.ceil(math.max(hp, 0)), math.ceil(maxHp))
	tween(b.fill, Cfg.FillSeconds, { Size = UDim2.fromScale(f, 1) })
	tween(b.trail, Cfg.TrailSeconds, { Size = UDim2.fromScale(f, 1) }, Cfg.TrailDelay)
	b.flash.BackgroundTransparency = 0.3
	tween(b.flash, Cfg.FlashSeconds, { BackgroundTransparency = 1 })
	b.fading = false
	tween(b.group, Cfg.FadeSeconds, { GroupTransparency = 0 })
	b.untilAt = os.clock() + (if hp <= 0 then Cfg.BrokenShowSeconds else Cfg.ShowSeconds)
	if hp <= 0 then print(("[BlockHealth] %s broken, bar closes in %.1fs"):format(block.Name, Cfg.BrokenShowSeconds)) end
end

remote.OnClientEvent:Connect(function(kind: string, _cell: any, block: any, _pos: any, frac: any, hp: any, maxHp: any)
	if kind ~= "Hit" or typeof(frac) ~= "number" or typeof(hp) ~= "number" or typeof(maxHp) ~= "number" then return end
	onHit(block, frac, hp, maxHp)
end)

-- fade out bars nobody has hit for ShowSeconds, then drop them
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for key, b in pairs(bars) do
		if not b.fading and now >= b.untilAt then
			b.fading = true
			tween(b.group, Cfg.FadeSeconds, { GroupTransparency = 1 })
		elseif b.fading and now >= b.untilAt + Cfg.FadeSeconds + 0.05 then
			drop(key)
		end
	end
end)
