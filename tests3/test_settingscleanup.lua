-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1: settings cleanup
--  * one "Sync Client Objects" switch (on by default) does what Smooth Client Objects, Frustum Culling CO,
--    Sync Button Timers, Sync Lighting, Kit Scripts On TAS Clock and Sync Kit Objects did
--  * MicroProfiler Text Offset (0), Allow PlayerGui Interface (off), Normalize Mouse UV (on) and Smooth Slow
--    Motion (on) are no settings any more: fixed values, not shown, not saved, not read from a file
--  * Invisible Mouse Speed Multiplier is "NohBoard Mouse Speed", at most 1 (the saved key stays)
--  * no Diagnostics: no button, no per-frame timing, no Diagnostics() command
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local s = E.settings
local Settings = __T3("engine/settings")
local Env = __T3("platform/env")
local Files = __T3("platform/files")
local Controls = __T3("engine/controls")
local SettingsFile = __T3("persist/settingsfile")
local Lifecycle = __T3("kernel/lifecycle")
local Errors = __T3("kernel/errors")
local HttpService = game:GetService("HttpService")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end

local FOLLOW = { "smoothClientObjects", "frustumCullingCO", "syncButtonTimers", "syncLighting", "kitScriptsOnTasClock", "syncKitObjects" }
local FIXED = { microProfilerTextOffset = 0, allowPlayerGuiInterface = 0, normalizeMouseUV = 1, smoothSlowMotion = 1 }
local HIDDEN = {}
for _, k in ipairs(FOLLOW) do HIDDEN[k] = true end
for k in pairs(FIXED) do HIDDEN[k] = true end

section("one Sync Client Objects switch, on by default")
eq(Settings.byKey.syncClientObjects.default, 1, "on by default")
local fresh = Settings.new(Errors.new(function() end))
for _, k in ipairs(FOLLOW) do eq(fresh:get(k), 1, k .. " on with it") end
fresh:set("syncClientObjects", 0)
for _, k in ipairs(FOLLOW) do eq(fresh:get(k), 0, k .. " off with it") end
fresh:set("syncClientObjects", 1)
for _, k in ipairs(FOLLOW) do eq(fresh:get(k), 1, k .. " on again") end
for k, v in pairs(FIXED) do eq(fresh:get(k), v, k .. " fixed at " .. v) end

section("not shown anywhere")
UIH.click(ui.dock.buttons.settings.gui)
local sw = ui.settingsWin
for k in pairs(HIDDEN) do eq(sw.rows[k], nil, k .. ": no row in the Settings window") end
check(sw.rows.syncClientObjects ~= nil, "Sync Client Objects has its row")
eq(sw.diag, nil, "no Diagnostics button")
s:set("interface", "Classic")
M.steps(2)
local c = ui.classic
local clist = c.byPath["MainMenu.SettingsFrame.List"]
for k in pairs(HIDDEN) do eq(clist:FindFirstChild(k, true), nil, k .. ": no row in Classic") end
check(clist:FindFirstChild("syncClientObjects", true) ~= nil, "Classic's Sync Client Objects row")
s:set("interface", "New")
M.steps(2)

section("NohBoard Mouse Speed")
local ims = Settings.byKey.invisibleMouseSpeed
eq(ims.name, "NohBoard Mouse Speed", "the new name")
eq(ims.v2, "Invisible Mouse Speed Multiplier", "V2's name kept for old files")
eq(ims.max, 1, "at most 1")
s:set("invisibleMouseSpeed", 5)
eq(s:get("invisibleMouseSpeed"), 1, "5 becomes 1")
s:set("invisibleMouseSpeed", 0.1)
check(sw.rows.invisibleMouseSpeed ~= nil and UIH.find(sw.rows.invisibleMouseSpeed.row.gui, "NohBoard Mouse Speed") ~= nil, "the Settings window shows it")

section("no Diagnostics")
local h = getgenv().__HappaTAS3
eq(h and h.Diagnostics, nil, "no Diagnostics() command")
local found = false
for _, stage in pairs(E.pipe.stages or {}) do
	for _, hd in ipairs(stage.list or stage) do if type(hd) == "table" and tostring(hd.name or ""):find("diagnostics") then found = true end end
end
eq(found, false, "no per-frame diagnostics handler")

section("the settings file")
local files = Files.new(Env)
local V3_PATH = "HappaTasPort/Settings3.json"
local function load(settingsTable)
	files:write(V3_PATH, HttpService:JSONEncode({ format = "HappaTAS3 settings", version = 1, settings = settingsTable, controls = {} }))
	local st = Settings.new(Errors.new(function() end))
	local sf = SettingsFile.new(files, st, Controls.new(), Lifecycle.new("cleanup test"))
	sf:load()
	return st, sf
end
local saved = files:read(V3_PATH)
-- an old file: client objects off (the old default) but its other world settings on -> the switch is on
local st = load({ syncClientObjects = 0, syncLighting = 1, syncButtonTimers = 1, microProfilerTextOffset = 3,
	smoothSlowMotion = 0, normalizeMouseUV = 0, allowPlayerGuiInterface = 1, invisibleMouseSpeed = 40 })
eq(st:get("syncClientObjects"), 1, "old file, its world settings on: Sync Client Objects on")
eq(st:get("syncLighting"), 1, "lighting still synced")
for k, v in pairs(FIXED) do eq(st:get(k), v, k .. " ignored in the file") end
eq(st:get("invisibleMouseSpeed"), 1, "an old speed above 1 loads as 1")
st = load({ syncClientObjects = 0, smoothClientObjects = 0, frustumCullingCO = 0, syncButtonTimers = 0, syncLighting = 0,
	kitScriptsOnTasClock = 0, syncKitObjects = 0 })
eq(st:get("syncClientObjects"), 0, "old file with all of them off: off")
st = load({ syncClientObjects = 0 })
eq(st:get("syncClientObjects"), 0, "a new file with the switch off: off")
for _, k in ipairs(FOLLOW) do eq(st:get(k), 0, k .. " follows it") end
local st2, sf2 = load({ syncClientObjects = 1 })
sf2:write()
local out = HttpService:JSONDecode(files:read(V3_PATH))
for k in pairs(HIDDEN) do eq(out.settings[k], nil, k .. " not saved") end
eq(out.settings.syncClientObjects, 1, "the switch is saved")
eq(out.version, 1, "the file's version is unchanged")
if saved then files:write(V3_PATH, saved) end
finish()
