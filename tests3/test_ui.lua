-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5a: the interface together: start with only the Dock, Settings and Controls open
-- while recording (no click reaches the engine), an accent change restyles everything in one frame,
-- pause / Test / Idle, then Unload leaves nothing (headless mock)
-- ================================================================================================
local UIS0 = game:GetService("UserInputService")
local before = { began = UIS0.InputBegan:Count(), changed = UIS0.InputChanged:Count(), ended = UIS0.InputEnded:Count() }
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local wm = ui.wm
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local CoreGui = game:GetService("CoreGui")
local function guis(name)
	local n = 0
	for _, d in ipairs(CoreGui:GetDescendants()) do if d.Name == name then n = n + 1 end end
	return n
end

section("start: only the Dock")
eq(wm:anyOpen(), false, "no window")
check(ui.dock.buttons.settings and ui.dock.buttons.controls, "Settings and Controls in the Dock")
eq(E.modalOpen(), false, "the mouse isn't freed")

section("both windows open while recording")
UIH.click(ui.dock.buttons.settings.gui)
UIH.click(ui.dock.buttons.controls.gui)
check(wm:isOpen("settings") and wm:isOpen("controls"), "both open")
eq(E.modalOpen(), true, "the mouse is freed")
E.modes:request("create")
M.steps(3)
E.modes:request("unpause")
M.steps(3)
check(E.mode == 2 and not E.paused, "recording")
local n0 = E.tl:count()
local sw = ui.settingsWin
UIH.click(sw.search.gui)
UIH.click(UIH.center(wm.windows.controls.titleBar))
UIH.click(UIH.center(wm.windows.settings.body))
M.steps(120, 1 / 60)
eq(E.paused, false, "clicks on the windows never paused")
check(E.tl:count() > n0 + 100, "frames recorded meanwhile (" .. E.tl:count() - n0 .. ")")

section("clicks on the interface are the interface's (Active panels: Roblox marks them game processed)")
-- (live: a click on a window reached the game as not processed, so an equipped tool would fire)
eq(wm.windows.settings.glass.panel.Active, true, "a window's panel")
eq(ui.dock.glass.panel.Active, true, "the Dock's panel")
UIH.click(sw.rows.font.ctl.gui)
local catcher = ui.root.gui:FindFirstChild("PopoverCatcher", true)
check(catcher ~= nil, "a dropdown is open")
eq(catcher and catcher.Active, true, "a popover's full-screen catcher (a click outside it closes it, the game gets nothing)")
UIH.key(Enum.KeyCode.Escape)
ui.toast:add("hello")
eq(ui.toast.items[#ui.toast.items].glass.panel.Active, false, "a toast lets clicks through")

section("only characters every listed font has")
-- (live: ↺ ⌕ ✕ ▾ drew as empty boxes in all 12 fonts; × ▼ ← … • are in every one, both weights)
local FONT_OK = { ["×"] = true, ["▼"] = true, ["←"] = true, ["…"] = true, ["•"] = true }
UIH.click(sw.rows.font.ctl.gui) -- (a dropdown's list too)
local bad = {}
for _, d in ipairs(ui.root.gui:GetDescendants()) do
	if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
		for _, s in ipairs({ d.Text, d:IsA("TextBox") and d.PlaceholderText or "" }) do
			for _, c in utf8.codes(s) do
				local ch = utf8.char(c)
				if c > 127 and not FONT_OK[ch] then bad[#bad + 1] = d.Name .. " " .. ch end
			end
		end
	end
end
eq(#bad, 0, "no character a font lacks (" .. table.concat(bad, ", ") .. ")")
UIH.key(Enum.KeyCode.Escape)

section("an accent change restyles everything in one frame")
E.settings:set("accentColor", "#00C080")
local acc = Color3.fromHex("00C080")
eq(ui.dock.buttons.settings.gui.BackgroundColor3, acc, "the Dock's lit button")
eq(sw.rows.speedHackFrameStep.ctl.gui.BackgroundColor3 == acc, false, "an off toggle isn't accent")
E.settings:set("speedHack", 1)
eq(sw.rows.speedHack.ctl.gui.BackgroundColor3, acc, "an on toggle is")
E.settings:set("speedHack", 0)
E.settings:set("accentColor", "#3F7CF0")

section("pause, Test, Idle")
E.modes:request("pause")
M.steps(3)
eq(E.paused, true, "paused")
E.modes:request("test")
M.steps(30)
eq(E.mode, 3, "testing with the windows open")
E.modes:request("idle")
M.steps(3)
eq(E.mode, 1, "Idle")

section("Unload leaves nothing")
E.settings:set("glass", "Frost")
local uis = M.services.UserInputService
getgenv().__HappaTAS3.Unload()
M.steps(2)
eq(guis("TASUserInterface"), 0, "no interface")
eq(workspace.CurrentCamera:FindFirstChild("HappaTASFrost"), nil, "no Frost parts")
eq(game:GetService("Lighting"):FindFirstChild("HappaTASFrost"), nil, "no Frost effect")
eq(E.inputs.mouseOverOwn, nil, "the engine's pointer hook cleared")
eq(E.modalOpen, nil, "E.modalOpen cleared")
eq(E.modal, nil, "E.modal cleared")
-- (review: sliders, fields and popovers kept their InputBegan connections, and with them the old engine)
eq(UIS0.InputBegan:Count(), before.began, "no InputBegan connection left")
eq(UIS0.InputChanged:Count(), before.changed, "no InputChanged connection left")
eq(UIS0.InputEnded:Count(), before.ended, "no InputEnded connection left")
local before = E.settings:get("glass")
UIH.key(Enum.KeyCode.M)
eq(ui.root.gui.Parent, nil, "the Menu key does nothing any more")
finish()
