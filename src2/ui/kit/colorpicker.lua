-- ================================================================================================
--  COLORPICKER  (HappaTAS 3 ui kit, V3.1): the colour picker. A saturation / value square and a hue bar
--  (press and drag), the old and new colour side by side, one HEX box (it takes "#RRGGBB", "RRGGBB" or
--  "r, g, b"; anything else is refused), 8 quick colours, the recent colours, Reset to default, Cancel and
--  Apply. While picking, opts.onPreview(hex) shows the colour live; Cancel, Esc or a press outside put the
--  old value back (onPreview(old)). Apply puts the colour first in the recent colours (at most 8,
--  Settings3.json) and reports onApply(hex); Reset to default reports onApply(opts.default).
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Popover = import("ui/kit/popover")
local Field = import("ui/kit/field")
local Button = import("ui/kit/button")
local Settings = import("engine/settings")

local ColorPicker = {}
ColorPicker.__index = ColorPicker

-- the quick colours (the Classic picker shows them too)
ColorPicker.QUICK = { "#3FB950", "#3F7CF0", "#A371F7", "#DB61A2", "#F85149", "#F0883E", "#E3B341", "#FFFFFF" }
ColorPicker.MAX_RECENT = 8

local PW, PH = 300, 372
local SQ_W, SQ_H, HUE_W, SW, STEP = 238, 150, 22, 26, 30
local COLOR_DEF = { kind = "color" }

local function hexOf(c) return "#" .. c:ToHex():upper() end
local function fromHex(hex) return Color3.fromHex(hex:sub(2)) end

-- the recent colours with hex first (at most MAX_RECENT)
function ColorPicker.remember(settingsFile, hex)
	local data = settingsFile:getUi()
	local list = { hex }
	for _, c in ipairs(data.recentColors or {}) do
		if c ~= hex and #list < ColorPicker.MAX_RECENT then list[#list + 1] = c end
	end
	data.recentColors = list
	settingsFile:setUi(data)
end

function ColorPicker.open(ctx, anchor, opts)
	local pop = Popover.open(ctx, anchor, PW, PH)
	local self = setmetatable({ ctx = pop.ctx, pop = pop, frame = pop.frame, onApply = opts.onApply,
		onPreview = opts.onPreview, default = opts.default, quick = {}, recent = {}, rects = {}, offs = {} }, ColorPicker)
	self.original = Settings.sanitize(COLOR_DEF, opts.value) or "#FFFFFF"
	local c0 = fromHex(self.original)
	self.h, self.s, self.v = c0:ToHSV()
	local f = pop.frame
	-- the square: the hue at full strength, white to the left, black to the bottom
	local sq = K.frame("Square", f, Color3.new(1, 0, 0))
	sq.Position, sq.Size = UDim2.new(0, 14, 0, 14), UDim2.new(0, SQ_W, 0, SQ_H)
	sq.ZIndex = 3
	K.corner(sq, 6)
	local white = K.frame("White", sq, Color3.new(1, 1, 1))
	white.Size, white.ZIndex = UDim2.new(1, 0, 1, 0), 3
	local wg = Instance.new("UIGradient")
	wg.Transparency = NumberSequence.new(0, 1)
	wg.Parent = white
	K.corner(white, 6)
	local black = K.frame("Black", sq, Color3.new(0, 0, 0))
	black.Size, black.ZIndex = UDim2.new(1, 0, 1, 0), 3
	local bg = Instance.new("UIGradient")
	bg.Rotation = 90
	bg.Transparency = NumberSequence.new(1, 0)
	bg.Parent = black
	K.corner(black, 6)
	local mark = K.frame("Mark", sq)
	mark.Size, mark.AnchorPoint, mark.ZIndex = UDim2.new(0, 12, 0, 12), Vector2.new(0.5, 0.5), 4
	K.corner(mark, 6)
	K.stroke(mark, Color3.new(1, 1, 1), 0, 2)
	self.square, self.mark = sq, mark
	-- the hue bar, top to bottom
	local hue = K.frame("Hue", f, Color3.new(1, 1, 1))
	hue.Position, hue.Size, hue.ZIndex = UDim2.new(0, 14 + SQ_W + 10, 0, 14), UDim2.new(0, HUE_W, 0, SQ_H), 3
	K.corner(hue, 5)
	local keys = {}
	for i = 0, 6 do keys[#keys + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i / 6) % 1, 1, 1)) end
	local hg = Instance.new("UIGradient")
	hg.Rotation = 90
	hg.Color = ColorSequence.new(keys)
	hg.Parent = hue
	local hueMark = K.frame("HueMark", hue, Color3.new(1, 1, 1))
	hueMark.Size, hueMark.AnchorPoint, hueMark.ZIndex = UDim2.new(1, 6, 0, 4), Vector2.new(0.5, 0.5), 4
	self.hueBar, self.hueMark = hue, hueMark
	pop:add({ gui = sq, onPress = function(p) self:fromSquare(p) end, onDrag = function(p) self:fromSquare(p) end }, 5)
	pop:add({ gui = hue, onPress = function(p) self:fromHue(p) end, onDrag = function(p) self:fromHue(p) end }, 5)
	-- old / new, the HEX box
	local y = 14 + SQ_H + 12
	local old = K.frame("Old", f, c0)
	old.Position, old.Size, old.ZIndex = UDim2.new(0, 14, 0, y), UDim2.new(0, 36, 0, 28), 3
	local new = K.frame("New", f, c0)
	new.Position, new.Size, new.ZIndex = UDim2.new(0, 50, 0, y), UDim2.new(0, 36, 0, 28), 3
	self.oldHalf, self.newHalf = old, new
	local pctx = pop.ctx
	local cap = K.label(self, f, "HEX", "bold", 11, true)
	cap.Position, cap.Size = UDim2.new(0, 98, 0, y), UDim2.new(0, 30, 0, 28)
	self.box = Field.new(pctx, f, { w = PW - 14 - 132, z = 5, placeholder = "#RRGGBB or r, g, b", onCommit = function(t)
		local hex = Settings.sanitize(COLOR_DEF, t)
		if not hex then self:refreshBox() return false end
		self:setColor(fromHex(hex))
		return true
	end })
	self.box.gui.Position = UDim2.new(0, 132, 0, y + 2)
	self.box.gui.ZIndex = 3
	-- the quick and the recent colours
	local function row(list, into, title, ry)
		local l = K.label(self, f, title, "bold", 10.5, true)
		l.Position, l.Size = UDim2.new(0, 14, 0, ry), UDim2.new(0, 100, 0, 14)
		for i, hex in ipairs(list) do
			local sw = K.frame(title, f, fromHex(hex))
			sw.Position, sw.Size, sw.ZIndex = UDim2.new(0, 14 + (i - 1) * STEP, 0, ry + 16), UDim2.new(0, SW, 0, SW), 3
			K.corner(sw, SW / 2)
			K.stroke(sw, Color3.new(1, 1, 1), 0.7, 1)
			into[i] = sw
			pop:add({ gui = sw, onRelease = function(_, clicked) if clicked then self:setColor(fromHex(hex)) end end }, 5)
		end
	end
	row(ColorPicker.QUICK, self.quick, "Quick", y + 38)
	row(pctx.E.settingsFile:getUi().recentColors or {}, self.recent, "Recent", y + 84)
	-- the buttons
	local cancel = Button.new(pctx, f, { text = "Cancel", kind = "plain", z = 5 })
	cancel.gui.AnchorPoint, cancel.gui.Position = Vector2.new(1, 1), UDim2.new(1, -86, 1, -14)
	cancel.onClick = function() self:cancel() end
	local apply = Button.new(pctx, f, { text = "Apply", kind = "primary", z = 5 })
	apply.gui.AnchorPoint, apply.gui.Position = Vector2.new(1, 1), UDim2.new(1, -14, 1, -14)
	apply.onClick = function() self:apply() end
	self.cancelButton, self.applyButton = cancel, apply
	self.controls = { cancel, apply, self.box }
	if self.default then
		local reset = Button.new(pctx, f, { text = "Reset to default", kind = "plain", z = 5 })
		reset.gui.AnchorPoint, reset.gui.Position = Vector2.new(0, 1), UDim2.new(0, 14, 1, -14)
		reset.onClick = function() self:reset() end
		self.resetButton = reset
		self.controls[#self.controls + 1] = reset
	end
	pop.onClose = function()
		for _, c in ipairs(self.controls) do c:destroy() end
		K.destroy(self)
		-- (closed without Apply: the old colour back)
		if not self.done and self.previewed and self.onPreview then self.onPreview(self.original) end
	end
	self:show(true)
	return self
end

function ColorPicker:color() return Color3.fromHSV(self.h, self.s, self.v) end
function ColorPicker:hex() return hexOf(self:color()) end
function ColorPicker:rgb()
	local c = self:color()
	return math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)
end
function ColorPicker:hsv()
	return math.floor(self.h * 360 + 0.5), math.floor(self.s * 100 + 0.5), math.floor(self.v * 100 + 0.5)
end

function ColorPicker:setColor(c)
	local h, s, v = c:ToHSV()
	-- (a grey has no hue: keep the one shown)
	if s > 0 then self.h = h end
	self.s, self.v = s, v
	self:show()
end

function ColorPicker:fromSquare(p)
	local sq = self.square
	local a, s = sq.AbsolutePosition, sq.AbsoluteSize
	self.s = math.clamp((p.X - a.X) / s.X, 0, 1)
	self.v = 1 - math.clamp((p.Y - a.Y) / s.Y, 0, 1)
	self:show()
end

function ColorPicker:fromHue(p)
	local hb = self.hueBar
	self.h = math.clamp((p.Y - hb.AbsolutePosition.Y) / hb.AbsoluteSize.Y, 0, 1)
	if self.h >= 1 then self.h = 0.999999 end
	self:show()
end

function ColorPicker:refreshBox() self.box:set(self:hex()) end

-- first: the picker just opened (nothing to preview yet)
function ColorPicker:show(first)
	W.set(self.square, "BackgroundColor3", Color3.fromHSV(self.h, 1, 1))
	W.set(self.mark, "Position", UDim2.new(self.s, 0, 1 - self.v, 0))
	W.set(self.hueMark, "Position", UDim2.new(0.5, 0, self.h, 0))
	W.set(self.newHalf, "BackgroundColor3", self:color())
	self:refreshBox()
	if not first and self.onPreview and not self.done then
		local hex = self:hex()
		if hex ~= self.lastPreview then
			self.lastPreview = hex
			self.previewed = true
			self.onPreview(hex)
		end
	end
end

function ColorPicker:apply()
	local hex = self:hex()
	self.done = true
	ColorPicker.remember(self.ctx.E.settingsFile, hex)
	self.pop:close()
	if self.onApply then self.onApply(hex) end
end

function ColorPicker:reset()
	if not self.default then return end
	self.done = true
	self.pop:close()
	if self.onApply then self.onApply(self.default) end
end

function ColorPicker:cancel() self.pop:close() end

return ColorPicker
