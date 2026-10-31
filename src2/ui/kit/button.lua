-- ================================================================================================
--  BUTTON  (HappaTAS 3 ui kit): a pill button. kind "primary" (accent, the mockup's .bt.pri), "plain" (calm
--  glass) or "reset" (the 24 px amber ← shown next to a setting that isn't its default). onClick().
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Layout = import("ui/layout")

local Button = {}
Button.__index = Button

function Button.new(ctx, parent, opts)
	opts = opts or {}
	local self = K.new(ctx, Button)
	self.kind = opts.kind or "plain"
	local gui = K.frame("Button", parent, Color3.new(1, 1, 1))
	self.gui = gui
	self.cornerObj = K.corner(gui)
	if self.kind == "reset" then
		gui.Size = UDim2.new(0, 24, 0, 24)
		K.gradient(gui, Color3.fromHex("FFC86E"), Color3.fromHex("F0A032"))
		local l = K.label(self, gui, "←", "bold", 12)
		l.Size = UDim2.new(1, 0, 1, 0)
		l.TextColor3 = Color3.fromHex("2A1C00")
		self.label = l
	else
		local l = K.label(self, gui, opts.text or "", "bold", 11.5)
		l.Size = UDim2.new(1, 0, 1, 0)
		self.label = l
	end
	self.restyle = function(th)
		if self.kind == "reset" then
			W.set(self.cornerObj, "CornerRadius", UDim.new(0, 12))
			W.set(self.label, "TextColor3", Color3.fromHex("2A1C00"))
			return
		end
		W.set(self.cornerObj, "CornerRadius", UDim.new(0, th.corner("control")))
		if self.kind == "primary" then
			W.set(gui, "BackgroundColor3", th.c.accent)
			W.set(gui, "BackgroundTransparency", 0)
		else
			W.set(gui, "BackgroundColor3", Color3.new(1, 1, 1))
			W.set(gui, "BackgroundTransparency", 0.88)
		end
		local w = opts.w or (Layout.textWidth(self.label.Text, th.font("bold"), th.size(11.5), gui) + 26)
		W.set(gui, "Size", UDim2.new(0, w, 0, opts.h or 24))
	end
	K.style(self, self.restyle)
	K.rect(self, { onRelease = function(_, clicked) if clicked and self.onClick then self.onClick() end end,
		onHover = function(on) if self.kind ~= "reset" then W.set(self.label, "TextTransparency", on and 0 or 0.08) end end }, opts.z)
	return self
end

function Button:setText(t)
	self.label.Text = t
	self.restyle(self.ctx.theme)
end

-- "primary" / "plain" (the Dock lights the buttons of open windows)
function Button:setKind(kind)
	if kind == self.kind or self.kind == "reset" then return end
	self.kind = kind
	self.restyle(self.ctx.theme)
end

Button.destroy = K.destroy

return Button
