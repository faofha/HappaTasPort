-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1 Compact (Task 5): Compact hosts the New interface's pages (Settings, Help, About, Controls)
-- and side panels (Library, Inspector) through ui/compact/host, never writing ui.<x>Win; the title-bar search
-- (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local Settings = __T3("engine/settings")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local function handlers()
	local n = 0
	for _, list in pairs(T.pipe.stages) do n = n + #list end
	return n
end
local wmSettings = ui.settingsWin
E.settings:set("interface", "Tasability")
M.steps(2)
local cp = ui.compact
local firstHandlers = handlers()

section("pages and panels are hosted")
cp:showTab("settings")
cp:showTab("help")
cp:showTab("about")
cp:showTab("controls")
cp:setPanel("library", true)
cp:setPanel("inspector", true)
M.steps(2)
-- (V3.1: SETTINGS is the Tasability page of its own, test_tsettings, not a hosted window)
for _, id in ipairs({ "help", "about", "controls", "library", "inspector" }) do
	check(cp.hosted[id] ~= nil and cp.hosted[id].obj ~= nil, id .. " hosted")
end
check(ui.settingsWin == wmSettings, "ui.settingsWin is never the hosted copy")
check(ui.helpWin == nil or ui.helpWin ~= cp.hosted.help.obj, "nor ui.helpWin")
check(cp.hosted.help.win.hosted and cp.hosted.help.win.compact, "the fake window says hosted / compact")

section("the hosted Settings")
local sw = cp.settingsPage
check(sw.rows.accentColor ~= nil, "the accent row")
local leaked = {}
for _, def in ipairs(Settings.SCHEMA) do if def.newOnly and sw.rows[def.key] then leaked[#leaked + 1] = def.key end end
eq(#leaked, 0, "no New-only rows (" .. table.concat(leaked, ", ") .. ")")
check(sw.scroll:IsDescendantOf(cp.pages.settings), "inside the SETTINGS tab")

section("the title-bar search")
cp:showTab("controls")
UIH.typeInto(cp.search.box, "accent", false)
M.steps(1)
eq(cp.tab, "settings", "typing shows SETTINGS")
eq(sw.rows.accentColor.gui.Visible, true, "the accent row matches")
eq(sw.rows.textSize.gui.Visible, false, "Text size doesn't")
-- (Review Focus 2: typing never fires a HappaTAS key)
cp.search.box:CaptureFocus()
M.steps(1)
UIH.key(Enum.KeyCode.Two)
M.steps(2)
eq(E.mode, 1, "the Create key while typing in the search: still Idle")
cp.search.box:ReleaseFocus()
UIH.typeInto(cp.search.box, "", false)
M.steps(1)
eq(sw.rows.textSize.gui.Visible, true, "cleared: every row again")

section("Help, About, Library, Inspector")
check(#cp.hosted.help.obj.topicRows > 5, "HELP lists the topics")
check(UIH.find(cp.hosted.about.frame, "Credits") ~= nil, "ABOUT has the credits")
check(cp.hosted.library.frame:IsDescendantOf(cp.panels.library.body), "the Library in the left panel")
check(cp.hosted.inspector.frame:IsDescendantOf(cp.panels.inspector.body), "the Inspector in the right panel")
eq(cp.hosted.library.win.open, true, "the Library panel open: its window open")
do
	-- (the Library's narrow layout: every button, the name field and the move menu inside the panel)
	local lw = cp.hosted.library.obj
	local f = cp.hosted.library.frame
	local fx, fw = f.AbsolutePosition.X, f.AbsoluteSize.X
	local out = {}
	local function inside(name, g)
		local x, w = g.AbsolutePosition.X, g.AbsoluteSize.X
		if x < fx - 0.5 or x + w > fx + fw + 0.5 then out[#out + 1] = name end
	end
	for key, b in pairs(lw.buttons) do inside(key, b.gui) end
	inside("name field", lw.nameField.gui)
	inside("move menu", lw.moveDrop.gui)
	inside("search", lw.search.gui)
	inside("sort", lw.sort.gui)
	eq(#out, 0, "the Library fits its panel (" .. table.concat(out, ", ") .. ")")
	local ys = {}
	for key, b in pairs(lw.buttons) do ys[#ys + 1] = { key, b.gui.AbsolutePosition, b.gui.AbsoluteSize } end
	local overlap = {}
	for i = 1, #ys do
		for j = i + 1, #ys do
			local a, b = ys[i], ys[j]
			if a[2].X < b[2].X + b[3].X and b[2].X < a[2].X + a[3].X and a[2].Y < b[2].Y + b[3].Y and b[2].Y < a[2].Y + a[3].Y then
				overlap[#overlap + 1] = a[1] .. "/" .. b[1]
			end
		end
	end
	eq(#overlap, 0, "no two buttons overlap (" .. table.concat(overlap, ", ") .. ")")
end
cp:setPanel("library", false)
eq(cp.hosted.library.win.open, false, "closed with the panel")
check(cp.panels.library.width >= 300, "a Library panel wide enough for its narrow layout")
check(cp.panels.inspector.width >= 260, "an Inspector panel as wide as the Inspector's minimum")

section("rebinding then switching (Review Focus 2)")
local cw = cp.hosted.controls.obj
local keyRow
for _, r in pairs(cw.rows or {}) do
	if r.key and (not keyRow or r.key.gui.AbsolutePosition.Y < keyRow.key.gui.AbsolutePosition.Y) then keyRow = r end
end
check(keyRow ~= nil, "a key row")
if keyRow then
	cp:showTab("controls")
	M.steps(1)
	UIH.click(keyRow.key and keyRow.key.gui or keyRow.gui)
	M.steps(1)
	eq(E.typing.rebinding, true, "a click on a key starts the wait")
end
E.settings:set("interface", "New")
M.steps(2)
eq(E.typing.rebinding == true, false, "the switch ends the wait for a key")
eq(cw.waiting, nil, "and the hosted key list stops waiting")

section("New -> Compact -> Classic -> Compact (Review Focus 4)")
local rowsBefore = 0
for _ in pairs(sw.rows) do rowsBefore = rowsBefore + 1 end
E.settings:set("interface", "Tasability")
M.steps(2)
E.settings:set("interface", "Classic")
M.steps(2)
E.settings:set("interface", "Tasability")
M.steps(2)
check(cp.settingsPage == sw, "the same SETTINGS page")
local rowsAfter = 0
for _ in pairs(sw.rows) do rowsAfter = rowsAfter + 1 end
eq(rowsAfter, rowsBefore, "no duplicated rows")
local n = 0
for _, ch in ipairs(cp.pages.settings:GetChildren()) do if ch.Name == "SettingsPage" then n = n + 1 end end
eq(n, 1, "one SETTINGS page")
cp:setPanel("inspector", false)
M.steps(1)
eq(handlers(), firstHandlers, "no extra pipeline handlers with the same panels shut (" .. handlers() .. " vs " .. firstHandlers .. ")")
finish()
