-- ================================================================================================
-- HappaTAS 3, phase 2: the inputs plugin (recording keys / clicks / wheel / mouse, replay through the
-- executor's functions (keypress only since V2.38.17), the window-focus rule, the real-mouse fit)
-- Sections ported from V2.38.16's tests/test_realinput.lua and tests/test_typing.lua.
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local Timeline = __T3("engine/timeline")
local Inputs = __T3("world/inputs")
local IS = E.inputs
local UIS = M.services.UserInputService
local function id(kc) return Inputs.idOf(M.input(Enum.UserInputType.Keyboard, kc)) end
local function sent(kind, a, b)
	for _, e in ipairs(M.inputLog) do
		if e[1] == kind and e[2] == a and (b == nil or e[3] == b) then return true end
	end
	return false
end
-- a small run with the columns the replay reads
local function run(frames)
	local tl = Timeline.new()
	tl:addColumn("Input", "list", 1, { key = "Input" })
	tl:addColumn("Mouse", "f64", 4, { keys = { "MX", "MY", "UVX", "UVY" } })
	tl:addColumn("ShiftLock", "u8", 1, { key = "ShiftLock" })
	tl:addColumn("Zoom", "f64", 1, { key = "Zoom" })
	for _, f in ipairs(frames) do
		local i = tl:append()
		tl:setList("Input", i, f.Input)
		tl:setN("Mouse", i, f.MX or 0, f.MY or 0, 0, 0)
		tl:set("Zoom", i, 1, f.Zoom or 10)
		tl:setFilled(i)
	end
	return tl
end

section("key ids are V2's (file format)")
eq(id(Enum.KeyCode.A), 1, "A"); eq(id(Enum.KeyCode.W), 23, "W"); eq(id(Enum.KeyCode.Z), 26, "Z")
eq(id(Enum.KeyCode.Zero), 27, "0"); eq(id(Enum.KeyCode.Nine), 36, "9"); eq(id(Enum.KeyCode.Space), 37, "Space")
eq(id(Enum.KeyCode.LeftShift), 41, "LeftShift"); eq(id(Enum.KeyCode.Up), 47, "Up"); eq(id(Enum.KeyCode.F1), 57, "F1")
eq(Inputs.idOf(M.input(Enum.UserInputType.MouseButton1)), 96, "LMB"); eq(Inputs.idOf(M.input(Enum.UserInputType.MouseButton2)), 97, "RMB")

section("held keys at a frame; the start of a recording")
do
	local tl = run({ { Input = { 23, 37 } }, { Input = { -37, 10001 } }, { Input = { 1 } } })
	local held = IS:heldAt(tl, 2)
	check(held[23] and not held[37] and not held[10001], "W held, Space released, the wheel isn't a key")
	held = IS:heldAt(tl, 3, { [5] = true })
	check(held[23] and held[1] and held[5], "with a base")
	-- resuming from frame 3 with nothing held live: the recording starts by releasing W and A
	IS:beginRecording(tl, nil)
	local q = IS:take()
	eq(table.concat(q, ","), "-1,-23", "releases what the frame held (sorted by id)")
end

section("recording: keys, clicks, wheel; controls and typing are not recorded")
M.pressKey(Enum.KeyCode.Two); M.releaseKey(Enum.KeyCode.Two)
M.steps(2)
UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
M.steps(2)
check(not E.paused, "recording")
M.pressKey(Enum.KeyCode.W)
M.wheel(1)
M.mouseDown(2, false)
M.steps(1)
E.settings:set("ignoreGameProcessed", 1) -- (so only the typing check keeps the chat key out)
M.chatBar.IsFocused = true
M.pressKey(Enum.KeyCode.H, true); M.releaseKey(Enum.KeyCode.H, true)
M.chatBar.IsFocused = false
E.settings:set("ignoreGameProcessed", 0)
M.pressKey(Enum.KeyCode.L); M.releaseKey(Enum.KeyCode.L) -- (Look Around: a control, does nothing while recording)
M.releaseKey(Enum.KeyCode.W)
M.mouseUp(2, false)
M.steps(2)
UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
M.steps(2)
local seen = {}
for i = 1, E.tl:count() do
	for _, e in ipairs(E.tl:getList("Input", i) or {}) do seen[e] = true end
end
check(seen[23] and seen[-23], "W pressed and released")
check(seen[10001], "one wheel notch up")
check(seen[97] and seen[-97], "right button")
check(not seen[8], "H typed in chat not recorded")
check(not seen[96] and not seen[28] and not seen[12], "controls (the Pause click, Create, Look Around) not recorded")
local mx = E.tl:getN("Mouse", 1)
eq(mx, math.floor(UIS:GetMouseLocation().X + 0.5), "mouse X recorded")
check(E.tl:getList("Viewport", 1) ~= nil, "the viewport on the first frame")
check(E.tl:getList("Viewport", 2) == nil, "and only when it changes")
M.pressKey(Enum.KeyCode.One); M.releaseKey(Enum.KeyCode.One)
M.steps(2)

E.settings:set("replayKeyboard", 1)
E.settings:set("windowGuarding", 1)
section("keys replay through keypress only (V2.38.17)")
do
	local tl = run({
		{ Input = { id(Enum.KeyCode.Up), id(Enum.KeyCode.W), id(Enum.KeyCode.RightControl), id(Enum.KeyCode.Home), id(Enum.KeyCode.Left) } },
		{ Input = { -id(Enum.KeyCode.Up), -id(Enum.KeyCode.W), -id(Enum.KeyCode.RightControl), -id(Enum.KeyCode.Home), -id(Enum.KeyCode.Left) } },
	})
	M.inputLog = {}
	IS:replayBegin(tl, 1)
	IS:replayTo(tl, 1)
	check(sent("keypress", 0x26) and sent("keypress", 0x57) and sent("keypress", 0xA3) and sent("keypress", 0x24) and sent("keypress", 0x25),
		"Up, W, RightControl, Home, Left through keypress")
	local vim = false
	for _, e in ipairs(M.inputLog) do if e[1] == "vimkey" then vim = true end end
	check(not vim, "nothing through VirtualInputManager")
	IS:replayTo(tl, 2)
	check(sent("keyrelease", 0x26) and sent("keyrelease", 0x57) and sent("keyrelease", 0xA3), "released through keyrelease")
	IS:replayEnd()
end

section("a key held while the window wasn't active is pressed when it is")
do
	local tl = run({ { Input = { id(Enum.KeyCode.W) } }, {}, {}, { Input = { -id(Enum.KeyCode.W) } } })
	M.inputLog = {}
	M.windowActive = false
	IS:replayBegin(tl, 1)
	IS:replayTo(tl, 1)
	IS:replayTo(tl, 2)
	check(not sent("keypress", 0x57), "nothing sent while the window isn't active")
	M.windowActive = true
	IS:replayTo(tl, 3)
	IS:replayTo(tl, 3)
	local presses = 0
	for _, e in ipairs(M.inputLog) do if e[1] == "keypress" and e[2] == 0x57 then presses = presses + 1 end end
	eq(presses, 1, "W pressed once, as soon as the window is active")
	IS:replayTo(tl, 4)
	check(sent("keyrelease", 0x57), "released on its frame")
	IS:replayEnd()
end

section("no input function: that replay is off, no error")
do
	local keys = IS.available.keys
	IS.available.keys = false
	local tl = run({ { Input = { id(Enum.KeyCode.W) } }, { Input = { -id(Enum.KeyCode.W) } } })
	M.inputLog = {}
	local ok = pcall(function()
		IS:replayBegin(tl, 1)
		IS:replayTo(tl, 2)
		IS:replayEnd()
	end)
	check(ok, "no error")
	check(not sent("keypress", 0x57), "nothing sent")
	IS.available.keys = keys
end

section("real mouse: each move is flushed, and aimed through the measured fit")
do
	E.settings:set("replayMouseMovement", 1)
	E.settings:set("normalizeMouseUV", 0)
	M.realMouse = { w = 1920, h = 1080, ox = 0, oy = 23 }
	M.mouse, M.osMouse = Vector2.new(960, 500), nil
	M.inputLog = {}
	local tl = run({ {}, {} })
	IS:replayBegin(tl, 1)
	local path = {}
	for i = 0, 29 do path[#path + 1] = { 1800 - i * 60, 950 - i * 30 } end
	for i = 0, 39 do path[#path + 1] = { 60 + i * 45, (i % 2 == 0) and 950 or 120 + i * 5 } end
	local worstBefore, worstAfter, calibratedAt, flushed = 0, 0, nil, true
	for k, p in ipairs(path) do
		local logStart = #M.inputLog
		tl:setN("Mouse", 1, p[1], p[2], 0, 0)
		IS:replayMouse(tl, 1)
		local e1, e2, e3 = M.inputLog[logStart + 1], M.inputLog[logStart + 2], M.inputLog[logStart + 3]
		if not (e1 and e1[1] == "mousemoveabs" and e2 and e2[1] == "mousemoverel" and e2[2] == 1 and e3 and e3[1] == "mousemoverel" and e3[2] == -1) then
			flushed = false
		end
		local err = math.max(math.abs(M.mouse.X - p[1]), math.abs(M.mouse.Y - p[2]))
		local c = IS:calibration()
		if c.x.ok and c.y.ok then
			calibratedAt = calibratedAt or k
			if k > calibratedAt then worstAfter = math.max(worstAfter, err) end
		else
			worstBefore = math.max(worstBefore, err)
		end
	end
	check(flushed, "every mousemoveabs is followed by mousemoverel(1, 0) and (-1, 0)")
	check(calibratedAt ~= nil and calibratedAt <= 12, "the fit is ready after a few moves (" .. tostring(calibratedAt) .. ")")
	check(worstBefore >= 6, "before the fit the cursor lands short like Real's (" .. worstBefore .. " px)")
	check(worstAfter <= 1, "after it within 1 px (" .. worstAfter .. " px)")
	local c = IS:calibration()
	near(c.x.a, 34 * 1920 / 65536, 0.002, "x scale like Real's")
	near(c.y.a, 60 * 1080 / 65536, 0.002, "y scale like Real's")
	-- a hand on the mouse isn't used for the fit (a new replay: no move pending)
	IS:replayBegin(tl, 1)
	local c0 = IS:calibration()
	tl:setN("Mouse", 1, 500, 500, 0, 0); IS:replayMouse(tl, 1)
	tl:setN("Mouse", 1, 520, 510, 0, 0); IS:replayMouse(tl, 1)
	local c1 = IS:calibration()
	eq(c1.x.n, c0.x.n + 1, "the landed move was added")
	M.mouse = Vector2.new(1700, 200)
	M.osMouse = M.mouse
	tl:setN("Mouse", 1, 540, 520, 0, 0); IS:replayMouse(tl, 1)
	eq(IS:calibration().x.n, c1.x.n, "the hand-moved reading wasn't")
	-- a locked frame (shift lock) moves nothing
	local n0 = #M.inputLog
	tl:set("ShiftLock", 1, 1, 1)
	tl:setN("Mouse", 1, 700, 700, 0, 0); IS:replayMouse(tl, 1)
	eq(#M.inputLog, n0, "no move on a shift-locked frame")
	-- a resized window starts the fit again
	tl:set("ShiftLock", 1, 1, 0)
	local vp = M.viewport
	M.viewport = Vector2.new(vp.X - 100, vp.Y - 100)
	tl:setN("Mouse", 1, 400, 300, 0, 0); IS:replayMouse(tl, 1)
	local after = IS:calibration()
	check(not after.x.ok and after.x.n == 0, "measured again after a resize")
	M.viewport = vp
	IS:replayEnd()
	M.realMouse = nil
end
finish()
