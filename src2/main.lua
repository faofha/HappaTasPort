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
local function unloadOlder()
	local genv = Env.genv
	for _, key in ipairs({ "__HappaTAS", "__HappaTAS3" }) do
		local old = genv[key]
		if type(old) == "table" and type(old.Unload) == "function" then
			task.spawn(pcall, old.Unload)
		end
	end
end

function Main.Start()
	unloadOlder()
	local errs = Errors.new()
	local life = Lifecycle.new()
	local state = State.new({ mode = "Idle", frame = 0, paused = true }, errs)
	local bus = Bus.new(errs)
	local pipe = Pipeline.new(life, errs, bus)
	pipe:start()
	local handle = { Version = CONFIG.VERSION, Unload = Main.Unload }
	kernel = { errs = errs, life = life, state = state, bus = bus, pipe = pipe, handle = handle }
	share("__HappaTAS3", handle, errs)
	if CONFIG.Debug then
		kernel.debug = { errs = errs, life = life, state = state, bus = bus, pipe = pipe, Env = Env }
		share("__HappaTAS3_T", kernel.debug, errs)
		print("[HappaTAS3] loaded " .. CONFIG.VERSION .. " (" .. Env.executor .. ")")
	end
end

function Main.Unload()
	local k = kernel
	if not k then return end
	kernel = nil
	k.pipe:stop()
	k.life:cleanup()
	local genv = Env.genv
	if genv.__HappaTAS3 == k.handle then share("__HappaTAS3", nil) end
	if k.debug and genv.__HappaTAS3_T == k.debug then share("__HappaTAS3_T", nil) end
end

return Main
