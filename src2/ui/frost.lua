-- ================================================================================================
--  FROST  (HappaTAS 3 ui, spec 8.1, a trial until the live check): the game blurred behind the windows.
--  Behind each open window a thin Glass-material part sits 1 stud in front of the camera, covering the
--  window's screen rect, and one DepthOfFieldEffect blurs what is that near (the known Roblox "acrylic"
--  way: NearIntensity from Blur strength, in focus from 1.6 studs on, so only the glass is blurred). Only
--  with high graphics (saved level 8+ of 10, or Automatic at 16+ of 21); else the panels stay Tint.
--  Parts: Camera.HappaTASFrost, anchored, no collide / touch / query, HappaTASIgnore. The per-frame
--  placement runs only while something shows; everything goes when Frost is off, no window is open, the
--  interface is hidden, or on Unload.
-- ================================================================================================
local Env = import("platform/env")

local Frost = {}
Frost.__index = Frost

local DIST = 1
local NAME = "HappaTASFrost"

function Frost.new(ui)
	local E = ui.E
	local self = setmetatable({ ui = ui, E = E, parts = {}, folder = nil, dof = nil, off = nil, offs = {},
		gui = Env.svc("GuiService") }, Frost)
	local s = E.settings
	self.offs[#self.offs + 1] = s:changed("glass", function() self:update() end)
	self.offs[#self.offs + 1] = s:changed("blurStrength", function() self:update() end)
	self.offs[#self.offs + 1] = ui.wm:changed(function() self:update() end)
	self.offs[#self.offs + 1] = E.bus:on("uiShown", function() self:update() end)
	pcall(function()
		local ugs = UserSettings():GetService("UserGameSettings")
		local c = ugs:GetPropertyChangedSignal("SavedQualityLevel"):Connect(function() self:update() end)
		self.offs[#self.offs + 1] = function() c:Disconnect() end
	end)
	ui.life:own(function() self:destroy() end)
	self:update()
	return self
end

-- high enough graphics for the blur
function Frost:available()
	local saved = 0
	pcall(function() saved = UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value end)
	if saved and saved > 0 then return saved >= 8 end
	local auto = 0
	pcall(function() auto = settings().Rendering.QualityLevel.Value end)
	return (auto or 0) >= 16
end

function Frost:wanted()
	return self.E.settings:get("glass") == "Frost" and self.ui.shown and self.ui.wm:anyOpen() and self:available()
end

function Frost:update()
	if not self:wanted() then return self:clear() end
	local cam = workspace.CurrentCamera
	if not cam then return self:clear() end
	if not (self.folder and self.folder.Parent) then
		local f = Instance.new("Folder")
		f.Name = NAME
		f.Parent = cam
		self.folder = f
	end
	local blur = self.E.settings:get("blurStrength") / 100
	if not (self.dof and self.dof.Parent) then
		local d = Instance.new("DepthOfFieldEffect")
		d.Name = NAME
		d.FarIntensity, d.FocusDistance, d.InFocusRadius = 0, 51.6, 50
		d.Parent = Env.svc("Lighting")
		self.dof = d
	end
	self.dof.NearIntensity = blur
	local wm = self.ui.wm
	for id, win in pairs(wm.windows) do
		local p = self.parts[id]
		if win.open and not p then
			p = Instance.new("Part")
			p.Name = id
			p.Material = Enum.Material.Glass
			p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
			p:SetAttribute("HappaTASIgnore", true)
			p.Parent = self.folder
			self.parts[id] = p
		elseif not win.open and p then
			p:Destroy()
			self.parts[id] = nil
		end
		if p then
			p.Transparency = 1 - 0.5 * blur
			p.Color = self.ui.theme.c.glass
		end
	end
	if not self.off then self.off = self.E.pipe:add("PreRender", 210, "ui.frost", function() self:place() end, "ui") end
	self:place()
end

-- each part over its window's screen rect, DIST studs in front of the camera
function Frost:place()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local inset = 0
	if self.gui then pcall(function() inset = self.gui:GetGuiInset().Y end) end
	local cf = cam.CFrame
	local look, rot = cf.LookVector, cf - cf.Position
	local function at(x, y)
		local r = cam:ViewportPointToRay(x, y)
		return r.Origin + r.Direction * (DIST / r.Direction:Dot(look))
	end
	for id, p in pairs(self.parts) do
		local win = self.ui.wm.windows[id]
		if win then
			local a, s = win.holder.AbsolutePosition, win.holder.AbsoluteSize
			local x0, y0 = a.X, a.Y + inset
			local cx, cy = x0 + s.X / 2, y0 + s.Y / 2
			local w = (at(x0 + s.X, cy) - at(x0, cy)).Magnitude
			local h = (at(cx, y0 + s.Y) - at(cx, y0)).Magnitude
			p.Size = Vector3.new(w, h, 0.01)
			p.CFrame = CFrame.new(at(cx, cy)) * rot
		end
	end
end

function Frost:clear()
	if self.off then self.off(); self.off = nil end
	for id, p in pairs(self.parts) do
		pcall(function() p:Destroy() end)
		self.parts[id] = nil
	end
	if self.folder then pcall(function() self.folder:Destroy() end); self.folder = nil end
	if self.dof then pcall(function() self.dof:Destroy() end); self.dof = nil end
end

function Frost:destroy()
	for _, off in ipairs(self.offs) do off() end
	self.offs = {}
	self:clear()
end

return Frost
