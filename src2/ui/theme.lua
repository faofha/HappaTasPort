-- ================================================================================================
--  THEME  (HappaTAS 3 ui): what the interface looks like, read from the Appearance settings (spec 8.1 /
--  8.4, the mockup's numbers as defaults). theme.c = colours, theme.t = transparencies (0 = solid),
--  theme.font(kind), theme.size(n), theme.corner(kind). changed(f) fires once for each Appearance setting
--  that changes, and for a font preview (a font shown everywhere while a font list is hovered; the stored
--  setting stays as it is).
-- ================================================================================================
local Settings = import("engine/settings")

local Theme = {}
Theme.__index = Theme

local CONTROL_CORNER = { Pill = 999, Rounded = 8, Square = 2 }
local FIXED = { reset1 = "#FFC86E", reset2 = "#F0A032", close = "#FF6A6A" }

local function color(hex)
	local h = tostring(hex or ""):gsub("#", "")
	local r, g, b = tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)
	if not (r and g and b) then return Color3.new(1, 1, 1) end
	return Color3.fromRGB(r, g, b)
end
Theme.color = color

local function family(name) return "rbxasset://fonts/families/" .. tostring(name) .. ".json" end

function Theme.new(E, life)
	local self = setmetatable({ E = E, s = E.settings, c = {}, t = {}, listeners = {}, previewName = nil }, Theme)
	self:refresh()
	life:own(E.settings:onAny(function(key)
		local def = Settings.byKey[key]
		if def and def.section == "Appearance" then
			self:refresh()
			self:fire()
		end
	end))
	-- (plain functions, so they can be passed around: theme.size(13))
	self.size = function(n) return n * self.s:get("textSize") / 13 end
	self.font = function(kind)
		local s = self.s
		local name = (kind == "number") and s:get("numberFont") or (self.previewName or s:get("font"))
		local weight = (kind == "bold") and Enum.FontWeight.Bold or Enum.FontWeight.Regular
		return Font.new(family(name), weight)
	end
	self.corner = function(kind)
		if kind == "window" then return self.s:get("windowCorners") end
		return CONTROL_CORNER[self.s:get("buttonShape")] or 999
	end
	return self
end

function Theme:refresh()
	local s, c, t = self.s, self.c, self.t
	c.glass = color(s:get("glassColor"))
	c.accent = color(s:get("accentColor"))
	c.text = color(s:get("textColor"))
	c.text2 = color(s:get("secondaryTextColor"))
	c.rec = color(s:get("recordingColor"))
	for k, hex in pairs(FIXED) do c[k] = color(hex) end
	t.glass = s:get("glassTransparency") / 100
	t.rim = 1 - s:get("edgeLight") / 100
end

function Theme:fire()
	for _, f in ipairs(table.clone(self.listeners)) do
		local ok, err = pcall(f)
		if not ok and self.E.errs then self.E.errs:report("theme", err) end
	end
end

-- f() after each change of the look; returns a function that removes it
function Theme:changed(f)
	local list = self.listeners
	list[#list + 1] = f
	return function()
		local i = table.find(list, f)
		if i then table.remove(list, i) end
	end
end

-- a font shown everywhere for now (nil: back to the stored one)
function Theme:preview(name)
	if name == self.previewName then return end
	self.previewName = name
	self:fire()
end

return Theme
