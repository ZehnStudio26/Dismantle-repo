--!strict
-- FX: server -> client event visuals over Remotes.FX (StarterPlayerScripts.EventFXClient plays them with
-- ReplicatedStorage.UI.EventFX). Visual only: it never changes Cash or anything else, callers do that.
-- Requires nothing from Server, so any server module can require it without a cycle.
--   FX.coins(player: Player, amount: number, from: Vector3)                     -> FireClient("coins", amount, from)
--   FX.popup(target: Player | "all", text: string, at: Vector3, color: Color3?) -> FireClient / FireAllClients("popup", text, at, color)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("FX") :: RemoteEvent

local FX = {}

function FX.coins(player: Player, amount: number, from: Vector3)
	remote:FireClient(player, "coins", amount, from)
end

function FX.popup(target: Player | "all", text: string, at: Vector3, color: Color3?)
	if target == "all" then
		remote:FireAllClients("popup", text, at, color)
	else
		remote:FireClient(target :: Player, "popup", text, at, color)
	end
end

return FX
