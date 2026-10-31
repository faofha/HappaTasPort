-- ================================================================================================
-- HappaTAS 3, phase 2: settings schema, controls, key names, the typing check
-- ================================================================================================
check(boot(3), "boots")
local Settings = __T3("engine/settings")
local Controls = __T3("engine/controls")
local Keys = __T3("engine/keys")
local Typing = __T3("platform/typing")
local Util = __T3("engine/util")
local Errors = __T3("kernel/errors")
local Lifecycle = __T3("kernel/lifecycle")

section("every V2 setting is in the schema")
local V2_NAMES = {
	"Lock Camera (Test)", "Interpolate Playback", "Playback Speed", "Restart When Testing", "Show Completion Message",
	"Lock Camera (Paused)", "Record Death & Respawn", "Record Tool Actions", "Ignore Game Processed",
	"Speed Hack", "Speed Hack Speed", "Speed Hack Frame Step",
	"Replay Keyboard", "Replay Mouse Clicks", "Replay Mouse Movement", "Normalize Mouse UV", "NohBoard Cursor",
	"Invisible Mouse Speed Multiplier", "Window Guarding",
	"Sync Client Objects", "Smooth Client Objects", "Frustum Culling CO", "Sync Button Timers", "Sync Lighting",
	"Kit Scripts On TAS Clock", "Sync Kit Objects",
	"Show Stats (Idle)", "Show Stats (Create)", "Show Stats (Test)", "Stats Text Size", "Show MicroProfiler",
	"MicroProfiler Scale", "MicroProfiler Text Offset", "Allow PlayerGui Interface",
}
local v2Rows = 0
for _, row in ipairs(Settings.SCHEMA) do if row.v2 then v2Rows = v2Rows + 1 end end
eq(v2Rows, 34, "34 V2 rows (V2.38.16's 39 without the 5 sound settings V2.38.17 removed)")
for _, gone in ipairs({ "Enable Keyboard Sounds", "Enable Click Sounds", "Sound Trigger Mode", "Sound Volume", "Dynamic Pitch Variation" }) do
	eq(Settings.byV2[gone], nil, "no sound setting: " .. gone)
end
local seenV2, seenKey = {}, {}
for _, row in ipairs(Settings.SCHEMA) do
	check(not seenKey[row.key], "unique key " .. tostring(row.key))
	seenKey[row.key] = true
	if row.v2 then seenV2[row.v2] = (seenV2[row.v2] or 0) + 1 end -- (Appearance rows have no V2 name)
end
for _, n in ipairs(V2_NAMES) do eq(seenV2[n], 1, "V2 name in the schema once: " .. n) end
eq(Settings.byV2["Lock Camera (Test)"].key, "lockCameraTest", "byV2")
eq(Settings.byV2["Invisible Mouse Speed Multiplier"].key, "invisibleMouseSpeed", "byV2 (shortened key)")

section("defaults are V2's")
local errsPrinted = {}
local errs = Errors.new(function(m) errsPrinted[#errsPrinted + 1] = m end)
local s = Settings.new(errs)
eq(s:get("playbackSpeed"), 1, "playbackSpeed")
eq(s:get("ignoreGameProcessed"), 0, "ignoreGameProcessed")
eq(s:get("speedHackSpeed"), 0.5, "speedHackSpeed")
eq(s:get("statsTextSize"), 11, "statsTextSize")
eq(s:get("syncClientObjects"), 0, "syncClientObjects")
eq(s:on("lockCameraTest"), true, "lockCameraTest on")
eq(s:on("speedHack"), false, "speedHack off")

section("sanitise")
check(s:set("speedHack", 5), "toggle set")
eq(s:get("speedHack"), 1, "toggle 5 -> 1")
s:set("speedHackSpeed", 9); eq(s:get("speedHackSpeed"), 4, "max 4")
s:set("speedHackSpeed", 0.01); eq(s:get("speedHackSpeed"), 0.1, "min 0.1")
s:set("statsTextSize", 11.6); eq(s:get("statsTextSize"), 12, "integer rounding")
eq(s:set("playbackSpeed", 0), false, "playbackSpeed 0 refused")
eq(s:get("playbackSpeed"), 1, "unchanged")
eq(s:set("playbackSpeed", 0 / 0), false, "NaN refused")
eq(s:set("playbackSpeed", math.huge), false, "inf refused")
eq(s:set("noSuchSetting", 1), false, "unknown key refused")

section("listeners")
local calls = 0
local off = s:changed("playbackSpeed", function(v) calls = calls + 1 end)
s:changed("playbackSpeed", function() error("listener broke") end)
local after = 0
s:changed("playbackSpeed", function() after = after + 1 end)
s:set("playbackSpeed", 2)
s:set("playbackSpeed", 2)
eq(calls, 1, "called once per change, not for an equal value")
eq(after, 1, "a listener after a failing one still runs")
s:set("playbackSpeed", 3)
local n = 0
for _, m in ipairs(errsPrinted) do if m:find("listener broke", 1, true) then n = n + 1 end end
eq(n, 1, "the failing listener is reported once")
off()
s:set("playbackSpeed", 4)
eq(calls, 2, "off() removes a listener")

section("controls")
local c = Controls.new()
eq(#Controls.LIST, 17, "17 controls")
local want = {
	idle = "1", create = "2", test = "3", pause = "Left Click", unpause = "Left Click", forward = "T", back = "R",
	forward1 = "G", back1 = "F", unpause1 = "V", ["return"] = "E", lookAround = "L", optimize = "Q",
	deleteTas = "Backspace", menu = "M", microProfiler = "F6", toggleSpeedHack = "None",
}
for k, v in pairs(want) do eq(c:get(k), v, "default key of " .. k) end
local function key(kc) return M.input(Enum.UserInputType.Keyboard, kc, Enum.UserInputState.Begin) end
check(c:matches(key(Enum.KeyCode.Two), "create"), "2 matches create")
check(not c:matches(key(Enum.KeyCode.Three), "create"), "3 doesn't match create")
check(c:matches(M.input(Enum.UserInputType.MouseButton1), "pause"), "Left Click matches pause")
check(not c:matches(key(Enum.KeyCode.Unknown), "toggleSpeedHack"), "None never matches")
c:set("create", "K")
check(c:matches(key(Enum.KeyCode.K), "create"), "rebound key matches")
eq(Keys.toKey["Num5"], Enum.KeyCode.KeypadFive, "key names: Num5")
eq(Keys.fromKey[Enum.KeyCode.Two], "2", "key names: Two -> 2")
eq(Controls.byV2["Unpause 1 Frame"].key, "unpause1", "controls byV2")

section("util")
eq(Util.round(-0.0001, 1000), 0, "round -0 -> 0")
check(1 / Util.round(-0.0001, 1000) > 0, "really +0")
eq(Util.round(1.23456, 1000), 1.235, "round to 1/1000")
eq(Util.toTime(65.5), "1:05.5", "toTime")
eq(Util.toTime(5), "0:05", "toTime whole seconds")

section("typing")
local life = Lifecycle.new()
local t = Typing.new(life)
local UIS = M.services.UserInputService
eq(t:active(nil), false, "nothing focused")
local hui = Instance.new("ScreenGui"); hui.Parent = M.hui -- (under gethui(), like our interface)
local ownBox = Instance.new("TextBox"); ownBox.Parent = hui
t:watch(hui)
M.focus(ownBox)
eq(UIS:GetFocusedTextBox(), nil, "GetFocusedTextBox doesn't see our box")
eq(t:active(nil), true, "our own box focused")
M.focus(nil)
eq(t:active(nil), false, "lost focus")
local later = Instance.new("TextBox"); later.Parent = hui
M.focus(later)
eq(t:active(nil), true, "a box added later counts too")
M.focus(nil)
local pg = M.player:FindFirstChildOfClass("PlayerGui")
local sg = Instance.new("ScreenGui"); sg.Parent = pg
local gameBox = Instance.new("TextBox"); gameBox.Parent = sg
M.focus(gameBox)
eq(t:active(nil), true, "a game text box")
M.focus(nil)
M.chatBar.IsFocused = true
eq(t:active(nil), true, "the chat bar")
M.chatBar.IsFocused = false
M.services.GuiService.MenuIsOpen = true
eq(t:active(nil), true, "the Roblox menu")
M.services.GuiService.MenuIsOpen = false
t.rebinding = true
eq(t:active(nil), true, "rebinding")
t.rebinding = false
local inp = key(Enum.KeyCode.Q)
t.boundInput = inp
eq(t:active(inp), true, "the input that set a new key")
eq(t:active(key(Enum.KeyCode.W)), false, "another input")
life:cleanup()
section("phase 3: onAny and Controls:changed (the settings file saves on them)")
do
	local s2 = Settings.new(errs)
	local seen = {}
	local off = s2:onAny(function(key, v) seen[#seen + 1] = key .. "=" .. tostring(v) end)
	s2:set("playbackSpeed", 2)
	s2:set("playbackSpeed", 2)
	s2:set("syncLighting", 0)
	s2:set("nope", 1)
	eq(table.concat(seen, ","), "playbackSpeed=2,syncLighting=0", "onAny: each change once, nothing for no change / unknown")
	off()
	s2:set("playbackSpeed", 3)
	eq(#seen, 2, "removed")
	local c = Controls.new()
	local got = {}
	local offC = c:changed(function(control, keyName) got[#got + 1] = control .. "=" .. keyName end)
	c:set("pause", "E")
	c:set("pause", "E")
	c:set("pause", "Banana")
	c:set("nope", "E")
	eq(table.concat(got, ","), "pause=E", "Controls:changed: a real change only")
	offC()
	c:set("pause", "Q")
	eq(#got, 1, "removed")
end

section("choice / color / text kinds sanitise (phase 5a)")
do
	local sa = Settings.sanitize
	local glass, accent, theme = Settings.byKey.glass, Settings.byKey.accentColor, Settings.byKey.theme
	check(glass and accent and theme, "the rows exist")
	eq(glass.kind, "choice", "glass is a choice")
	eq(sa(glass, "tint"), "Tint", "a choice matches case-insensitively, canonical name back")
	eq(sa(glass, "Frost"), "Frost", "Frost")
	eq(sa(glass, "Glassy"), nil, "an unknown option refused")
	eq(sa(glass, 2), nil, "a number for a choice refused")
	eq(accent.kind, "color", "accentColor is a color")
	eq(sa(accent, "3f7cf0"), "#3F7CF0", "RRGGBB without # -> #RRGGBB upper case")
	eq(sa(accent, "#3f7cf0"), "#3F7CF0", "#rrggbb")
	eq(sa(accent, "#3F7"), "#33FF77", "#RGB widened")
	eq(sa(accent, "#12"), nil, "#12 refused")
	eq(sa(accent, "#GG0000"), nil, "not hex refused")
	eq(theme.kind, "text", "theme is text")
	eq(sa(theme, "My look"), "My look", "text kept")
	eq(sa(theme, string.rep("a", 41)), nil, "41 characters refused")
	eq(sa(theme, string.rep("a", 40)), string.rep("a", 40), "40 characters kept")
	local s3 = Settings.new()
	check(s3:set("glass", "frost"), "set a choice")
	eq(s3:get("glass"), "Frost", "get returns the string")
	eq(s3:set("accentColor", "nope"), false, "a bad colour refused by set")
	eq(s3:get("accentColor"), "#3F7CF0", "unchanged")
	local fired = 0
	s3:changed("glassColor", function() fired = fired + 1 end)
	s3:set("glassColor", "#242a38")
	eq(fired, 0, "the same colour in another case is no change")
end

section("appearance defaults (phase 5a)")
do
	local want = {
		theme = "Default", glass = "Tint", glassColor = "#242A38", glassTransparency = 54, blurStrength = 70, edgeLight = 16,
		accentColor = "#3F7CF0", textColor = "#FFFFFF", secondaryTextColor = "#B4BBC8", recordingColor = "#FF5A5A",
		font = "BuilderSans", numberFont = "RobotoMono", textSize = 13, interfaceScale = 100, windowCorners = 16,
		buttonShape = "Pill", shadows = 1, animations = "Smooth", animationLength = 0.2, easing = "Preset",
		easingDirection = "Out", bezierX1 = 0.25, bezierY1 = 0.1, bezierX2 = 0.25, bezierY2 = 1,
	}
	local s4 = Settings.new()
	local n = 0
	for key, v in pairs(want) do
		n = n + 1
		local def = Settings.byKey[key]
		check(def ~= nil, "row " .. key)
		if def then
			eq(def.section, "Appearance", key .. " in Appearance")
			eq(def.default, v, key .. " default")
			eq(s4:get(key), v, key .. " value")
			eq(def.v2, nil, key .. " has no V2 name")
		end
	end
	eq(n, 25, "25 appearance rows")
	local ranges = { glassTransparency = { 0, 100 }, blurStrength = { 0, 100 }, edgeLight = { 0, 100 }, textSize = { 8, 24 },
		interfaceScale = { 50, 200 }, windowCorners = { 0, 24 }, animationLength = { 0.05, 1 }, bezierX1 = { 0, 1 },
		bezierY1 = { -1, 2 }, bezierX2 = { 0, 1 }, bezierY2 = { -1, 2 } }
	for key, r in pairs(ranges) do
		local def = Settings.byKey[key]
		eq(def.min, r[1], key .. " min")
		eq(def.max, r[2], key .. " max")
	end
	for _, key in ipairs({ "glassTransparency", "blurStrength", "edgeLight", "textSize", "interfaceScale", "windowCorners" }) do
		eq(Settings.byKey[key].integer, true, key .. " is an integer")
	end
	local opts = function(key) return table.concat(Settings.byKey[key].options, ",") end
	eq(opts("glass"), "Clear,Tint,Frost", "glass options")
	eq(opts("buttonShape"), "Pill,Rounded,Square", "button shapes")
	eq(opts("animations"), "Off,Smooth,Snappy,Bouncy", "animations")
	eq(opts("easing"), "Preset,Linear,Sine,Quad,Cubic,Quart,Quint,Exponential,Circular,Back,Elastic,Bounce,Custom", "easing")
	eq(opts("easingDirection"), "In,Out,InOut", "easing direction")
	eq(table.concat(Settings.FONTS, ","), "BuilderSans,GothamSSm,SourceSansPro,Roboto,Montserrat,Nunito,Ubuntu,FredokaOne,Oswald,Merriweather,RobotoMono,Inconsolata", "fonts")
	eq(opts("font"), table.concat(Settings.FONTS, ","), "font options are the fonts")
	eq(opts("numberFont"), table.concat(Settings.FONTS, ","), "number font options are the fonts")
	eq(Settings.byKey.glass.order < Settings.byKey.lockCameraTest.order, true, "Appearance comes first (spec 8.3's section order)")
end

section("every row has a desc (phase 5a)")
for _, row in ipairs(Settings.SCHEMA) do
	check(type(row.desc) == "string" and #row.desc >= 8 and #row.desc <= 90, "desc for " .. row.key .. " (" .. tostring(row.desc) .. ")")
end

finish()
