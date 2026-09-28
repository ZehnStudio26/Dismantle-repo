--!strict
-- Gun (A6 / TOOL-02): D8 unlimited ammo, D9 damages enemies only and never touches the kaiju.
-- D9 holds by construction: this module never requires Demolition. It only ever calls
-- Humanoid:TakeDamage on models tagged "Enemy".
-- The client fires from the muzzle (StarterPack.Gun.Client); the server checks the shot, applies the
-- damage and relays the shot to the other clients for their muzzle flash and tracer.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UpgradeConfig = require(ReplicatedStorage.Config.UpgradeConfig)
local Tags = require(ReplicatedStorage.Config.Tags)
-- damage, fire rate and range are the player's Gun tiers (U-4); tier 1 is the sheet's baseline
local function stat(player: Player, name: string): number return UpgradeConfig.Value(player, "Gun", name) end
local GunFire: RemoteEvent = ReplicatedStorage.Remotes.GunFire

local lastShot: { [Player]: number } = {}

local function root(player: Player): BasePart?
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function holdingGun(player: Player): boolean
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and char:FindFirstChild("Gun") ~= nil
end

-- where the shot leaves: the gun's muzzle, or the root when the tool has none
local function muzzle(player: Player): Vector3?
	local char = player.Character
	local gun = char and char:FindFirstChild("Gun")
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
		print(("[Gun] %s shot out of range"):format(player.Name))
		return
	end
	local hum = enemyHumanoid(target)
	local hitEnemy = false
	if hum and hum.Health > 0 then
		-- Reject spoofed targets far from the reported hit point.
		local part = target :: BasePart
		if part:IsA("BasePart") and (part.Position - hitPos).Magnitude > part.Size.Magnitude + 5 then return end
		local dmg = stat(player, "Damage")
		hum:TakeDamage(dmg)
		hitEnemy = true
		local name = (hum.Parent :: Instance).Name
		if hum.Health <= 0 then
			print(("[Gun] %s killed %s (%d damage)"):format(player.Name, name, dmg))
		else
			print(("[Gun] %s hit %s for %d, %.0f HP left"):format(player.Name, name, dmg, hum.Health))
		end
	else
		print(("[Gun] %s shot %s: no effect (D9, enemies only)"):format(player.Name, if target then target.Name else "nothing in range"))
	end
	-- everyone else sees the flash and the tracer; the shooter already played them
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then GunFire:FireClient(other, player, from, hitPos, target ~= nil, hitEnemy) end
	end
end)

Players.PlayerRemoving:Connect(function(player) lastShot[player] = nil end)

return { EnemyHumanoid = enemyHumanoid }
