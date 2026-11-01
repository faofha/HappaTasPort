-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5c: touch buttons (a touch screen without a keyboard): the new interface's pad, V2's
-- mobile buttons in Classic, held Back / Forward, Test's double-tap quit, none on a touch laptop
-- (headless mock)
-- ================================================================================================
local uis = M.services.UserInputService
uis.TouchEnabled, uis.KeyboardEnabled = true, false
check(boot(30), "boots on a touch screen")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
ui.wm:close("inspector")
M.steps(2)
local lastStatus
E.bus:on("status", function(t) lastStatus = tostring(t) end)
local pad = ui.touch
check(pad ~= nil and pad.gui.Visible, "the touch pad shows")
local function tap(name)
	local btn = pad.buttons[name]
	UIH.click(btn.gui)
	M.steps(1)
end

section("the pad's Menu button hides the interface and brings it back (review: it hid itself)")
tap("menu")
eq(ui.shown, false, "hidden")
eq(pad.gui.Visible and ui.root.gui.Enabled, true, "the pad stays")
eq(ui.bar.gui.AbsoluteSize.X > 0 and ui.root.layer.Visible, false, "the rest is hidden")
tap("menu")
eq(ui.shown, true, "shown again")
eq(ui.root.layer.Visible, true, "everything back")

section("modes and recording from the pad")
tap("create")
eq(E.mode, 2, "Create")
eq(E.paused, true, "paused")
tap("pause")
eq(E.paused, false, "the pause button unpaused")
eq(pad.buttons.pause.icon.kind, "pause", "it shows pause while recording")
M.steps(200, 1 / 60) -- (a run long enough to test for a few seconds)
tap("pause")
eq(E.paused, true, "and paused again")
eq(pad.buttons.pause.icon.kind, "play", "it shows play while paused")
local n = E.tl:count()
check(n > 10, "frames recorded (" .. n .. ")")

section("back held, then released")
E.modes:request("seek", { frame = n })
M.steps(2)
local p = UIH.center(pad.buttons.back.gui)
UIH.press(p)
M.steps(1)
eq(E.back, true, "held")
M.steps(10, 1 / 60)
UIH.release(p)
M.steps(1)
eq(E.back, false, "released: E.back off (Modes:release)")
check(E.frame < n, "went back (" .. E.frame .. " of " .. n .. ")")
tap("back1")
tap("forward1")
tap("unpause1")
M.steps(2)
eq(E.paused, true, "one frame recorded, paused again")

section("Test: one tap never quits, two do")
tap("test")
eq(E.mode, 3, "testing")
uis.TouchTap:Fire({ Vector2.new(500, 500) }, false)
M.steps(1)
eq(E.mode, 3, "still testing after one tap")
eq(lastStatus, "Tap again to quit Test", "it asks")
M.steps(90, 1 / 60) -- (1.5 s: the first tap forgotten)
uis.TouchTap:Fire({ Vector2.new(500, 500) }, false)
M.steps(1)
eq(E.mode, 3, "a tap after 1.5 s asks again")
uis.TouchTap:Fire({ Vector2.new(500, 500) }, false)
M.steps(1)
eq(E.mode, 1, "two taps quit")
eq(lastStatus, "Test Quit", "V2's message")

section("windows are sheets, the pad stays")
ui.wm:open("settings")
M.steps(1)
eq(ui.wm:isSheet(), true, "a sheet (phase 5a)")
eq(pad.gui.Visible, true, "the pad still there")
ui.wm:close("settings")

section("Classic: V2's mobile buttons")
E.settings:set("interface", "Classic")
M.steps(2)
local b = ui.classic.byPath
eq(pad.gui.Visible, false, "the new pad hidden with the new interface")
eq(b["Mobile.MenuOpener"].Visible, true, "V2's menu button")
eq(b["Mobile.MobileModes.Mode2Mobile"].Visible, true, "V2's mode buttons")
b["Mobile.MobileModes.Mode2Mobile"].MouseButton1Click:Fire()
M.steps(2)
eq(E.mode, 2, "Mode 2: Create")
eq(b["Mobile.MobileCreate.Pause"].Visible, true, "the Create buttons show")
b["Mobile.MobileCreate.Pause"].MouseButton1Click:Fire()
M.steps(2)
eq(E.paused, false, "V2's pause button unpaused")
b["Mobile.MobileCreate.Pause"].MouseButton1Click:Fire()
M.steps(2)
b["Mobile.MobileCreate.Back"].MouseButton1Down:Fire()
M.steps(1)
eq(E.back, true, "V2's Back held")
b["Mobile.MobileCreate.Back"].MouseButton1Up:Fire()
M.steps(1)
eq(E.back, false, "and released")
b["Mobile.MenuOpener"].MouseButton1Click:Fire()
eq(ui.classic.menu.Visible, true, "the menu button opens V2's menu")

section("a touch laptop (touch and keyboard): no touch buttons")
E.settings:set("interface", "New")
M.steps(2)
uis.TouchEnabled, uis.KeyboardEnabled = true, true
check(boot(30), "runs again")
ui = getgenv().__HappaTAS3_T.engine.ui
M.steps(2)
check(ui.touch == nil or not ui.touch.gui.Visible, "no pad")
uis.TouchEnabled, uis.KeyboardEnabled = false, true
finish()
