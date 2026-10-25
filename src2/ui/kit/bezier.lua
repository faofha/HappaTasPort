-- ================================================================================================
--  BEZIER  (HappaTAS 3 ui kit): the Custom easing editor (spec 8.4): a box with the curve, two handles
--  that write bezierX1 / bezierY1 and bezierX2 / bezierY2 (x 0..1, y -1..2), the four values as boxes,
--  presets (Ease, Ease in, Ease out, Overshoot) and a Preview: a dot runs along a track with the curve
--  and the Animation length.
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Field = import("ui/kit/field")
local Button = import("ui/kit/button")
local Tween = import("ui/tween")
local Settings = import("engine/settings")

local Bezier = {}
Bezier.__index = Bezier

local BOX, DOTS, HANDLE, TRACK_W, DOT = 120, 24, 12, 160, 12
local KEYS = { "bezierX1", "bezierY1", "bezierX2", "bezierY2" }
local PRESETS = {
	{ "Ease", { 0.25, 0.1, 0.25, 1 } }, { "Ease in", { 0.42, 0, 1, 1 } },
	{ "Ease out", { 0, 0, 0.58, 1 } }, { "Overshoot", { 0.34, 1.56, 0.64, 1 } },
}

local function fmt(v) return (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")) end

function Bezier.new(ctx, parent)
	local self = K.new(ctx, Bezier)
	local s = ctx.E.settings
	self.s = s
	local gui = K.frame("Bezier", parent)
	gui.Size = UDim2.new(0, BOX + 12 + TRACK_W, 0, BOX + 72)
	self.gui = gui
	local box = K.frame("Curve", gui, Color3.new(0, 0, 0))
	box.BackgroundTransparency = 0.75
	box.Size = UDim2.new(0, BOX, 0, BOX)
	K.corner(box, 8)
	self.box = box
	self.dots = {}
	for i = 1, DOTS do
		local d = K.frame("Dot", box, Color3.new(1, 1, 1))
		d.Size, d.AnchorPoint = UDim2.new(0, 3, 0, 3), Vector2.new(0.5, 0.5)
		K.corner(d, 2)
		self.dots[i] = d
	end
	self.handles = {}
	for i = 1, 2 do
		local hnd = K.frame("Handle" .. i, box, Color3.new(1, 1, 1))
		hnd.Size, hnd.AnchorPoint, hnd.ZIndex = UDim2.new(0, HANDLE, 0, HANDLE), Vector2.new(0.5, 0.5), 3
		K.corner(hnd, HANDLE / 2)
		K.stroke(hnd, Color3.new(1, 1, 1), 0, 1)
		self.handles[i] = hnd
		K.rect(self, { gui = hnd, onDrag = function(p)
			local a = box.AbsolutePosition
			local x = math.clamp((p.X - a.X) / BOX, 0, 1)
			local y = math.clamp(1 - (p.Y - a.Y) / BOX, -1, 2)
			s:set(KEYS[i * 2 - 1], math.floor(x * 100 + 0.5) / 100)
			s:set(KEYS[i * 2], math.floor(y * 100 + 0.5) / 100)
		end }, 3)
	end
	K.style(self, function(th)
		for _, d in ipairs(self.dots) do W.set(d, "BackgroundColor3", th.c.accent) end
		for _, hnd in ipairs(self.handles) do W.set(hnd, "BackgroundColor3", th.c.text) end
	end)
	self.fields = {}
	for i, key in ipairs(KEYS) do
		local fd = Field.new(ctx, gui, { w = 52, number = true, onCommit = function(t)
			local v = Settings.sanitize(Settings.byKey[key], t)
			if v == nil then return false end
			s:set(key, v)
			self:show()
			return true
		end })
		fd.gui.Position = UDim2.new(0, (i - 1) * 58, 0, BOX + 8)
		local cap = K.label(self, gui, ({ "x1", "y1", "x2", "y2" })[i], "text", 10, true)
		cap.Position, cap.Size = UDim2.new(0, (i - 1) * 58, 0, BOX + 34), UDim2.new(0, 52, 0, 12)
		self.fields[i] = fd
	end
	self.buttons = {}
	for i, p in ipairs(PRESETS) do
		local b = Button.new(ctx, gui, { text = p[1], kind = "plain" })
		b.gui.Position = UDim2.new(0, BOX + 12, 0, (i - 1) * 28)
		b.onClick = function() for j, key in ipairs(KEYS) do s:set(key, p[2][j]) end end
		self.buttons[i] = b
	end
	local preview = Button.new(ctx, gui, { text = "Preview", kind = "primary" })
	preview.gui.Position = UDim2.new(0, BOX + 12, 0, 4 * 28 + 4)
	preview.onClick = function() self:preview() end
	self.buttons[#self.buttons + 1] = preview
	local track = K.frame("Track", gui, Color3.new(1, 1, 1))
	track.BackgroundTransparency = 0.82
	track.Position, track.Size = UDim2.new(0, BOX + 12, 0, BOX + 8), UDim2.new(0, TRACK_W, 0, DOT)
	K.corner(track, DOT / 2)
	local dot = K.frame("PreviewDot", track, Color3.new(1, 1, 1))
	dot.Size = UDim2.new(0, DOT, 0, DOT)
	K.corner(dot, DOT / 2)
	self.track, self.dot = track, dot
	for _, key in ipairs(KEYS) do self.offs[#self.offs + 1] = s:changed(key, function() self:show() end) end
	self:show()
	return self
end

function Bezier:show()
	local s = self.s
	local x1, y1, x2, y2 = s:get("bezierX1"), s:get("bezierY1"), s:get("bezierX2"), s:get("bezierY2")
	for i = 1, DOTS do
		local t = (i - 1) / (DOTS - 1)
		local u = 1 - t
		local x = 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t
		local y = 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t
		W.set(self.dots[i], "Position", UDim2.new(0, x * BOX, 0, (1 - y) * BOX))
	end
	W.set(self.handles[1], "Position", UDim2.new(0, x1 * BOX, 0, (1 - y1) * BOX))
	W.set(self.handles[2], "Position", UDim2.new(0, x2 * BOX, 0, (1 - y2) * BOX))
	for i, key in ipairs(KEYS) do self.fields[i]:set(fmt(s:get(key))) end
end

function Bezier:preview()
	local s = self.s
	W.set(self.dot, "Position", UDim2.new(0, 0, 0, 0))
	local far = self.track.AbsoluteSize.X - self.dot.AbsoluteSize.X
	self.ctx.tween:play(self.dot, { Position = UDim2.new(0, far, 0, 0) }, { curve = Tween.curve(s), length = Tween.length(s) })
end

function Bezier:destroy()
	for _, f in ipairs(self.fields) do f:destroy() end
	for _, b in ipairs(self.buttons) do b:destroy() end
	K.destroy(self)
end

return Bezier
