-- ================================================================================================
--  INSPECTOR  (HappaTAS 3 ui, spec 8.3 / 6.3): V2's stats panels as a window. Collapsible sections (Frame,
--  Character, Camera & input, World, Performance) of the values in ui/win/inspectorvalues; every row can be
--  pinned (also shown in a Pinned section at the top) or hidden (back from the Options popover); pinned /
--  hidden / collapsed are kept in the settings file (ui.inspector). It doesn't free the mouse (modal false)
--  and opens on the first start. The stats settings: Show Stats (Idle / Create / Test) off = one line instead
--  of the values (Test at another playback speed still shows Frame, V2's rule); Stats Text Size = the values'
--  size. Updated every frame while the character can move (Idle, recording, Test: the frame time and the
--  other values stood still between updates at 5 a second, which read as a bug; the rows that can't change
--  every frame, the rig, health, the settings' rows, 5 times a second), on a change while paused and once a
--  second then too, never while closed or minimised; only the rows that show are worked out, and a value is
--  written only when its text changed;
--  the pipeline is timed (HappaTAS ms) only while Performance shows.
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Button = import("ui/kit/button")
local Toggle = import("ui/kit/toggle")
local Slider = import("ui/kit/slider")
local Popover = import("ui/kit/popover")
local IV = import("ui/win/inspectorvalues")

local Insp = {}
Insp.__index = Insp

local PAD, HEADER_H, ROW_H, TOP = 14, 24, 20, 36
local STAT_KEY = { "showStatsIdle", "showStatsCreate", "showStatsTest" }
local MODE_NAME = { "Idle", "Create", "Test" }
local PERF_EVERY = 1 -- (seconds between FPS / HappaTAS ms readings)
local PAUSED_EVERY = 1 -- (seconds between updates while paused and nothing changes: FPS, HappaTAS ms, settings)
local SLOW_EVERY = 0.2 -- (seconds between updates of the rows marked slow)

function Insp.define(ui)
	ui.wm:define("inspector", { title = "Inspector", w = 320, h = 460, minW = 260, minH = 180, modal = false, corner = "topRight",
		openByDefault = true, build = function(body, win) ui.inspector = Insp.build(ui, body, win) end })
	ui:addDockButton("inspector")
end

-- the saved pins / hides / collapsed sections (a table in the settings file's ui part)
local function saved(ui) return ui.E.settingsFile:getUi().inspector end
local function save(ui)
	local sf = ui.E.settingsFile
	sf:setUi(sf:getUi())
end

function Insp.build(ui, body, win)
	local E = ui.E
	local self = setmetatable({ ui = ui, E = E, win = win, ctx = win.ctx, rows = {}, pinned = {}, sections = {},
		offs = {}, slowT = 0, last = {}, memo = {}, values = {}, perf = { dt = 0, fps = 0, ms = 0 }, perfT = 0, perfFrames = 0 }, Insp)
	local ctx = win.ctx
	self.options = Button.new(ctx, body, { text = "Options", kind = "plain", h = 22 })
	self.options.gui.AnchorPoint = Vector2.new(1, 0)
	self.options.gui.Position = UDim2.new(1, -PAD, 0, 8)
	self.options.onClick = function() self:openOptions() end
	local note = K.text("TextLabel", "Note", body)
	note.Position = UDim2.new(0, PAD, 0, TOP)
	note.Size = UDim2.new(1, -PAD * 2, 0, 22)
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.Visible = false
	self.note = note
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 0, 0, TOP)
	list.Size = UDim2.new(1, 0, 1, -TOP)
	list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.Parent = body
	self.list = list
	local lctx = {}
	for k, v in pairs(ctx) do lctx[k] = v end
	lctx.pointer = { add = function(r, z) r.clip = list; return ctx.pointer.add(r, z) end, remove = ctx.pointer.remove }
	self.lctx = lctx
	local scrollConn = list:GetPropertyChangedSignal("CanvasPosition"):Connect(function() W.bump() end)
	self.offs[#self.offs + 1] = function() scrollConn:Disconnect() end
	for _, name in ipairs({ "Pinned", table.unpack(IV.SECTIONS) }) do self:makeSection(name) end
	for _, def in ipairs(IV.LIST) do
		self.rows[def.key] = self:makeRow(self.sections[def.section], def, false)
	end
	for key in pairs(saved(ui).pinned) do
		if self.rows[key] then self:setPinned(key, true, true) end
	end
	-- (listeners)
	local s = E.settings
	for _, key in ipairs({ "showStatsIdle", "showStatsCreate", "showStatsTest", "playbackSpeed", "statsTextSize" }) do
		self.offs[#self.offs + 1] = s:changed(key, function() self:restyle(); self:layout(); self:update(true) end)
	end
	self.offs[#self.offs + 1] = E.state:watch("mode", function() self:layout(); self:update(true) end)
	self.offs[#self.offs + 1] = ui.theme:changed(function() self:restyle() end)
	self.offs[#self.offs + 1] = ui.wm:changed(function(id) if id == "inspector" then self:follow() end end)
	self.offs[#self.offs + 1] = E.bus:on("uiShown", function(active)
		self:follow()
		if active and self.win.open then self:update(true) end -- (what changed while it was hidden)
	end)
	ui.life:own(function() self:destroy() end)
	self:restyle()
	self:layout()
	self:follow()
	self:update(true)
	return self
end

-- ------------------------------------------------------------------------------------------------ building
function Insp:makeSection(name)
	local sec = { name = name, rows = {} }
	local gui = K.frame("Section_" .. name, self.list)
	gui.Size = UDim2.new(1, 0, 0, HEADER_H)
	sec.gui = gui
	local header = K.frame("Header", gui)
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	sec.header = header
	local label = K.text("TextLabel", "Title", header)
	label.Text = name:upper()
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Position = UDim2.new(0, PAD + 14, 0, 0)
	label.Size = UDim2.new(1, -PAD * 2, 1, 0)
	sec.title = label
	local chev = K.text("TextLabel", "Chevron", header)
	chev.Text = "▼"
	chev.Position = UDim2.new(0, PAD, 0, 0)
	chev.Size = UDim2.new(0, 10, 1, 0)
	sec.chev = chev
	if name ~= "Pinned" then
		self.lctx.pointer.add({ gui = header, onRelease = function(_, clicked)
			if clicked then self:setCollapsed(name, not saved(self.ui).collapsed[name]) end
		end }, 1)
	end
	self.sections[name] = sec
	return sec
end

function Insp:makeRow(sec, def, pinnedCopy)
	local row = { key = def.key, def = def, sec = sec }
	local gui = K.frame("Row_" .. def.key, sec.gui)
	gui.Size = UDim2.new(1, 0, 0, ROW_H)
	row.gui = gui
	local label = K.text("TextLabel", "Label", gui)
	label.Text = def.label
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Position = UDim2.new(0, PAD, 0, 0)
	label.Size = UDim2.new(0.42, -PAD, 1, 0)
	row.label = label
	local value = K.text("TextLabel", "Value", gui)
	value.Text = ""
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.TextTruncate = Enum.TextTruncate.AtEnd
	value.Position = UDim2.new(0.42, 0, 0, 0)
	value.Size = UDim2.new(0.58, -PAD - 44, 1, 0)
	row.value = value
	local pin = Button.new(self.lctx, gui, { text = "•", kind = "plain", w = 18, h = 16, z = 2 })
	pin.gui.AnchorPoint = Vector2.new(1, 0.5)
	pin.gui.Position = UDim2.new(1, -PAD - 22, 0.5, 0)
	pin.onClick = function() self:setPinned(def.key, not saved(self.ui).pinned[def.key]) end
	row.pin = pin
	if not pinnedCopy then
		local hide = Button.new(self.lctx, gui, { text = "×", kind = "plain", w = 18, h = 16, z = 2 })
		hide.gui.AnchorPoint = Vector2.new(1, 0.5)
		hide.gui.Position = UDim2.new(1, -PAD, 0.5, 0)
		hide.onClick = function() self:setHidden(def.key, true) end
		row.hide = hide
	end
	sec.rows[#sec.rows + 1] = row
	return row
end

function Insp:restyle()
	local th = self.ui.theme
	local size = self.E.settings:get("statsTextSize")
	local function styleRow(row)
		W.set(row.label, "FontFace", th.font("text"))
		W.set(row.label, "TextSize", th.size(11))
		W.set(row.label, "TextColor3", th.c.text2)
		W.set(row.value, "FontFace", th.font("number"))
		W.set(row.value, "TextSize", size)
		W.set(row.value, "TextColor3", th.c.text)
	end
	for _, row in pairs(self.rows) do styleRow(row) end
	for _, row in pairs(self.pinned) do styleRow(row) end
	for _, sec in pairs(self.sections) do
		W.set(sec.title, "FontFace", th.font("bold"))
		W.set(sec.title, "TextSize", th.size(10.5))
		W.set(sec.title, "TextColor3", th.c.text2)
		W.set(sec.chev, "FontFace", th.font("bold"))
		W.set(sec.chev, "TextSize", th.size(8))
		W.set(sec.chev, "TextColor3", th.c.text2)
	end
	W.set(self.note, "FontFace", th.font("text"))
	W.set(self.note, "TextSize", th.size(12))
	W.set(self.note, "TextColor3", th.c.text2)
	for key, row in pairs(self.rows) do row.pin:setKind(saved(self.ui).pinned[key] and "primary" or "plain") end
end

-- ------------------------------------------------------------------------------------------------ pin / hide / collapse
function Insp:setPinned(key, on, quiet)
	local data = saved(self.ui)
	data.pinned[key] = on or nil
	if on and not self.pinned[key] then
		local row = self:makeRow(self.sections.Pinned, self.rows[key].def, true)
		self.pinned[key] = row
	end
	if not quiet then save(self.ui) end
	self.last = {}
	self:restyle()
	self:layout()
	self:update(true)
end

function Insp:setHidden(key, on)
	saved(self.ui).hidden[key] = on or nil
	save(self.ui)
	self.last = {}
	self:layout()
	self:update(true)
	if self.optionsPop then self:openOptions(true) end
end

function Insp:setCollapsed(name, on)
	saved(self.ui).collapsed[name] = on or nil
	save(self.ui)
	self.last = {}
	self:layout()
	self:update(true)
end

-- whether the values show in this mode (Show Stats (Mode)); Test at another speed still shows Frame
function Insp:statsShown()
	local E = self.E
	if E.settings:on(STAT_KEY[E.mode] or "showStatsIdle") then return true, true end
	if E.mode == 3 and E.settings:get("playbackSpeed") ~= 1 then return false, true end
	return false, false
end

-- places every section and row (layer units), shows / hides them
function Insp:layout()
	self.plan = nil -- (which rows update: worked out again on the next update)
	local data = saved(self.ui)
	local all, frameToo = self:statsShown()
	W.set(self.note, "Visible", not all and not frameToo)
	W.set(self.note, "Text", "Hidden in " .. (MODE_NAME[self.E.mode] or "Idle"))
	local y = 0
	for _, name in ipairs({ "Pinned", table.unpack(IV.SECTIONS) }) do
		local sec = self.sections[name]
		local show = all or (frameToo and name == "Frame")
		if name == "Pinned" then show = show and next(data.pinned) ~= nil end
		local collapsed = data.collapsed[name] == true
		local h = HEADER_H
		for _, row in ipairs(sec.rows) do
			local visible = show and not collapsed and not data.hidden[row.key]
			if name == "Pinned" then visible = show and not collapsed and data.pinned[row.key] == true end
			W.set(row.gui, "Visible", visible)
			if visible then
				W.set(row.gui, "Position", UDim2.new(0, 0, 0, h))
				h = h + ROW_H
			end
		end
		W.set(sec.gui, "Visible", show)
		W.set(sec.chev, "Rotation", collapsed and -90 or 0)
		if show then
			W.set(sec.gui, "Position", UDim2.new(0, 0, 0, y))
			W.set(sec.gui, "Size", UDim2.new(1, 0, 0, h))
			y = y + h
		end
	end
	W.set(self.list, "CanvasSize", UDim2.new(0, 0, 0, y + 8))
	self:timing()
end

-- the pipeline is timed only while the Performance rows show in an open, unminimised Inspector
function Insp:timing()
	local data = saved(self.ui)
	local all = self:statsShown()
	local perf = all and self.win.open and self.ui:newActive() and not self.win.min and not data.collapsed.Performance
		and not (data.hidden.fps and data.hidden.happaMs)
	self.E.pipe.timing = perf == true
	if not perf then self.E.pipe.timeSum, self.E.pipe.timeFrames = 0, 0 end
end

-- ------------------------------------------------------------------------------------------------ options
function Insp:openOptions(reopen)
	if self.optionsPop then
		self.optionsPop:close()
		self.optionsPop = nil
		if not reopen then return end
	end
	local s = self.E.settings
	local hidden = {}
	for _, def in ipairs(IV.LIST) do
		if saved(self.ui).hidden[def.key] then hidden[#hidden + 1] = def end
	end
	local h = 4 * 32 + 16 + #hidden * 26 + (#hidden > 0 and 22 or 0)
	local pop = Popover.open(self.ctx, self.options.gui, 260, h)
	self.optionsPop = pop
	pop.showButtons = {}
	pop.onClose = function() if self.optionsPop == pop then self.optionsPop = nil end end
	local th = self.ui.theme
	local function label(text, y)
		local l = K.text("TextLabel", "Label", pop.frame)
		l.Text = text
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Position = UDim2.new(0, 12, 0, y)
		l.Size = UDim2.new(1, -24, 0, 26)
		l.FontFace = th.font("text")
		l.TextSize = th.size(12)
		l.TextColor3 = th.c.text
		l.ZIndex = 3
		return l
	end
	local y = 8
	for i, key in ipairs(STAT_KEY) do
		label("Show in " .. MODE_NAME[i], y)
		local t = Toggle.new(pop.ctx, pop.frame, {})
		t.gui.AnchorPoint = Vector2.new(1, 0)
		t.gui.Position = UDim2.new(1, -12, 0, y)
		t.gui.ZIndex = 3
		t:set(s:on(key))
		t.onChange = function(on) s:set(key, on and 1 or 0) end
		y = y + 32
	end
	label("Text size", y)
	local def = { min = 6, max = 30, step = 1 }
	local sl = Slider.new(pop.ctx, pop.frame, { min = def.min, max = def.max, step = def.step, w = 90 })
	sl.gui.AnchorPoint = Vector2.new(1, 0)
	sl.gui.Position = UDim2.new(1, -12, 0, y)
	sl.gui.ZIndex = 3
	sl:set(s:get("statsTextSize"))
	sl.onChange = function(v) s:set("statsTextSize", v) end
	y = y + 32
	if #hidden > 0 then
		label("Hidden rows", y).TextColor3 = th.c.text2
		y = y + 22
		for _, d in ipairs(hidden) do
			label(d.label, y)
			local b = Button.new(pop.ctx, pop.frame, { text = "Show", kind = "plain", h = 20 })
			b.gui.AnchorPoint = Vector2.new(1, 0)
			b.gui.Position = UDim2.new(1, -12, 0, y + 3)
			b.gui.ZIndex = 3
			b.onClick = function() self:setHidden(d.key, false) end
			pop.showButtons[d.key] = b
			y = y + 26
		end
	end
end

-- ------------------------------------------------------------------------------------------------ per frame
function Insp:follow()
	local open = self.win.open and self.ui:newActive()
	if open and not self.off then
		self.pausedKey = nil -- (opened again on the same frame: shown afresh)
		self.off = self.E.pipe:add("PreRender", 230, "ui.inspector", function(dt) self:step(dt) end, "ui")
	elseif not open and self.off then
		self.off()
		self.off = nil
	end
	self:timing()
end

function Insp:step(dt)
	if self.win.min then return end
	local E = self.E
	-- (Performance: averaged over a second)
	self.perfT = self.perfT + (dt or 0)
	self.perfFrames = self.perfFrames + 1
	self.perf.dt = dt or 0
	if self.perfT >= PERF_EVERY then
		self.perf.fps = self.perfFrames / self.perfT
		local pipe = E.pipe
		local frames = pipe.timeFrames or 0
		self.perf.ms = frames > 0 and (pipe.timeSum or 0) / frames * 1000 or 0
		pipe.timeSum, pipe.timeFrames = 0, 0
		self.perfT, self.perfFrames = 0, 0
	end
	-- (every frame; paused: when the frame shown changes, and once a second, only FPS / HappaTAS ms and the rows
	-- from settings change then)
	self.slowT = self.slowT + (dt or 0)
	local slow = self.slowT >= SLOW_EVERY
	if E.mode == 2 and E.paused then
		local tl = E.tl
		local key = E.frame .. ":" .. tl:count() .. ":" .. tl.version .. ":" .. (tl.edits or 0)
		local changed = key ~= self.pausedKey
		self.pausedKey = key
		if not changed and self.slowT < PAUSED_EVERY then return end
		slow = true
	else
		self.pausedKey = nil
	end
	if slow then self.slowT = 0 end
	self:update(false, slow)
end

-- the rows to update ({ want = keys, puts = rows }): every = all that show, fast = without the slow rows;
-- kept until the next layout() (pin / hide / collapse / mode / stats settings all lay out again)
function Insp:makePlan(all, frameToo)
	local data = saved(self.ui)
	local plan = { all = all, frameToo = frameToo, every = { want = {}, puts = {} }, fast = { want = {}, puts = {} } }
	local function add(part, def, row)
		part.want[def.key] = true
		part.puts[#part.puts + 1] = row
	end
	for _, def in ipairs(IV.LIST) do
		local k = def.key
		local rows = {}
		if (all or def.section == "Frame") and not data.collapsed[def.section] and not data.hidden[k] then
			rows[#rows + 1] = self.rows[k]
		end
		if self.pinned[k] and all and data.pinned[k] and not data.collapsed.Pinned then rows[#rows + 1] = self.pinned[k] end
		for _, row in ipairs(rows) do
			add(plan.every, def, row)
			if not def.slow then add(plan.fast, def, row) end
		end
	end
	return plan
end

-- writes the values that changed into the rows that show (slowToo: the slow rows too; force: every row
-- written again)
function Insp:update(force, slowToo)
	if not self.win.open then return end
	local all, frameToo = self:statsShown()
	if not all and not frameToo then return end
	local plan = self.plan
	if not plan or plan.all ~= all or plan.frameToo ~= frameToo then
		plan = self:makePlan(all, frameToo)
		self.plan = plan
	end
	local part = (slowToo or force) and plan.every or plan.fast
	if #part.puts == 0 then return end
	local ok, values = pcall(IV.values, self.E, self.perf, part.want, self.memo, self.values)
	if not ok then return end
	for _, row in ipairs(part.puts) do self:put(row, values, force) end
end

function Insp:put(row, values, force)
	local v = values[row.key] or "-"
	if force or self.last[row] ~= v then
		self.last[row] = v
		W.paint(row.value, "Text", v)
	end
end

function Insp:destroy()
	if self.dead then return end
	self.dead = true
	if self.off then self.off(); self.off = nil end
	if self.optionsPop then self.optionsPop:close() end
	for _, off in ipairs(self.offs) do off() end
	self.E.pipe.timing = false
end

return Insp
