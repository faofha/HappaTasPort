-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5b: the Help window: every V2.38.17 help topic has a home, keys shown are the bound
-- ones, search, the missing executor functions (Env.notes), the credits word for word (headless mock)
-- ================================================================================================
-- (getconnections taken away for the first run: Env.notes says what that switches off)
local savedGC = getconnections
getconnections = nil
check(boot(30), "boots without getconnections")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local Env = __T3("platform/env")
local HelpText = __T3("ui/win/helptext")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end

section("missing executor functions (Env.notes)")
local function noted(text)
	for _, n in ipairs(Env.notes) do if n == text then return true end end
	return false
end
check(noted("getconnections unavailable; the kit's frame listeners keep real time"), "the Kit Clock note is in Env.notes")
local ui = E.ui
ui.wm:close("inspector")
ui.wm:open("help")
M.steps(2)
local hw = ui.helpWin
check(hw ~= nil, "the Help window")
eq(E.modalOpen(), true, "it frees the mouse")
check(ui.dock.buttons.help ~= nil, "a Dock button")
hw:show("missing")
M.steps(1)
check(hw.body.Text:find("getconnections unavailable", 1, true) ~= nil, "the topic lists it")
local count = #Env.notes
Env.debugNote("getconnections unavailable; the kit's frame listeners keep real time")
eq(#Env.notes, count, "each note once")

-- (everything back: a fresh run)
getconnections = savedGC
check(boot(30), "boots with everything")
T = getgenv().__HappaTAS3_T
E = T.engine
Env = __T3("platform/env")
HelpText = __T3("ui/win/helptext")
ui = E.ui
guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
ui.wm:close("inspector")
ui.wm:open("help")
M.steps(2)
hw = ui.helpWin
hw:show("missing")
M.steps(1)
eq(hw.body.Text, "None: every feature is available", "nothing missing")

section("every V2 help topic has a home")
local V2_TITLES = {
	"Idle", "Create", "Unpause", "Pause", "Back/Forward", "Test", "Optimize TAS", "Delete TAS",
	"Back/Forward 1 Frame", "Return", "Unpause 1 Frame", "Look Around", "Lock Camera (Mode)", "Show Stats (Mode)",
	"Restart When Testing", "Stats Text Size", "Playback Speed", "Interpolate Playback", "MicroProfiler",
	"Mouse UV Normalization", "Death & Respawn Recording", "Tool Actions Support", "Button & Obby Mechanism Sync",
	"Speed Hack (Slow / Fast Motion)", "EToH Kit Objects", "Frustum Culling & Sandboxing",
	"Saving and Loading", "Merging a TAS", "Keyboard and Mouse Inputs", "Client Objects", "Executor Port Settings",
}
local topics = HelpText.topics(E)
local homeless = {}
for _, title in ipairs(V2_TITLES) do
	local found = false
	for _, t in ipairs(topics) do
		if t.title:lower():find(title:lower(), 1, true) or t.body:lower():find(title:lower(), 1, true) then found = true end
	end
	if not found then homeless[#homeless + 1] = title end
end
eq(#homeless, 0, "every title found (" .. table.concat(homeless, ", ") .. ")")
local new = { "Timeline bar", "Library", "Inspector", "Known limits", "Missing executor functions", "Credits" }
for _, title in ipairs(new) do
	local found = false
	for _, t in ipairs(topics) do if t.title:find(title, 1, true) then found = true end end
	check(found, "a topic for " .. title)
end
check(#hw.topicRows == #topics, "one row per topic in the list")

section("keys are live")
E.controls:set("pause", "P")
M.steps(1)
hw:show("pause")
M.steps(1)
check(hw.body.Text:find("[P]", 1, true) ~= nil, "the Pause topic shows P")
E.controls:set("pause", "Left Click")
M.steps(1)
hw:show("pause")
M.steps(1)
check(hw.body.Text:find("[Left Click]", 1, true) ~= nil, "and Left Click again")
check(hw.body.Text:find("{key:", 1, true) == nil, "no placeholder left")

section("search")
UIH.typeInto(hw.search.box, "merge", false)
M.steps(1)
check(#hw.listed > 0 and #hw.listed < #topics, "some topics, not all (" .. #hw.listed .. ")")
local all = true
for _, t in ipairs(hw.listed) do
	if not (t.title:lower():find("merge", 1, true) or t.body:lower():find("merge", 1, true)) then all = false end
end
check(all, "each one mentions merge")
local visibleRows = 0
for _, r in ipairs(hw.topicRows) do if r.gui.Visible then visibleRows = visibleRows + 1 end end
eq(visibleRows, #hw.listed, "only those rows show")
UIH.typeInto(hw.search.box, "", false)
M.steps(1)
eq(#hw.listed, #topics, "cleared: every topic")

section("click a topic")
local row
for _, r in ipairs(hw.topicRows) do if r.id == "library" then row = r end end
check(row ~= nil, "a Library row")
if row then
	hw.list.CanvasPosition = Vector2.new(0, math.max(0, row.gui.Position.Y.Offset - 10))
	M.steps(1)
	UIH.click(row.gui)
end
M.steps(1)
eq(hw.shown, "library", "shows the clicked topic")
check(hw.title.Text:find("Library", 1, true) ~= nil, "its title")

section("credits exact")
hw:show("credits")
M.steps(1)
eq(hw.body.Text, table.concat({
	"Happy_Liam/happa - Main Scripter/UI Design",
	"plusgiant5 - Tasability creator",
	"TestMicrowaveDinner - Scripting Help",
	"Skittlesuna - Playtester",
	"Executor port - client side script",
}, "\n"), "the five lines")

section("what's new (phase 7)")
do
	local list = HelpText.topics(E)
	local function topicById(id)
		for _, t in ipairs(list) do if t.id == id then return t end end
		return nil
	end
	local function order(id)
		for i, t in ipairs(list) do if t.id == id then return i end end
		return -1
	end
	eq(__T3("config").VERSION, "3.0.0", "version 3.0.0")
	local t = topicById("whatsnew")
	check(t ~= nil and t.title == "What's new", "a What's new topic")
	eq(order("whatsnew"), order("start") + 1, "right after Getting started")
	check(t ~= nil and t.body:find("HappaTAS 3.0.0", 1, true) ~= nil, "names the version")
	for _, item in ipairs(HelpText.WHATS_NEW and HelpText.WHATS_NEW.items or {}) do
		check(t ~= nil and t.body:find("• " .. item, 1, true) ~= nil, "lists: " .. item)
		check(#item <= 60, "fits a classic row: " .. item)
	end
	eq(HelpText.WHATS_NEW and #HelpText.WHATS_NEW.items or 0, 8, "eight items")
end

section("only characters every font has")
local okChars = { [utf8.char(215)] = true, [utf8.char(9660)] = true, [utf8.char(8592)] = true, [utf8.char(8230)] = true,
	[utf8.char(8226)] = true }
local bad = {}
for _, t in ipairs(HelpText.topics(E)) do
	for _, s in ipairs({ t.title, t.body }) do
		for _, c in utf8.codes(s) do
			local ch = utf8.char(c)
			if c > 126 and not okChars[ch] then bad[#bad + 1] = t.id .. ":" .. ch end
			if c < 32 and c ~= 10 then bad[#bad + 1] = t.id .. ":ctrl" .. c end
		end
	end
end
eq(#bad, 0, "ASCII and × ▼ ← … • only (" .. table.concat(bad, " ") .. ")")
finish()
