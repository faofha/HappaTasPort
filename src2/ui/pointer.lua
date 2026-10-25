-- ================================================================================================
--  POINTER  (HappaTAS 3 ui): the interface's own mouse / touch handling. GUI button events aren't used:
--  Roblox measures GUI positions below the top bar but GetMouseLocation() from the top of the screen, and
--  mixing the two put clicks one top-bar height off (V2.36). Here every position is in the GUI's space
--  (InputObject.Position, or GetMouseLocation() minus the inset), and the hit test walks the interface's
--  own rects, the highest z first (then the last added).
--  rect = { gui, z, onHover(on), onPress(pos), onRelease(pos, clicked), onDrag(pos, delta), onWheel(dz) }
--  A press keeps its rect: moves and the release go to it wherever the pointer is. A click is a release
--  within 3 px of its press, over the same rect (microprofile's rule).
-- ================================================================================================
local Env = import("platform/env")

local Pointer = {}
Pointer.__index = Pointer

local CLICK_PX = 3
local PRESS = { [Enum.UserInputType.MouseButton1] = true, [Enum.UserInputType.Touch] = true }
local MOVE = { [Enum.UserInputType.MouseMovement] = true, [Enum.UserInputType.Touch] = true }

function Pointer.new(E, root, life)
	local self = setmetatable({ E = E, root = root, rects = {}, seq = 0, hover = nil, pressed = nil, pressPos = nil,
		pos = Vector2.zero, uis = Env.svc("UserInputService"), guiService = Env.svc("GuiService") }, Pointer)
	local uis = self.uis
	life:connect(uis.InputBegan, function(inp) self:began(inp) end)
	life:connect(uis.InputChanged, function(inp) self:changed(inp) end)
	life:connect(uis.InputEnded, function(inp) self:ended(inp) end)
	return self
end

function Pointer:add(rect)
	self.seq = self.seq + 1
	rect.seq = self.seq
	rect.z = rect.z or 0
	self.rects[#self.rects + 1] = rect
	return rect
end

function Pointer:remove(rect)
	local i = table.find(self.rects, rect)
	if i then table.remove(self.rects, i) end
	if self.hover == rect then self.hover = nil end
	if self.pressed == rect then self.pressed = nil end
end

-- visible = the gui and every GuiObject above it Visible, inside the shown root
local function shown(gui, top)
	local g = gui
	while g and g ~= top do
		if g:IsA("GuiObject") and not g.Visible then return false end
		g = g.Parent
	end
	return g == top and top.Enabled
end

local function inside(gui, pos)
	local p, s = gui.AbsolutePosition, gui.AbsoluteSize
	return pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y
end

-- the rect under pos (GUI space), or nil
function Pointer:over(pos)
	local best = nil
	local top = self.root.gui
	for _, r in ipairs(self.rects) do
		local g = r.gui
		if g and g.Parent and (not best or r.z > best.z or (r.z == best.z and r.seq > best.seq)) and inside(g, pos) and shown(g, top) then
			best = r
		end
	end
	return best
end

-- the pointer now, in GUI space
function Pointer:now()
	local ok, m = pcall(self.uis.GetMouseLocation, self.uis)
	if not ok then return self.pos end
	local inset = Vector2.zero
	if self.guiService then pcall(function() inset = self.guiService:GetGuiInset() end) end
	return m - inset
end

local function posOf(inp)
	local p = inp.Position
	return Vector2.new(p.X, p.Y)
end

local function call(f, ...) if f then f(...) end end

function Pointer:setHover(r)
	if r == self.hover then return end
	local old = self.hover
	self.hover = r
	if old then call(old.onHover, false) end
	if r then call(r.onHover, true) end
end

function Pointer:began(inp)
	if not PRESS[inp.UserInputType] then return end
	local pos = posOf(inp)
	self.pos = pos
	local r = self:over(pos)
	if not r then return end
	self.pressed, self.pressPos, self.pressInput = r, pos, inp
	call(r.onPress, pos)
end

function Pointer:changed(inp)
	local t = inp.UserInputType
	if t == Enum.UserInputType.MouseWheel then
		local pos = posOf(inp)
		local r = self:over(pos)
		if r then call(r.onWheel, inp.Position.Z) end
		return
	end
	if not MOVE[t] then return end
	local pos = posOf(inp)
	if pos == self.pos then return end -- (no move: nothing to drag or hover)
	self.pos = pos
	local r = self.pressed
	if r then
		call(r.onDrag, pos, pos - self.pressPos)
	else
		self:setHover(self:over(pos))
	end
end

function Pointer:ended(inp)
	if not PRESS[inp.UserInputType] then return end
	local r = self.pressed
	if not r then return end
	local pos = posOf(inp)
	self.pos = pos
	self.pressed = nil
	local clicked = (pos - self.pressPos).Magnitude <= CLICK_PX and self:over(pos) == r
	call(r.onRelease, pos, clicked)
	self:setHover(self:over(pos))
end

-- whether the pointer is on the interface now (a press on it counts until its release)
function Pointer:busy()
	return self.pressed ~= nil or self:over(self:now()) ~= nil
end

return Pointer
