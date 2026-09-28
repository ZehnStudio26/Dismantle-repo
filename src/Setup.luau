-- Dismantle place setup. Idempotent: run in the Studio command bar to (re)create every
-- non-script Instance. Script sources live next to this file; paste them afterwards.
local RS, SSS, SS, SP = game.ReplicatedStorage, game.ServerScriptService, game.ServerStorage, game.StarterPack

local function folder(parent, name) local f = parent:FindFirstChild(name) or Instance.new("Folder"); f.Name = name; f.Parent = parent; return f end
local function module(parent, name) local m = parent:FindFirstChild(name) or Instance.new("ModuleScript"); m.Name = name; m.Parent = parent; return m end
local function localscript(parent, name) local m = parent:FindFirstChild(name) or Instance.new("LocalScript"); m.Name = name; m.Parent = parent; return m end
local function remote(name) if not RS.Remotes:FindFirstChild(name) then Instance.new("RemoteEvent", RS.Remotes).Name = name end end

-- ReplicatedStorage
local Config = folder(RS, "Config")
folder(RS, "Remotes")
local RunState = folder(RS, "RunState")
for _, a in ipairs({ "TotalBlocks", "RemainingBlocks", "DemolitionPercent", "EventCount" }) do if RunState:GetAttribute(a) == nil then RunState:SetAttribute(a, 0) end end
if RunState:GetAttribute("State") == nil then RunState:SetAttribute("State", "Idle") end
if RunState:GetAttribute("LastEvent") == nil then RunState:SetAttribute("LastEvent", "") end
for _, n in ipairs({ "RunConfig", "KaijuConfig", "ToolConfig", "EventConfig", "DroneConfig", "FXConfig", "BriefConfig" }) do module(Config, n) end
for _, n in ipairs({ "CutterAim", "GunFire", "BlockFX", "BriefShow", "BriefDone" }) do remote(n) end

-- ServerScriptService
local Server = folder(SSS, "Server")
for _, n in ipairs({ "Demolition", "Cutter", "Gun", "Health", "Scaffold", "EventBlocks", "EventRoll", "Egg", "Gas", "Mask", "Drone", "BlockFX", "Brief", "Telemetry", "Balance" }) do module(Server, n) end
local main = Server:FindFirstChild("Main") or Instance.new("Script"); main.Name = "Main"; main.Parent = Server

-- ServerStorage
local Assets = folder(SS, "Assets")
folder(Assets, "Creatures"); folder(Assets, "Props"); folder(Assets, "VFX")

-- Workspace
local TA = folder(workspace, "TestArea")
folder(TA, "Rigs"); folder(TA, "Models"); folder(TA, "Showcase")
for _, n in ipairs({ "Scaffolds", "Enemies", "Hazards", "Drones", "Pickups" }) do folder(workspace, n) end
if workspace:FindFirstChild("Kaiju") then workspace.Kaiju:SetAttribute("BlockSize", 40) end

-- StarterPlayer
local sps = game.StarterPlayer.StarterPlayerScripts
for _, n in ipairs({ "Inventory", "GasOverlay", "HUD", "BlockFX", "MissionBrief" }) do localscript(sps, n) end
local scs = game.StarterPlayer.StarterCharacterScripts
local h = scs:FindFirstChild("Health") or Instance.new("Script"); h.Name = "Health"; h.Parent = scs
h.Source = "-- Empty on purpose. A Script named Health here replaces Roblox's default one,\n-- which regenerates 1% HP per second. D4: no passive regeneration.\n"

-- Tools (primitive handles; real models to be supplied)
local function tool(name, tip, handleSize, shape, color, material, muzzlePos, grip)
	local t = SP:FindFirstChild(name) or Instance.new("Tool")
	t.Name = name; t.RequiresHandle = true; t.CanBeDropped = false; t.ToolTip = tip; t.Parent = SP
	local handle = t:FindFirstChild("Handle") or Instance.new("Part")
	handle.Name = "Handle"; handle.Size = handleSize; handle.Color = color; handle.Material = material
	if shape then handle.Shape = shape end
	handle.CanCollide = false; handle.Massless = true; handle.Parent = t
	if grip then t.Grip = grip end
	local muzzle = handle:FindFirstChild("Muzzle") or Instance.new("Attachment"); muzzle.Name = "Muzzle"; muzzle.Position = muzzlePos; muzzle.Parent = handle
	localscript(t, "Client")
	return t, handle, muzzle
end
local _, cutterHandle, cutterMuzzle = tool("LaserCutter", "Laser cutter: hold to cut kaiju blocks", Vector3.new(3, 0.6, 0.6), Enum.PartType.Cylinder,
	Color3.fromRGB(60, 60, 70), Enum.Material.Metal, Vector3.new(1.5, 0, 0), CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90)))
local beam = cutterHandle:FindFirstChild("Beam") or Instance.new("Beam"); beam.Name = "Beam"
beam.Attachment0 = cutterMuzzle; beam.Width0 = 0.3; beam.Width1 = 0.6; beam.FaceCamera = true; beam.LightEmission = 1; beam.Enabled = false
beam.Color = ColorSequence.new(Color3.fromRGB(255, 80, 40)); beam.Parent = cutterHandle
tool("Gun", "Gun: click to shoot enemies (never cuts the kaiju)", Vector3.new(0.5, 1, 2), nil, Color3.fromRGB(40, 40, 45), Enum.Material.Metal, Vector3.new(0, 0.3, -1), nil)
tool("GasMask", "Gas mask: hold to block gas damage (narrows your view by tier)", Vector3.new(1.2, 1, 0.6), nil, Color3.fromRGB(70, 80, 60), Enum.Material.SmoothPlastic, Vector3.new(0, 0, 0), nil)

print("[Setup] Dismantle instances ready. Paste the sources from src/ next.")
