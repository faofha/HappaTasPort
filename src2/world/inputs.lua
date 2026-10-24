-- ================================================================================================
--  INPUTS  (HappaTAS 3 world plugin, order 30): keyboard and mouse recording, and their replay through
--  the executor's input functions (V2.38.16 p10_inputs).
--  Key ids are part of the file format (A-Z = 1-26, 0-9 = 27-36, ... LMB 96, RMB 97): never reorder.
--  A frame's Input list holds events: id = pressed, -id = released, 10000 + n = n wheel notches.
--  Columns: Input (list), Mouse (MX, MY, UVX, UVY), Viewport (list { VX, VY }: only when it changed).
--  Keys bound to HappaTAS controls are never recorded or replayed. Nothing is recorded while the player
--  types or a click lands on a HappaTAS window.
--  Replay: Windows "extended" keys go through VirtualInputManager (Real's keypress sends them without the
--  extended flag: Up came out as KeypadEight...), the others through keypress; keys held while the Roblox
--  window wasn't active are pressed when it is again; the real mouse is aimed through a measured fit
--  (Real's mousemoveabs scales with integer maths) and each move is flushed with a 1 px step.
-- ================================================================================================
local Env = import("platform/env")
local Util = import("engine/util")
local Keys = import("engine/keys")
local Controls = import("engine/controls")

local floor, clamp = math.floor, Util.clamp
local Inputs = { name = "inputs", order = 30 }
Inputs.__index = Inputs

local SCROLL_BASE = 10000
local SCROLL_LIMIT = SCROLL_BASE - 5000
local SCROLL_UNIT = 120
Inputs.SCROLL_BASE = SCROLL_BASE

-- (V2.38.16's list: { KeyCode name, Windows virtual-key code, short name }; the index is the id)
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
Inputs.ID_M1, Inputs.ID_M2 = ID_M1, ID_M2

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
-- Windows "extended" keys: Real's keypress sends their scancode without the extended-key flag
local EXTENDED = { [0x21] = true, [0x22] = true, [0x23] = true, [0x24] = true, [0x25] = true, [0x26] = true,
	[0x27] = true, [0x28] = true, [0x2D] = true, [0x2E] = true, [0x6F] = true, [0xA3] = true, [0xA5] = true }
local MOUSE_BUTTON = { [Enum.UserInputType.MouseButton1] = true, [Enum.UserInputType.MouseButton2] = true,
	[Enum.UserInputType.MouseButton3] = true }
local function isMouseId(id) return id == ID_M1 or id == ID_M2 end

function Inputs.idOf(inp)
	local t = inp.UserInputType
	if t == Enum.UserInputType.Keyboard then return KEY_BY_ENUM[inp.KeyCode]
	elseif t == Enum.UserInputType.MouseButton1 then return ID_M1
	elseif t == Enum.UserInputType.MouseButton2 then return ID_M2 end
	return nil
end

local function newAxis() return { n = 0, st = 0, sr = 0, stt = 0, str = 0, lo = math.huge, hi = -math.huge, a = 1, b = 0, ok = false } end
local CAL_SPREAD = 150 -- px between the lowest and highest sample before the fit is used

function Inputs.new(E)
	local self = setmetatable({ E = E, held = {}, queue = {}, ownWindows = {}, mouseOverOwn = nil,
		onLive = nil, onReplay = nil, controlIds = nil, controlKey = nil, lastVX = nil, lastVY = nil,
		replay = { active = false, applied = 0, injected = {}, state = {}, recent = {}, lastMX = nil, lastMY = nil },
		cal = { x = newAxis(), y = newAxis(), vx = 0, vy = 0, pend = nil },
		uis = Env.svc("UserInputService"), gui = Env.svc("GuiService"), vim = Env.svc("VirtualInputManager") }, Inputs)
	self.available = {
		keys = Env.keypress ~= nil and Env.keyrelease ~= nil,
		clicks = Env.mouse1press ~= nil and Env.mouse1release ~= nil and Env.mouse2press ~= nil and Env.mouse2release ~= nil,
		move = Env.mousemoveabs ~= nil,
		scroll = Env.mousescroll ~= nil,
	}
	local tl = E.tl
	tl:addColumn("Input", "list", 1, { key = "Input", keep = function(v) return #v > 0 end })
	tl:addColumn("Mouse", "f64", 4, { keys = { "MX", "MY", "UVX", "UVY" }, keepOnChange = { 1, 2 } })
	tl:addColumn("Viewport", "list", 1, { keys = { "VX", "VY" } })
	return self
end

-- true when the Roblox window has focus (or the executor can't tell, or Window Guarding is off)
function Inputs:windowActive()
	if not self.E.settings:on("windowGuarding") or not Env.isactive then return true end
	local ok, a = pcall(Env.isactive)
	return (not ok) or a ~= false
end

-- the key ids of HappaTAS's own controls
function Inputs:getControlIds()
	local controls = self.E.controls
	local sig = {}
	for _, c in ipairs(Controls.LIST) do sig[#sig + 1] = controls:get(c.key) or "" end
	local key = table.concat(sig, "\0")
	if key ~= self.controlKey then
		self.controlKey = key
		local ids = {}
		for _, c in ipairs(Controls.LIST) do
			local item = Keys.toKey[controls:get(c.key) or ""]
			if item then
				if item == Enum.UserInputType.MouseButton1 then ids[ID_M1] = true
				elseif item == Enum.UserInputType.MouseButton2 then ids[ID_M2] = true
				elseif KEY_BY_ENUM[item] then ids[KEY_BY_ENUM[item]] = true end
			end
		end
		self.controlIds = ids
	end
	return self.controlIds
end

function Inputs:pushEvent(e)
	local q = self.queue
	q[#q + 1] = e
	if #q > 256 then table.remove(q, 1) end
end

-- the mouse is over a visible HappaTAS window (the interface sets ownWindows / mouseOverOwn)
function Inputs:overOwnUI()
	local okM, m = pcall(self.uis.GetMouseLocation, self.uis)
	if not okM then return false end
	local inset = Vector2.zero
	if self.gui then pcall(function() inset = self.gui:GetGuiInset() end) end
	for _, f in ipairs(self.ownWindows) do
		if f and f.Visible then
			local p, s = f.AbsolutePosition, f.AbsoluteSize
			local x, y = m.X - inset.X, m.Y - inset.Y
			if x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y then return true end
			x, y = m.X, m.Y
			if x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y then return true end
		end
	end
	return self.mouseOverOwn ~= nil and self.mouseOverOwn(m) or false
end

-- a mouse button pressed over a HappaTAS window is meant for that window, never a control
function Inputs:isOverOwnUI(inp)
	return MOUSE_BUTTON[inp.UserInputType] == true and self:overOwnUI()
end

function Inputs:start()
	local E, uis = self.E, self.uis
	E.life:connect(uis.InputBegan, function(inp, proc)
		if proc and not E.settings:on("ignoreGameProcessed") then return end
		local id = Inputs.idOf(inp)
		if not id or self:getControlIds()[id] or E.typing:active(inp) then return end
		if isMouseId(id) and self:overOwnUI() then return end
		if self.held[id] then return end
		self.held[id] = true
		self:pushEvent(id)
		-- a key / click the replay pressed itself comes back here like real input
		local t = self.replay.recent[id]
		if t then
			self.replay.recent[id] = nil
			if os.clock() - t < 0.5 then return end
		end
		if self.onLive then self.onLive(id, isMouseId(id), id == ID_M2) end
	end)
	E.life:connect(uis.InputEnded, function(inp)
		local id = Inputs.idOf(inp)
		if id and self.held[id] then
			self.held[id] = nil
			self:pushEvent(-id)
		end
	end)
	E.life:connect(uis.InputChanged, function(inp)
		if inp.UserInputType ~= Enum.UserInputType.MouseWheel then return end
		if E.typing:active(nil) or self:overOwnUI() then return end
		self:pushEvent(SCROLL_BASE + (inp.Position.Z > 0 and 1 or -1))
	end)
	pcall(function()
		E.life:connect(uis.WindowFocusReleased, function()
			for id in pairs(self.held) do self:pushEvent(-id) end
			self.held = {}
		end)
	end)
	E.life:own(function() self:replayEnd() end)
end

-- ------------------------------------------------------------------------------------------------ recording
function Inputs:take()
	if #self.queue == 0 then return nil end
	local q = self.queue
	self.queue = {}
	return q
end

function Inputs:clear()
	if #self.queue > 0 then self.queue = {} end
end

-- mouse position in window pixels + the same position normalised to the viewport (0..1)
function Inputs:mouse()
	local v = self.uis:GetMouseLocation()
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
	local mx, my = floor(v.X + 0.5), floor(v.Y + 0.5)
	local vx, vy = vp.X, vp.Y
	local uvx = vx > 0 and clamp(mx / vx, 0, 1) or 0.5
	local uvy = vy > 0 and clamp(my / vy, 0, 1) or 0.5
	return mx, my, uvx, uvy, vx, vy
end

function Inputs:begin(tl, i)
	local mx, my, uvx, uvy, vx, vy = self:mouse()
	tl:setList("Input", i, self:take())
	tl:setN("Mouse", i, mx, my, uvx, uvy)
	if i == 1 or vx ~= self.lastVX or vy ~= self.lastVY then
		self.lastVX, self.lastVY = vx, vy
		tl:setList("Viewport", i, { vx, vy })
	end
end

-- the keys held at frame upTo (base: held before frame 1)
function Inputs:heldAt(tl, upTo, base)
	local set = {}
	if base then for id in pairs(base) do set[id] = true end end
	for i = 1, math.min(upTo, tl:count()) do
		local ev = tl:getList("Input", i)
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

-- unpausing: the recording starts with the keys that go up / down compared to the frame resumed from
function Inputs:beginRecording(tl, base)
	self.lastVX, self.lastVY = nil, nil
	self.queue = {}
	local want = self:heldAt(tl, tl:count(), base)
	local ids = {}
	for id in pairs(want) do if not self.held[id] then ids[#ids + 1] = -id end end
	for id in pairs(self.held) do if not want[id] then ids[#ids + 1] = id end end
	table.sort(ids, function(a, b) return math.abs(a) < math.abs(b) end)
	for _, e in ipairs(ids) do self.queue[#self.queue + 1] = e end
end

function Inputs:describe(set)
	if not set or next(set) == nil then return "-" end
	local ids = {}
	for id in pairs(set) do ids[#ids + 1] = id end
	table.sort(ids)
	local names = {}
	for i, id in ipairs(ids) do names[i] = KEY_SHORT[id] or "?" end
	return table.concat(names, " ")
end

-- ------------------------------------------------------------------------------------------------ replay
function Inputs:allowed(id)
	if self:getControlIds()[id] then return false end
	local s = self.E.settings
	if isMouseId(id) then return self.available.clicks and s:on("replayMouseClicks") end
	return self.available.keys and s:on("replayKeyboard") and KEY_VK[id] ~= nil
end

-- an extended key through VirtualInputManager (false: not one, or no VirtualInputManager)
function Inputs:vimKey(id, down)
	local vim, kc = self.vim, KEY_KC[id]
	if not (vim and kc and EXTENDED[KEY_VK[id]]) then return false end
	return (pcall(vim.SendKeyEvent, vim, down, kc, false, game))
end
function Inputs:sendDown(id)
	return (pcall(function()
		if id == ID_M1 then Env.mouse1press() elseif id == ID_M2 then Env.mouse2press()
		elseif not self:vimKey(id, true) then Env.keypress(KEY_VK[id]) end
	end))
end
function Inputs:sendUp(id)
	pcall(function()
		if id == ID_M1 then Env.mouse1release() elseif id == ID_M2 then Env.mouse2release()
		elseif not self:vimKey(id, false) then Env.keyrelease(KEY_VK[id]) end
	end)
end

function Inputs:press(id)
	local rp = self.replay
	rp.state[id] = true
	if rp.injected[id] or not self:allowed(id) or not self:windowActive() then return end
	if self:sendDown(id) then
		rp.injected[id] = true
		rp.recent[id] = os.clock()
	end
end
function Inputs:release(id)
	local rp = self.replay
	rp.state[id] = nil
	if rp.injected[id] then
		self:sendUp(id)
		rp.injected[id] = nil
	end
end

function Inputs:applyEvent(e)
	if e >= SCROLL_LIMIT then
		local notches = e - SCROLL_BASE
		if notches ~= 0 and self.available.scroll and self.E.settings:on("replayMouseClicks") and self:windowActive() then
			pcall(Env.mousescroll, notches * SCROLL_UNIT)
		end
	elseif e > 0 then
		self:press(e)
		if self.onReplay then self.onReplay(e, isMouseId(e), e == ID_M2) end
	else
		self:release(-e)
	end
end

function Inputs:syncTo(desired)
	local rp = self.replay
	for id in pairs(rp.injected) do
		if not desired[id] then self:release(id) end
	end
	for id in pairs(rp.state) do
		if not desired[id] then rp.state[id] = nil end
	end
	for id in pairs(desired) do
		if not rp.state[id] or not rp.injected[id] then self:press(id) end
	end
end

function Inputs:isReplaying() return self.replay.active end

function Inputs:replayBegin(tl, startFrame)
	self:replayEnd()
	self.replay.active = true
	self.replay.applied = startFrame - 1
	self:syncTo(self:heldAt(tl, startFrame - 1))
end

function Inputs:replayTo(tl, frame)
	local rp = self.replay
	if not rp.active then return end
	if frame > rp.applied then
		for f = rp.applied + 1, math.min(frame, tl:count()) do
			local ev = tl:getList("Input", f)
			if ev then
				for k = 1, #ev do self:applyEvent(ev[k]) end
			end
		end
	elseif frame < rp.applied then
		self:syncTo(self:heldAt(tl, frame))
	end
	rp.applied = frame
	-- keys held while the Roblox window wasn't active (the input functions send nothing then): pressed as
	-- soon as it is active again
	if next(rp.state) ~= nil and self:windowActive() then
		for id in pairs(rp.state) do
			if not rp.injected[id] then self:press(id) end
		end
	end
end

-- true when the camera had the mouse locked on this frame (shift lock, first person, right button held)
function Inputs:frameLocked(tl, i)
	if tl:get("ShiftLock", i, 1) == 1 then return true end
	if tl:get("Zoom", i, 1) <= 0.55 then return true end
	return self.replay.state[ID_M2] == true
end

-- where the recorded cursor was, mapped to this window
function Inputs:framePoint(tl, i)
	local mx, my, uvx, uvy = tl:getN("Mouse", i)
	if self.E.settings:on("normalizeMouseUV") then
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1920, 1080)
		return floor(uvx * vp.X + 0.5), floor(uvy * vp.Y + 0.5)
	end
	return mx, my
end

-- ------------------------------------------------------------------------------------------------ real mouse
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
local function calAim(ax, v)
	if not ax.ok then return v end
	return floor((v - ax.b) / ax.a + 0.5)
end

function Inputs:calRead()
	local cal = self.cal
	local p = cal.pend
	if not p then return end
	cal.pend = nil
	if os.clock() - p[3] > 0.25 or self.uis.MouseBehavior ~= Enum.MouseBehavior.Default then return end
	local okM, m = pcall(self.uis.GetMouseLocation, self.uis)
	if not okM then return end
	calAdd(cal.x, p[1], m.X, p[4])
	calAdd(cal.y, p[2], m.Y, p[5])
end

function Inputs:calibration()
	local cal = self.cal
	return { x = { a = cal.x.a, b = cal.x.b, ok = cal.x.ok, n = cal.x.n }, y = { a = cal.y.a, b = cal.y.b, ok = cal.y.ok, n = cal.y.n } }
end

function Inputs:moveRealMouse(x, y)
	if not self.available.move or not self:windowActive() then return end
	local cal, rp = self.cal, self.replay
	local cam = workspace.CurrentCamera
	local vp = cam and cam.ViewportSize
	if vp and (vp.X ~= cal.vx or vp.Y ~= cal.vy) then -- window resized: measure again
		cal.x, cal.y, cal.vx, cal.vy, cal.pend, cal.sentX, cal.sentY = newAxis(), newAxis(), vp.X, vp.Y, nil, nil, nil
	end
	self:calRead()
	x, y = floor(x + 0.5), floor(y + 0.5)
	if x == rp.lastMX and y == rp.lastMY then return end
	rp.lastMX, rp.lastMY = x, y
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

function Inputs:replayMouse(tl, i)
	if not self.replay.active or i < 1 or i > tl:count() then return end
	if not self.E.settings:on("replayMouseMovement") then return end
	if self:frameLocked(tl, i) then return end -- the cursor module moves the hidden cursor then
	local tx, ty = self:framePoint(tl, i)
	if tx then self:moveRealMouse(tx, ty) end
end

function Inputs:replayEnd()
	local rp, cal = self.replay, self.cal
	local had = rp.active
	for id in pairs(rp.injected) do self:sendUp(id) end
	rp.injected = {}
	rp.state = {}
	rp.active = false
	rp.applied = 0
	rp.lastMX, rp.lastMY = nil, nil
	cal.pend, cal.sentX, cal.sentY = nil, nil, nil
	return had
end

return Inputs
