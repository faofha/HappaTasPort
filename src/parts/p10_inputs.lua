-- ================================================================================================
--  INPUTS   (keyboard + mouse recording and replay through the executor's input functions)
--
--  Key ids are part of the file format (A-Z = 1-26, 0-9 = 27-36, ... LMB 96, RMB 97): never reorder.
--  A frame stores a list of events: id = pressed, -id = released, 10000 + n = n wheel notches.
-- ================================================================================================
do
	local floor = math.floor

	InputSys.Available = {
		Keys = Env.keypress ~= nil and Env.keyrelease ~= nil,
		Clicks = Env.mouse1press ~= nil and Env.mouse1release ~= nil and Env.mouse2press ~= nil and Env.mouse2release ~= nil,
		Move = Env.mousemoveabs ~= nil,
		Scroll = Env.mousescroll ~= nil,
	}

	local SCROLL_BASE = Codec.ScrollBase
	local SCROLL_LIMIT = SCROLL_BASE - 5000
	local SCROLL_UNIT = 120

	local KEYLIST = {
		{ "A", 0x41, "A" }, { "B", 0x42, "B" }, { "C", 0x43, "C" }, { "D", 0x44, "D" }, { "E", 0x45, "E" }, { "F", 0x46, "F" },
		{ "G", 0x47, "G" }, { "H", 0x48, "H" }, { "I", 0x49, "I" }, { "J", 0x4A, "J" }, { "K", 0x4B, "K" }, { "L", 0x4C, "L" },
		{ "M", 0x4D, "M" }, { "N", 0x4E, "N" }, { "O", 0x4F, "O" }, { "P", 0x50, "P" }, { "Q", 0x51, "Q" }, { "R", 0x52, "R" },
		{ "S", 0x53, "S" }, { "T", 0x54, "T" }, { "U", 0x55, "U" }, { "V", 0x56, "V" }, { "W", 0x57, "W" }, { "X", 0x58, "X" },
		{ "Y", 0x59, "Y" }, { "Z", 0x5A, "Z" },
		{ "Zero", 0x30, "0" }, { "One", 0x31, "1" }, { "Two", 0x32, "2" }, { "Three", 0x33, "3" }, { "Four", 0x34, "4" },
		{ "Five", 0x35, "5" }, { "Six", 0x36, "6" }, { "Seven", 0x37, "7" }, { "Eight", 0x38, "8" }, { "Nine", 0x39, "9" },
		{ "Space", 0x20, "Space" }, { "Return", 0x0D, "Enter" }, { "Tab", 0x09, "Tab" }, { "Backspace", 0x08, "Bksp" },
		{ "LeftShift", 0xA0, "LShift" }, { "RightShift", 0xA1, "RShift" }, { "LeftControl", 0xA2, "LCtrl" },
		{ "RightControl", 0xA3, "RCtrl" }, { "LeftAlt", 0xA4, "LAlt" }, { "RightAlt", 0xA5, "RAlt" },
		{ "Up", 0x26, "Up" }, { "Down", 0x28, "Down" }, { "Left", 0x25, "Left" }, { "Right", 0x27, "Right" },
		{ "Insert", 0x2D, "Ins" }, { "Delete", 0x2E, "Del" }, { "Home", 0x24, "Home" }, { "End", 0x23, "End" },
		{ "PageUp", 0x21, "PgUp" }, { "PageDown", 0x22, "PgDn" },
		{ "F1", 0x70, "F1" }, { "F2", 0x71, "F2" }, { "F3", 0x72, "F3" }, { "F4", 0x73, "F4" }, { "F5", 0x74, "F5" },
		{ "F6", 0x75, "F6" }, { "F7", 0x76, "F7" }, { "F8", 0x77, "F8" }, { "F9", 0x78, "F9" }, { "F10", 0x79, "F10" },
		{ "F11", 0x7A, "F11" }, { "F12", 0x7B, "F12" },
		{ "Minus", 0xBD, "-" }, { "Equals", 0xBB, "=" }, { "LeftBracket", 0xDB, "[" }, { "RightBracket", 0xDD, "]" },
		{ "BackSlash", 0xDC, "\\" }, { "Semicolon", 0xBA, ";" }, { "Quote", 0xDE, "'" }, { "Comma", 0xBC, "," },
		{ "Period", 0xBE, "." }, { "Slash", 0xBF, "/" }, { "Backquote", 0xC0, "`" }, { "CapsLock", 0x14, "Caps" },
		{ "KeypadZero", 0x60, "Num0" }, { "KeypadOne", 0x61, "Num1" }, { "KeypadTwo", 0x62, "Num2" },
		{ "KeypadThree", 0x63, "Num3" }, { "KeypadFour", 0x64, "Num4" }, { "KeypadFive", 0x65, "Num5" },
		{ "KeypadSix", 0x66, "Num6" }, { "KeypadSeven", 0x67, "Num7" }, { "KeypadEight", 0x68, "Num8" },
		{ "KeypadNine", 0x69, "Num9" }, { "KeypadMultiply", 0x6A, "Num*" }, { "KeypadPlus", 0x6B, "Num+" },
		{ "KeypadMinus", 0x6D, "Num-" }, { "KeypadPeriod", 0x6E, "Num." }, { "KeypadDivide", 0x6F, "Num/" },
		{ false, false, "LMB" }, { false, false, "RMB" },
	}
	local ID_M1, ID_M2 = 96, 97
	InputSys.ID_M1, InputSys.ID_M2 = ID_M1, ID_M2

	local KEY_BY_ENUM, KEY_VK, KEY_SHORT, KEY_KC = {}, {}, {}, {}
	for id, k in ipairs(KEYLIST) do
		KEY_SHORT[id] = k[3]
		if k[1] then
			local ok, item = pcall(function() return Enum.KeyCode[k[1]] end)
			if ok and item then
				KEY_BY_ENUM[item] = id
				KEY_VK[id] = k[2]
				KEY_KC[id] = item
			end
		end
	end
	-- Windows "extended" keys: their scancode needs the extended-key flag. Real's keypress sends the key's
	-- scancode with KEYEVENTF_SCANCODE only (Real docs), so in the Roblox client Up came out as KeypadEight,
	-- Left as KeypadFour, Home as KeypadSeven, RightControl as LeftControl, ... (tested). These keys are
	-- replayed through VirtualInputManager:SendKeyEvent, which gives Roblox the exact KeyCode (tested too).
	local EXTENDED = { [0x21] = true, [0x22] = true, [0x23] = true, [0x24] = true, [0x25] = true, [0x26] = true,
		[0x27] = true, [0x28] = true, [0x2D] = true, [0x2E] = true, [0x6F] = true, [0xA3] = true, [0xA5] = true }

	local function isMouseId(id) return id == ID_M1 or id == ID_M2 end

	-- keys bound to HappaTAS controls are never recorded or replayed
	local controlIds, controlDirty = {}, true
	Controls.Changed("*", function() controlDirty = true end)
	local function getControlIds()
		if controlDirty then
			controlDirty = false
			controlIds = {}
			for _, cdef in ipairs(ControlsTable) do
				local item = ToKey[Controls.Get(cdef[1]) or ""]
				if item then
					if item == Enum.UserInputType.MouseButton1 then controlIds[ID_M1] = true
					elseif item == Enum.UserInputType.MouseButton2 then controlIds[ID_M2] = true
					elseif KEY_BY_ENUM[item] then controlIds[KEY_BY_ENUM[item]] = true end
				end
			end
		end
		return controlIds
	end

	local live = { held = {} }
	local queue = {}
	local ownWindows = {}
	InputSys.Live = live

	local function pushEvent(e)
		queue[#queue + 1] = e
		if #queue > 256 then table.remove(queue, 1) end
	end

	local function overOwnUI()
		local okM, m = pcall(UIS.GetMouseLocation, UIS)
		if not okM then return false end
		local inset = Vector2.zero
		if GuiService then pcall(function() inset = GuiService:GetGuiInset() end) end
		for _, f in ipairs(ownWindows) do
			if f and f.Visible then
				local p, s = f.AbsolutePosition, f.AbsoluteSize
				local x, y = m.X - inset.X, m.Y - inset.Y
				if x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y then return true end
				x, y = m.X, m.Y
				if x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y then return true end
			end
		end
		return Profiler.IsMouseOver ~= nil and Profiler.IsMouseOver(m) or false
	end
	-- a mouse button pressed over a HappaTAS window (menu, merge dialog, MicroProfiler) is meant for that
	-- window, never a HappaTAS control (Left Click = Pause / Unpause)
	local MOUSE_BUTTON = { [Enum.UserInputType.MouseButton1] = true, [Enum.UserInputType.MouseButton2] = true,
		[Enum.UserInputType.MouseButton3] = true }
	function InputSys.ClickOnOwnUI(inp)
		return MOUSE_BUTTON[inp.UserInputType] == true and overOwnUI()
	end

	local function idOf(inp)
		local t = inp.UserInputType
		if t == Enum.UserInputType.Keyboard then
			return KEY_BY_ENUM[inp.KeyCode]
		elseif t == Enum.UserInputType.MouseButton1 then
			return ID_M1
		elseif t == Enum.UserInputType.MouseButton2 then
			return ID_M2
		end
		return nil
	end
	InputSys.IdOf = idOf

	local ignoring = Typing.Active -- typing (chat, a text box) or in the Roblox menu: nothing is recorded

	local function onBegan(inp, proc)
		if proc and not Settings.On("Ignore Game Processed") then return end
		local id = idOf(inp)
		if not id or getControlIds()[id] or ignoring(inp) then return end
		if isMouseId(id) and overOwnUI() then return end
		if live.held[id] then return end
		live.held[id] = true
		pushEvent(id)
		-- a key / click the replay pressed itself comes back here like real input (found in the live
		-- client: Sound Mode 0 = live only played the replayed keys, 2 played them twice)
		local rp = InputSys.Replay
		local t = rp and rp.recent[id]
		if t then
			rp.recent[id] = nil
			if os.clock() - t < 0.5 then return end
		end
		if Sounds.PlayLive then Sounds.PlayLive(id, isMouseId(id), id == ID_M2) end
	end

	local function onEnded(inp, proc)
		local id = idOf(inp)
		if id and live.held[id] then
			live.held[id] = nil
			pushEvent(-id)
		end
	end

	local function onChanged(inp)
		if inp.UserInputType ~= Enum.UserInputType.MouseWheel then return end
		if ignoring() or overOwnUI() then return end
		pushEvent(SCROLL_BASE + (inp.Position.Z > 0 and 1 or -1))
	end

	local function onFocusLost()
		for id in pairs(live.held) do pushEvent(-id) end
		live.held = {}
	end

	function InputSys.Take()
		if #queue == 0 then return nil end
		local q = queue
		queue = {}
		return q
	end

	function InputSys.Clear()
		if #queue > 0 then queue = {} end
	end

	-- mouse position in window pixels + the same position normalised to the viewport (0..1)
	function InputSys.Mouse()
		local v = UIS:GetMouseLocation()
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
		local mx, my = floor(v.X + 0.5), floor(v.Y + 0.5)
		local vx, vy = vp.X, vp.Y
		local uvx = vx > 0 and clampn(mx / vx, 0, 1) or 0.5
		local uvy = vy > 0 and clampn(my / vy, 0, 1) or 0.5
		return mx, my, uvx, uvy, vx, vy
	end

	function InputSys.HeldAt(data, upTo, base)
		local set = {}
		if base then for id in pairs(base) do set[id] = true end end
		for i = 1, math.min(upTo, #data) do
			local ev = data[i].Input
			if ev then
				for k = 1, #ev do
					local e = ev[k]
					if e < SCROLL_LIMIT then
						if e > 0 then set[e] = true else set[-e] = nil end
					end
				end
			end
		end
		return set
	end

	-- unpausing: tell the recording which keys go up / down compared to the frame we resume from
	function InputSys.BeginRecording(data, base)
		queue = {}
		local want = InputSys.HeldAt(data, #data, base)
		local ids = {}
		for id in pairs(want) do if not live.held[id] then ids[#ids + 1] = -id end end
		for id in pairs(live.held) do if not want[id] then ids[#ids + 1] = id end end
		table.sort(ids, function(a, b) return math.abs(a) < math.abs(b) end)
		for _, e in ipairs(ids) do queue[#queue + 1] = e end
	end

	function InputSys.Describe(set)
		local ids = {}
		for id in pairs(set) do ids[#ids + 1] = id end
		if #ids == 0 then return "-" end
		table.sort(ids)
		local names = {}
		for i, id in ipairs(ids) do names[i] = KEY_SHORT[id] or "?" end
		return table.concat(names, " ")
	end

	-- ------------------------------------------------------------------------------------ replay
	-- recent: id -> os.clock() of the last press the replay sent (recognised when it comes back as input)
	local replay = { active = false, applied = 0, injected = {}, state = {}, recent = {}, lastMX = nil, lastMY = nil }
	InputSys.Replay = replay

	local function allowed(id)
		if getControlIds()[id] then return false end
		if isMouseId(id) then return InputSys.Available.Clicks and Settings.On("Replay Mouse Clicks") end
		return InputSys.Available.Keys and Settings.On("Replay Keyboard") and KEY_VK[id] ~= nil
	end

	-- an extended key through VirtualInputManager (false: not one, or no VirtualInputManager)
	local function vimKey(id, down)
		local vim, kc = Env.VirtualInput, KEY_KC[id]
		if not (vim and kc and EXTENDED[KEY_VK[id]]) then return false end
		return (pcall(vim.SendKeyEvent, vim, down, kc, false, game))
	end
	local function sendDown(id)
		return (pcall(function()
			if id == ID_M1 then Env.mouse1press() elseif id == ID_M2 then Env.mouse2press()
			elseif not vimKey(id, true) then Env.keypress(KEY_VK[id]) end
		end))
	end
	local function sendUp(id)
		pcall(function()
			if id == ID_M1 then Env.mouse1release() elseif id == ID_M2 then Env.mouse2release()
			elseif not vimKey(id, false) then Env.keyrelease(KEY_VK[id]) end
		end)
	end

	local function press(id)
		replay.state[id] = true
		if replay.injected[id] or not allowed(id) or not Env.WindowActive() then return end
		if sendDown(id) then
			replay.injected[id] = true
			replay.recent[id] = os.clock()
		end
	end
	local function release(id)
		replay.state[id] = nil
		if replay.injected[id] then
			sendUp(id)
			replay.injected[id] = nil
		end
	end

	local function applyEvent(e)
		if e >= SCROLL_LIMIT then
			local notches = e - SCROLL_BASE
			if notches ~= 0 and InputSys.Available.Scroll and Settings.On("Replay Mouse Clicks") and Env.WindowActive() then
				pcall(Env.mousescroll, notches * SCROLL_UNIT)
			end
		elseif e > 0 then
			press(e)
			if Sounds.PlayReplay then Sounds.PlayReplay(e, isMouseId(e), e == ID_M2) end
		else
			release(-e)
		end
	end

	local function syncTo(desired)
		for id in pairs(replay.injected) do
			if not desired[id] then release(id) end
		end
		for id in pairs(replay.state) do
			if not desired[id] then replay.state[id] = nil end
		end
		for id in pairs(desired) do
			if not replay.state[id] or not replay.injected[id] then press(id) end
		end
	end

	function InputSys.IsReplaying() return replay.active end

	function InputSys.ReplayBegin(data, startFrame)
		InputSys.ReplayEnd()
		replay.active = true
		replay.applied = startFrame - 1
		syncTo(InputSys.HeldAt(data, startFrame - 1))
	end

	function InputSys.ReplayTo(data, frame)
		if not replay.active then return end
		if frame > replay.applied then
			for f = replay.applied + 1, math.min(frame, #data) do
				local ev = data[f].Input
				if ev then
					for k = 1, #ev do applyEvent(ev[k]) end
				end
			end
		elseif frame < replay.applied then
			syncTo(InputSys.HeldAt(data, frame))
		end
		replay.applied = frame
		-- keys the TAS holds that weren't pressed because the Roblox window wasn't active (Real's input
		-- functions send nothing then, Real docs): pressed as soon as the window is active again
		if next(replay.state) ~= nil and Env.WindowActive() then
			for id in pairs(replay.state) do
				if not replay.injected[id] then press(id) end
			end
		end
	end

	-- true when the camera had the mouse locked on this recorded frame (shift lock, first person, right click)
	function InputSys.FrameLocked(fr)
		if not fr then return false end
		if fr.ShiftLock == 1 then return true end
		if (fr.Zoom or 99) < 1 then return true end
		return replay.state[ID_M2] == true
	end

	-- where the recorded cursor was, mapped to this window
	function InputSys.FramePoint(fr)
		if not fr or fr.MX == nil then return nil end
		if Settings.On("Normalize Mouse UV") and fr.UVX and fr.UVY then
			local cam = workspace.CurrentCamera
			local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
			return floor(fr.UVX * vp.X + 0.5), floor(fr.UVY * vp.Y + 0.5)
		end
		return fr.MX, fr.MY
	end

	-- ------------------------------------------------------------------------------------ real mouse
	-- Found in the Roblox client with Real's mousemoveabs:
	--  * Roblox takes an injected move only when the next mouse event comes (every move showed up one move
	--    late, and the last one never), so each move is followed by a 1 px step right and back.
	--  * Real scales the client point to the screen with integer maths (Real docs: GetSystemMetrics(SM_CXSCREEN)
	--    - 1); the factor 65535 / (width - 1) is cut to a whole number (34 instead of 34.15 at 1920 px, 60
	--    instead of 60.74 at 1080), so the cursor landed up to 0.4 % (x) / 1.2 % (y) short: 8 / 11 px at the
	--    far edges. Where a move really landed (UserInputService:GetMouseLocation, read before the next move)
	--    is fitted with a straight line per axis and the moves are aimed through it: within 1 px (tested).
	local function newAxis() return { n = 0, st = 0, sr = 0, stt = 0, str = 0, lo = math.huge, hi = -math.huge, a = 1, b = 0, ok = false } end
	local cal = { x = newAxis(), y = newAxis(), vx = 0, vy = 0, pend = nil }
	local CAL_SPREAD = 150   -- px between the lowest and highest sample before the fit is used
	local function calExpect(ax, t) return ax.ok and (ax.a * t + ax.b) or t end
	-- t = where a move was sent, r = where the cursor was read, prev = the move before (nil: none)
	local function calAdd(ax, t, r, prev)
		local expect = calExpect(ax, t)
		local tol = ax.ok and 3 or (math.abs(t) * 0.04 + 4)
		if math.abs(r - expect) > tol then return end -- not landed yet, or the mouse was moved by hand
		if prev and prev ~= t and math.abs(r - calExpect(ax, prev)) < math.abs(r - expect) then return end -- still the move before
		if ax.n >= 240 then -- forget the older half slowly (the window can move)
			ax.n, ax.st, ax.sr, ax.stt, ax.str = ax.n / 2, ax.st / 2, ax.sr / 2, ax.stt / 2, ax.str / 2
		end
		ax.n = ax.n + 1
		ax.st, ax.sr, ax.stt, ax.str = ax.st + t, ax.sr + r, ax.stt + t * t, ax.str + t * r
		if t < ax.lo then ax.lo = t end
		if t > ax.hi then ax.hi = t end
		if ax.n >= 6 and ax.hi - ax.lo >= CAL_SPREAD then
			local d = ax.n * ax.stt - ax.st * ax.st
			if d > 0 then
				local a = (ax.n * ax.str - ax.st * ax.sr) / d
				local b = (ax.sr - a * ax.st) / ax.n
				if a >= 0.9 and a <= 1.1 and math.abs(b) <= 64 then ax.a, ax.b, ax.ok = a, b, true end
			end
		end
	end
	local function calRead()
		local p = cal.pend
		if not p then return end
		cal.pend = nil
		if os.clock() - p[3] > 0.25 or UIS.MouseBehavior ~= Enum.MouseBehavior.Default then return end
		local okM, m = pcall(UIS.GetMouseLocation, UIS)
		if not okM then return end
		calAdd(cal.x, p[1], m.X, p[4])
		calAdd(cal.y, p[2], m.Y, p[5])
	end
	local function calAim(ax, v)
		if not ax.ok then return v end
		return floor((v - ax.b) / ax.a + 0.5)
	end
	function InputSys.MouseCalibration()
		return { x = { a = cal.x.a, b = cal.x.b, ok = cal.x.ok, n = cal.x.n }, y = { a = cal.y.a, b = cal.y.b, ok = cal.y.ok, n = cal.y.n } }
	end

	function InputSys.MoveRealMouse(x, y)
		if not InputSys.Available.Move or not Env.WindowActive() then return end
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize
		if vp and (vp.X ~= cal.vx or vp.Y ~= cal.vy) then -- window resized: measure again
			cal.x, cal.y, cal.vx, cal.vy, cal.pend, cal.sentX, cal.sentY = newAxis(), newAxis(), vp.X, vp.Y, nil, nil, nil
		end
		calRead()
		x, y = floor(x + 0.5), floor(y + 0.5)
		if x == replay.lastMX and y == replay.lastMY then return end
		replay.lastMX, replay.lastMY = x, y
		local sx, sy = calAim(cal.x, x), calAim(cal.y, y)
		if pcall(Env.mousemoveabs, sx, sy) then
			if Env.mousemoverel then
				pcall(Env.mousemoverel, 1, 0)
				pcall(Env.mousemoverel, -1, 0)
			end
			cal.pend = { sx, sy, os.clock(), cal.sentX, cal.sentY }
			cal.sentX, cal.sentY = sx, sy
		end
	end

	function InputSys.ReplayMouse(fr)
		if not replay.active or not fr or fr.MX == nil then return end
		if not Settings.On("Replay Mouse Movement") then return end
		if InputSys.FrameLocked(fr) then return end -- the cursor module moves the hidden cursor then
		local tx, ty = InputSys.FramePoint(fr)
		if tx then InputSys.MoveRealMouse(tx, ty) end
	end

	function InputSys.ReplayEnd()
		local had = replay.active
		for id in pairs(replay.injected) do sendUp(id) end
		replay.injected = {}
		replay.state = {}
		replay.active = false
		replay.applied = 0
		replay.lastMX, replay.lastMY = nil, nil
		cal.pend, cal.sentX, cal.sentY = nil, nil, nil
		return had
	end

	function InputSys.Start(gui)
		ownWindows = { gui.MainMenu, gui.Merge, gui.MergeStats, gui.JoinMessage }
		on(UIS.InputBegan, onBegan)
		on(UIS.InputEnded, onEnded)
		on(UIS.InputChanged, onChanged)
		pcall(function() on(UIS.WindowFocusReleased, onFocusLost) end)
		Janitor.add(function() InputSys.ReplayEnd() end)
	end
end

