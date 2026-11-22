-- ================================================================================================
--  COMPACT  (HappaTAS 3 ui, V3.1): the third interface (docs/superpowers/specs/2026-11-22-third-interface-
--  design.md): one main window in the theme's compact look (ui/theme compact mode, ui/compact/kit): a title bar
--  (HAPPATAS, the version, LIBRARY and INSPECTOR chips that open the docked side panels, a search box, the
--  status chip, minimise), capital tabs (CONTROLS, SETTINGS, HELP, ABOUT) over scrolling pages, a corner grip.
--  Drag it by the title bar; minimise folds it to the title bar (the panels close with it). Its rect, tab, the
--  Library panel and the fold are saved in the settings file's ui.compact. Kept on screen at load and when the
--  screen changes. It lives in the root's layer with the New interface's bar, toasts and Merge window, which
--  it shares; only one interface is live (ui/app).
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Field = import("ui/kit/field")
local CK = import("ui/compact/kit")
local CONFIG = import("config")
local Host = import("ui/compact/host")
local Controls = import("ui/compact/controls")
local TSettings = import("ui/compact/settings")
local TKeys = import("ui/compact/keys")
local HelpWin = import("ui/win/help")
local AboutWin = import("ui/win/about")
local LibraryWin = import("ui/win/library")
local InspectorWin = import("ui/win/inspector")

local Compact = {}
Compact.__index = Compact

Compact.W, Compact.H, Compact.MIN_W, Compact.MIN_H = 700, 500, 560, 400
Compact.TITLE_H = 28
-- (the Library's narrow layout needs ~320; 260 is the Inspector's own minimum)
Compact.LIB_W, Compact.INS_W, Compact.GAP = 320, 260, 8
Compact.TABS = { "controls", "settings", "help", "about" }
local Z = 20 -- (pointer z: under every New window, so the shared Merge window is above it)

function Compact.new(ui)
	local self = setmetatable({ ui = ui, E = ui.E, live = false, folded = false, tab = "controls", rects = {}, offs = {},
		pieces = {}, pages = {}, tabs = {}, panels = {}, hosted = {} }, Compact)
	local th = ui.theme
	self.ctx = { E = ui.E, ui = ui, theme = th, tween = ui.tween, typing = ui.E.typing,
		-- (controls sit above the window's own rects: the title bar's drag, the grip)
		pointer = { add = function(r, z) return self:addRect(r, 10 + (z or 0)) end, remove = function(r) self:removeRect(r) end } }
	local gui = K.frame("HappaTASCompact", ui.root.layer, Color3.new(0, 0, 0))
	gui.Visible = false
	gui.ZIndex = 0
	gui.Active = true
	self.gui = gui
	self.stroke = K.stroke(gui, Color3.new(1, 1, 1), 0, 1)
	self.line = CK.accentLine(gui)
	self:addRect({ gui = gui }, 0) -- (a press on the window is the window's)
	self:buildTitleBar()
	self:buildBody()
	self.controls = Controls.build(self)
	-- (SETTINGS: its own page in Tasability's style, V3.1)
	self.settingsPage = TSettings.build(self)
	self.pieces[#self.pieces + 1] = self.settingsPage
	-- (KEYS: its own key boxes, V3.1)
	self.keys = TKeys.build(self, self.keysFrame)
	self.pieces[#self.pieces + 1] = self.keys
	self:buildPanel("library", "LIBRARY", Compact.LIB_W, -1)
	self:buildPanel("inspector", "INSPECTOR", Compact.INS_W, 1)
	self.offs[#self.offs + 1] = th:changed(function() self:paint() end)
	self.offs[#self.offs + 1] = ui.wm:screenChanged(function() self:place(self.x, self.y, self.w, self.h) end)
	-- (a merge started from the Library panel: the panel closes, as the Library window does)
	self.offs[#self.offs + 1] = ui.wm:changed(function(id, open)
		if id == "merge" and open and self.panels.library.open then self:setPanel("library", false) end
	end)
	self.search.onInput = function(t)
		if self.tab ~= "settings" then self:showTab("settings") end
		self.settingsPage:filter(t or "")
	end
	self:paint()
	self:load()
	return self
end

-- ------------------------------------------------------------------------------------------------ pointer
function Compact:addRect(r, z)
	r.z = Z + (z or 0)
	r.group = r.group or self.gui
	self.rects[#self.rects + 1] = r
	self.ui.pointer:add(r)
	return r
end

function Compact:removeRect(r)
	local i = table.find(self.rects, r)
	if i then table.remove(self.rects, i) end
	self.ui.pointer:remove(r)
end

-- ------------------------------------------------------------------------------------------------ build
function Compact:buildTitleBar()
	local ctx = self.ctx
	local bar = K.frame("TitleBar", self.gui, Color3.new(0, 0, 0))
	bar.Position = UDim2.new(0, 0, 0, 2)
	bar.Size = UDim2.new(1, 0, 0, Compact.TITLE_H)
	bar.ZIndex = 2
	self.titleBar = bar
	local sep = K.frame("Separator", bar, Color3.new(0, 0, 0))
	sep.AnchorPoint = Vector2.new(0, 1)
	sep.Position = UDim2.new(0, 0, 1, 0)
	sep.Size = UDim2.new(1, 0, 0, 1)
	self.sep = sep
	local name = K.text("TextLabel", "Name", bar)
	name.Text = "HAPPATAS"
	name.Position = UDim2.new(0, 8, 0, 0)
	name.Size = UDim2.new(0, 78, 1, 0)
	name.TextXAlignment = Enum.TextXAlignment.Left
	K.stroke(name, Color3.new(0, 0, 0), 0, 1)
	self.name = name
	local function chip(text, x, w, opts)
		local c = CK.chip(ctx, bar, text, opts)
		c.gui.Position = UDim2.new(x < 0 and 1 or 0, x, 0, 5)
		c.gui.Size = UDim2.new(0, w, 0, 18)
		c.gui.ZIndex = 3
		self.pieces[#self.pieces + 1] = c
		return c
	end
	self.version = chip(CONFIG.LABEL, 90, 56, { bold = false })
	self.libraryChip = chip("LIBRARY", 154, 64, { button = true, onClick = function() self:setPanel("library", not self.panels.library.open) end })
	self.inspectorChip = chip("INSPECTOR", 224, 74, { button = true, onClick = function() self:setPanel("inspector", not self.panels.inspector.open) end })
	self.status = chip("Idle", -154, 118, { bold = false })
	self.status.label.TextXAlignment = Enum.TextXAlignment.Left
	self.status.label.Position = UDim2.new(0, 6, 0, 0)
	self.minimise = chip("_", -30, 22, { button = true, onClick = function() self:setFolded(not self.folded) end })
	local search = Field.new(ctx, bar, { w = 160, placeholder = "search settings..." })
	search.gui.Position = UDim2.new(1, -322, 0, 5)
	search.gui.Size = UDim2.new(0, 160, 0, 18)
	search.gui.ZIndex = 3
	self.search = search
	self.pieces[#self.pieces + 1] = search
	-- (drag by the title bar; chips and the box are above it)
	local from = nil
	self:addRect({ gui = bar,
		onPress = function() from = Vector2.new(self.x, self.y) end,
		onDrag = function(_, d)
			if not from then return end
			local p = from + d / self.ui.root.scale.Scale
			self:place(p.X, p.Y, self.w, self.h)
		end,
		onRelease = function() if from then from = nil; self:save() end end }, 1)
end

function Compact:buildBody()
	local ctx = self.ctx
	local inline = K.frame("Inline", self.gui, Color3.new(0, 0, 0))
	inline.Position = UDim2.new(0, 7, 0, Compact.TITLE_H + 6)
	inline.Size = UDim2.new(1, -14, 1, -(Compact.TITLE_H + 13))
	inline.ZIndex = 1
	self.inline = inline
	self.inlineStroke = CK.border(inline)
	for i, id in ipairs(Compact.TABS) do
		local t = CK.tab(ctx, inline, id, function() self:showTab(id) end)
		t.gui.Position = UDim2.new(0, 7 + (i - 1) * 95, 0, 7)
		t.gui.ZIndex = 2
		self.tabs[id] = t
		self.pieces[#self.pieces + 1] = t
	end
	local content = K.frame("Content", inline, Color3.new(0, 0, 0))
	content.Position = UDim2.new(0, 7, 0, 34)
	content.Size = UDim2.new(1, -14, 1, -41)
	content.ClipsDescendants = true
	content.ZIndex = 1
	self.content = content
	self.contentStroke = CK.border(content)
	for _, id in ipairs(Compact.TABS) do
		-- (CONTROLS scrolls itself; a hosted window's page is a plain frame: the window scrolls its own list)
		local page = Instance.new(id == "controls" and "ScrollingFrame" or "Frame")
		page.Name = "Page_" .. id
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.Size = UDim2.new(1, 0, 1, 0)
		if id == "controls" then
			page.ScrollBarThickness = 2
			page.CanvasSize = UDim2.new(0, 0, 0, 0)
			page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		end
		page.Visible = id == self.tab
		page.ZIndex = 2
		page.Parent = content
		self.pages[id] = page
		if page:IsA("ScrollingFrame") then
			-- (the pointer keeps rects' bounds until told: a scroll moves them, V3.1)
			local conn = page:GetPropertyChangedSignal("CanvasPosition"):Connect(function() W.bump() end)
			self.offs[#self.offs + 1] = function() conn:Disconnect() end
		end
	end
	local grip = K.frame("Grip", self.gui)
	grip.AnchorPoint = Vector2.new(1, 1)
	grip.Position = UDim2.new(1, -2, 1, -2)
	grip.Size = UDim2.new(0, 14, 0, 14)
	grip.ZIndex = 6
	for i, p in ipairs({ { 10, 4 }, { 10, 10 }, { 4, 10 } }) do
		local g = K.frame("G" .. i, grip, Color3.new(1, 1, 1))
		g.Size = UDim2.new(0, 2, 0, 2)
		g.Position = UDim2.new(0, p[1], 0, p[2])
		g.BackgroundTransparency = 0.3
		g.ZIndex = 6
	end
	self.grip = grip
	-- (CONTROLS: the KEYS section holds the Controls window's list)
	local keys = CK.section(ctx, self.pages.controls, "keys")
	keys.gui.Size = UDim2.new(1, -4, 0, 0)
	self.pieces[#self.pieces + 1] = keys
	local kf = K.frame("Keys", keys.body)
	kf.Size = UDim2.new(1, 0, 0, 320)
	self.keysSection, self.keysFrame = keys, kf
	local start = nil
	self:addRect({ gui = grip,
		onPress = function() start = Vector2.new(self.w, self.h) end,
		onDrag = function(_, d)
			if not start then return end
			local s = d / self.ui.root.scale.Scale
			self:place(self.x, self.y, start.X + s.X, start.Y + s.Y)
		end,
		onRelease = function() if start then start = nil; self:save() end end }, 6)
end

-- a side panel docked to the window's left (side -1) or right (side 1): { gui, body, open }
function Compact:buildPanel(id, title, width, side)
	local gui = K.frame("Panel_" .. id, self.gui, Color3.new(0, 0, 0))
	gui.Size = UDim2.new(0, width, 1, 0)
	gui.Position = side < 0 and UDim2.new(0, -width - Compact.GAP, 0, 0) or UDim2.new(1, Compact.GAP, 0, 0)
	gui.Visible = false
	gui.Active = true
	gui.ZIndex = 0
	local stroke = K.stroke(gui, Color3.new(1, 1, 1), 0, 1)
	local line = CK.accentLine(gui)
	local bar = K.frame("TitleBar", gui, Color3.new(0, 0, 0))
	bar.Position = UDim2.new(0, 0, 0, 2)
	bar.Size = UDim2.new(1, 0, 0, 22)
	local name = K.text("TextLabel", "Name", bar)
	name.Text = title
	name.Position = UDim2.new(0, 8, 0, 0)
	name.Size = UDim2.new(1, -16, 1, 0)
	name.TextXAlignment = Enum.TextXAlignment.Left
	K.stroke(name, Color3.new(0, 0, 0), 0, 1)
	local body = K.frame("Body", gui)
	body.Position = UDim2.new(0, 4, 0, 28)
	body.Size = UDim2.new(1, -8, 1, -32)
	body.ClipsDescendants = true
	local p = { id = id, gui = gui, body = body, open = false, width = width, side = side, stroke = stroke, line = line,
		bar = bar, name = name }
	self.panels[id] = p
	-- (a panel is outside the window: its rects are grouped with the panel, or the pointer cuts them away)
	self:addRect({ gui = gui, group = gui }, 0)
	return p
end

-- ------------------------------------------------------------------------------------------------ look
function Compact:paint()
	local th = self.ui.theme
	local s = th.shades
	if not s then return end
	W.set(self.gui, "BackgroundColor3", s.window)
	W.set(self.stroke, "Color", th.c.accent)
	W.set(self.line, "BackgroundColor3", th.c.accent)
	W.set(self.titleBar, "BackgroundColor3", s.deep)
	W.set(self.sep, "BackgroundColor3", s.outline)
	W.set(self.name, "FontFace", th.font("bold"))
	W.set(self.name, "TextSize", th.size(13))
	W.set(self.name, "TextColor3", th.c.accent)
	W.set(self.inline, "BackgroundColor3", s.inline)
	CK.paintBorder(self.inline, self.inlineStroke, th)
	W.set(self.content, "BackgroundColor3", s.deep)
	CK.paintBorder(self.content, self.contentStroke, th)
	W.set(self.pages.controls, "ScrollBarImageColor3", th.c.accent)
	for _, p in pairs(self.panels) do
		W.set(p.gui, "BackgroundColor3", s.window)
		W.set(p.stroke, "Color", th.c.accent)
		W.set(p.line, "BackgroundColor3", th.c.accent)
		W.set(p.bar, "BackgroundColor3", s.deep)
		W.set(p.name, "FontFace", th.font("bold"))
		W.set(p.name, "TextSize", th.size(11))
		W.set(p.name, "TextColor3", th.c.accent)
	end
end

-- ------------------------------------------------------------------------------------------------ state
function Compact:shownH() return self.folded and (Compact.TITLE_H + 2) or self.h end

-- puts the window at x, y (layer units) with size w, h, kept on screen; nil x / y: centred
function Compact:place(x, y, w, h)
	local sw, sh, top = self.ui.wm:screen()
	w = math.max(Compact.MIN_W, math.min(w or Compact.W, sw))
	h = math.max(Compact.MIN_H, math.min(h or Compact.H, sh - top))
	if type(x) ~= "number" then x = (sw - w) / 2 end
	if type(y) ~= "number" then y = top + (sh - top - h) / 2 end
	-- (open side panels stay on screen too, when there is room for them)
	local lib, ins = self.panels.library, self.panels.inspector
	local left = (lib and lib.open and not self.folded) and (lib.width + Compact.GAP) or 0
	local right = (ins and ins.open and not self.folded) and (ins.width + Compact.GAP) or 0
	if left + w + right > sw then left, right = 0, 0 end
	x = math.max(left, math.min(x, sw - w - right))
	y = math.max(top, math.min(y, sh - (self.folded and (Compact.TITLE_H + 2) or h)))
	self.x, self.y, self.w, self.h = x, y, w, h
	W.set(self.gui, "Position", UDim2.new(0, x, 0, y))
	W.set(self.gui, "Size", UDim2.new(0, w, 0, self:shownH()))
	for _, p in pairs(self.panels) do W.set(p.gui, "Size", UDim2.new(0, p.width, 0, h)) end
end

function Compact:applyVisible()
	local on = self.live
	-- (a dropdown list left open closes when the window folds or the interface changes)
	if self.settingsPage and not (on and not self.folded) then self.settingsPage:closePopups() end
	W.set(self.gui, "Visible", on)
	W.set(self.inline, "Visible", not self.folded)
	W.set(self.grip, "Visible", not self.folded)
	for _, p in pairs(self.panels) do W.set(p.gui, "Visible", on and p.open and not self.folded) end
	W.set(self.gui, "Size", UDim2.new(0, self.w or Compact.W, 0, self:shownH()))
end

function Compact:setLive(on)
	self.live = on == true
	self:applyVisible()
	self:syncHosted()
	if self.controls then self.controls:follow(self.live) end
end

-- ------------------------------------------------------------------------------------------------ hosting
-- what each hosted window is built from and where it goes
function Compact:hostSpec(id)
	local p = self.pages
	if id == "help" then return HelpWin.build, p.help end
	if id == "about" then return AboutWin.build, p.about end
	if id == "library" then return LibraryWin.build, self.panels.library.body, { narrow = true, group = self.panels.library.gui } end
	if id == "inspector" then return InspectorWin.build, self.panels.inspector.body, { group = self.panels.inspector.gui } end
	return nil
end

-- the hosted window id (built the first time it is needed)
function Compact:host(id)
	local h = self.hosted[id]
	if h then return h end
	local build, parent, opts = self:hostSpec(id)
	if not (build and parent) then return nil end
	h = Host.new(self, id, build, parent, opts)
	self.hosted[id] = h
	if self.E.typing and h.frame then self.E.typing:watch(h.frame) end
	return h
end

-- each hosted window open while it shows (its per-frame work and refreshes follow win.open)
function Compact:syncHosted()
	local shown = self.live and not self.folded
	for _, id in ipairs(Compact.TABS) do
		if self.hosted[id] or (shown and self.tab == id) then
			local h = self:host(id)
			if h then h:setOpen(shown and self.tab == id) end
		end
	end
	for id, p in pairs(self.panels) do
		if self.hosted[id] or (shown and p.open) then
			local h = self:host(id)
			if h then h:setOpen(shown and p.open) end
		end
	end
end

-- a key being bound ends with the interface going away
function Compact:endTyping()
	if self.keys then self.keys:stopWaiting() end
end

function Compact:showTab(id)
	if not self.pages[id] then return end
	self.tab = id
	for name, page in pairs(self.pages) do W.set(page, "Visible", name == id) end
	for name, t in pairs(self.tabs) do t:setActive(name == id) end
	self:syncHosted()
	if self.onTab then self.onTab(id) end
	self:save()
end

function Compact:setPanel(id, on)
	local p = self.panels[id]
	if not p then return end
	p.open = on == true
	if p.open and self.folded then self:setFolded(false) end
	if self.x then self:place(self.x, self.y, self.w, self.h) end
	self:applyVisible()
	self:syncHosted()
	if self.onPanel then self.onPanel(id, p.open) end
	if id == "library" then self:save() end
end

function Compact:setFolded(on)
	self.folded = on == true
	self:place(self.x, self.y, self.w, self.h)
	self:applyVisible()
	self:syncHosted()
	self.ui:updateModal()
	self:save()
end

-- the window frees the mouse (like a New window) while it is live, shown and unfolded
-- (not while the Merge window is open: you play during a merge, as with the New interface, V3.1 review)
function Compact:modal() return self.live and not self.folded and not self.ui.wm:isOpen("merge") end

function Compact:pointerOver() return self.live and self.ui.pointer ~= nil and self.ui.pointer:busy() end

-- ------------------------------------------------------------------------------------------------ saving
function Compact:load()
	local sf = self.E.settingsFile
	local t = sf and sf:getUi().compact or {}
	self.folded = t.folded == true
	self.panels.library.open = t.library == true
	self:place(t.x, t.y, t.w, t.h)
	local tab = (type(t.tab) == "string" and self.pages[t.tab]) and t.tab or "controls"
	self.tab = tab
	for name, page in pairs(self.pages) do page.Visible = name == tab end
	for name, tb in pairs(self.tabs) do tb:setActive(name == tab) end
	self:applyVisible()
end

function Compact:save()
	local sf = self.E.settingsFile
	if not sf or not self.x then return end
	local data = sf:getUi()
	data.compact = { x = self.x, y = self.y, w = self.w, h = self.h, tab = self.tab, library = self.panels.library.open,
		folded = self.folded }
	sf:setUi(data)
end

function Compact:destroy()
	if self.dead then return end
	self.dead = true
	for _, off in ipairs(self.offs) do pcall(off) end
	for _, pc in ipairs(self.pieces) do pcall(function() pc:destroy() end) end
	for _, r in ipairs(self.rects) do self.ui.pointer:remove(r) end
	self.rects = {}
	pcall(function() self.gui:Destroy() end)
end

return Compact
