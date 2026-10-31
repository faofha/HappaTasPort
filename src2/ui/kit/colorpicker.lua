-- ================================================================================================
--  COLORPICKER  (HappaTAS 3 ui kit): the colour picker (spec 8.3, the mockup): a saturation / value square,
--  a hue bar, the old and new colour side by side, HEX / RGB / HSV boxes (typed values checked: HEX through
--  the settings schema, R G B 0-255, H 0-360, S V 0-100; anything else is refused), the recent colours,
--  Cancel / Apply. Apply puts the colour first in the recent colours (at most 8, Settings3.json).
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Popover = import("ui/kit/popover")
local Field = import("ui/kit/field")
local Button = import("ui/kit/button")
local Segmented = import("ui/kit/segmented")
local Settings = import("engine/settings")

local ColorPicker = {}
ColorPicker.__index = ColorPicker

local SQ_W, SQ_H, HUE_W, MAX_RECENT = 180, 150, 16, 8

local function hexOf(c) return "#" .. c:ToHex():upper() end
local function toInt(text, lo, hi)
	local n = tonumber(text)
	if not n or n ~= n or n % 1 ~= 0 or n < lo or n > hi then return nil end
	return n
end

function ColorPicker.open(ctx, anchor, opts)
	local pop = Popover.open(ctx, anchor, 268, 336)
	local self = setmetatable({ ctx = pop.ctx, pop = pop, frame = pop.frame, onApply = opts.onApply, fields = {}, recent = {} }, ColorPicker)
	local c0 = Color3.fromHex((Settings.sanitize(Settings.byKey.accentColor, opts.value) or "#FFFFFF"):sub(2))
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
	mark.Size, mark.AnchorPoint, mark.ZIndex = UDim2.new(0, 10, 0, 10), Vector2.new(0.5, 0.5), 4
	K.corner(mark, 5)
	K.stroke(mark, Color3.new(1, 1, 1), 0, 2)
	self.square, self.mark = sq, mark
	-- the hue bar, top to bottom
	local hue = K.frame("Hue", f, Color3.new(1, 1, 1))
	hue.Position, hue.Size, hue.ZIndex = UDim2.new(0, 14 + SQ_W + 10, 0, 14), UDim2.new(0, HUE_W, 0, SQ_H), 3
	K.corner(hue, 4)
	local keys = {}
	for i = 0, 6 do keys[#keys + 1] = ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i / 6) % 1, 1, 1)) end
	local hg = Instance.new("UIGradient")
	hg.Rotation = 90
	hg.Color = ColorSequence.new(keys)
	hg.Parent = hue
	local hueMark = K.frame("HueMark", hue, Color3.new(1, 1, 1))
	hueMark.Size, hueMark.AnchorPoint, hueMark.ZIndex = UDim2.new(1, 4, 0, 3), Vector2.new(0.5, 0.5), 4
	self.hueBar, self.hueMark = hue, hueMark
	-- old / new halves
	local old = K.frame("Old", f, c0)
	old.Position, old.Size, old.ZIndex = UDim2.new(0, 14 + SQ_W + HUE_W + 20, 0, 14), UDim2.new(0, 34, 0, 36), 3
	local new = K.frame("New", f, c0)
	new.Position, new.Size, new.ZIndex = UDim2.new(0, 14 + SQ_W + HUE_W + 20, 0, 50), UDim2.new(0, 34, 0, 36), 3
	self.oldHalf, self.newHalf = old, new
	local pctx = pop.ctx
	pop:add({ gui = sq, onPress = function(p) self:fromSquare(p) end, onDrag = function(p) self:fromSquare(p) end }, 5)
	pop:add({ gui = hue, onPress = function(p) self:fromHue(p) end, onDrag = function(p) self:fromHue(p) end }, 5)
	-- tabs and boxes
	local tabs = Segmented.new(pctx, f, { options = { "HEX", "RGB", "HSV" }, z = 5 })
	tabs.gui.Position = UDim2.new(0, 14, 0, 176)
	tabs.onChange = function(t) self:setTab(t) end
	self.tabs = tabs
	local function field(name, x, w, commit, label)
		local fd = Field.new(pctx, f, { w = w, number = true, z = 5, onCommit = commit })
		fd.gui.Position = UDim2.new(0, x, 0, 210)
		fd.gui.ZIndex = 3
		if label then
			local l = K.label(fd, f, label, "bold", 10.5, true)
			l.Position, l.Size = UDim2.new(0, x, 0, 236), UDim2.new(0, w, 0, 14)
			fd.caption = l
		end
		self.fields[name] = fd
		return fd
	end
	field("HEX", 14, 120, function(t)
		local hex = Settings.sanitize(Settings.byKey.accentColor, t)
		if not hex then self:refreshFields() return false end
		self:setColor(Color3.fromHex(hex:sub(2)))
		return true
	end, "HEX")
	for i, ch in ipairs({ "R", "G", "B" }) do
		field(ch, 14 + (i - 1) * 64, 56, function(t)
			local n = toInt(t, 0, 255)
			if not n then self:refreshFields() return false end
			local r, g, b = self:rgb()
			if ch == "R" then r = n elseif ch == "G" then g = n else b = n end
			self:setColor(Color3.fromRGB(r, g, b))
			return true
		end, ch)
	end
	for i, ch in ipairs({ "H", "S", "V" }) do
		field(ch, 14 + (i - 1) * 64, 56, function(t)
			local n = toInt(t, 0, ch == "H" and 360 or 100)
			if not n then self:refreshFields() return false end
			if ch == "H" then self.h = (n / 360) % 1 elseif ch == "S" then self.s = n / 100 else self.v = n / 100 end
			self:show()
			return true
		end, ch)
	end
	-- recent colours
	local rec = pctx.E.settingsFile:getUi().recentColors
	for i, hex in ipairs(rec) do
		local sw = K.frame("Recent", f, Color3.fromHex(hex:sub(2)))
		sw.Position, sw.Size, sw.ZIndex = UDim2.new(0, 14 + (i - 1) * 26, 0, 262), UDim2.new(0, 20, 0, 20), 3
		K.corner(sw, 10)
		self.recent[i] = sw
		pop:add({ gui = sw, onRelease = function(_, clicked) if clicked then self:setColor(Color3.fromHex(hex:sub(2))) end end }, 5)
	end
	local cancel = Button.new(pctx, f, { text = "Cancel", kind = "plain", z = 5 })
	cancel.gui.AnchorPoint, cancel.gui.Position = Vector2.new(1, 1), UDim2.new(1, -96, 1, -14)
	cancel.onClick = function() self:cancel() end
	local apply = Button.new(pctx, f, { text = "Apply", kind = "primary", z = 5 })
	apply.gui.AnchorPoint, apply.gui.Position = Vector2.new(1, 1), UDim2.new(1, -14, 1, -14)
	apply.onClick = function() self:apply() end
	self.controls = { tabs, cancel, apply }
	for _, fd in pairs(self.fields) do self.controls[#self.controls + 1] = fd end
	pop.onClose = function() for _, c in ipairs(self.controls) do c:destroy() end end
	self:setTab("HEX")
	self:show()
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

function ColorPicker:refreshFields()
	local r, g, b = self:rgb()
	local h, s, v = self:hsv()
	local vals = { HEX = self:hex(), R = r, G = g, B = b, H = h, S = s, V = v }
	for k, fd in pairs(self.fields) do fd:set(tostring(vals[k])) end
end

function ColorPicker:show()
	W.set(self.square, "BackgroundColor3", Color3.fromHSV(self.h, 1, 1))
	W.set(self.mark, "Position", UDim2.new(self.s, 0, 1 - self.v, 0))
	W.set(self.hueMark, "Position", UDim2.new(0.5, 0, self.h, 0))
	W.set(self.newHalf, "BackgroundColor3", self:color())
	self:refreshFields()
end

function ColorPicker:setTab(tab)
	self.tab = tab
	local on = { HEX = { HEX = true }, RGB = { R = true, G = true, B = true }, HSV = { H = true, S = true, V = true } }
	for k, fd in pairs(self.fields) do
		local vis = on[tab][k] == true
		W.set(fd.gui, "Visible", vis)
		if fd.caption then W.set(fd.caption, "Visible", vis) end
	end
	self.tabs:set(tab)
end

function ColorPicker:apply()
	local hex = self:hex()
	local sf = self.ctx.E.settingsFile
	local data = sf:getUi()
	local list = { hex }
	for _, c in ipairs(data.recentColors) do
		if c ~= hex and #list < MAX_RECENT then list[#list + 1] = c end
	end
	data.recentColors = list
	sf:setUi(data)
	self.pop:close()
	if self.onApply then self.onApply(hex) end
end

function ColorPicker:cancel() self.pop:close() end

return ColorPicker
