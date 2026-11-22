-- ================================================================================================
--  TASABILITY PARTS  (HappaTAS 3 ui, V3.1): the Tasability interface's own controls, in the theme's compact shades
--  (docs/superpowers/specs/2026-11-22-tasability-settings-design.md): checkbox, value box, dropdown, colour box,
--  button, key box, slider. Square, layered borders, the accent from accentColor, dim labels in the secondary text
--  colour, Gotham with a 1 px black text outline; hover: the hover shade and accent text. Each part has gui,
--  set(v) (shows a value without reporting it) and destroy(); a player's change is reported through opts.onChange
--  (or the part's own callbacks). Glyphs only ASCII and × ▼ ← … • (the tick is a drawn square).
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local CK = import("ui/compact/kit")
local Popover = import("ui/kit/popover")
local ColorPicker = import("ui/kit/colorpicker")
local Settings = import("engine/settings")

local P = {}

local Part = {}
Part.__index = Part
Part.destroy = K.destroy

local WAIT_COLOR = Color3.fromHex("DCC83C")
local COLOR_DEF = { kind = "color" }

local function sh(th) return th.shades or {} end

-- the interface scale (Absolute sizes are screen pixels, popover sizes layer units)
local function uiScale(ctx)
	local ui = ctx.ui
	return ui and ui.root and ui.root.scale.Scale or 1
end

-- a label with the Tasability text outline
local function text(parent, name, str, align)
	local l = K.text("TextLabel", name, parent)
	l.Text = str or ""
	l.TextXAlignment = align or Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	K.stroke(l, Color3.new(0, 0, 0), 0, 1)
	return l
end

local function paintText(l, th, size, color, bold)
	W.set(l, "FontFace", th.font(bold and "bold" or "text"))
	W.set(l, "TextSize", th.size(size))
	W.set(l, "TextColor3", color)
end

-- ------------------------------------------------------------------------------------------------ checkbox
function P.checkbox(ctx, parent, label, opts)
	opts = opts or {}
	local self = K.new(ctx, Part)
	self.value, self.hover = false, false
	local gui = K.frame("Checkbox", parent)
	gui.Size = UDim2.new(1, 0, 0, 18)
	self.gui = gui
	local box = K.frame("Box", gui, Color3.new(0, 0, 0))
	box.Position, box.Size = UDim2.new(0, 0, 0, 3), UDim2.new(0, 12, 0, 12)
	local stroke = CK.border(box)
	local tick = K.frame("Tick", box, Color3.new(1, 1, 1))
	tick.AnchorPoint, tick.Position, tick.Size = Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 0.5, 0), UDim2.new(0, 6, 0, 6)
	tick.Visible = false
	local l = text(gui, "Label", label)
	l.Position, l.Size = UDim2.new(0, 20, 0, 0), UDim2.new(1, -20, 1, 0)
	self.box, self.tick, self.label = box, tick, l
	local function paint(th)
		local s = sh(th)
		W.set(box, "BackgroundColor3", self.value and th.c.accent:Lerp(s.deep or Color3.new(0, 0, 0), 0.7) or (s.deep or Color3.new(0, 0, 0)))
		CK.paintBorder(box, stroke, th)
		W.set(tick, "BackgroundColor3", th.c.accent)
		W.set(tick, "Visible", self.value)
		paintText(l, th, 11, self.hover and th.c.accent or th.c.text)
	end
	self.paint = paint
	K.style(self, paint)
	function self.set(_, on)
		self.value = on == true
		paint(ctx.theme)
	end
	K.rect(self, { gui = gui,
		onHover = function(on) self.hover = on; paint(ctx.theme); if opts.onHover then opts.onHover(on) end end,
		onRelease = function(_, clicked)
			if not clicked then return end
			self:set(not self.value)
			if opts.onChange then opts.onChange(self.value) end
		end })
	return self
end

-- ------------------------------------------------------------------------------------------------ value box
-- a row: the label on the left 40 %, a box on the right 60 %
local function boxRow(ctx, self, parent, label, opts)
	local gui = K.frame(opts.name or "ValueBox", parent)
	gui.Size = UDim2.new(1, 0, 0, 22)
	self.gui = gui
	local l = text(gui, "Label", label)
	l.Size = UDim2.new(0.4, -4, 1, 0)
	self.label = l
	local holder = K.frame("Holder", gui, Color3.new(0, 0, 0))
	holder.Position, holder.Size = UDim2.new(0.4, 0, 0, 0), UDim2.new(0.6, 0, 1, 0)
	self.holder = holder
	self.holderStroke = CK.border(holder)
	return gui
end

function P.valueBox(ctx, parent, label, opts)
	opts = opts or {}
	local self = K.new(ctx, Part)
	boxRow(ctx, self, parent, label, opts)
	local box = K.text("TextBox", "Box", self.holder)
	box.Position, box.Size = UDim2.new(0, 5, 0, 0), UDim2.new(1, -(opts.rightPad or 0) - 9, 1, 0)
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.Text = ""
	self.box = box
	local focused = false
	local function paint(th)
		local s = sh(th)
		if s.element then W.set(self.holder, "BackgroundColor3", s.element) end
		CK.paintBorder(self.holder, self.holderStroke, th)
		if focused then W.set(self.holderStroke, "Color", th.c.accent) end
		paintText(self.label, th, 10.5, th.c.text2)
		paintText(box, th, 11, focused and th.c.accent or th.c.text)
	end
	K.style(self, paint)
	function self.set(_, t)
		if not focused then box.Text = tostring(t or "") end
	end
	K.connect(self, box.Focused, function() focused = true; paint(ctx.theme) end)
	K.connect(self, box.FocusLost, function()
		focused = false
		local ok = opts.commit and opts.commit(box.Text)
		if opts.current then box.Text = tostring(opts.current()) end
		paint(ctx.theme)
		return ok
	end)
	K.rect(self, { gui = self.gui, onHover = function(on) if opts.onHover then opts.onHover(on) end end }, -1)
	-- (the interface's pointer sits over Roblox's own text box: a click on it focuses the box, like ui/kit/field)
	K.rect(self, { gui = box, onRelease = function(_, clicked) if clicked then box:CaptureFocus() end end })
	return self
end

-- ------------------------------------------------------------------------------------------------ dropdown
function P.dropdown(ctx, parent, label, options, opts)
	opts = opts or {}
	local self = K.new(ctx, Part)
	self.options = options
	boxRow(ctx, self, parent, label, opts)
	local button = self.holder
	button.Name = "Button"
	self.button = button
	local v = text(button, "Value", "")
	v.Position, v.Size = UDim2.new(0, 5, 0, 0), UDim2.new(1, -24, 1, 0)
	local arrow = text(button, "Arrow", "▼", Enum.TextXAlignment.Center)
	arrow.AnchorPoint, arrow.Position, arrow.Size = Vector2.new(1, 0), UDim2.new(1, -2, 0, 0), UDim2.new(0, 16, 1, 0)
	self.valueLabel = v
	local hover = false
	local function paint(th)
		local s = sh(th)
		if s.element then W.set(button, "BackgroundColor3", hover and s.hover or s.element) end
		CK.paintBorder(button, self.holderStroke, th)
		paintText(self.label, th, 10.5, th.c.text2)
		paintText(v, th, 11, hover and th.c.accent or th.c.text)
		paintText(arrow, th, 9, th.c.text2)
	end
	K.style(self, paint)
	function self.set(_, val)
		self.value = val
		W.set(v, "Text", tostring(val or ""))
	end
	function self.close()
		if self.pop then self.pop:close() end
	end
	local function open()
		local n = #self.options
		local pop = Popover.open(ctx, button, button.AbsoluteSize.X / uiScale(ctx), 20 * math.min(n, 8) + 4)
		self.pop, self.list = pop, pop.frame
		for i, opt in ipairs(self.options) do
			local item = K.frame("Item", pop.frame, Color3.new(1, 1, 1))
			item.BackgroundTransparency = 1
			item.Position, item.Size = UDim2.new(0, 2, 0, 2 + (i - 1) * 20), UDim2.new(1, -4, 0, 20)
			item.ZIndex = 3
			local l = text(item, "Label", tostring(opt))
			l.Position, l.Size, l.ZIndex = UDim2.new(0, 6, 0, 0), UDim2.new(1, -8, 1, 0), 3
			paintText(l, ctx.theme, 11, ctx.theme.c.text2)
			pop:add({ gui = item,
				onHover = function(on)
					W.set(item, "BackgroundTransparency", on and 0.85 or 1)
					W.set(l, "TextColor3", on and ctx.theme.c.accent or ctx.theme.c.text2)
				end,
				onRelease = function(_, clicked)
					if not clicked then return end
					self:set(opt)
					pop:close()
					if opts.onChange then opts.onChange(opt) end
				end }, 2)
		end
		pop.onClose = function()
			if self.pop == pop then self.pop, self.list = nil, nil end
		end
	end
	K.rect(self, { gui = button,
		onHover = function(on) hover = on; paint(ctx.theme); if opts.onHover then opts.onHover(on) end end,
		onRelease = function(_, clicked)
			if not clicked then return end
			if self.pop then self.pop:close() else open() end
		end })
	K.rect(self, { gui = self.gui, onHover = function(on) if opts.onHover then opts.onHover(on) end end }, -1)
	self.offs[#self.offs + 1] = function() self.close() end
	return self
end

-- ------------------------------------------------------------------------------------------------ colour box
function P.colorBox(ctx, parent, label, opts)
	opts = opts or {}
	local self
	self = P.valueBox(ctx, parent, label, { name = "ColorBox", rightPad = 20, onHover = opts.onHover,
		current = function() return opts.value() end,
		commit = function(t)
			local hex = Settings.sanitize(COLOR_DEF, t)
			if not hex then return false end
			if opts.onApply then opts.onApply(hex) end
			return true
		end })
	local sw = K.frame("Swatch", self.holder, Color3.new(1, 1, 1))
	sw.AnchorPoint, sw.Position, sw.Size = Vector2.new(1, 0.5), UDim2.new(1, -4, 0.5, 0), UDim2.new(0, 14, 0, 12)
	K.stroke(sw, Color3.new(0, 0, 0), 0, 1)
	self.swatch = sw
	local valueSet = self.set
	function self.set(me, hex)
		valueSet(me, hex)
		local ok, c = pcall(function() return Color3.fromHex(tostring(hex):sub(2)) end)
		if ok then W.set(sw, "BackgroundColor3", c) end
	end
	K.rect(self, { gui = sw, onRelease = function(_, clicked)
		if not clicked then return end
		ColorPicker.open(ctx, sw, { value = opts.value(), default = opts.default,
			onPreview = opts.onPreview, onApply = opts.onApply })
	end }, 2)
	return self
end

-- ------------------------------------------------------------------------------------------------ button
function P.button(ctx, parent, label, opts)
	opts = opts or {}
	local self = K.new(ctx, Part)
	self.onClick = opts.onClick
	local gui = K.frame("Button", parent, Color3.new(0, 0, 0))
	gui.Size = opts.w and UDim2.new(0, opts.w, 0, 22) or UDim2.new(1, 0, 0, 22)
	self.gui = gui
	local stroke = CK.border(gui)
	K.gradient(gui, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
	local l = text(gui, "Label", label, Enum.TextXAlignment.Center)
	l.Size, l.Position = UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, -1)
	self.label = l
	local hover = false
	local function paint(th)
		local s = sh(th)
		if s.element then W.set(gui, "BackgroundColor3", hover and s.hover or s.element) end
		CK.paintBorder(gui, stroke, th)
		paintText(l, th, 11, hover and th.c.accent or th.c.text)
	end
	K.style(self, paint)
	function self.set(_, t) W.set(l, "Text", tostring(t or "")) end
	K.rect(self, { gui = gui,
		onHover = function(on) hover = on; paint(ctx.theme) end,
		onRelease = function(_, clicked) if clicked and self.onClick then self.onClick() end end })
	return self
end

-- ------------------------------------------------------------------------------------------------ key box
function P.keyBox(ctx, parent, label, opts)
	opts = opts or {}
	local self = K.new(ctx, Part)
	self.keyName, self.waiting, self.conflict, self.hover = "", false, false, false
	local gui = K.frame("KeyBox", parent, Color3.new(0, 0, 0))
	gui.Size = UDim2.new(1, 0, 0, 22)
	self.gui = gui
	local stroke = CK.border(gui)
	local l = text(gui, "Label", label)
	l.Position, l.Size = UDim2.new(0, 6, 0, 0), UDim2.new(0.58, -8, 1, 0)
	self.label = l
	local inset = K.frame("Inset", gui, Color3.new(0, 0, 0))
	inset.Position, inset.Size = UDim2.new(0.58, 0, 0.15, 0), UDim2.new(0.42, -24, 0.7, 0)
	inset.BorderSizePixel = 0
	local insetStroke = K.stroke(inset, Color3.new(1, 1, 1), 0.4, 1)
	self.inset, self.insetStroke = inset, insetStroke
	local key = text(inset, "Key", "", Enum.TextXAlignment.Center)
	key.Size = UDim2.new(1, 0, 1, 0)
	self.key = key
	local clear = CK.chip(ctx, gui, "×", { button = true, onClick = function() if opts.onClear then opts.onClear() end end })
	clear.gui.AnchorPoint, clear.gui.Position, clear.gui.Size = Vector2.new(1, 0.5), UDim2.new(1, -3, 0.5, 0), UDim2.new(0, 16, 0, 16)
	self.clear = clear
	self.offs[#self.offs + 1] = function() clear:destroy() end
	local function paint(th)
		local s = sh(th)
		if s.element then W.set(gui, "BackgroundColor3", self.hover and s.hover or s.element) end
		CK.paintBorder(gui, stroke, th)
		if s.deep then W.set(inset, "BackgroundColor3", s.deep) end
		W.set(insetStroke, "Color", self.conflict and th.c.rec or th.c.accent:Lerp(s.deep or Color3.new(0, 0, 0), 0.6))
		W.set(insetStroke, "Transparency", self.conflict and 0 or 0.4)
		paintText(l, th, 10.5, self.hover and th.c.accent or th.c.text2)
		paintText(key, th, 10.5, self.waiting and WAIT_COLOR or th.c.accent)
		W.set(key, "Text", self.waiting and "..." or self.keyName)
	end
	K.style(self, paint)
	function self.set(_, name)
		self.keyName = tostring(name or "")
		paint(ctx.theme)
	end
	function self.setWaiting(_, on)
		self.waiting = on == true
		paint(ctx.theme)
	end
	function self.setConflict(_, on)
		self.conflict = on == true
		paint(ctx.theme)
	end
	K.rect(self, { gui = gui,
		onHover = function(on) self.hover = on; paint(ctx.theme); if opts.onHover then opts.onHover(on) end end,
		onRelease = function(_, clicked) if clicked and opts.onClick then opts.onClick() end end }, -1)
	return self
end

-- ------------------------------------------------------------------------------------------------ slider
function P.slider(ctx, parent, opts)
	opts = opts or {}
	local self = K.new(ctx, Part)
	self.min, self.max = opts.min or 0, opts.max or 1
	self.fmt = opts.fmt or tostring
	self.value = self.min
	self.onChange = opts.onChange
	local gui = K.frame("Slider", parent)
	gui.Size = UDim2.new(1, 0, 0, 22)
	self.gui = gui
	local track = K.frame("Track", gui, Color3.new(0, 0, 0))
	track.AnchorPoint, track.Position, track.Size = Vector2.new(0, 0.5), UDim2.new(0, 0, 0.5, 0), UDim2.new(1, -56, 0, 6)
	local tstroke = CK.border(track)
	local fill = K.frame("Fill", track, Color3.new(1, 1, 1))
	fill.Size = UDim2.new(0, 0, 1, 0)
	local knob = K.frame("Knob", track, Color3.new(1, 1, 1))
	knob.AnchorPoint, knob.Size = Vector2.new(0.5, 0.5), UDim2.new(0, 10, 0, 10)
	knob.Position = UDim2.new(0, 0, 0.5, 0)
	K.stroke(knob, Color3.new(0, 0, 0), 0, 1)
	local value = K.text("TextBox", "Value", gui)
	value.AnchorPoint, value.Position, value.Size = Vector2.new(1, 0), UDim2.new(1, 0, 0, 0), UDim2.new(0, 50, 1, 0)
	value.TextXAlignment = Enum.TextXAlignment.Right
	self.track, self.fill, self.knob, self.valueLabel = track, fill, knob, value
	local function show()
		local a = (self.max > self.min) and (self.value - self.min) / (self.max - self.min) or 0
		W.set(fill, "Size", UDim2.new(a, 0, 1, 0))
		W.set(knob, "Position", UDim2.new(a, 0, 0.5, 0))
		value.Text = self.fmt(self.value)
	end
	local function paint(th)
		local s = sh(th)
		if s.deep then W.set(track, "BackgroundColor3", s.deep) end
		CK.paintBorder(track, tstroke, th)
		W.set(fill, "BackgroundColor3", th.c.accent)
		W.set(knob, "BackgroundColor3", th.c.accent)
		paintText(value, th, 11, th.c.text)
	end
	K.style(self, paint)
	function self.set(_, v)
		v = tonumber(v)
		if not v then return end
		self.value = math.clamp(v, self.min, self.max)
		show()
	end
	local function report(v)
		self:set(v)
		if self.onChange then self.onChange(self.value) end
	end
	local function fromX(pos)
		local a, w = track.AbsolutePosition.X, track.AbsoluteSize.X
		if w <= 0 then return end
		local t = math.clamp((pos.X - a) / w, 0, 1)
		report(self.min + (self.max - self.min) * t)
	end
	K.rect(self, { gui = track, onPress = fromX, onDrag = function(pos) fromX(pos) end })
	K.rect(self, { gui = value, onRelease = function(_, clicked) if clicked then value:CaptureFocus() end end })
	K.connect(self, value.FocusLost, function()
		local n = tonumber((value.Text:gsub("[^%d%.%-]", "")))
		if n then report(n) else show() end
	end)
	show()
	return self
end

return P
