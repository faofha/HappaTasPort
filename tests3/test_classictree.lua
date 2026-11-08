-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5c: the classic interface's tree: every V2.38.17 frame by name and class, V2's look,
-- the lists left for the menu to fill, no auto-translation, nothing per frame (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local function handlers()
	local n = 0
	for _, list in pairs(T.pipe.stages) do n = n + #list end
	return n
end
E.settings:set("interface", "Classic")
M.steps(2)
local c = ui.classic
check(c ~= nil and c.byPath ~= nil, "built, with its instances by path")

section("every V2 frame")
local V2 = {
	{ "MainMenu", "Frame" }, { "MainMenu.Title", "TextLabel" },
	{ "MainMenu.ControlsFrame", "ScrollingFrame" }, { "MainMenu.SettingsFrame", "ScrollingFrame" },
	{ "MainMenu.SavesFrame", "ScrollingFrame" }, { "MainMenu.HelpFrame", "ScrollingFrame" },
	{ "MainMenu.MoreFrame", "ScrollingFrame" },
	{ "MainMenu.ControlsToggle", "TextButton" }, { "MainMenu.SettingsToggle", "TextButton" },
	{ "MainMenu.SavesToggle", "TextButton" }, { "MainMenu.HelpToggle", "TextButton" }, { "MainMenu.MoreToggle", "TextButton" },
	{ "MainMenu.SettingsFrame.List", "Frame" }, { "MainMenu.ControlsFrame.List", "Frame" },
	{ "MainMenu.SavesFrame.YourSlots", "Frame" }, { "MainMenu.HelpFrame.List", "Frame" }, { "MainMenu.MoreFrame.List", "Frame" },
	{ "MainMenu.MoreFrame.List.1Model", "TextButton" }, { "MainMenu.MoreFrame.List.ToggleMicroProfiler", "TextButton" },
	{ "IdleStats", "Frame" }, { "CreateStats", "Frame" }, { "TestStats", "Frame" },
	{ "Merge", "Frame" }, { "Merge.Options.Before", "TextButton" }, { "Merge.Options.After", "TextButton" },
	{ "MergeStats", "TextButton" },
	{ "Mobile", "Folder" }, { "Mobile.MobileCreate", "Folder" }, { "Mobile.MobileModes", "Folder" },
	{ "Mobile.MobileOptions", "Folder" }, { "Mobile.MenuOpener", "TextButton" }, { "Mobile.More", "TextButton" },
	{ "Mobile.MobileCreate.Pause", "TextButton" }, { "Mobile.MobileModes.Mode1Mobile", "TextButton" },
	{ "JoinMessage", "Frame" }, { "Status", "TextLabel" },
}
local missing = {}
for _, e in ipairs(V2) do
	local inst = c.byPath[e[1]]
	if not inst or inst.ClassName ~= e[2] then missing[#missing + 1] = e[1] end
end
eq(#missing, 0, "all " .. #V2 .. " there with V2's class (" .. table.concat(missing, ", ") .. ")")
eq(c.menu, c.byPath.MainMenu, "the menu is V2's MainMenu")

section("V2's look")
local menu = c.byPath.MainMenu
eq(menu.Size, UDim2.new(0, 400, 0, 400), "MainMenu 400 x 400")
eq(menu.Position, UDim2.new(0.5, 0, 0.5, 0), "centred")
eq(menu.BackgroundColor3, Color3.fromRGB(0, 35, 73), "V2's dark blue")
eq(menu.Visible, false, "closed until the Menu key")
check(c.byPath["MainMenu.Title"].Text:find("3.0.0", 1, true) ~= nil
	and not c.byPath["MainMenu.Title"].Text:find("-dev", 1, true), "the title carries the version (3.0.0)")

section("the lists the menu fills (Task 3 fills Settings and Help)")
local function rows(path)
	local n = 0
	for _, ch in ipairs(c.byPath[path]:GetChildren()) do
		if not (ch:IsA("UIListLayout") or ch:IsA("UICorner") or ch:IsA("UIStroke")) then n = n + 1 end
	end
	return n
end
local Settings = __T3("engine/settings")
local sections, seen = 0, {}
-- (V2.38.17's settings and the Classic interface switch: the New interface's own are not shown, Part E2; a multi
-- row with Classic labels, Speed Hack In, is a switch per option)
local shownN = 0
for _, def in ipairs(Settings.SCHEMA) do
	if def.v2 or def.key == "interface" then
		shownN = shownN + 1
		if not seen[def.section] then seen[def.section] = true; sections = sections + 1 end
	elseif def.kind == "multi" and def.classic then
		shownN = shownN + #def.options
		if not seen[def.section] then seen[def.section] = true; sections = sections + 1 end
	end
end
eq(rows("MainMenu.SettingsFrame.List"), shownN + sections, "a row per setting shown and a header per section")
eq(rows("MainMenu.ControlsFrame.List"), #__T3("engine/controls").LIST, "a row per control (Task 4)")
local HelpText = __T3("ui/win/helptext")
eq(rows("MainMenu.HelpFrame.List"), 1 + #HelpText.topics(E), "Help: V2's spacer and a row per topic")
local log = c.byPath["MainMenu.MoreFrame.List.3UpdateLog"]
check(log ~= nil, "Classic's More tab has an update log again (phase 7)")
eq(log and c.byPath["MainMenu.MoreFrame.List.3UpdateLog.0"].Text, " HappaTAS 3.0.0", "its version line")
eq(log and rows("MainMenu.MoreFrame.List.3UpdateLog"), 1 + #(HelpText.WHATS_NEW and HelpText.WHATS_NEW.items or {}),
	"one row per item")
check(HelpText.WHATS_NEW ~= nil and #HelpText.WHATS_NEW.items > 0, "built from Help's What's new list")
check(c.byPath["MainMenu.MoreFrame.List.5Credits"] ~= nil, "the credits stay")

section("no auto-translation, nothing per frame")
eq(c.gui.AutoLocalize, false, "AutoLocalize off")
eq(c.gui.ResetOnSpawn, false, "kept over a respawn")
E.settings:set("interface", "New")
M.steps(2)
local hNew = handlers()
E.settings:set("interface", "Classic")
M.steps(2)
check(handlers() <= hNew, "Classic adds no pipeline handler (" .. handlers() .. " vs " .. hNew .. ")")
finish()
