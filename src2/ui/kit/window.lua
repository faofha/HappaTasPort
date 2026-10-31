-- ================================================================================================
--  WINDOW  (HappaTAS 3 ui kit): what one window is made of (the mockup's look): a glass panel, a title bar
--  (bold title on the left, the close and minimise dots on the right, a thin line under it), the body, a
--  corner grip, and four 6 px edge bands for resizing. The window manager (ui/windows.lua) gives it its
--  behaviour; this file only builds and restyles it.
-- ================================================================================================
local W = import("ui/write")
local Glass = import("ui/kit/glass")

local Window = {}
Window.__index = Window

Window.TITLE_H = 36
Window.EDGE = 6
local DOT, DOT_GAP, PAD = 11, 6, 18

local function frame(name, parent, transparent)
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	if transparent ~= false then f.BackgroundTransparency = 1 end
	f.Parent = parent
	return f
end

local function dot(name, parent, x)
	local d = frame(name, parent, false)
	d.Size = UDim2.new(0, DOT, 0, DOT)
	d.AnchorPoint = Vector2.new(0, 0.5)
	d.Position = UDim2.new(1, x, 0.5, 0)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = d
	return d
end

function Window.build(theme, parent, title)
	local self = setmetatable({ theme = theme, titleH = Window.TITLE_H }, Window)
	local holder = frame("Window", parent)
	self.holder = holder
	self.glass = Glass.panel(theme, holder)
	self.panel, self.shadow = self.glass.panel, self.glass.shadow
	local bar = frame("TitleBar", self.panel)
	bar.Size = UDim2.new(1, 0, 0, Window.TITLE_H)
	bar.ZIndex = 2
	self.titleBar = bar
	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, PAD, 0, 0)
	label.Size = UDim2.new(1, -PAD * 2 - DOT * 2 - DOT_GAP, 1, 0)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = title
	label.ZIndex = 2
	label.Parent = bar
	self.titleLabel = label
	-- (close first, then minimise, from the right: the mockup's dots, the red one the close)
	self.minDot = dot("Minimise", bar, -PAD - DOT)
	self.closeDot = dot("Close", bar, -PAD - DOT * 2 - DOT_GAP)
	local line = frame("Line", self.panel, false)
	line.Position = UDim2.new(0, 0, 0, Window.TITLE_H)
	line.Size = UDim2.new(1, 0, 0, 1)
	line.BackgroundColor3 = Color3.new(1, 1, 1)
	line.BackgroundTransparency = 0.9
	line.ZIndex = 2
	self.line = line
	local body = frame("Body", self.panel)
	body.Position = UDim2.new(0, 0, 0, Window.TITLE_H + 1)
	body.Size = UDim2.new(1, 0, 1, -Window.TITLE_H - 1)
	body.ClipsDescendants = true
	body.ZIndex = 2
	self.body = body
	local grip = frame("Grip", self.panel)
	grip.AnchorPoint = Vector2.new(1, 1)
	grip.Position = UDim2.new(1, -4, 1, -4)
	grip.Size = UDim2.new(0, 14, 0, 14)
	grip.ZIndex = 5
	for i, p in ipairs({ { 10, 4 }, { 10, 10 }, { 4, 10 } }) do
		local g = frame("G" .. i, grip, false)
		g.Size = UDim2.new(0, 2, 0, 2)
		g.Position = UDim2.new(0, p[1], 0, p[2])
		g.BackgroundColor3 = Color3.new(1, 1, 1)
		g.BackgroundTransparency = 0.3
		g.ZIndex = 5
	end
	self.grip = grip
	local E_ = Window.EDGE
	local edges = {}
	for _, e in ipairs({ { "l", UDim2.new(0, 0, 0, 0), UDim2.new(0, E_, 1, 0) }, { "r", UDim2.new(1, -E_, 0, 0), UDim2.new(0, E_, 1, 0) },
		{ "t", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, E_) }, { "b", UDim2.new(0, 0, 1, -E_), UDim2.new(1, 0, 0, E_) } }) do
		local f = frame("Edge" .. e[1], holder)
		f.Position, f.Size = e[2], e[3]
		f.ZIndex = 4
		edges[e[1]] = f
	end
	self.edges = edges
	self:restyle()
	self.off = theme:changed(function() self:restyle() end)
	return self
end

function Window:restyle()
	local th = self.theme
	W.set(self.titleLabel, "FontFace", th.font("bold"))
	W.set(self.titleLabel, "TextSize", th.size(13.5))
	W.set(self.titleLabel, "TextColor3", th.c.text)
	W.set(self.closeDot, "BackgroundColor3", th.c.close)
	W.set(self.minDot, "BackgroundColor3", Color3.new(1, 1, 1))
	W.set(self.minDot, "BackgroundTransparency", 0.55)
end

function Window:destroy()
	if self.off then self.off() end
	self.glass:destroy()
	pcall(function() self.holder:Destroy() end)
end

return Window
