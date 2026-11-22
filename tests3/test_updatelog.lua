-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1: the version (V3.1) and the full update log: one shared list (ui/updatelog) with V3.1 and
-- V3.0 on top and V2.38.17's log word for word below them (generated from src/parts/p04_ui.lua on branch
-- v2.38.17-humanoid-clock: 39 versions, 167 lines); the About window, Classic's More page and Compact's ABOUT
-- tab all show it (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local CONFIG = __T3("config")
local UpdateLog = __T3("ui/updatelog")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end

section("the version")
eq(CONFIG.VERSION, "3.1", "3.1")
eq(CONFIG.LABEL, "V3.1", "shown as V3.1")
eq(getgenv().__HappaTAS3.Version, "3.1", "the handle's version")

section("the list")
local entries = UpdateLog.ENTRIES
eq(entries[1].heading, " 11/22/26 - V3.1", "V3.1 first")
eq(entries[2].heading, " 11/02/26 - V3.0", "then V3.0")
local V30 = { "A new interface: Dock, windows, timeline bar, Inspector", "Classic interface: Settings > Interface",
	"Library: folders, search, sort, numbered attempts", "File format v6: smaller files, safe saving",
	"Old .tas files (v1-v5) and Settings.json carry over", "Smaller files and faster saving, a clean Unload",
	"Touch buttons and thumbstick replay on phones", "The MicroProfiler on the new engine" }
eq(#entries[2].bullets, #V30, "V3.0's eight lines")
for i, t in ipairs(V30) do eq(entries[2].bullets[i], "   -   " .. t, "V3.0 line " .. i) end
local v31 = table.concat(entries[1].bullets, "\n")
for _, want in ipairs({ "Compact", "colour picker", "Green default colours", "Sync Client Objects", "Smooth Slow Motion",
	"Glide Manipulation", "Classic Look", "About window" }) do
	check(v31:find(want, 1, true) ~= nil, "V3.1 mentions " .. want)
end
for _, b in ipairs(entries[1].bullets) do
	check(b:sub(1, 7) == "   -   " and #b <= 67, "V3.1 line in V2's form, at most 60 characters: " .. b)
end

section("V2.38.17's log, word for word")
local heads, lines, bytes, hash = 0, 0, 0, 0
for i = 3, #entries do
	local e = entries[i]
	heads = heads + 1
	local all = { e.heading }
	for _, b in ipairs(e.bullets) do all[#all + 1] = b; lines = lines + 1 end
	for _, s in ipairs(all) do
		bytes = bytes + #s
		for k = 1, #s do hash = (hash * 31 + string.byte(s, k)) % 2147483647 end
	end
end
eq(heads, 39, "39 versions")
eq(lines, 167, "167 lines")
eq(bytes, 10067, "the same text (bytes)")
eq(hash, 60709074, "the same text (hash, in order)")
eq(entries[3].heading, " 10/25/26 - 2.38.17", "2.38.17 first")
eq(entries[#entries].heading, " 7/14/22 - 2.01", "2.01 last")

section("the About window")
ui.wm:open("about")
M.steps(2)
local aw = ui.aboutWin
eq(aw.title.Text, "HappaTAS V3.1", "its title")
local text = aw.logAll()
local nLines = 0
for _, e in ipairs(entries) do nLines = nLines + 1 + #e.bullets end
eq(#aw.logLabels, nLines, "one label per line (a label taller than the page stops growing in Roblox, live)")
for _, l in ipairs(aw.logLabels) do check(l:IsDescendantOf(aw.log), "inside the log panel") end
check(text:find("11/22/26 - V3.1", 1, true) ~= nil, "V3.1 in the log")
check(text:find("7/14/22 - 2.01", 1, true) ~= nil, "back to 2.01")
check(text:find("Fixed issue with the \"Delete\" keybind", 1, true) ~= nil, "a V2 line with quotes")
ui.wm:close("about")

section("Classic")
E.settings:set("interface", "Classic")
M.steps(2)
local c = ui.classic
check(c.byPath["MainMenu.Title"].Text == "HappaTAS V3.1", "the menu title")
local log = c.byPath["MainMenu.MoreFrame.List.3UpdateLog"]
local rows = {}
for _, ch in ipairs(log:GetChildren()) do if ch:IsA("TextLabel") then rows[#rows + 1] = ch end end
table.sort(rows, function(a, b) return a.Name < b.Name end) -- (the frame lists its rows by name)
local want = {}
for _, e in ipairs(entries) do
	want[#want + 1] = e.heading
	for _, b in ipairs(e.bullets) do want[#want + 1] = b end
end
eq(#rows, #want, "a row per line")
local wrong = 0
for i, r in ipairs(rows) do if r.Text ~= want[i] then wrong = wrong + 1 end end
eq(wrong, 0, "every row in the list's order")
local join
for _, d in ipairs(c.gui:GetDescendants()) do if d:IsA("TextLabel") and d.Name == "Title" and d.Text:find("Loaded", 1, true) then join = d end end
check(join == nil or join.Text == "HappaTAS V3.1 Loaded", "the join message")

section("Compact")
E.settings:set("interface", "Compact")
M.steps(2)
eq(ui.compact.version.label.Text, "V3.1", "the version chip")
ui.compact:showTab("about")
M.steps(1)
check(ui.compact.hosted.about.obj.logAll():find("7/14/22 - 2.01", 1, true) ~= nil, "ABOUT shows the whole log")
finish()
