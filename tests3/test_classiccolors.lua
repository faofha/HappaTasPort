-- needs: ui
-- ================================================================================================
-- HappaTAS 3: Classic Look: the Classic interface's own colours (a Main Colour that every colour follows on
-- Auto, one setting per colour V2's Classic draws), the Classic colour picker; shown only in Classic's
-- Settings tab (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local ui = E.ui
local Settings = __T3("engine/settings")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end

section("the rows")
local keys = 0
for _, def in ipairs(Settings.SCHEMA) do
	if def.classicOnly then
		keys = keys + 1
		eq(def.section, "Classic look", def.key .. " in Classic look")
	end
end
eq(keys, 27, "Main Colour, 23 colours, 3 background rows")
local byKey = Settings.byKey
check(byKey.classicPanel ~= nil and byKey.classicMainColor ~= nil and byKey.classicBackground ~= nil, "the keys exist")
if byKey.classicPanel then
	eq(Settings.sanitize(byKey.classicPanel, "auto"), "Auto", "auto")
	eq(Settings.sanitize(byKey.classicPanel, ""), "Auto", "empty = Auto")
	eq(Settings.sanitize(byKey.classicPanel, "0, 41, 91"), "#00295B", "r, g, b")
	eq(Settings.sanitize(byKey.classicPanel, "256, 0, 0"), nil, "out of range refused")
	eq(byKey.classicPanel.default, "Auto", "Auto by default")
end
if byKey.classicMainColor then
	eq(Settings.sanitize(byKey.classicMainColor, "255,0,0"), "#FF0000", "r,g,b on a color row")
	eq(Settings.sanitize(byKey.classicMainColor, "Auto"), nil, "the Main Colour has no Auto")
	eq(byKey.classicMainColor.default, "#003481", "V2's button blue")
end
if byKey.classicBackground then
	eq(Settings.sanitize(byKey.classicBackground, string.rep("a", 500)), string.rep("a", 500), "a 500-character link")
	eq(Settings.sanitize(byKey.classicBackground, string.rep("a", 501)), nil, "501 refused")
end
eq(Settings.sanitize(byKey.theme, string.rep("a", 41)), nil, "other text rows keep their 40")

section("Classic shows them, the New Settings window doesn't")
UIH.click(ui.dock.buttons.settings.gui)
check(ui.wm:isOpen("settings"), "(the New Settings window is open)")
local inNew = 0
for key in pairs(ui.settingsWin.rows) do
	if byKey[key] and byKey[key].classicOnly then inNew = inNew + 1 end
end
eq(inNew, 0, "none in the New interface's Settings window")
E.settings:set("interface", "Classic")
M.steps(1)
local c = ui.classic
local missing = 0
for _, def in ipairs(Settings.SCHEMA) do
	if def.classicOnly and not c.settingsRows[def.key] then missing = missing + 1 end
end
eq(missing, 0, "every one in Classic's Settings tab")
check(c.byPath["MainMenu.SettingsFrame.List"]:FindFirstChild("Section_Classic Look") ~= nil, "under a Classic Look title")

finish()
