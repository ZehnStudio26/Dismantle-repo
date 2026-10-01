--!strict
-- Nevermore bootstrap, client side (setup only, 2026-09-28; see ServerScriptService.NevermoreServer).
-- The server's bootstrapGame puts the shared / client packages in ReplicatedStorage.Nevermore. The
-- package root has no loader link of its own (it holds no game modules yet), so the loader is found by
-- its unique LoaderUtils child instead.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = ReplicatedStorage:WaitForChild("Nevermore")
local loaderUtils = root:FindFirstChild("LoaderUtils", true)
local waited = 0
while not loaderUtils and waited < 30 do -- the folder can arrive a moment before all its modules
	waited += task.wait()
	loaderUtils = root:FindFirstChild("LoaderUtils", true)
end
assert(loaderUtils and loaderUtils.Parent, "[Nevermore] loader never replicated to ReplicatedStorage.Nevermore")
local require = require(loaderUtils.Parent :: ModuleScript).bootstrapGame(root)

local serviceBag = require("ServiceBag").new()
serviceBag:Init()
serviceBag:Start()

