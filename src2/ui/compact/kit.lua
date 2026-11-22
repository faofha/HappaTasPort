-- ================================================================================================
--  COMPACT KIT  (HappaTAS 3 ui, V3.1): the Compact interface's own pieces, drawn in the theme's compact shades
--  (ui/theme compactShades): the layered border (a dark inner edge and an outline stroke), the accent line,
--  sections (an accent line, a small capital title, a body that lists its rows), chips (small boxed labels or
--  buttons) and tabs (capital, accent text and underline when active). Each repaints on a theme change and
--  destroy() removes it and its listener.
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")

local CK = {}

local Piece = {}
Piece.__index = Piece
Piece.destroy = K.destroy

local function sh(th) return th.shades or {} end

-- the layered border on gui: a 2 px dark inner edge and a 1 px outline stroke (painted by the owner's style)
function CK.border(gui)
	gui.BorderSizePixel = 2
	gui.BorderMode = Enum.BorderMode.Inset
	local s = Instance.new("UIStroke")
	s.Thickness = 1
	pcall(function() s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border end)
	pcall(function() s.LineJoinMode = Enum.LineJoinMode.Miter end)
	s.Parent = gui
	return s
end

-- paints a layered border made by CK.border
function CK.paintBorder(gui, stroke, th)
	local s = sh(th)
	if s.border then W.set(gui, "BorderColor3", s.border) end
	if s.outline then W.set(stroke, "Color", s.outline) end
end

-- a 2 px accent line across the top of parent (white-to-grey shine); painted by the owner's style
function CK.accentLine(parent)
	local line = K.frame("AccentLine", parent, Color3.new(1, 1, 1))
	line.Size = UDim2.new(1, 0, 0, 2)
	line.ZIndex = (parent.ZIndex or 1) + 2
	K.gradient(line, Color3.new(1, 1, 1), Color3.fromRGB(65, 65, 65)).Rotation = 90
	return line
end

-- a section: { gui, body, title }; body lists its rows (padding 5) and grows with them
function CK.section(ctx, parent, title)
	local self = K.new(ctx, Piece)
	local gui = K.frame("Section", parent, Color3.new(0, 0, 0))
	gui.Size = UDim2.new(1, 0, 0, 0)
	gui.AutomaticSize = Enum.AutomaticSize.Y
	self.gui = gui
	local stroke = CK.border(gui)
	local line = CK.accentLine(gui)
	local t = K.text("TextLabel", "Title", gui)
	t.Text = string.upper(title or "")
	t.Position = UDim2.new(0, 7, 0, 4)
	t.Size = UDim2.new(1, -12, 0, 16)
	t.TextXAlignment = Enum.TextXAlignment.Left
	K.stroke(t, Color3.new(0, 0, 0), 0, 1)
	self.title = t
	local body = K.frame("Body", gui)
	body.Position = UDim2.new(0, 0, 0, 22)
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 6)
	pad.Parent = body
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 5)
	list.Parent = body
	self.body = body
	K.style(self, function(th)
		local s = sh(th)
		if s.inline then W.set(gui, "BackgroundColor3", s.inline) end
		CK.paintBorder(gui, stroke, th)
		W.set(line, "BackgroundColor3", th.c.accent)
		W.set(t, "TextColor3", th.c.accent)
		W.set(t, "FontFace", th.font("bold"))
		W.set(t, "TextSize", th.size(10.5))
	end)
	return self
end

-- a chip: a small boxed label, or a button with opts.button (opts.onClick); { gui, label, set(text) }
function CK.chip(ctx, parent, text, opts)
	opts = opts or {}
	local self = K.new(ctx, Piece)
	local gui = K.frame("Chip", parent, Color3.new(0, 0, 0))
	gui.Size = UDim2.new(0, 62, 0, 18)
	self.gui = gui
	local stroke = CK.border(gui)
	local l = K.text("TextLabel", "Label", gui)
	l.Size = UDim2.new(1, 0, 1, 0)
	l.Text = text or ""
	self.label = l
	self.color = opts.color
	self.hover = false
	function self.set(_, t) W.set(l, "Text", t) end
	function self.setColor(_, c)
		self.color = c
		W.set(l, "TextColor3", c or ctx.theme.c.text2)
	end
	K.style(self, function(th)
		local s = sh(th)
		local bg = self.hover and s.hover or s.element
		if bg then W.set(gui, "BackgroundColor3", bg) end
		CK.paintBorder(gui, stroke, th)
		W.set(l, "FontFace", th.font(opts.bold == false and "text" or "bold"))
		W.set(l, "TextSize", th.size(9.5))
		W.set(l, "TextColor3", self.color or (self.hover and th.c.accent) or th.c.text2)
	end)
	if opts.button then
		local function repaint()
			local th = ctx.theme
			local s = sh(th)
			if s.element then W.set(gui, "BackgroundColor3", self.hover and s.hover or s.element) end
			W.set(l, "TextColor3", self.color or (self.hover and th.c.accent) or th.c.text2)
		end
		K.rect(self, { gui = gui,
			onHover = function(on) self.hover = on; repaint() end,
			onRelease = function(_, clicked) if clicked and opts.onClick then opts.onClick() end end })
	end
	return self
end

-- a tab: 90 x 22, capital text; setActive(on)
function CK.tab(ctx, parent, text, onClick)
	local self = K.new(ctx, Piece)
	local gui = K.frame("Tab", parent, Color3.new(0, 0, 0))
	gui.Size = UDim2.new(0, 90, 0, 22)
	self.gui = gui
	local stroke = CK.border(gui)
	local l = K.text("TextLabel", "Label", gui)
	l.Size = UDim2.new(1, 0, 1, 0)
	l.Position = UDim2.new(0, 0, 0, -1)
	l.Text = string.upper(text or "")
	K.stroke(l, Color3.new(0, 0, 0), 0, 1)
	self.label = l
	local under = K.frame("Underline", gui, Color3.new(1, 1, 1))
	under.AnchorPoint = Vector2.new(0, 1)
	under.Position = UDim2.new(0, 0, 1, 0)
	under.Size = UDim2.new(1, 0, 0, 2)
	under.Visible = false
	self.underline = under
	self.active, self.hover = false, false
	local function paint(th)
		local s = sh(th)
		local bg = self.active and s.inline or (self.hover and s.hover) or s.panel
		if bg then W.set(gui, "BackgroundColor3", bg) end
		CK.paintBorder(gui, stroke, th)
		W.set(under, "BackgroundColor3", th.c.accent)
		W.set(under, "Visible", self.active)
		W.set(l, "FontFace", th.font("text"))
		W.set(l, "TextSize", th.size(11))
		W.set(l, "TextColor3", (self.active or self.hover) and th.c.accent or th.c.text)
		W.set(l, "TextTransparency", (self.active or self.hover) and 0 or 0.48)
	end
	K.style(self, paint)
	function self.setActive(_, on)
		self.active = on == true
		paint(ctx.theme)
	end
	K.rect(self, { gui = gui,
		onHover = function(on) self.hover = on; paint(ctx.theme) end,
		onRelease = function(_, clicked) if clicked and onClick then onClick() end end })
	return self
end

return CK
