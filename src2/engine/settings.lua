-- ================================================================================================
--  SETTINGS  (HappaTAS 3 engine): one schema of every setting and an in-memory store with change
--  listeners. Each row keeps its V2.38.16 name (`v2`) so Settings.json from V2 can be converted (phase 3).
--  kind "toggle" = 0 / 1, "number" = clamped to min / max (integer: rounded; nonzero: 0 refused),
--  "choice" = one of `options` (matched without case, stored as written there), "color" = "#RRGGBB",
--  "text" = a string of at most 40 characters. Every row has a `desc` (the line under its name in the
--  Settings window). Defaults are V2.38.16's; the Appearance rows (phase 5a, no V2 name) come from the mockup.
-- ================================================================================================
local Settings = {}
Settings.__index = Settings

local function row(key, v2, section, default, extra)
	local r = { key = key, v2 = v2, section = section, default = default, kind = "toggle" }
	if extra then for k, v in pairs(extra) do r[k] = v end end
	return r
end
local NUM = "number"
local function choice(options) return { kind = "choice", options = options } end
local function color() return { kind = "color" } end
local function num(min, max, integer) return { kind = NUM, min = min, max = max, integer = integer } end
local function with(t, desc) t.desc = desc; return t end

-- the font families the interface can use (rbxasset://fonts/families/<name>.json)
Settings.FONTS = { "BuilderSans", "GothamSSm", "SourceSansPro", "Roboto", "Montserrat", "Nunito", "Ubuntu", "FredokaOne",
	"Oswald", "Merriweather", "RobotoMono", "Inconsolata" }
local EASINGS = { "Preset", "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Circular", "Back", "Elastic",
	"Bounce", "Custom" }
local function look(key, default, extra, desc) return row(key, nil, "Appearance", default, with(extra, desc)) end

Settings.SCHEMA = {
	look("theme", "Default", { kind = "text" }, "Save your look and switch between saved looks"),
	look("glass", "Tint", choice({ "Clear", "Tint", "Frost" }), "Frost blurs the game behind (high graphics only)"),
	look("glassColor", "#242A38", color(), "The colour of the windows' glass"),
	look("glassTransparency", 54, num(0, 100, true), "How much of the game shows through the glass"),
	look("blurStrength", 70, num(0, 100, true), "How strongly Frost blurs the game behind"),
	look("edgeLight", 16, num(0, 100, true), "The light on the windows' edges"),
	look("accentColor", "#3F7CF0", color(), "Switches, sliders and main buttons"),
	look("textColor", "#FFFFFF", color(), "The interface's text"),
	look("secondaryTextColor", "#B4BBC8", color(), "Explanations and other quieter text"),
	look("recordingColor", "#FF5A5A", color(), "Shown while recording"),
	look("font", "BuilderSans", choice(Settings.FONTS), "The interface's text font"),
	look("numberFont", "RobotoMono", choice(Settings.FONTS), "The font for numbers"),
	look("textSize", 13, num(8, 24, true), "Click the number to type a value"),
	look("interfaceScale", 100, num(50, 200, true), "The size of the whole interface"),
	look("windowCorners", 16, num(0, 24, true), "How round the windows' corners are"),
	look("buttonShape", "Pill", choice({ "Pill", "Rounded", "Square" }), "The corners of buttons and fields"),
	look("shadows", 1, { kind = "toggle" }, "Soft shadows under the windows"),
	look("animations", "Smooth", choice({ "Off", "Smooth", "Snappy", "Bouncy" }), "How the interface moves"),
	look("animationLength", 0.2, num(0.05, 1), "How long a move takes, in seconds"),
	look("easing", "Preset", choice(EASINGS), "The curve moves follow (Preset: the Animations style)"),
	look("easingDirection", "Out", choice({ "In", "Out", "InOut" }), "Where the curve speeds up or slows down"),
	look("bezierX1", 0.25, num(0, 1), "Custom curve: first handle x"),
	look("bezierY1", 0.1, num(-1, 2), "Custom curve: first handle y"),
	look("bezierX2", 0.25, num(0, 1), "Custom curve: second handle x"),
	look("bezierY2", 1, num(-1, 2), "Custom curve: second handle y"),

	row("lockCameraTest", "Lock Camera (Test)", "Playback", 1, { desc = "The camera follows the recorded camera while testing" }),
	row("interpolatePlayback", "Interpolate Playback", "Playback", 1, { desc = "Blends between frames for smooth playback" }),
	row("playbackSpeed", "Playback Speed", "Playback", 1, { kind = NUM, nonzero = true, desc = "How fast Test plays the run (1 = normal)" }),
	row("restartWhenTesting", "Restart When Testing", "Playback", 1, { desc = "Test always starts from the first frame" }),
	row("showCompletionMessage", "Show Completion Message", "Playback", 1, { desc = "Shows TAS Completed when a test ends" }),

	row("lockCameraPaused", "Lock Camera (Paused)", "Create", 1, { desc = "The camera stays on the frame shown while paused" }),
	row("recordDeath", "Record Death & Respawn", "Create", 1, { desc = "Keeps recording through death and respawn" }),
	row("recordTools", "Record Tool Actions", "Create", 1, { desc = "Records equipping and using tools" }),
	row("ignoreGameProcessed", "Ignore Game Processed", "Create", 0, { desc = "Controls work even when the game took the key" }),

	row("speedHack", "Speed Hack", "Speed hack", 0, { desc = "Records in slow or fast motion" }),
	row("speedHackSpeed", "Speed Hack Speed", "Speed hack", 0.5, { kind = NUM, min = 0.1, max = 4, desc = "The speed hack's speed (0.1x to 4x)" }),
	row("speedHackFrameStep", "Speed Hack Frame Step", "Speed hack", 0, { desc = "Below 1x: normal physics on some steps, the world held on the others" }),

	row("replayKeyboard", "Replay Keyboard", "Inputs", 1, { desc = "Presses the recorded keys while testing" }),
	row("replayMouseClicks", "Replay Mouse Clicks", "Inputs", 1, { desc = "Presses the recorded mouse buttons while testing" }),
	row("replayMouseMovement", "Replay Mouse Movement", "Inputs", 1, { desc = "Moves the real mouse to the recorded spots while testing" }),
	row("normalizeMouseUV", "Normalize Mouse UV", "Inputs", 1, { desc = "Mouse positions follow the screen size" }),
	row("nohboardCursor", "NohBoard Cursor", "Inputs", 1, { desc = "Shows a cursor where the mouse is, for key overlays" }),
	row("invisibleMouseSpeed", "Invisible Mouse Speed Multiplier", "Inputs", 1, { kind = NUM, min = 0.01, max = 100, desc = "How fast the hidden mouse moves when the camera is locked" }),
	row("windowGuarding", "Window Guarding", "Inputs", 1, { desc = "Stops replayed input when the Roblox window isn't focused" }),

	row("syncClientObjects", "Sync Client Objects", "World sync", 0, { desc = "Records and replays the parts only you see" }),
	row("smoothClientObjects", "Smooth Client Objects", "World sync", 1, { desc = "Fills the gaps between client object frames smoothly" }),
	row("frustumCullingCO", "Frustum Culling CO", "World sync", 1, { desc = "Only records client objects on screen or close by" }),
	row("syncButtonTimers", "Sync Button Timers", "World sync", 1, { desc = "Timed buttons follow the TAS clock" }),
	row("syncLighting", "Sync Lighting", "World sync", 1, { desc = "Records and replays lighting changes" }),
	row("kitScriptsOnTasClock", "Kit Scripts On TAS Clock", "World sync", 1, { desc = "The EToH kit's scripts run on the TAS clock" }),
	row("syncKitObjects", "Sync Kit Objects", "World sync", 1, { desc = "Beat blocks, turrets and other kit objects follow TAS time" }),

	row("showStatsIdle", "Show Stats (Idle)", "Interface", 1, { desc = "Shows the stats in Idle" }),
	row("showStatsCreate", "Show Stats (Create)", "Interface", 1, { desc = "Shows the stats in Create" }),
	row("showStatsTest", "Show Stats (Test)", "Interface", 1, { desc = "Shows the stats while testing" }),
	row("statsTextSize", "Stats Text Size", "Interface", 11, { kind = NUM, min = 6, max = 30, integer = true, desc = "The size of the stats text" }),
	row("showMicroProfiler", "Show MicroProfiler", "Interface", 0, { desc = "Shows the MicroProfiler" }),
	row("microProfilerScale", "MicroProfiler Scale", "Interface", 1, { kind = NUM, min = 0.5, max = 4, desc = "The size of the MicroProfiler" }),
	row("microProfilerTextOffset", "MicroProfiler Text Offset", "Interface", 0, { kind = NUM, min = -6, max = 6, integer = true, desc = "Moves the MicroProfiler's text up or down" }),
	row("allowPlayerGuiInterface", "Allow PlayerGui Interface", "Interface", 0, { desc = "Lets the interface sit where game scripts can see it" }),
	-- (V2.38.16's 5 sound settings went with V2.38.17: a V2 Settings.json that has them converts without them)
}
-- the names the Settings window shows (a V2 row shows its V2 name)
local NAMES = {
	theme = "Theme", glass = "Glass", glassColor = "Glass colour", glassTransparency = "Glass transparency",
	blurStrength = "Blur strength", edgeLight = "Edge light", accentColor = "Accent colour", textColor = "Text colour",
	secondaryTextColor = "Secondary text colour", recordingColor = "Recording colour", font = "Font", numberFont = "Number font",
	textSize = "Text size", interfaceScale = "Interface scale", windowCorners = "Window corners", buttonShape = "Button shape",
	shadows = "Shadows", animations = "Animations", animationLength = "Animation length", easing = "Easing",
	easingDirection = "Easing direction", bezierX1 = "Curve x1", bezierY1 = "Curve y1", bezierX2 = "Curve x2", bezierY2 = "Curve y2",
}
Settings.byKey, Settings.byV2 = {}, {}
for i, r in ipairs(Settings.SCHEMA) do
	r.order = i
	r.name = NAMES[r.key] or r.v2
	Settings.byKey[r.key] = r
	if r.v2 then Settings.byV2[r.v2] = r end
end

-- nil when the value isn't allowed (V2 Settings.Sanitize)
local function hexColor(v)
	if type(v) ~= "string" then return nil end
	local h = v:match("^#?(%x+)$")
	if not h then return nil end
	if #h == 3 then h = h:sub(1, 1):rep(2) .. h:sub(2, 2):rep(2) .. h:sub(3, 3):rep(2) end
	if #h ~= 6 then return nil end
	return "#" .. h:upper()
end

function Settings.sanitize(def, v)
	if def.kind == "choice" then
		if type(v) ~= "string" then return nil end
		local low = v:lower()
		for _, o in ipairs(def.options) do
			if o:lower() == low then return o end
		end
		return nil
	elseif def.kind == "color" then
		return hexColor(v)
	elseif def.kind == "text" then
		if type(v) ~= "string" or #v > 40 then return nil end
		return v
	end
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
