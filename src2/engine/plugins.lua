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
--  onCut(tl, n) (frames after n were cut when unpausing), onSave(tl) (before a file is built). A plugin's own methods must not use these names (the registry would call them).
--  Each call is protected: an error is reported once per message (the frame goes on).
-- ================================================================================================
local Plugins = {}
Plugins.__index = Plugins

function Plugins.new(errs)
	return setmetatable({ list = {}, byName = {}, errs = errs }, Plugins)
end

function Plugins:add(p)
	local at = #self.list + 1
	for i, other in ipairs(self.list) do
		if other.order > p.order then at = i break end
	end
	table.insert(self.list, at, p)
	self.byName[p.name] = p
	return p
end

function Plugins:get(name) return self.byName[name] end

-- The engine calls the phase 2 plugins (and the camera script) by name, in V2.38.16's order. Each of those
-- calls goes through a guard: an error is reported once per message as "name.method" and the call returns
-- nothing, so one failing plugin never stops the engine's frame. Fields read and written through the guard
-- are the object's own.
function Plugins.guard(errs, obj, name)
	local proxy = {}
	local function make(k)
		local label = name .. "." .. tostring(k)
		local function finish(ok, ...)
			if ok then return ... end
			errs:report(label, (...))
			return nil
		end
		return function(_, ...) return finish(pcall(obj[k], obj, ...)) end
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

function Plugins:call(hook, ...)
	for _, p in ipairs(self.list) do
		local f = p[hook]
		if f then
			local ok, err = pcall(f, p, ...)
			if not ok then self.errs:report(p.name .. "." .. hook, err) end
		end
	end
end

return Plugins
