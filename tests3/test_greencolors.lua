-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1: green defaults for the New interface
--  * accent #3FB950 (was #3F7CF0), glass #232B26 (was #242A38), the switch knob's shine #ECFFF2 (was #ECF2FF)
--  * a settings file with the old default blue (exactly #3F7CF0 / #242A38) counts as never customised: it loads
--    as the new default; any other saved colour stays
--  * Classic keeps V2's blue
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
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

section("the new defaults")
eq(Settings.byKey.accentColor.default, "#3FB950", "accent green")
eq(Settings.byKey.glassColor.default, "#232B26", "glass dark green-grey")
local fresh = Settings.new(Errors.new(function() end))
eq(fresh:get("accentColor"), "#3FB950", "a fresh store: green accent")
eq(fresh:get("glassColor"), "#232B26", "and green-grey glass")

section("the switch knob")
E.settings:set("accentColor", "#3FB950")
E.settings:set("glassColor", "#232B26")
ui.wm:open("settings")
M.steps(2)
local knobGrad
for _, d in ipairs(ui.settingsWin.gui and ui.settingsWin.gui:GetDescendants() or ui.root.layer:GetDescendants()) do
	if d:IsA("UIGradient") and d.Parent and d.Parent.Name == "Knob" then knobGrad = d end
end
check(knobGrad ~= nil, "a switch knob with its shine")
if knobGrad then
	local kps = knobGrad.Color.Keypoints
	eq(kps[#kps].Value, Color3.fromHex("ECFFF2"), "the shine ends green-white")
end
ui.wm:close("settings")
eq(ui.theme.c.accent, Color3.fromHex("3FB950"), "the theme's accent")
eq(ui.theme.c.glass, Color3.fromHex("232B26"), "the theme's glass")

section("an old file with the old default blue loads green")
local files = Files.new(Env)
local V3_PATH = "HappaTasPort/Settings3.json"
local saved = files:read(V3_PATH)
local function load(t)
	files:write(V3_PATH, HttpService:JSONEncode({ format = "HappaTAS3 settings", version = 1, settings = t, controls = {} }))
	local st = Settings.new(Errors.new(function() end))
	SettingsFile.new(files, st, Controls.new(), Lifecycle.new("green test")):load()
	return st
end
local st = load({ accentColor = "#3F7CF0", glassColor = "#242A38" })
eq(st:get("accentColor"), "#3FB950", "#3F7CF0 (never changed) -> the new green")
eq(st:get("glassColor"), "#232B26", "#242A38 (never changed) -> the new glass")
st = load({ accentColor = "#3f7cf0", glassColor = "#242a38" })
eq(st:get("accentColor"), "#3FB950", "lower case too")
eq(st:get("glassColor"), "#232B26", "lower case glass too")
st = load({ accentColor = "#FF0000", glassColor = "#101010" })
eq(st:get("accentColor"), "#FF0000", "a chosen accent stays")
eq(st:get("glassColor"), "#101010", "a chosen glass stays")
st = load({ accentColor = "#3F7CF1" })
eq(st:get("accentColor"), "#3F7CF1", "a blue one step off the old default stays (chosen)")
st = load({ textColor = "#3F7CF0" })
eq(st:get("textColor"), "#3F7CF0", "only the accent and the glass are moved")
if saved then files:write(V3_PATH, saved) end

section("Classic keeps V2's blue")
E.settings:set("interface", "Classic")
M.steps(2)
local menu = ui.classic.byPath.MainMenu
eq(menu.BackgroundColor3, Color3.fromRGB(0, 35, 73), "the menu's dark blue")
eq(Settings.byKey.classicMainColor.default, "#003481", "Main Colour default unchanged")
E.settings:set("interface", "New")
M.steps(2)
finish()
