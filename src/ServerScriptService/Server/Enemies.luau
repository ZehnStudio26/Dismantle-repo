--!strict
-- Enemies: one Heartbeat loop that ticks every larva, the way Drone ticks every drone. A coroutine
-- per enemy each calling PathfindingService on its own timer is the shape behind every "my NPCs lag
-- as more spawn" thread; one loop keeps the cost flat and in one place. Also owns the server-wide
-- cap (EventConfig.Egg.MaxAlive) so compound events later cannot flood the server.
--
-- Larvae builds bodies and calls Track; Larva owns behaviour. Nothing else needs to know either exists:
-- EventRoll, HUD and Telemetry count enemies from Workspace.Enemies, and Gun / Cutter hit anything
-- tagged "Enemy".
--
-- Hits (2026-10-01): Gun and Chainsaw land every enemy hit through here, so the reaction and the
-- rewards live in one place and neither weapon needs Demolition (D9):
--   Strike(hum, damage, attacker)   larva: Larva.hit (knockback, brain pause, last attacker for
--                                   KillReward) then TakeDamage
--   EggOf(inst) / HitEgg(...)       an incubating egg (tag "Egg") has EggHP; at 0 it pops, never
--                                   hatches, and the attacker gets EggReward + coin / popup FX.
--                                   The egg's Incubating (Server.Egg) is cancelled by its Destroy.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local EventConfig = require(ReplicatedStorage.Config.EventConfig)
local Tags = require(ReplicatedStorage.Config.Tags)
local Larva = require(script.Parent.Larva)
local FX = require(script.Parent.FX)

local Enemies = {}
local live: { [Model]: Larva.Larva } = {}

function Enemies.Alive(): number
	local n = 0
	for _, larva in pairs(live) do
		if larva:alive() then n += 1 end
	end
	return n
end

function Enemies.CanSpawn(): boolean
	return Enemies.Alive() < EventConfig.Egg.MaxAlive
end

function Enemies.Track(larva: Larva.Larva)
	live[larva.model] = larva
	-- Destroying covers both the corpse timer and Cleared's ClearAllChildren
	larva.model.Destroying:Once(function() live[larva.model] = nil end)
end

function Enemies.Strike(hum: Humanoid, damage: number, attacker: Player)
	local larva = live[hum.Parent :: Model]
	if larva then larva:hit(attacker) end -- before the damage, so a killing blow already has its killer
	hum:TakeDamage(damage)
end

-- the incubating egg `inst` belongs to, or nil (hatched / popped eggs are gone or marked Burst)
function Enemies.EggOf(inst: Instance?): Model?
	local model = if inst and inst:IsA("Model") then inst else inst and inst:FindFirstAncestorWhichIsA("Model")
	if not model or not CollectionService:HasTag(model, Tags.Egg) or not model:IsDescendantOf(workspace) then return nil end
	if model:GetAttribute("Burst") == true then return nil end
	return model
end

function Enemies.HitEgg(egg: Model, damage: number, attacker: Player)
	local hp = (tonumber(egg:GetAttribute("EggHP")) or EventConfig.Egg.EggHP) - damage
	egg:SetAttribute("EggHP", math.max(0, hp))
	if hp > 0 then return end
	local pos = egg:GetPivot().Position
	egg:SetAttribute("Burst", true) -- the client's goo burst; replicates before the Destroy
	egg:Destroy()
	local reward = EventConfig.Egg.EggReward
	attacker:SetAttribute("Cash", (tonumber(attacker:GetAttribute("Cash")) or 0) + reward)
	FX.coins(attacker, reward, pos)
	FX.popup(attacker, "+" .. reward, pos)
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for model, larva in pairs(live) do
		if not model.Parent then
			live[model] = nil -- removed some other way; never tick a parentless body
		else
			larva:tick(now)
		end
	end
end)

return Enemies
