-- ================================================================================================
--  COMPACT CONTROLS  (HappaTAS 3 ui, V3.1): the Compact interface's CONTROLS page, two columns:
--  left RUN (mode, frame / count, time, the file saved or loaded last; Idle / Create / Test) and SPEED HACK (its
--  switch and speed), right KEYS (the Controls window's list, hosted by ui/compact/compact) and TOOLS
--  (MicroProfiler, Unload HappaTAS). The title bar's status chip says the mode, and paused / recording.
--  Values are written 10 times a second, and only when they change, by one handler that runs only while
--  Compact is live (pipeline "ui.compact"). Sections and rows have fixed places and heights (no list layouts:
--  the page reads the same in every client and in the headless tests).
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Parts = import("ui/compact/parts")
local CK = import("ui/compact/kit")
local Env = import("platform/env")
local Util = import("engine/util")
local TKeys = import("ui/compact/keys")

local Controls = {}
Controls.__index = Controls

local EVERY = 0.1
local MODE = { "Idle", "Create", "Test" }
local GAP, TOP, ROW = 7, 26, 21 -- (between sections; a section's first row; a row's pitch)
-- section heights: title + rows + padding
local H = { run = TOP + 4 * ROW + 24 + 8, speed = TOP + 2 * 31 + 4, keys = TOP + TKeys.height() + 8, tools = TOP + 24 + 8 }

local function column(parent, x)
	local f = K.frame(x == 0 and "Left" or "Right", parent)
	f.Position = UDim2.new(x, x == 0 and 0 or 5, 0, 0)
	f.Size = UDim2.new(0.5, -5, 0, H.run + H.speed + GAP)
	return f
end

-- a section at a fixed place and height; its body's list layout gives way to fixed rows
local function fix(sec, y, h)
	sec.gui.AutomaticSize = Enum.AutomaticSize.None
	sec.gui.Position = UDim2.new(0, 0, 0, y)
	sec.gui.Size = UDim2.new(1, 0, 0, h)
	sec.body.AutomaticSize = Enum.AutomaticSize.None
	sec.body.Size = UDim2.new(1, 0, 1, -22)
	for _, ch in ipairs(sec.body:GetChildren()) do
		if ch:IsA("UIListLayout") or ch:IsA("UIPadding") then ch:Destroy() end
	end
end

function Controls.build(cp)
	local ui = cp.ui
	local ctx = cp:clippedCtx(cp.pages.controls) -- (rows scrolled out of view take no click)
	local E = ui.E
	local self = setmetatable({ cp = cp, ui = ui, E = E, values = {}, buttons = {}, labels = {}, last = {}, t = 0, file = "-" }, Controls)
	local page = cp.pages.controls
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 6), UDim.new(0, 6), UDim.new(0, 8)
	pad.Parent = page
	self.left, self.right = column(page, 0), column(page, 0.5)
	local function section(col, title, y, h)
		local s = CK.section(ctx, col, title)
		fix(s, y, h)
		cp.pieces[#cp.pieces + 1] = s
		return s
	end
	-- RUN
	self.run = section(self.left, "run", 0, H.run)
	local function row(key, name, order)
		local f = K.frame("Row_" .. key, self.run.body)
		f.Size = UDim2.new(1, -16, 0, 16)
		f.Position = UDim2.new(0, 8, 0, 4 + (order - 1) * ROW)
		local l = K.text("TextLabel", "Name", f)
		l.Text = name
		l.Size = UDim2.new(0.4, 0, 1, 0)
		l.TextXAlignment = Enum.TextXAlignment.Left
		local v = K.text("TextLabel", "Value", f)
		v.Position = UDim2.new(0.4, 0, 0, 0)
		v.Size = UDim2.new(0.6, 0, 1, 0)
		v.TextXAlignment = Enum.TextXAlignment.Right
		v.TextTruncate = Enum.TextTruncate.AtEnd
		self.labels[#self.labels + 1] = l
		self.values[key] = v
	end
	row("mode", "Mode", 1)
	row("frame", "Frame", 2)
	row("time", "Time", 3)
	row("file", "File", 4)
	local brow = K.frame("Buttons", self.run.body)
	brow.Size = UDim2.new(1, -16, 0, 24)
	brow.Position = UDim2.new(0, 8, 0, 4 + 4 * ROW)
	local function button(key, text, parent, x, w, onClick)
		local b = Parts.button(ctx, parent, text, { onClick = onClick })
		b.gui.Position = UDim2.new(x, x > 0 and 2 or 0, 0, 0)
		b.gui.Size = UDim2.new(w and 0 or 0.333, w or -3, 0, 22)
		self.buttons[key] = b
		cp.pieces[#cp.pieces + 1] = b
		return b
	end
	local function request(what) E.modes:request(what) end
	button("idle", "Idle", brow, 0, nil, function() request("idle") end)
	button("create", "Create", brow, 0.333, nil, function() request("create") end)
	button("test", "Test", brow, 0.666, nil, function() if E.tl:count() > 0 then request("test") end end)
	-- SPEED HACK
	self.speed = section(self.left, "speed hack", H.run + GAP, H.speed)
	local s = E.settings
	local tog = Parts.checkbox(ctx, self.speed.body, "Speed Hack", { onChange = function(on) s:set("speedHack", on and 1 or 0) end })
	tog.gui.Size = UDim2.new(1, -16, 0, 18)
	tog.gui.Position = UDim2.new(0, 8, 0, 6)
	tog:set(s:on("speedHack"))
	self.speedToggle = tog
	cp.pieces[#cp.pieces + 1] = tog
	local sr = K.frame("Row_speedHackSpeed", self.speed.body)
	sr.Size = UDim2.new(1, -16, 0, 26)
	sr.Position = UDim2.new(0, 8, 0, 35)
	local sl = K.text("TextLabel", "Name", sr)
	sl.Text = "Speed"
	sl.Size = UDim2.new(0.3, 0, 1, 0)
	sl.TextXAlignment = Enum.TextXAlignment.Left
	self.labels[#self.labels + 1] = sl
	local slider = Parts.slider(ctx, sr, { min = 0.1, max = 1, fmt = function(v) return string.format("%.2fx", v) end,
		onChange = function(x) s:set("speedHackSpeed", math.floor(x * 100 + 0.5) / 100) end })
	slider.gui.AnchorPoint = Vector2.new(1, 0.5)
	slider.gui.Position = UDim2.new(1, 0, 0.5, 0)
	slider.gui.Size = UDim2.new(0.7, 0, 0, 22)
	slider:set(s:get("speedHackSpeed"))
	self.speedSlider = slider
	cp.pieces[#cp.pieces + 1] = slider
	cp.offs[#cp.offs + 1] = s:changed("speedHack", function(v) tog:set(v == 1) end)
	cp.offs[#cp.offs + 1] = s:changed("speedHackSpeed", function(v) slider:set(v) end)
	-- KEYS (hosted by the compact window) and TOOLS
	cp.keysSection.gui.Parent = self.right
	fix(cp.keysSection, 0, H.keys)
	cp.keysFrame.Position = UDim2.new(0, 4, 0, 2)
	cp.keysFrame.Size = UDim2.new(1, -16, 0, TKeys.height())
	cp.keysFrame.Position = UDim2.new(0, 8, 0, 4)
	self.right.Size = UDim2.new(0.5, -5, 0, H.keys + GAP + H.tools)
	self.tools = section(self.right, "tools", H.keys + GAP, H.tools)
	local trow = K.frame("Buttons", self.tools.body)
	trow.Size = UDim2.new(1, -16, 0, 24)
	trow.Position = UDim2.new(0, 8, 0, 4)
	button("profiler", "MicroProfiler", trow, 0, nil, function()
		s:set("showMicroProfiler", s:on("showMicroProfiler") and 0 or 1)
	end)
	self.buttons.profiler.gui.Size = UDim2.new(0.5, -2, 0, 22)
	button("unload", "Unload HappaTAS", trow, 0.5, nil, function()
		local h = Env.genv.__HappaTAS3
		if h and h.Unload then task.spawn(h.Unload) end
	end)
	self.buttons.unload.gui.Size = UDim2.new(0.5, -2, 0, 22)
	-- (the file shown: the last one saved or loaded)
	cp.offs[#cp.offs + 1] = E.bus:on("persist", function(ev)
		if ev and ev.ok and (ev.op == "save" or ev.op == "load") and ev.path then
			self.file = (tostring(ev.path):match("([^/]+)$") or tostring(ev.path)):gsub("%.[^%.]+$", "")
		end
	end)
	local function paint()
		local th = ui.theme
		for _, l in ipairs(self.labels) do
			W.set(l, "FontFace", th.font("text"))
			W.set(l, "TextSize", th.size(11))
			W.set(l, "TextColor3", th.c.text2)
		end
		for _, v in pairs(self.values) do
			W.set(v, "FontFace", th.font("number"))
			W.set(v, "TextSize", th.size(11))
			W.set(v, "TextColor3", th.c.text)
		end
		self.last = {}
		self:update()
	end
	cp.offs[#cp.offs + 1] = ui.theme:changed(paint)
	cp.offs[#cp.offs + 1] = E.state:watch("mode", function() self:update() end)
	paint()
	cp.offs[#cp.offs + 1] = function() self:follow(false) end
	return self
end

-- the handler runs only while Compact is live
function Controls:follow(on)
	if on and not self.off then
		self.off = self.E.pipe:add("PreRender", 240, "ui.compact", function(dt) self:step(dt) end, "ui")
		self:update()
	elseif not on and self.off then
		self.off()
		self.off = nil
	end
end

function Controls:step(dt)
	self.t = self.t + (dt or 0)
	if self.t < EVERY then return end
	self.t = 0
	self:update()
end

local function put(self, gui, prop, v)
	local key = tostring(gui) .. prop
	if self.last[key] == v then return end
	self.last[key] = v
	W.set(gui, prop, v)
end

-- the RUN values and the status chip, written only when they change
function Controls:update()
	local E = self.E
	local tl = E.tl
	local n = tl and tl:count() or 0
	local f = math.clamp(E.frame or 0, n > 0 and 1 or 0, n)
	put(self, self.values.mode, "Text", MODE[E.mode] or "Idle")
	put(self, self.values.frame, "Text", string.format("%d / %d", f, n))
	put(self, self.values.time, "Text", n > 0 and Util.toTime(tl:get("TotalTime", math.max(1, f), 1)) or "0:00.000")
	put(self, self.values.file, "Text", self.file)
	local status, rec = MODE[E.mode] or "Idle", false
	if E.mode == 2 then
		rec = not E.paused
		status = "Create - " .. (rec and "recording" or "paused")
	end
	local chip = self.cp.status
	put(self, chip.label, "Text", status)
	local th = self.ui.theme
	local color = rec and th.c.rec or nil
	if self.lastColor ~= (color or false) then
		self.lastColor = color or false
		chip:setColor(color)
	end
end

return Controls
