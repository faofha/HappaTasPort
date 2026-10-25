-- ================================================================================================
--  SETTINGS  (HappaTAS 3 engine): one schema of every setting and an in-memory store with change
--  listeners. Each row keeps its V2.38.16 name (`v2`) so Settings.json from V2 can be converted (phase 3).
--  kind "toggle" = 0 / 1, "number" = clamped to min / max (integer: rounded; nonzero: 0 refused).
--  Defaults are V2.38.16's.
-- ================================================================================================
local Settings = {}
Settings.__index = Settings

local function row(key, v2, section, default, extra)
	local r = { key = key, v2 = v2, section = section, default = default, kind = "toggle" }
	if extra then for k, v in pairs(extra) do r[k] = v end end
	return r
end
local NUM = "number"

Settings.SCHEMA = {
	row("lockCameraTest", "Lock Camera (Test)", "Playback", 1),
	row("interpolatePlayback", "Interpolate Playback", "Playback", 1),
	row("playbackSpeed", "Playback Speed", "Playback", 1, { kind = NUM, nonzero = true }),
	row("restartWhenTesting", "Restart When Testing", "Playback", 1),
	row("showCompletionMessage", "Show Completion Message", "Playback", 1),

	row("lockCameraPaused", "Lock Camera (Paused)", "Create", 1),
	row("recordDeath", "Record Death & Respawn", "Create", 1),
	row("recordTools", "Record Tool Actions", "Create", 1),
	row("ignoreGameProcessed", "Ignore Game Processed", "Create", 0),

	row("speedHack", "Speed Hack", "Speed hack", 0),
	row("speedHackSpeed", "Speed Hack Speed", "Speed hack", 0.5, { kind = NUM, min = 0.1, max = 4 }),
	row("speedHackFrameStep", "Speed Hack Frame Step", "Speed hack", 0),

	row("replayKeyboard", "Replay Keyboard", "Inputs", 1),
	row("replayMouseClicks", "Replay Mouse Clicks", "Inputs", 1),
	row("replayMouseMovement", "Replay Mouse Movement", "Inputs", 1),
	row("normalizeMouseUV", "Normalize Mouse UV", "Inputs", 1),
	row("nohboardCursor", "NohBoard Cursor", "Inputs", 1),
	row("invisibleMouseSpeed", "Invisible Mouse Speed Multiplier", "Inputs", 1, { kind = NUM, min = 0.01, max = 100 }),
	row("windowGuarding", "Window Guarding", "Inputs", 1),

	row("syncClientObjects", "Sync Client Objects", "World sync", 0),
	row("smoothClientObjects", "Smooth Client Objects", "World sync", 1),
	row("frustumCullingCO", "Frustum Culling CO", "World sync", 1),
	row("syncButtonTimers", "Sync Button Timers", "World sync", 1),
	row("syncLighting", "Sync Lighting", "World sync", 1),
	row("kitScriptsOnTasClock", "Kit Scripts On TAS Clock", "World sync", 1),
	row("syncKitObjects", "Sync Kit Objects", "World sync", 1),

	row("showStatsIdle", "Show Stats (Idle)", "Interface", 1),
	row("showStatsCreate", "Show Stats (Create)", "Interface", 1),
	row("showStatsTest", "Show Stats (Test)", "Interface", 1),
	row("statsTextSize", "Stats Text Size", "Interface", 11, { kind = NUM, min = 6, max = 30, integer = true }),
	row("showMicroProfiler", "Show MicroProfiler", "Interface", 0),
	row("microProfilerScale", "MicroProfiler Scale", "Interface", 1, { kind = NUM, min = 0.5, max = 4 }),
	row("microProfilerTextOffset", "MicroProfiler Text Offset", "Interface", 0, { kind = NUM, min = -6, max = 6, integer = true }),
	row("allowPlayerGuiInterface", "Allow PlayerGui Interface", "Interface", 0),
	-- (V2.38.16's 5 sound settings went with V2.38.17: a V2 Settings.json that has them converts without them)
}
Settings.byKey, Settings.byV2 = {}, {}
for i, r in ipairs(Settings.SCHEMA) do
	r.order = i
	Settings.byKey[r.key] = r
	Settings.byV2[r.v2] = r
end

-- nil when the value isn't allowed (V2 Settings.Sanitize)
function Settings.sanitize(def, v)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then return nil end
	if def.kind == "toggle" then return (v ~= 0) and 1 or 0 end
	if def.integer then v = math.floor(v + 0.5) end
	if def.min and v < def.min then v = def.min end
	if def.max and v > def.max then v = def.max end
	if def.nonzero and v == 0 then return nil end
	return v
end

function Settings.new(errs)
	local values = {}
	for _, r in ipairs(Settings.SCHEMA) do values[r.key] = r.default end
	return setmetatable({ values = values, listeners = {}, anyListeners = {}, errs = errs }, Settings)
end

function Settings:get(key) return self.values[key] or 0 end

function Settings:on(key)
	local v = self.values[key]
	return v ~= nil and v ~= 0
end

-- false when the key is unknown or the value isn't allowed; listeners run only on a change
function Settings:set(key, v)
	local def = Settings.byKey[key]
	if not def then return false end
	v = Settings.sanitize(def, v)
	if v == nil then return false end
	if self.values[key] == v then return true end
	self.values[key] = v
	local list = self.listeners[key]
	if list then
		for _, f in ipairs(table.clone(list)) do
			local ok, err = pcall(f, v)
			if not ok and self.errs then self.errs:report("setting " .. key, err) end
		end
	end
	for _, f in ipairs(table.clone(self.anyListeners)) do
		local ok, err = pcall(f, key, v)
		if not ok and self.errs then self.errs:report("settings", err) end
	end
	return true
end

-- f(key, value) after any change (the settings file saves on it); returns a function that removes it
function Settings:onAny(f)
	local list = self.anyListeners
	list[#list + 1] = f
	return function()
		local i = table.find(list, f)
		if i then table.remove(list, i) end
	end
end

-- f(value) after each change; returns a function that removes it
function Settings:changed(key, f)
	local list = self.listeners[key]
	if not list then
		list = {}
		self.listeners[key] = list
	end
	list[#list + 1] = f
	return function()
		local i = table.find(list, f)
		if i then table.remove(list, i) end
	end
end

return Settings
