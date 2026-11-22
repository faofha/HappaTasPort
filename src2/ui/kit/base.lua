-- ================================================================================================
--  BASE  (HappaTAS 3 ui kit): what every control shares. A control is { ctx, gui, rects, offs } with
--  K.rect (a pointer rect in its window's layer), K.style (a function run now and whenever the theme
--  changes) and K.destroy (rects out of the pointer, theme listeners off, the gui destroyed).
--  ctx (from the window manager) = { E, theme, tween, typing, pointer = { add(rect, z), remove(rect) } }.
-- ================================================================================================
local W = import("ui/write")

local K = {}

-- the New interface's sound for a control (ui/sounds; nothing without it)
function K.sound(self, name)
	local ui = self.ctx and self.ctx.ui
	local snd = ui and ui.sounds
	if snd then snd:play(name) end
end

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

-- a self-sizing frame in a scrolling page: live, Roblox didn't draw its background after it grew until the page
-- scrolled once (its texts were drawn). Moving the canvas 1 px and back in the same frame makes it draw, with no
-- visible scroll (V3.1)
function K.redrawOnGrow(frame, scroller)
	return frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(function()
			if not scroller.Parent then return end
			local p = scroller.CanvasPosition
			scroller.CanvasPosition = p + Vector2.new(0, 1)
			scroller.CanvasPosition = p
		end)
	end)
end

-- Tasability's layered edge on a kit control (the theme's compact mode), none otherwise (V3.1)
-- like Tasability's own boxes (compact/kit CK.border): a 2 px dark inner edge and a 1 px outline. ring: the
-- control's own UIStroke, which then paints the outline itself (a field's focus ring); without one a stroke
-- "Edge" is made and shown only in Tasability
function K.edge(gui, th, ring)
	local s = ring or gui:FindFirstChild("Edge")
	if th.compact and th.shades then
		W.set(gui, "BorderMode", Enum.BorderMode.Inset)
		W.set(gui, "BorderSizePixel", 2)
		W.set(gui, "BorderColor3", th.shades.border)
		if not s then
			s = Instance.new("UIStroke")
			s.Name = "Edge"
			pcall(function() s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border end)
			pcall(function() s.LineJoinMode = Enum.LineJoinMode.Miter end)
			s.Parent = gui
		end
		if s.Name == "Edge" then
			W.set(s, "Enabled", true)
			W.set(s, "Thickness", 1)
			W.set(s, "Color", th.shades.outline or th.shades.border)
		end
	else
		W.set(gui, "BorderSizePixel", 0)
		if s and s.Name == "Edge" then W.set(s, "Enabled", false) end
	end
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
