-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5c: Interface: New / Classic. One interface is live, the other hidden and idle; the
-- switch takes effect in the same frame, keeps recording / merging / typing / rebinding sane, and the Menu
-- key shows / hides the live one (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local wm = ui.wm
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local function classicGui()
	for _, root in ipairs({ gethui and gethui(), game:GetService("CoreGui") }) do
		if root then
			for _, d in ipairs(root:GetDescendants()) do
				if d.Name == "HappaTASClassic" and d:IsA("ScreenGui") then return d end
			end
		end
	end
	return nil
end
local function uiHandlers()
	local n = 0
	for _, list in pairs(T.pipe.stages) do
		for _, e in ipairs(list) do
			if e.on and (e.name:find("^ui%.bar") or e.name:find("^ui%.inspector")) then n = n + 1 end
		end
	end
	return n
end

section("default New")
eq(E.settings:get("interface"), "New", "the setting")
eq(ui.live, "New", "the new interface is live")
eq(classicGui(), nil, "no classic interface built")

section("the switch takes effect at once")
E.settings:set("interface", "Classic")
eq(ui.live, "Classic", "Classic live")
eq(ui.root.gui.Enabled, false, "the new interface hidden in the same frame")
local cg = classicGui()
check(cg ~= nil and cg.Enabled, "the classic one shown in the same frame")
eq(cg and cg.AutoLocalize, false, "no auto-translation")
local classic = ui.classic
E.settings:set("interface", "New")
eq(ui.root.gui.Enabled, true, "back: the new one shown")
eq(cg.Enabled, false, "the classic one hidden")
E.settings:set("interface", "Classic")
eq(ui.classic, classic, "the classic interface isn't built again")
eq(classicGui(), cg, "the same ScreenGui")

section("a hidden interface does nothing")
E.modes:request("create")
M.steps(3)
E.modes:request("unpause")
M.steps(5)
eq(uiHandlers(), 0, "Classic live: no bar or Inspector handler")
M.writeLog = {}
M.steps(60, 1 / 60)
local writes = 0
for _, e in ipairs(M.writeLog) do if e[1]:IsDescendantOf(ui.root.gui) then writes = writes + 1 end end
M.writeLog = nil
eq(writes, 0, "nothing written under the hidden new interface over 60 recorded frames")
E.settings:set("interface", "New")
M.steps(2)
check(uiHandlers() > 0, "New live again: its handlers back")
UIH.key(Enum.KeyCode.M)
M.steps(2)
eq(ui.shown, false, "the Menu key hid it")
eq(uiHandlers(), 0, "hidden by the Menu key: no handler either")
UIH.key(Enum.KeyCode.M)
M.steps(2)
check(uiHandlers() > 0, "shown again")

section("switching at awkward moments")
-- (recording goes on)
local n0 = E.tl:count()
E.settings:set("interface", "Classic")
M.steps(10, 1 / 60)
eq(E.paused, false, "still recording")
check(E.tl:count() > n0 + 5, "frames keep coming")
E.settings:set("interface", "New")
E.modes:request("pause")
M.steps(2)
-- (a merge goes on)
local frames = E.tl:toV2All()
check(E.mergeRun:startMerge(frames, "after"), "a merge started")
E.settings:set("interface", "Classic")
M.steps(3)
eq(E.merge, true, "still merging")
E.settings:set("interface", "New")
E.mergeCanComplete = false
E.mergeRun:finishMerge()
M.steps(2)
-- (a text box focused: typing ends)
wm:open("settings")
M.steps(2)
local box = ui.settingsWin.search.box
box:CaptureFocus()
M.steps(1)
eq(E.typing:active(nil), true, "typing in Settings' search")
E.settings:set("interface", "Classic")
M.steps(1)
eq(E.typing:active(nil), false, "the switch ended the typing")
E.settings:set("interface", "New")
-- (a key being rebound: the wait ends)
wm:open("controls")
M.steps(2)
UIH.click(ui.controlsWin.rows.pause.key.gui)
M.steps(1)
eq(E.typing.rebinding, true, "waiting for a key")
E.settings:set("interface", "Classic")
M.steps(1)
eq(E.typing.rebinding, false, "the switch ended the wait")
eq(E.controls:get("pause"), "Left Click", "the key unchanged")
-- (Settings open frees the mouse; Classic with its menu closed doesn't)
E.settings:set("interface", "New")
M.steps(1)
eq(E.modal, true, "New with Settings open: the mouse is free")
E.settings:set("interface", "Classic")
M.steps(1)
eq(E.modal, false, "Classic, its menu closed: the mouse isn't")
eq(E.modalOpen(), false, "E.modalOpen agrees")

section("the Menu key: in Classic it opens / closes V2's menu (V2's rule), the new interface stays hidden")
eq(ui.classic.menu.Visible, false, "Classic's menu closed")
UIH.key(Enum.KeyCode.M)
M.steps(1)
eq(ui.classic.menu.Visible, true, "Menu: opened")
eq(E.modal, true, "the mouse is free")
eq(ui.root.gui.Enabled, false, "the new one stays hidden")
UIH.key(Enum.KeyCode.M)
M.steps(1)
eq(ui.classic.menu.Visible, false, "Menu: closed")
eq(E.modal, false, "the mouse back to the game")
E.settings:set("interface", "New")
M.steps(2)
eq(ui.root.gui.Enabled, true, "New shown on the switch back")
finish()
