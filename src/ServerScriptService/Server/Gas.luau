--!strict
-- Gas event (A8 / EVT-03..05, E-2): a gas outcome bursts a cloud in that cell.
--
-- The cloud is a BOX the size of the visible collider, and the damage volume IS that box: each tick
-- the live characters are tested against the part with GetPartBoundsInBox, so what a player sees is
-- exactly what hurts them. (Until 2026-09-25 it was a radius-60 sphere tested by magnitude: 120 studs
-- across, most of a working face, and the sheet's "4x4 area" cannot be expressed as a radius.)
--
-- Damage ticks are phase-locked to the CLOUD (2026-10-01), not to each player: the first lands
-- Cfg.GraceSeconds after spawn (the cloud puffs in and warns, nobody is hurt yet), then one every
-- Cfg.DamageInterval until it expires. Everyone unmasked inside at a tick takes Cfg.Damage; at 8 s,
-- 0.5 and 2.5 that is ticks at 0.5 / 3.0 / 5.5 s, the same 30 HP a full exposure cost before. Fixed
-- times are what let a player time the mask. The part publishes the schedule in server time
-- (workspace:GetServerTimeNow) for GasFX and the GasOverlay tick ring:
--   StartedAt, DamageFrom (= StartedAt + grace), TickPeriod, EndsAt (pulled to now when it dissipates)
-- Player attributes owned here:
--   InGas       inside any live cloud (overlay, HUD, K-metrics)
--   GasHits     damage ticks taken in the current exposure      } reset to 0 when the player leaves
--   GasBlocked  ticks the mask blocked in the current exposure  } the gas; GasOverlay flashes on them
-- "Masked" is the player attribute owned by Server.Mask; this module never inspects the character.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventConfig = require(ReplicatedStorage.Config.EventConfig)
local Demolition = require(script.Parent.Demolition)
local EventRoll = require(script.Parent.EventRoll)

local Cfg = EventConfig.Gas
local folder = workspace:WaitForChild("Hazards")
local template = game:GetService("ServerStorage"):WaitForChild("Templates"):WaitForChild("GasCloud") :: BasePart

local function now(): number
	return workspace:GetServerTimeNow()
end

-- Let the last particles die before the part goes, instead of the cloud popping out of existence.
local function dissipate(part: BasePart)
	part:SetAttribute("EndsAt", now()) -- clients drop the ring and the footprint at once
	local longest = 0
	for _, pe in ipairs(part:GetChildren()) do
		if pe:IsA("ParticleEmitter") then
			pe.Enabled = false
			longest = math.max(longest, pe.Lifetime.Max)
		end
	end
	part.CanQuery = false
	task.delay(longest, function() part:Destroy() end)
end

type Zone = { part: Part, until_: number, nextTick: number }
local zones: { Zone } = {}
local lastHit: { [Player]: number } = {} -- per player, so two overlapping clouds do not double the rate

local function masked(player: Player): boolean
	return player:GetAttribute("Masked") == true
end

-- duration defaults to Cfg.Duration; Server.TestArea passes a longer one for its standing cloud.
local function spawnCloud(centre: Vector3, duration: number?): Part
	local seconds = duration or Cfg.Duration
	-- The cloud is the authored VFX part (ServerStorage.Templates.GasCloud, from Workspace.TestArea
	-- "Gas vfx"): box-shaped emitters fill the part, so sizing it to Cfg.Size makes the visual and
	-- the damage volume one and the same. The host box itself is hidden; the particles are the look.
	-- The asset was authored as a thin 17x25x1.7 sheet, so rates scale by its FACE area (X*Y), not
	-- volume: by volume a 32-stud cube would ask for ~50,000 particles/s. MaxEmitterRate caps it.
	-- GasFX scales these rates down again per client on low-end devices.
	local part = template:Clone()
	part.Size = Cfg.Size
	part.Position = centre
	part.Transparency = 1
	part.CanQuery = false -- the damage test queries characters against this box, never the box itself
	local authored = part:GetAttribute("AuthoredSize")
	if typeof(authored) == "Vector3" and authored.X * authored.Y > 0 then
		local scale = (Cfg.Size.X * Cfg.Size.Y) / (authored.X * authored.Y)
		for _, pe in ipairs(part:GetChildren()) do
			if pe:IsA("ParticleEmitter") then pe.Rate = math.min(pe.Rate * scale, Cfg.MaxEmitterRate or 600) end
		end
	end
	local t = now()
	local firstTick = t + (Cfg.GraceSeconds or 0)
	part:SetAttribute("StartedAt", t)
	part:SetAttribute("DamageFrom", firstTick)
	part:SetAttribute("TickPeriod", Cfg.DamageInterval)
	part:SetAttribute("EndsAt", t + seconds)
	part.Parent = folder
	table.insert(zones, { part = part, until_ = t + seconds, nextTick = firstTick })
	return part
end

-- Rolled outcome from a seeded "Event" block (EVT-02) ...
EventRoll.Triggered.Event:Connect(function(kind: string, cf: CFrame)
	if kind == "Gas" then spawnCloud(cf.Position) end
end)
-- ... or a hand-placed block tagged "Organ" with a fixed outcome.
Demolition.BlockBroken.Event:Connect(function(cf: CFrame, size: Vector3, material: string?, source: string)
	if material == "Organ" then spawnCloud(cf.Position) end
end)

local function setCount(player: Player, name: string, n: number)
	if player:GetAttribute(name) ~= n then player:SetAttribute(name, n) end
end
local function bump(player: Player, name: string)
	setCount(player, name, ((player:GetAttribute(name) :: number?) or 0) + 1)
end

-- one due tick for a player inside that cloud: blocked by the mask, or damage
local function tick(player: Player, hum: Humanoid, t: number)
	if masked(player) then
		bump(player, "GasBlocked")
	elseif t - (lastHit[player] or -math.huge) >= Cfg.DamageInterval - Cfg.TickSeconds then
		lastHit[player] = t
		local before = hum.Health
		hum:TakeDamage(Cfg.Damage)
		if hum.Health < before then bump(player, "GasHits") end -- a ForceField (run end) takes it silently
	end
end

-- One overlap query per cloud, filtered to the live characters, so the cost is clouds x characters
-- and never touches the kaiju's thousands of parts.
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include

-- one tick loop for every cloud: expiry, then due ticks, then the InGas flag per player
task.spawn(function()
	while true do
		task.wait(Cfg.TickSeconds)
		local t = now()
		for i = #zones, 1, -1 do
			if t >= zones[i].until_ or zones[i].part.Parent == nil then -- expired, or removed by something else
				dissipate(zones[i].part) -- out of `zones` now, so it stops hurting at once; the particles fade after
				table.remove(zones, i)
			end
		end
		local inside: { [Player]: boolean } = {}
		local ticked: { [Player]: boolean } = {} -- one tick per player per pass, however many clouds are due
		local chars: { Instance } = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then table.insert(chars, p.Character) end
		end
		overlap.FilterDescendantsInstances = chars
		for _, z in ipairs(zones) do
			local due = t >= z.nextTick
			if due then z.nextTick += Cfg.DamageInterval end
			if #chars > 0 then
				for _, hit in ipairs(workspace:GetPartBoundsInBox(z.part.CFrame, z.part.Size, overlap)) do
					local model = hit:FindFirstAncestorOfClass("Model")
					local p = model and Players:GetPlayerFromCharacter(model)
					local hum = model and model:FindFirstChildOfClass("Humanoid")
					if p and hum and hum.Health > 0 then
						inside[p] = true
						if due and not ticked[p] then
							ticked[p] = true
							tick(p, hum, t)
						end
					end
				end
			end
		end
		for _, player in ipairs(Players:GetPlayers()) do
			local isIn = inside[player] == true
			if (player:GetAttribute("InGas") == true) ~= isIn then
				player:SetAttribute("InGas", isIn)
			end
			if not isIn then -- the exposure is over
				setCount(player, "GasHits", 0)
				setCount(player, "GasBlocked", 0)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player) lastHit[player] = nil end)

Demolition.Cleared.Event:Connect(function()
	for _, z in ipairs(zones) do dissipate(z.part) end
	table.clear(zones)
end)

return { SpawnCloud = spawnCloud }
