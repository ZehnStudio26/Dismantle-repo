--!strict
-- BlockFX relay: forwards Demolition's hit / cell / block events to every client over one
-- RemoteEvent. Clients own the visuals (pop, dust, shards). Nothing here is authoritative.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Demolition = require(script.Parent.Demolition)
local remote: RemoteEvent = ReplicatedStorage.Remotes.BlockFX

Demolition.CellHit.Event:Connect(function(cell: BasePart, block: BasePart, hitPos: Vector3, frac: number)
	-- the block Part is sent too: the hit cell is often destroyed in the same tick (deferred signals)
	-- and reaches here already parentless, while the block survives until its last cell goes
	remote:FireAllClients("Hit", cell, block, hitPos, frac)
end)
Demolition.CellBroken.Event:Connect(function(cf: CFrame, size: Vector3, color: Color3)
	remote:FireAllClients("Cell", cf, size, color)
end)
Demolition.BlockBroken.Event:Connect(function(cf: CFrame, size: Vector3, _material, _source, actor: Player?, cash: number?)
	remote:FireAllClients("Block", cf, size, cash or 0, actor and actor.Name or nil)
end)

return true
