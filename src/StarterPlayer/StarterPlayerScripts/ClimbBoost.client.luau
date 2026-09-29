--!strict
-- ClimbBoost (Shayan 2026-09-29): faster climbing on the scaffold ladders. A humanoid climbs at 70%
-- of its WalkSpeed (~11 studs/s at 16), so the ~170-stud tower took ~15 s. While the local character
-- is Climbing, WalkSpeed is held at RunConfig.ClimbWalkSpeed; it is set in PreSimulation, right
-- before physics, so the chainsaw's per-frame walk-speed easing (Heartbeat) cannot undo it. The value
-- from before the climb is put back when the climb ends.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CLIMB = require(ReplicatedStorage.Config.RunConfig).ClimbWalkSpeed or 40
local player = Players.LocalPlayer

local function watch(char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then return end
	local climbing, saved = false, hum.WalkSpeed
	local step: RBXScriptConnection? = nil
	hum.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Climbing and not climbing then
			climbing, saved = true, hum.WalkSpeed
			step = RunService.PreSimulation:Connect(function() hum.WalkSpeed = CLIMB end)
			print(("[Climb] boost on: climbing at walk speed %d"):format(CLIMB))
		elseif new ~= Enum.HumanoidStateType.Climbing and climbing then
			climbing = false
			if step then step:Disconnect(); step = nil end
			hum.WalkSpeed = saved
		end
	end)
end

player.CharacterAdded:Connect(watch)
if player.Character then task.spawn(watch, player.Character) end
