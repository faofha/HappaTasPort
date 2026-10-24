-- ================================================================================================
-- HappaTAS 3, phase 2: the mode machine (Idle / Create paused or recording / Test) and the frame loop
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
check(E.char:loaded(), "character loaded")
local UIS = M.services.UserInputService
local hrp, hum = E.char.hrp, E.char.hum
local statuses = {}
E.bus:on("status", function(text) statuses[#statuses + 1] = text end)
local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
local function click()
	UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	UIS.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
local function jumpEnabled() return hum:GetStateEnabled(Enum.HumanoidStateType.Jumping) end
local function moving() hrp.AssemblyLinearVelocity = Vector3.new(10, 0, 0) end

section("Create on an empty run")
key(Enum.KeyCode.Two)
M.steps(2)
eq(E.mode, 2, "Create")
eq(E.paused, true, "paused")
eq(E.frame, 0, "frame 0")
eq(E.state:get("mode"), "Paused", "published mode Paused")
eq(hrp.Anchored, true, "root anchored")
eq(hum.AutoRotate, false, "AutoRotate off while held")

section("unpause: the first frame is recorded on the second frame after the click")
click()
eq(E.paused, false, "unpaused at once")
eq(jumpEnabled(), false, "no jump on the first recorded frame")
eq(E.state:get("mode"), "Recording", "published mode Recording")
moving(); M.step(1 / 60)
eq(E.tl:count(), 0, "nothing recorded on the first frame")
eq(jumpEnabled(), false, "still no jump")
moving(); M.step(1 / 60)
eq(E.tl:count(), 1, "frame 1 recorded on the second frame")
eq(jumpEnabled(), true, "jumping back on")
eq(hrp.Anchored, false, "root free while recording")
for _ = 1, 18 do moving(); M.step(1 / 60) end
eq(E.tl:count(), 19, "one frame per frame")
local tt = E.tl:get("TotalTime", 19, 1)
near(tt, 19 / 60, 1e-5, "TotalTime adds up the frame times")

section("pause on the last frame")
click()
M.step(1 / 60)
eq(E.paused, true, "paused")
eq(E.frame, E.tl:count(), "on the last frame")
check(E.tl:isFilled(E.tl:count()), "the last frame is complete")
eq(hrp.Anchored, true, "anchored")

section("Back / Forward held step one frame each Heartbeat")
local n = E.tl:count()
M.pressKey(Enum.KeyCode.R)
M.steps(5)
M.releaseKey(Enum.KeyCode.R)
eq(E.frame, n - 5, "R held 5 frames")
M.pressKey(Enum.KeyCode.T)
M.steps(2)
M.releaseKey(Enum.KeyCode.T)
eq(E.frame, n - 3, "T held 2 frames")
key(Enum.KeyCode.F); eq(E.frame, n - 4, "F: one back")
key(Enum.KeyCode.G); eq(E.frame, n - 3, "G: one forward")
local cf = E.char:cframeAt(E.tl, E.frame)
check((hrp.Position - cf.Position).Magnitude < 1e-6, "the root is on the shown frame")

section("seek")
E.modes:seek(5)
eq(E.frame, 5, "seek to frame 5 while paused")
check((hrp.Position - E.char:cframeAt(E.tl, 5).Position).Magnitude < 1e-6, "shows frame 5")

section("unpause cuts the frames after the current one; Return goes back to where it unpaused")
click()
M.steps(3)
eq(E.tl:count(), 5 + 2, "cut to 5, then two new frames in 3 frames")
click()
M.step(1 / 60)
local after = E.tl:count()
key(Enum.KeyCode.E)
eq(E.frame, 5, "Return to the frame it unpaused from")
eq(E.tl:count(), 5, "frames after it cut")
check(after > 5, "(there were more)")

section("Unpause 1 Frame records exactly one frame")
local before = E.tl:count()
key(Enum.KeyCode.V)
M.steps(4)
eq(E.tl:count(), before + 1, "one frame")
eq(E.paused, true, "paused again")
eq(E.frame, before + 1, "on it")
-- a Landed frame: two frames
E.tl:set("State", E.frame, 1, Enum.HumanoidStateType.Landed.Value)
before = E.tl:count()
key(Enum.KeyCode.V)
M.steps(5)
eq(E.tl:count(), before + 2, "two frames after a Landed frame")

section("one Left Click is one transition")
click()
eq(E.paused, false, "the click unpaused (and didn't pause again)")
M.steps(3)
click()
eq(E.paused, true, "the next click paused")
M.steps(2)

section("Test")
key(Enum.KeyCode.Three)
eq(E.mode, 3, "Test")
eq(E.state:get("mode"), "Testing", "published mode Testing")
eq(E.frame, 1, "from frame 1 (Restart When Testing)")
local guardT = 0
while E.mode == 3 and guardT < 400 do M.step(1 / 60); guardT = guardT + 1 end
eq(E.mode, 1, "back to Idle at the end")
check(statuses[#statuses]:find("TAS Completed", 1, true) ~= nil, "completion message")
eq(hrp.Anchored, false, "root free in Idle")
eq(hum.AutoRotate, true, "AutoRotate back on")

section("seek in Test")
key(Enum.KeyCode.Three)
M.steps(2)
E.modes:seek(3)
eq(E.frame, 3, "Test at frame 3")
near(E.testTime, E.tl:get("TotalTime", 3, 1), 1e-9, "the clock at frame 3's time")
key(Enum.KeyCode.One)
eq(E.mode, 1, "Idle")

section("optimize and delete need a second press; optimize only in Idle")
key(Enum.KeyCode.Two)
key(Enum.KeyCode.Q)
eq(statuses[#statuses], "Switch to idle to optimize TAS", "optimize refused outside Idle")
key(Enum.KeyCode.One)
local count0 = E.tl:count()
key(Enum.KeyCode.Backspace)
eq(E.tl:count(), count0, "the first press only asks")
M.steps(2)
key(Enum.KeyCode.Backspace)
eq(E.tl:count(), 0, "the second press deletes")
eq(statuses[#statuses], "TAS Deleted", "status")
key(Enum.KeyCode.Backspace)
M.step(1 / 60)
for _ = 1, 80 do M.step(1 / 60) end
key(Enum.KeyCode.Backspace)
eq(statuses[#statuses]:sub(1, 11), "Delete TAS?", "a press after the confirm time asks again")

section("Test needs 2 frames")
key(Enum.KeyCode.Two)
click(); M.steps(2); click(); M.steps(2)
eq(E.tl:count(), 1, "one frame")
key(Enum.KeyCode.Three)
eq(E.mode, 2, "Test refused")
eq(statuses[#statuses], "There is not enough TAS data to test.", "status")
click(); M.steps(2); click(); M.steps(2)
eq(E.tl:count(), 2, "two frames")
key(Enum.KeyCode.Three)
eq(E.mode, 3, "a 2-frame run plays")
M.steps(10)
eq(E.mode, 1, "and ends")
section("request: each transition checks that it is allowed")
do
	local m = E.modes
	key(Enum.KeyCode.One)
	M.steps(2)
	eq(m:request("pause"), false, "no Pause in Idle")
	eq(m:request("back1"), false, "no stepping in Idle")
	eq(E.mode, 1, "still Idle")
	eq(m:request("create"), true, "Create")
	eq(E.mode, 2, "in Create")
	M.steps(2)
	eq(m:request("pause"), false, "no Pause while paused")
	eq(m:request("unpause"), true, "Unpause")
	M.steps(4)
	eq(m:request("unpause"), false, "no Unpause while recording")
	eq(m:request("lookAround"), false, "no Look Around while recording")
	eq(m:request("pause"), true, "Pause")
	M.steps(2)
	E.modes:seek(1)
	eq(m:request("back1"), false, "no step back on frame 1")
	eq(m:request("forward1"), true, "step forward")
	E.merge = true
	eq(m:request("idle"), false, "no Idle while merging")
	eq(m:request("test"), false, "no Test while merging")
	E.merge = false
	eq(m:request("nonsense"), false, "an unknown action")
	eq(m:request("test"), true, "Test")
	eq(E.mode, 3, "testing")
	local g = 0
	while E.mode == 3 and g < 600 do M.step(1 / 60); g = g + 1 end
	eq(E.mode, 1, "Test ends through the mode machine")
end

section("a plugin that keeps failing doesn't switch the engine off")
do
	local disabled = {}
	E.bus:on("moduleDisabled", function(name) disabled[#disabled + 1] = name end)
	local cam = E.plugins:get("camera")
	local realHold = cam.holdPaused
	cam.holdPaused = function() error("camera broke") end
	key(Enum.KeyCode.Two)
	M.steps(2)
	click(); M.steps(4); click()
	M.steps(12)
	eq(#disabled, 0, "no module switched off")
	local n = E.tl:count()
	click(); M.steps(4)
	check(E.tl:count() > n, "recording still works")
	click(); M.steps(2)
	local f = E.frame
	key(Enum.KeyCode.F)
	eq(E.frame, f - 1, "stepping back still works")
	local reported = 0
	for _, l in ipairs(M.logs) do if l:find("camera broke", 1, true) then reported = reported + 1 end end
	eq(reported, 1, "the error is reported once")
	cam.holdPaused = realHold
	key(Enum.KeyCode.One)
	M.steps(2)
	local kept = {}
	for _, l in ipairs(M.logs) do if not l:find("camera broke", 1, true) then kept[#kept + 1] = l end end
	M.logs = kept
end

section("a transition right after an unpause finishes it (jumping back on, not stuck in the first frame)")
key(Enum.KeyCode.One)
key(Enum.KeyCode.Two)
M.steps(2)
click()
eq(jumpEnabled(), false, "(no jump on the first frame)")
key(Enum.KeyCode.One)
M.steps(3)
eq(jumpEnabled(), true, "Idle within a frame of the unpause: jumping on")
eq(E.firstFrame, false, "not stuck in the first frame")
key(Enum.KeyCode.Two)
M.steps(2)
click()
click()
M.steps(3)
eq(jumpEnabled(), true, "Pause within a frame of the unpause: jumping on")
eq(E.firstFrame, false, "not stuck in the first frame (pause)")
key(Enum.KeyCode.V)
key(Enum.KeyCode.Three)
M.steps(3)
eq(jumpEnabled(), true, "Test within a frame of Unpause 1 Frame: jumping on")
key(Enum.KeyCode.One)
M.steps(2)

finish()
