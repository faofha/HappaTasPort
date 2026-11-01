-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5c: classic Saves: V2's slot rows on the Library's rules (names, a second click before
-- saving over a run, never an empty run), load, merge before / after through V2's dialog and Merge Stats,
-- the merge refusals; runs in folders stay in the new Library (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local root = E.library.root
local files = E.files
local lastStatus = nil
E.bus:on("status", function(t) lastStatus = tostring(t) end)
local function waitIdle()
	local g = 0
	while E.busy and g < 2000 do M.step(1 / 60); g = g + 1 end
	M.steps(2)
	return not E.busy
end
local function record(n, vx)
	E.modes:request("create")
	M.steps(3)
	if E.tl:count() > 0 then E.modes:request("seek", { frame = E.tl:count() }) M.steps(2) end
	E.modes:request("unpause")
	for _ = 1, n do
		E.char.hrp.AssemblyLinearVelocity = Vector3.new(vx or 0, 0, 0)
		M.step(1 / 60)
	end
	E.modes:request("pause")
	M.steps(2)
	E.char.hrp.AssemblyLinearVelocity = Vector3.zero
end
local function idle()
	if E.merge then E.mergeCanComplete = false; E.mergeRun:finishMerge() end
	E.modes:request("idle")
	M.steps(2)
end
local function click(b) b.MouseButton1Click:Fire() M.steps(1) end
local function typeName(slot, text)
	slot.name.Text = text
	slot.name.FocusLost:Fire(true, nil)
	M.steps(1)
end

E.settings:set("interface", "Classic")
M.steps(2)
local c = ui.classic
c:tab("Saves")
M.steps(1)
local sv = c.saves
check(sv ~= nil, "the classic Saves tab")
local function slotNamed(name)
	for _, s in ipairs(sv.slots) do if s.name.Text == name then return s end end
	return nil
end

section("Add Slot, save, load")
record(30, 10)
local n30 = E.tl:count()
click(sv.addSlot)
local s1 = sv.slots[#sv.slots]
check(s1 ~= nil and s1.name.Text == "Slot 1", "an unsaved \"Slot 1\" row")
eq(files:exists(root .. "/Slot 1.tas"), false, "no file yet")
click(s1.save)
check(waitIdle(), "saved")
check(files:exists(root .. "/Slot 1.tas"), "Slot 1.tas")
eq(sv.count.Text, "1 slot", "V2's count")
idle()
E.modes:setRun({})
M.steps(2)
click(s1.load)
check(waitIdle(), "loaded")
eq(E.tl:count(), n30, "the run as saved")

section("saving over a run asks; an empty run is never saved")
record(5, 10)
local before = files:read(root .. "/Slot 1.tas")
click(s1.save)
eq(s1.save.Text, "Sure?", "asks first")
eq(files:read(root .. "/Slot 1.tas"), before, "nothing written yet")
click(s1.save)
check(waitIdle(), "saved over")
check(files:read(root .. "/Slot 1.tas") ~= before, "the slot holds the longer run")
idle()
E.modes:setRun({})
M.steps(2)
before = files:read(root .. "/Slot 1.tas")
click(s1.save)
click(s1.save)
M.steps(3)
eq(lastStatus, "There is nothing to save", "V2's message")
eq(files:read(root .. "/Slot 1.tas"), before, "the saved run kept")

section("names (the Library's rules)")
click(s1.load)
check(waitIdle(), "loaded again")
typeName(s1, "")
eq(s1.name.Text, "Slot 1", "empty: the old name back")
typeName(s1, "My/run")
check(files:exists(root .. "/Myrun.tas"), "a/b cleaned (Files.cleanName)")
eq(s1.name.Text, "Myrun", "the row shows the clean name")
click(sv.addSlot)
local s2 = sv.slots[#sv.slots]
typeName(s2, string.rep("x", 200))
eq(s2.name.Text, string.rep("x", 60), "200 characters cut to 60")
click(s2.save)
check(waitIdle(), "saved")
typeName(s2, "MYRUN")
eq(s2.name.Text, string.rep("x", 60), "another slot's name in another case: refused")
check(lastStatus:find("already exists", 1, true) ~= nil, "the Library's message (" .. lastStatus .. ")")

section("delete asks (V2's \"Sure?\")")
click(s2.delete)
eq(s2.delete.Text, "Sure?", "asks")
check(files:exists(root .. "/" .. string.rep("x", 60) .. ".tas"), "still there")
click(s2.delete)
eq(files:exists(root .. "/" .. string.rep("x", 60) .. ".tas"), false, "deleted")
eq(slotNamed(string.rep("x", 60)), nil, "its row gone")

section("merge after, completed; merge cancelled")
idle()
E.modes:setRun({})
M.steps(2)
record(20, 10)
local beforeRun = E.tl:toV2All()
local target = slotNamed("Myrun")
local fileFrames = nil
E.bus:on("persist", function(ev) if ev and ev.op == "frames" and ev.ok then fileFrames = ev.frames end end)
click(target.merge)
check(waitIdle(), "read")
eq(c.byPath.Merge.Visible, true, "V2's merge dialog")
eq(c.menu.Visible, false, "the menu closed for it")
local after = c.byPath["Merge.Options.After"]
eq(after.Interactable, true, "Merge After allowed (the file starts Running)")
click(after)
eq(E.merge, true, "merging")
eq(c.byPath.MergeStats.Visible, true, "Merge Stats shown")
local goal = fileFrames[1].Cframe
E.modes:request("unpause")
for _ = 1, 3 do
	E.char.hrp.CFrame = CFrame.new(goal[1], goal[2], goal[3])
	M.step(1 / 60)
end
E.modes:request("pause")
M.steps(2)
local during = E.tl:count()
eq(c.byPath["MergeStats.3"].Text, " Click here to complete merge", "close enough")
check(c.byPath["MergeStats.1"].Text:find("Current Distance", 1, true) ~= nil, "the distance")
click(c.byPath.MergeStats)
eq(E.merge, false, "merged")
eq(E.tl:count(), #beforeRun - 1 + during + #fileFrames, "before + recorded + after - 1")
eq(c.byPath.MergeStats.Visible, false, "Merge Stats gone")
-- (cancelled: far away)
idle()
E.modes:setRun(beforeRun)
M.steps(2)
click(target.merge)
check(waitIdle(), "read")
click(c.byPath["Merge.Options.After"])
E.char.hrp.CFrame = CFrame.new(goal[1] + 200, goal[2], goal[3])
E.modes:request("unpause")
M.steps(3, 1 / 60)
E.modes:request("pause")
M.steps(2)
eq(c.byPath["MergeStats.3"].Text, " Click here to cancel merge", "too far")
click(c.byPath.MergeStats)
eq(E.merge, false, "cancelled")
eq(E.tl:count(), #beforeRun, "the old run back")

section("merge refusals")
E.modes:request("test")
M.steps(3)
click(target.merge)
M.steps(2)
eq(lastStatus, "Go Idle or pause before merging", "from Test")
eq(c.byPath.Merge.Visible, false, "no dialog")
idle()
E.modes:setRun({})
M.steps(2)
click(target.merge)
M.steps(2)
eq(lastStatus, "You must have a TAS to merge", "an empty run")

section("runs in folders stay in the new Library")
files:makeFolder(root .. "/Folder A")
files:write(root .. "/Folder A/Hidden run.tas", files:read(root .. "/Myrun.tas"))
c:tab("Settings")
c:tab("Saves")
M.steps(1)
eq(slotNamed("Hidden run"), nil, "not a classic slot")

section("runs saved elsewhere while the Saves tab is chosen: the rows are made again once (review: a restyle rebuilt them forever)")
record(20, 10)
E.settings:set("interface", "New")
M.steps(2)
check(E.persist:save("Run A", ""), "Run A saved in the new interface")
check(waitIdle(), "saved")
check(E.persist:save("Run B", ""), "Run B saved")
check(waitIdle(), "saved")
E.settings:set("interface", "Classic")
M.steps(2)
local okTab, errTab = pcall(function() c.byPath["MainMenu.SavesToggle"].MouseButton1Click:Fire() end)
M.steps(1)
check(okTab, "the Saves tab opens (" .. tostring(errTab) .. ")")
check(slotNamed("Run A") ~= nil and slotNamed("Run B") ~= nil, "both runs listed")
local okAcc, errAcc = pcall(function() E.settings:set("accentColor", "#FF0000") end)
check(okAcc, "an accent change with the Saves tab chosen (" .. tostring(errAcc) .. ")")
E.settings:set("accentColor", "#3F7CF0")

section("an unsaved slot named like a saved run asks before saving over it (review: the Library's rule, any case)")
idle()
record(7, 10)
local runA = files:read(root .. "/Run A.tas")
click(sv.addSlot)
local fresh = sv.slots[#sv.slots]
typeName(fresh, "run a")
click(fresh.save)
eq(fresh.save.Text, "Sure?", "asks first")
eq(files:read(root .. "/Run A.tas"), runA, "nothing written yet")
click(fresh.save)
check(waitIdle(), "saved over")
check(files:read(root .. "/Run A.tas") ~= runA, "Run A holds the new run")
eq(files:exists(root .. "/run a.tas"), false, "no second file in another case")
finish()
