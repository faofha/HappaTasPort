-- ================================================================================================
--  CLASSIC LOOK  (HappaTAS 3 ui, Classic Look): paints the Classic interface in the Classic Look settings.
--  Every part of Classic's ScreenGui is looked at once, when it is added (the tree at the start, rows built
--  later through DescendantAdded): each colour property holding a palette colour (ui/classic/palette) is
--  registered under the setting that owns it and painted in that setting's colour. A settings change
--  rewrites only the registered properties whose colour changed. Colours Classic's own code paints while
--  running (switch knobs, merge buttons, merge stats, section titles) are `own`ed by that code and never
--  repainted here; it reads look:color(key) and repaints on look:changed. Parts with the attribute
--  HappaTASNoLook (and everything under them) are left alone. Nothing runs per frame.
-- ================================================================================================
local Palette = import("ui/classic/palette")

local Look = {}
Look.__index = Look

-- the colour properties a part can hold, by class
local function propsOf(inst)
	if inst:IsA("UIStroke") then return { "Color" } end
	if not inst:IsA("GuiObject") then return nil end
	local out = { "BackgroundColor3", "BorderColor3" }
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then out[#out + 1] = "TextColor3" end
	if inst:IsA("TextBox") then out[#out + 1] = "PlaceholderColor3" end
	if inst:IsA("ScrollingFrame") then out[#out + 1] = "ScrollBarImageColor3" end
	return out
end

local function skipped(inst, root)
	local p = inst
	while p and p ~= root do
		if p:GetAttribute("HappaTASNoLook") then return true end
		p = p.Parent
	end
	return false
end

function Look.new(classic)
	local s = classic.E.settings
	local self = setmetatable({ classic = classic, settings = s, colors = Palette.resolve(s), entries = {},
		owned = setmetatable({}, { __mode = "k" }), seen = setmetatable({}, { __mode = "k" }), listeners = {} }, Look)
	local root = classic.gui
	for _, d in ipairs(root:GetDescendants()) do self:register(d) end
	-- (a row built later: DescendantAdded comes for it and every part in it; `seen` keeps each part to once)
	local conn = root.DescendantAdded:Connect(function(d) self:register(d) end)
	classic.offs[#classic.offs + 1] = function() conn:Disconnect() end
	local function changed() self:repaint() end
	classic.offs[#classic.offs + 1] = s:changed("classicMainColor", changed)
	for _, p in ipairs(Palette.LIST) do
		classic.offs[#classic.offs + 1] = s:changed(p.key, changed)
	end
	return self
end

-- a part added to Classic: its palette colours registered and painted now (once per part)
function Look:register(inst)
	if self.seen[inst] then return end
	self.seen[inst] = true
	local props = propsOf(inst)
	if not props or skipped(inst, self.classic.gui) then return end
	for _, prop in ipairs(props) do
		local ok, col = pcall(function() return inst[prop] end)
		local key = ok and typeof(col) == "Color3" and Palette.keyFor(prop, col) or nil
		if key then
			local list = self.entries[key]
			if not list then
				list = {}
				self.entries[key] = list
			end
			list[#list + 1] = { inst = inst, prop = prop }
			local want = self.colors[key]
			if col ~= want then pcall(function() inst[prop] = want end) end
		end
	end
end

-- the colour a setting stands for now
function Look:color(key)
	return self.colors[key] or (Palette.byKey[key] and Palette.byKey[key].color)
end

-- the caller paints inst[prop] itself: the Look never repaints it
function Look:own(inst, prop)
	local t = self.owned[inst]
	if not t then
		t = {}
		self.owned[inst] = t
	end
	t[prop] = true
end

function Look:owns(inst, prop)
	local t = self.owned[inst]
	return t ~= nil and t[prop] == true
end

-- f() after every repaint; returns a function that removes it
function Look:changed(f)
	local list = self.listeners
	list[#list + 1] = f
	return function()
		local i = table.find(list, f)
		if i then table.remove(list, i) end
	end
end

-- the settings changed: every registered property whose colour changed gets the new one
function Look:repaint()
	local new = Palette.resolve(self.settings)
	local old = self.colors
	self.colors = new
	for key, col in pairs(new) do
		if old[key] ~= col then
			local list = self.entries[key]
			if list then
				local keep = {}
				for _, e in ipairs(list) do
					if e.inst.Parent ~= nil then
						keep[#keep + 1] = e
						if not self:owns(e.inst, e.prop) then pcall(function() e.inst[e.prop] = col end) end
					end
				end
				self.entries[key] = keep
			end
		end
	end
	for _, f in ipairs(table.clone(self.listeners)) do pcall(f) end
end

return Look
