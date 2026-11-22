-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1 Compact (Task 3): the compact kit: layered borders, the accent line, sections, chips, tabs
-- (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local th = ui.theme
local CK = __T3("ui/compact/kit")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
th:setCompact(true)
local holder = Instance.new("Frame")
holder.Size = UDim2.new(0, 400, 0, 300)
holder.Position = UDim2.new(0, 100, 0, 100)
holder.Parent = ui.root.layer
local ctx = { E = E, ui = ui, theme = th, tween = ui.tween, typing = E.typing,
	pointer = { add = function(r) ui.pointer:add(r); return r end, remove = function(r) ui.pointer:remove(r) end } }
local listeners0 = #th.listeners

section("a section")
local sec = CK.section(ctx, holder, "run")
eq(sec.title.Text, "RUN", "its title in capitals")
eq(sec.title.TextColor3, th.c.accent, "in the accent")
local line = sec.gui:FindFirstChild("AccentLine")
check(line ~= nil and line.Size.Y.Offset == 2, "a 2 px accent line on top")
eq(line and line.BackgroundColor3, th.c.accent, "in the accent")
local stroke = sec.gui:FindFirstChildOfClass("UIStroke")
check(stroke ~= nil and stroke.Color == th.shades.outline, "an outline stroke (the layered border)")
eq(sec.gui.BorderColor3, th.shades.border, "and the dark inner border")
eq(sec.gui.BackgroundColor3, th.shades.inline, "the inline shade")
check(sec.body:FindFirstChildOfClass("UIListLayout") ~= nil, "a body that lists its rows")

section("a chip")
local clicks = 0
local chip = CK.chip(ctx, holder, "LIBRARY", { button = true, onClick = function() clicks = clicks + 1 end })
chip.gui.Position = UDim2.new(0, 10, 0, 200)
chip.gui.Size = UDim2.new(0, 70, 0, 18)
eq(chip.label.Text, "LIBRARY", "its text")
eq(chip.gui.BackgroundColor3, th.shades.element, "the element shade")
UIH.click(chip.gui)
eq(clicks, 1, "a click")
chip:set("FILES")
eq(chip.label.Text, "FILES", "set changes the text")

section("a tab")
local tabClicks = 0
local tab = CK.tab(ctx, holder, "settings", function() tabClicks = tabClicks + 1 end)
tab.gui.Position = UDim2.new(0, 10, 0, 240)
eq(tab.gui.Size, UDim2.new(0, 90, 0, 22), "90 x 22")
eq(tab.label.Text, "SETTINGS", "in capitals")
tab:setActive(true)
eq(tab.underline.Visible, true, "active: the underline")
eq(tab.label.TextColor3, th.c.accent, "active: accent text")
eq(tab.label.TextTransparency, 0, "active: solid text")
tab:setActive(false)
eq(tab.underline.Visible, false, "inactive: no underline")
eq(tab.label.TextTransparency, 0.48, "inactive: dimmed text")
UIH.click(tab.gui)
eq(tabClicks, 1, "a click calls onClick once")

section("a new accent repaints")
E.settings:set("accentColor", "#F85149")
eq(sec.title.TextColor3, th.c.accent, "the section title")
eq(line.BackgroundColor3, th.c.accent, "the accent line")
tab:setActive(true)
eq(tab.underline.BackgroundColor3, th.c.accent, "the tab underline")
E.settings:set("accentColor", "#3FB950")

section("destroy")
sec:destroy()
chip:destroy()
tab:destroy()
eq(sec.gui.Parent, nil, "the section is gone")
eq(#th.listeners, listeners0, "no theme listener left")
th:setCompact(false)
holder:Destroy()
finish()
