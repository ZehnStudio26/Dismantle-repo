--!strict
-- Loader (Shayan 2026-09-29): the loading screen. ReplicatedFirst.LoadingScreen is authored in Studio
-- (the game key art, a gold DISMANTLE title in the HUD's Arcade face, a LOADING line, a spinner). This
-- script runs before anything else on the client: it shows the screen on the first frame in place of
-- Roblox's default loader, waits for the game, preloads the UI art, meshes and sounds while the LOADING
-- line counts up to 90% of every asset in the game (UI, tools, the kaiju and city, sounds, sky), waits for
-- the character, then fades the screen out (never shorter than MIN_SECONDS so the art is seen, never longer
-- than MAX_SECONDS so nobody gets stuck behind it). The opening cutscene starts once the screen is gone.
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- READY_SHARE (Shayan 2026-09-29): the screen stays until 90% of the game's assets are loaded; the last 10%
-- finish behind the game (and the opening cutscene), MAX_SECONDS is the safety cap for a stuck asset
local MIN_SECONDS, MAX_SECONDS, FADE_SECONDS, READY_SHARE = 2.5, 60, 0.8, 0.9
local STREAM_SECONDS = 20 -- at most this long waiting for the city and the kaiju to stream in
local started = os.clock()
local player = Players.LocalPlayer

local gui = (script.Parent :: Instance):WaitForChild("LoadingScreen"):Clone() :: ScreenGui
gui.Parent = player:WaitForChild("PlayerGui")
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- the key art: if the image cannot be fetched (a fresh upload still in moderation, a wrong id) show the
-- Background's FallbackImage attribute instead of a black screen
local bg = gui:FindFirstChild("Background")
if bg and bg:IsA("ImageLabel") then
	local fallback = bg:GetAttribute("FallbackImage")
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ bg.Image }, function(id, fetch)
				if fetch == Enum.AssetFetchStatus.Failure and typeof(fallback) == "string" and fallback ~= id then
					warn(("[Loader] background %s could not be loaded (moderation pending or wrong id): showing %s"):format(id, fallback))
					bg.Image = fallback
				end
			end)
		end)
	end)
end

local label = gui:WaitForChild("Loading") :: TextLabel
local icon = gui:WaitForChild("LoadingIcon") :: ImageLabel
local spin = RunService.RenderStepped:Connect(function(dt) icon.Rotation -= 240 * dt end)

local function status(text: string) label.Text = text end

task.spawn(function()
	status("LOADING")
	if not game:IsLoaded() then game.Loaded:Wait() end
	local tLoaded = os.clock() - started
	-- StarterGui is copied into PlayerGui when the character spawns: wait for it so its art is preloaded too
	local pg = player:WaitForChild("PlayerGui")
	local waitHud = os.clock() + 5
	while not pg:FindFirstChild("HUD") and os.clock() < waitHud do task.wait(0.1) end

	-- the world first (StreamingEnabled): ask for the areas the opening cutscene shows (each shot's camera
	-- and what it looks at), then wait until the kaiju and the city stop arriving. Otherwise the cutscene
	-- opens on an empty plaza and the asset list below misses the city's meshes and textures.
	status("LOADING THE CITY")
	local tStream0 = os.clock()
	local shots = workspace:WaitForChild("CutsceneIntro", 5)
	local points: { Vector3 } = {}
	if shots then
		for _, p in ipairs(shots:GetChildren()) do
			if p:IsA("BasePart") then
				table.insert(points, p.Position)
				table.insert(points, p.Position + p.CFrame.LookVector * (tonumber(p:GetAttribute("Focus")) or 100))
			end
		end
	end
	for _, pt in ipairs(points) do
		task.spawn(function() pcall(function() player:RequestStreamAroundAsync(pt, 8) end) end)
	end
	local function worldCount(): number
		local n = 0
		for _, name in ipairs({ "Kaiju", "Env", "Scaffolding" }) do
			local f = workspace:FindFirstChild(name)
			if f then n += #f:GetDescendants() end
		end
		return n
	end
	local lastCount, stableSince = -1, os.clock()
	local streamUntil = os.clock() + STREAM_SECONDS
	while os.clock() < streamUntil and os.clock() - started < MAX_SECONDS do
		local c = worldCount()
		if c ~= lastCount then
			lastCount, stableSince = c, os.clock()
		elseif os.clock() - stableSince >= 1.5 then
			break -- nothing new for 1.5 s: the world is in
		end
		task.wait(0.5)
	end
	local streamed, tStream = lastCount, os.clock() - tStream0

	-- what to preload: every image, mesh, texture, sound and animation in the game the client can see, as a
	-- de-duplicated list of content ids (so the percentage is honest: one callback per id, each id once)
	local ids: { string } = {}
	local seen: { [string]: boolean } = {}
	local function add(id: any)
		if typeof(id) ~= "string" or id == "" or seen[id] then return end
		seen[id] = true
		table.insert(ids, id)
	end
	local PROPS: { [string]: { string } } = {
		ImageLabel = { "Image" }, ImageButton = { "Image", "HoverImage", "PressedImage" },
		Decal = { "Texture" }, Texture = { "Texture" }, Sound = { "SoundId" }, Animation = { "AnimationId" },
		MeshPart = { "MeshId", "TextureID" }, SpecialMesh = { "MeshId", "TextureId" },
		SurfaceAppearance = { "ColorMap", "NormalMap", "MetalnessMap", "RoughnessMap" },
		ParticleEmitter = { "Texture" }, Beam = { "Texture" }, Trail = { "Texture" },
		Sky = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp", "SunTextureId", "MoonTextureId" },
	}
	local function collect(root: Instance?)
		if not root then return end
		for _, d in ipairs(root:GetDescendants()) do
			local props = PROPS[d.ClassName]
			if props then
				for _, p in ipairs(props) do
					local ok, v = pcall(function() return (d :: any)[p] end)
					if ok then add(v) end
				end
			end
		end
	end
	for _, root in ipairs({ pg, player:FindFirstChildOfClass("Backpack"), game:GetService("StarterPack"), workspace,
		game:GetService("ReplicatedStorage"), game:GetService("Lighting"), game:GetService("SoundService") }) do
		collect(root)
	end

	-- hold the screen until READY_SHARE of them are in; the rest keep loading behind the game
	local done, total = 0, math.max(#ids, 1)
	local finished = false
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(ids, function()
				done += 1
				if not gui.Parent then return end
				status(("LOADING %d%%"):format(math.min(99, math.floor(done / total * 100))))
			end)
		end)
		finished = true
		if gui.Parent then status("LOADING 100%") end
	end)
	-- never past MAX_SECONDS: a slow or blocked asset must not hold anyone forever
	while not finished and done < total * READY_SHARE and os.clock() - started < MAX_SECONDS do task.wait(0.1) end
	local tPreload = os.clock() - started

	status("ENTERING THE CITY")
	if not player.Character then
		local waitUntil = started + MAX_SECONDS
		while not player.Character and os.clock() < waitUntil do task.wait(0.1) end
	end
	local left = MIN_SECONDS - (os.clock() - started)
	if left > 0 then task.wait(left) end

	-- fade everything out together, then remove the screen
	local info = TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("ImageLabel") then TweenService:Create(d, info, { ImageTransparency = 1, BackgroundTransparency = 1 }):Play()
		elseif d:IsA("TextLabel") then TweenService:Create(d, info, { TextTransparency = 1 }):Play()
		elseif d:IsA("Frame") then TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
		elseif d:IsA("UIStroke") then TweenService:Create(d, info, { Transparency = 1 }):Play()
		end
	end
	task.wait(FADE_SECONDS)
	spin:Disconnect()
	gui:Destroy()
	print(("[Loader] loading screen done after %.1f s: game loaded at %.1f s, world streamed (%d instances) in %.1f s, %d of %d asset(s) (%d%%) in by %.1f s%s"):format(
		os.clock() - started, tLoaded, streamed, tStream, done, #ids, math.floor(done / total * 100), tPreload,
		if done >= total * READY_SHARE or finished then "" else " (safety cap reached)"))
end)
