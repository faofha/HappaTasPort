-- ================================================================================================
--  ICON  (HappaTAS 3 ui kit): small icons drawn from frames and the one triangle every listed font has
--  (▼, turned by the label's Rotation: -90 = ▶, 90 = ◀; phase 5a measured the fonts live). Kinds: play,
--  back1 (◀|), forward1 (|▶), start (|◀), record (a round dot, the recording colour), pause (two bars),
--  marker (a diamond), chevron (▼), rewind / fastforward (two triangles). Coloured from the theme.
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")

local Icon = {}
Icon.__index = Icon

-- the parts of each kind: { "tri", rotation, x } / { "bar", x, w } / { "dot" } / { "diamond" }, x in 0..1
local SHAPES = {
	play = { { "tri", -90, 0.5 } },
	back1 = { { "tri", 90, 0.4 }, { "bar", 0.82, 0.14 } },
	forward1 = { { "bar", 0.04, 0.14 }, { "tri", -90, 0.6 } },
	start = { { "bar", 0.08, 0.14 }, { "tri", 90, 0.58 } },
	record = { { "dot" } },
	pause = { { "bar", 0.22, 0.2 }, { "bar", 0.58, 0.2 } },
	marker = { { "diamond" } },
	chevron = { { "tri", 0, 0.5 } },
	rewind = { { "tri", 90, 0.3 }, { "tri", 90, 0.7 } },
	fastforward = { { "tri", -90, 0.3 }, { "tri", -90, 0.7 } },
}

function Icon.new(ctx, parent, kind, size)
	local self = K.new(ctx, Icon)
	self.size = size or 12
	local gui = K.frame("Icon", parent)
	gui.Size = UDim2.new(0, self.size, 0, self.size)
	self.gui = gui
	self.parts = {}
	self:setKind(kind)
	K.style(self, function(th) self:paint(th) end)
	return self
end

function Icon:paint(th)
	local c = (self.kind == "record") and th.c.rec or (self.color or th.c.text)
	for _, p in ipairs(self.parts) do
		if p:IsA("TextLabel") then W.set(p, "TextColor3", c) else W.set(p, "BackgroundColor3", c) end
	end
end

-- (rebuilds the parts: only when the kind changes, never per frame)
function Icon:setKind(kind)
	if kind == self.kind then return end
	self.kind = kind
	for _, p in ipairs(self.parts) do p:Destroy() end
	self.parts = {}
	local s = self.size
	for _, sh in ipairs(SHAPES[kind] or {}) do
		local p
		if sh[1] == "tri" then
			p = K.text("TextLabel", "Tri", self.gui)
			p.Text = "▼"
			p.TextSize = s
			p.FontFace = self.ctx.theme.font("bold")
			p.AnchorPoint = Vector2.new(0.5, 0.5)
			p.Position = UDim2.new(sh[3], 0, 0.5, 0)
			p.Size = UDim2.new(0, s, 0, s)
			p.Rotation = sh[2]
		elseif sh[1] == "bar" then
			p = K.frame("Bar", self.gui, Color3.new(1, 1, 1))
			p.Position = UDim2.new(sh[2], 0, 0.15, 0)
			p.Size = UDim2.new(sh[3], 0, 0.7, 0)
		elseif sh[1] == "dot" then
			p = K.frame("Dot", self.gui, Color3.new(1, 1, 1))
			p.AnchorPoint = Vector2.new(0.5, 0.5)
			p.Position = UDim2.new(0.5, 0, 0.5, 0)
			p.Size = UDim2.new(0.7, 0, 0.7, 0)
			K.corner(p, 999)
		else
			p = K.frame("Diamond", self.gui, Color3.new(1, 1, 1))
			p.AnchorPoint = Vector2.new(0.5, 0.5)
			p.Position = UDim2.new(0.5, 0, 0.5, 0)
			p.Size = UDim2.new(0.6, 0, 0.6, 0)
			p.Rotation = 45
		end
		p.ZIndex = self.gui.ZIndex
		self.parts[#self.parts + 1] = p
	end
	if self.ctx.theme then self:paint(self.ctx.theme) end
end

-- a fixed colour (nil: the theme's text colour)
function Icon:setColor(c)
	self.color = c
	self:paint(self.ctx.theme)
end

function Icon:destroy() K.destroy(self) end

return Icon
