-- ================================================================================================
--  LANES  (HappaTAS 3 ui, spec 8.2): the timeline bar's ▾ panel just above it: Character (state changes,
--  deaths in the recording colour, tools), Inputs, Kit & objects (the kit's events), Buttons. Each event is
--  a 2 x 10 mark at its frame's x on the bar's track; events in the same 2-pixel column share one mark (at
--  most 300 a lane, found by jumping over each column with a binary search). Drawn only when the bar redraws
--  and only while open; open / closed is kept in the settings file (ui.bar.lanes).
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Glass = import("ui/kit/glass")

local Lanes = {}
Lanes.__index = Lanes

local ROW, PAD, GAP, MARKS = 16, 4, 6, 300
-- lane name -> its kinds, the first drawn on top of a shared column
local LANES = {
	{ "Character", { "death", "state", "tool" } },
	{ "Inputs", { "input" } },
	{ "Kit & objects", { "kit" } },
	{ "Buttons", { "button" } },
}

function Lanes.new(bar)
	local ui = bar.ui
	local self = setmetatable({ bar = bar, ui = ui, rows = {}, open = false, built = false }, Lanes)
	local gui = K.frame("Lanes", bar.gui)
	gui.AnchorPoint = Vector2.new(0, 1)
	gui.Position = UDim2.new(0, 0, 0, -GAP)
	gui.Size = UDim2.new(1, 0, 0, PAD * 2 + ROW * #LANES)
	gui.Visible = false
	gui.ZIndex = bar.gui.ZIndex
	self.gui = gui
	local saved = ui.E.settingsFile and ui.E.settingsFile:getUi().bar
	if saved and saved.lanes == true then self:setOpen(true, true) end
	return self
end

-- the rows and their mark pools (made on the first open: closed lanes have no objects to keep up)
function Lanes:build()
	if self.built then return end
	self.built = true
	self.glass = Glass.panel(self.ui.theme, self.gui, { cornerKind = "window", passThrough = true })
	local th = self.ui.theme
	for i, lane in ipairs(LANES) do
		local y = PAD + (i - 1) * ROW
		local label = K.text("TextLabel", "Label", self.glass.panel)
		label.Text = lane[1]
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Position = UDim2.new(0, 14, 0, y)
		label.Size = UDim2.new(0, 110, 0, ROW)
		label.ZIndex = 2
		local area = K.frame("Area", self.glass.panel)
		area.ZIndex = 2
		local marks = {}
		for k = 1, MARKS do
			local m = K.frame("Mark", area, Color3.new(1, 1, 1))
			m.AnchorPoint = Vector2.new(0.5, 0.5)
			m.Size = UDim2.new(0, 2, 0, 10)
			m.Position = UDim2.new(0, 0, 0.5, 0)
			m.Visible = false
			m.ZIndex = 3
			marks[k] = m
		end
		self.rows[lane[1]] = { label = label, area = area, marks = marks, y = y, kinds = lane[2] }
	end
	self.offTheme = th:changed(function() self:restyle(); self:redraw() end)
	self:restyle()
end

function Lanes:restyle()
	local th = self.ui.theme
	for _, row in pairs(self.rows) do
		W.set(row.label, "FontFace", th.font("text"))
		W.set(row.label, "TextSize", th.size(10))
		W.set(row.label, "TextColor3", th.c.text2)
	end
end

function Lanes:setOpen(on, quiet)
	on = on == true
	if on then self:build() end
	self.open = on
	W.set(self.gui, "Visible", on and not self.bar.strip)
	local chev = self.bar.buttons.lanes
	if chev then W.paint(chev.icon.gui, "Rotation", on and 180 or 0) end
	if not quiet then
		local sf = self.ui.E.settingsFile
		if sf then
			local t = sf:getUi()
			t.bar = t.bar or {}
			t.bar.lanes = on
			sf:setUi(t)
		end
	end
	if on then self:redraw() end
end

function Lanes:toggle() self:setOpen(not self.open) end

-- hidden while the bar is a strip (Idle without a run), back when a run comes; open stays the user's choice
function Lanes:fit()
	W.set(self.gui, "Visible", self.open and not self.bar.strip)
end

-- every lane's marks for the bar's view (only while open)
function Lanes:redraw()
	if not self.open or not self.built then return end
	local bar = self.bar
	local model = bar.model
	local v = bar.view
	local span = math.max(1, v.last - v.first)
	local trackX = bar.track.Position.X.Offset
	local tw = bar.trackW
	local th = self.ui.theme
	for _, row in pairs(self.rows) do
		W.paint(row.area, "Position", UDim2.new(0, trackX, 0, row.y))
		W.paint(row.area, "Size", UDim2.new(0, tw, 0, ROW))
		local used, mi = {}, 0
		for _, kind in ipairs(row.kinds) do
			local list = model:events(kind)
			local color = (kind == "death") and th.c.rec or ((kind == "tool") and th.c.accent or th.c.text2)
			local i, i1 = model:range(kind, v.first, v.last)
			while i <= i1 and mi < MARKS do
				local x = bar:xOf(list[i])
				local bucket = math.floor(x / 2)
				if not used[bucket] then
					used[bucket] = true
					mi = mi + 1
					local m = row.marks[mi]
					W.paint(m, "Visible", true)
					W.paint(m, "Position", UDim2.new(0, x, 0.5, 0))
					W.paint(m, "BackgroundColor3", color)
				end
				-- (the first event past this 2-px column)
				local nextF = v.first + (bucket + 1) * 2 / tw * span
				local j = model:range(kind, nextF, v.last)
				i = math.max(i + 1, j)
			end
		end
		-- (only the marks shown last time are hidden: the rest already are)
		for k = mi + 1, row.shown or MARKS do W.paint(row.marks[k], "Visible", false) end
		row.shown = mi
	end
end

function Lanes:destroy()
	if self.offTheme then self.offTheme() end
	if self.glass then self.glass:destroy() end
	pcall(function() self.gui:Destroy() end)
end

return Lanes
