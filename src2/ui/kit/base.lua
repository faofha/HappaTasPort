-- ================================================================================================
--  BASE  (HappaTAS 3 ui kit): what every control shares. A control is { ctx, gui, rects, offs } with
--  K.rect (a pointer rect in its window's layer), K.style (a function run now and whenever the theme
--  changes) and K.destroy (rects out of the pointer, theme listeners off, the gui destroyed).
--  ctx (from the window manager) = { E, theme, tween, typing, pointer = { add(rect, z), remove(rect) } }.
-- ================================================================================================
local W = import("ui/write")

local K = {}

function K.new(ctx, cls)
	return setmetatable({ ctx = ctx, rects = {}, offs = {} }, cls)
end

function K.frame(name, parent, bg)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	if bg then f.BackgroundColor3 = bg else f.BackgroundTransparency = 1 end
	if parent then f.Parent = parent end
	return f
end

function K.text(class, name, parent)
	local t = Instance.new(class)
	t.Name = name
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	if class == "TextBox" then
		t.ClearTextOnFocus = false
		pcall(function() t.TextEditable = true end)
	end
	t.Parent = parent
	return t
end

function K.corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 999)
	c.Parent = parent
	return c
end

function K.stroke(parent, color, transparency, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.new(1, 1, 1)
	s.Transparency = transparency or 0
	s.Thickness = thickness or 1
	s.Parent = parent
	return s
end

-- a soft top-to-bottom shine (the mockup's glass knobs and pills)
function K.gradient(parent, top, bottom)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(top, bottom)
	g.Parent = parent
	return g
end

function K.rect(self, rect, z)
	rect.gui = rect.gui or self.gui
	self.ctx.pointer.add(rect, z)
	self.rects[#self.rects + 1] = rect
	return rect
end

function K.style(self, f)
	f(self.ctx.theme)
	self.offs[#self.offs + 1] = self.ctx.theme:changed(function() f(self.ctx.theme) end)
end

-- a label in the theme's font (kind "text" / "bold" / "number") at size (before Text size scaling)
function K.label(self, parent, text, kind, size, secondary)
	local l = K.text("TextLabel", "Label", parent)
	l.Text = text or ""
	K.style(self, function(th)
		W.set(l, "FontFace", th.font(kind or "text"))
		W.set(l, "TextSize", th.size(size or 13))
		W.set(l, "TextColor3", secondary and th.c.text2 or th.c.text)
	end)
	return l
end

-- the interface scale (UIScale): Absolute* sizes are screen pixels, Offsets are layer units = pixels / scale
function K.scale(self)
	local ui = self.ctx.ui
	return ui and ui.root and ui.root.scale.Scale or 1
end

-- a connection to a signal that outlives the control (UserInputService): owned by the interface's scope, so
-- Unload ends it even when the control is never destroyed, and the control's destroy ends it early
function K.connect(self, signal, fn)
	local ui = self.ctx.ui
	local c
	if ui and ui.life then
		c = ui.life:connect(signal, fn)
		self.offs[#self.offs + 1] = function() ui.life:drop(c) end
	else
		c = signal:Connect(fn)
		self.offs[#self.offs + 1] = function() c:Disconnect() end
	end
	return c
end

function K.destroy(self)
	for _, r in ipairs(self.rects) do self.ctx.pointer.remove(r) end
	self.rects = {}
	for _, off in ipairs(self.offs) do off() end
	self.offs = {}
	if self.gui then pcall(function() self.gui:Destroy() end) end
end

return K
