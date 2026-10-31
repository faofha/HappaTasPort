-- ================================================================================================
--  TOGGLE  (HappaTAS 3 ui kit): the mockup's switch: 44 x 26, accent when on, a clear bright glass knob
--  (22 px, white with a crisp rim). value = true / false; set(v) shows a value, onChange(v) on a click.
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")

local Toggle = {}
Toggle.__index = Toggle

function Toggle.new(ctx, parent, opts)
	local self = K.new(ctx, Toggle)
	self.value = false
	local gui = K.frame("Toggle", parent, Color3.new(1, 1, 1))
	gui.Size = UDim2.new(0, 44, 0, 26)
	K.corner(gui, 13)
	self.gui = gui
	local knob = K.frame("Knob", gui, Color3.new(1, 1, 1))
	knob.Size = UDim2.new(0, 22, 0, 22)
	knob.Position = UDim2.new(0, 2, 0, 2)
	K.corner(knob, 11)
	K.stroke(knob, Color3.new(1, 1, 1), 0.05, 1)
	K.gradient(knob, Color3.new(1, 1, 1), Color3.fromHex("ECF2FF"))
	self.knob = knob
	K.style(self, function() self:show(false) end)
	K.rect(self, { onRelease = function(_, clicked)
		if not clicked then return end
		self.value = not self.value
		self:show(true)
		if self.onChange then self.onChange(self.value) end
	end }, opts and opts.z)
	return self
end

function Toggle:show(animate)
	local th = self.ctx.theme
	W.set(self.gui, "BackgroundColor3", self.value and th.c.accent or Color3.new(1, 1, 1))
	W.set(self.gui, "BackgroundTransparency", self.value and 0 or 0.78)
	local goal = UDim2.new(0, self.value and 20 or 2, 0, 2)
	if animate then self.ctx.tween:play(self.knob, { Position = goal }) else W.set(self.knob, "Position", goal) end
end

function Toggle:set(v)
	v = v == true or v == 1
	if v == self.value then return end
	self.value = v
	self:show(false)
end

Toggle.destroy = K.destroy

return Toggle
