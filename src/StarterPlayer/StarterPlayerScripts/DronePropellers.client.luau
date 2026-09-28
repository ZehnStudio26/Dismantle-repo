--!strict
-- DronePropellers: spins the support drones' propellers on this client. The Recon Drone mesh has
-- no moving parts; its propellers are a flipbook of four meshes (attribute PropellerMeshes on the body,
-- one frame every PropellerFrameSeconds). The model swapped them on the server, which would replicate
-- twenty property changes a second per drone; here each client swaps its own copy instead.
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")

local folder = workspace:WaitForChild("Drones")

type Spinner = { mesh: SpecialMesh, frames: { string }, seconds: number, frame: number, t: number }
local spinners: { [BasePart]: Spinner } = {}
local preloaded: { [string]: boolean } = {}

local function watch(body: Instance)
	if not body:IsA("BasePart") then return end
	local list = body:GetAttribute("PropellerMeshes")
	local mesh = body:FindFirstChildOfClass("SpecialMesh")
	if typeof(list) ~= "string" or not mesh then return end
	local frames = string.split(list, ",")
	-- load every frame once up front, or the first spins flicker to nothing while a mesh downloads
	local toLoad = {}
	for _, id in ipairs(frames) do
		if not preloaded[id] then
			preloaded[id] = true
			local m = Instance.new("SpecialMesh")
			m.MeshType = Enum.MeshType.FileMesh
			m.MeshId = id
			table.insert(toLoad, m)
		end
	end
	if #toLoad > 0 then task.spawn(function() ContentProvider:PreloadAsync(toLoad) end) end
	spinners[body] = {
		mesh = mesh,
		frames = frames,
		seconds = tonumber(body:GetAttribute("PropellerFrameSeconds")) or 0.05,
		frame = 1,
		t = math.random() * 0.05, -- drones do not spin in lockstep
	}
	body.Destroying:Once(function() spinners[body] = nil end)
end

folder.ChildAdded:Connect(watch)
for _, c in ipairs(folder:GetChildren()) do watch(c) end

RunService.RenderStepped:Connect(function(dt)
	for body, s in pairs(spinners) do
		if not body.Parent then
			spinners[body] = nil
		else
			s.t += dt
			if s.t >= s.seconds then
				s.t %= s.seconds
				s.frame = s.frame % #s.frames + 1
				s.mesh.MeshId = s.frames[s.frame]
			end
		end
	end
end)
