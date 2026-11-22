-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1 Tasability (Task 5): the KEYS list: a key box per control, a click waits for a key, × clears,
-- Reset all, conflicts marked with "Also: ..." in its hover line (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local Controls = __T3("engine/controls")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local c = E.controls
E.settings:set("interface", "Tasability")
M.steps(2)
local cp = ui.compact
cp:showTab("controls")
M.steps(2)
local keys = cp.keys
check(keys ~= nil, "the KEYS list")
eq(cp.hosted.controls, nil, "not the New Controls window")

section("a key box per control, in order")
local lastY = -1
for _, ctl in ipairs(Controls.LIST) do
	local kb = keys.rows[ctl.key]
	check(kb ~= nil, ctl.key)
	if kb then
		eq(kb.key.Text, c:get(ctl.key), ctl.key .. " shows its key")
		check(kb.gui.Position.Y.Offset > lastY, ctl.key .. " below the one before")
		lastY = kb.gui.Position.Y.Offset
	end
end

section("rebinding")
local back = keys.rows.back
UIH.click(back.gui.AbsolutePosition + Vector2.new(10, 11))
M.steps(1)
eq(back.key.Text, "...", "waiting")
eq(E.typing.rebinding, true, "keys off while waiting")
UIH.key(Enum.KeyCode.G)
M.steps(1)
eq(c:get("back"), "G", "G binds")
eq(back.key.Text, "G", "and shows")
UIH.click(back.gui.AbsolutePosition + Vector2.new(10, 11))
UIH.key(Enum.KeyCode.Backspace)
M.steps(1)
eq(c:get("back"), "Backspace", "Backspace binds too (Review Focus 3)")
UIH.click(back.clear.gui)
M.steps(1)
eq(c:get("back"), "None", "× clears to None")

section("conflicts")
c:set("back", "T")
c:set("forward", "T")
M.steps(1)
eq(keys.rows.back.conflict, true, "back marked")
eq(keys.rows.forward.conflict, true, "forward marked")
UIH.move(UIH.center(keys.rows.back.gui))
M.steps(1)
check(keys.hover.Text:find("Also:", 1, true) ~= nil, "hovering says which other control shares it (" .. keys.hover.Text .. ")")
c:set("pause", "Left Click")
c:set("unpause", "Left Click")
M.steps(1)
eq(keys.rows.pause.conflict, false, "Pause / Unpause may share")

section("Reset all")
do
	local pg = cp.pages.controls
	pg.CanvasPosition = Vector2.new(0, math.max(0, keys.resetAll.gui.AbsolutePosition.Y - pg.AbsolutePosition.Y + pg.CanvasPosition.Y - 60))
	M.steps(1)
end
local over = ui.pointer:over(UIH.center(keys.resetAll.gui))
check(over ~= nil and over.gui == keys.resetAll.gui, "after scrolling, a click lands on what is under it (click areas follow the scroll)")
UIH.click(keys.resetAll.gui)
M.steps(1)
local off = {}
for _, ctl in ipairs(Controls.LIST) do if c:get(ctl.key) ~= ctl.default then off[#off + 1] = ctl.key end end
eq(#off, 0, "every default back (" .. table.concat(off, ", ") .. ")")

section("waiting, then switching interface or unloading (Review Focus 3)")
cp.pages.controls.CanvasPosition = Vector2.new(0, 0)
M.steps(1)
UIH.click(back.gui.AbsolutePosition + Vector2.new(10, 11))
M.steps(1)
E.settings:set("interface", "New")
M.steps(2)
eq(E.typing.rebinding, false, "the switch ends the wait")
UIH.key(Enum.KeyCode.Y)
M.steps(1)
local backDefault
for _, x in ipairs(Controls.LIST) do if x.key == "back" then backDefault = x.default end end
eq(c:get("back"), backDefault, "the next key binds nothing")
E.settings:set("interface", "Tasability")
M.steps(2)
cp:showTab("controls")
M.steps(1)
cp.pages.controls.CanvasPosition = Vector2.new(0, 0)
M.steps(1)
UIH.click(back.gui.AbsolutePosition + Vector2.new(10, 11))
M.steps(1)
getgenv().__HappaTAS3.Unload()
M.steps(3)
eq(E.typing.rebinding, false, "Unload ends the wait")
finish()
