-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5c: Appearance in the classic interface (spec 8.5): the eight values it draws, changed
-- in either interface, shown in the other at once and after a restart; nothing else changes its look
-- (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local ACC = "#00C080"
local acc = Color3.fromHex("00C080")

section("accent set in New, then Classic uses it at once")
E.settings:set("accentColor", ACC)
E.settings:set("interface", "Classic")
local c = ui.classic
local b = c.byPath
c:tab("Settings")
eq(b["MainMenu.SettingsToggle"].BackgroundColor3, acc, "the selected tab")
local on = c.settingsRows.syncButtonTimers
eq(on.on, true, "(an on switch)")
eq(on.knob.BackgroundColor3, acc, "an on switch's knob")
eq(b["MainMenu.Line"].BackgroundColor3, acc, "V2's blue line under the tabs")
local stroke = b["MainMenu.SettingsFrame.List"]:FindFirstChildOfClass("UIStroke")
eq(stroke.Color, acc, "a list's blue stroke")

section("accent set in Classic, then New uses it")
local GREEN = "#40A0FF"
local r = c.settingsRows.accentColor
r.input.Text = GREEN
r.input.FocusLost:Fire(true, nil)
E.settings:set("interface", "New")
ui.wm:open("settings")
M.steps(1)
eq(ui.dock.buttons.settings.gui.BackgroundColor3, Color3.fromHex("40A0FF"), "the Dock's lit button")

section("the other seven")
E.settings:set("interface", "Classic")
M.steps(1)
E.settings:set("textColor", "#FFEEDD")
eq(b["MainMenu.Title"].TextColor3, Color3.fromHex("FFEEDD"), "text colour")
E.settings:set("secondaryTextColor", "#998877")
local header = b["MainMenu.SettingsFrame.List"]:FindFirstChild("Section_Playback")
eq(header.TextColor3, Color3.fromHex("998877"), "secondary text colour (section headers)")
E.settings:set("font", "Roboto")
check(b["MainMenu.Title"].FontFace.Family:find("Roboto", 1, true) ~= nil, "font")
eq(b["MainMenu.Title"].FontFace.Weight, Enum.FontWeight.Bold, "its weight kept")
E.settings:set("numberFont", "Inconsolata")
check(b["IdleStats.2"].FontFace.Family:find("Inconsolata", 1, true) ~= nil, "number font (stats)")
E.settings:set("textSize", 22)
eq(b["MainMenu.Title"].TextSize, 34, "text size: V2's 20 x 22 / 13")
eq(b["IdleStats.2"].TextSize, E.settings:get("statsTextSize"), "the stats keep Stats Text Size")
E.settings:set("interfaceScale", 150)
local sc = b.MainMenu:FindFirstChildOfClass("UIScale")
eq(sc and sc.Scale, 1.5, "interface scale")
E.settings:set("recordingColor", "#FF00FF")
E.modes:request("create")
M.steps(3)
E.modes:request("unpause")
M.steps(2)
local rec = b.CreateStats:FindFirstChild("RecStroke")
check(rec ~= nil and rec.Enabled, "an outline while recording")
eq(rec and rec.Color, Color3.fromHex("FF00FF"), "in the recording colour")
E.modes:request("pause")
M.steps(2)
eq(rec.Enabled, false, "gone while paused")

section("nothing else changes Classic's look")
local menuBg = b.MainMenu.BackgroundColor3
E.settings:set("glassColor", "#102030")
E.settings:set("windowCorners", 4)
E.settings:set("edgeLight", 80)
eq(b.MainMenu.BackgroundColor3, menuBg, "the glass colour doesn't reach V2's panels")

section("restart: both load it")
M.steps(60, 1 / 60)
check(boot(30), "runs again")
T = getgenv().__HappaTAS3_T
E = T.engine
ui = E.ui
M.steps(2)
c = ui.classic
c:tab("Saves")
eq(c.byPath["MainMenu.SavesToggle"].BackgroundColor3, Color3.fromHex("40A0FF"), "Classic loads the accent")
eq(c.byPath["MainMenu.Title"].TextSize, 34, "and the text size")
E.settings:set("interface", "New")
ui.wm:open("settings")
M.steps(1)
eq(ui.dock.buttons.settings.gui.BackgroundColor3, Color3.fromHex("40A0FF"), "New loads it")
finish()
