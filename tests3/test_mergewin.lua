-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5b: the Merge window: reading a saved run without touching the one in use, the Running
-- rule for Before / After, a completed and a cancelled merge, refusals (an empty run, busy), closing the
-- window cancels (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local wm = ui.wm
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
wm:close("inspector")
M.steps(2)
local tl = E.tl
local RUNNING = Enum.HumanoidStateType.Running.Value
local lastStatus = nil
E.bus:on("status", function(text) lastStatus = tostring(text) end)
local frameEvents = {}
E.bus:on("persist", function(ev) if ev and ev.op == "frames" then frameEvents[#frameEvents + 1] = ev end end)

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
local function save(name)
	assert(E.persist:save(name, ""))
	check(waitIdle(), "saved " .. name)
end
local function cframes()
	local out = {}
	for i, fr in ipairs(tl:toV2All()) do out[i] = table.concat(fr.Cframe or {}, ",") end
	return table.concat(out, ";")
end
local function idle()
	if E.merge then
		E.mergeCanComplete = false
		E.mergeRun:finishMerge()
	end
	E.modes:request("idle")
	M.steps(2)
end

section("readFrames: the file's frames, the run in use untouched")
record(50, 10)
local fifty = tl:count()
save("Fifty")
record(5, 10)
local inUse, version, dirty = tl:count(), tl.version, E.persist:dirty()
check(inUse > fifty, "the run in use is longer now")
local ok, why = E.persist:readFrames("Fifty.tas")
eq(ok, true, "started (" .. tostring(why) .. ")")
check(waitIdle(), "read")
local ev = frameEvents[#frameEvents]
check(ev ~= nil and ev.ok, "a frames event")
eq(ev and #ev.frames, fifty, "with the file's frames")
eq(tl:count(), inUse, "the run in use: same length")
eq(tl.version, version, "same version")
eq(E.persist:dirty(), dirty, "its unsaved state as it was")

section("the Running rule")
-- (a run whose last frame is Running and whose first isn't)
idle()
local mixed = tl:toV2All()
mixed[1].State = Enum.HumanoidStateType.Freefall.Value
mixed[#mixed].State = RUNNING
E.modes:setRun(mixed)
M.steps(2)
save("Mixed")
ui.startMerge("Mixed.tas")
check(waitIdle(), "read")
local mw = ui.mergeWin
check(mw ~= nil, "the Merge window")
eq(wm:isOpen("merge"), true, "open")
eq(E.modalOpen(), false, "it leaves the mouse to the game (you play during a merge)")
eq(mw.buttons.before.enabled, true, "Before: the file's last frame is Running")
eq(mw.buttons.after.enabled, false, "After: its first frame isn't")
UIH.click(mw.buttons.cancel.gui)
M.steps(2)
eq(wm:isOpen("merge"), false, "Cancel closes it")
eq(E.merge, false, "no merge")

section("merge after, completed")
idle()
E.modes:setRun({})
M.steps(2)
record(20, 10)
local before = tl:toV2All()
local fiftyFrames = frameEvents[1].frames
ui.startMerge("Fifty.tas")
check(waitIdle(), "read")
eq(mw.buttons.after.enabled, true, "After allowed")
UIH.click(mw.buttons.after.gui)
M.steps(2)
eq(E.merge, true, "merging")
local goal = fiftyFrames[1].Cframe
E.char.hrp.CFrame = CFrame.new(goal[1], goal[2], goal[3])
E.char.hrp.AssemblyLinearVelocity = Vector3.zero
E.modes:request("unpause")
for _ = 1, 3 do
	E.char.hrp.CFrame = CFrame.new(goal[1], goal[2], goal[3])
	M.step(1 / 60)
end
E.modes:request("pause")
M.steps(2)
local during = tl:count()
eq(mw.buttons.finish.label.Text, "Complete merge", "close enough")
check(mw.detail.Text:find("Current distance", 1, true) ~= nil, "the distances show (" .. mw.detail.Text .. ")")
UIH.click(mw.buttons.finish.gui)
M.steps(2)
eq(E.merge, false, "merge over")
eq(tl:count(), #before - 1 + during + #fiftyFrames, "before + recorded + after - 1")
eq(lastStatus, "Merge Complete", "the toast")
eq(wm:isOpen("merge"), false, "the window closes")

section("cancelled: the old run back")
idle()
E.modes:setRun(before)
M.steps(2)
local old = cframes()
ui.startMerge("Fifty.tas")
check(waitIdle(), "read")
UIH.click(mw.buttons.after.gui)
M.steps(2)
E.char.hrp.CFrame = CFrame.new(goal[1] + 200, goal[2], goal[3])
E.modes:request("unpause")
M.steps(3, 1 / 60)
E.modes:request("pause")
M.steps(2)
eq(mw.buttons.finish.label.Text, "Cancel merge", "too far")
UIH.click(mw.buttons.finish.gui)
M.steps(2)
eq(E.merge, false, "merge over")
eq(cframes(), old, "the old run back frame for frame")
eq(lastStatus, "Merge Cancelled", "the toast")

section("refusals")
idle()
E.modes:setRun({})
M.steps(2)
local reads = 0
local oRead = E.persist.readFrames
E.persist.readFrames = function(...) reads = reads + 1; return oRead(...) end
ui.startMerge("Fifty.tas")
M.steps(2)
eq(lastStatus, "You must have a TAS to merge", "an empty run")
eq(reads, 0, "nothing read")
eq(mw.message.Text, "You must have a TAS to merge", "the window says so")
wm:close("merge")
E.persist.readFrames = oRead
E.modes:setRun(before)
M.steps(2)
wm:open("library")
M.steps(2)
local lw = ui.libraryWin
lw.select("Fifty.tas")
M.steps(1)
eq(lw.buttons.merge.enabled, true, "the Library's Merge works")
E.busy = "saving"
M.steps(2)
eq(lw.buttons.merge.enabled, false, "dimmed while busy")
E.busy = nil
M.steps(2)
UIH.click(lw.buttons.merge.gui)
check(waitIdle(), "read through the Library")
eq(wm:isOpen("merge"), true, "the Library's Merge opens the Merge window")
E.busy = "saving"
M.steps(2)
eq(mw.buttons.after.enabled, false, "Before / After dimmed while busy")
E.busy = nil
M.steps(2)
wm:close("merge")
M.steps(1)

section("closing the window cancels the merge")
idle()
E.modes:setRun(before)
M.steps(2)
old = cframes()
ui.startMerge("Fifty.tas")
check(waitIdle(), "read")
UIH.click(mw.buttons.after.gui)
M.steps(2)
eq(E.merge, true, "merging")
eq(wm:isOpen("library"), false, "the Library closed for playing")
wm:close("merge")
M.steps(2)
eq(E.merge, false, "cancelled")
eq(cframes(), old, "the old run back")
finish()
