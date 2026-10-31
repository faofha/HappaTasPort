-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5a: the Controls window: rebinding a key (the binding press never runs a control),
-- Esc cancels, ✕ unbinds, conflicts marked (not Pause / Unpause), changes from elsewhere shown, reset
-- (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local ui = E.ui
local wm = ui.wm
local Controls = __T3("engine/controls")
local c = E.controls
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end

section("the window")
check(wm.defs.controls ~= nil, "defined")
eq(wm.defs.controls.w, 380, "380 wide")
eq(wm.defs.controls.h, 560, "560 high")
check(ui.dock.buttons.controls ~= nil, "a Dock button")
wm:open("controls")
local cw = ui.controlsWin
check(cw ~= nil, "ui.controlsWin")
for _, ctl in ipairs(Controls.LIST) do
	local r = cw.rows[ctl.key]
	check(r ~= nil and UIH.find(r.row.gui, ctl.v2) ~= nil, "a row named " .. ctl.v2)
end
eq(cw.rows.create.key.label.Text, "2", "Create shows its key")
local function reveal(key)
	local r = cw.rows[key]
	cw.list.CanvasPosition = Vector2.new(0, math.max(0, r.row.gui.Position.Y.Offset - 40))
	return r
end

section("rebind with a key")
local r = reveal("lookAround")
UIH.click(r.key.gui)
eq(r.key.label.Text, "Press a key…", "waiting for a key")
eq(E.typing.rebinding, true, "the engine's keys are off meanwhile")
UIH.key(Enum.KeyCode.K)
eq(c:get("lookAround"), "K", "bound to K")
eq(r.key.label.Text, "K", "shown")
eq(E.typing.rebinding, false, "keys on again")

section("binding Left Click by clicking the key pill again")
r = reveal("forward")
UIH.click(r.key.gui)
UIH.click(r.key.gui)
M.steps(2)
eq(c:get("forward"), "Left Click", "bound to Left Click")
eq(r.key.label.Text, "Left Click", "shown")
eq(E.typing.rebinding, false, "the press's own release didn't start waiting again")
c:set("forward", "T")

section("the binding press doesn't run the control it had (V2.37.2)")
E.modes:request("create")
M.steps(3)
eq(E.mode, 2, "Create")
r = reveal("create")
UIH.click(r.key.gui)
UIH.key(Enum.KeyCode.One)
M.steps(3)
eq(c:get("create"), "1", "Create on 1")
eq(E.mode, 2, "the press that bound it didn't go Idle (1 was Idle's key)")

section("conflicts")
r = cw.rows.idle
eq(r.conflict, true, "Idle and Create both on 1: marked")
eq(cw.rows.create.conflict, true, "both of them")
check(r.row.desc and r.row.desc.Text:find("Create", 1, true) ~= nil, "a note names the other (" .. tostring(r.row.desc and r.row.desc.Text) .. ")")
eq(cw.rows.pause.conflict, false, "Pause and Unpause share Left Click by design: not marked")
eq(cw.rows.unpause.conflict, false, "Unpause neither")

section("Esc cancels")
r = reveal("create")
UIH.click(r.key.gui)
UIH.key(Enum.KeyCode.Escape)
eq(c:get("create"), "1", "unchanged")
eq(r.key.label.Text, "1", "shown again")
eq(E.typing.rebinding, false, "keys on again")

section("✕ unbinds")
UIH.click(r.clear.gui)
eq(c:get("create"), "None", "None")
eq(r.key.label.Text, "None", "shown")
eq(cw.rows.idle.conflict, false, "no conflict any more")

section("a key changed elsewhere shows (the settings file, another window)")
c:set("optimize", "P")
eq(cw.rows.optimize.key.label.Text, "P", "shown at once")

section("reset buttons")
r = reveal("optimize")
eq(r.row.reset.gui.Visible, true, "not the default: ↺")
UIH.click(r.row.reset.gui)
eq(c:get("optimize"), "Q", "back to Q")
UIH.click(cw.resetAll.gui)
for _, ctl in ipairs(Controls.LIST) do eq(c:get(ctl.key), ctl.default, "Reset all: " .. ctl.key) end

section("Unload")
E.modes:request("idle")
M.steps(2)
getgenv().__HappaTAS3.Unload()
M.steps(2)
c:set("optimize", "P")
eq(cw.rows.optimize.key.label.Text, "Q", "no listener left")
eq(E.typing.rebinding, false, "never left waiting")
finish()
