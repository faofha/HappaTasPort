-- ================================================================================================
--  CLASSIC COLOUR PICKER  (HappaTAS 3 ui, Classic Look; V3.1 layout): a small window in Classic's own look for
--  one colour setting, the same design as the New interface's picker (ui/kit/colorpicker): a saturation /
--  brightness square and a hue bar (press and drag), the old and new colour side by side, one box for "#RRGGBB"
--  or "r, g, b", the quick colours, the recent colours, Reset (to the default: Auto on a colour that can follow
--  the Main Colour), Cancel and Apply. The colour shows on Classic live while picking; closing without Apply
--  (Cancel, Esc, a click outside it, another tab, hiding Classic, Unload) puts the old value back. One at a
--  time (classic.picker). It is built in V2's colours and the Classic Look paints it like any other part.
-- ================================================================================================
local Env = import("platform/env")
local Settings = import("engine/settings")
local Palette = import("ui/classic/palette")
local KitPicker = import("ui/kit/colorpicker")

local ClassicPicker = {}
ClassicPicker.__index = ClassicPicker

local NAME = "HappaTASColorPicker"
local W, H, SQ, BAR, SW, STEP = 300, 344, 180, 22, 24, 28
local Z = 40
local u, rgb = UDim2.new, Color3.fromRGB
local COLOR_DEF = { kind = "color" }

-- (noLook: the part keeps its own colours; marked before it is parented, when the Look first sees it)
local function frame(name, parent, color, pos, size, z, noLook)
	local f = Instance.new("Frame")
	f.Name, f.BorderSizePixel, f.BackgroundColor3 = name, 0, color
	f.Position, f.Size, f.ZIndex = pos, size, z or Z + 1
	if noLook then f:SetAttribute("HappaTASNoLook", true) end
	f.Parent = parent
	return f
end
local function corner(p, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
end
local function button(name, parent, text, pos, size, color)
	local b = Instance.new("TextButton")
	b.Name, b.Text, b.BorderSizePixel = name, text, 0
	b.BackgroundColor3, b.TextColor3, b.TextSize = color, rgb(255, 255, 255), 14
	b.Position, b.Size, b.ZIndex = pos, size, Z + 1
	b.Parent = parent
	corner(b, 5)
	return b
end
local function inside(gui, p)
	local a, s = gui.AbsolutePosition, gui.AbsoluteSize
	return p.X >= a.X and p.X <= a.X + s.X and p.Y >= a.Y and p.Y <= a.Y + s.Y
end

-- opens the picker for setting `key` (closing one already open); returns it (also classic.picker)
function ClassicPicker.open(classic, key)
	if classic.picker then classic.picker:close() end
	local s = classic.E.settings
	local def = Settings.byKey[key]
	local start = (key == "classicMainColor") and Color3.fromHex(s:get(key):sub(2)) or classic.look:color(key)
	local self = setmetatable({ classic = classic, key = key, offs = {}, original = s:get(key), quick = {}, recent = {} }, ClassicPicker)
	self.h, self.s, self.v = start:ToHSV()
	-- (the window, in V2's colours: the Classic Look repaints it)
	local f = frame(NAME, classic.gui, rgb(0, 35, 73), u(0.5, 0, 0.5, 0), u(0, W, 0, H), Z)
	f.AnchorPoint, f.Active = Vector2.new(0.5, 0.5), true
	corner(f, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Color, stroke.Thickness = rgb(0, 141, 237), 1
	stroke.Parent = f
	self.frame = f
	local title = Instance.new("TextLabel")
	title.Name, title.BackgroundTransparency, title.Text = "Title", 1, def and def.name or key
	title.TextColor3, title.TextSize, title.ZIndex = rgb(255, 255, 255), 14, Z + 1
	title.Position, title.Size = u(0, 10, 0, 4), u(1, -20, 0, 20)
	title.Parent = f
	-- the square: the hue at full strength, white to the left, black to the bottom
	local sq = frame("Square", f, Color3.fromHSV(self.h, 1, 1), u(0, 10, 0, 28), u(0, SQ, 0, SQ))
	sq.Active = true
	local white = frame("White", sq, rgb(255, 255, 255), u(0, 0, 0, 0), u(1, 0, 1, 0), Z + 2, true)
	local wg = Instance.new("UIGradient")
	wg.Transparency = NumberSequence.new(0, 1)
	wg.Parent = white
	local black = frame("Black", sq, rgb(0, 0, 0), u(0, 0, 0, 0), u(1, 0, 1, 0), Z + 3, true)
	local bg = Instance.new("UIGradient")
	bg.Rotation, bg.Transparency = 90, NumberSequence.new(1, 0)
	bg.Parent = black
	local mark = frame("Mark", sq, rgb(255, 255, 255), u(0, 0, 0, 0), u(0, 12, 0, 12), Z + 4, true)
	mark.AnchorPoint, mark.BackgroundTransparency = Vector2.new(0.5, 0.5), 1
	corner(mark, 6)
	local ms = Instance.new("UIStroke")
	ms.Color, ms.Thickness = rgb(255, 255, 255), 2
	ms.Parent = mark
	-- the hue bar, top to bottom
	local hue = frame("Hue", f, rgb(255, 255, 255), u(0, 10 + SQ + 8, 0, 28), u(0, BAR, 0, SQ), nil, true)
	hue.Active = true
	local keys = {}
	for i = 0, 6 do keys[#keys + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i / 6) % 1, 1, 1)) end
	local hg = Instance.new("UIGradient")
	hg.Rotation, hg.Color = 90, ColorSequence.new(keys)
	hg.Parent = hue
	local hueMark = frame("HueMark", hue, rgb(255, 255, 255), u(0.5, 0, 0, 0), u(1, 6, 0, 4), Z + 2, true)
	hueMark.AnchorPoint = Vector2.new(0.5, 0.5)
	-- old / new
	local x = 10 + SQ + 8 + BAR + 10
	local old = frame("Old", f, start, u(0, x, 0, 28), u(0, W - x - 10, 0, 40), nil, true)
	local new = frame("New", f, start, u(0, x, 0, 68), u(0, W - x - 10, 0, 40), nil, true)
	self.square, self.mark, self.hueBar, self.hueMark, self.newHalf = sq, mark, hue, hueMark, new
	-- the box and the buttons
	local box = Instance.new("TextBox")
	box.Name, box.ClearTextOnFocus, box.BorderSizePixel = "Value", false, 0
	box.BackgroundColor3, box.TextColor3, box.TextSize = rgb(0, 52, 129), rgb(255, 255, 255), 13
	box.PlaceholderText, box.PlaceholderColor3 = "#RRGGBB or r, g, b", rgb(178, 178, 178)
	box.Position, box.Size, box.ZIndex = u(0, 10, 0, 28 + SQ + 8), u(1, -20, 0, 22), Z + 1
	box.Parent = f
	corner(box, 5)
	self.box = box
	-- the quick and the recent colours: a caption, then a round swatch each
	local function swatches(list, into, title, ry)
		local l = Instance.new("TextLabel")
		l.Name, l.BackgroundTransparency, l.Text = title .. "Title", 1, title
		l.TextColor3, l.TextSize, l.ZIndex = rgb(255, 255, 255), 13, Z + 1
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Position, l.Size = u(0, 10, 0, ry), u(0, 50, 0, SW)
		l.Parent = f
		for i, hex in ipairs(list) do
			local b = Instance.new("TextButton")
			b.Name, b.Text, b.BorderSizePixel, b.AutoButtonColor = title, "", 0, false
			b:SetAttribute("HappaTASNoLook", true)
			b.BackgroundColor3 = Color3.fromHex(hex:sub(2))
			b.Position, b.Size, b.ZIndex = u(0, 64 + (i - 1) * STEP, 0, ry), u(0, SW, 0, SW), Z + 1
			b.Parent = f
			corner(b, SW / 2)
			into[i] = { button = b, hex = hex }
		end
	end
	local qy = 28 + SQ + 8 + 22 + 8
	swatches(KitPicker.QUICK, self.quick, "Quick", qy)
	local data = classic.E.settingsFile and classic.E.settingsFile:getUi()
	swatches(data and data.recentColors or {}, self.recent, "Recent", qy + SW + 6)
	local by = qy + 2 * (SW + 6) + 2
	local bw = (W - 40) / 3
	self.resetButton = button("Reset", f, "Reset", u(0, 10, 0, by), u(0, bw, 0, 26), rgb(0, 52, 129))
	self.cancelButton = button("Cancel", f, "Cancel", u(0, 10 + bw + 10, 0, by), u(0, bw, 0, 26), rgb(142, 11, 0))
	self.applyButton = button("Apply", f, "Apply", u(0, 10 + 2 * (bw + 10), 0, by), u(0, bw, 0, 26), rgb(0, 52, 129))
	-- input
	local function conn(sig, fn)
		local c = sig:Connect(fn)
		self.offs[#self.offs + 1] = function() c:Disconnect() end
	end
	conn(self.applyButton.MouseButton1Click, function() self:apply() end)
	conn(self.cancelButton.MouseButton1Click, function() self:close() end)
	conn(self.resetButton.MouseButton1Click, function() self:reset() end)
	for _, list in ipairs({ self.quick, self.recent }) do
		for _, it in ipairs(list) do conn(it.button.MouseButton1Click, function() self:typed(it.hex) end) end
	end
	conn(box.FocusLost, function() self:typed(box.Text) end)
	local uis = Env.svc("UserInputService")
	local function point(inp) return Vector2.new(inp.Position.X, inp.Position.Y) end
	local function drag(p)
		if self.dragging == "square" then
			local a, z = sq.AbsolutePosition, sq.AbsoluteSize
			if z.X > 0 and z.Y > 0 then self:setSV((p.X - a.X) / z.X, (p.Y - a.Y) / z.Y) end
		elseif self.dragging == "hue" then
			local a, z = hue.AbsolutePosition, hue.AbsoluteSize
			if z.Y > 0 then self:setHue((p.Y - a.Y) / z.Y) end
		end
	end
	local PRESS = { [Enum.UserInputType.MouseButton1] = true, [Enum.UserInputType.Touch] = true }
	conn(uis.InputBegan, function(inp)
		if inp.KeyCode == Enum.KeyCode.Escape then
			self:close()
		elseif PRESS[inp.UserInputType] then
			local p = point(inp)
			if inside(sq, p) then
				self.dragging = "square"
				drag(p)
			elseif inside(hue, p) then
				self.dragging = "hue"
				drag(p)
			elseif not inside(f, p) then
				self:close()
			end
		end
	end)
	conn(uis.InputChanged, function(inp)
		if self.dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
			drag(point(inp))
		end
	end)
	conn(uis.InputEnded, function(inp)
		if PRESS[inp.UserInputType] then self.dragging = nil end
	end)
	self:show()
	self.startHex = Palette.hex(self.newColor)
	self.ready = true -- (from here a change previews on Classic)
	classic.picker = self
	return self
end

-- sx 0..1 left to right = saturation, sy 0..1 top to bottom = brightness 1 .. 0
function ClassicPicker:setSV(sx, sy)
	self.s = math.clamp(sx, 0, 1)
	self.v = 1 - math.clamp(sy, 0, 1)
	self:show()
end

-- y 0..1 top to bottom = hue 0 .. 1
function ClassicPicker:setHue(y)
	self.h = math.clamp(y, 0, 1)
	if self.h >= 1 then self.h = 0.999999 end
	self:show()
end

-- the box: "#RRGGBB" or "r, g, b"; anything else changes nothing
function ClassicPicker:typed(text)
	local hex = Settings.sanitize(COLOR_DEF, text)
	if hex then
		local h, s, v = Color3.fromHex(hex:sub(2)):ToHSV()
		if s > 0 then self.h = h end -- (a grey has no hue: keep the one shown)
		self.s, self.v = s, v
	end
	self:show()
end

function ClassicPicker:show()
	local col = Color3.fromHSV(self.h, self.s, self.v)
	col = rgb(math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5))
	self.newColor = col
	if not self.frame or not self.frame.Parent then return end
	self.square.BackgroundColor3 = Color3.fromHSV(self.h, 1, 1)
	self.mark.Position = u(self.s, 0, 1 - self.v, 0)
	self.hueMark.Position = u(0.5, 0, self.h, 0)
	self.newHalf.BackgroundColor3 = col
	self.box.Text = Palette.hex(col)
	-- (the colour shows on Classic while picking)
	local hex = Palette.hex(col)
	if self.ready and not self.done and hex ~= (self.lastPreview or self.startHex) then
		self.lastPreview = hex
		self.classic.E.settings:set(self.key, hex)
	end
end

function ClassicPicker:apply()
	local hex = Palette.hex(self.newColor)
	self.done = true
	self.classic.E.settings:set(self.key, hex)
	if self.classic.E.settingsFile then KitPicker.remember(self.classic.E.settingsFile, hex) end
	self:close()
end

-- the setting's default (Auto on a colour that can follow the Main Colour)
function ClassicPicker:reset()
	local def = Settings.byKey[self.key]
	self.done = true
	if def then self.classic.E.settings:set(self.key, def.default) end
	self:close()
end

function ClassicPicker:close()
	-- (closed without Apply or Reset: the old value back)
	if not self.done and self.lastPreview then
		self.done = true
		self.classic.E.settings:set(self.key, self.original)
	end
	for _, off in ipairs(self.offs) do pcall(off) end
	self.offs = {}
	if self.frame then pcall(function() self.frame:Destroy() end) end
	if self.classic.picker == self then self.classic.picker = nil end
end

return ClassicPicker
