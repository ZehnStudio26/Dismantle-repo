--!strict
-- PickupSpin: pickups in Workspace.Pickups with the Spin attribute (the E-4 health cross) turn slowly and
-- bob on this client so they catch the eye. Visual only: the server keeps their real position and does
-- the pickup check there.
local RunService = game:GetService("RunService")

local folder = workspace:WaitForChild("Pickups")
local SPIN, BOB, BOB_HZ = math.rad(90), 0.6, 0.8

type Spinner = { home: CFrame, phase: number }
local spinners: { [Model]: Spinner } = {}

local function watch(m: Instance)
	if m:IsA("Model") and m:GetAttribute("Spin") == true and not spinners[m] then
		spinners[m] = { home = m:GetPivot(), phase = math.random() * math.pi * 2 }
	end
end
folder.ChildAdded:Connect(function(c) task.defer(watch, c) end)
for _, c in ipairs(folder:GetChildren()) do watch(c) end

local t = 0
RunService.RenderStepped:Connect(function(dt)
	t += dt
	for m, s in pairs(spinners) do
		if not m.Parent then
			spinners[m] = nil
		else
			local y = math.sin((t + s.phase) * BOB_HZ * 2 * math.pi) * BOB
			m:PivotTo(s.home * CFrame.new(0, y, 0) * CFrame.Angles(0, t * SPIN, 0))
		end
	end
end)
