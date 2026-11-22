-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1: the pages
--  * an About window in the Dock (after Help): the version, the credits and the update log, each list in a
--    rounded panel
--  * the credits: one list (Help text's CREDITS) for the About window and Classic's More page; Happy_Liam/happa
--    is "UI design", 9kwr "Tasability UI design" is new
--  * credits and what's new leave Help (New and Classic, which lists Help's topics)
--  * Classic's update log is rounded like the credits box above it
--  * Help reworked: short lines (bullets / steps), nothing removed that a V2 topic needs
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local HelpText = __T3("ui/win/helptext")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
ui.wm:close("inspector")

local CREDITS = {
	"Happy_Liam/happa - UI design",
	"plusgiant5 - Tasability creator",
	"9kwr - Tasability UI design",
	"TestMicrowaveDinner - Scripting Help",
	"Skittlesuna - Playtester",
}

section("the credits list")
eq(#HelpText.CREDITS, #CREDITS, "five names")
for i, line in ipairs(CREDITS) do eq(HelpText.CREDITS[i], line, "line " .. i) end

section("the About window")
local dock = ui.dock
check(dock.buttons.about ~= nil, "a Dock button")
eq(dock.buttons.about and dock.buttons.about.label.Text, "About", "named About")
local iHelp, iAbout = table.find(dock.order, "help"), table.find(dock.order, "about")
check(iHelp ~= nil and iAbout == iHelp + 1, "right after Help")
UIH.click(dock.buttons.about.gui)
M.steps(2)
eq(ui.wm:isOpen("about"), true, "a click opens it")
local aw = ui.aboutWin
check(aw ~= nil, "built")
eq(aw.title.Text, "HappaTAS " .. __T3("config").LABEL, "the version")
eq(aw.creditsText.Text, table.concat(CREDITS, "\n"), "the credits, word for word")
local log = aw.logAll()
local UL = __T3("ui/updatelog").ENTRIES
check(log:find(UL[1].heading, 1, true) == 1, "the log starts with the newest version")
for _, item in ipairs(UL[1].bullets) do check(log:find(item, 1, true) ~= nil, "log: " .. item) end
for _, p in ipairs({ aw.credits, aw.log }) do
	check(p:FindFirstChildOfClass("UICorner") ~= nil, p.Name .. ": a rounded panel")
	eq(aw.creditsText.TextWrapped, true, p.Name .. ": the text wraps")
end
check(aw.page:IsA("ScrollingFrame") and aw.page.AutomaticCanvasSize == Enum.AutomaticSize.Y, "the page scrolls as far as its content")
UIH.click(dock.buttons.about.gui)
M.steps(1)
eq(ui.wm:isOpen("about"), false, "a second click closes it")

section("credits and what's new leave Help")
local topics = HelpText.topics(E)
for _, t in ipairs(topics) do
	check(t.id ~= "credits" and t.id ~= "whatsnew", "not a Help topic: " .. t.id)
	check(not t.body:find("TestMicrowaveDinner", 1, true), "no credits in " .. t.id)
end

section("Help reworked: short lines")
local long = {}
for _, t in ipairs(topics) do
	for line in (t.body .. "\n"):gmatch("([^\n]*)\n") do
		if #line > 330 then long[#long + 1] = t.id .. " (" .. #line .. ")" end
	end
end
eq(#long, 0, "no line over 330 characters (" .. table.concat(long, ", ") .. ")")
check(#topics <= 20, "at most 20 sections (" .. #topics .. ")")
local start
for _, t in ipairs(topics) do if t.id == "start" then start = t end end
check(start ~= nil and start.body:find("1. Press [2] for Create", 1, true) ~= nil, "Getting started: numbered steps, the keys bound now")

section("Classic: credits from the same list, a rounded update log, Help without credits")
E.settings:set("interface", "Classic")
M.steps(2)
local c = ui.classic
local box = c.byPath["MainMenu.MoreFrame.List.5Credits"]
local rows = {}
for _, ch in ipairs(box:GetChildren()) do if ch:IsA("TextLabel") then rows[#rows + 1] = ch end end
table.sort(rows, function(a, b) return a.Name < b.Name end) -- (the box's list sorts by name)
eq(#rows, #CREDITS, "a row per name")
for i, r in ipairs(rows) do eq(r.Text, " " .. CREDITS[i], "row " .. i .. " in the list's order") end
check(c.byPath["MainMenu.MoreFrame.List.3UpdateLog"]:FindFirstChildOfClass("UICorner") ~= nil, "the update log is rounded")
check(box:FindFirstChildOfClass("UICorner") ~= nil, "like the credits box")
eq(c.byPath["MainMenu.MoreFrame.List.0ModelN"].Text, HelpText.PORT, "the More page's title line")
local helpTitles = {}
for _, r in ipairs(c.helpRows) do helpTitles[#helpTitles + 1] = r.button.N.Text end
eq(#c.helpRows, #topics, "Classic's Help: a row per Help topic")
for _, title in ipairs(helpTitles) do check(title ~= "Credits" and title ~= "What's new", "Classic Help row: " .. title) end
E.settings:set("interface", "New")
M.steps(2)
finish()
