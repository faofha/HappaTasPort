-- ================================================================================================
--  WINDOWS  (HappaTAS 3 ui): the window manager (spec 8.2). Windows are defined once (id, title, default
--  and minimum size, build), built on first open, dragged by the title, resized from any edge or the corner
--  grip, minimised to their title bar, closed, brought to the front when pressed. Places are remembered per
--  screen size ("<W>x<H>" of the camera's ViewportSize) in Settings3.json; a screen size with no saved place
--  keeps each window where it is, always fully on screen and below the top bar (Review Focus 3). On a
--  touch-only device a window is a full-width sheet at the bottom, 60 % of the screen high, not movable.
--  Positions are in the interface layer's units (screen pixels / Interface scale).
-- ================================================================================================
local Env = import("platform/env")
local W = import("ui/write")
local Window = import("ui/kit/window")

local Windows = {}
Windows.__index = Windows

local CASCADE = 24
local SHEET_H = 0.6

function Windows.new(E, ui)
	local self = setmetatable({ E = E, ui = ui, defs = {}, order = {}, windows = {}, zTop = 0, conns = {}, listeners = {}, openCount = 0,
		uis = Env.svc("UserInputService"), guiService = Env.svc("GuiService") }, Windows)
	self.key = self:screenKey()
	self:watchCamera()
	self.conns[#self.conns + 1] = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		self:watchCamera()
		self:onScreen()
	end)
	-- (a new interface scale changes the screen in layer units: windows are kept on it; the root's scale is
	-- applied first, whichever listener runs first)
	self.offScale = E.settings:changed("interfaceScale", function()
		ui.root:applyScale()
		self:onScreen()
	end)
	ui.life:own(function() self:destroy() end)
	return self
end

function Windows:watchCamera()
	if self.camConn then self.camConn:Disconnect() end
	local cam = workspace.CurrentCamera
	self.camConn = cam and cam:GetPropertyChangedSignal("ViewportSize"):Connect(function() self:onScreen() end) or nil
end

-- ------------------------------------------------------------------------------------------------ screen
function Windows:viewport()
	local cam = workspace.CurrentCamera
	return cam and cam.ViewportSize or Vector2.new(1920, 1080)
end

function Windows:scale() return self.ui.root.scale.Scale end

function Windows:screenKey()
	local vp = self:viewport()
	return string.format("%dx%d", math.floor(vp.X + 0.5), math.floor(vp.Y + 0.5))
end

-- the screen in layer units, and the top bar's height there
function Windows:screen()
	local vp, s = self:viewport(), self:scale()
	local top = 0
	if self.guiService then pcall(function() top = self.guiService:GetGuiInset().Y end) end
	return vp.X / s, vp.Y / s, top / s
end

function Windows:isSheet() return self.uis.TouchEnabled and not self.uis.KeyboardEnabled end

function Windows:layout()
	local data = self.E.settingsFile:getUi()
	local l = data.layout[self.key]
	return l, data
end

-- ------------------------------------------------------------------------------------------------ place
-- puts win at x, y with size w, h, kept on screen
function Windows:apply(win, x, y, w, h)
	local sw, sh, top = self:screen()
	local def = win.def
	if self:isSheet() then
		w, h = sw, math.floor(sh * SHEET_H)
		x, y = 0, sh - h
	else
		w = math.max(def.minW or 120, math.min(w, sw))
		h = math.max(def.minH or 80, math.min(h, sh - top))
		local shownH = win.min and win.titleH or h
		x = math.max(0, math.min(x, sw - w))
		y = math.max(top, math.min(y, sh - shownH))
	end
	win.x, win.y, win.w, win.h = x, y, w, h
	W.set(win.holder, "Position", UDim2.new(0, x, 0, y))
	W.set(win.holder, "Size", UDim2.new(0, w, 0, win.min and win.titleH or h))
end

function Windows:defaultRect(id)
	local def = self.defs[id]
	local sw, sh = self:screen()
	local i = (table.find(self.order, id) or 1) - 1
	return math.floor((sw - def.w) / 2) + i * CASCADE, math.floor((sh - def.h) / 2) + i * CASCADE, def.w, def.h
end

function Windows:place(id, x, y)
	local win = self.windows[id]
	if win then self:apply(win, x, y, win.w, win.h) end
end

-- remembers id's place for this screen size
function Windows:save(id)
	local win = self.windows[id]
	if not win or self:isSheet() then return end
	local l, data = self:layout()
	if not l then
		l = {}
		data.layout[self.key] = l
	end
	l[id] = { x = win.x, y = win.y, w = win.w, h = win.h, min = win.min }
	self.E.settingsFile:setUi(data)
end

function Windows:onScreen()
	W.bump() -- (anything placed by scale moved)
	self.key = self:screenKey()
	local l = self:layout()
	for id, win in pairs(self.windows) do
		local r = l and l[id]
		if r and type(r.x) == "number" then
			win.min = r.min == true
			self:setMinimised(win, win.min)
			self:apply(win, r.x, r.y, r.w or win.w, r.h or win.h)
		else
			self:apply(win, win.x, win.y, win.w, win.h)
		end
	end
end

-- ------------------------------------------------------------------------------------------------ windows
-- def = { title, w, h, minW, minH, build = f(body, win) }
function Windows:define(id, def)
	if not self.defs[id] then self.order[#self.order + 1] = id end
	self.defs[id] = def
end

function Windows:addRect(win, rect, lz)
	rect.lz = lz
	rect.z = win.z * 100 + lz
	rect.group = rect.group or win.holder
	win.rects[#win.rects + 1] = rect
	self.ui.pointer:add(rect)
	return rect
end

function Windows:removeRect(win, rect)
	local i = table.find(win.rects, rect)
	if i then table.remove(win.rects, i) end
	self.ui.pointer:remove(rect)
end

function Windows:setMinimised(win, on)
	win.min = on == true
	W.set(win.body, "Visible", not win.min)
	W.set(win.grip, "Visible", not win.min)
end

local function resizer(self, win, edge)
	local from
	return {
		gui = edge == "grip" and win.grip or win.edges[edge],
		onPress = function() self:focus(win.id); from = { x = win.x, y = win.y, w = win.w, h = win.h } end,
		onDrag = function(_, d)
			if not from or self:isSheet() or win.min then return end
			d = d / self:scale()
			local def = win.def
			local minW, minH = def.minW or 120, def.minH or 80
			local x, y, w, h = from.x, from.y, from.w, from.h
			if edge == "l" then
				w = math.max(minW, from.w - d.X)
				x = from.x + from.w - w
			elseif edge == "r" or edge == "grip" then
				w = math.max(minW, from.w + d.X)
			end
			if edge == "t" then
				h = math.max(minH, from.h - d.Y)
				y = from.y + from.h - h
			elseif edge == "b" or edge == "grip" then
				h = math.max(minH, from.h + d.Y)
			end
			self:apply(win, x, y, w, h)
		end,
		onRelease = function() from = nil; self:save(win.id) end,
	}
end

function Windows:build(id)
	local def = self.defs[id]
	local win = Window.build(self.ui.theme, self.ui.root.layer, def.title)
	win.id, win.def, win.rects, win.min, win.z = id, def, {}, false, 0
	self.windows[id] = win
	-- (what the window's controls get: the theme, tweens, typing, and pointer rects in the window's layer)
	win.ctx = { E = self.E, ui = self.ui, win = win, theme = self.ui.theme, tween = self.ui.tween, typing = self.E.typing,
		pointer = { add = function(r, z) return self:addRect(win, r, 10 + (z or 0)) end, remove = function(r) self:removeRect(win, r) end } }
	self:addRect(win, { gui = win.panel, onPress = function() self:focus(id) end }, 1)
	local dragFrom = nil
	self:addRect(win, { gui = win.titleBar,
		onPress = function() self:focus(id); dragFrom = Vector2.new(win.x, win.y) end,
		onDrag = function(_, d)
			if not dragFrom or self:isSheet() then return end
			local p = dragFrom + d / self:scale()
			self:apply(win, p.X, p.Y, win.w, win.h)
		end,
		onRelease = function() dragFrom = nil; self:save(id) end }, 2)
	for _, e in ipairs({ "l", "r", "t", "b" }) do self:addRect(win, resizer(self, win, e), 3) end
	self:addRect(win, { gui = win.closeDot, onRelease = function(_, clicked) if clicked then self:close(id) end end }, 4)
	self:addRect(win, { gui = win.minDot, onRelease = function(_, clicked)
		if not clicked then return end
		self:setMinimised(win, not win.min)
		self:apply(win, win.x, win.y, win.w, win.h)
		self:save(id)
	end }, 4)
	self:addRect(win, resizer(self, win, "grip"), 5)
	local l = self:layout()
	local r = l and l[id]
	if r and type(r.x) == "number" then
		self:setMinimised(win, r.min == true)
		self:apply(win, r.x, r.y, r.w or def.w, r.h or def.h)
	else
		self:apply(win, self:defaultRect(id))
	end
	if def.build then
		local ok, err = pcall(def.build, win.body, win)
		if not ok then self.E.errs:report("window " .. id, err) end
	end
	return win
end

function Windows:focus(id)
	local win = self.windows[id]
	if not win then return end
	self.zTop = self.zTop + 1
	win.z = self.zTop
	W.set(win.holder, "ZIndex", self.zTop)
	for _, r in ipairs(win.rects) do r.z = win.z * 100 + r.lz end
end

function Windows:open(id)
	if not self.defs[id] then return end
	local win = self.windows[id] or self:build(id)
	if not win.open then self.openCount = self.openCount + 1 end
	win.open = true
	W.set(win.holder, "Visible", true)
	self:apply(win, win.x, win.y, win.w, win.h)
	self:focus(id)
	self:fire(id, true)
end

function Windows:close(id)
	local win = self.windows[id]
	if not win or not win.open then return end
	win.open = false
	self.openCount = self.openCount - 1
	W.set(win.holder, "Visible", false)
	self:save(id)
	self:fire(id, false)
end

function Windows:toggle(id)
	if self:isOpen(id) then self:close(id) else self:open(id) end
end

function Windows:isOpen(id)
	local win = self.windows[id]
	return win ~= nil and win.open == true
end

-- (asked every frame through E.modalOpen: a count, no loop)
function Windows:anyOpen() return self.openCount > 0 end

-- every window back at its default place and size (this screen size's saved places forgotten)
function Windows:resetLayout()
	local _, data = self:layout()
	data.layout[self.key] = nil
	self.E.settingsFile:setUi(data)
	for id, win in pairs(self.windows) do
		self:setMinimised(win, false)
		self:apply(win, self:defaultRect(id))
	end
end

-- f(id, open) after a window opens or closes (the Dock); returns a remover
function Windows:changed(f)
	local list = self.listeners
	list[#list + 1] = f
	return function()
		local i = table.find(list, f)
		if i then table.remove(list, i) end
	end
end

function Windows:fire(id, open)
	for _, f in ipairs(table.clone(self.listeners)) do pcall(f, id, open) end
end

function Windows:destroy()
	if self.dead then return end
	self.dead = true
	for _, c in ipairs(self.conns) do c:Disconnect() end
	if self.offScale then self.offScale() end
	if self.camConn then self.camConn:Disconnect() end
	for _, win in pairs(self.windows) do
		for _, r in ipairs(win.rects) do self.ui.pointer:remove(r) end
		win:destroy()
	end
	self.windows = {}
	self.openCount = 0
end

return Windows
