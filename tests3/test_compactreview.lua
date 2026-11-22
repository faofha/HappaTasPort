-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1 Compact: the final review's findings (headless mock)
--  C1 the side panels take clicks; I1 the New Inspector keeps timing after Compact; I2 no Frost in Compact;
--  I3 open side panels stay on screen; I4 the mouse stays with the game while the Merge window is open;
--  I6 the Dock shows which New windows are open after Compact's hosted pages opened and closed
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local wm = ui.wm
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
M.steps(2)
local timing0 = E.pipe.timing
wm:open("settings")
M.steps(1)
E.settings:set("interface", "Tasability")
M.steps(2)
local cp = ui.compact

section("C1: the side panels take clicks")
cp:setPanel("library", true)
cp:setPanel("inspector", true)
M.steps(2)
local lw = cp.hosted.library.obj
local function hits(gui)
	local r = ui.pointer:over(UIH.center(gui))
	return r ~= nil and (r.gui == gui or gui:IsDescendantOf(r.gui) or r.gui:IsDescendantOf(gui))
end
check(hits(lw.buttons.save.gui), "the Library's Save button")
check(hits(lw.search.gui), "the Library's search box")
check(hits(cp.hosted.inspector.obj.options.gui), "the Inspector's Options button")
check(ui.pointer:over(UIH.center(cp.panels.library.bar)) ~= nil, "the panel's title bar")
lw.nameField:set("ClickSaved")
UIH.click(lw.buttons.save.gui)
local g = 0
while E.busy and g < 2000 do M.step(1 / 60); g = g + 1 end
M.steps(2)

section("I3: open side panels stay on screen")
cp:place(0, 100, cp.w, cp.h)
M.steps(1)
check(cp.panels.library.gui.AbsolutePosition.X >= -0.5, "the Library panel isn't off the left edge (" .. cp.panels.library.gui.AbsolutePosition.X .. ")")
cp:place(5000, 100, cp.w, cp.h)
M.steps(1)
local ip = cp.panels.inspector.gui
check(ip.AbsolutePosition.X + ip.AbsoluteSize.X <= workspace.CurrentCamera.ViewportSize.X + 0.5, "the Inspector panel isn't off the right edge")
cp:setPanel("library", false)
cp:place(0, 100, cp.w, cp.h)
M.steps(1)
check(cp.x < 50, "with the Library closed the window may go to the left edge (" .. cp.x .. ")")
cp:setPanel("library", true)
M.steps(1)
check(cp.panels.library.gui.AbsolutePosition.X >= -0.5, "opening the Library moves the window over to show it")

section("I2: no Frost in Compact")
UserSettings():GetService("UserGameSettings").SavedQualityLevel = { Name = "QualityLevel10", Value = 10 }
E.settings:set("glass", "Frost")
M.steps(2)
check(ui.frost:available(), "(Frost available: high graphics)")
check(wm:anyOpen(), "(a New window is still open, hidden)")
eq(ui.frost:wanted(), false, "Frost isn't wanted in Compact")
E.settings:set("glass", "Tint")

section("I4: the Merge window leaves the mouse to the game")
eq(E.modal, true, "the Compact window frees the mouse")
wm:open("merge")
M.steps(1)
eq(E.modal, false, "with the Merge window open it doesn't (you play while merging)")
wm:close("merge")
M.steps(1)
eq(E.modal, true, "and does again when it closes")

section("I6: the Dock after hosted pages")
cp:showTab("settings")
M.steps(1)
cp:showTab("help")
M.steps(1)
cp:setPanel("inspector", false)
M.steps(1)
E.settings:set("interface", "New")
M.steps(2)
eq(wm:isOpen("settings"), true, "the New Settings window is still open")
eq(ui.dock.buttons.settings.kind, "primary", "and its Dock button is lit")

section("I1: the New Inspector keeps timing after Compact")
M.steps(2)
eq(E.pipe.timing, timing0, "timing as before Compact (" .. tostring(timing0) .. ")")
E.modes:request("create")
M.steps(3)
E.modes:request("idle")
M.steps(3)
eq(E.pipe.timing, timing0, "and after a mode change")
finish()
