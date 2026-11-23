-- ================================================================================================
--  TRAJECTORY DRAW  (HappaTAS 3 world, V3.1 Show Trajectory): the lines, as pooled LineHandleAdornments on the
--  Terrain (drawn in the world, over everything, client only, no parts for game scripts to find), parented to
--  HappaTAS's hidden interface root. One pool per line id; a redraw reuses segments and hides the ones left over.
-- ================================================================================================
local W = import("ui/write")

local Draw = {}
Draw.__index = Draw

local THICKNESS = 3

function Draw.new(parent)
	return setmetatable({ parent = parent, pools = {}, shown = {} }, Draw)
end

function Draw:segment(id, i)
	local pool = self.pools[id]
	if not pool then pool = {}; self.pools[id] = pool end
	local a = pool[i]
	if a and a.Parent then return a end
	a = Instance.new("LineHandleAdornment")
	a.Name = "HappaTrajectory"
	a.Adornee = workspace.Terrain
	a.AlwaysOnTop = true
	a.ZIndex = 1
	a.Thickness = THICKNESS
	a.Parent = self.parent
	pool[i] = a
	return a
end

-- draws line `id` through points (Vector3 list) in color
function Draw:line(id, points, color)
	local n = 0
	for i = 1, #points - 1 do
		local p0, p1 = points[i], points[i + 1]
		local len = (p1 - p0).Magnitude
		if len > 1e-4 then
			n = n + 1
			local a = self:segment(id, n)
			W.set(a, "CFrame", CFrame.lookAt(p0, p1))
			W.set(a, "Length", len)
			W.set(a, "Color3", color)
			W.set(a, "Visible", true)
		end
	end
	local pool = self.pools[id] or {}
	for i = n + 1, self.shown[id] or 0 do
		if pool[i] then W.set(pool[i], "Visible", false) end
	end
	self.shown[id] = n
end

-- hides line id (every line without one)
function Draw:hide(id)
	for k, pool in pairs(self.pools) do
		if id == nil or k == id then
			for i = 1, self.shown[k] or 0 do
				if pool[i] then W.set(pool[i], "Visible", false) end
			end
			self.shown[k] = 0
		end
	end
end

function Draw:destroy()
	for _, pool in pairs(self.pools) do
		for _, a in pairs(pool) do pcall(function() a:Destroy() end) end
	end
	self.pools, self.shown = {}, {}
end

return Draw
