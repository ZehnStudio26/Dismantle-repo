--!strict
-- DeviceLayout (Shayan 2026-09-29): one UI, a layout per device. The UI stays authored in Studio exactly as
-- the desktop layout; phone and tablet layouts are ATTRIBUTES on the same instances, named after the property
-- they replace:  PhoneSize, PhonePosition, PhoneVisible, PhoneAnchorPoint, PhoneAspectRatio, PhoneMinSize,
-- TabletSize ... (any property of that instance). Edit them in the Properties panel.
--   Phone    touch screen whose short side is under PHONE_MAX_SHORT points (phones in landscape: 360-440)
--   Tablet   any other touch screen (iPads, Android tablets: 600-1030)
--   Desktop  mouse / keyboard (a touch laptop with a mouse too): the authored values, untouched
--            (in Studio the emulator's touch flag alone decides, see classify)
-- A Tablet with no Tablet<Prop> keeps the desktop value. The desktop values are remembered the first time a
-- device value is applied and put back when the class changes (rotation, window resize, a keyboard plugged
-- in). Screens cloned later (ResetOnSpawn, the loading screen) get their layout as they arrive.
-- The class is published as the player attribute DeviceClass for other scripts. In Studio, set the workspace
-- attribute ForceDevice = "Phone" / "Tablet" / "Desktop" to preview a layout without the emulator.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local PHONE_MAX_SHORT = 500
local CLASSES = { "Phone", "Tablet" }

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local function classify(): string
	local forced = workspace:GetAttribute("ForceDevice")
	if forced == "Phone" or forced == "Tablet" or forced == "Desktop" then return forced :: string end
	-- live: a touch screen WITH a mouse (a touch laptop) is a desktop. In Studio, TouchEnabled is only true in
	-- the device emulator, which reports a mouse as soon as you drive it with one: the touch flag alone decides.
	local touch = UserInputService.TouchEnabled and (RunService:IsStudio() or not UserInputService.MouseEnabled)
	if not touch then return "Desktop" end
	local vp = workspace.CurrentCamera.ViewportSize
	return if math.min(vp.X, vp.Y) < PHONE_MAX_SHORT then "Phone" else "Tablet"
end

-- desktop values, per instance and property, captured before a device value first replaces them. A plain
-- table (a weak-keyed one can drop an Instance key while the instance is alive, and the next capture would
-- then save a PHONE value as the desktop one); entries go when the element leaves the PlayerGui.
local originals: { [Instance]: { [string]: any } } = {}
local current = "Desktop"

-- the properties this instance has device attributes for
local function deviceProps(inst: Instance): { [string]: boolean }?
	local props: { [string]: boolean } = {}
	local any = false
	for name in pairs(inst:GetAttributes()) do
		for _, c in ipairs(CLASSES) do
			if name:sub(1, #c) == c and #name > #c then
				props[name:sub(#c + 1)] = true
				any = true
			end
		end
	end
	return if any then props else nil
end

local function apply(inst: Instance, class: string)
	local props = deviceProps(inst)
	if not props then return end
	local saved = originals[inst]
	if not saved then
		saved = {}
		originals[inst] = saved
	end
	for prop in pairs(props) do
		local ok, value = pcall(function() return (inst :: any)[prop] end)
		if ok then
			if saved[prop] == nil then saved[prop] = value end
			local want = if class ~= "Desktop" then inst:GetAttribute(class .. prop) else nil
			if want == nil then want = saved[prop] end
			local set, err = pcall(function() (inst :: any)[prop] = want end)
			if not set then warn(("[Device] %s.%s: %s"):format(inst:GetFullName(), prop, tostring(err))) end
		end
	end
end

local function applyAll(class: string)
	local n = 0
	for _, d in ipairs(pg:GetDescendants()) do
		if deviceProps(d) then apply(d, class); n += 1 end
	end
	return n
end

local function refresh(reason: string)
	local class = classify()
	if class == current and reason ~= "start" then return end
	current = class
	player:SetAttribute("DeviceClass", class)
	local n = applyAll(class)
	local vp = workspace.CurrentCamera.ViewportSize
	print(("[Device] %s layout (%dx%d, touch %s, mouse %s, %s): %d element(s) adjusted"):format(class, vp.X, vp.Y,
		tostring(UserInputService.TouchEnabled), tostring(UserInputService.MouseEnabled), reason, n))
end

pg.DescendantAdded:Connect(function(d)
	if current ~= "Desktop" then task.defer(apply, d, current) end
end)
pg.DescendantRemoving:Connect(function(d) originals[d] = nil end)
local function watchCamera()
	local cam = workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() refresh("viewport changed") end) end
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)
watchCamera()
UserInputService.LastInputTypeChanged:Connect(function() refresh("input changed") end)
workspace:GetAttributeChangedSignal("ForceDevice"):Connect(function() refresh("ForceDevice") end)
refresh("start")
-- the input flags can settle a moment after the client starts (seen in the device emulator): look again
task.delay(1, refresh, "settled")
task.delay(4, refresh, "settled")
