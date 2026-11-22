-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1 Compact (Task 4): the main window: title bar, tabs, pages, panels, drag, resize, fold,
-- saving, kept on screen (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local CONFIG = __T3("config")
local Files = __T3("platform/files")
local Env = __T3("platform/env")
local HttpService = game:GetService("HttpService")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
E.settings:set("interface", "Compact")
M.steps(2)
local cp = ui.compact
local sw, sh = ui.wm:screen()

section("the window")
check(cp.gui ~= nil and cp.gui.Visible, "shown")
eq(cp.w .. "x" .. cp.h, "700x500", "700 x 500")
near(cp.x + cp.w / 2, sw / 2, 1, "centred across")
check(UIH.find(cp.titleBar, "HAPPATAS") ~= nil, "HAPPATAS in the title bar")
check(UIH.find(cp.titleBar, "V" .. CONFIG.VERSION) ~= nil, "the version chip")
check(UIH.find(cp.titleBar, "LIBRARY") ~= nil and UIH.find(cp.titleBar, "INSPECTOR") ~= nil, "the panel chips")
check(cp.search ~= nil and cp.search.box:IsDescendantOf(cp.titleBar), "the search box")
check(cp.status ~= nil and cp.status.gui:IsDescendantOf(cp.titleBar), "the status chip")
check(cp.minimise ~= nil, "the minimise chip")
for _, name in ipairs({ "CONTROLS", "SETTINGS", "HELP", "ABOUT" }) do check(UIH.find(cp.gui, name) ~= nil, "a tab " .. name) end
eq(cp.tab, "controls", "CONTROLS first")
eq(cp.pages.controls.Visible, true, "its page shown")
eq(E.modal, true, "the window frees the mouse")

section("tabs")
UIH.click(cp.tabs.settings.gui)
eq(cp.tab, "settings", "SETTINGS")
eq(cp.pages.settings.Visible, true, "its page")
eq(cp.pages.controls.Visible, false, "the other hidden")
cp:showTab("controls")

section("drag and resize")
local x0, y0 = cp.x, cp.y
local tb = cp.titleBar
local from = tb.AbsolutePosition + Vector2.new(330, 10)
UIH.drag(from, from + Vector2.new(40, 30), 4)
near(cp.x, x0 + 40 / ui.root.scale.Scale, 1, "moved across")
near(cp.y, y0 + 30 / ui.root.scale.Scale, 1, "and down")
local g = cp.grip
UIH.drag(UIH.center(g), UIH.center(g) - Vector2.new(400, 300), 4)
eq(cp.w .. "x" .. cp.h, "560x400", "never below 560 x 400")
UIH.drag(UIH.center(g), UIH.center(g) + Vector2.new(100, 50), 4)
check(cp.w > 560 and cp.h > 400, "grows")

section("panels")
UIH.click(cp.libraryChip.gui)
eq(cp.panels.library.open, true, "LIBRARY opens the left panel")
check(cp.panels.library.gui.Visible and cp.panels.library.gui.AbsolutePosition.X < cp.gui.AbsolutePosition.X, "docked on the left")
UIH.click(cp.inspectorChip.gui)
eq(cp.panels.inspector.open, true, "INSPECTOR opens the right panel")
check(cp.panels.inspector.gui.AbsolutePosition.X > cp.gui.AbsolutePosition.X + cp.gui.AbsoluteSize.X - 1, "docked on the right")

section("fold")
UIH.click(cp.minimise.gui)
eq(cp.folded, true, "folded")
eq(cp.inline.Visible, false, "pages hidden (their frame; each page keeps its tab state)")
eq(cp.panels.library.gui.Visible, false, "panels hidden")
eq(cp:modal(), false, "folded: the mouse stays with the game")
eq(E.modal, false, "(E.modal too)")
eq(cp:pointerOver() ~= nil, true, "still answers pointerOver")
UIH.click(cp.minimise.gui)
eq(cp.folded, false, "unfolded")
eq(cp.panels.library.gui.Visible, true, "the Library panel back")

section("saving")
cp:showTab("help")
cp:save()
M.steps(60)
local saved = E.settingsFile:getUi().compact
check(saved ~= nil and saved.w == cp.w and saved.tab == "help" and saved.library == true, "saved rect, tab, panel")
E.settingsFile:write()
local raw = Files.new(Env):read("HappaTasPort/Settings3.json")
local j = HttpService:JSONDecode(raw)
eq(j.ui.compact and j.ui.compact.tab, "help", "in the file")
-- (Review Focus 3: a rect saved off screen comes back on screen)
j.ui.compact.x = 5000
j.ui.compact.y = -300
j.ui.compact.folded = false
Files.new(Env):write("HappaTasPort/Settings3.json", HttpService:JSONEncode(j))
check(boot(30), "boots again")
E = getgenv().__HappaTAS3_T.engine
ui = E.ui
M.steps(2)
cp = ui.compact
check(cp ~= nil, "Compact again (the saved interface)")
eq(cp.tab, "help", "the saved tab")
sw, sh = ui.wm:screen()
check(cp.x >= 0 and cp.x + cp.w <= sw + 0.5, "on screen across (" .. cp.x .. ")")
check(cp.y >= 0 and cp.y < sh, "on screen down (" .. cp.y .. ")")
cp:place(sw - cp.w, 100, cp.w, cp.h)
M.viewport = Vector2.new(1280, 720)
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Fire()
M.steps(2)
sw = ui.wm:screen()
check(cp.x + cp.w <= sw + 0.5, "a smaller screen keeps it on screen")

section("hidden by the Menu key")
UIH.key(Enum.KeyCode.M)
eq(ui.root.gui.Enabled, false, "hidden")
eq(E.modal, false, "the mouse back to the game")
UIH.key(Enum.KeyCode.M)
eq(ui.root.gui.Enabled, true, "shown")
E.settings:set("interface", "New")
M.steps(2)
eq(cp.gui.Visible, false, "New: the Compact window hidden")
finish()
