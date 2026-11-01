-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5c: classic controls: a V2-style row per control, rebinding (the binding press never
-- runs a control), Esc cancels, both interfaces show the same keys, touch screens have no Controls tab
-- (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local Controls = __T3("engine/controls")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
ui.wm:open("controls")
M.steps(2)
local cw = ui.controlsWin
E.settings:set("interface", "Classic")
M.steps(2)
local c = ui.classic
local rows = c.controlRows
check(rows ~= nil, "the classic control rows")

section("a row per control")
local n = 0
for _, ctl in ipairs(Controls.LIST) do
	local r = rows and rows[ctl.key]
	if r and r.label.Text == ctl.v2 and r.key.Text == E.controls:get(ctl.key) then n = n + 1 end
end
eq(n, #Controls.LIST, "every control with its name and key")

section("rebinding while recording: the binding press runs nothing")
E.modes:request("create")
M.steps(3)
E.modes:request("unpause")
M.steps(3)
eq(E.paused, false, "recording")
rows.pause.key.MouseButton1Down:Fire()
M.steps(1)
eq(E.typing.rebinding, true, "waiting for a key")
eq(rows.pause.key.Text, "Press Any Key", "V2's prompt")
UIH.key(Enum.KeyCode.P)
M.steps(2)
eq(E.controls:get("pause"), "P", "Pause bound to P")
eq(E.typing.rebinding, false, "done waiting")
eq(E.paused, false, "the P that bound it didn't pause")
eq(cw.rows.pause.key.label.Text, "P", "the new Controls window shows P at once")
UIH.key(Enum.KeyCode.P)
M.steps(2)
eq(E.paused, true, "the next P pauses")

section("Esc cancels")
rows.back.key.MouseButton1Down:Fire()
M.steps(1)
UIH.key(Enum.KeyCode.Escape)
M.steps(1)
eq(E.typing.rebinding, false, "not waiting")
eq(E.controls:get("back"), "R", "Back unchanged")
eq(rows.back.key.Text, "R", "the row shows R again")

section("a key bound in the new window shows here")
E.controls:set("forward", "Y")
eq(rows.forward.key.Text, "Y", "in the same frame")
E.controls:set("forward", "T")
E.controls:set("pause", "Left Click")

section("touch screens: no Controls tab (V2's rule)")
local uis = M.services.UserInputService
uis.TouchEnabled, uis.KeyboardEnabled = true, false
check(boot(30), "runs again on a touch screen")
T = getgenv().__HappaTAS3_T
E = T.engine
ui = E.ui
M.steps(2)
local c2 = ui.classic
check(c2 ~= nil, "Classic again (the setting kept)")
eq(c2.byPath["MainMenu.ControlsToggle"].Visible, false, "no Controls tab")
eq(c2.byPath["MainMenu.ControlsFrame"].Visible, false, "its frame hidden")
eq(c2.tabName, "Settings", "Settings first")
eq(c2.byPath["MainMenu.SettingsToggle"].Position, UDim2.new(0, 0, 0.108, 0), "four tabs in a row (V2's places)")
uis.TouchEnabled, uis.KeyboardEnabled = false, true
finish()
