--!strict
-- Spectate (C-2, Shayan 2026-09-29): when you are DOWN (player attribute Down, set by Server.Health when
-- you die during a run) the camera follows a living teammate for the rest of the run. The bar above
-- the hotbar (StarterGui.SpectateGui, authored in Studio in the HUD style) shows "YOU'RE DOWN" and the
-- teammate's name; < and > (or Q / E) switch teammates. It moves on by itself when the one you watch
-- goes down or leaves. When the run ends Server.Health respawns you and the camera comes back.
-- (Adapted from the team's SpectateGui: its manual Spectate toggle is hidden, the list skips downed
-- players and players who left, and the camera follows the teammate's Humanoid.)
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local gui = script.Parent
local container = gui:WaitForChild("Container") :: Frame
local title = gui:WaitForChild("Title") :: TextLabel
local nextButton = container:WaitForChild("NextButton") :: TextButton
local lastButton = container:WaitForChild("LastButton") :: TextButton
local label = container:WaitForChild("PlayerLabel") :: TextLabel

local watching: Player? = nil
local conns: { RBXScriptConnection } = {}

local function aliveHumanoid(p: Player): Humanoid?
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	return if hum and hum.Health > 0 then hum else nil
end

-- living teammates, in a stable order
local function teammates(): { Player }
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and aliveHumanoid(p) then table.insert(list, p) end
	end
	table.sort(list, function(a, b) return a.UserId < b.UserId end)
	return list
end

local function clearConns()
	for _, c in ipairs(conns) do c:Disconnect() end
	table.clear(conns)
end

local watch: (step: number) -> ()
watch = function(step: number)
	clearConns()
	local list = teammates()
	if #list == 0 then
		watching = nil
		label.Text = "NO ONE LEFT"
		return
	end
	local i = if watching then (table.find(list, watching) or 0) else 0
	i = ((i - 1 + step) % #list) + 1
	local p = list[i]
	watching = p
	local hum = aliveHumanoid(p) :: Humanoid
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	workspace.CurrentCamera.CameraSubject = hum
	label.Text = ("SPECTATING %s"):format(p.DisplayName:upper())
	-- the one we watch goes down or leaves: move on
	table.insert(conns, hum.Died:Connect(function() task.defer(watch, 1) end))
	table.insert(conns, p.AncestryChanged:Connect(function() if not p.Parent then task.defer(watch, 1) end end))
	print(("[Spectate] watching %s (%d teammate(s) up)"):format(p.Name, #list))
end

local function setDown(down: boolean)
	container.Visible = down
	title.Visible = down
	if down then
		watching = nil
		watch(1)
	else
		clearConns()
		watching = nil
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then workspace.CurrentCamera.CameraSubject = hum end
	end
end

nextButton.Activated:Connect(function() if player:GetAttribute("Down") == true then watch(1) end end)
lastButton.Activated:Connect(function() if player:GetAttribute("Down") == true then watch(-1) end end)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or player:GetAttribute("Down") ~= true then return end
	if input.KeyCode == Enum.KeyCode.E then watch(1) elseif input.KeyCode == Enum.KeyCode.Q then watch(-1) end
end)
player:GetAttributeChangedSignal("Down"):Connect(function() setDown(player:GetAttribute("Down") == true) end)
setDown(player:GetAttribute("Down") == true)
