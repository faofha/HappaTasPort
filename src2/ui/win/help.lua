-- ================================================================================================
--  HELP WINDOW  (HappaTAS 3 ui, spec 8.3): a search field and the topic list on the left, the topic on the
--  right (ui/win/helptext). The search matches titles and text as you type. Keys in the text are the ones
--  bound now, and "Missing executor functions" lists Env.notes: both are read again whenever a topic shows.
--  Below the topics: Unload HappaTAS (V2's More > Unload; Classic keeps its own).
-- ================================================================================================
local Env = import("platform/env")
local W = import("ui/write")
local K = import("ui/kit/base")
local Field = import("ui/kit/field")
local Button = import("ui/kit/button")
local HelpText = import("ui/win/helptext")

local HelpWin = {}

local SIDE, PAD, ROW_H = 200, 14, 24

function HelpWin.define(ui)
	ui.wm:define("help", { title = "Help", w = 640, h = 470, minW = 480, minH = 300,
		build = function(body, win) ui.helpWin = HelpWin.build(ui, body, win) end })
	ui:addDockButton("help")
end

function HelpWin.build(ui, body, win)
	local E, ctx, th = ui.E, win.ctx, ui.theme
	local hw = { ui = ui, E = E, offs = {}, topicRows = {}, listed = {}, shown = nil, query = "" }

	hw.search = Field.new(ctx, body, { search = true, w = SIDE - PAD, placeholder = "Search help" })
	hw.search.gui.Position = UDim2.new(0, PAD, 0, 10)

	local list = Instance.new("ScrollingFrame")
	list.Name = "Topics"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.Position = UDim2.new(0, 8, 0, 50)
	list.Size = UDim2.new(0, SIDE, 1, -58 - 40)
	list.Parent = body
	hw.list = list
	local lctx = {}
	for k, v in pairs(ctx) do lctx[k] = v end
	lctx.pointer = { add = function(r, z) r.clip = list; return ctx.pointer.add(r, z) end, remove = ctx.pointer.remove }
	local conn = list:GetPropertyChangedSignal("CanvasPosition"):Connect(function() W.bump() end)
	hw.offs[#hw.offs + 1] = function() conn:Disconnect() end

	hw.unload = Button.new(ctx, body, { text = "Unload HappaTAS", kind = "plain", w = SIDE - PAD })
	hw.unload.gui.Position = UDim2.new(0, PAD, 1, -40)
	hw.unload.onClick = function()
		local h = Env.genv.__HappaTAS3
		if h and h.Unload then task.spawn(h.Unload) end
	end

	local page = Instance.new("ScrollingFrame")
	page.Name = "Page"
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 4
	page.Position = UDim2.new(0, SIDE + 18, 0, 10)
	page.Size = UDim2.new(1, -SIDE - 18 - PAD, 1, -18)
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.Parent = body
	hw.page = page
	local title = K.text("TextLabel", "Title", page)
	title.Size = UDim2.new(1, -8, 0, 28)
	title.TextXAlignment = Enum.TextXAlignment.Left
	hw.title = title
	local text = K.text("TextLabel", "Body", page)
	text.Position = UDim2.new(0, 0, 0, 34)
	text.Size = UDim2.new(1, -8, 0, 0)
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.TextWrapped = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	hw.body = text

	local function paintText()
		W.set(title, "FontFace", th.font("bold"))
		W.set(title, "TextSize", th.size(16))
		W.set(title, "TextColor3", th.c.text)
		W.set(text, "FontFace", th.font("text"))
		W.set(text, "TextSize", th.size(13))
		W.set(text, "TextColor3", th.c.text)
		W.set(text, "LineHeight", 1.15)
	end
	paintText()

	local function topicsNow() return HelpText.topics(E) end

	-- shows topic id (its text as it is now: keys, missing functions)
	function hw:show(id)
		for _, t in ipairs(topicsNow()) do
			if t.id == id then
				self.shown = id
				W.set(title, "Text", t.title)
				W.set(text, "Text", t.body)
				W.set(page, "CanvasPosition", Vector2.new(0, 0))
				for _, r in ipairs(self.topicRows) do
					W.set(r.gui, "BackgroundTransparency", (r.id == id) and 0.84 or 1)
				end
				return
			end
		end
	end

	-- the rows (one per topic, made once); the search shows the matching ones, in order
	for i, t in ipairs(topicsNow()) do
		local gui = K.frame("Topic", list, Color3.new(1, 1, 1))
		gui.BackgroundTransparency = 1
		gui.Size = UDim2.new(1, -6, 0, ROW_H)
		K.corner(gui, 8)
		local l = K.text("TextLabel", "Label", gui)
		l.Position = UDim2.new(0, 10, 0, 0)
		l.Size = UDim2.new(1, -14, 1, 0)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextTruncate = Enum.TextTruncate.AtEnd
		l.Text = t.title
		local r = { id = t.id, gui = gui, label = l, index = i }
		r.rect = lctx.pointer.add({ gui = gui, onRelease = function(_, clicked) if clicked then hw:show(t.id) end end }, 1)
		hw.topicRows[#hw.topicRows + 1] = r
	end
	local function paintRows()
		for _, r in ipairs(hw.topicRows) do
			W.set(r.label, "FontFace", th.font("text"))
			W.set(r.label, "TextSize", th.size(12.5))
			W.set(r.label, "TextColor3", th.c.text)
		end
	end
	paintRows()

	function hw:filter()
		local q = string.lower(self.query or "")
		local listed, show = {}, {}
		for _, t in ipairs(topicsNow()) do
			if q == "" or string.lower(t.title):find(q, 1, true) or string.lower(t.body):find(q, 1, true) then
				listed[#listed + 1] = t
				show[t.id] = true
			end
		end
		self.listed = listed
		local y = 0
		for _, r in ipairs(self.topicRows) do
			local on = show[r.id] == true
			W.set(r.gui, "Visible", on)
			if on then
				W.set(r.gui, "Position", UDim2.new(0, 0, 0, y))
				y = y + ROW_H + 2
			end
		end
		W.set(list, "CanvasSize", UDim2.new(0, 0, 0, y))
		-- (the first match shows when the topic shown no longer matches)
		if #listed > 0 and not show[self.shown or ""] then self:show(listed[1].id) end
	end
	hw.search.onInput = function(t)
		hw.query = t or ""
		hw:filter()
	end

	hw.offs[#hw.offs + 1] = ui.wm:changed(function(id, open)
		if id == "help" and open and hw.shown then hw:show(hw.shown) end
	end)
	hw.offs[#hw.offs + 1] = E.controls:changed(function() if win.open and hw.shown then hw:show(hw.shown) end end)
	hw.offs[#hw.offs + 1] = th:changed(function()
		paintText()
		paintRows()
	end)
	ui.life:own(function() for _, off in ipairs(hw.offs) do off() end end)
	hw:filter()
	hw:show("start")
	return hw
end

return HelpWin
