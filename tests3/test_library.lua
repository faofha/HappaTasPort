-- needs: fsfail
-- ================================================================================================
-- HappaTAS 3, phase 3: the library (listing with library.json, folders, attempts, sort / search, safe
-- saving, rename / move / delete)
-- ================================================================================================
check(boot(3), "boots")
local Env = __T3("platform/env")
local Files = __T3("platform/files")
local Library = __T3("persist/library")
local Codec6 = __T3("persist/codec6")
local Timeline = __T3("engine/timeline")

local ROOT = "HappaTasPort/lib"

-- a v6 file of n frames (encoded on a thread: the codec yields)
local function v6file(n, saved, length)
	local tl = Timeline.new()
	tl:addColumn("FrameTime", "f64", 1, { key = "FrameTime" })
	for i = 1, n do
		tl:append()
		tl:set("FrameTime", i, 1, 0.004167)
	end
	local data
	local co = coroutine.create(function()
		data = Codec6.encode(tl, { length = length or n / 240, created = 1, saved = saved or 100, script = "3.0.0-dev",
			place = 1, kit = 0, speedHack = 0, name = "x" })
	end)
	coroutine.resume(co)
	while coroutine.status(co) ~= "dead" do M.step(1 / 60) end
	return data
end
local function varint(n)
	local out = {}
	while n >= 128 do out[#out + 1] = string.char(n % 128 + 128); n = n // 128 end
	out[#out + 1] = string.char(n)
	return table.concat(out)
end
local function v2file(frames) return "HTAS" .. string.char(5, 1) .. varint(frames) .. varint(10) .. "\0\0garbage" end

local files = Files.new(Env)
files:makeFolder(ROOT .. "/Tower A/Hard")
files:write(ROOT .. "/Run.tas", v6file(240, 300, 1.0))
files:write(ROOT .. "/Run (2).tas", v6file(480, 400, 2.0))
files:write(ROOT .. "/Run (3).tas", v6file(120, 500, 0.5))
files:write(ROOT .. "/Run 10.tas", v6file(10, 50, 3.0))
files:write(ROOT .. "/Run 2.tas", v6file(20, 60, 4.0))
files:write(ROOT .. "/old v2.tas", v2file(777))
files:write(ROOT .. "/legacy slot.json", "{}")
files:write(ROOT .. "/Tower A/Stage 1.tas", v6file(30, 70, 0.1))
files:write(ROOT .. "/Tower A/Hard/Jump.tas", v6file(40, 80, 0.2))
files:write(ROOT .. "/notes.txt", "not a run")
files:write(ROOT .. "/half.tas.tmp", "a temporary file")
files:write(ROOT .. "/x~rename.tas", "a rename in progress")
files:write(ROOT .. "/dump.html", "a MicroProfiler dump")

local L = Library.new(files, ROOT)

local function byPath(entries)
	local m = {}
	for _, e in ipairs(entries) do m[e.path] = e end
	return m
end

section("listing")
FSFAIL.log = {}
local list = L:list()
local m = byPath(list)
eq(#list, 9, "nine runs (no .txt / .tmp / ~rename / .html / library.json)")
check(m["Run.tas"] and m["Run.tas"].frames == 240 and m["Run.tas"].length == 1.0 and m["Run.tas"].version == 6, "v6 header info")
eq(m["Run.tas"].saved, 300, "saved date")
eq(m["Run.tas"].script, "3.0.0-dev", "script version")
check(m["Run.tas"].size and m["Run.tas"].size > 0, "size")
check(m["old v2.tas"] and m["old v2.tas"].frames == 777 and m["old v2.tas"].version == 5, "a V2 file: frames from its header")
eq(m["old v2.tas"].length, nil, "a V2 file: length unknown")
check(m["legacy slot.json"] and m["legacy slot.json"].version == 0, "a legacy JSON slot")
check(m["Tower A/Stage 1.tas"] and m["Tower A/Stage 1.tas"].folder == "Tower A", "a run in a folder")
eq(m["Tower A/Hard/Jump.tas"].folder, "Tower A/Hard", "two levels deep")
eq(m["Run (2).tas"].attempt, 2, "attempt number")
eq(m["Run (2).tas"].base, "Run", "attempt base")
check(files:exists(ROOT .. "/library.json"), "library.json written")
FSFAIL.log = {}
local list2 = L:list()
eq(#list2, 9, "the same list again")
eq(FSFAIL.count("read", "%.tas$") + FSFAIL.count("read", "%.json$") - FSFAIL.count("read", "library%.json$"), 0, "the second list reads no run file (the cache)")
files:delete(ROOT .. "/Run 10.tas")
local list3 = byPath(L:list())
eq(list3["Run 10.tas"], nil, "a deleted file is gone from the list")
local cache = files:read(ROOT .. "/library.json")
check(cache and not cache:find("Run 10", 1, true), "and from library.json")
FSFAIL.log = {}
L:refresh()
check(FSFAIL.count("read", "Run%.tas$") >= 1, "refresh reads every header again")

section("attempts, sort, search")
local groups = L:groups(L:list())
local runGroup
for _, g in ipairs(groups) do if g.run.path == "Run.tas" then runGroup = g end end
check(runGroup ~= nil, "Run is a run")
eq(runGroup and #runGroup.attempts, 2, "with two attempts")
eq(runGroup and runGroup.attempts[1].name, "Run (3)", "newest attempt first")
for _, g in ipairs(groups) do
	check(g.run.name ~= "Run (2)" and g.run.name ~= "Run (3)", "an attempt is not its own run: " .. g.run.name)
end
eq(L:nextAttemptName("run", ""), "run (4)", "next attempt (case-insensitive)")
eq(L:nextAttemptName("Stage 1", "Tower A"), "Stage 1 (2)", "first attempt is (2)")
local sortedNames = {}
for _, e in ipairs(L:sorted(L:list(), "name")) do sortedNames[#sortedNames + 1] = e.name end
local i2, i10 = table.find(sortedNames, "Run 2"), table.find(sortedNames, "Run 10")
files:write(ROOT .. "/Run 10.tas", v6file(10, 50, 3.0))
sortedNames = {}
for _, e in ipairs(L:sorted(L:list(), "name")) do sortedNames[#sortedNames + 1] = e.name end
i2, i10 = table.find(sortedNames, "Run 2"), table.find(sortedNames, "Run 10")
check(i2 and i10 and i2 < i10, "natural order: Run 2 before Run 10")
local byDate = L:sorted(L:list(), "date", true)
eq(byDate[1].name, "Run (3)", "newest saved first")
local byLength = L:sorted(L:list(), "length", true)
eq(byLength[1].name, "Run 2", "longest first")
local found = L:search(L:list(), "RUN")
eq(#found, 5, "search is case-insensitive: Run, Run (2), Run (3), Run 10, Run 2")
eq(#L:search(L:list(), "jump"), 1, "search inside folders too")

section("safe saving")
do
	local okS, rel = L:save("New run", "Tower A", v6file(50))
	check(okS, "save")
	eq(rel, "Tower A/New run.tas", "saved path")
	check(not files:exists(ROOT .. "/Tower A/New run.tas.tmp"), "no temporary file left")
	eq(byPath(L:list())["Tower A/New run.tas"].frames, 50, "listed with its header")
	-- Review focus 2: the old file keeps its bytes whatever fails
	local before = files:read(ROOT .. "/Run.tas")
	for _, case in ipairs({ { "write", "%.tmp$" }, { "shortWritten", "%.tmp$" }, { "write", "Run%.tas$" }, { "shortWritten", "Run%.tas$" } }) do
		FSFAIL.mark()
		FSFAIL[case[1]] = case[2]
		local ok, err = L:save("Run", "", v6file(999))
		FSFAIL[case[1]] = nil
		check(not ok and type(err) == "string", "failing " .. case[1] .. " " .. case[2] .. ": refused with a message")
		eq(files:read(ROOT .. "/Run.tas"), before, "failing " .. case[1] .. " " .. case[2] .. ": the old file keeps its bytes")
		check(not files:exists(ROOT .. "/Run.tas.tmp"), "failing " .. case[1] .. " " .. case[2] .. ": no temporary file left")
	end
	-- saving over a run of the same name replaces it
	check((L:save("Run", "", v6file(241))), "save over the same name")
	eq(byPath(L:list())["Run.tas"].frames, 241, "replaced")
	-- a legacy .json slot of the same name goes after a save (V2 did)
	check((L:save("legacy slot", "", v6file(5))), "save over a legacy slot")
	check(not files:exists(ROOT .. "/legacy slot.json"), "the legacy .json is gone")
	check(files:exists(ROOT .. "/legacy slot.tas"), "the .tas is there")
	-- names never leave the root
	local okE, relE = L:save("../evil", "../../up", v6file(5))
	check(okE and relE == "up/evil.tas", "'../evil' in '../../up' stays inside (" .. tostring(relE) .. ")")
	check(not L:save("x", "a/b/c/d", v6file(5)), "at most three folder levels")
	check(not L:save("   ", "", v6file(5)), "an empty name is refused")
end

section("case-insensitive names (Windows)")
do
	local okA = L:save("run", "", v6file(5))
	check(not okA, "saving 'run' while 'Run' exists is refused")
	check(not L:rename("Run 2.tas", "run"), "renaming to 'run' is refused")
	files:makeFolder(ROOT .. "/Other")
	files:write(ROOT .. "/Other/Run.tas", v6file(5))
	check(not L:move("Other/Run.tas", ""), "moving another 'Run' into the root is refused")
	local okR, newRel = L:rename("Run.tas", "RUN")
	check(okR and newRel == "RUN.tas", "a case-only rename works")
	check(files:exists(ROOT .. "/RUN.tas") and not files:exists(ROOT .. "/Run.tas"), "only the new name is there")
	check(not files:exists(ROOT .. "/Run~rename.tas") and not files:exists(ROOT .. "/RUN~rename.tas"), "no rename leftover")
	eq(byPath(L:list())["RUN.tas"].frames, 241, "listed under its new name")
end

section("rename, move, delete, folders")
do
	local okM, rel = L:move("Run 2.tas", "Tower A")
	check(okM and rel == "Tower A/Run 2.tas", "move into a folder")
	check(files:exists(ROOT .. "/Tower A/Run 2.tas") and not files:exists(ROOT .. "/Run 2.tas"), "moved")
	local okN, rel2 = L:rename("Tower A/Run 2.tas", "Second")
	check(okN and rel2 == "Tower A/Second.tas", "rename in its folder")
	eq(L:read("Tower A/Second.tas") ~= nil, true, "read by path")
	check((L:delete("Tower A/Second.tas")), "delete")
	eq(byPath(L:list())["Tower A/Second.tas"], nil, "deleted from the list")
	check((L:createFolder("Tower B/Easy")), "create a folder (two levels)")
	check(files:isFolder(ROOT .. "/Tower B/Easy"), "it exists")
	check(not L:deleteFolder("Tower A"), "a folder with runs isn't deleted")
	check(files:isFolder(ROOT .. "/Tower A"), "still there")
	check((L:deleteFolder("Tower B/Easy")), "an empty folder is deleted")
	check(not files:isFolder(ROOT .. "/Tower B/Easy"), "gone")
	check(not L:read("missing.tas"), "reading a missing run returns nil")
end
finish()
