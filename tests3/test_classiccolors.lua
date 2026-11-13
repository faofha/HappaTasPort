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

section("Auto colours")
local Palette = __T3("ui/classic/palette")
local function rgb(col) return math.floor(col.R * 255 + 0.5) .. "," .. math.floor(col.G * 255 + 0.5) .. "," .. math.floor(col.B * 255 + 0.5) end
eq(#Palette.LIST, 23, "23 colours")
for i, p in ipairs(Palette.LIST) do
	eq(p.key, ({ "classicWindow", "classicPanel", "classicButton", "classicShade", "classicScrollBar", "classicLight", "classicText",
		"classicDarkText", "classicLabelText", "classicPlaceholder", "classicSectionTitle", "classicOutline", "classicFieldOutline",
		"classicDivider", "classicLine", "classicLightOutline", "classicCancel", "classicWarning", "classicMergeOk", "classicToggleOff",
		"classicIconButton", "classicSwitchOn", "classicSwitchOff" })[i], "palette order " .. i)
	eq(rgb(Palette.derive(Palette.BASE, p.color)), rgb(p.color), p.key .. ": the default Main Colour gives V2's colour")
end
local function value(col) return select(3, col:ToHSV()) end
local red = Color3.fromRGB(200, 0, 0)
local w, b, o = Palette.derive(red, Palette.LIST[1].color), Palette.derive(red, Palette.LIST[3].color), Palette.derive(red, Palette.LIST[12].color)
check(value(w) < value(b) and value(b) <= value(o), "red: window darker than buttons, outline lightest")
check(w.R > w.G and w.R > w.B, "red: the window is red")
-- (Review Focus: grey / white / black Main Colours)
for _, m in ipairs({ Color3.new(1, 1, 1), Color3.new(0, 0, 0), Color3.fromRGB(128, 128, 128) }) do
	local okAll = true
	for _, p in ipairs(Palette.LIST) do
		local col = Palette.derive(m, p.color)
		for _, x in ipairs({ col.R, col.G, col.B }) do
			if x ~= x or x < 0 or x > 1 then okAll = false end
		end
	end
	check(okAll, "a real colour for every part with the Main Colour " .. rgb(m))
end
local white = Palette.derive(Color3.new(1, 1, 1), Palette.LIST[11].color)
eq(rgb(white), "255,255,255", "a white Main Colour: the section title (lighter than buttons) is white")
local paler = Palette.derive(Color3.fromRGB(255, 0, 0), Palette.LIST[12].color)
check(paler.R > 0.99 and paler.G > 0.3 and paler.B > 0.3, "pure red: the outline (brighter than buttons) turns paler, not clipped (" .. rgb(paler) .. ")")
local resolved = Palette.resolve(E.settings)
eq(rgb(resolved.classicWindow), "0,35,73", "resolve: Auto at the default")
E.settings:set("classicShade", "#123456")
eq(rgb(Palette.resolve(E.settings).classicShade), "18,52,86", "resolve: a typed colour wins")
E.settings:set("classicMainColor", "#C80000")
eq(rgb(Palette.resolve(E.settings).classicText), "255,255,255", "neutral Auto stays V2's")
check(Palette.resolve(E.settings).classicPanel.R > 0.1, "tinted Auto follows the Main Colour")
E.settings:set("classicShade", "Auto")
E.settings:set("classicMainColor", "#003481")
eq(Palette.hex(Color3.fromRGB(0, 52, 129)), "#003481", "hex")
eq(Palette.keyFor("ScrollBarImageColor3", Color3.new(0, 0, 0)), "classicScrollBar", "black scroll bar")
eq(Palette.keyFor("BackgroundColor3", Color3.new(0, 0, 0)), "classicShade", "black background")
eq(Palette.keyFor("TextColor3", Color3.new(0, 0, 0)), "classicLabelText", "black text")
eq(Palette.keyFor("Color", Color3.fromRGB(0, 196, 248)), "classicDivider", "a divider stroke")
eq(Palette.keyFor("BackgroundColor3", Color3.fromRGB(0, 196, 248)), "classicDivider", "a divider frame")
eq(Palette.keyFor("BackgroundColor3", Color3.fromRGB(50, 50, 50)), nil, "runtime-only colours aren't registered")
eq(Palette.keyFor("TextColor3", Color3.fromRGB(140, 205, 255)), nil, "(the section title is painted while running)")

finish()
