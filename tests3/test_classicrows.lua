-- needs: ui
-- ================================================================================================
-- HappaTAS 3: settings rows both interfaces share.
--   * Glide Manipulation and Glide Chance are in Classic's Settings tab too (a Glide section)
--   * the interface setting is a choice of two: a pill (New | Classic) in the New interface's Settings window, and
--     in Classic a box that shows the choice and goes to the next one when it is clicked (New -> Classic -> New)
--   * Classic Look's Background Fit is the same kind of box (Crop -> Fit -> Stretch -> Crop)
-- (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local ui = E.ui
local s = E.settings
local Settings = __T3("engine/settings")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end

section("the New interface: the interface setting is a pill")
do
	local def = Settings.byKey.interface
	eq(def.name, "Interface", "its name")
	eq(def.kind, "choice", "a choice")
	eq(def.switch, nil, "not a switch any more")
	UIH.click(ui.dock.buttons.settings.gui)
	local r = ui.settingsWin.rows.interface
	check(r ~= nil, "a row in the Settings window")
	eq(r and r.kind, "segmented", "a segmented control (New | Classic)")
	eq(r and r.ctl.value, "New", "showing New")
end

s:set("interface", "Classic")
M.steps(1)
local c = ui.classic
local rows = c.settingsRows
local list = c.byPath["MainMenu.SettingsFrame.List"]

section("Classic: the Glide settings")
do
	check(list:FindFirstChild("Section_Glide") ~= nil, "a Glide section")
	local gm, gc = rows.glideManipulation, rows.glideChance
	check(gm ~= nil and gm.switch ~= nil, "Glide Manipulation: a switch")
	check(gc ~= nil and gc.input ~= nil, "Glide Chance: a box")
	if gm and gm.switch then
		eq(gm.label.Text, "Glide Manipulation", "its name")
		local was = s:get("glideManipulation")
		gm.switch.MouseButton1Click:Fire()
		eq(s:get("glideManipulation"), (was == 1) and 0 or 1, "the switch switches it")
		gm.switch.MouseButton1Click:Fire()
		eq(s:get("glideManipulation"), was, "and back")
	end
	if gc and gc.input then
		eq(gc.label.Text, "Glide Chance (%)", "its name")
		gc.input.Text = "75"
		gc.input.FocusLost:Fire(true, nil)
		eq(s:get("glideChance"), 75, "typing sets the chance")
		s:set("glideChance", 20)
		eq(gc.input.Text, "20", "the box follows the store")
		s:set("glideChance", 50)
	end
	-- (the section sits with the speed hack's, in the settings' own order)
	local speed, glide = list:FindFirstChild("Section_Speed Hack"), list:FindFirstChild("Section_Glide")
	check(speed and glide and glide.LayoutOrder > speed.LayoutOrder, "after the Speed Hack section")
end

section("Classic: Background Fit goes to the next choice on a click")
do
	local r = rows.classicBackgroundFit
	check(r ~= nil and r.cycle ~= nil, "a box to click")
	eq(r and r.input, nil, "not a box to type in")
	if r and r.cycle then
		check(r.cycle:IsA("TextButton"), "a button")
		eq(r.cycle.Text, "Crop", "showing Crop")
		r.cycle.MouseButton1Click:Fire()
		eq(s:get("classicBackgroundFit"), "Fit", "a click: Fit")
		eq(r.cycle.Text, "Fit", "shown")
		r.cycle.MouseButton1Click:Fire()
		eq(s:get("classicBackgroundFit"), "Stretch", "again: Stretch")
		r.cycle.MouseButton1Click:Fire()
		eq(s:get("classicBackgroundFit"), "Crop", "again: back to Crop")
		eq(r.cycle.Text, "Crop", "shown")
		s:set("classicBackgroundFit", "Stretch")
		eq(r.cycle.Text, "Stretch", "the box follows the store")
		s:set("classicBackgroundFit", "Crop")
	end
end

section("Classic: the interface setting goes to the next choice on a click")
do
	local r = rows.interface
	check(r ~= nil and r.cycle ~= nil, "a box to click")
	eq(r and r.switch, nil, "not a switch")
	if r and r.cycle then
		eq(r.label.Text, "Interface", "its name")
		eq(r.cycle.Text, "Classic", "showing Classic")
		r.cycle.MouseButton1Click:Fire()
		M.steps(1)
		eq(s:get("interface"), "Tasability", "a click: the next choice, Compact (V3.1)")
		eq(ui.live, "Tasability", "the Compact interface is up")
		eq(r.cycle.Text, "Tasability", "(the box shows it)")
		s:set("interface", "Classic")
		M.steps(1)
		r.cycle.MouseButton1Click:Fire()
		M.steps(1)
		r.cycle.MouseButton1Click:Fire()
		M.steps(1)
		eq(s:get("interface"), "New", "a second click: New (it wraps round)")
		eq(ui.live, "New", "the New interface is up")
		eq(ui.settingsWin.rows.interface.ctl.value, "New", "the New window's pill too")
		s:set("interface", "Classic")
		M.steps(1)
		eq(r.cycle.Text, "Classic", "back in Classic: showing Classic")
	end
end

finish()
