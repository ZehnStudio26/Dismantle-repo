--!strict
-- Scaffold (Q19): players cannot jump a 40-stud block, so every broken block leaves a climbable
-- TrussPart behind, flush against a still-standing neighbour. Climb the truss, step onto the
-- neighbour's top, cut the next layer from there. Work-site scaffolding, no model needed.
-- ponytail: one truss per broken cell, never removed until the run clears. If truss count or
-- misaligned stacks become a problem, place trusses only on faces with an open top above.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Demolition = require(script.Parent.Demolition)

local folder = workspace:WaitForChild("Scaffolds")
local SIDES = { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis }

local placed = 0

Demolition.BlockBroken.Event:Connect(function(cf: CFrame, size: Vector3, material: string?, source: string)
	-- Prefer a side that still has a block, so the truss leads somewhere.
	local dir = SIDES[1]
	for _, d in ipairs(SIDES) do
		if Demolition.BlockAt(cf.Position + d * size.X) then dir = d break end
	end
	local truss = Instance.new("TrussPart")
	truss.Name = "Scaffold"
	truss.Style = Enum.Style.AlternatingSupports
	truss.Size = Vector3.new(2, size.Y, 2)
	truss.CFrame = CFrame.new(cf.Position + dir * (size.X / 2 - 1))
	truss.Anchored = true
	truss.Color = Color3.fromRGB(230, 180, 40)
	truss.Material = Enum.Material.Metal
	truss.Parent = folder
	placed += 1
	print(("[Scaffold] #%d at %s (%s block broken by %s), leaning %s"):format(placed, tostring(truss.Position), tostring(material), source, tostring(dir)))
end)

Demolition.Cleared.Event:Connect(function()
	folder:ClearAllChildren()
	print(("[Scaffold] run cleared, removed %d trusses"):format(placed))
	placed = 0
end)

return true
