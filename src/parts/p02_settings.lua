-- ================================================================================================
--  CONTROLS + SETTINGS
--  Plain Lua tables (fast to read every frame). Names are the same as before, so an old
--  HappaTasPort/Settings.json keeps working.
-- ================================================================================================
local ControlsTable = {
	{ "Idle", "1" },
	{ "Create", "2" },
	{ "Test", "3" },
	{ "Pause", "Left Click" },
	{ "Unpause", "Left Click" },
	{ "Forward", "T" },
	{ "Back", "R" },
	{ "Forward 1 Frame", "G" },
	{ "Back 1 Frame", "F" },
	{ "Unpause 1 Frame", "V" },
	{ "Return", "E" },
	{ "Look Around", "L" },
	{ "Optimize TAS", "Q" },
	{ "Delete TAS", "Backspace" },
	{ "Menu", "M" },
	{ "MicroProfiler", "F6" },
}

-- kind: "toggle" (0/1) or "number". label = text in the Settings tab. section = heading it is listed under.
local SettingsTable = {
	{ name = "Lock Camera (Test)",       default = 1, section = "Playback" },
	{ name = "Interpolate Playback",     default = 1, section = "Playback" },
	{ name = "Playback Speed",           default = 1, section = "Playback", kind = "number", nonzero = true },
	{ name = "Restart When Testing",     default = 1, section = "Playback" },
	{ name = "Show Completion Message",  default = 1, section = "Playback" },

	{ name = "Lock Camera (Paused)",     default = 1, section = "Create" },
	{ name = "Record Death & Respawn",   default = 1, section = "Create" },
	{ name = "Record Tool Actions",      default = 1, section = "Create" },
	{ name = "Ignore Game Processed",    default = 0, section = "Create" },

	{ name = "Replay Keyboard",          default = 1, section = "Inputs" },
	{ name = "Replay Mouse Clicks",      default = 1, section = "Inputs" },
	{ name = "Replay Mouse Movement",    default = 1, section = "Inputs" },
	{ name = "Normalize Mouse UV",       default = 1, section = "Inputs" },
	{ name = "NohBoard Cursor",          default = 1, section = "Inputs" },
	{ name = "Invisible Mouse Speed Multiplier", default = 1, section = "Inputs", kind = "number", label = "Invisible Mouse Speed", min = 0.01, max = 100 },
	{ name = "Window Guarding",          default = 1, section = "Inputs" },

	{ name = "Sync Client Objects",      default = 0, section = "World Sync" },
	{ name = "Smooth Client Objects",    default = 1, section = "World Sync" },
	{ name = "Frustum Culling CO",       default = 1, section = "World Sync" },
	{ name = "Sync Button Timers",       default = 1, section = "World Sync" },

	{ name = "Show Stats (Idle)",        default = 1, section = "Interface" },
	{ name = "Show Stats (Create)",      default = 1, section = "Interface" },
	{ name = "Show Stats (Test)",        default = 1, section = "Interface" },
	{ name = "Stats Text Size",          default = 11, section = "Interface", kind = "number", min = 6, max = 30, integer = true },
	{ name = "Show MicroProfiler",       default = 0, section = "Interface" },
	{ name = "MicroProfiler Scale",      default = 1, section = "Interface", kind = "number", label = "MicroProfiler Size (1 = Roblox)", min = 0.5, max = 4 },
	{ name = "MicroProfiler Text Offset", default = 0, section = "Interface", kind = "number", label = "MicroProfiler Text Offset (px, - = up)", min = -6, max = 6, integer = true },

	{ name = "Enable Keyboard Sounds",   default = 0, section = "Sounds", label = "Keyboard Sounds" },
	{ name = "Enable Click Sounds",      default = 0, section = "Sounds", label = "Mouse Click Sounds" },
	{ name = "Sound Trigger Mode",       default = 0, section = "Sounds", kind = "number", label = "Sound Mode (0 Live 1 Play 2 Both)", min = 0, max = 2, integer = true },
	{ name = "Sound Volume",             default = 50, section = "Sounds", kind = "number", label = "Sound Volume (0-100)", min = 0, max = 100 },
	{ name = "Dynamic Pitch Variation",  default = 1, section = "Sounds" },
}

local Settings = { values = {}, defs = {}, listeners = {}, onAnyChange = nil }
local Controls = { values = {}, listeners = {}, onAnyChange = nil }

do
	for i, def in ipairs(SettingsTable) do
		def.kind = def.kind or "toggle"
		def.label = def.label or def.name
		def.order = i
		Settings.defs[def.name] = def
		Settings.values[def.name] = def.default
	end
	for _, c in ipairs(ControlsTable) do
		Controls.values[c[1]] = c[2]
	end

	local function sanitize(def, v)
		v = tonumber(v)
		if v == nil or v ~= v or v == math.huge or v == -math.huge then return nil end
		if def.kind == "toggle" then return (v ~= 0) and 1 or 0 end
		if def.integer then v = math.floor(v + 0.5) end
		if def.min and v < def.min then v = def.min end
		if def.max and v > def.max then v = def.max end
		if def.nonzero and v == 0 then return nil end
		return v
	end
	Settings.Sanitize = sanitize

	function Settings.Get(name)
		return Settings.values[name] or 0
	end
	function Settings.On(name)
		local v = Settings.values[name]
		return v ~= nil and v ~= 0
	end

	local function fire(list, ...)
		if not list then return end
		for _, f in ipairs(list) do
			local ok, err = pcall(f, ...)
			if not ok then log("listener failed:", tostring(err)) end
		end
	end

	-- returns false when the value is not allowed
	function Settings.Set(name, v)
		local def = Settings.defs[name]
		if not def then return false end
		v = sanitize(def, v)
		if v == nil then return false end
		if Settings.values[name] == v then return true end
		Settings.values[name] = v
		fire(Settings.listeners[name], v)
		if Settings.onAnyChange then Settings.onAnyChange() end
		return true
	end

	function Settings.Changed(name, f)
		local list = Settings.listeners[name]
		if not list then list = {}; Settings.listeners[name] = list end
		list[#list + 1] = f
	end

	function Controls.Get(name)
		return Controls.values[name]
	end
	function Controls.Set(name, key)
		if Controls.values[name] == nil or type(key) ~= "string" then return end
		if Controls.values[name] == key then return end
		Controls.values[name] = key
		fire(Controls.listeners[name], key)
		fire(Controls.listeners["*"], name, key)
		if Controls.onAnyChange then Controls.onAnyChange() end
	end
	function Controls.Changed(name, f)
		local list = Controls.listeners[name]
		if not list then list = {}; Controls.listeners[name] = list end
		list[#list + 1] = f
	end

	-- saved = decoded Settings.json ({ controls = {...}, settings = {...} })
	function Settings.ApplySaved(saved, validKey)
		if type(saved) ~= "table" then return end
		if type(saved.settings) == "table" then
			for name, v in pairs(saved.settings) do
				local def = type(name) == "string" and Settings.defs[name]
				if def then
					local s = sanitize(def, v)
					if s ~= nil then Settings.values[name] = s end
				end
			end
		end
		if type(saved.controls) == "table" then
			for name, v in pairs(saved.controls) do
				if type(name) == "string" and Controls.values[name] ~= nil and type(v) == "string" and validKey(v) then
					Controls.values[name] = v
				end
			end
		end
	end

	function Settings.Serialize(extra)
		local out = { controls = {}, settings = {} }
		for name, v in pairs(Controls.values) do out.controls[name] = v end
		for name, v in pairs(Settings.values) do out.settings[name] = v end
		if extra then for k, v in pairs(extra) do out[k] = v end end
		return out
	end

	Settings.Changed("Window Guarding", function(v) Env.Guarding = v ~= 0 end)
end

