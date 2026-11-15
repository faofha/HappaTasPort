-- needs: ui
-- ================================================================================================
-- HappaTAS 3: touch buttons. A touch screen without a keyboard always gets the Classic interface (the new one
-- was too buggy on phones; Classic fits V2's mobile buttons): the Interface row is gone there, a saved or set
-- "New" stays Classic. V2's mobile buttons, Test's double-tap quit, a touch laptop keeps the choice
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
M.steps(2)
local lastStatus
E.bus:on("status", function(t) lastStatus = tostring(t) end)

section("a phone: Classic only")
eq(E.settings:get("interface"), "New", "the saved setting is New (the default)")
eq(ui.live, "Classic", "but Classic is live")
eq(ui.root.gui.Enabled, false, "the new interface (and its pad) hidden")
E.settings:set("interface", "New")
M.steps(2)
eq(ui.live, "Classic", "setting New keeps Classic")
eq(ui.classic.gui.Enabled, true, "Classic still shown")
local list = ui.classic.byPath["MainMenu.SettingsFrame.List"]
eq(list:FindFirstChild("interface"), nil, "no Interface row in Classic's Settings")
check(list:FindFirstChild("speedHack") ~= nil, "(the other rows are there)")

section("Classic: V2's mobile buttons")
local b = ui.classic.byPath
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

section("Test: one tap never quits, two do")
E.modes:request("create")
M.steps(3)
E.modes:request("unpause")
M.steps(300, 1 / 60)
E.modes:request("pause")
M.steps(2)
E.modes:request("test")
M.steps(2)
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

section("a touch laptop (touch and keyboard): the choice stays")
uis.TouchEnabled, uis.KeyboardEnabled = true, true
check(boot(30), "runs again")
ui = getgenv().__HappaTAS3_T.engine.ui
M.steps(2)
eq(ui.live, "New", "New is live")
check(ui.touch == nil or not ui.touch.gui.Visible, "no pad")
local E2 = getgenv().__HappaTAS3_T.engine
E2.settings:set("interface", "Classic")
M.steps(2)
eq(ui.live, "Classic", "Classic can be picked")
check(ui.classic.byPath["MainMenu.SettingsFrame.List"]:FindFirstChild("interface") ~= nil, "the Interface row is there")
E2.settings:set("interface", "New")
M.steps(2)
uis.TouchEnabled, uis.KeyboardEnabled = false, true
finish()
