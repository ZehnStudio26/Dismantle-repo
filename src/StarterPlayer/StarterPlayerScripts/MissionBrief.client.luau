--!strict
-- MissionBrief client (B13 / MAP-09 / MAP-10, P-5 / KJ-74): the opening cutscene with the brief as its
-- subtitles. P-5: "City overview, kaiju lying down, player. Camera move only".
--   camera   Workspace.CutsceneIntro holds the shots, authored in Studio: parts named 1, 2, 3 ...,
--            each placed and aimed like a camera, with a Time attribute (seconds) and a Focus attribute
--            (how far ahead it looks). The last shot is added here: behind the player, where the normal
--            camera takes over (model attributes EndTime / EndBack / EndUp / Fov). Positions and look
--            targets each follow a Catmull-Rom curve (smooth through every shot, no stops); the
--            flight eases in over its first 2 s and out over its last 2 s and cruises in between, so
--            each shot lands near its Time (the DevForum / CutsceneService approach, no package).
--            The model streams Persistent, and the shots' surroundings are requested before playing.
--   screen   StarterGui.Cutscene, authored in Studio: letterbox bars, the SITE BRIEF tag, a subtitle
--            line (BriefConfig lines, typed out one at a time) and the skip hint.
-- First run: plays through, no skip. Later runs: SPACE (or the hint) skips. The HUD, hotbar and rail
-- step aside and movement is off while it plays; the server hears BriefDone either way.
local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Cfg = require(ReplicatedStorage.Config.BriefConfig)
local BriefShow: RemoteEvent = ReplicatedStorage.Remotes.BriefShow
local BriefDone: RemoteEvent = ReplicatedStorage.Remotes.BriefDone

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")
local gui = pg:WaitForChild("Cutscene") :: ScreenGui
local topBar = gui:WaitForChild("TopBar") :: Frame
local bottomBar = gui:WaitForChild("BottomBar") :: Frame
local title = topBar:WaitForChild("Title") :: TextLabel
local subtitle = bottomBar:WaitForChild("Subtitle") :: TextLabel
local skipHint = bottomBar:WaitForChild("Skip") :: TextButton
title.Text = Cfg.Title

local HIDE = { "HUD", "Hotbar", "Upgrades", "Crosshair", "SpectateGui" } -- step aside while it plays
local BAR_TWEEN = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TYPE_CPS = 45 -- subtitle characters per second
local RENDER = "DismantleCutscene"
local DEFAULT_FOV = 70

-- ---------- camera path ----------
type Key = { t: number, pos: Vector3, focus: Vector3 }

local function rootPart(): BasePart?
	local char = player.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function buildKeys(model: Instance?): { Key }
	local keys: { Key } = {}
	if not model then return keys end
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") and tonumber(p.Name) then
			local focus = tonumber(p:GetAttribute("Focus")) or 100
			table.insert(keys, { t = tonumber(p:GetAttribute("Time")) or 0, pos = p.Position, focus = p.Position + p.CFrame.LookVector * focus })
		end
	end
	table.sort(keys, function(a, b) return a.t < b.t end)
	local root = rootPart()
	if root and #keys > 0 then
		local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		look = if look.Magnitude > 0.05 then look.Unit else -Vector3.zAxis
		local back = tonumber(model:GetAttribute("EndBack")) or 12.5
		local up = tonumber(model:GetAttribute("EndUp")) or 4
		table.insert(keys, {
			t = math.max(tonumber(model:GetAttribute("EndTime")) or keys[#keys].t + 3, keys[#keys].t + 0.5),
			pos = root.Position - look * back + Vector3.yAxis * up,
			focus = root.Position + Vector3.yAxis * 1.5,
		})
	end
	return keys
end

-- uniform Catmull-Rom between p1 and p2
local function catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, s: number): Vector3
	local s2, s3 = s * s, s * s * s
	return 0.5 * ((2 * p1) + (p2 - p0) * s + (2 * p0 - 5 * p1 + 4 * p2 - p3) * s2 + (3 * p1 - p0 - 3 * p2 + p3) * s3)
end

local function sample(keys: { Key }, t: number): CFrame
	local n = #keys
	if n == 1 then return CFrame.lookAt(keys[1].pos, keys[1].focus) end
	local i = 1
	while i < n - 1 and t >= keys[i + 1].t do i += 1 end
	local a, b = keys[i], keys[i + 1]
	local s = math.clamp((t - a.t) / math.max(b.t - a.t, 1e-3), 0, 1)
	local prev = keys[i - 1]
	local nxt = keys[i + 2]
	-- mirror the ends so the curve starts and finishes on the first and last shot
	local function field(k: Key?, name: "pos" | "focus", fallback: Vector3): Vector3
		return if k then k[name] else fallback
	end
	local p0 = field(prev, "pos", a.pos * 2 - b.pos)
	local p3 = field(nxt, "pos", b.pos * 2 - a.pos)
	local f0 = field(prev, "focus", a.focus * 2 - b.focus)
	local f3 = field(nxt, "focus", b.focus * 2 - a.focus)
	local pos = catmull(p0, a.pos, b.pos, p3, s)
	local focus = catmull(f0, a.focus, b.focus, f3, s)
	return CFrame.lookAt(pos, focus)
end

-- ---------- showing ----------
local session = 0 -- bumps per showing so an old run stops touching a new one
local showing = false
local skipAllowed = false
local hidden: { [ScreenGui]: boolean } = {}
local bindSkip: (boolean) -> ()

-- movement off while it plays: the character stands still (this place has no PlayerModule in
-- PlayerScripts to disable, so the humanoid is frozen and given back exactly what it had)
local frozen: { hum: Humanoid, walk: number, jump: number }? = nil
local function controls(on: boolean)
	-- phones / tablets: the thumbstick and jump button would sit on top of the cutscene
	pcall(function() game:GetService("GuiService").TouchControlsEnabled = on end)
	if on then
		if frozen and frozen.hum.Parent then
			frozen.hum.WalkSpeed = frozen.walk
			frozen.hum.JumpHeight = frozen.jump
		end
		frozen = nil
	else
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if not hum or frozen then return end
		frozen = { hum = hum, walk = hum.WalkSpeed, jump = hum.JumpHeight }
		hum.WalkSpeed = 0
		hum.JumpHeight = 0
	end
end

local function hideOthers(hide: boolean)
	if hide then
		for _, name in ipairs(HIDE) do
			local g = pg:FindFirstChild(name)
			if g and g:IsA("ScreenGui") and g.Enabled then hidden[g] = true; g.Enabled = false end
		end
	else
		for g in pairs(hidden) do g.Enabled = true end
		table.clear(hidden)
	end
end

local function bars(inOut: boolean)
	topBar.Position = UDim2.fromScale(0, if inOut then -0.11 else 0)
	bottomBar.Position = UDim2.fromScale(0, if inOut then 1.15 else 1)
	TweenService:Create(topBar, BAR_TWEEN, { Position = UDim2.fromScale(0, if inOut then 0 else -0.11) }):Play()
	TweenService:Create(bottomBar, BAR_TWEEN, { Position = UDim2.fromScale(0, if inOut then 1 else 1.15) }):Play()
end

local function restoreCamera()
	RunService:UnbindFromRenderStep(RENDER)
	local cam = workspace.CurrentCamera
	cam.FieldOfView = DEFAULT_FOV
	cam.CameraType = Enum.CameraType.Custom -- the default camera takes its rotation from the current CFrame
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then cam.CameraSubject = hum end
end

local function finish(skipped: boolean)
	if not showing then return end
	showing = false
	session += 1
	restoreCamera()
	bars(false)
	task.delay(BAR_TWEEN.Time, function() if not showing then gui.Enabled = false end end)
	hideOthers(false)
	controls(true)
	bindSkip(false)
	BriefDone:FireServer(skipped)
end

local function show(runs: number)
	session += 1
	local mine = session
	showing = true
	skipAllowed = runs > 0
	skipHint.Visible = skipAllowed
	subtitle.Text = ""
	-- the camera path (the end shot needs the character on the kaiju)
	local model = workspace:FindFirstChild("CutsceneIntro") or workspace:WaitForChild("CutsceneIntro", 5)
	local t0 = os.clock()
	while not rootPart() and os.clock() - t0 < 10 do task.wait(0.1) end
	local keys = buildKeys(model)
	-- ask the server to stream what every shot will see (StreamingEnabled), for at most ~3 s
	local pending = #keys
	for _, k in ipairs(keys) do
		task.spawn(function()
			pcall(function() player:RequestStreamAroundAsync(k.pos, 3) end)
			pending -= 1
		end)
	end
	local waitUntil = os.clock() + 3
	while pending > 0 and os.clock() < waitUntil do task.wait(0.1) end
	if session ~= mine then return end

	gui.Enabled = true
	bars(true)
	hideOthers(true)
	controls(false)
	if skipAllowed then bindSkip(true) end
	local narration = #Cfg.Lines * Cfg.SecondsPerLine + Cfg.HoldSeconds
	local camEnd = if #keys > 0 then keys[#keys].t else 0
	local total = math.max(narration, camEnd)

	if #keys > 0 then
		local cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Scriptable
		cam.FieldOfView = tonumber(model and model:GetAttribute("Fov")) or DEFAULT_FOV
		local start = os.clock()
		-- speed profile: ease in over the first EASE s, cruise, ease out over the last EASE s (a
		-- whole-timeline ease would rush the middle and move every shot off its authored Time)
		local EASE = math.min(2, camEnd / 4)
		local vmax = camEnd / math.max(camEnd - EASE, 1e-3)
		local function warp(e: number): number
			if e < EASE then return vmax * e * e / (2 * EASE) end
			if e < camEnd - EASE then return vmax * (e - EASE / 2) end
			local r = camEnd - e
			return camEnd - vmax * r * r / (2 * EASE)
		end
		RunService:BindToRenderStep(RENDER, Enum.RenderPriority.Camera.Value + 1, function()
			if session ~= mine then return end
			cam.CFrame = sample(keys, warp(math.min(os.clock() - start, camEnd)))
		end)
	end

	-- subtitles: one line at a time, typed out
	task.spawn(function()
		for _, line in ipairs(Cfg.Lines) do
			if session ~= mine then return end
			subtitle.Text = line
			subtitle.MaxVisibleGraphemes = 0
			local len = utf8.len(line) or #line
			local typeSeconds = math.min(len / TYPE_CPS, Cfg.SecondsPerLine * 0.6)
			local tStart = os.clock()
			while os.clock() - tStart < typeSeconds do
				if session ~= mine then return end
				subtitle.MaxVisibleGraphemes = math.floor(len * (os.clock() - tStart) / typeSeconds)
				task.wait()
			end
			subtitle.MaxVisibleGraphemes = -1
			task.wait(Cfg.SecondsPerLine - typeSeconds)
		end
	end)
	task.delay(total, function() if session == mine then finish(false) end end)
end

BriefShow.OnClientEvent:Connect(function(runs: number) show(tonumber(runs) or 0) end)

-- On join: wait for the loading screen to go (ReplicatedFirst.Loader) and for the server to publish
-- BriefRuns (it may be loading from the DataStore), then play.
task.spawn(function()
	local t0 = os.clock()
	while pg:FindFirstChild("LoadingScreen") and os.clock() - t0 < 30 do task.wait(0.2) end
	local runs = player:GetAttribute("BriefRuns")
	if runs == nil then
		player:GetAttributeChangedSignal("BriefRuns"):Wait()
		runs = player:GetAttribute("BriefRuns")
	end
	show(tonumber(runs) or 0)
end)

-- Space is also the jump key and reaches InputBegan as already processed, so the skip is bound
-- through ContextActionService at high priority while the cutscene plays. The hint is a button too.
local SKIP_ACTION = "DismantleSkipBrief"
local function onSkipAction(_name: string, state: Enum.UserInputState)
	if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
	if showing and skipAllowed then finish(true) end
	return Enum.ContextActionResult.Sink
end
function bindSkip(on: boolean)
	if on then
		ContextActionService:BindActionAtPriority(SKIP_ACTION, onSkipAction, false, Enum.ContextActionPriority.High.Value, Cfg.SkipKey)
	else
		ContextActionService:UnbindAction(SKIP_ACTION)
	end
end
skipHint.Activated:Connect(function() if showing and skipAllowed then finish(true) end end)
