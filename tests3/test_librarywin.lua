-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5b: the Library window: folders, sort / search, attempts nested, save and load through
-- the window, refusals (recording, Test, busy), names, delete asks twice, rename / move, typing in its
-- fields never runs a control (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local wm = ui.wm
local Timeline = __T3("engine/timeline")
local Codec6 = __T3("persist/codec6")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
wm:close("inspector")
M.steps(2)

local root = E.library.root
local files = E.files
local lastStatus, lastError = nil, nil
E.bus:on("status", function(text, isError) lastStatus, lastError = tostring(text), isError == true end)

local function waitIdle()
	local g = 0
	while E.busy and g < 2000 do M.step(1 / 60); g = g + 1 end
	M.steps(2)
	return not E.busy
end
-- a v6 file of n frames, saved at `saved`, `length` seconds long (encoded on a thread: the codec yields)
local function v6file(n, saved, length)
	local tl = Timeline.new()
	tl:addColumn("FrameTime", "f64", 1, { key = "FrameTime" })
	for i = 1, n do
		tl:append()
		tl:set("FrameTime", i, 1, 1 / 60)
	end
	local data
	local co = coroutine.create(function()
		data = Codec6.encode(tl, { frames = n, length = length, created = saved, saved = saved, script = "3.0.0-dev",
			place = 1, kit = 0, speedHack = 0, name = "x" })
	end)
	coroutine.resume(co)
	while coroutine.status(co) ~= "dead" do M.step(1 / 60) end
	return data
end
local function put(rel, n, saved, length)
	files:makeFolder(root)
	files:write(root .. "/" .. rel, v6file(n, saved, length))
end
local function record(n)
	E.modes:request("create")
	M.steps(3)
	E.modes:request("unpause")
	M.steps(n, 1 / 60)
	E.modes:request("pause")
	M.steps(2)
end

put("Alpha.tas", 30, 500, 3.0)
put("Run.tas", 20, 50, 0.5)
put("Run (2).tas", 21, 60, 0.6)
put("Run (3).tas", 22, 70, 0.7)
put("Tower run.tas", 40, 300, 1.0)
put("tower B.tas", 50, 100, 2.0)
files:makeFolder(root .. "/C")

wm:open("library")
M.steps(2)
local lw = ui.libraryWin
check(lw ~= nil, "the Library window")
eq(E.modalOpen(), true, "it frees the mouse")
check(ui.dock.buttons.library ~= nil, "a Dock button")
local function names()
	local out = {}
	for _, r in ipairs(lw.visible) do
		if r.depth == 0 then out[#out + 1] = r.entry.name end
	end
	return table.concat(out, "|")
end
local function rowOf(name)
	for _, r in ipairs(lw.rows) do
		if r.entry.name == name and r.gui.Visible then return r end
	end
	return nil
end
local function select(name)
	local r = rowOf(name)
	check(r ~= nil, "a row for " .. name)
	if not r then return end
	lw.list.CanvasPosition = Vector2.new(0, math.max(0, r.gui.Position.Y.Offset - 10))
	M.steps(1)
	UIH.click(r.gui)
	M.steps(1)
end
local function sortBy(label)
	UIH.click(lw.sort.gui)
	M.steps(1)
	local item = UIH.find(lw.sort.list, label)
	check(item ~= nil, "sort option " .. label)
	if item then UIH.click(item) end
	M.steps(1)
end
local function typeName(text) UIH.typeInto(lw.nameField.box, text) M.steps(1) end
local function press(name) UIH.click(lw.buttons[name].gui) M.steps(1) end

section("at its smallest every control is inside the window (live: a saved 539 x 340 layout hid Rename)")
do
	local win = wm.windows.library
	local ox, oy, ow, oh = win.x, win.y, win.w, win.h
	wm:apply(win, win.x, win.y, 1, 1)
	M.steps(2)
	local hp, hs = win.holder.AbsolutePosition, win.holder.AbsoluteSize
	local out = {}
	local function inside(name, g)
		local p, s = g.AbsolutePosition, g.AbsoluteSize
		if p.X < hp.X or p.Y < hp.Y or p.X + s.X > hp.X + hs.X or p.Y + s.Y > hp.Y + hs.Y then out[#out + 1] = name end
	end
	for k, b in pairs(lw.buttons) do inside(k, b.gui) end
	inside("move", lw.moveDrop.gui)
	inside("sort", lw.sort.gui)
	inside("name", lw.nameField.gui)
	inside("search", lw.search.gui)
	eq(#out, 0, "all inside at " .. win.w .. " x " .. win.h .. " (" .. table.concat(out, ", ") .. ")")
	wm:apply(win, ox, oy, ow, oh)
	M.steps(2)
end

section("folders")
local fnames = {}
for _, fr in ipairs(lw.folderRows) do fnames[#fnames + 1] = fr.label.Text end
eq(table.concat(fnames, "|"), "All runs|C", "All runs, then the folders (empty ones too)")

section("list, sort, search")
eq(names(), "Alpha|Run|tower B|Tower run", "by name")
sortBy("Newest")
eq(names(), "Alpha|Tower run|tower B|Run", "by date, newest first")
sortBy("Longest")
eq(names(), "Alpha|tower B|Tower run|Run", "by length, longest first")
sortBy("Name A-Z")
UIH.typeInto(lw.search.box, "tow", false)
M.steps(1)
eq(names(), "tower B|Tower run", "search tow")
UIH.typeInto(lw.search.box, "", false)
M.steps(1)
eq(names(), "Alpha|Run|tower B|Tower run", "search cleared")
check(rowOf("Run (2)") == nil, "attempts start folded")
local run = rowOf("Run")
check(run and run.chevron ~= nil, "Run has a chevron")
if run and run.chevron then UIH.click(run.chevron.gui) end
M.steps(1)
local after = {}
local seen = false
for _, r in ipairs(lw.visible) do
	if seen and r.depth == 1 then after[#after + 1] = r.entry.name end
	if r.entry.name == "Run" then seen = true elseif r.depth == 0 then seen = false end
end
eq(table.concat(after, "|"), "Run (3)|Run (2)", "attempts nested under Run, newest first")
select("Tower run")
check(lw.info.Text:find("40 frames", 1, true) ~= nil, "the info line (" .. lw.info.Text .. ")")
eq(lw.nameField.box.Text, "Tower run", "the name field takes the selection")

section("save and load through the window")
wm:close("library")
record(30)
local saved = E.tl:count()
check(saved > 20, "a run of " .. saved .. " frames")
wm:open("library")
M.steps(2)
typeName("My run")
press("save")
check(waitIdle(), "saved")
check(files:exists(root .. "/My run.tas"), "the file exists")
eq(E.persist:dirty(), false, "nothing unsaved")
check(rowOf("My run") ~= nil, "listed after the save")
E.modes:request("idle")
M.steps(2)
E.modes:setRun({})
M.steps(2)
eq(E.tl:count(), 0, "the run cleared")
select("My run")
press("load")
check(waitIdle(), "loaded")
eq(E.tl:count(), saved, "the run as saved")
eq(lastStatus, "Loaded My run", "the toast")

section("refusals")
wm:close("library")
E.modes:request("create")
M.steps(3)
E.modes:request("unpause")
M.steps(5, 1 / 60)
wm:open("library")
M.steps(2)
typeName("While recording")
press("save")
M.steps(2)
eq(lastStatus, "Pause before saving", "Save while recording")
eq(files:exists(root .. "/While recording.tas"), false, "no file")
wm:close("library")
E.modes:request("pause")
M.steps(2)
E.modes:request("test")
M.steps(3)
eq(E.mode, 3, "in Test")
wm:open("library")
M.steps(2)
select("Alpha")
press("load")
eq(lastStatus, "Go Idle or pause before loading", "Load from Test")
wm:close("library")
E.modes:request("idle")
M.steps(3)
wm:open("library")
M.steps(2)
local calls = 0
local oSave, oLoad = E.persist.save, E.persist.load
E.persist.save = function(...) calls = calls + 1; return oSave(...) end
E.persist.load = function(...) calls = calls + 1; return oLoad(...) end
E.busy = "saving"
M.steps(2)
for _, b in ipairs({ "load", "save", "attempt", "merge" }) do
	eq(lw.buttons[b].enabled, false, b .. " dimmed while busy")
end
select("Alpha")
press("load")
typeName("Busy")
press("save")
press("attempt")
eq(calls, 0, "nothing called while busy")
E.busy = nil
M.steps(2)
eq(lw.buttons.save.enabled, true, "Save back")
E.persist.save, E.persist.load = oSave, oLoad

section("names")
lastStatus = nil
typeName("")
press("save")
eq(lastStatus, "Invalid name", "empty: refused")
typeName("a/b")
press("save")
check(waitIdle(), "a/b saved")
check(files:exists(root .. "/ab.tas"), "a/b cleaned to ab (Files.cleanName)")
typeName(string.rep("x", 200))
press("save")
check(waitIdle(), "a long name saved")
check(files:exists(root .. "/" .. string.rep("x", 60) .. ".tas"), "200 characters cut to 60 (Files.cleanName)")
local before = files:read(root .. "/My run.tas")
typeName("my run")
press("save")
eq(lw.buttons.save.label.Text, "Overwrite?", "a name that exists asks first")
eq(E.busy, nil, "nothing saved yet")
press("save")
check(waitIdle(), "saved over")
check(files:exists(root .. "/My run.tas"), "the same file, its own case kept")
eq(lastStatus, "Saved My run", "the toast")
eq(lw.buttons.save.label.Text, "Save", "the button back")
check(before ~= nil, "the old file was there")

section("new attempt")
select("My run")
press("attempt")
check(waitIdle(), "attempt saved")
check(files:exists(root .. "/My run (2).tas"), "My run (2)")

section("delete asks twice")
select("ab")
press("delete")
eq(lw.buttons.delete.label.Text, "Delete?", "asks")
check(files:exists(root .. "/ab.tas"), "still there after one click")
press("delete")
eq(files:exists(root .. "/ab.tas"), false, "gone after the second")
select(string.rep("x", 60))
press("delete")
M.steps(200, 1 / 60)
eq(lw.buttons.delete.label.Text, "Delete", "after 3 s the question is gone")
press("delete")
check(files:exists(root .. "/" .. string.rep("x", 60) .. ".tas"), "the first click was forgotten")
M.steps(200, 1 / 60)

section("rename and move")
select("Alpha")
typeName("B")
press("rename")
check(rowOf("B") ~= nil and rowOf("Alpha") == nil, "listed as B")
check(files:exists(root .. "/B.tas"), "the file renamed")
typeName("A")
UIH.click(lw.newFolder.gui)
M.steps(2)
check(files:isFolder(root .. "/A"), "folder A made")
select("B")
UIH.click(lw.moveDrop.gui)
M.steps(1)
local item = UIH.find(lw.moveDrop.list, "A")
check(item ~= nil, "A in the Move menu")
if item then UIH.click(item) end
M.steps(2)
check(files:exists(root .. "/A/B.tas"), "moved under A")
local fr
for _, f in ipairs(lw.folderRows) do if f.folder == "A" then fr = f end end
check(fr ~= nil, "A in the sidebar")
if fr then UIH.click(fr.gui) end
M.steps(1)
eq(names(), "B", "the folder shows its run")
UIH.click(lw.deleteFolder.gui)
M.steps(1)
eq(lastStatus, "The folder is not empty", "a folder with runs isn't deleted")
for _, f in ipairs(lw.folderRows) do if f.folder == "C" then fr = f end end
UIH.click(fr.gui)
M.steps(1)
UIH.click(lw.deleteFolder.gui)
M.steps(2)
eq(files:isFolder(root .. "/C"), false, "the empty folder C deleted")

section("typing in the fields never runs a control")
E.modes:request("idle")
M.steps(2)
local box = lw.nameField.box
box:CaptureFocus()
M.steps(1)
UIH.key(Enum.KeyCode.Two)
M.steps(3)
eq(E.mode, 1, "still Idle after 2 in the name field")
box:ReleaseFocus()
M.steps(1)
finish()
