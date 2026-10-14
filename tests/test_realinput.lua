-- ================================================================================================
-- Real's input and garbage-collector functions, as measured in the Roblox client (V2.38.2):
--  * keypress sends scancodes without the extended-key flag: Up came out as KeypadEight, Home as
--    KeypadSeven, RightControl as LeftControl -> those keys go through VirtualInputManager
--  * input functions send nothing while the Roblox window isn't active -> held keys are pressed when it is
--  * mousemoveabs scales with integer maths and Roblox shows a move only at the next mouse event -> every
--    move is followed by a 1 px step back and forth, and aimed through the measured fit
--  * camera controllers are found with filtergc instead of getgc(true)
-- ================================================================================================
-- fake camera controllers in the garbage collector, found at start-up
local ctrlClass = { __index = {
	SetCameraToSubjectDistance = function(self, d) self.currentSubjectDistance = d end,
	GetCameraToSubjectDistance = function(self) return self.currentSubjectDistance end,
} }
local zc1 = setmetatable({ currentSubjectDistance = 12.5 }, ctrlClass)
local zc2 = setmetatable({ currentSubjectDistance = 20 }, ctrlClass)
local lockCtrl = { isMouseLocked = false }
M.gcTables = { zc1, { currentSubjectDistance = "not a controller" }, zc2, { activeMouseLockController = lockCtrl }, lockCtrl }

check(boot(5), "boots")
local IS, S = __T.InputSys, __T.Settings

local function logHas(pattern)
	for _, l in ipairs(M.logs) do if l:find(pattern, 1, true) then return true end end
	return false
end

section("camera controllers are found with filtergc, not getgc(true)")
M.steps(2)
check(M.gcCalls.filtergc >= 1, "filtergc was used (" .. M.gcCalls.filtergc .. " calls)")
eq(M.gcCalls.getgc, 0, "getgc was not called")
check(logHas("2 zoom controller(s) found (filtergc)"), "both zoom controllers found, the other table skipped")

-- ------------------------------------------------------------------------------------------------ keys
local function id(kc) return IS.IdOf(M.input(Enum.UserInputType.Keyboard, kc)) end
local function sent(kind, a, b)
	for _, e in ipairs(M.inputLog) do
		if e[1] == kind and e[2] == a and (b == nil or e[3] == b) then return true end
	end
	return false
end
S.Set("Replay Keyboard", 1)
S.Set("Window Guarding", 1)

section("extended keys go through VirtualInputManager with their exact KeyCode")
do
	local began = {}
	local conn = M.services.UserInputService.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.Keyboard then began[inp.KeyCode.Name] = true end
	end)
	local data = {
		{ Input = { id(Enum.KeyCode.Up), id(Enum.KeyCode.W), id(Enum.KeyCode.RightControl), id(Enum.KeyCode.Home), id(Enum.KeyCode.Left) } },
		{ Input = { -id(Enum.KeyCode.Up), -id(Enum.KeyCode.W), -id(Enum.KeyCode.RightControl), -id(Enum.KeyCode.Home), -id(Enum.KeyCode.Left) } },
	}
	M.inputLog = {}
	IS.ReplayBegin(data, 1)
	IS.ReplayTo(data, 1)
	check(sent("vimkey", true, "Up"), "Up pressed through VirtualInputManager")
	check(sent("vimkey", true, "RightControl"), "RightControl too")
	check(sent("vimkey", true, "Home"), "Home too")
	check(sent("vimkey", true, "Left"), "Left too")
	check(sent("keypress", 0x57), "W (not extended) still through keypress")
	check(not sent("keypress", 0x26) and not sent("keypress", 0xA3) and not sent("keypress", 0x24) and not sent("keypress", 0x25),
		"no keypress for the extended keys (Real would send KeypadEight, LeftControl, KeypadSeven, KeypadFour)")
	check(began.Up and began.RightControl and began.Home and began.Left, "Roblox sees Up, RightControl, Home and Left")
	IS.ReplayTo(data, 2)
	check(sent("vimkey", false, "Up") and sent("vimkey", false, "RightControl") and sent("vimkey", false, "Home"), "released through VirtualInputManager")
	check(sent("keyrelease", 0x57), "W released through keyrelease")
	IS.ReplayEnd()
	conn:Disconnect()
end

section("if VirtualInputManager refuses, keypress is used")
do
	M.vimFail = true
	local data = { { Input = { id(Enum.KeyCode.Up) } }, { Input = { -id(Enum.KeyCode.Up) } } }
	M.inputLog = {}
	IS.ReplayBegin(data, 1)
	IS.ReplayTo(data, 1)
	check(sent("keypress", 0x26), "Up falls back to keypress")
	IS.ReplayTo(data, 2)
	check(sent("keyrelease", 0x26), "and keyrelease")
	IS.ReplayEnd()
	M.vimFail = false
end

section("a key pressed while the Roblox window wasn't active is pressed when it is active again")
do
	local data = { { Input = { id(Enum.KeyCode.W) } }, {}, {}, { Input = { -id(Enum.KeyCode.W) } } }
	M.inputLog = {}
	M.windowActive = false
	IS.ReplayBegin(data, 1)
	IS.ReplayTo(data, 1)
	check(not sent("keypress", 0x57), "nothing sent while the window isn't active")
	IS.ReplayTo(data, 2)
	check(not sent("keypress", 0x57), "still nothing")
	M.windowActive = true
	IS.ReplayTo(data, 3)
	check(sent("keypress", 0x57), "W pressed as soon as the window is active")
	local presses = 0
	for _, e in ipairs(M.inputLog) do if e[1] == "keypress" and e[2] == 0x57 then presses = presses + 1 end end
	IS.ReplayTo(data, 3)
	eq(presses, 1, "pressed once")
	IS.ReplayTo(data, 4)
	check(sent("keyrelease", 0x57), "released on its frame")
	IS.ReplayEnd()
end

-- ------------------------------------------------------------------------------------------------ mouse
-- (no frames are stepped here: the core ends a replay on the next frame outside Test mode, and the mock's
-- mouse answers at once)
section("real mouse: each move is flushed, and aimed through the measured fit")
do
	S.Set("Replay Mouse Movement", 1)
	S.Set("Normalize Mouse UV", 0)
	M.realMouse = { w = 1920, h = 1080, ox = 0, oy = 23 }
	M.mouse, M.osMouse = Vector2.new(960, 500), nil
	M.inputLog = {}
	IS.ReplayBegin({ {}, {} }, 1)
	-- a cursor path over the whole window: from the far corner (where Real's error is biggest) to the
	-- top left, then a zig-zag back
	local path = {}
	for i = 0, 29 do path[#path + 1] = { 1800 - i * 60, 950 - i * 30 } end
	for i = 0, 39 do path[#path + 1] = { 60 + i * 45, (i % 2 == 0) and 950 or 120 + i * 5 } end
	local worstBefore, worstAfter, calibratedAt = 0, 0, nil
	local flushed = true
	for k, p in ipairs(path) do
		local logStart = #M.inputLog
		IS.ReplayMouse({ MX = p[1], MY = p[2], Zoom = 10 })
		local e1, e2, e3 = M.inputLog[logStart + 1], M.inputLog[logStart + 2], M.inputLog[logStart + 3]
		if not (e1 and e1[1] == "mousemoveabs" and e2 and e2[1] == "mousemoverel" and e2[2] == 1 and e3 and e3[1] == "mousemoverel" and e3[2] == -1) then
			flushed = false
		end
		local err = math.max(math.abs(M.mouse.X - p[1]), math.abs(M.mouse.Y - p[2]))
		local c = IS.MouseCalibration()
		if c.x.ok and c.y.ok then
			calibratedAt = calibratedAt or k
			if k > calibratedAt then worstAfter = math.max(worstAfter, err) end
		else
			worstBefore = math.max(worstBefore, err)
		end
	end
	M.realPrint(string.format("   fit ready at move %s, worst before it %d px, after it %d px", tostring(calibratedAt), worstBefore, worstAfter))
	check(flushed, "every mousemoveabs is followed by mousemoverel(1, 0) and mousemoverel(-1, 0)")
	check(calibratedAt ~= nil and calibratedAt <= 12, "the fit is ready after a few moves (move " .. tostring(calibratedAt) .. ")")
	check(worstBefore >= 6, "before the fit the cursor lands short like Real's (" .. worstBefore .. " px)")
	check(worstAfter <= 1, "after it, every move lands within 1 px (" .. worstAfter .. " px)")
	local c = IS.MouseCalibration()
	near(c.x.a, 34 * 1920 / 65536, 0.002, "x scale like Real's (34 * 1920 / 65536)")
	near(c.y.a, 60 * 1080 / 65536, 0.002, "y scale like Real's (60 * 1080 / 65536)")
	IS.ReplayEnd()
end

section("a hand on the mouse isn't used for the fit")
do
	local c0 = IS.MouseCalibration()
	IS.ReplayBegin({ {}, {} }, 1)
	IS.ReplayMouse({ MX = 500, MY = 500, Zoom = 10 })
	IS.ReplayMouse({ MX = 520, MY = 510, Zoom = 10 }) -- reads where the first move landed
	local c1 = IS.MouseCalibration()
	eq(c1.x.n, c0.x.n + 1, "the landed move was added")
	M.mouse = Vector2.new(1700, 200) -- the player moved the mouse
	M.osMouse = M.mouse
	IS.ReplayMouse({ MX = 540, MY = 520, Zoom = 10 })
	local c2 = IS.MouseCalibration()
	eq(c2.x.n, c1.x.n, "the hand-moved reading wasn't")
	near(c2.x.a, c0.x.a, 0.001, "the fit didn't move")
	IS.ReplayEnd()
	M.realMouse = nil
end

section("a resized window starts the fit again")
do
	local before = IS.MouseCalibration()
	check(before.x.ok, "fit ready")
	local vp = M.viewport
	M.viewport = Vector2.new(vp.X - 100, vp.Y - 100)
	IS.ReplayBegin({ {}, {} }, 1)
	IS.ReplayMouse({ MX = 400, MY = 300, Zoom = 10 })
	local after = IS.MouseCalibration()
	check(not after.x.ok and after.x.n == 0, "measured again after a resize")
	IS.ReplayEnd()
	M.viewport = vp
end

finish()
