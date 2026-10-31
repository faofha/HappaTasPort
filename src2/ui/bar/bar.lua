-- ================================================================================================
--  TIMELINE BAR  (HappaTAS 3 ui, spec 8.2): a thin glass bar at the bottom centre (76 above the bottom
--  edge, clear of Roblox's hotbar). Left: the mode and the speed; then the transport (start, step back,
--  record / pause, step forward, Test, marker); the track with its time ruler, markers and playhead (press
--  or drag to seek while paused, scrub in Test, wheel to zoom); right: the unsaved dot, frame / count and
--  the time, and the lanes button (ui/bar/lanes). A 10-high strip in Idle with no run.
--  Every transition goes through E.modes:request. Per-frame work only outside Idle (a handler added when
--  the mode leaves Idle); in Idle it follows the run through the plugin hooks and the state store. The
--  ruler and marks are redrawn when the model, the view or the width changed (every 60th frame at
--  most while recording; the rest every 2nd frame while recording or testing); everything else is written only when its value changes (W.set). The pools are fixed:
--  41 ticks, 11 labels, 120 marks.
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Glass = import("ui/kit/glass")
local Icon = import("ui/kit/icon")
local Util = import("engine/util")
local BarModel = import("ui/bar/model")

local Bar = {}
Bar.__index = Bar

local Z, ZINDEX = 40000000, 450000
local H, STRIP, BOTTOM, MAXW = 40, 10, 76, 900
local TICKS, LABELS, MARKS = 41, 11, 120
-- (while recording or testing the bar is written every 2nd frame, as V2 wrote its stats panels, and the ruler
-- redrawn every 60th: within V2's writes per frame in the bench)
local BTN, EVERY, REDRAW_EVERY, MIN_FRAMES = 24, 2, 60, 10
local STEPS = { 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000, 200000, 500000 }
local TRANSPORT = { { "start", "start" }, { "back1", "back1" }, { "rec", "record" }, { "forward1", "forward1" },
	{ "test", "play" }, { "marker", "marker" } }

local function shortTime(t)
	t = t or 0
	return string.format("%d:%04.1f", math.floor(t / 60), t % 60)
end

function Bar.new(ui)
	local E = ui.E
	local self = setmetatable({ ui = ui, E = E, rects = {}, offs = {}, buttons = {}, view = { first = 1, last = 1 },
		whole = true, tick = 0, ticks = {}, labels = {}, marks = {}, drawn = {}, trackW = 1 }, Bar)
	self.model = BarModel.new(E)
	self.ctx = { E = E, ui = ui, theme = ui.theme, tween = ui.tween, typing = E.typing,
		pointer = {
			add = function(r, z)
				r.z = Z + (z or 0)
				r.group = r.group or self.gui
				self.rects[#self.rects + 1] = r
				ui.pointer:add(r)
				return r
			end,
			remove = function(r) ui.pointer:remove(r) end,
		} }
	local gui = K.frame("TimelineBar", ui.root.layer)
	gui.AnchorPoint = Vector2.new(0.5, 1)
	gui.ZIndex = ZINDEX
	self.gui = gui
	self.glass = Glass.panel(ui.theme, gui, { cornerKind = "control" })
	self.ctx.pointer.add({ gui = self.glass.panel }, 0) -- (a press on the bar is the bar's)
	local body = K.frame("Body", self.glass.panel)
	body.Size = UDim2.new(1, 0, 1, 0)
	body.ZIndex = 2
	self.body = body
	self:build()
	self.offs[#self.offs + 1] = ui.theme:changed(function() self:place(); self:restyle(); self:refresh(true) end)
	self.offs[#self.offs + 1] = ui.wm:screenChanged(function() self:place(); self:refresh(true) end)
	self.offs[#self.offs + 1] = E.state:watch("mode", function() self:follow(); self:refresh(true) end)
	self.offs[#self.offs + 1] = E.state:watch("frame", function() if E.mode == 1 then self:refresh(true) end end)
	self.offs[#self.offs + 1] = E.bus:on("persist", function() self:refresh(true) end)
	for _, key in ipairs({ "speedHack", "speedHackSpeed", "playbackSpeed" }) do
		self.offs[#self.offs + 1] = E.settings:changed(key, function() self:refresh(true) end)
	end
	-- (the engine tells plugins when the run changed: a load, a merge, Delete TAS; the bar listens the same way)
	local function changed() self.whole = true; self.model:sync(); self:refresh(true) end
	E.plugins:add({ name = "ui.bar", order = 990, onDataChanged = changed, onLoaded = changed })
	self.offs[#self.offs + 1] = function() E.plugins:remove("ui.bar") end
	ui.life:own(function() self:destroy() end)
	self:place()
	self:restyle()
	self:follow()
	self.model:sync()
	self:refresh(true)
	return self
end

-- ------------------------------------------------------------------------------------------------ building
function Bar:iconButton(name, kind)
	local b = { name = name, enabled = true }
	local gui = K.frame("Button_" .. name, self.body, Color3.new(1, 1, 1))
	gui.Size = UDim2.new(0, BTN, 0, BTN)
	gui.AnchorPoint = Vector2.new(0, 0.5)
	gui.BackgroundTransparency = 0.88
	gui.ZIndex = 3
	K.corner(gui, 999)
	b.gui = gui
	b.icon = Icon.new(self.ctx, gui, kind, 11)
	b.icon.gui.AnchorPoint = Vector2.new(0.5, 0.5)
	b.icon.gui.Position = UDim2.new(0.5, 0, 0.5, 0)
	b.icon.gui.ZIndex = 4
	self.ctx.pointer.add({ gui = gui, onRelease = function(_, clicked) if clicked then self:press(name) end end }, 3)
	self.buttons[name] = b
	return b
end

function Bar:setEnabled(b, on)
	b.enabled = on
	W.set(b.gui, "BackgroundTransparency", on and 0.88 or 0.95)
	for _, p in ipairs(b.icon.parts) do
		if p:IsA("TextLabel") then W.set(p, "TextTransparency", on and 0 or 0.6)
		else W.set(p, "BackgroundTransparency", on and 0 or 0.6) end
	end
end

function Bar:build()
	local body = self.body
	self.modeIcon = Icon.new(self.ctx, body, "pause", 10)
	self.modeIcon.gui.AnchorPoint = Vector2.new(0, 0.5)
	self.modeLabel = K.text("TextLabel", "Mode", body)
	self.modeLabel.TextXAlignment = Enum.TextXAlignment.Left
	self.speedLabel = K.text("TextLabel", "Speed", body)
	self.speedLabel.TextXAlignment = Enum.TextXAlignment.Left
	self.speedLabel.Text = ""
	for _, t in ipairs(TRANSPORT) do self:iconButton(t[1], t[2]) end
	self:iconButton("lanes", "chevron")
	self.readout = K.text("TextLabel", "Readout", body)
	self.readout.TextXAlignment = Enum.TextXAlignment.Right
	self.unsaved = K.frame("Unsaved", body, Color3.new(1, 1, 1))
	self.unsaved.AnchorPoint = Vector2.new(0, 0.5)
	self.unsaved.Size = UDim2.new(0, 6, 0, 6)
	K.corner(self.unsaved, 999)
	self.unsaved.Visible = false
	local track = K.frame("Track", body)
	track.ZIndex = 3
	self.track = track
	local line = K.frame("Line", track, Color3.new(1, 1, 1))
	line.Position = UDim2.new(0, 0, 0, 25)
	line.Size = UDim2.new(1, 0, 0, 3)
	K.corner(line, 2)
	self.line = line
	for i = 1, TICKS do
		local t = K.frame("Tick", track, Color3.new(1, 1, 1))
		t.Size = UDim2.new(0, 1, 0, 4)
		t.Visible = false
		self.ticks[i] = t
	end
	for i = 1, LABELS do
		local l = K.text("TextLabel", "Label", track)
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.Size = UDim2.new(0, 48, 0, 10)
		l.Position = UDim2.new(0, 0, 0, 2)
		l.Visible = false
		self.labels[i] = l
	end
	for i = 1, MARKS do
		local m = K.frame("Mark", track, Color3.new(1, 1, 1))
		m.AnchorPoint = Vector2.new(0.5, 0.5)
		m.Size = UDim2.new(0, 6, 0, 6)
		m.Position = UDim2.new(0, 0, 0, 26)
		m.Rotation = 45
		m.Visible = false
		self.marks[i] = m
	end
	local ph = K.frame("Playhead", track, Color3.new(1, 1, 1))
	ph.AnchorPoint = Vector2.new(0.5, 0)
	ph.Position = UDim2.new(0, 0, 0, 4)
	ph.Size = UDim2.new(0, 2, 0, 32)
	ph.ZIndex = 4
	self.playhead = ph
	local ui = self.ui
	self.ctx.pointer.add({ gui = track,
		onPress = function(pos) self:seekAt(pos.X) end,
		onDrag = function(pos) self:seekAt(pos.X) end,
		onWheel = function(dz) self:zoom(dz, ui.pointer.pos.X) end }, 2)
end

-- place and size (layer units): bottom centre, every part's spot in the bar
function Bar:place()
	local sw, sh = self.ui.wm:screen()
	local w = math.min(MAXW, math.floor(sw * 0.7))
	local strip = self.E.mode == 1 and self.E.tl:count() == 0
	self.strip = strip
	W.set(self.gui, "Position", UDim2.new(0, sw / 2, 0, sh - BOTTOM))
	W.set(self.gui, "Size", UDim2.new(0, w, 0, strip and STRIP or H))
	W.set(self.body, "Visible", not strip)
	W.set(self.modeIcon.gui, "Position", UDim2.new(0, 14, 0.5, 0))
	W.set(self.modeLabel, "Position", UDim2.new(0, 30, 0, 0))
	W.set(self.modeLabel, "Size", UDim2.new(0, 64, 1, 0))
	W.set(self.speedLabel, "Position", UDim2.new(0, 96, 0, 0))
	W.set(self.speedLabel, "Size", UDim2.new(0, 36, 1, 0))
	local x = 136
	for _, t in ipairs(TRANSPORT) do
		W.set(self.buttons[t[1]].gui, "Position", UDim2.new(0, x, 0.5, 0))
		x = x + BTN + 2
	end
	local lanesX = w - 12 - BTN
	W.set(self.buttons.lanes.gui, "Position", UDim2.new(0, lanesX, 0.5, 0))
	local readoutX = lanesX - 8 - 150
	W.set(self.readout, "Position", UDim2.new(0, readoutX, 0, 0))
	W.set(self.readout, "Size", UDim2.new(0, 150, 1, 0))
	local dotX = readoutX - 10
	W.set(self.unsaved, "Position", UDim2.new(0, dotX, 0.5, 0))
	local tx = x + 10
	local tw = math.max(40, dotX - 12 - tx)
	W.set(self.track, "Position", UDim2.new(0, tx, 0, 0))
	W.set(self.track, "Size", UDim2.new(0, tw, 1, 0))
	self.trackW = tw
end

function Bar:restyle()
	local th = self.ui.theme
	W.set(self.modeLabel, "FontFace", th.font("bold"))
	W.set(self.modeLabel, "TextSize", th.size(11.5))
	W.set(self.modeLabel, "TextColor3", th.c.text)
	W.set(self.speedLabel, "FontFace", th.font("number"))
	W.set(self.speedLabel, "TextSize", th.size(11))
	W.set(self.speedLabel, "TextColor3", th.c.text2)
	W.set(self.readout, "FontFace", th.font("number"))
	W.set(self.readout, "TextSize", th.size(11.5))
	W.set(self.readout, "TextColor3", th.c.text)
	W.set(self.unsaved, "BackgroundColor3", th.c.reset1)
	W.set(self.line, "BackgroundColor3", th.c.text2)
	W.set(self.line, "BackgroundTransparency", 0.6)
	W.set(self.playhead, "BackgroundColor3", th.c.accent)
	for _, t in ipairs(self.ticks) do
		W.set(t, "BackgroundColor3", th.c.text2)
		W.set(t, "BackgroundTransparency", 0.3)
	end
	for _, l in ipairs(self.labels) do
		W.set(l, "FontFace", th.font("number"))
		W.set(l, "TextSize", th.size(9))
		W.set(l, "TextColor3", th.c.text2)
	end
	for _, m in ipairs(self.marks) do W.set(m, "BackgroundColor3", th.c.reset1) end
end

-- ------------------------------------------------------------------------------------------------ mapping
-- x (layer units, inside the track) of frame f in the view
function Bar:xOf(f)
	local v = self.view
	local span = math.max(1, v.last - v.first)
	return (f - v.first) / span * self.trackW
end

-- the frame at x (GUI space, a pointer's X), clamped to 1..count
function Bar:frameAt(px)
	local n = self.E.tl:count()
	local a = self.track.AbsolutePosition.X
	local scale = self.ui.root.scale.Scale
	local v = self.view
	local span = math.max(1, v.last - v.first)
	local f = v.first + (px - a) / scale / self.trackW * span
	return math.clamp(math.floor(f + 0.5), 1, math.max(1, n))
end

function Bar:seekAt(px)
	local E = self.E
	if not E.modes:allowed("seek") then return end
	local f = self:frameAt(px)
	-- (Test plays from a frame with one after it: Modes:seek's rule)
	if E.mode == 3 then f = math.min(f, math.max(1, E.tl:count() - 1)) end
	if f ~= E.frame then E.modes:request("seek", { frame = f }) end
	self:refresh(true)
end

-- the wheel: ×0.8 (in) / ×1.25 (out) around the frame under the pointer, never fewer than 10 frames
function Bar:zoom(dz, px)
	local n = self.E.tl:count()
	if n < 2 or dz == 0 then return end
	local v = self.view
	local span = math.max(1, v.last - v.first)
	local scale = self.ui.root.scale.Scale
	local fp = v.first + (px - self.track.AbsolutePosition.X) / scale / self.trackW * span
	local newSpan = (dz > 0) and span * 0.8 or span * 1.25
	newSpan = math.clamp(newSpan, math.min(MIN_FRAMES - 1, n - 1), n - 1)
	local rel = (fp - v.first) / span
	local first = fp - rel * newSpan
	first = math.clamp(first, 1, n - newSpan)
	if first <= 1 and first + newSpan >= n then
		self.whole, v.first, v.last = true, 1, n
	else
		self.whole, v.first, v.last = false, first, first + newSpan
	end
	self:refresh(true)
end

-- ------------------------------------------------------------------------------------------------ actions
function Bar:press(name)
	local E = self.E
	local m = E.modes
	local b = self.buttons[name]
	if b and not b.enabled then return end
	if name == "start" then m:request("seek", { frame = 1 })
	elseif name == "back1" or name == "forward1" then m:request(name)
	elseif name == "rec" then
		if E.mode ~= 2 then m:request("create") elseif E.paused then m:request("unpause") else m:request("pause") end
	elseif name == "test" then
		if E.mode == 3 then m:request("create") else m:request("test") end
	elseif name == "marker" then self.model:toggleMarker(math.clamp(E.frame, 1, math.max(1, E.tl:count())))
	elseif name == "lanes" then
		if self.lanes then self.lanes:toggle() end
	end
	self:refresh(true)
end

local function allowedNow(self, name)
	local E = self.E
	local m = E.modes
	local n = E.tl:count()
	if name == "start" then return n > 0 and m:allowed("seek") end
	if name == "back1" or name == "forward1" then return m:allowed(name) end
	if name == "rec" then
		if E.mode ~= 2 then return m:allowed("create") end
		return m:allowed(E.paused and "unpause" or "pause")
	end
	if name == "test" then return m:allowed(E.mode == 3 and "create" or "test") end
	if name == "marker" then return n > 0 and E.mode ~= 1 end
	return true
end

-- ------------------------------------------------------------------------------------------------ per frame
-- the per-frame handler only outside Idle
function Bar:follow()
	local E = self.E
	if E.mode ~= 1 then
		if not self.off then self.off = E.pipe:add("PreRender", 220, "ui.bar", function() self:step() end, "ui") end
	elseif self.off then
		self.off()
		self.off = nil
	end
end

function Bar:step()
	self.model:sync()
	self:refresh(false)
end

local MODE_ICON = { Recording = "record", Paused = "pause", Test = "play" }

function Bar:refresh(force)
	local E = self.E
	local tl = E.tl
	local n = tl:count()
	local running = E.mode == 3 or (E.mode == 2 and not E.paused)
	if not force and running then
		self.tick = self.tick + 1
		if self.tick % EVERY ~= 0 then return end
	end
	if (E.mode == 1 and n == 0) ~= self.strip then
		self:place()
		force = true
	end
	local v = self.view
	if self.whole or v.last > n then
		self.whole, v.first, v.last = true, 1, math.max(1, n)
	end
	local f = math.clamp(E.frame or 1, 1, math.max(1, n))
	if n == 0 then
		W.paint(self.readout, "Text", "0 / 0")
	elseif f ~= self.lastF or n ~= self.lastN or force then
		W.paint(self.readout, "Text", string.format("%d / %d   %s", f, n, Util.toTime(tl:get("TotalTime", f, 1))))
	end
	self.lastF, self.lastN = f, n
	W.paint(self.playhead, "Visible", n > 0)
	W.paint(self.playhead, "Position", UDim2.new(0, self:xOf(f), 0, 4))
	local mode = (E.mode == 1 and "Idle") or (E.mode == 3 and "Test") or (E.paused and "Paused" or "Recording")
	if mode ~= self.modeName then
		self.modeName = mode
		W.paint(self.modeLabel, "Text", mode)
		W.paint(self.modeIcon.gui, "Visible", MODE_ICON[mode] ~= nil)
		if MODE_ICON[mode] then self.modeIcon:setKind(MODE_ICON[mode]) end
	end
	local s = E.settings
	local sp = ""
	if E.mode == 2 and s:on("speedHack") then sp = string.format("%gx", s:get("speedHackSpeed"))
	elseif E.mode == 3 and s:get("playbackSpeed") ~= 1 then sp = string.format("%gx", s:get("playbackSpeed")) end
	W.paint(self.speedLabel, "Text", sp)
	W.paint(self.unsaved, "Visible", E.persist ~= nil and E.persist:dirty())
	for name, b in pairs(self.buttons) do
		local on = allowedNow(self, name)
		if on ~= b.enabled or force then self:setEnabled(b, on) end
	end
	local d = self.drawn
	if force or d.v ~= self.model.version or d.first ~= v.first or d.last ~= v.last or d.w ~= self.trackW then
		if not force and E.mode == 2 and not E.paused and self.tick % REDRAW_EVERY ~= 0 then return end
		d.v, d.first, d.last, d.w = self.model.version, v.first, v.last, self.trackW
		self:redraw()
	end
end

-- the ruler (ticks every quarter of a step that gives ≤ 10 labels) and the markers in view, 2-px buckets
function Bar:redraw()
	local tl = self.E.tl
	local n = tl:count()
	local v = self.view
	local span = math.max(1, v.last - v.first)
	local step = STEPS[#STEPS]
	for _, s in ipairs(STEPS) do
		if span / s <= 10 then step = s break end
	end
	local minor = step / 4
	local ti, li = 0, 0
	if n > 0 then
		local f = math.ceil(v.first / minor) * minor
		while f <= v.last + 1e-9 and ti < TICKS do
			ti = ti + 1
			local major = math.abs(f / step - math.floor(f / step + 0.5)) < 1e-6
			local t = self.ticks[ti]
			W.paint(t, "Visible", true)
			W.paint(t, "Position", UDim2.new(0, self:xOf(f), 0, major and 13 or 17))
			W.paint(t, "Size", UDim2.new(0, 1, 0, major and 8 or 4))
			if major and li < LABELS then
				li = li + 1
				local l = self.labels[li]
				local fi = math.clamp(math.floor(f + 0.5), 1, n)
				W.paint(l, "Visible", true)
				W.paint(l, "Position", UDim2.new(0, self:xOf(f), 0, 1))
				W.paint(l, "Text", shortTime(tl:get("TotalTime", fi, 1)))
			end
			f = f + minor
		end
	end
	for i = ti + 1, TICKS do W.paint(self.ticks[i], "Visible", false) end
	for i = li + 1, LABELS do W.paint(self.labels[i], "Visible", false) end
	local mi = 0
	local i0, i1 = self.model:range("marker", v.first, v.last)
	local list = self.model:events("marker")
	local lastBucket = nil
	for k = i0, i1 do
		if mi >= MARKS then break end
		local x = self:xOf(list[k])
		local bucket = math.floor(x / 2)
		if bucket ~= lastBucket then
			lastBucket = bucket
			mi = mi + 1
			local m = self.marks[mi]
			W.paint(m, "Visible", true)
			W.paint(m, "Position", UDim2.new(0, x, 0, 26))
		end
	end
	for k = mi + 1, MARKS do W.paint(self.marks[k], "Visible", false) end
	if self.lanes then self.lanes:redraw() end
end

function Bar:destroy()
	if self.dead then return end
	self.dead = true
	if self.off then self.off(); self.off = nil end
	for _, off in ipairs(self.offs) do off() end
	for _, r in ipairs(self.rects) do self.ui.pointer:remove(r) end
	if self.lanes then self.lanes:destroy() end
	self.glass:destroy()
	pcall(function() self.gui:Destroy() end)
end

return Bar
