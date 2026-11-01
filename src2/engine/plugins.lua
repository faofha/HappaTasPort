-- ================================================================================================
--  PLUGINS  (HappaTAS 3 engine): the world plugins (character, camera, inputs, animation, tools, and in
--  later phases client objects, buttons, lighting, the EToH kit, time control), called in a fixed order.
--  A plugin is a table { name, order, ... hooks }; every hook is optional:
--    attach(char)              a new character
--    begin(tl, i)              PreRender: frame i was just appended (recording)
--    fill(tl, i)               PreSimulation, or Heartbeat when the frame had no physics step
--    lateRender()              the end of the render step
--  and the "on..." hooks at V2.38.16's call sites (onShowFrame(tl, i) paused on frame i, onRestoreUnpause,
--  onPlayTo(tl, i, t), onPause(t), onRewind, onRelease, onEndPlayback, onPlaybackBegin(Always),
--  onBeginRecording, onUnpause, onStep(t), onPausedTick, onHeartbeatStart(mode), onFrameEnd(dt),
--  onCreateStats(tl, f), onPlayedFrame, onAfterPhysics, onDataChanged, onReset, onLoaded, onCursorReset,
--  onUnload), and phase 4's onFrameStart (first in PreRender), onPreSimulation(dt) (first in PreSimulation),
--  onCut(tl, n) (frames after n were cut when unpausing), onSave(tl) (before a file is built),
--  onLoading(tl) (a loaded run before the engine takes it: its ids translated, may yield). A plugin's own methods must not use these names (the registry would call them).
--  Each call is protected: an error is reported once per message (the frame goes on).
-- ================================================================================================
local Plugins = {}
Plugins.__index = Plugins

function Plugins.new(errs)
	-- (byHook: for each hook, the functions and plugins that have it, in order; made on the first call, dropped by
	-- add / remove)
	return setmetatable({ list = {}, byName = {}, byHook = {}, errs = errs }, Plugins)
end

function Plugins:add(p)
	local at = #self.list + 1
	for i, other in ipairs(self.list) do
		if other.order > p.order then at = i break end
	end
	table.insert(self.list, at, p)
	self.byName[p.name] = p
	self.byHook = {}
	return p
end

function Plugins:remove(name)
	local p = self.byName[name]
	if not p then return end
	for i, q in ipairs(self.list) do
		if q == p then table.remove(self.list, i) break end
	end
	self.byName[name] = nil
	self.byHook = {}
end

function Plugins:get(name) return self.byName[name] end

-- The engine calls the phase 2 plugins (and the camera script) by name, in V2.38.16's order. Each of those
-- calls goes through a guard: an error is reported once per message as "name.method" and the call returns
-- nothing, so one failing plugin never stops the engine's frame. Fields read and written through the guard
-- are the object's own.
-- Plugins.prof (set by the MicroProfiler while it's open): begin(name) / finish(name) around the guarded calls
-- and plugin hooks it times: Plugins.prof.names[name] = true (every call) or a set of hook / method names.
function Plugins.guard(errs, obj, name)
	local proxy = {}
	local function make(k)
		local label = name .. "." .. tostring(k)
		local function finish(ok, ...)
			if ok then return ... end
			errs:report(label, (...))
			return nil
		end
		local function timed(pr, ok, ...)
			pr.finish(name)
			return finish(ok, ...)
		end
		return function(_, ...)
			local pr = Plugins.prof
			local t = pr and pr.names[name]
			if t and (t == true or t[k]) then
				pr.begin(name)
				return timed(pr, pcall(obj[k], obj, ...))
			end
			return finish(pcall(obj[k], obj, ...))
		end
	end
	return setmetatable(proxy, {
		__index = function(_, k)
			local v = obj[k]
			if type(v) ~= "function" then return v end
			local w = make(k)
			rawset(proxy, k, w)
			return w
		end,
		__newindex = function(_, k, v) obj[k] = v end,
	})
end

-- (each hook's functions, plugins and report names are listed once, on the first call after an add / remove:
-- a call is one pcall per plugin, no method lookup or name building every frame)
function Plugins:call(hook, ...)
	local h = self.byHook[hook]
	if not h then
		h = { fns = {}, ps = {}, names = {}, n = 0 }
		for _, p in ipairs(self.list) do
			local f = p[hook]
			if f then
				local n = h.n + 1
				h.n = n
				h.fns[n], h.ps[n], h.names[n] = f, p, p.name .. "." .. hook
			end
		end
		self.byHook[hook] = h
	end
	local fns, ps = h.fns, h.ps
	local pr = Plugins.prof
	local timed = pr and pr.names
	for i = 1, h.n do
		local t = timed and timed[ps[i].name]
		if t and t ~= true and not t[hook] then t = nil end
		if t then pr.begin(ps[i].name) end
		local ok, err = pcall(fns[i], ps[i], ...)
		if t then pr.finish(ps[i].name) end
		if not ok then self.errs:report(h.names[i], err) end
	end
end

return Plugins
