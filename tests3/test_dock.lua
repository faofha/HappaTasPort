-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5a: the Dock (a button per window, the open ones lit) and status toasts (the bus's
-- "status" and "moduleDisabled": at most 3, 3 s each, errors 6 s) (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local ui = E.ui
local wm = ui.wm
local dock = ui.dock
check(dock ~= nil, "the Dock")

section("only the Dock shows at start")
eq(wm:anyOpen(), false, "no window open")
check(dock.gui.Visible and dock.gui.Parent ~= nil, "the Dock is shown")
local sw = workspace.CurrentCamera.ViewportSize.X
near(dock.gui.AbsolutePosition.X + dock.gui.AbsoluteSize.X / 2, sw / 2, 1, "centred at the top")
check(dock.gui.AbsolutePosition.Y >= 0, "below the top bar")
check(UIH.find(dock.gui, "HappaTAS") ~= nil, "its title")

section("dock buttons open / close their window and show which are open")
wm:define("one", { title = "One", w = 300, h = 200, build = function() end })
wm:define("two", { title = "Two", w = 300, h = 200, build = function() end })
ui:addDockButton("one")
ui:addDockButton("two")
local b1, b2 = dock.buttons.one, dock.buttons.two
check(b1 and b2, "a button each")
eq(b1.label.Text, "One", "named after the window")
UIH.click(b1.gui)
eq(wm:isOpen("one"), true, "a click opens it")
eq(b1.kind, "primary", "lit while open")
eq(b2.kind, "plain", "the other not")
UIH.click(b1.gui)
eq(wm:isOpen("one"), false, "a second click closes it")
eq(b1.kind, "plain", "not lit")
wm:open("two")
eq(b2.kind, "primary", "opened another way: lit too")
wm:close("two")

section("the Menu key hides the Dock and the windows, shows them again")
wm:open("one")
UIH.key(Enum.KeyCode.M)
eq(ui.root.gui.Enabled, false, "everything hidden")
eq(E.modalOpen(), false, "hidden: the mouse isn't freed for the game")
UIH.key(Enum.KeyCode.M)
eq(ui.root.gui.Enabled, true, "shown again")
eq(wm:isOpen("one"), true, "the window still open")
wm:close("one")

section("status toasts")
local toast = ui.toast
E.bus:emit("status", "Saved run 1", false)
eq(#toast.items, 1, "a toast")
check(UIH.find(ui.root.gui, "Saved run 1") ~= nil, "its text shown")
local t1 = toast.items[1].gui
check(t1.AbsolutePosition.Y + t1.AbsoluteSize.Y <= workspace.CurrentCamera.ViewportSize.Y - 96 + 1, "96 px above the bottom")
M.steps(2 * 60, 1 / 60)
eq(#toast.items, 1, "still there after 2 s")
M.steps(80, 1 / 60)
eq(#toast.items, 0, "gone after 3 s")
check(UIH.find(ui.root.gui, "Saved run 1") == nil, "and removed")

section("four messages: three shown, the oldest goes first")
for i = 1, 4 do E.bus:emit("status", "m" .. i, false) end
eq(#toast.items, 3, "three")
eq(toast.items[1].text, "m2", "m1 went first")
eq(toast.items[3].text, "m4", "the newest last")
check(toast.items[3].gui.AbsolutePosition.Y > toast.items[1].gui.AbsolutePosition.Y, "the newest at the bottom")
M.steps(4 * 60, 1 / 60)
eq(#toast.items, 0, "all gone")

section("errors stay 6 s; a module switched off toasts")
E.bus:emit("status", "Could not save", true)
M.steps(4 * 60, 1 / 60)
eq(#toast.items, 1, "an error stays after 4 s")
M.steps(3 * 60, 1 / 60)
eq(#toast.items, 0, "gone after 6 s")
E.bus:emit("moduleDisabled", "kitobjects", "boom")
eq(#toast.items, 1, "a toast")
check(toast.items[1].text:find("kitobjects", 1, true) ~= nil and toast.items[1].text:find("switched off", 1, true) ~= nil,
	"it names the module (" .. toast.items[1].text .. ")")
M.steps(7 * 60, 1 / 60)

section("Unload")
getgenv().__HappaTAS3.Unload()
M.steps(2)
E.bus:emit("status", "after", false)
eq(dock.gui.Parent, nil, "the Dock gone")
finish()
