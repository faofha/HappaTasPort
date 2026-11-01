-- ================================================================================================
--  CLASSIC  (HappaTAS 3 ui, spec 8.5): V2.38.17's interface drawn by HappaTAS 3, for people who prefer it.
--  Its own ScreenGui ("HappaTASClassic") next to the new interface's, built the first time Classic is
--  chosen (UI:setInterface). Only one interface is live; this one answers the engine's questions while it is
--  (pointerOver: the mouse on its visible menu; modal: its menu open frees the mouse).
-- ================================================================================================
local Env = import("platform/env")

local Classic = {}
Classic.__index = Classic

local NAME = "HappaTASClassic"
local DISPLAY_ORDER = 10

function Classic.new(ui)
	local E = ui.E
	local self = setmetatable({ ui = ui, E = E, shown = true, offs = {} }, Classic)
	local parent = ui.root.gui.Parent
	if parent then
		for _, g in ipairs(parent:GetChildren()) do
			if g.Name == NAME and g:IsA("ScreenGui") then pcall(function() g:Destroy() end) end
		end
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	pcall(function() gui.AutoLocalize = false end)
	pcall(function() gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
	pcall(function() gui.DisplayOrder = DISPLAY_ORDER end)
	self.gui = gui
	local menu = Instance.new("Frame")
	menu.Name = "MainMenu"
	menu.Visible = false
	menu.Parent = gui
	self.menu = menu
	pcall(function() gui.Parent = parent end)
	self.uis = Env.svc("UserInputService")
	self.guiService = Env.svc("GuiService")
	return self
end

-- shown / hidden (the Menu key while Classic is live); the engine's mouse state follows
function Classic:show(on)
	self.shown = on == true
	self.gui.Enabled = self.shown and self.ui.live == "Classic"
	self.ui:updateModal()
end

function Classic:toggle() self:show(not self.shown) end

-- the menu is open: the mouse is free (V2's Menu.IsModalOpen)
function Classic:modal()
	return self.shown and self.menu.Visible == true
end

-- the mouse (m: UserInputService:GetMouseLocation()) is on the open menu
function Classic:pointerOver(m)
	if not self:modal() then return false end
	if not m then
		local ok, v = pcall(self.uis.GetMouseLocation, self.uis)
		if not ok then return false end
		m = v
	end
	local inset = Vector2.zero
	if self.guiService then pcall(function() inset = self.guiService:GetGuiInset() end) end
	local p, s = self.menu.AbsolutePosition, self.menu.AbsoluteSize
	local x, y = m.X - inset.X, m.Y - inset.Y
	return x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y
end

function Classic:destroy()
	if self.dead then return end
	self.dead = true
	for _, off in ipairs(self.offs) do off() end
	self.offs = {}
	pcall(function() self.gui:Destroy() end)
end

return Classic
