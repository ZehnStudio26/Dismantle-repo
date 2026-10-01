--!strict
-- EventFXClient: plays the server's Server.FX calls (Remotes.FX) through ReplicatedStorage.UI.EventFX.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EventFX = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("EventFX"))
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("FX") :: RemoteEvent

remote.OnClientEvent:Connect(function(kind: string, ...)
	if kind == "coins" then
		local amount, from = ...
		EventFX.coins(amount, from)
	elseif kind == "popup" then
		local text, at, color = ...
		EventFX.popup(text, at, { color = color })
	end
end)
