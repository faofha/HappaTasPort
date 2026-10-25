-- ================================================================================================
--  PERSIST  (HappaTAS 3 persist): saving and loading the engine's run. Each runs on a thread of its own
--  (it yields every 2000 frames, so the game keeps its frame rate) and E.busy says so; while it runs,
--  every transition is refused (Modes:allowed), so the run can't change under it. The result goes on the
--  bus ("persist", { op, ok, message, path }) and as a status message.
--  Save: not while recording. Load: only in Idle or paused in Create; the file is read into a fresh
--  timeline and taken over only when it loaded, so a damaged file leaves the run as it was.
-- ================================================================================================
local Files = import("platform/files")
local Timeline = import("engine/timeline")
local Run = import("persist/run")

local Persist = {}
Persist.__index = Persist

local UNAVAILABLE = "Saving is unavailable on this executor"

function Persist.new(E)
	return setmetatable({ E = E }, Persist)
end

local function available(E)
	return E.library ~= nil and E.library.files ~= nil and E.library.files.available == true
end

local function done(E, op, ok, message, path)
	E.busy = nil
	E.bus:emit("persist", { op = op, ok = ok, message = message, path = path })
	E.bus:emit("status", message, not ok)
end

local function baseName(path)
	return (tostring(path):match("([^/]+)$") or tostring(path)):gsub("%.[^%.]+$", "")
end

-- saves the run as <folder>/<name>.tas (asAttempt: the next "name (n)"); true, "started" or false, why
function Persist:save(name, folder, asAttempt)
	local E = self.E
	if not available(E) then return false, UNAVAILABLE end
	if E.busy then return false, "Wait: " .. E.busy end
	if E.mode == 2 and not E.paused then return false, "Pause before saving" end
	local clean = Files.cleanName(name)
	if not clean then return false, "Invalid name" end
	if asAttempt then clean = E.library:nextAttemptName(clean, folder) end
	E.plugins:call("onSave", E.tl) -- (the plugins' id tables into tl.meta before the file is built)
	E.busy = "saving"
	task.spawn(function()
		task.wait() -- (the work starts on the next frame: the caller's frame isn't held up)
		local ok, res = pcall(function()
			local data = Run.build(E.tl, clean)
			local okS, rel = E.library:save(clean, folder, data)
			if not okS then error(rel, 0) end
			return rel
		end)
		if ok then
			done(E, "save", true, "Saved " .. clean, res)
		else
			done(E, "save", false, "Could not save: " .. tostring(res), nil)
		end
	end)
	return true, "started"
end

-- loads the run at path (relative to the library's root); true, "started" or false, why
function Persist:load(path)
	local E = self.E
	if not available(E) then return false, UNAVAILABLE end
	if E.busy then return false, "Wait: " .. E.busy end
	if not (E.mode == 1 or (E.mode == 2 and E.paused)) then return false, "Go Idle or pause before loading" end
	E.busy = "loading"
	task.spawn(function()
		task.wait()
		local fresh
		local ok, res = pcall(function()
			local data, err = E.library:read(path)
			if not data then error(err or "the file could not be read", 0) end
			fresh = Timeline.newLike(E.tl)
			return Run.load(fresh, data)
		end)
		if ok then
			E.tl:adopt(fresh)
			E.modes:runLoaded()
			E.loaded = { path = path, header = res }
			done(E, "load", true, "Loaded " .. baseName(path), path)
		else
			done(E, "load", false, "Could not load: " .. tostring(res), path)
		end
	end)
	return true, "started"
end

return Persist
