--!strict
-- Gun (A6 / TOOL-02): D8 unlimited ammo, D9 damages enemies only and never touches the kaiju.
-- D9 holds by construction: this module never requires Demolition. It only ever calls
-- Humanoid:TakeDamage on models tagged "Enemy" (through Enemies.Strike: knockback, kill reward) and
-- lowers EggHP on incubating eggs (Enemies.HitEgg). Enemies does not require Demolition either.
-- The client fires from the muzzle (StarterPack.Handgun.Client, which auto-locks the nearest larva or egg); the server checks the shot, applies the
-- damage and relays the shot to the other clients for their muzzle flash and tracer.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UpgradeConfig = require(ReplicatedStorage.Config.UpgradeConfig)
local Tags = require(ReplicatedStorage.Config.Tags)
local Enemies = require(script.Parent.Enemies)
-- damage, fire rate and range are the player's Gun tiers (U-4); tier 1 is the sheet's baseline
local function stat(player: Player, name: string): number return UpgradeConfig.Value(player, "Gun", name) end
local GunFire: RemoteEvent = ReplicatedStorage.Remotes.GunFire
local TOOL = "Handgun" -- StarterPack.Handgun (replaced the old Gun tool 2026-09-29)

local lastShot: { [Player]: number } = {}

local function root(player: Player): BasePart?
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function holdingGun(player: Player): boolean
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and char:FindFirstChild(TOOL) ~= nil
end

-- where the shot leaves: the gun's muzzle, or the root when the tool has none
local function muzzle(player: Player): Vector3?
	local char = player.Character
	local gun = char and char:FindFirstChild(TOOL)
	local h = gun and gun:FindFirstChild("Handle")
	local a = h and h:FindFirstChild("MuzzleFX")
	if a and a:IsA("Attachment") then return a.WorldPosition end
	local r = root(player)
	return r and r.Position
end

local function enemyHumanoid(target: Instance?): Humanoid?
	if not target then return nil end
	local model = target:FindFirstAncestorWhichIsA("Model")
	if not model or not CollectionService:HasTag(model, Tags.Enemy) then return nil end
	if Players:GetPlayerFromCharacter(model) then return nil end
	return model:FindFirstChildOfClass("Humanoid")
end

GunFire.OnServerEvent:Connect(function(player: Player, target: Instance?, hitPos: Vector3?)
	if not holdingGun(player) or typeof(hitPos) ~= "Vector3" then return end
	if target ~= nil and typeof(target) ~= "Instance" then return end
	local now = os.clock()
	if now - (lastShot[player] or 0) < 1 / stat(player, "FireRate") * 0.9 then return end -- 10% slack for ping jitter
	lastShot[player] = now

	local from = muzzle(player)
	if not from or (hitPos - from).Magnitude > stat(player, "Range") + 5 then
		return
	end
	local hum = enemyHumanoid(target)
	local egg = if hum then nil else Enemies.EggOf(target)
	local hitEnemy = false
	if (hum and hum.Health > 0) or egg then
		-- Reject spoofed targets: a raycast always reports a part, and it must be near the reported hit point.
		local part = target :: BasePart
		if not part:IsA("BasePart") or (part.Position - hitPos).Magnitude > part.Size.Magnitude + 5 then return end
		local dmg = stat(player, "Damage")
		if egg then
			Enemies.HitEgg(egg, dmg, player)
		else
			Enemies.Strike(hum :: Humanoid, dmg, player)
			hitEnemy = true -- red sparks for the other clients, matching the shooter's own isEnemy
		end
	end
	-- everyone else sees the flash and the tracer; the shooter already played them
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then GunFire:FireClient(other, player, from, hitPos, target ~= nil, hitEnemy) end
	end
end)

Players.PlayerRemoving:Connect(function(player) lastShot[player] = nil end)

return { EnemyHumanoid = enemyHumanoid }
