-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1 Compact (Task 7): the shared pieces in Compact's look (timeline bar, toasts, the colour
-- picker) and a merge that goes on across interface switches (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local wm = ui.wm
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local RUNNING = Enum.HumanoidStateType.Running.Value
local function waitIdle()
	local g = 0
	while E.busy and g < 2000 do M.step(1 / 60); g = g + 1 end
	M.steps(2)
	return not E.busy
end
local function record(n)
	E.modes:request("create")
	M.steps(3)
	E.modes:request("unpause")
	for _ = 1, n do
		E.char.hrp.AssemblyLinearVelocity = Vector3.new(10, 0, 0)
		M.step(1 / 60)
	end
	E.modes:request("pause")
	M.steps(2)
	E.char.hrp.AssemblyLinearVelocity = Vector3.zero
end
E.settings:set("interface", "Tasability")
M.steps(2)
local cp = ui.compact

section("the timeline bar")
record(30)
M.steps(2)
local bar = ui.bar
check(bar ~= nil and bar.gui.Visible, "shown in Create")
eq(bar.glass.corner.CornerRadius, UDim.new(0, 0), "square")
eq(bar.glass.panel.BackgroundTransparency, 0, "solid")
eq(bar.glass.shadow.Visible, false, "no shadow")

section("a toast")
E.bus:emit("status", "Saved run 1", false)
local item = ui.toast.items[#ui.toast.items]
check(item ~= nil, "a toast")
local tg = item and item.glass
check(tg == nil or tg.corner.CornerRadius == UDim.new(0, 0), "square")
local corners = {}
for _, d in ipairs(item.gui:GetDescendants()) do
	local shown = true
	local p = d.Parent
	while p and p ~= item.gui do if p:IsA("GuiObject") and not p.Visible then shown = false end p = p.Parent end
	if shown and d:IsA("UICorner") and d.CornerRadius.Offset > 0 and d.CornerRadius.Scale == 0 then corners[#corners + 1] = d:GetFullName() end
end
eq(#corners, 0, "no rounded corner in it (" .. table.concat(corners, ", ") .. ")")

section("the colour picker")
cp:showTab("settings")
M.steps(2)
local acc = cp.settingsPage.rows.accentColor
UIH.click(acc.part.swatch)
M.steps(1)
local pop
for _, d in ipairs(ui.root.layer:GetDescendants()) do if d.Name == "Popover" then pop = d end end
check(pop ~= nil, "the picker opened from the hosted Settings")
local glassPanel = pop and pop:FindFirstChild("Glass")
eq(glassPanel and glassPanel:FindFirstChildOfClass("UICorner").CornerRadius, UDim.new(0, 0), "square")
UIH.key(Enum.KeyCode.Escape)
M.steps(1)

section("a merge across interface switches (Review Focus 1)")
E.modes:request("idle")
M.steps(2)
local run = E.tl:toV2All()
for _, fr in ipairs(run) do fr.State = RUNNING end
E.modes:setRun(run)
M.steps(2)
assert(E.persist:save("MergeMe", ""))
check(waitIdle(), "saved")
cp:setPanel("library", true)
M.steps(2)
ui.startMerge("MergeMe.tas")
check(waitIdle(), "read")
eq(cp.panels.library.open, false, "the Library panel closes for the merge")
local mwin = wm.windows.merge
check(mwin ~= nil and mwin.holder.Visible, "the Merge window shows in Compact")
local mw = ui.mergeWin
UIH.click(mw.buttons.before.gui)
M.steps(2)
check(E.merge, "merging")
E.settings:set("interface", "New")
M.steps(2)
check(mwin.holder.Visible, "still shown in New")
E.settings:set("interface", "Tasability")
M.steps(2)
check(mwin.holder.Visible, "and back in Compact")
check(E.merge, "the merge goes on")
UIH.click(mw.buttons.finish.gui)
M.steps(3)
eq(not E.merge, true, "Cancel merge ends it")
finish()
