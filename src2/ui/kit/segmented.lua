-- ================================================================================================
--  SEGMENTED  (HappaTAS 3 ui kit): a pill of options; the selected one sits in a gentle glass bubble that
--  slides to the new choice (the mockup's .seg). value = the option; onChange(option) on a click.
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Layout = import("ui/layout")

local Segmented = {}
Segmented.__index = Segmented

local PAD, SEG_PAD = 2, 11

function Segmented.new(ctx, parent, opts)
	local self = K.new(ctx, Segmented)
	self.options = opts.options
	self.value = opts.options[1]
	local gui = K.frame("Segmented", parent, Color3.new(1, 1, 1))
	gui.BackgroundTransparency = 0.88
	self.gui = gui
	self.cornerObj = K.corner(gui)
	local bubble = K.frame("Bubble", gui, Color3.new(1, 1, 1))
	bubble.BackgroundTransparency = 0.72
	bubble.ZIndex = 1
	self.bubbleCorner = K.corner(bubble)
	K.stroke(bubble, Color3.new(1, 1, 1), 0.82, 1)
	self.bubble = bubble
	self.segments = {}
	for i, o in ipairs(opts.options) do
		local l = K.label(self, gui, o, "text", 11.5)
		l.ZIndex = 2
		self.segments[i] = l
		K.rect(self, { gui = l, onRelease = function(_, clicked)
			if not clicked or self.value == o then return end
			self.value = o
			self:show(true)
			if self.onChange then self.onChange(o) end
		end }, opts.z)
	end
	K.style(self, function(th)
		local r = th.corner("control")
		W.set(self.cornerObj, "CornerRadius", UDim.new(0, r))
		W.set(self.bubbleCorner, "CornerRadius", UDim.new(0, r))
		local items, h = {}, 24
		for _, l in ipairs(self.segments) do
			local w = Layout.textWidth(l.Text, th.font("text"), th.size(11.5), gui) + SEG_PAD * 2
			W.set(l, "Size", UDim2.new(0, w, 0, h - PAD * 2))
			items[#items + 1] = { gui = l, w = w }
		end
		local total = Layout.hstack(items, { pad = PAD, y = PAD })
		W.set(gui, "Size", UDim2.new(0, total, 0, h))
		self:show(false)
	end)
	return self
end

function Segmented:show(animate)
	local i = table.find(self.options, self.value) or 1
	local seg = self.segments[i]
	local goal = { Position = seg.Position, Size = seg.Size }
	for j, l in ipairs(self.segments) do W.set(l, "TextTransparency", (j == i) and 0 or 0.22) end
	if animate then self.ctx.tween:play(self.bubble, goal) else
		W.set(self.bubble, "Position", goal.Position)
		W.set(self.bubble, "Size", goal.Size)
	end
end

function Segmented:set(v)
	if v == self.value or not table.find(self.options, v) then return end
	self.value = v
	self:show(false)
end

Segmented.destroy = K.destroy

return Segmented
