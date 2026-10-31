-- needs: fsfail
-- ================================================================================================
-- HappaTAS 3, phase 3: the settings file (Settings3.json; converted once from V2's Settings.json, which is
-- never written; autosave 0.4 s after a change; flushed on Unload)
-- ================================================================================================
check(boot(3), "boots")
local Env = __T3("platform/env")
local Files = __T3("platform/files")
local Settings = __T3("engine/settings")
local Controls = __T3("engine/controls")
local SettingsFile = __T3("persist/settingsfile")
local Lifecycle = __T3("kernel/lifecycle")
local Errors = __T3("kernel/errors")
local HttpService = game:GetService("HttpService")

-- (the fixture: a V2 Settings.json with every V2 name, the 5 sound settings too, every control, a profiler)
local V2_JSON = [=[{"controls":{"MicroProfiler":"F6","Forward 1 Frame":"G","Delete TAS":"Backspace","Back":"Q","Unpause":"E","Idle":"1","Return":"'","Toggle Speed Hack":"None","Create":"2","Test":"3","Pause":"E","Forward":"T","Back 1 Frame":"F","Unpause 1 Frame":"V","Look Around":"L","Optimize TAS":"]","Menu":"M"},"settings":{"Lock Camera (Test)":1,"Interpolate Playback":1,"Playback Speed":1.5,"Restart When Testing":0,"Show Completion Message":1,"Lock Camera (Paused)":1,"Record Death & Respawn":1,"Record Tool Actions":0,"Ignore Game Processed":1,"Speed Hack":0,"Speed Hack Speed":0.25,"Speed Hack Frame Step":1,"Replay Keyboard":1,"Replay Mouse Clicks":0,"Replay Mouse Movement":1,"Normalize Mouse UV":1,"NohBoard Cursor":0,"Invisible Mouse Speed Multiplier":2,"Window Guarding":1,"Sync Client Objects":1,"Smooth Client Objects":1,"Frustum Culling CO":0,"Sync Button Timers":1,"Sync Lighting":1,"Kit Scripts On TAS Clock":1,"Sync Kit Objects":0,"Show Stats (Idle)":0,"Show Stats (Create)":1,"Show Stats (Test)":1,"Stats Text Size":14,"Show MicroProfiler":1,"MicroProfiler Scale":1.25,"MicroProfiler Text Offset":-2,"Allow PlayerGui Interface":0,"Enable Keyboard Sounds":1,"Enable Click Sounds":0,"Sound Trigger Mode":2,"Sound Volume":70,"Dynamic Pitch Variation":1},"profiler":{"mode":"Frame","aggregate":"Infinite","custom":{"tasTimeline":true},"presets":[{"name":"one","groups":["Render"]}]}}]=]
local V2 = HttpService:JSONDecode(V2_JSON)

local files = Files.new(Env)
local V2_PATH, V3_PATH, DAMAGED = "HappaTasPort/Settings.json", "HappaTasPort/Settings3.json", "HappaTasPort/Settings3.damaged.json"
files:makeFolder("HappaTasPort")

local printed = {}
local errs = Errors.new(function(m) printed[#printed + 1] = m end)
local function fresh()
	local life = Lifecycle.new("settingsfile test")
	local s, c = Settings.new(errs), Controls.new()
	return SettingsFile.new(files, s, c, life), s, c, life
end
local function wait(seconds)
	local t = 0
	while t < seconds do M.step(1 / 60); t = t + 1 / 60 end
end
local function writes(pattern) return FSFAIL.count("write", pattern) end

section("converted from V2's Settings.json")
files:delete(V3_PATH)
files:write(V2_PATH, V2_JSON)
FSFAIL.log = {}
local sf, s, c, life = fresh()
eq(sf:load(), "v2", "source v2")
for name, v in pairs(V2.settings) do
	local def = Settings.byV2[name]
	if def then
		eq(s:get(def.key), Settings.sanitize(def, v), "setting " .. name)
	end
end
eq(s:get("playbackSpeed"), 1.5, "Playback Speed 1.5")
eq(s:get("microProfilerTextOffset"), -2, "a negative value")
for name, keyName in pairs(V2.controls) do
	local ctl = Controls.byV2[name]
	check(ctl ~= nil, "control known: " .. name)
	if ctl then eq(c:get(ctl.key), keyName, "control " .. name) end
end
check(sf.profiler and sf.profiler.mode == "Frame" and sf.profiler.presets[1].name == "one", "profiler kept")
eq(#printed, 0, "the sound settings are dropped without an error")
check(files:exists(V3_PATH), "Settings3.json written at once")
local v3 = HttpService:JSONDecode(files:read(V3_PATH))
eq(v3.format, "HappaTAS3 settings", "format")
eq(v3.version, 1, "version")
eq(v3.settings.playbackSpeed, 1.5, "saved by key")
eq(v3.controls.optimize, "]", "controls saved by key")
eq(v3.settings.soundVolume, nil, "no sound settings in it")
eq(v3.profiler.aggregate, "Infinite", "profiler saved")
eq(files:read(V2_PATH), V2_JSON, "Settings.json unchanged")
eq(writes("/Settings%.json$"), 0, "Settings.json never written")

section("autosave: one write 0.4 s after a burst of changes")
FSFAIL.log = {}
for i = 1, 5 do
	s:set("playbackSpeed", 1 + i / 10)
	M.step(0.02)
end
c:set("pause", "Q")
eq(writes("Settings3%.json$"), 0, "not yet")
wait(0.5)
eq(writes("Settings3%.json$"), 1, "one write")
local saved = HttpService:JSONDecode(files:read(V3_PATH))
eq(saved.settings.playbackSpeed, 1.5, "the last value")
eq(saved.controls.pause, "Q", "the control")
sf:setProfiler({ mode = "Detailed" })
wait(0.5)
eq(HttpService:JSONDecode(files:read(V3_PATH)).profiler.mode, "Detailed", "setProfiler saves too")
eq(files:read(V2_PATH), V2_JSON, "Settings.json still unchanged")

section("Unload within 0.4 s still saves")
FSFAIL.log = {}
s:set("syncLighting", 0)
M.step(0.05)
life:cleanup()
eq(writes("Settings3%.json$"), 1, "written on Unload")
eq(HttpService:JSONDecode(files:read(V3_PATH)).settings.syncLighting, 0, "with the change")
s:set("syncLighting", 1)
wait(0.5)
eq(writes("Settings3%.json$"), 1, "no saving after Unload")

section("the next start reads Settings3.json, even when Settings.json changed")
files:write(V2_PATH, '{"settings":{"Playback Speed":3}}')
local sf2, s2, c2 = fresh()
eq(sf2:load(), "v3", "source v3")
eq(s2:get("playbackSpeed"), 1.5, "v3's value, not V2's")
eq(c2:get("pause"), "Q", "v3's control")
eq(s2:get("syncLighting"), 0, "the value saved on Unload")
check(sf2.profiler and sf2.profiler.mode == "Detailed", "profiler from v3")

section("bad values (Review focus 4)")
files:delete(V3_PATH)
files:write(V2_PATH, '{"settings":{"Playback Speed":"fast","Stats Text Size":999,"Speed Hack":"yes","Nope":1},"controls":{"Pause":"Banana","Create":5,"Nope":"E"}}')
local sf3, s3, c3 = fresh()
eq(sf3:load(), "v2", "converted")
eq(s3:get("playbackSpeed"), 1, "'fast' -> default")
eq(s3:get("statsTextSize"), 30, "999 -> clamped to 30")
eq(s3:get("speedHack"), 0, "'yes' -> default")
eq(c3:get("pause"), "Left Click", "'Banana' -> default key")
eq(c3:get("create"), "2", "a number -> default key")
eq(sf3.profiler, nil, "no profiler")
eq(#printed, 0, "no errors")

section("a damaged Settings3.json is kept aside")
files:write(V3_PATH, "{not json")
files:write(V2_PATH, V2_JSON)
local sf4, s4 = fresh()
eq(sf4:load(), "v2", "converted again from Settings.json")
eq(files:read(DAMAGED), "{not json", "the damaged file kept as Settings3.damaged.json")
eq(HttpService:JSONDecode(files:read(V3_PATH)).format, "HappaTAS3 settings", "a good Settings3.json again")
eq(s4:get("playbackSpeed"), 1.5, "values from Settings.json")
files:write(V3_PATH, '{"format":"something else"}')
local sf5 = fresh()
eq(sf5:load(), "v2", "a JSON table of another format counts as damaged too")

section("nothing at all: defaults, nothing written")
files:delete(V3_PATH)
files:delete(V2_PATH)
FSFAIL.log = {}
local sf6, s6 = fresh()
eq(sf6:load(), "defaults", "defaults")
eq(s6:get("playbackSpeed"), 1, "default value")
eq(writes("Settings3%.json$"), 0, "nothing written until a change")
s6:set("playbackSpeed", 2)
wait(0.5)
eq(writes("Settings3%.json$"), 1, "written after a change")

section("a V2 Settings.json converts with the Appearance defaults (phase 5a)")
files:delete(V3_PATH)
files:write(V2_PATH, V2_JSON)
do
	local sf7, s7 = fresh()
	eq(sf7:load(), "v2", "converted")
	eq(s7:get("glass"), "Tint", "glass default")
	eq(s7:get("accentColor"), "#3F7CF0", "accent default")
	eq(s7:get("font"), "BuilderSans", "font default")
	local v3j = HttpService:JSONDecode(files:read(V3_PATH))
	eq(v3j.settings.accentColor, "#3F7CF0", "strings saved")
	eq(v3j.settings.textSize, 13, "numbers saved")
	local ui = sf7:getUi()
	check(type(ui) == "table" and type(ui.themes) == "table" and type(ui.layout) == "table" and type(ui.recentColors) == "table",
		"getUi: an empty table set, never nil")
end

section("the ui table round trip (phase 5a)")
do
	local sf8, s8 = fresh()
	sf8:load()
	local ui = sf8:getUi()
	ui.themes["Night"] = { accentColor = "#FF00AA", glass = "Clear" }
	ui.layout["1920x1080"] = { settings = { x = 40, y = 60, w = 420, h = 640, min = false } }
	local colors = {}
	for i = 1, 9 do colors[i] = string.format("#%02X0000", i) end
	ui.recentColors = colors
	sf8:setUi(ui)
	s8:set("glass", "Frost")
	wait(0.5)
	local j = HttpService:JSONDecode(files:read(V3_PATH))
	eq(j.settings.glass, "Frost", "a choice saved")
	eq(j.ui.themes.Night.accentColor, "#FF00AA", "a theme saved")
	eq(j.ui.layout["1920x1080"].settings.w, 420, "a layout saved")
	eq(#j.ui.recentColors, 8, "at most 8 recent colours")
	eq(j.ui.recentColors[1], "#010000", "the newest first, the oldest dropped")
	local sf9, s9 = fresh()
	eq(sf9:load(), "v3", "read back")
	eq(s9:get("glass"), "Frost", "the choice read back")
	local ui9 = sf9:getUi()
	eq(ui9.themes.Night.glass, "Clear", "theme read back")
	eq(ui9.layout["1920x1080"].settings.x, 40, "layout read back")
	eq(#ui9.recentColors, 8, "recent colours read back")
end

section("an older Settings3.json without ui loads (phase 5a)")
do
	files:write(V3_PATH, '{"format":"HappaTAS3 settings","version":1,"settings":{"playbackSpeed":2},"controls":{}}')
	local sf10, s10 = fresh()
	eq(sf10:load(), "v3", "loaded")
	eq(s10:get("playbackSpeed"), 2, "its value")
	local ui = sf10:getUi()
	check(next(ui.themes) == nil and next(ui.layout) == nil and #ui.recentColors == 0, "an empty ui table")
	files:write(V3_PATH, '{"format":"HappaTAS3 settings","version":1,"settings":{},"controls":{},"ui":{"themes":"bad","layout":5,"recentColors":["#123456","nope",7]}}')
	local sf11 = fresh()
	sf11:load()
	local ui11 = sf11:getUi()
	check(next(ui11.themes) == nil and next(ui11.layout) == nil, "bad parts dropped")
	eq(table.concat(ui11.recentColors, ","), "#123456", "only real colours kept")
	eq(#printed, 0, "no errors")
end
finish()
