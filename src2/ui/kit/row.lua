-- ================================================================================================
--  ROW  (HappaTAS 3 ui kit): one setting row (the mockup's .row): the name with its short explanation
--  under it on the left, the control flush right (18 px in), and the amber ↺ reset button just left of
--  the control (7 px) while the value isn't the default. onReset() when it's clicked.
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Button = import("ui/kit/button")

local Row = {}
Row.__index = Row

local PAD, GAP = 18, 7

function Row.new(ctx, parent, opts)
	local self = K.new(ctx, Row)
	local h = opts.desc and 44 or 32
	self.h = h
	local gui = K.frame("Row", parent)
	gui.Size = UDim2.new(1, 0, 0, h)
	self.gui = gui
	local name = K.label(self, gui, opts.name, "text", 13)
	name.Position = UDim2.new(0, PAD, 0, opts.desc and 6 or 0)
	name.Size = UDim2.new(0.62, -PAD, 0, opts.desc and 18 or h)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	self.name = name
	if opts.desc then
		local d = K.label(self, gui, opts.desc, "text", 10.5, true)
		d.Position = UDim2.new(0, PAD, 0, 24)
		d.Size = UDim2.new(0.62, -PAD, 0, 14)
		d.TextXAlignment = Enum.TextXAlignment.Left
		d.TextTruncate = Enum.TextTruncate.AtEnd
		self.desc = d
	end
	self.control = opts.control
	if opts.control then
		local cg = opts.control.gui
		cg.AnchorPoint = Vector2.new(1, 0.5)
		cg.Position = UDim2.new(1, -PAD, 0.5, 0)
		cg.Parent = gui
	end
	local reset = Button.new(ctx, gui, { kind = "reset", z = opts.z })
	reset.gui.AnchorPoint = Vector2.new(1, 0.5)
	reset.gui.Visible = false
	reset.onClick = function() if self.onReset then self.onReset() end end
	self.reset = reset
	self:place()
	return self
end

-- the reset button's place follows the control's width
function Row:place()
	local cw = self.control and self.control.gui.AbsoluteSize.X / K.scale(self) or 0
	if cw == 0 and self.control then cw = self.control.gui.Size.X.Offset end
	W.set(self.reset.gui, "Position", UDim2.new(1, -PAD - cw - GAP, 0.5, 0))
end

function Row:setReset(on)
	self:place()
	W.set(self.reset.gui, "Visible", on == true)
end

function Row:destroy()
	self.reset:destroy()
	if self.control and self.control.destroy then self.control:destroy() end
	K.destroy(self)
end

return Row
