-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1: the Tasability interface looks the same everywhere: no rounded corners in its window and
-- side panels (the hosted Library, Inspector, Help and About included), and every button, text field and dropdown
-- has the layered edge; switching back to New gives the rounded look back (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local function shown(d, root)
	local p = d.Parent
	while p and p ~= root do
		if p:IsA("GuiObject") and not p.Visible then return false end
		p = p.Parent
	end
	return true
end
local function audit(root)
	local rounded, edgeless, outlineless = {}, {}, {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("UICorner") and shown(d, root) and not d:GetAttribute("HappaRound")
			and (d.CornerRadius.Offset > 0 or d.CornerRadius.Scale > 0) then
			rounded[#rounded + 1] = d.Parent:GetFullName():gsub("^.*HappaTASCompact%.", "")
		end
		if d:IsA("Frame") and (d.Name == "Button" or d.Name == "Field" or d.Name == "Dropdown") and shown(d, root) and d.Visible
			and d.BorderSizePixel < 2 then
			edgeless[#edgeless + 1] = d:GetFullName():gsub("^.*HappaTASCompact%.", "")
		end
		if d:IsA("Frame") and (d.Name == "Button" or d.Name == "Field" or d.Name == "Dropdown") and shown(d, root) and d.Visible then
			local ok = false
			for _, st in ipairs(d:GetChildren()) do
				if st:IsA("UIStroke") and st.Enabled and st.Transparency < 0.5 and st.Thickness >= 1 then ok = true end
			end
			if not ok then outlineless[#outlineless + 1] = d:GetFullName():gsub("^.*HappaTASCompact%.", "") end
		end
	end
	return rounded, edgeless, outlineless
end

E.settings:set("interface", "Tasability")
M.steps(2)
local cp = ui.compact
cp:setPanel("library", true)
cp:setPanel("inspector", true)
local allRounded, allEdgeless, allOutlineless = {}, {}, {}
for _, tab in ipairs({ "controls", "settings", "help", "about" }) do
	cp:showTab(tab)
	M.steps(2)
	local r, e, o = audit(cp.gui)
	for _, x in ipairs(o) do allOutlineless[#allOutlineless + 1] = tab .. ": " .. x end
	for _, x in ipairs(r) do allRounded[#allRounded + 1] = tab .. ": " .. x end
	for _, x in ipairs(e) do allEdgeless[#allEdgeless + 1] = tab .. ": " .. x end
end

section("Tasability: square everywhere, every control with the edge")
eq(#allRounded, 0, "no rounded corner (" .. table.concat(allRounded, " | "):sub(1, 400) .. ")")
eq(#allEdgeless, 0, "no button / field / dropdown without the edge (" .. table.concat(allEdgeless, " | "):sub(1, 400) .. ")")
eq(#allOutlineless, 0, "every button / field / dropdown has the outline too, like Tasability's own boxes (" .. table.concat(allOutlineless, " | "):sub(1, 400) .. ")")
do
	local _, _, missing = audit(cp.titleBar)
	eq(#missing, 0, "the title bar's search box has the outline (" .. table.concat(missing, " | ") .. ")")
end

section("Tasability: no timeline bar")
eq(ui.bar.gui.Visible, false, "the timeline bar is hidden")
E.modes:request("create")
M.steps(2)
eq(ui.bar.gui.Visible, false, "also in Create")
E.modes:request("idle")
M.steps(2)

section("back to New: the rounded look comes back")
E.settings:set("interface", "New")
M.steps(2)
ui.wm:open("help")
M.steps(2)
local hw = ui.helpWin
local c = hw.topicRows[1].gui:FindFirstChildOfClass("UICorner")
check(c ~= nil and c.CornerRadius.Offset == 8, "a Help topic row is rounded again (8)")
local btnCorner = hw.unload.gui:FindFirstChildOfClass("UICorner")
check(btnCorner ~= nil and btnCorner.CornerRadius.Offset > 0, "and the Unload button")
eq(hw.unload.gui.BorderSizePixel, 0, "without the Tasability edge")
do
	local outlined = false
	for _, st in ipairs(hw.unload.gui:GetChildren()) do
		if st:IsA("UIStroke") and st.Enabled and st.Transparency < 0.5 then outlined = true end
	end
	eq(outlined, false, "and without its outline")
	local f = hw.search.gui
	eq(hw.search.ring.Transparency, 1, "a field's ring is hidden again until it is focused")
	check(f ~= nil, "(the Help search box)")
end
eq(ui.bar.gui.Visible, true, "the timeline bar is back")
finish()
