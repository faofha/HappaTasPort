-- ================================================================================================
--  GLASS  (HappaTAS 3 ui kit): the soft frosted glass every window is made of (spec 8.1, the mockup's
--  numbers): translucent fill, a thin white rim, rounded corners, a soft shadow drawn as three dark frames a
--  little larger each (no image assets). It restyles itself when the theme changes.
-- ================================================================================================
local W = import("ui/write")

local Glass = {}
Glass.__index = Glass

local SHADOW = { { grow = 4, t = 0.86 }, { grow = 8, t = 0.92 }, { grow = 14, t = 0.96 } }

local function corner(parent)
	local c = Instance.new("UICorner")
	c.Parent = parent
	return c
end

-- a panel filling holder (a transparent Frame the caller sizes); opts.cornerKind ("window" by default).
-- The panel is Active, so Roblox marks a click on it game processed and the game (an equipped tool, the
-- camera's right drag) leaves it alone; opts.passThrough (a toast) lets clicks through to the game.
function Glass.panel(theme, holder, opts)
	opts = opts or {}
	local self = setmetatable({ theme = theme, kind = opts.cornerKind or "window", shadowCorners = {} }, Glass)
	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.BackgroundTransparency = 1
	shadow.BorderSizePixel = 0
	shadow.Size = UDim2.new(1, 0, 1, 0)
	shadow.ZIndex = 0
	shadow.Parent = holder
	for i, sh in ipairs(SHADOW) do
		local f = Instance.new("Frame")
		f.Name = "S" .. i
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BackgroundTransparency = sh.t
		f.BorderSizePixel = 0
		f.Position = UDim2.new(0, -sh.grow, 0, -sh.grow + 4)
		f.Size = UDim2.new(1, sh.grow * 2, 1, sh.grow * 2)
		f.ZIndex = 0
		f.Parent = shadow
		self.shadowCorners[i] = { c = corner(f), grow = sh.grow }
	end
	local panel = Instance.new("Frame")
	panel.Name = "Glass"
	panel.BorderSizePixel = 0
	panel.Size = UDim2.new(1, 0, 1, 0)
	panel.ZIndex = 1
	panel.Active = not opts.passThrough
	panel.Parent = holder
	self.corner = corner(panel)
	local rim = Instance.new("UIStroke")
	rim.Color = Color3.new(1, 1, 1)
	rim.Thickness = 1
	pcall(function() rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border end)
	rim.Parent = panel
	self.panel, self.shadow, self.rim = panel, shadow, rim
	self:restyle()
	self.off = theme:changed(function() self:restyle() end)
	return self
end

function Glass:restyle()
	local th = self.theme
	local r = th.corner(self.kind)
	W.set(self.panel, "BackgroundColor3", th.c.glass)
	-- (Clear: barely any fill, only the rim; Tint and Frost: the glass colour at its transparency)
	local clear = th.E.settings:get("glass") == "Clear"
	W.set(self.panel, "BackgroundTransparency", clear and math.max(th.t.glass, 0.94) or th.t.glass)
	W.set(self.corner, "CornerRadius", UDim.new(0, r))
	W.set(self.rim, "Transparency", th.t.rim)
	W.set(self.shadow, "Visible", th.E.settings:on("shadows"))
	for _, sc in ipairs(self.shadowCorners) do W.set(sc.c, "CornerRadius", UDim.new(0, r + sc.grow)) end
end

function Glass:destroy()
	if self.off then self.off() end
	self.off = nil
end

return Glass
