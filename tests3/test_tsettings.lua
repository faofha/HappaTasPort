-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1 Tasability (Task 4): its own SETTINGS page: a part per shown row (checkbox, value box,
-- dropdown, colour box, the Theme row, a checkbox per option of a multi row), two balanced columns of sections in
-- schema order, RESET per section, descriptions in a hover strip, the title-bar search, live (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local s = E.settings
local Settings = __T3("engine/settings")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
s:set("interface", "Tasability")
M.steps(2)
local cp = ui.compact
cp:showTab("settings")
M.steps(2)
local page = cp.settingsPage
check(page ~= nil, "the SETTINGS page")
eq(cp.hosted.settings, nil, "not the New Settings window")

local SECTIONS = { "Appearance", "Playback", "Create", "Speed hack", "Glide", "Inputs", "World sync", "Interface" }
local BEZIER = { bezierX1 = true, bezierY1 = true, bezierX2 = true, bezierY2 = true }
local function shown(def)
	return table.find(SECTIONS, def.section) and not BEZIER[def.key] and not def.hidden and not def.newOnly
end

section("a part per shown row, of the right kind")
local missing, wrong, extra = {}, {}, {}
for _, def in ipairs(Settings.SCHEMA) do
	local r = page.rows[def.key]
	if shown(def) then
		if not r then missing[#missing + 1] = def.key
		else
			local k = def.kind
			local ok = (k == "toggle" and r.part.box ~= nil and r.part.tick ~= nil)
				or (k == "number" and r.part.box ~= nil and r.part.box:IsA("TextBox"))
				or (k == "choice" and r.part.button ~= nil)
				or (k == "color" and r.part.swatch ~= nil)
				or (k == "text" and def.key == "theme" and r.part.button ~= nil and r.save ~= nil)
				or (k == "multi" and r.parts ~= nil and #r.parts == #def.options)
			if not ok then wrong[#wrong + 1] = def.key .. ":" .. k end
		end
	elseif r then extra[#extra + 1] = def.key end
end
eq(#missing, 0, "every shown row (" .. table.concat(missing, ", ") .. ")")
eq(#wrong, 0, "each with its part (" .. table.concat(wrong, ", ") .. ")")
eq(#extra, 0, "nothing else (" .. table.concat(extra, ", ") .. ")")
local multi = page.rows.speedHackModes
eq(multi and multi.parts[1].label.Text, "Speed Hack In: Idle", "a multi row: a checkbox per option")

section("two balanced columns, schema order")
local order = {}
for _, name in ipairs(SECTIONS) do if page.sections[name] then order[#order + 1] = name end end
local lastY = { left = -1, right = -1 }
local heights = { left = 0, right = 0 }
for _, name in ipairs(order) do
	local sec = page.sections[name]
	check(sec.column == "left" or sec.column == "right", name .. " in a column")
	check(sec.gui.Position.Y.Offset > lastY[sec.column], name .. " below the one before it in its column")
	lastY[sec.column] = sec.gui.Position.Y.Offset
	heights[sec.column] = heights[sec.column] + sec.gui.Size.Y.Offset
end
check(math.abs(heights.left - heights.right) <= 260, "the columns about as tall (" .. heights.left .. " / " .. heights.right .. ")")
eq(page.sections.Appearance.column, "left", "the first section on the left")
eq(page.sections.Appearance.title.Text, "APPEARANCE", "capital titles")

section("parts change their settings, settings change their parts")
local sync = page.rows.syncClientObjects.part
local function into(part)
	local sc = page.scroll
	sc.CanvasPosition = Vector2.new(0, math.max(0, part.gui.AbsolutePosition.Y - sc.AbsolutePosition.Y + sc.CanvasPosition.Y - 40))
	M.steps(1)
end
into(sync)
s:set("syncClientObjects", 1)
UIH.click(sync.gui)
eq(s:get("syncClientObjects"), 0, "a checkbox click")
s:set("syncClientObjects", 1)
M.steps(1)
eq(sync.value, true, "a change from elsewhere ticks it (Review Focus 2)")
local ts = page.rows.statsTextSize.part
UIH.typeInto(ts.box, "9999", true)
eq(s:get("statsTextSize"), Settings.byKey.statsTextSize.max, "9999: the maximum (Review Focus 1)")
eq(ts.box.Text, tostring(Settings.byKey.statsTextSize.max), "and the box shows it")
UIH.typeInto(ts.box, "abc", true)
eq(ts.box.Text, tostring(s:get("statsTextSize")), "abc: the stored value again")
ts.box:CaptureFocus()
ts.box.Text = "12"
s:set("statsTextSize", 20)
M.steps(1)
eq(ts.box.Text, "12", "a focused box keeps what is typed (Review Focus 2)")
ts.box:ReleaseFocus()
s:set("statsTextSize", 11)
local iface = page.rows.interface.part
eq(iface.value, "Tasability", "the Interface dropdown")
local idle = multi.parts[1]
into(idle)
UIH.click(idle.gui)
check(Settings and s:get("speedHackModes"):find("Idle", 1, true) ~= nil, "Speed Hack In: Idle ticked")
UIH.click(idle.gui)
eq(s:get("speedHackModes"), "Create", "and unticked")

section("the colour box")
local acc = page.rows.accentColor.part
s:set("accentColor", "#3FB950")
into(acc)
UIH.click(acc.swatch)
M.steps(1)
local pop
for _, d in ipairs(ui.root.layer:GetDescendants()) do if d.Name == "Popover" then pop = d end end
check(pop ~= nil, "the picker opens")
UIH.key(Enum.KeyCode.Escape)
M.steps(1)
eq(s:get("accentColor"), "#3FB950", "closed without Apply: the old accent")

section("the Theme row")
local th = page.rows.theme
UIH.typeInto(th.save.box, "MyLook", true)
eq(s:get("theme"), "MyLook", "Save as: saved and picked")
check(table.find(th.part.options, "MyLook") ~= nil, "in the dropdown")

section("RESET per section and the hover strip")
s:set("interpolatePlayback", 0)
local pb = page.sections.Playback
check(pb.reset ~= nil, "a RESET chip")
into(pb.reset)
UIH.click(pb.reset.gui)
eq(s:get("interpolatePlayback"), Settings.byKey.interpolatePlayback.default, "RESET: Playback's defaults")
s:set("accentColor", "#FF0000")
into(page.sections.Appearance.reset)
UIH.click(page.sections.Appearance.reset.gui)
eq(s:get("accentColor"), Settings.byKey.accentColor.default, "Appearance RESET: the Default look")
into(page.rows.syncClientObjects.part)
UIH.move(UIH.center(page.rows.syncClientObjects.part.gui))
M.steps(1)
eq(page.hover.Text, Settings.byKey.syncClientObjects.desc, "hovering a row shows its description")

section("search (Review Focus 4)")
page:filter("zzzz")
local any = false
for _, sec in pairs(page.sections) do if sec.gui.Visible then any = true end end
eq(any, false, "no match: no section shown")
page:filter("accent")
eq(page.rows.accentColor.part.gui.Visible, true, "accent row kept")
eq(page.rows.statsTextSize.part.gui.Visible, false, "others hidden")
page:filter("")
local all = true
for _, sec in pairs(page.sections) do if not sec.gui.Visible then all = false end end
eq(all, true, "cleared: every section")
UIH.typeInto(cp.search.box, "sync client", false)
M.steps(1)
eq(page.rows.syncClientObjects.part.gui.Visible, true, "the title-bar search filters the page")
eq(page.rows.accentColor.part.gui.Visible, false, "(the rest hidden)")
UIH.typeInto(cp.search.box, "", false)

section("scrolled rows don't take clicks outside the page (final review)")
page.scroll.CanvasPosition = Vector2.new(0, 200)
M.steps(1)
local ov = ui.pointer:over(UIH.center(cp.tabs.controls.gui))
check(ov ~= nil and ov.gui == cp.tabs.controls.gui, "a click on the CONTROLS tab hits the tab, not a hidden row")
local ov2 = ui.pointer:over(UIH.center(cp.libraryChip.gui))
check(ov2 ~= nil and ov2.gui == cp.libraryChip.gui, "nor the LIBRARY chip")
page.scroll.CanvasPosition = Vector2.new(0, 0)
cp:showTab("controls")
M.steps(1)
cp.pages.controls.CanvasPosition = Vector2.new(0, 200)
M.steps(1)
local ov3 = ui.pointer:over(UIH.center(cp.tabs.settings.gui))
check(ov3 ~= nil and ov3.gui == cp.tabs.settings.gui, "CONTROLS scrolled: the SETTINGS tab still hit")
cp.pages.controls.CanvasPosition = Vector2.new(0, 0)
cp:showTab("settings")
M.steps(1)

section("a dropdown open when the window folds (Review Focus 5)")
local function scrollTo(part)
	local sc = page.scroll
	sc.CanvasPosition = Vector2.new(0, math.max(0, part.gui.AbsolutePosition.Y - sc.AbsolutePosition.Y + sc.CanvasPosition.Y - 40))
	M.steps(1)
end
scrollTo(iface)
local o = ui.pointer:over(UIH.center(iface.button))
check(o ~= nil and o.gui == iface.button, "after scrolling the page, the click area follows")
UIH.click(iface.button)
M.steps(1)
check(iface.list ~= nil, "open")
cp:setFolded(true)
M.steps(1)
eq(iface.list, nil, "folding closes it")
cp:setFolded(false)
M.steps(1)
scrollTo(iface)
UIH.click(iface.button)
M.steps(1)
s:set("interface", "New")
M.steps(2)
eq(iface.list, nil, "switching interface closes it")
finish()
