-- ================================================================================================
--  MAIN  (HappaTAS 3): starts the kernel, and undoes everything on Unload.
--  Running the script again (or over HappaTAS V2.38.x) unloads the older copy first. Only the version
--  and Unload are shared through getgenv(); with CONFIG.Debug the kernel is shared too (for tests).
-- ================================================================================================
local CONFIG = import("config")
local Env = import("platform/env")
local Lifecycle = import("kernel/lifecycle")
local Errors = import("kernel/errors")
local State = import("kernel/state")
local Bus = import("kernel/bus")
local Pipeline = import("kernel/pipeline")
local Settings = import("engine/settings")
local Controls = import("engine/controls")
local Typing = import("platform/typing")
local Timeline = import("engine/timeline")
local Plugins = import("engine/plugins")
local Modes = import("engine/modes")
local Frame = import("engine/frame")
local Character = import("world/character")
local CameraScript = import("platform/camerascript")
local Camera = import("world/camera")
local Inputs = import("world/inputs")
local Cursor = import("world/cursor")
local Animation = import("world/animation")
local Tools = import("world/tools")
local ClientObjects = import("world/clientobjects")
local Buttons = import("world/buttons")
local Lighting = import("world/lighting")
local TimeControl = import("world/time/control")
local KitClockPlugin = import("world/kit/clock")
local Merge = import("engine/merge")
local Files = import("platform/files")
local Library = import("persist/library")
local Run = import("persist/run")
local Persist = import("persist/persist")
local SettingsFile = import("persist/settingsfile")

local Main = {}
local kernel = nil

-- (sharing through getgenv() never stops the script: without getgenv the global table may be read-only,
-- then only re-run detection is lost, reported once)
local function share(key, value, errs)
	local ok, err = pcall(function() Env.genv[key] = value end)
	if not ok and errs then errs:report("main", "could not share " .. key .. ": " .. tostring(err)) end
end

-- (V2.38.x's Unload could take its thread's access to CoreGui away: each older copy unloads on a
-- thread of its own)
-- the engine: settings, the run's timeline, the world plugins, the mode machine and the frame loop, all
-- owned by one lifecycle scope. On Unload the character is let go first (Idle, unanchored).
local function startEngine(k)
	local life = k.life:scope("engine")
	local E = { life = life, errs = k.errs, bus = k.bus, state = k.state, pipe = k.pipe }
	E.settings = Settings.new(k.errs)
	E.controls = Controls.new()
	-- (saved settings and keys before any plugin reads them)
	E.files = Files.new(Env)
	E.settingsFile = SettingsFile.new(E.files, E.settings, E.controls, life)
	E.settingsFile:load()
	E.typing = Typing.new(life)
	E.tl = Timeline.new()
	E.tl:addColumn("FrameTime", "f64", 1, { key = "FrameTime" })
	E.tl:addColumn("TotalTime", "f64", 1, { key = "TotalTime" })
	E.plugins = Plugins.new(k.errs)
	local guard = function(obj, name) return Plugins.guard(k.errs, obj, name) end
	E.cs = guard(CameraScript.new(life, k.errs, { modalOpen = function() return E.modalOpen ~= nil and E.modalOpen() end, getMode = function() return E.mode end }), "cameraScript")
	E.char = guard(E.plugins:add(Character.new(E)), "character")
	E.cam = guard(E.plugins:add(Camera.new(E)), "camera")
	E.inputs = guard(E.plugins:add(Inputs.new(E)), "inputs")
	E.cursor = guard(E.plugins:add(Cursor.new(E)), "cursor")
	E.anim = guard(E.plugins:add(Animation.new(E)), "animation")
	E.co = guard(E.plugins:add(ClientObjects.new(E)), "clientObjects")
	E.buttons = guard(E.plugins:add(Buttons.new(E)), "buttons")
	E.lighting = guard(E.plugins:add(Lighting.new(E)), "lighting")
	E.tools = guard(E.plugins:add(Tools.new(E)), "tools")
	E.mergeRun = guard(E.plugins:add(Merge.new(E)), "merge")
	-- (the kit: the engine calls it by name; no-ops until its plugins replace them)
	E.kitObjects = guard({ frame = function() end }, "kitObjects")
	E.time = guard(E.plugins:add(TimeControl.new(E)), "time")
	E.kitClock = guard(E.plugins:add(KitClockPlugin.new(E)), "kitClock")
	-- (data no plugin records yet, from V2 files: kept for phase 4; the library of this place's runs)
	Run.registerCarry(E.tl)
	E.library = Library.new(E.files, "HappaTasPort/" .. tostring(game.PlaceId))
	E.persist = Persist.new(E)
	E.modes = Modes.new(E)
	k.pipe:keep("engine") -- (one failing call is reported; the engine's frame always goes on)
	E.inputs:start() -- (before the engine's key dispatch, as in V2.38.16)
	Frame.start(E)
	E.cs:start()
	E.char:start()
	life:own(function()
		pcall(E.modes.cancelDeferred, E.modes)
		if E.mode ~= 1 and E.char:loaded() then pcall(E.modes.idle, E.modes) end
		local hrp = E.char.hrp
		if hrp and hrp.Parent then hrp.Anchored = false end
		E.plugins:call("onUnload")
	end)
	return E
end

-- Saving and loading from the executor's console, until the phase 5 Library window:
--   Save(name, folder?)   SaveAttempt(name, folder?)   Load(path)   List()
-- Save / Load start the work and return true, "started" (the result shows as a status message), or false
-- and why. Without file functions each returns false, "Saving is unavailable on this executor".
local UNAVAILABLE = "Saving is unavailable on this executor"
local function addSaveApi(handle, k)
	local function engine()
		local E = k.engine
		if not E then return nil, "HappaTAS isn't running" end
		if not E.files.available then return nil, UNAVAILABLE end
		return E
	end
	handle.Save = function(name, folder)
		local E, why = engine()
		if not E then return false, why end
		return E.persist:save(name, folder)
	end
	handle.SaveAttempt = function(name, folder)
		local E, why = engine()
		if not E then return false, why end
		return E.persist:save(name, folder, true)
	end
	handle.Load = function(path)
		local E, why = engine()
		if not E then return false, why end
		return E.persist:load(path)
	end
	handle.List = function()
		local E, why = engine()
		if not E then return false, why end
		local out = {}
		for _, e in ipairs(E.library:list()) do
			out[#out + 1] = { path = e.path, name = e.name, frames = e.frames, length = e.length, saved = e.saved }
		end
		return out
	end
end

local function unloadOlder()
	local genv = Env.genv
	for _, key in ipairs({ "__HappaTAS", "__HappaTAS3" }) do
		local old = genv[key]
		if type(old) == "table" and type(old.Unload) == "function" then
			task.spawn(pcall, old.Unload)
		end
	end
end

-- The handle is shared first and every later step runs protected: a Start that fails halfway is
-- reported and unloaded at once, so it never leaves a running copy nothing can unload.
function Main.Start()
	unloadOlder()
	local errs = Errors.new()
	local life = Lifecycle.new("HappaTAS3")
	local handle = { Version = CONFIG.VERSION, Unload = Main.Unload }
	local k = { errs = errs, life = life, handle = handle }
	addSaveApi(handle, k)
	kernel = k
	share("__HappaTAS3", handle, errs)
	local ok, err = pcall(function()
		k.state = State.new({ mode = "Idle", frame = 0, paused = true }, errs)
		k.bus = Bus.new(errs)
		k.pipe = Pipeline.new(life, errs, k.bus)
		k.pipe:start()
		k.engine = startEngine(k)
		if CONFIG.Debug then
			k.debug = { errs = errs, life = life, state = k.state, bus = k.bus, pipe = k.pipe, Env = Env, engine = k.engine }
			share("__HappaTAS3_T", k.debug, errs)
			print("[HappaTAS3] loaded " .. CONFIG.VERSION .. " (" .. Env.executor .. ")")
		end
	end)
	if not ok then
		errs:report("main", "start failed: " .. tostring(err))
		Main.Unload()
		return false
	end
	return true
end

function Main.Unload()
	local k = kernel
	if not k then return end
	kernel = nil
	if k.pipe then k.pipe:stop() end
	k.life:cleanup()
	local genv = Env.genv
	if genv.__HappaTAS3 == k.handle then share("__HappaTAS3", nil) end
	if k.debug and genv.__HappaTAS3_T == k.debug then share("__HappaTAS3_T", nil) end
end

return Main
