--!strict
-- LaserCutter client: while the tool is held, outline the logical kaiju block under the cursor
-- (the reference title's white target outline), or the enemy under it (the cutter is "for both").
-- While the mouse button is down, report the part under the cursor and the hit position; the
-- server validates and applies discrete hits.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ToolConfig = require(ReplicatedStorage.Config.ToolConfig)
local FXConfig = require(ReplicatedStorage.Config.FXConfig)
local CutterAim: RemoteEvent = ReplicatedStorage.Remotes.CutterAim
local BlockFX: RemoteEvent = ReplicatedStorage.Remotes.BlockFX

local tool = script.Parent :: Tool
local camera = workspace.CurrentCamera
local interval = 1 / ToolConfig.Cutter.ReportHz

local equipped = false
local firing = false
local lastSent = 0
local lastSentBlock: Instance? = nil -- the block our last report pointed at, for the hit flash

local outline = Instance.new("Highlight")
outline.Name = "AimOutline"
outline.FillTransparency = 1
outline.OutlineColor = Color3.new(1, 1, 1)
outline.OutlineTransparency = 0
outline.DepthMode = Enum.HighlightDepthMode.Occluded
outline.Enabled = false
outline.Parent = tool

-- the logical thing a part belongs to: an enemy Model, a cracked block Model, or the intact block Part
local function holderOf(part: BasePart): Instance
	local model = part:FindFirstAncestorWhichIsA("Model")
	if model and CollectionService:HasTag(model, "Enemy") then return model end
	local kaiju = workspace:FindFirstChild("Kaiju")
	return if part.Parent and part.Parent.Parent == kaiju then part.Parent :: Instance else part
end

-- returns the part under the cursor, the hit position, and its holder
local function aimed(): (BasePart?, Vector3?, Instance?)
	local kaiju = workspace:FindFirstChild("Kaiju")
	if not kaiju then return nil, nil, nil end
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { kaiju, workspace:FindFirstChild("Enemies") }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	if not hit or not hit.Instance:IsA("BasePart") then return nil, nil, nil end
	return hit.Instance, hit.Position, holderOf(hit.Instance)
end

local function send(part: BasePart?, pos: Vector3?)
	CutterAim:FireServer(part, pos)
	lastSent = os.clock()
	lastSentBlock = if part then holderOf(part) else nil
end

local function stop()
	firing = false
	outline.Enabled = false
	outline.Adornee = nil
	send(nil, nil)
end

tool.Equipped:Connect(function() equipped = true end)
tool.Unequipped:Connect(function() equipped = false; stop() end)
tool.Activated:Connect(function() firing = true end)
tool.Deactivated:Connect(function() firing = false; send(nil, nil) end)

-- hit flash: the outline fills briefly when one of our hits lands on the aimed block
local flashUntil = 0
BlockFX.OnClientEvent:Connect(function(kind: string, _a, block: any)
	if kind == "Hit" and firing and (block == lastSentBlock or block == outline.Adornee) then
		flashUntil = os.clock() + FXConfig.Flash.Seconds
		_G.CutterFlashes = (_G.CutterFlashes or 0) + 1 -- exposed for tests
	end
end)

RunService.RenderStepped:Connect(function()
	if not equipped then return end
	outline.FillTransparency = if os.clock() < flashUntil then FXConfig.Flash.Fill else 1
	local part, pos, block = aimed()
	outline.Adornee = block
	outline.Enabled = block ~= nil
	if firing and os.clock() - lastSent >= interval then send(part, pos) end
end)
