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

section("repainting")
local look = c.look
check(look ~= nil, "Classic has a Look")
local menu = c.byPath.MainMenu
eq(rgb(menu.BackgroundColor3), "0,35,73", "V2's window colour at the default")
E.settings:set("classicMainColor", "#C80000")
M.steps(1)
check(menu.BackgroundColor3.R > menu.BackgroundColor3.B, "Main Colour red: the window turns red (" .. rgb(menu.BackgroundColor3) .. ")")
eq(rgb(c.byPath["MainMenu.SavesFrame.YourSlots.Top.AddSlot"].BackgroundColor3), rgb(look:color("classicButton")), "a button follows too")
E.settings:set("classicWindow", "#00FF00")
M.steps(1)
eq(rgb(menu.BackgroundColor3), "0,255,0", "a typed Window colour wins")
E.settings:set("classicWindow", "Auto")
M.steps(1)
check(menu.BackgroundColor3.R > menu.BackgroundColor3.G, "back on Auto: red again")
-- (Review Focus: a row built later comes up in the current colours)
c:tab("Saves")
local before = #c.saves.slots
c.byPath["MainMenu.SavesFrame.YourSlots.Top.AddSlot"].MouseButton1Click:Fire()
M.steps(1)
check(#c.saves.slots > before, "(a new slot row)")
local newRow = c.saves.slots[#c.saves.slots]
local frame = newRow and (newRow.frame or newRow.gui or newRow)
local wrong = 0
for key, list in pairs(look.entries) do
	for _, e in ipairs(list) do
		if typeof(frame) == "Instance" and (e.inst == frame or e.inst:IsDescendantOf(frame)) and rgb(e.inst[e.prop]) ~= rgb(look:color(key)) then wrong = wrong + 1 end
	end
end
eq(wrong, 0, "the new slot row comes up in the current colours")
check(newRow ~= nil and rgb(newRow.save.Parent.BackgroundColor3) == rgb(look:color("classicButton")) and look:color("classicButton").R > 0.3, "its button bar is in the (red) Button colour")
-- (Review Focus: colours painted while running follow their setting, and no other key repaints them)
local before1 = c.byPath["Merge.Options.Before"]
E.settings:set("classicToggleOff", "#010203")
E.settings:set("classicButton", "#FFFF00")
M.steps(1)
check(look:owns(before1, "BackgroundColor3"), "the merge option buttons are painted by their own code")
local knobOn, knobOff
for _, r in pairs(c.settingsRows) do
	if r.knob and r.on == true and not knobOn then knobOn = r.knob end
	if r.knob and r.on == false and not knobOff then knobOff = r.knob end
end
E.settings:set("classicSwitchOn", "#0A0B0C")
E.settings:set("classicSwitchOff", "#0D0E0F")
M.steps(1)
eq(rgb(knobOn.BackgroundColor3), "10,11,12", "a switch that is on: Switch On")
eq(rgb(knobOff.BackgroundColor3), "13,14,15", "a switch that is off: Switch Off")
E.settings:set("classicLight", "#202020")
M.steps(1)
eq(rgb(knobOff.BackgroundColor3), "13,14,15", "Light Fill doesn't repaint a knob")
local title = c.byPath["MainMenu.SettingsFrame.List"]:FindFirstChild("Section_Classic Look")
E.settings:set("classicSectionTitle", "#112233")
M.steps(1)
eq(rgb(title.TextColor3), "17,34,51", "section titles follow Section Title")
-- (Review Focus: to the New interface and back)
E.settings:set("interface", "New")
M.steps(1)
E.settings:set("interface", "Classic")
M.steps(1)
eq(rgb(ui.classic.byPath.MainMenu.BackgroundColor3), rgb(ui.classic.look:color("classicWindow")), "back to Classic: still the set colours")
for _, k in ipairs({ "classicMainColor", "classicButton", "classicToggleOff", "classicSwitchOn", "classicSwitchOff", "classicLight", "classicSectionTitle" }) do
	E.settings:set(k, Settings.byKey[k].default)
end
M.steps(1)
eq(rgb(menu.BackgroundColor3), "0,35,73", "everything back on the defaults: V2's colours")

section("colour rows and the picker")
c = ui.classic
c:tab("Settings")
local r = c.settingsRows.classicPanel
eq(r.input.Text, "Auto", "Auto shown")
check(r.swatch ~= nil, "a swatch")
r.input.Text = "10, 20, 30"
r.input.FocusLost:Fire(true, nil)
eq(E.settings:get("classicPanel"), "#0A141E", "typed r, g, b stored as hex")
eq(r.input.Text, "#0A141E", "shown as hex")
eq(rgb(r.swatch.BackgroundColor3), "10,20,30", "the swatch shows it")
r.input.Text = ""
r.input.FocusLost:Fire(true, nil)
eq(E.settings:get("classicPanel"), "Auto", "an empty box = Auto")
eq(rgb(r.swatch.BackgroundColor3), "0,41,91", "the swatch shows the Auto colour")
E.settings:set("classicMainColor", "#C80000")
check(r.swatch.BackgroundColor3.R > r.swatch.BackgroundColor3.B, "a new Main Colour repaints an Auto swatch")
E.settings:set("classicMainColor", "#003481")
r.swatch.MouseButton1Click:Fire()
local p = c.picker
check(p ~= nil and p.frame.Parent == c.gui, "the swatch opens the picker")
if p then
	p:setHue(0)
	p:setSV(1, 0)
	eq(Palette.hex(p.newColor), "#FF0000", "hue 0, full saturation and value = red")
	p:setSV(0, 1)
	eq(Palette.hex(p.newColor), "#000000", "bottom = black")
	p:typed("0, 255, 0")
	eq(Palette.hex(p.newColor), "#00FF00", "typed r, g, b")
	p:typed("nonsense")
	eq(Palette.hex(p.newColor), "#00FF00", "a bad value changes nothing")
	p:typed("128, 128, 128")
	p:setSV(1, 0)
	eq(Palette.hex(p.newColor), "#00FF00", "a grey typed keeps the hue shown")
	p:apply()
	eq(E.settings:get("classicPanel"), "#00FF00", "Apply stores it")
	eq(c.picker, nil, "and closes")
end
local rm = c.settingsRows.classicMainColor
eq(rm.input.Text, "#003481", "the Main Colour row shows its colour")
rm.swatch.MouseButton1Click:Fire()
check(c.picker ~= nil and c.picker.autoButton == nil, "no Auto for the Main Colour")
c.picker:typed("#123456")
c.picker:close()
eq(E.settings:get("classicMainColor"), "#003481", "closing without Apply changes nothing")
c.settingsRows.classicPanel.swatch.MouseButton1Click:Fire()
local first = c.picker
c.settingsRows.classicWindow.swatch.MouseButton1Click:Fire()
check(first.frame.Parent == nil and c.picker ~= first, "one picker at a time")
c.picker:auto()
eq(E.settings:get("classicWindow"), "Auto", "Auto button")
c.settingsRows.classicPanel.swatch.MouseButton1Click:Fire()
c.picker:auto()
eq(E.settings:get("classicPanel"), "Auto", "(Panel back on Auto)")
c.settingsRows.classicPanel.swatch.MouseButton1Click:Fire()
do
	-- (the mouse: a press on the square picks there, a drag follows, a press outside closes)
	local pk = c.picker
	local function at(gui, fx, fy)
		local a, z = gui.AbsolutePosition, gui.AbsoluteSize
		M.mouse = Vector2.new(a.X + fx * z.X, a.Y + fy * z.Y + M.inset)
	end
	pk:setHue(0)
	at(pk.square, 0.999, 0.001)
	M.mouseDown(1)
	eq(Palette.hex(pk.newColor), "#FF0000", "a press at the square's top right: red")
	at(pk.square, 0.999, 0.999)
	M.services.UserInputService.InputChanged:Fire(M.input(Enum.UserInputType.MouseMovement), false)
	eq(Palette.hex(pk.newColor), "#000000", "dragging to its bottom: black")
	M.mouseUp(1)
	at(pk.hueBar, 0.5, 1 / 3)
	M.mouseDown(1)
	M.mouseUp(1)
	at(pk.square, 0.999, 0.001)
	M.mouseDown(1)
	M.mouseUp(1)
	eq(Palette.hex(pk.newColor), "#00FF00", "a third down the hue bar: green")
	M.mouse = Vector2.new(2, 2 + M.inset)
	M.mouseDown(1)
	M.mouseUp(1)
	eq(c.picker, nil, "a press outside closes it")
	eq(E.settings:get("classicPanel"), "Auto", "without applying")
end
do
	-- (review: the picker's square overlays, hue bar and previews keep their own colours whatever the Look's are)
	E.settings:set("classicShade", "#FF00FF")
	E.settings:set("classicLight", "#00FF00")
	E.settings:set("classicPanel", "#123456")
	c.settingsRows.classicWindow.swatch.MouseButton1Click:Fire()
	local pk = c.picker
	eq(rgb(pk.square.White.BackgroundColor3), "255,255,255", "the square's white overlay stays white")
	eq(rgb(pk.square.Black.BackgroundColor3), "0,0,0", "its black overlay stays black")
	eq(rgb(pk.hueBar.BackgroundColor3), "255,255,255", "the hue bar stays white under its gradient")
	eq(rgb(pk.frame.Old.BackgroundColor3), rgb(look:color("classicWindow")), "the old colour preview shows the colour")
	pk:close()
	E.settings:set("classicShade", "Auto")
	E.settings:set("classicLight", "Auto")
	E.settings:set("classicPanel", "Auto")
end
c.settingsRows.classicPanel.swatch.MouseButton1Click:Fire()
M.pressKey(Enum.KeyCode.Escape)
M.releaseKey(Enum.KeyCode.Escape)
M.steps(1)
eq(c.picker, nil, "Esc closes it")
c.settingsRows.classicPanel.swatch.MouseButton1Click:Fire()
c:tab("Saves")
eq(c.picker, nil, "another tab closes it")
c:tab("Settings")
c.settingsRows.classicPanel.swatch.MouseButton1Click:Fire()
E.settings:set("interface", "New")
M.steps(1)
local left = 0
for _, g in ipairs({ c.gui }) do
	for _, d in ipairs(g:GetDescendants()) do if d.Name == "HappaTASColorPicker" then left = left + 1 end end
end
eq(left, 0, "switching to the New interface closes it")
E.settings:set("interface", "Classic")
M.steps(1)

finish()
