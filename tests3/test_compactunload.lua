-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1 Compact (Task 8): Help knows the Compact interface; Unload with Compact live, folded and a
-- popover open leaves nothing (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local HelpText = __T3("ui/win/helptext")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end

section("Help")
local topics = HelpText.topics(E)
local compact
for _, t in ipairs(topics) do if t.id == "compact" then compact = t end end
check(compact ~= nil and compact.title == "Compact interface", "a Compact interface topic")
if compact then
	for _, word in ipairs({ "title bar", "tabs", "LIBRARY", "INSPECTOR", "minimise" }) do
		check(compact.body:find(word, 1, true) ~= nil, "it names " .. word)
	end
end
local bad = {}
for _, t in ipairs(topics) do
	for line in (t.body .. "\n"):gmatch("([^\n]*)\n") do
		if line:find("Dock", 1, true) and not line:find("New interface", 1, true) then bad[#bad + 1] = t.id end
		if line:find("their own windows", 1, true) and not line:find("New interface", 1, true) then bad[#bad + 1] = t.id end
	end
end
eq(#bad, 0, "New-only lines name the New interface (" .. table.concat(bad, ", ") .. ")")
local cl
for _, t in ipairs(topics) do if t.id == "classiclook" then cl = t end end
check(cl ~= nil and cl.body:find("Compact", 1, true) ~= nil, "the Interface line lists Compact too")

section("Unload with Compact live, folded, a popover open (Review Focus 5)")
E.settings:set("interface", "Compact")
M.steps(2)
local cp = ui.compact
cp:showTab("settings")
M.steps(2)
UIH.click(cp.hosted.settings.obj.rows.accentColor.ctl.gui)
M.steps(1)
cp:setFolded(true)
M.steps(1)
local h = getgenv().__HappaTAS3
check(h ~= nil and h.Unload ~= nil, "loaded")
h.Unload()
M.steps(5)
eq(getgenv().__HappaTAS3, nil, "unloaded")
local left = {}
for _, root in ipairs({ gethui and gethui(), game:GetService("CoreGui") }) do
	if root then
		for _, d in ipairs(root:GetDescendants()) do
			if d.Name == "HappaTASCompact" or d.Name == "Popover" or d.Name == "PopoverCatcher" or d.Name == "TASUserInterface" then
				left[#left + 1] = d:GetFullName()
			end
		end
	end
end
eq(#left, 0, "nothing left (" .. table.concat(left, ", ") .. ")")
finish()
