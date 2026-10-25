-- ================================================================================================
-- HappaTAS 3, phase 4: timed buttons ("Sync Button Timers", V2.38.17 p14_buttons.lua 12-1811): presses
-- recorded with their frame, the kit's timer on the TAS clock (frozen while paused, exact when scrubbing,
-- on the TAS clock in Test), ids saved with their workspace paths
-- ================================================================================================
M.clockStep = 0
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local tl = E.tl

-- the EToH kit's button: Pressed + TimerStart next to its ButtonPart; a Heartbeat loop releases it when
-- Timer - (os.clock() - TimerStart) <= 0 (Repository/Interactables/Button)
local folder = Instance.new("Folder"); folder.Name = "Buttons"; folder.Parent = workspace
local model = Instance.new("Model"); model.Name = "Button"; model.Parent = folder
local bp = Instance.new("Part"); bp.Name = "ButtonPart"; bp.Anchored = true; bp.Parent = model
local cfg = Instance.new("Configuration"); cfg.Name = "ButtonConfiguration"; cfg.Parent = model
local timer = Instance.new("NumberValue"); timer.Name = "Timer"; timer.Value = 1; timer.Parent = cfg
local timerStart = Instance.new("NumberValue"); timerStart.Name = "TimerStart"; timerStart.Parent = cfg
local pressed = Instance.new("BoolValue"); pressed.Name = "Pressed"; pressed.Parent = model
local kitLoop = M.services.RunService.Heartbeat:Connect(function()
	if pressed.Value and timer.Value - (os.clock() - timerStart.Value) <= 0 then pressed.Value = false end
end)
local function press()
	timerStart.Value = os.clock()
	pressed.Value = true
end

E.settings:set("syncButtonTimers", 1)
M.steps(5)
eq(E.buttons:count(), 1, "one button bound")

local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
local function click()
	local UIS = M.services.UserInputService
	UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	UIS.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
local function eventFrame()
	for i = 1, tl:count() do
		local bt = tl:getList("v2BT", i)
		if bt then for _, e in ipairs(bt) do if e[2] == 1 then return i, e end end end
	end
	return nil
end

section("a press is recorded on its frame")
key(Enum.KeyCode.Two)
M.steps(3)
click()
M.steps(10)
press()
M.steps(10)
local pf, ev = eventFrame()
check(pf ~= nil, "a press event")
eq(ev and ev[3], 0, "pressed on that frame (no time already run)")
local pressT = pf and tl:get("TotalTime", pf, 1)

section("paused: the kit's timer stands still")
click()
M.steps(3)
check(pressed.Value, "still pressed when pausing")
for _ = 1, 120 do M.step(1 / 60) end -- 2 s of real time, longer than the timer
check(pressed.Value, "still pressed after 2 s paused")
local nowT = tl:get("TotalTime", E.frame, 1)
near(os.clock() - timerStart.Value, nowT - pressT, 0.02, "TimerStart = the TAS time since the press")

section("scrubbing: the button's state on every frame shown")
for _ = 1, 15 do key(Enum.KeyCode.F); M.steps(2) end
check(E.frame < pf, "back before the press (frame " .. E.frame .. ")")
eq(pressed.Value, false, "not pressed before the press")
for _ = 1, 20 do key(Enum.KeyCode.G); M.steps(2) end
check(E.frame > pf, "after the press again")
check(pressed.Value, "pressed again")
near(os.clock() - timerStart.Value, tl:get("TotalTime", E.frame, 1) - pressT, 0.02, "with the TAS time since the press")

section("recording on: released by the kit at the recorded TAS time")
while E.frame < tl:count() do key(Enum.KeyCode.G); M.steps(2) end
click()
local releasedAt = nil
for _ = 1, 120 do
	M.step(1 / 60)
	if not pressed.Value and not releasedAt then releasedAt = tl:get("TotalTime", tl:count(), 1) end
end
check(releasedAt ~= nil, "released")
check(releasedAt and math.abs(releasedAt - pressT - 1) < 0.1, "1 s of TAS time after the press (" .. tostring(releasedAt and releasedAt - pressT) .. ")")
click()
M.steps(3)

section("Test: pressed and released at the recorded TAS times")
local testPress, testRelease = nil, nil
key(Enum.KeyCode.Three)
M.steps(1)
local g = 0
while E.mode == 3 and g < 600 do
	M.step(1 / 60)
	g = g + 1
	local t = E.testTime
	if pressed.Value and not testPress then testPress = t end
	if testPress and not pressed.Value and not testRelease then testRelease = t end
end
check(testPress and math.abs(testPress - pressT) < 0.05, "pressed at the recorded time (" .. tostring(testPress) .. " / " .. tostring(pressT) .. ")")
check(testRelease and math.abs(testRelease - testPress - 1) < 0.1, "released 1 s later")
M.steps(3)

section("Idle: the kit's timer runs on os.clock again")
eq(E.mode, 1, "idle")
press()
for _ = 1, 70 do M.step(1 / 60) end
eq(pressed.Value, false, "the kit released it after 1 s of real time")

section("ids are saved with their paths")
E.plugins:call("onSave", tl)
local keys = tl.meta.v2buttons
check(type(keys) == "table" and keys[1] and keys[1].key == "Buttons/Button", "v2buttons has the button's path")

section("off: released, the events kept")
local n = 0
for i = 1, tl:count() do if tl:getList("v2BT", i) then n = n + 1 end end
E.settings:set("syncButtonTimers", 0)
M.steps(2)
eq(E.buttons:count(), 0, "unbound")
local n2 = 0
for i = 1, tl:count() do if tl:getList("v2BT", i) then n2 = n2 + 1 end end
eq(n2, n, "the run keeps its button events")
kitLoop:Disconnect()
folder:Destroy()
finish()
