-- ================================================================================================
--  SQUARE  (HappaTAS 3 ui, V3.1): while the Tasability interface is live, every rounded corner in the interface's
--  layer is square (the hosted New windows' rows, the timeline bar's buttons, popovers...), like the rest of
--  Tasability; a corner marked HappaRound (a round dot, the search magnifier) stays round. Each corner's own
--  radius is kept in an attribute and put back when the interface changes; corners made while Tasability is live
--  are squared as they appear. Kit controls whose radius follows the theme get 0 from the theme too.
-- ================================================================================================
local Square = {}
Square.__index = Square

local KEPT = "HappaRadius"

local function squareOne(c)
	if not c:IsA("UICorner") or c:GetAttribute("HappaRound") then return end
	if c:GetAttribute(KEPT) == nil then
		local r = c.CornerRadius
		c:SetAttribute(KEPT, r.Offset)
		c:SetAttribute(KEPT .. "Scale", r.Scale)
	end
	if c.CornerRadius ~= UDim.new(0, 0) then c.CornerRadius = UDim.new(0, 0) end
end

local function restoreOne(c)
	if not c:IsA("UICorner") then return end
	local v = c:GetAttribute(KEPT)
	if v == nil then return end
	local scale = c:GetAttribute(KEPT .. "Scale") or 0
	c:SetAttribute(KEPT, nil)
	c:SetAttribute(KEPT .. "Scale", nil)
	c.CornerRadius = UDim.new(scale, v)
end

function Square.new(root)
	return setmetatable({ root = root, on = false, conn = nil }, Square)
end

function Square:set(on)
	on = on == true
	if on == self.on then return end
	self.on = on
	local root = self.root
	if on then
		for _, d in ipairs(root:GetDescendants()) do squareOne(d) end
		self.conn = root.DescendantAdded:Connect(function(d)
			if d:IsA("UICorner") then
				task.defer(function() if self.on and d.Parent then squareOne(d) end end) -- (after its owner set its radius)
			end
		end)
	else
		if self.conn then self.conn:Disconnect(); self.conn = nil end
		for _, d in ipairs(root:GetDescendants()) do restoreOne(d) end
	end
end

function Square:destroy() self:set(false) end

return Square
