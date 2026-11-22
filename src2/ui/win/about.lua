-- ================================================================================================
--  ABOUT WINDOW  (HappaTAS 3 ui, V3.1): the version, the credits and the update log, in the Dock after Help.
--  The credits come from ui/win/helptext (CREDITS), the log from ui/updatelog (every version since 2.01), the same
--  lists Classic's More page shows. One
--  scrolling page: a rounded panel for the credits, one for the log; the texts wrap and grow with the window.
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local HelpText = import("ui/win/helptext")
local UpdateLog = import("ui/updatelog")
local CONFIG = import("config")

local AboutWin = {}

local PAD = 16

function AboutWin.define(ui)
	ui.wm:define("about", { title = "About", w = 420, h = 440, minW = 320, minH = 240,
		build = function(body, win) ui.aboutWin = AboutWin.build(ui, body, win) end })
	ui:addDockButton("about")
end

-- the log as lines: "HappaTAS <version>", then a bullet per item
function AboutWin.logText() return UpdateLog.text() end


function AboutWin.build(ui, body, win)
	local th = ui.theme
	local aw = { ui = ui, offs = {}, labels = {}, panels = {} }

	local page = Instance.new("ScrollingFrame")
	page.Name = "Page"
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 4
	page.Position = UDim2.new(0, PAD, 0, 10)
	page.Size = UDim2.new(1, -PAD * 2 + 6, 1, -18)
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.Parent = body
	aw.page = page
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = page

	local order = 0
	local function label(name, parent, text, kind)
		order = order + 1
		local l = K.text("TextLabel", name, parent)
		l.LayoutOrder = order
		l.Size = UDim2.new(1, -8, 0, 0)
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.TextWrapped = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextYAlignment = Enum.TextYAlignment.Top
		l.Text = text
		aw.labels[#aw.labels + 1] = { gui = l, kind = kind }
		return l
	end
	-- a rounded panel with a text in it
	local function panel(name, text)
		order = order + 1
		local p = K.frame(name, page, Color3.new(1, 1, 1))
		p.LayoutOrder = order
		p.BackgroundTransparency = 0.92
		p.Size = UDim2.new(1, -8, 0, 0)
		p.AutomaticSize = Enum.AutomaticSize.Y
		K.corner(p, 10)
		K.redrawOnGrow(p, page)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10)
		pad.Parent = p
		aw.panels[name] = p
		local l = label("Text", p, text, "body")
		l.Size = UDim2.new(1, 0, 0, 0)
		return p, l
	end

	aw.title = label("Title", page, "HappaTAS " .. CONFIG.LABEL, "title")
	aw.port = label("Port", page, HelpText.PORT, "small")
	label("CreditsTitle", page, "Credits", "heading")
	aw.credits, aw.creditsText = panel("Credits", table.concat(HelpText.CREDITS, "\n"))
	label("LogTitle", page, "Update log", "heading")
	-- (one label per line, version headings in bold: a self-sizing label stops growing at about the page's
	-- height in Roblox (live: capped at 356 px), so one label per version still cut the longest one off)
	local lines = {}
	for _, e in ipairs(UpdateLog.ENTRIES) do
		lines[#lines + 1] = { e.heading, "heading" }
		for _, b in ipairs(e.bullets) do lines[#lines + 1] = { b, "body" } end
	end
	aw.log, aw.logLabels = panel("UpdateLog", lines[1][1]), {}
	local first = aw.log:FindFirstChild("Text")
	first.Name = "Line0001"
	first.LayoutOrder = 1
	aw.labels[#aw.labels].kind = "heading"
	aw.logLabels[1] = first
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 2)
	list.Parent = aw.log
	for i = 2, #lines do
		local l = label(string.format("Line%04d", i), aw.log, lines[i][1], lines[i][2])
		l.Size = UDim2.new(1, 0, 0, 0)
		l.LayoutOrder = i
		aw.logLabels[i] = l
	end
	function aw.logAll()
		local out = {}
		for i, l in ipairs(aw.logLabels) do out[i] = l.Text end
		return table.concat(out, "\n")
	end

	local function paint()
		for _, it in ipairs(aw.labels) do
			local g, kind = it.gui, it.kind
			W.set(g, "FontFace", th.font((kind == "title" or kind == "heading") and "bold" or "text"))
			W.set(g, "TextSize", th.size(kind == "title" and 16 or kind == "heading" and 13.5 or kind == "small" and 12 or 13))
			W.set(g, "TextColor3", kind == "small" and th.c.text2 or th.c.text)
			W.set(g, "LineHeight", 1.15)
		end
	end
	paint()
	aw.offs[#aw.offs + 1] = th:changed(paint)
	ui.life:own(function() for _, off in ipairs(aw.offs) do off() end end)
	return aw
end

return AboutWin
