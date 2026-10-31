-- ================================================================================================
--  TOAST  (HappaTAS 3 ui): short status messages at the bottom centre, 96 px above the bottom of the
--  screen: the bus's "status" (text, isError) and "moduleDisabled" (a module switched off after its errors,
--  spec 10). At most 3 at a time (the oldest goes first), the newest at the bottom; 3 s each, errors 6 s.
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Glass = import("ui/kit/glass")
local Layout = import("ui/layout")

local Toast = {}
Toast.__index = Toast

local MAX, H, GAP, BOTTOM, ZINDEX = 3, 32, 6, 96, 400000

function Toast.new(ui)
	local self = setmetatable({ ui = ui, items = {}, offs = {} }, Toast)
	local bus = ui.E.bus
	self.offs[#self.offs + 1] = bus:on("status", function(text, isError) self:add(tostring(text), isError == true) end)
	self.offs[#self.offs + 1] = bus:on("moduleDisabled", function(module)
		self:add(tostring(module) .. " was switched off after errors", true)
	end)
	ui.life:own(function() self:destroy() end)
	return self
end

function Toast:add(text, isError)
	if #self.items >= MAX then self:remove(self.items[1]) end
	local th = self.ui.theme
	local gui = K.frame("Toast", self.ui.root.layer)
	gui.AnchorPoint = Vector2.new(0.5, 0)
	gui.ZIndex = ZINDEX
	local glass = Glass.panel(th, gui, { cornerKind = "control", passThrough = true })
	local label = K.text("TextLabel", "Text", glass.panel)
	label.Text = text
	label.FontFace = th.font("text")
	label.TextSize = th.size(12.5)
	label.TextColor3 = isError and th.c.rec or th.c.text
	label.ZIndex = 2
	label.Size = UDim2.new(1, 0, 1, 0)
	local w = Layout.textWidth(text, th.font("text"), th.size(12.5), gui) + 36
	gui.Size = UDim2.new(0, w, 0, H)
	local item = { text = text, gui = gui, glass = glass }
	self.items[#self.items + 1] = item
	self:layout()
	task.delay(isError and 6 or 3, function() self:remove(item) end)
	return item
end

function Toast:remove(item)
	local i = table.find(self.items, item)
	if not i then return end
	table.remove(self.items, i)
	item.glass:destroy()
	pcall(function() item.gui:Destroy() end)
	self:layout()
end

-- newest at the bottom, the others above it
function Toast:layout()
	local _, sh = self.ui.wm:screen()
	local n = #self.items
	for i, item in ipairs(self.items) do
		local y = sh - BOTTOM - H - (n - i) * (H + GAP)
		W.set(item.gui, "Position", UDim2.new(0.5, 0, 0, y))
	end
end

function Toast:destroy()
	for _, off in ipairs(self.offs) do off() end
	self.offs = {}
	for _, item in ipairs(table.clone(self.items)) do self:remove(item) end
end

return Toast
