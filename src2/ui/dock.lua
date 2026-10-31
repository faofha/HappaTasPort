-- ================================================================================================
--  DOCK  (HappaTAS 3 ui): the small glass pill at the top centre, below the top bar: "HappaTAS" and a
--  button per window (ui:addDockButton(id), in the order they're added); a click opens / closes that
--  window, and the buttons of open windows are lit. The spec names no launcher (phase 5a plan ruling).
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Glass = import("ui/kit/glass")
local Button = import("ui/kit/button")
local Layout = import("ui/layout")

local Dock = {}
Dock.__index = Dock

local Z, ZINDEX, H, PAD, GAP, TOP = 50000000, 500000, 36, 14, 8, 8

function Dock.new(ui)
	local self = setmetatable({ ui = ui, buttons = {}, order = {}, rects = {}, offs = {} }, Dock)
	local E = ui.E
	self.ctx = { E = E, ui = ui, theme = ui.theme, tween = ui.tween, typing = E.typing,
		pointer = {
			add = function(r, z)
				r.z = Z + (z or 0)
				r.group = r.group or self.gui
				self.rects[#self.rects + 1] = r
				ui.pointer:add(r)
				return r
			end,
			remove = function(r) ui.pointer:remove(r) end,
		} }
	local gui = K.frame("Dock", ui.root.layer)
	gui.AnchorPoint = Vector2.new(0.5, 0)
	gui.ZIndex = ZINDEX
	self.gui = gui
	self.glass = Glass.panel(ui.theme, gui, { cornerKind = "control" })
	self.ctx.pointer.add({ gui = self.glass.panel }, 0) -- (a press on the Dock is the Dock's)
	local title = K.text("TextLabel", "Title", self.glass.panel)
	title.Text = "HappaTAS"
	title.ZIndex = 2
	self.title = title
	self.offs[#self.offs + 1] = ui.theme:changed(function() self:layout() end)
	self.offs[#self.offs + 1] = ui.wm:changed(function(id, open)
		local b = self.buttons[id]
		if b then b:setKind(open and "primary" or "plain") end
	end)
	ui.life:own(function() self:destroy() end)
	self:layout()
	return self
end

function Dock:add(id)
	if self.buttons[id] then return self.buttons[id] end
	local def = self.ui.wm.defs[id]
	local b = Button.new(self.ctx, self.glass.panel, { text = def and def.title or id, kind = self.ui.wm:isOpen(id) and "primary" or "plain", z = 1 })
	b.gui.ZIndex = 2
	b.onClick = function() self.ui.wm:toggle(id) end
	self.buttons[id] = b
	self.order[#self.order + 1] = id
	self:layout()
	return b
end

function Dock:layout()
	local th = self.ui.theme
	W.set(self.title, "FontFace", th.font("bold"))
	W.set(self.title, "TextSize", th.size(12.5))
	W.set(self.title, "TextColor3", th.c.text)
	local tw = Layout.textWidth("HappaTAS", th.font("bold"), th.size(12.5), self.gui)
	W.set(self.title, "Size", UDim2.new(0, tw, 0, H))
	local items = { { gui = self.title, w = tw } }
	for _, id in ipairs(self.order) do
		local b = self.buttons[id]
		items[#items + 1] = { gui = b.gui, w = b.gui.Size.X.Offset }
		W.set(b.gui, "Position", UDim2.new(0, 0, 0, (H - 24) / 2))
	end
	local x = PAD
	for i, it in ipairs(items) do
		if i > 1 then x = x + GAP end
		local y = (it.gui == self.title) and 0 or (H - 24) / 2
		W.set(it.gui, "Position", UDim2.new(0, x, 0, y))
		x = x + it.w
	end
	local _, _, top = self.ui.wm:screen()
	W.set(self.gui, "Position", UDim2.new(0.5, 0, 0, top + TOP))
	W.set(self.gui, "Size", UDim2.new(0, x + PAD, 0, H))
end

function Dock:destroy()
	if self.dead then return end
	self.dead = true
	for _, off in ipairs(self.offs) do off() end
	for _, b in pairs(self.buttons) do b:destroy() end
	for _, r in ipairs(self.rects) do self.ui.pointer:remove(r) end
	self.glass:destroy()
	pcall(function() self.gui:Destroy() end)
end

return Dock
