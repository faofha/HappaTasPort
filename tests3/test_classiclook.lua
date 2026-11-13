-- needs: ui
-- ================================================================================================
-- HappaTAS 3: the classic interface is V2.38.17's (Part E2): only the settings V2.38.17 has (with its names
-- and sections) plus the Classic interface switch, its own fonts and colours (the New interface's Appearance
-- never reaches it), nothing of the New interface left on screen, and switching back and forth changes
-- nothing saved (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local Settings = __T3("engine/settings")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end

section("only V2.38.17's settings, with its names and sections")
E.settings:set("interface", "Classic")
M.steps(1)
local c = ui.classic
local b = c.byPath
local rows = c.settingsRows
local shown = 0
for _, def in ipairs(Settings.SCHEMA) do
	if def.v2 or def.key == "interface" or def.classicOnly then
		check(rows[def.key] ~= nil, def.key .. " shown")
		shown = shown + 1
	else
		eq(rows[def.key], nil, def.key .. " hidden (the New interface's only)")
	end
end
eq(shown, 61, "V2.38.17's 33 settings (Frame Step went with Part B), the Classic interface switch and Classic Look's 27")
eq(rows.speedHack.label.Text, "Speed Hack (slow / fast motion)", "V2.38.17's label")
eq(rows.speedHackSpeed.label.Text, "Speed (0.1 - 4, 0.5 = half, 2 = double)", "V2.38.17's label")
eq(rows.syncKitObjects.label.Text, "Sync Kit Objects (Beat Blocks, Turrets)", "V2.38.17's label")
eq(rows.allowPlayerGuiInterface.label.Text, "Allow Visible Interface (PlayerGui)", "V2.38.17's label")
local list = b["MainMenu.SettingsFrame.List"]
check(list:FindFirstChild("Section_Speed Hack") ~= nil and list:FindFirstChild("Section_World Sync") ~= nil, "V2.38.17's section names")
eq(list:FindFirstChild("Section_Appearance"), nil, "no Appearance section")

section("V2.38.17's fonts and colours, whatever the New interface's are")
c:tab("Settings")
M.steps(1)
local title = b["MainMenu.Title"]
local font0, color0, size0 = title.FontFace, title.TextColor3, title.TextSize
local stats0 = b["IdleStats.2"].FontFace
local line0 = b["MainMenu.Line"].BackgroundColor3
local stroke = list:FindFirstChildOfClass("UIStroke")
local stroke0 = stroke and stroke.Color
local tab0 = b["MainMenu.SettingsToggle"].BackgroundColor3
local V2BLUES = { ["008DED"] = true, ["004DCD"] = true, ["00A9F4"] = true, ["00C4F8"] = true }
check(V2BLUES[line0:ToHex():upper()] == true, "the line under the tabs is one of V2.38.17's blues (" .. line0:ToHex() .. ")")
check(stroke0 ~= nil and V2BLUES[stroke0:ToHex():upper()] == true, "the list's stroke too")
local header0 = list:FindFirstChild("Section_Playback").TextColor3
E.settings:set("accentColor", "#00C080")
E.settings:set("textColor", "#FFEEDD")
E.settings:set("secondaryTextColor", "#998877")
E.settings:set("font", "Roboto")
E.settings:set("numberFont", "Inconsolata")
E.settings:set("textSize", 22)
E.settings:set("interfaceScale", 150)
E.settings:set("recordingColor", "#FF00FF")
M.steps(1)
eq(title.FontFace, font0, "the title keeps its font")
eq(title.TextColor3, color0, "and its colour")
eq(title.TextSize, size0, "and its size")
eq(b["IdleStats.2"].FontFace, stats0, "the stats keep their font")
eq(b["MainMenu.Line"].BackgroundColor3, line0, "V2's blue line under the tabs")
eq(stroke and stroke.Color, stroke0, "a list's blue stroke")
eq(b["MainMenu.SettingsToggle"].BackgroundColor3, tab0, "the selected tab: V2's colour (only its transparency changes)")
eq(list:FindFirstChild("Section_Playback").TextColor3, header0, "section headers keep their colour")
eq(b.MainMenu:FindFirstChildOfClass("UIScale"), nil, "no interface scale")
local on = rows.syncButtonTimers
eq(on.on, true, "(an on switch)")
eq(on.knob.BackgroundColor3, Color3.fromRGB(75, 75, 75), "an on switch: V2.38.17's grey knob")
E.modes:request("create")
M.steps(3)
E.modes:request("unpause")
M.steps(2)
eq(b.CreateStats:FindFirstChild("RecStroke"), nil, "no recording outline (V2.38.17 had none)")
E.modes:request("pause")
M.steps(2)
E.modes:request("idle")
M.steps(2)

section("nothing of the New interface is left while Classic is up")
E.settings:set("interface", "New")
E.settings:set("glass", "Frost")
ui.wm:open("settings")
M.steps(3)
E.settings:set("interface", "Classic")
M.steps(3)
eq(M.services.Lighting:FindFirstChild("HappaTASFrost"), nil, "no Frost blur")
eq(workspace.CurrentCamera:FindFirstChild("HappaTASFrost"), nil, "no Frost glass")

section("switching back and forth changes nothing saved")
M.steps(60, 1 / 60) -- (the settings file saved)
local path = "HappaTasPort/Settings3.json"
local before = readfile(path)
for _ = 1, 10 do
	E.settings:set("interface", "New")
	M.steps(2)
	E.settings:set("interface", "Classic")
	M.steps(2)
end
M.steps(60, 1 / 60)
eq(readfile(path), before, "the settings file is the same after 10 switches")
eq(E.settings:get("font"), "Roboto", "the New interface's font kept")
eq(E.settings:get("accentColor"), "#00C080", "its accent kept")
eq(E.settings:get("interfaceScale"), 150, "its scale kept")
E.settings:set("interface", "New")
M.steps(2)
check(ui.theme ~= nil, "the New interface is back")
finish()
