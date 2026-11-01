-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 6: the MicroProfiler's config from the settings file (SettingsFile:getProfiler): a damaged
-- profiler table and no table at all open with defaults, never an error; the config is saved back there
-- (headless mock)
-- ================================================================================================
local SETTINGS3 = "HappaTasPort/Settings3.json"
M.fs[SETTINGS3] = '{"format":"HappaTAS3 settings","version":1,"settings":{"showMicroProfiler":1},"controls":{},'
	.. '"profiler":{"mode":"Nope","aggregate":"x","ref":-3,"bars":"y","groups":5,"custom":"z","fg":999,"bg":-1,'
	.. '"presets":{"Preset 1":"broken","Preset 2":{"mode":7}}}}'

section("a damaged profiler table: defaults, no error")
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local P = E.profiler
check(type(E.settingsFile.getProfiler) == "function", "SettingsFile:getProfiler")
check(type(E.settingsFile:getProfiler()) == "table", "the table as it was loaded")
check(P.active, "the profiler opens (Show MicroProfiler 1)")
M.steps(10, 16 / 1000)
local c = P.Config()
check(c.mode == "Frame" or c.mode == "Detailed" or c.mode == "Timers" or c.mode == "Counters" or c.mode == "Hidden",
	"a known mode (" .. tostring(c.mode) .. ")")
check(type(c.ref) == "number" and c.ref > 0, "a reference time above 0 (" .. tostring(c.ref) .. ")")
check(type(c.aggregate) == "number", "an aggregate number")
check(type(c.groups) == "table" and type(c.groups.Engine) == "boolean", "groups as booleans")
check(type(c.bars) == "number", "a bar column mask")
check(P.Snapshot().recorded > 0, "frames recorded")

section("saved back into the settings file")
P.SaveConfig()
M.steps(60, 1 / 60)
local saved = M.JSON.decode(M.fs[SETTINGS3])
check(type(saved.profiler) == "table" and saved.profiler.mode == c.mode, "the clean config written to Settings3.json")
check(saved.settings and saved.settings.showMicroProfiler == 1, "the settings kept")

section("no profiler table: defaults")
M.fs[SETTINGS3] = '{"format":"HappaTAS3 settings","version":1,"settings":{"showMicroProfiler":1},"controls":{}}'
check(boot(30), "runs again")
E = getgenv().__HappaTAS3_T.engine
P = E.profiler
eq(E.settingsFile:getProfiler(), nil, "nothing loaded")
check(P.active, "opens")
M.steps(10, 16 / 1000)
check(P.Snapshot().recorded > 0, "frames recorded")
getgenv().__HappaTAS3.Unload()
M.steps(3)
finish()
