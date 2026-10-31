-- ================================================================================================
--  POPOVER  (HappaTAS 3 ui kit): a glass panel above every window, next to the control that opened it
--  (below it, or above when there's no room). A transparent catcher under it covers the screen: a press
--  outside closes the popover (and never reaches the game or a window); Esc closes it too.
--  pop.ctx gives controls inside it their rects above everything else.
-- ================================================================================================
local Env = import("platform/env")
local K = import("ui/kit/base")
local Glass = import("ui/kit/glass")

local Popover = {}
Popover.__index = Popover

local Z = 100000000 -- (pointer z: above every window's rects)
local ZINDEX = 1000000 -- (draw order: above every window's holder)

function Popover.open(ctx, anchor, w, h)
	local ui = ctx.ui
	local layer = ui.root.layer
	local self = setmetatable({ ctx = nil, ui = ui, rects = {}, conns = {}, open = true, onClose = nil }, Popover)
	local scale = ui.root.scale.Scale
	local lp = layer.AbsolutePosition
	local ap, as = anchor.AbsolutePosition, anchor.AbsoluteSize
	local x, y = (ap.X - lp.X) / scale, (ap.Y + as.Y - lp.Y) / scale + 4
	local sw, sh = ui.wm:screen()
	if y + h > sh then y = (ap.Y - lp.Y) / scale - h - 4 end
	x = math.max(0, math.min(x, sw - w))
	y = math.max(0, y)
	local catcher = K.frame("PopoverCatcher", layer)
	catcher.Size = UDim2.new(1, 0, 1, 0)
	catcher.ZIndex = ZINDEX - 1
	catcher.Active = true -- (a click outside closes the popover; the game sees it game processed)
	self.catcher = catcher
	local holder = K.frame("Popover", layer)
	holder.Position = UDim2.new(0, x, 0, y)
	holder.Size = UDim2.new(0, w, 0, h)
	holder.ZIndex = ZINDEX
	self.holder = holder
	self.glass = Glass.panel(ui.theme, holder, { cornerKind = "window" })
	self.frame = self.glass.panel
	self.ctx = { E = ctx.E, ui = ui, theme = ctx.theme, tween = ctx.tween, typing = ctx.typing,
		pointer = { add = function(r, z) return self:add(r, z) end, remove = function(r) self:remove(r) end } }
	self.catcherRect = self:add({ gui = catcher, onPress = function() self:close() end }, -1)
	local uis = Env.svc("UserInputService")
	-- (owned by the interface's scope too: Unload ends it with the popover still open)
	self.conns[#self.conns + 1] = ui.life:connect(uis.InputBegan, function(inp)
		if inp.KeyCode == Enum.KeyCode.Escape and not ctx.typing:active(nil) then self:close() end
	end)
	return self
end

function Popover:add(rect, z)
	rect.z = Z + (z or 0) + 1
	if rect.gui ~= self.catcher then rect.group = rect.group or self.holder end
	self.rects[#self.rects + 1] = rect
	self.ui.pointer:add(rect)
	return rect
end

function Popover:remove(rect)
	local i = table.find(self.rects, rect)
	if i then table.remove(self.rects, i) end
	self.ui.pointer:remove(rect)
end

function Popover:close()
	if not self.open then return end
	self.open = false
	for _, r in ipairs(self.rects) do self.ui.pointer:remove(r) end
	self.rects = {}
	for _, c in ipairs(self.conns) do self.ui.life:drop(c) end
	self.glass:destroy()
	pcall(function() self.holder:Destroy() end)
	pcall(function() self.catcher:Destroy() end)
	if self.onClose then self.onClose() end
end

return Popover
