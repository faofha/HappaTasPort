-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1 Compact (Task 6): the CONTROLS page (RUN, SPEED HACK, KEYS, TOOLS in two columns) and the
-- title bar's status chip (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
E.settings:set("interface", "Tasability")
M.steps(2)
local cp = ui.compact
cp:showTab("controls")
M.steps(2)
local c = cp.controls
check(c ~= nil, "the controls page")

section("four sections in two columns")
eq(c.run.title.Text, "RUN", "RUN")
eq(c.speed.title.Text, "SPEED HACK", "SPEED HACK")
eq(cp.keysSection.title.Text, "KEYS", "KEYS")
eq(c.tools.title.Text, "TOOLS", "TOOLS")
eq(c.run.gui.Parent, c.left, "RUN on the left")
eq(c.speed.gui.Parent, c.left, "SPEED HACK on the left")
eq(cp.keysSection.gui.Parent, c.right, "KEYS on the right")
eq(c.tools.gui.Parent, c.right, "TOOLS on the right")
check(c.left.AbsolutePosition.X < c.right.AbsolutePosition.X, "left column left of the right one")

section("RUN")
local function rowText(key) return c.values[key].Text end
eq(rowText("mode"), "Idle", "mode Idle")
eq(rowText("frame"), "0 / 0", "no run yet")
UIH.click(c.buttons.create.gui)
M.steps(3)
eq(E.mode, 2, "the Create button requests Create")
eq(rowText("mode"), "Create", "mode Create")
eq(cp.status.label.Text, "Create - paused", "status: paused")
E.modes:request("unpause")
M.steps(30)
check(E.tl:count() > 10, "recording")
M.steps(12)
eq(cp.status.label.Text, "Create - recording", "status: recording")
eq(cp.status.label.TextColor3, ui.theme.c.rec, "in the recording colour")
local n = E.tl:count()
check(rowText("frame"):find(" / ", 1, true) ~= nil and tonumber(rowText("frame"):match("/ (%d+)")) >= n - 12, "the frame count follows (" .. rowText("frame") .. ")")
check(rowText("time"):find("%d") ~= nil, "a time")
E.modes:request("pause")
M.steps(2)
UIH.click(c.buttons.test.gui)
M.steps(3)
eq(E.mode, 3, "the Test button tests")
M.steps(12)
eq(cp.status.label.Text, "Test", "status: Test")
UIH.click(c.buttons.idle.gui)
M.steps(12)
eq(E.mode, 1, "the Idle button")
eq(cp.status.label.Text, "Idle", "status: Idle")

section("SPEED HACK")
local s = E.settings
s:set("speedHack", 0)
M.steps(1)
UIH.click(c.speedToggle.gui)
M.steps(1)
eq(s:get("speedHack"), 1, "the switch turns the speed hack on")
c.speedSlider.onChange(0.3)
eq(s:get("speedHackSpeed"), 0.3, "the slider sets the speed")
s:set("speedHackSpeed", 0.7)
M.steps(1)
eq(c.speedSlider.value, 0.7, "and follows the setting")
s:set("speedHack", 0)

section("TOOLS")
local before = s:on("showMicroProfiler")
UIH.click(c.buttons.profiler.gui)
M.steps(1)
eq(s:on("showMicroProfiler"), not before, "MicroProfiler toggles it")
UIH.click(c.buttons.profiler.gui)
M.steps(1)

section("no work while hidden")
local function handlers()
	local k = 0
	for _, list in pairs(T.pipe.stages) do
		for _, e in ipairs(list) do if e.on and e.name == "ui.compact" then k = k + 1 end end
	end
	return k
end
eq(handlers(), 1, "one Compact handler while live")
s:set("interface", "New")
M.steps(2)
eq(handlers(), 0, "none in New")
s:set("interface", "Tasability")
M.steps(2)
UIH.click(c.buttons.unload.gui)
M.steps(5)
eq(getgenv().__HappaTAS3, nil, "Unload HappaTAS unloads")
finish()
