-- Restore every script in kaiju.rbxl from the src/ mirror served by `node src/serve.js`.
-- Run in the Studio command bar after Setup.luau. Idempotent. Then SAVE the place.
local HttpService = game:GetService("HttpService")
local CHS = game:GetService("ChangeHistoryService")
local BASE = "http://127.0.0.1:8123"

HttpService.HttpEnabled = true
CHS:SetWaypoint("Before restore from src")

local ok, manifest = pcall(function() return HttpService:JSONDecode(HttpService:GetAsync(BASE .. "/manifest")) end)
assert(ok, "src server not reachable at " .. BASE .. ": " .. tostring(manifest) .. ". Run: node src/serve.js")

local function resolve(pathStr: string): Instance?
	local inst: Instance = game
	for _, seg in ipairs(string.split(pathStr, ".")) do
		if seg == "game" then continue end
		local child = inst:FindFirstChild(seg)
		if not child then
			if inst == game then child = game:GetService(seg) else return nil end
		end
		inst = child
	end
	return inst
end

local written, missing = 0, {}
for _, entry in ipairs(manifest) do
	local inst = resolve(entry.instancePath)
	if not inst then
		-- create the container if Setup did not (new module added later)
		local parentPath = entry.instancePath:match("^(.*)%.[^.]+$")
		local parent = parentPath and resolve(parentPath)
		if parent then
			inst = Instance.new(entry.className)
			inst.Name = entry.instancePath:match("[^.]+$")
			inst.Parent = parent
		end
	end
	if inst and inst:IsA("LuaSourceContainer") then
		(inst :: any).Source = HttpService:GetAsync(BASE .. "/" .. entry.file)
		written += 1
	else
		table.insert(missing, entry.instancePath)
	end
end
CHS:SetWaypoint("Restored from src")
print(("[Restore] wrote %d scripts%s"):format(written, if #missing > 0 then ". Missing containers: " .. table.concat(missing, ", ") else ""))
