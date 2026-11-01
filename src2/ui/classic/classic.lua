-- ================================================================================================
--  CLASSIC  (HappaTAS 3 ui, spec 8.5): V2.38.17's interface drawn by HappaTAS 3, for people who prefer it.
--  Its own ScreenGui ("HappaTASClassic") next to the new interface's, built from V2's tree (ui/classic/tree)
--  the first time Classic is chosen (UI:setInterface). Only one interface is live; this one answers the
--  engine's questions while it is (pointerOver: the mouse on its open menu; modal: the menu open frees the
--  mouse). As in V2: the Menu key opens / closes the main menu (the stats panels stay), its tabs are
--  Controls / Settings / Saves / Help / More, a status line shows messages, and "HappaTAS Loaded" slides in
--  at the start. Help shows HappaTAS 3's topics (ui/win/helptext) in V2's expandable rows. The menu can be
--  dragged by its title; its place is kept per screen size (settings file: ui.classic.menu), apart from the
--  new interface's windows.
-- ================================================================================================
local Env = import("platform/env")
local ClassicTree = import("ui/classic/tree")
local ClassicBuild = import("ui/classic/build")
local SettingsRows = import("ui/classic/settingsrows")
local ControlsRows = import("ui/classic/controlsrows")
local Saves = import("ui/classic/saves")
local HelpText = import("ui/win/helptext")

local Classic = {}
Classic.__index = Classic

local NAME = "HappaTASClassic"
local DISPLAY_ORDER = 10
local TABS = { "Controls", "Settings", "Saves", "Help", "More" }
local STATUS_TIME = 2.5
local u = UDim2.new

function Classic.new(ui)
	local E = ui.E
	local self = setmetatable({ ui = ui, E = E, shown = true, offs = {}, helpRows = {}, openHelp = nil }, Classic)
	local parent = ui.root.gui.Parent
	if parent then
		for _, g in ipairs(parent:GetChildren()) do
			if g.Name == NAME and g:IsA("ScreenGui") then pcall(function() g:Destroy() end) end
		end
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = NAME
	gui.ResetOnSpawn = false -- (IgnoreGuiInset off and Global ZIndex, as V2's UI.Create)
	pcall(function() gui.AutoLocalize = false end)
	pcall(function() gui.ZIndexBehavior = Enum.ZIndexBehavior.Global end)
	pcall(function() gui.DisplayOrder = DISPLAY_ORDER end)
	self.gui = gui
	-- V2.38.17's tree (byPath["MainMenu.SettingsFrame.List"] = that instance)
	local _, byPath = ClassicBuild.build(ClassicTree.TREE, ClassicTree.STYLES, gui)
	self.byPath = byPath
	self.menu = byPath.MainMenu
	self.uis = Env.svc("UserInputService")
	self.guiService = Env.svc("GuiService")
	self.ts = Env.svc("TweenService")
	self.settingsRows = SettingsRows.build(self)
	self.controlRows = ControlsRows.build(self)
	self.saves = Saves.build(self)
	self:buildHelp()
	self:wire()
	self:placeMenu()
	pcall(function() gui.Parent = parent end)
	self.touch = self.uis ~= nil and self.uis.TouchEnabled and not self.uis.KeyboardEnabled
	if self.touch then
		-- (touch screens: no Controls tab, the other four in a row: V2's p19_menu.lua)
		byPath["MainMenu.ControlsToggle"].Visible = false
		for x, t in pairs({ [0] = "Settings", [0.25] = "Saves", [0.5] = "Help", [0.75] = "More" }) do
			byPath["MainMenu." .. t .. "Toggle"].Position = u(x, 0, 0.108, 0)
			byPath["MainMenu." .. t .. "Toggle"].Size = u(0, 100, 0, 30)
		end
		self:tab("Settings")
	else
		self:tab("Controls")
	end
	self:joinMessage()
	return self
end

-- ------------------------------------------------------------------------------------------------ menu
-- the Menu key: V2's menu.Visible (the stats panels stay)
function Classic:toggle()
	self.menu.Visible = not self.menu.Visible
	self.ui:updateModal()
end

-- shown / hidden as the live interface (UI:setInterface)
function Classic:show(on)
	self.shown = on == true
	self.gui.Enabled = self.shown and self.ui.live == "Classic"
	self.ui:updateModal()
end

-- the menu or the merge dialog is open: the mouse is free (V2's Menu.IsModalOpen)
function Classic:modal()
	return self.shown and (self.menu.Visible == true or self.byPath.Merge.Visible == true)
end

-- V2's tab(): the chosen tab's button lighter, its frame shown
function Classic:tab(name)
	local b = self.byPath
	for _, t in ipairs(TABS) do
		b["MainMenu." .. t .. "Toggle"].BackgroundTransparency = 0.75
		b["MainMenu." .. t .. "Frame"].Visible = false
	end
	b["MainMenu." .. name .. "Toggle"].BackgroundTransparency = 0.5
	b["MainMenu." .. name .. "Frame"].Visible = not (self.touch and name == "Controls")
	self.tabName = name
	if name == "Saves" and self.saves then self.saves.refresh() end
end

function Classic:wire()
	local E, ui, life, b = self.E, self.ui, self.ui.life, self.byPath
	for _, t in ipairs(TABS) do
		life:connect(b["MainMenu." .. t .. "Toggle"].MouseButton1Click, function() self:tab(t) end)
	end
	life:connect(b["MainMenu.MoreFrame.List.1Model"].MouseButton1Click, function()
		local h = Env.genv.__HappaTAS3
		if h and h.Unload then task.spawn(h.Unload) end
	end)
	life:connect(b["MainMenu.MoreFrame.List.ToggleMicroProfiler"].MouseButton1Click, function()
		E.settings:set("showMicroProfiler", E.settings:on("showMicroProfiler") and 0 or 1)
	end)
	life:connect(b["JoinMessage.Close"].MouseButton1Click, function() b.JoinMessage.Visible = false end)
	-- the status line (V2's SetStatus): a message for a few seconds
	self.offs[#self.offs + 1] = E.bus:on("status", function(text) self:status(text) end)
	-- dragging the menu by its title
	local title = b["MainMenu.Title"]
	local from, start = nil, nil
	life:connect(self.uis.InputBegan, function(inp)
		if ui.live ~= "Classic" or not self:modal() then return end
		local t = inp.UserInputType
		if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
		local p, s, pos = title.AbsolutePosition, title.AbsoluteSize, inp.Position
		if pos.X >= p.X and pos.X <= p.X + s.X and pos.Y >= p.Y and pos.Y <= p.Y + s.Y then
			from, start = Vector2.new(pos.X, pos.Y), self.menuOffset or Vector2.zero
		end
	end)
	life:connect(self.uis.InputChanged, function(inp)
		if not from then return end
		local t = inp.UserInputType
		if t ~= Enum.UserInputType.MouseMovement and t ~= Enum.UserInputType.Touch then return end
		local d = Vector2.new(inp.Position.X, inp.Position.Y) - from
		self:moveMenu(start + d)
	end)
	life:connect(self.uis.InputEnded, function(inp)
		if not from then return end
		local t = inp.UserInputType
		if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
		from = nil
		self:saveMenu()
	end)
end

function Classic:status(text)
	local label = self.byPath.Status
	label.Text = tostring(text or "")
	self.statusSeq = (self.statusSeq or 0) + 1
	local seq = self.statusSeq
	task.delay(STATUS_TIME, function()
		if self.statusSeq == seq and not self.dead then label.Text = "" end
	end)
end

-- "HappaTAS Loaded" slides in, then out (V2's join message)
function Classic:joinMessage()
	local jm = self.byPath.JoinMessage
	local ts = self.ts
	if not ts then return end
	pcall(function()
		ts:Create(jm, TweenInfo.new(1, Enum.EasingStyle.Quad), { Position = u(0, 10, 1, -10) }):Play()
	end)
	task.delay(5, function()
		if self.dead then return end
		pcall(function()
			ts:Create(jm, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = u(0, 10, 1, 150) }):Play()
		end)
	end)
end

-- ------------------------------------------------------------------------------------------------ the menu's place
local function screenKey(ui) return ui.wm and ui.wm:screenKey() or "default" end

function Classic:moveMenu(offset)
	self.menuOffset = offset
	self.menu.Position = u(0.5, offset.X, 0.5, offset.Y)
end

function Classic:saveMenu()
	local sf = self.E.settingsFile
	if not sf or not self.menuOffset then return end
	local t = sf:getUi()
	t.classic = t.classic or { menu = {} }
	t.classic.menu = t.classic.menu or {}
	t.classic.menu[screenKey(self.ui)] = { x = self.menuOffset.X, y = self.menuOffset.Y }
	sf:setUi(t)
end

function Classic:placeMenu()
	local sf = self.E.settingsFile
	local t = sf and sf:getUi()
	local p = t and t.classic and t.classic.menu and t.classic.menu[screenKey(self.ui)]
	if p then self:moveMenu(Vector2.new(p.x, p.y)) end
end

-- ------------------------------------------------------------------------------------------------ help
-- one V2-style expandable row per topic (p04_ui.lua H(); V2's own texts described V2)
function Classic:buildHelp()
	local list = self.byPath["MainMenu.HelpFrame.List"]
	local spacer = self.byPath["MainMenu.HelpFrame.List.Spacer"]
	for i, t in ipairs(HelpText.topics(self.E)) do
		local lines = 0
		for para in (t.body .. "\n"):gmatch("([^\n]*)\n") do lines = lines + math.max(1, math.ceil(#para / 46)) end
		local h = lines * 17 + 30
		local name = string.format("H%02d", i)
		local node = { "TextButton", name, 50, { Position = u(0, 0, 0, 0), Size = u(1, 0, 0, 40), Text = "", TextSize = 8 }, {
			{ "UICorner", "UICorner", 5, {} },
			{ "TextLabel", "N", 47, { Position = u(0, 15, 0, 0), Size = u(0.7, 0, 1, 0), Text = t.title, TextSize = 20 } },
			{ "TextLabel", "Expand", 51, { Position = u(1, -10, 0.5, 0), Size = u(0, 30, 0, 30), AnchorPoint = Vector2.new(1, 0.5), ZIndex = 2,
				Text = "+", TextSize = 30 }, { { "UICorner", "UICorner", 5, {} } } },
			{ "Frame", "Expansion", 52, { Position = u(0, 0, 1, -8), Size = u(1, 0, 0, h), Visible = false }, {
				{ "UICorner", "UICorner", 5, {} },
				{ "Frame", "InnerBox", 19, { Position = u(0, 10, 0, 15), Size = u(1, -20, 1, -20) }, {
					{ "TextLabel", "01", 49, { Position = u(0, 0, 0, 0), Size = u(1, 0, 1, 0), Text = t.body, TextSize = 14 } },
				} },
			} },
			{ "UIStroke", "UIStroke", 22, {} },
		} }
		local b = ClassicBuild.node(node, ClassicTree.STYLES)
		b.Parent = list
		local row = { id = t.id, button = b, expansion = b.Expansion, expand = b.Expand, h = h, name = name }
		self.helpRows[i] = row
		self.ui.life:connect(b.MouseButton1Click, function() self:openHelpRow(row) end)
	end
	self.helpSpacer = spacer
end

-- V2's expandable help: one open at a time, a spacer under it as tall as its box
function Classic:openHelpRow(row)
	local open = self.openHelp
	if open then
		open.expansion.Visible = false
		open.expand.Text = "+"
		if open.spacer then open.spacer:Destroy(); open.spacer = nil end
		self.openHelp = nil
		if open == row then return end
	end
	row.expansion.Visible = true
	row.expand.Text = "-"
	local sp = self.helpSpacer and self.helpSpacer:Clone()
	if sp then
		sp.Name = row.name .. "Spacer"
		sp.Size = u(0, 0, 0, row.h - 8)
		sp.Parent = row.button.Parent
		row.spacer = sp
	end
	self.openHelp = row
end

-- ------------------------------------------------------------------------------------------------ the engine's questions
-- the mouse (m: UserInputService:GetMouseLocation()) is on the open menu, the merge dialog or Merge Stats (a
-- click there is never a Pause / Unpause)
function Classic:pointerOver(m)
	if not self.shown then return false end
	if not m then
		local ok, v = pcall(self.uis.GetMouseLocation, self.uis)
		if not ok then return false end
		m = v
	end
	local inset = Vector2.zero
	if self.guiService then pcall(function() inset = self.guiService:GetGuiInset() end) end
	local x, y = m.X - inset.X, m.Y - inset.Y
	for _, g in ipairs({ self.menu, self.byPath.Merge, self.byPath.MergeStats }) do
		if g.Visible then
			local p, s = g.AbsolutePosition, g.AbsoluteSize
			if x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y then return true end
		end
	end
	return false
end

function Classic:destroy()
	if self.dead then return end
	self.dead = true
	for _, off in ipairs(self.offs) do off() end
	self.offs = {}
	pcall(function() self.gui:Destroy() end)
end

return Classic
