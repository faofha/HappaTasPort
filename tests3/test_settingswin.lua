-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5a: the Settings window: a control of the right kind for every setting, changes made
-- elsewhere shown at once (Review Focus 4), reset buttons and Reset section, search (typing never runs a
-- control: Review Focus 1), section chips, saved looks (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local ui = E.ui
local wm = ui.wm
local Settings = __T3("engine/settings")
local s = E.settings
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end

section("the window and its Dock button")
check(wm.defs.settings ~= nil, "defined")
eq(wm.defs.settings.w, 420, "420 wide")
eq(wm.defs.settings.h, 640, "640 high")
check(ui.dock.buttons.settings ~= nil, "a Dock button")
UIH.click(ui.dock.buttons.settings.gui)
eq(wm:isOpen("settings"), true, "the Dock button opens it")
local sw = ui.settingsWin
check(sw ~= nil and sw.rows ~= nil, "ui.settingsWin with its rows")
-- brings a row into the list's view (the list scrolls, like a wheel would)
local function reveal(key)
	local r = sw.rows[key]
	local y = r.row.gui.Position.Y.Offset
	sw.list.CanvasPosition = Vector2.new(0, math.max(0, y - 40))
	return r
end

section("every setting has a control of its kind")
local BEZIER = { bezierX1 = true, bezierY1 = true, bezierX2 = true, bezierY2 = true }
local n = 0
for _, def in ipairs(Settings.SCHEMA) do
	local r = sw.rows[def.key]
	if BEZIER[def.key] then
		eq(r, nil, def.key .. ": shown by the curve editor, not a row")
	else
		check(r ~= nil, "a row for " .. def.key)
		if r then
			n = n + 1
			local want = (def.kind == "toggle" and "toggle") or (def.kind == "color" and "swatch") or (def.key == "theme" and "theme")
				or (def.kind == "choice" and (#def.options <= 4 and "segmented" or "dropdown"))
				or (def.kind == "number" and ((def.min and def.max) and "slider" or "field"))
			eq(r.kind, want, def.key .. " is a " .. tostring(want))
			check(UIH.find(r.row.gui, def.name) ~= nil, def.key .. " shows its name (" .. tostring(def.name) .. ")")
		end
	end
end
eq(n, #Settings.SCHEMA - 4, "a row each")
check(sw.bezier ~= nil, "the curve editor")
eq(sw.rows.font.ctl.fontPreview, true, "the font list previews fonts")
eq(sw.rows.glassTransparency.ctl.label.Text, "54%", "a percentage")
eq(sw.rows.windowCorners.ctl.label.Text, "16px", "pixels")
eq(sw.rows.animationLength.ctl.label.Text, "0.2s", "seconds")

section("a toggle row writes the setting")
local sh = reveal("shadows")
UIH.click(sh.ctl.gui)
eq(s:get("shadows"), 0, "Shadows off")
UIH.click(sh.ctl.gui)
eq(s:get("shadows"), 1, "and on")

section("a change made elsewhere shows at once (Review Focus 4)")
local tg = sw.rows.speedHack.ctl
local inst = tg.gui
s:set("speedHack", 1)
eq(tg.value, true, "the toggle shows it in the same frame")
eq(sw.rows.speedHack.ctl.gui, inst, "the same control (not rebuilt)")
s:set("speedHack", 0)
eq(tg.value, false, "and off")
s:set("glass", "Frost")
eq(sw.rows.glass.ctl.value, "Frost", "a choice too")
s:set("glass", "Tint")
s:set("accentColor", "#FF0000")
eq(sw.rows.accentColor.ctl.swatch.BackgroundColor3, Color3.fromHex("FF0000"), "a colour too")
s:set("accentColor", "#3F7CF0")

section("reset buttons")
local ps = reveal("playbackSpeed")
eq(ps.row.reset.gui.Visible, false, "the default: no reset button")
s:set("playbackSpeed", 2)
eq(ps.row.reset.gui.Visible, true, "not the default: the reset button")
UIH.click(ps.row.reset.gui)
eq(s:get("playbackSpeed"), 1, "a click resets it")
eq(ps.row.reset.gui.Visible, false, "and hides the button")

section("Reset section")
local sec = sw.sections["Playback"]
sw.list.CanvasPosition = Vector2.new(0, sec.y)
eq(sec.reset.gui.Visible, false, "no RESET SECTION while all are default")
s:set("playbackSpeed", 3)
s:set("restartWhenTesting", 0)
eq(sec.reset.gui.Visible, true, "RESET SECTION shows")
UIH.click(sec.reset.gui)
eq(s:get("playbackSpeed"), 1, "playbackSpeed back")
eq(s:get("restartWhenTesting"), 1, "restartWhenTesting back")
eq(sec.reset.gui.Visible, false, "and hides")

section("search (Review Focus 1)")
local box = sw.search.box
box:CaptureFocus()
M.pressKey(Enum.KeyCode.Two)
M.releaseKey(Enum.KeyCode.Two)
M.steps(3)
eq(E.mode, 1, "typing 2 in the search box doesn't Create")
box.Text = "frame step"
local shown = {}
for key, r in pairs(sw.rows) do if r.row.gui.Visible then shown[#shown + 1] = key end end
eq(table.concat(shown, ","), "speedHackFrameStep", "one row")
local secShown = {}
for name, sc in pairs(sw.sections) do if sc.header.Visible then secShown[#secShown + 1] = name end end
eq(table.concat(secShown, ","), "Speed hack", "only its section")
box.Text = "COLOUR"
local m = 0
for _, r in pairs(sw.rows) do if r.row.gui.Visible then m = m + 1 end end
check(m >= 5, "case-insensitive, names and explanations (" .. m .. " rows)")
box.Text = ""
local all = 0
for _, r in pairs(sw.rows) do if r.row.gui.Visible then all = all + 1 end end
eq(all, #Settings.SCHEMA - 4, "empty: every row again")
box:ReleaseFocus()

section("a row scrolled out of the list takes no click (it isn't shown there)")
sw.list.CanvasPosition = Vector2.new(0, 0)
local hidden = sw.rows.syncLighting
local before = E.settings:get("syncLighting")
check(hidden.ctl.gui.AbsolutePosition.Y > sw.list.AbsolutePosition.Y + sw.list.AbsoluteSize.Y, "World sync is below the list's view")
UIH.click(UIH.center(hidden.ctl.gui))
eq(E.settings:get("syncLighting"), before, "a click there does nothing")

section("section chips scroll to their section")
UIH.click(sw.chips["World sync"].gui)
eq(sw.list.CanvasPosition.Y, sw.sections["World sync"].y, "the list scrolled to World sync")
UIH.click(sw.chips["Appearance"].gui)
eq(sw.list.CanvasPosition.Y, 0, "Appearance at the top")

section("saved looks")
local th = reveal("theme")
s:set("accentColor", "#112233")
UIH.click(th.ctl.saveAs.gui)
check(th.ctl.nameField ~= nil and th.ctl.nameField.gui.Visible, "Save as… asks for a name")
UIH.typeInto(th.ctl.nameField.box, "Night", true)
eq(s:get("theme"), "Night", "the look is called Night")
eq(E.settingsFile:getUi().themes.Night.accentColor, "#112233", "saved with its accent")
check(table.find(th.ctl.dropdown.options, "Night") ~= nil, "in the list")
s:set("accentColor", "#3F7CF0")
UIH.click(th.ctl.dropdown.gui)
UIH.click(UIH.find(th.ctl.dropdown.list, "Night"))
eq(s:get("accentColor"), "#112233", "picking Night puts its accent back")
UIH.click(th.ctl.dropdown.gui)
UIH.click(UIH.find(th.ctl.dropdown.list, "Default"))
eq(s:get("accentColor"), "#3F7CF0", "Default: the default look")
eq(s:get("theme"), "Default", "theme Default")
UIH.click(th.ctl.saveAs.gui)
UIH.typeInto(th.ctl.nameField.box, "default", true)
eq(E.settingsFile:getUi().themes.default, nil, "\"Default\" can't be overwritten (any case)")
eq(E.settingsFile:getUi().themes.Default, nil, "nor saved")

section("the curve editor shows with Custom easing")
s:set("easing", "Quad")
eq(sw.bezier.gui.Visible, false, "hidden for a Roblox easing")
s:set("easing", "Custom")
eq(sw.bezier.gui.Visible, true, "shown for Custom")
s:set("easing", "Preset")

section("Unload")
getgenv().__HappaTAS3.Unload()
M.steps(2)
s:set("speedHack", 1)
eq(sw.rows.speedHack.ctl.value, false, "no listener left after Unload")
finish()
