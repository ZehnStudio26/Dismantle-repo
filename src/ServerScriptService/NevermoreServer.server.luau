--!strict
-- Nevermore (Quenty's NevermoreEngine) bootstrap, server side. Installed 2026-09-28 (approved by Bee),
-- setup only: nothing in the game uses it yet. Packages live in ServerScriptService.Nevermore
-- (node_modules/@quenty/...), pushed from Dismantle-repo/nevermore through MCP, not Rojo (see
-- nevermore/serve-packages.js). bootstrapGame links the packages and replicates the shared / client
-- ones to ReplicatedStorage.Nevermore (in Studio it simply moves the folder there).
-- To use it later: put a service module under ServerScriptService.Nevermore (or add its package), then
--   serviceBag:GetService(require("MyService"))  before Init below.
local ServerScriptService = game:GetService("ServerScriptService")

local root = ServerScriptService:WaitForChild("Nevermore")
local loaderUtils = root:FindFirstChild("LoaderUtils", true)
assert(loaderUtils and loaderUtils.Parent, "[Nevermore] loader package missing from ServerScriptService.Nevermore")
local require = require(loaderUtils.Parent :: ModuleScript).bootstrapGame(root)

local serviceBag = require("ServiceBag").new()
serviceBag:Init()
serviceBag:Start()

print("[Nevermore] server loader ready: ServiceBag started, packages under " .. root:GetFullName())
