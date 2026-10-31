-- ================================================================================================
--  POINTER  (HappaTAS 3 ui): the interface's own mouse / touch handling. GUI button events aren't used:
--  Roblox measures GUI positions below the top bar but GetMouseLocation() from the top of the screen, and
--  mixing the two put clicks one top-bar height off (V2.36). Here every position is in the GUI's space
--  (InputObject.Position, or GetMouseLocation() minus the inset), and the hit test walks the interface's
--  own rects, the highest z first (then the last added).
--  rect = { gui, z, group, clip, onHover(on), onPress(pos), onRelease(pos, clicked), onDrag(pos, delta), onWheel(dz) }
--  group (a window, the Dock, a popover) is checked once per search: the pointer runs this on every mouse
--  move, so a rect is only looked at when the pointer is inside its group, and nothing at all while the
--  interface is hidden. clip (a ScrollingFrame) limits a rect to the part of it that shows: a row scrolled
--  out of a list never takes a click meant for what is above or below the list.
--  A press keeps its rect: moves and the release go to it wherever the pointer is. A click is a release
--  within 3 px of its press, over the same rect (microprofile's rule).
-- ================================================================================================
local Env = import("platform/env")
local W = import("ui/write")

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
	W.bump()
	return rect
end

function Pointer:remove(rect)
	local i = table.find(self.rects, rect)
	if i then table.remove(self.rects, i) end
	if self.hover == rect then self.hover = nil end
	if self.pressed == rect then self.pressed = nil end
	W.bump()
end

-- (bounds and visibility are kept per gui until W.version changes: no engine reads on a plain mouse move)
local cache = setmetatable({}, { __mode = "k" })

-- visible = the gui and every GuiObject above it Visible, inside the shown root
local function shownNow(gui, top)
	local g = gui
	while g and g ~= top do
		if g:IsA("GuiObject") and not g.Visible then return false end
		g = g.Parent
	end
	return g == top and top.Enabled
end

local function info(gui, top)
	local c = cache[gui]
	if c and c.v == W.version then return c end
	local p, s = gui.AbsolutePosition, gui.AbsoluteSize
	c = { v = W.version, x0 = p.X, y0 = p.Y, x1 = p.X + s.X, y1 = p.Y + s.Y, shown = gui.Parent ~= nil and shownNow(gui, top) }
	cache[gui] = c
	return c
end

local function inside(c, pos)
	return pos.X >= c.x0 and pos.X <= c.x1 and pos.Y >= c.y0 and pos.Y <= c.y1
end

-- A grid of 64 px cells, each listing the rects that cover it (only shown ones, cut to their group and
-- clip), rebuilt when W.version changes: a mouse move looks at the few rects in its cell, not at every
-- rect of every open window (an open Settings window has ~200).
local CELL = 64

local function cut(c, by)
	return { x0 = math.max(c.x0, by.x0), y0 = math.max(c.y0, by.y0), x1 = math.min(c.x1, by.x1), y1 = math.min(c.y1, by.y1) }
end

function Pointer:index(top)
	local ix = self.ix
	if ix and ix.v == W.version then return ix end
	ix = { v = W.version, cells = {} }
	local cells = ix.cells
	for _, r in ipairs(self.rects) do
		local g = r.gui
		if g then
			local c = info(g, top)
			local ok = c.shown
			local b = c
			if ok and r.group then
				local gi = info(r.group, top)
				ok = gi.shown
				b = cut(b, gi)
			end
			if ok and r.clip then b = cut(b, info(r.clip, top)) end
			if ok and b.x1 >= b.x0 and b.y1 >= b.y0 then
				r.bx = b
				for cx = math.floor(b.x0 / CELL), math.floor(b.x1 / CELL) do
					for cy = math.floor(b.y0 / CELL), math.floor(b.y1 / CELL) do
						local k = cx * 65536 + cy
						local list = cells[k]
						if not list then list = {}; cells[k] = list end
						list[#list + 1] = r
					end
				end
			end
		end
	end
	self.ix = ix
	return ix
end

-- the rect under pos (GUI space), or nil
function Pointer:over(pos)
	if self.root.shown == false then return nil end -- (the root's own flag: no engine read on every move)
	local top = self.root.gui
	local list = self:index(top).cells[math.floor(pos.X / CELL) * 65536 + math.floor(pos.Y / CELL)]
	if not list then return nil end
	local best = nil
	for _, r in ipairs(list) do
		if (not best or r.z > best.z or (r.z == best.z and r.seq > best.seq)) and inside(r.bx, pos) then best = r end
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
