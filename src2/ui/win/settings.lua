-- ================================================================================================
--  SETTINGS WINDOW  (HappaTAS 3 ui, spec 8.3): a search box, section chips, and every setting as a row in
--  its section, in schema order, with the control its kind needs: toggle, slider (typeable), number box,
--  segmented choice, dropdown (fonts drawn in their font, previewed on hover), colour swatch (opens the
--  colour picker), saved looks (Theme: pick one, Save as…). The ↺ reset button shows while a value isn't
--  its default; RESET SECTION while any row of the section isn't. Every control listens to the settings
--  store, so a change made anywhere shows at once (Review Focus 4). The custom curve's four values are
--  edited in the curve editor under Easing, shown while Easing is Custom.
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local Settings = import("engine/settings")
local Toggle = import("ui/kit/toggle")
local Slider = import("ui/kit/slider")
local Segmented = import("ui/kit/segmented")
local Dropdown = import("ui/kit/dropdown")
local Field = import("ui/kit/field")
local Button = import("ui/kit/button")
local Row = import("ui/kit/row")
local ColorPicker = import("ui/kit/colorpicker")
local Bezier = import("ui/kit/bezier")

local SettingsWin = {}

local SECTIONS = { "Appearance", "Playback", "Create", "Speed hack", "Inputs", "World sync", "Interface" }
local BEZIER = { bezierX1 = true, bezierY1 = true, bezierX2 = true, bezierY2 = true }
local PERCENT = { glassTransparency = true, blurStrength = true, edgeLight = true, interfaceScale = true }
local HEADER_H, PAD = 30, 18

local function num(v)
	if v == math.floor(v) then return tostring(v) end
	return (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", ""))
end

local function fmtFor(key)
	if PERCENT[key] then return function(v) return num(v) .. "%" end end
	if key == "windowCorners" then return function(v) return num(v) .. "px" end end
	if key == "animationLength" then return function(v) return num(v) .. "s" end end
	return num
end

local function isDefault(def, v)
	if type(v) == "number" and type(def.default) == "number" then return math.abs(v - def.default) < 1e-9 end
	return v == def.default
end

-- ------------------------------------------------------------------------------------------------ controls
local Swatch = {}
Swatch.__index = Swatch
Swatch.destroy = K.destroy

local function swatch(ctx, s, key)
	local self = K.new(ctx, Swatch)
	local gui = K.frame("Swatch", nil, Color3.new(1, 1, 1))
	gui.Size = UDim2.new(0, 20, 0, 20)
	K.corner(gui, 10)
	K.stroke(gui, Color3.new(1, 1, 1), 0.65, 1.5)
	self.gui, self.swatch = gui, gui
	self.set = function(_, v) W.set(gui, "BackgroundColor3", Color3.fromHex(tostring(v):sub(2))) end
	K.rect(self, { onRelease = function(_, clicked)
		if clicked then ColorPicker.open(ctx, gui, { value = s:get(key), onApply = function(hex) s:set(key, hex) end }) end
	end })
	self:set(s:get(key))
	return self
end

local function appearanceKeys()
	local keys = {}
	for _, def in ipairs(Settings.SCHEMA) do
		if def.section == "Appearance" and def.key ~= "theme" then keys[#keys + 1] = def end
	end
	return keys
end

local function themeControl(ctx, s, sw)
	local self = K.new(ctx, {})
	local gui = K.frame("Theme", nil)
	gui.Size = UDim2.new(0, 238, 0, 24)
	self.gui = gui
	local sf = ctx.E.settingsFile
	local function options()
		local names = {}
		for name in pairs(sf:getUi().themes) do names[#names + 1] = name end
		table.sort(names)
		table.insert(names, 1, "Default")
		return names
	end
	local dd = Dropdown.new(ctx, gui, { options = options(), w = 150 })
	local saveAs = Button.new(ctx, gui, { text = "Save as…", kind = "plain", w = 80 })
	saveAs.gui.Position = UDim2.new(0, 158, 0, 0)
	local nameField = Field.new(ctx, gui, { w = 150, placeholder = "Name" })
	W.set(nameField.gui, "Visible", false)
	self.dropdown, self.saveAs, self.nameField = dd, saveAs, nameField
	local function apply(name)
		if name == "Default" then
			for _, def in ipairs(appearanceKeys()) do s:set(def.key, def.default) end
		else
			local look = sf:getUi().themes[name]
			if not look then return end
			for k, v in pairs(look) do s:set(k, v) end
		end
		s:set("theme", name)
	end
	self.apply = apply
	dd.onChange = apply
	saveAs.onClick = function()
		nameField:set("")
		W.set(dd.gui, "Visible", false)
		W.set(nameField.gui, "Visible", true)
		nameField.box:CaptureFocus()
	end
	nameField.onCommit = function(t)
		W.set(nameField.gui, "Visible", false)
		W.set(dd.gui, "Visible", true)
		local name = tostring(t):gsub("^%s+", ""):gsub("%s+$", "")
		if name == "" then return true end
		if name:lower() == "default" then
			ctx.E.bus:emit("status", "\"Default\" can't be overwritten: pick another name", true)
			return true
		end
		local data = sf:getUi()
		local look = {}
		for _, def in ipairs(appearanceKeys()) do look[def.key] = s:get(def.key) end
		data.themes[name] = look
		sf:setUi(data)
		dd.options = options()
		s:set("theme", name)
		return true
	end
	self.set = function(_, v)
		if not table.find(dd.options, v) then dd.options = options() end
		dd:set(v)
	end
	self.destroy = function()
		dd:destroy(); saveAs:destroy(); nameField:destroy()
		K.destroy(self)
	end
	self:set(s:get("theme"))
	return self
end

local function controlFor(ctx, s, def, sw)
	local key, v = def.key, s:get(def.key)
	local ctl, kind
	if key == "theme" then
		ctl, kind = themeControl(ctx, s, sw), "theme"
	elseif def.kind == "toggle" then
		ctl, kind = Toggle.new(ctx, nil), "toggle"
		ctl.onChange = function(on) s:set(key, on and 1 or 0) end
		ctl:set(v == 1)
		local set = ctl.set
		ctl.set = function(c, x) set(c, x == 1 or x == true) end
	elseif def.kind == "color" then
		ctl, kind = swatch(ctx, s, key), "swatch"
	elseif def.kind == "choice" then
		if #def.options <= 4 then
			ctl, kind = Segmented.new(ctx, nil, { options = def.options }), "segmented"
		else
			ctl, kind = Dropdown.new(ctx, nil, { options = def.options, fontPreview = key == "font" or key == "numberFont", w = 150 }), "dropdown"
		end
		ctl.onChange = function(o) s:set(key, o) end
		ctl:set(v)
	elseif def.min and def.max then
		ctl, kind = Slider.new(ctx, nil, { min = def.min, max = def.max, step = def.integer and 1 or nil, fmt = fmtFor(key),
			sanitize = function(t) return Settings.sanitize(def, t) end }), "slider"
		ctl.onChange = function(x) s:set(key, x) end
		ctl:set(v)
	else
		ctl, kind = Field.new(ctx, nil, { w = 70, number = true, text = num(v), onCommit = function(t) return s:set(key, t) end }), "field"
		local set = ctl.set
		ctl.set = function(c, x) set(c, num(x)) end
	end
	return ctl, kind
end

-- ------------------------------------------------------------------------------------------------ window
function SettingsWin.define(ui)
	ui.wm:define("settings", { title = "Settings", w = 420, h = 640, minW = 340, minH = 320,
		build = function(body, win) ui.settingsWin = SettingsWin.build(ui, body, win) end })
	ui:addDockButton("settings")
end

function SettingsWin.build(ui, body, win)
	local E, s, ctx = ui.E, ui.E.settings, win.ctx
	local sw = { rows = {}, sections = {}, chips = {}, offs = {}, items = {} }
	-- search
	local search = Field.new(ctx, body, { search = true, placeholder = "Search settings", w = 300 })
	search.gui.Position = UDim2.new(0, PAD, 0, 10)
	search.gui.Size = UDim2.new(1, -PAD * 2, 0, 32)
	sw.search = search
	-- chips (wrapped to the window's default width)
	local x, y = PAD, 50
	local width = 420 - PAD * 2
	for _, name in ipairs(SECTIONS) do
		local chip = Button.new(ctx, body, { text = name, kind = "plain", h = 22 })
		local w = chip.gui.Size.X.Offset
		if x + w > PAD + width then x, y = PAD, y + 28 end
		chip.gui.Position = UDim2.new(0, x, 0, y)
		x = x + w + 6
		sw.chips[name] = chip
	end
	local top = y + 30
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 0, 0, top)
	list.Size = UDim2.new(1, 0, 1, -top)
	list.ScrollBarThickness = 4
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.Parent = body
	sw.list = list
	-- (rows in the list only take clicks where the list shows them; a scroll moves every rect in it)
	local lctx = {}
	for k, v in pairs(ctx) do lctx[k] = v end
	lctx.pointer = { add = function(r, z) r.clip = list; return ctx.pointer.add(r, z) end, remove = ctx.pointer.remove }
	local scrollConn = list:GetPropertyChangedSignal("CanvasPosition"):Connect(function() W.bump() end)
	sw.offs[#sw.offs + 1] = function() scrollConn:Disconnect() end
	-- sections and rows
	local function refreshSection(sec)
		local any = false
		for _, r in ipairs(sec.rows) do if not isDefault(r.def, s:get(r.def.key)) then any = true end end
		W.set(sec.reset.gui, "Visible", any)
	end
	for _, secName in ipairs(SECTIONS) do
		local header = K.frame("Section", list)
		header.Size = UDim2.new(1, 0, 0, HEADER_H)
		local holder = { ctx = lctx, offs = {}, rects = {} }
		local label = K.label(holder, header, secName:upper(), "bold", 10.5)
		label.Position, label.Size = UDim2.new(0, PAD, 0, 10), UDim2.new(0.6, 0, 0, 14)
		label.TextXAlignment = Enum.TextXAlignment.Left
		local reset = Button.new(lctx, header, { text = "Reset section", kind = "plain", h = 20 })
		reset.gui.AnchorPoint, reset.gui.Position = Vector2.new(1, 0), UDim2.new(1, -PAD, 0, 6)
		local sec = { header = header, reset = reset, rows = {}, y = 0, labelHolder = holder }
		sw.sections[secName] = sec
		sw.items[#sw.items + 1] = { gui = header, h = HEADER_H, section = sec }
		reset.onClick = function()
			for _, r in ipairs(sec.rows) do
				if r.def.key == "theme" then r.ctl.apply("Default") else s:set(r.def.key, r.def.default) end
			end
		end
		for _, def in ipairs(Settings.SCHEMA) do
			if def.section == secName and not BEZIER[def.key] then
				local ctl, kind = controlFor(lctx, s, def, sw)
				local row = Row.new(lctx, list, { name = def.name, desc = def.desc, control = ctl })
				local r = { row = row, ctl = ctl, kind = kind, def = def }
				sw.rows[def.key] = r
				sec.rows[#sec.rows + 1] = r
				sw.items[#sw.items + 1] = { gui = row.gui, h = row.h }
				row:setReset(not isDefault(def, s:get(def.key)))
				row.onReset = function()
					if def.key == "theme" then ctl.apply("Default") else s:set(def.key, def.default) end
				end
				sw.offs[#sw.offs + 1] = s:changed(def.key, function(v)
					ctl:set(v)
					row:setReset(not isDefault(def, v))
					refreshSection(sec)
				end)
				if def.key == "easingDirection" then
					local holderF = K.frame("CurveBlock", list)
					holderF.Size = UDim2.new(1, 0, 0, 200)
					local bz = Bezier.new(lctx, holderF)
					bz.gui.Position = UDim2.new(0, PAD, 0, 4)
					sw.bezier = { gui = holderF, editor = bz }
					sw.items[#sw.items + 1] = { gui = holderF, h = 200, curve = true }
				end
			end
		end
		refreshSection(sec)
	end
	-- positions top to bottom (hidden rows and empty sections skipped)
	local function relayout()
		local yy = 0
		for _, it in ipairs(sw.items) do
			if it.gui.Visible then
				W.set(it.gui, "Position", UDim2.new(0, 0, 0, yy))
				if it.section then it.section.y = yy end
				yy = yy + it.h
			end
		end
		W.set(list, "CanvasSize", UDim2.new(0, 0, 0, yy + 12))
	end
	sw.relayout = relayout
	local query = ""
	local function filter()
		local q = query:lower()
		for _, secName in ipairs(SECTIONS) do
			local sec = sw.sections[secName]
			local any = false
			for _, r in ipairs(sec.rows) do
				local d = r.def
				local hit = q == "" or (d.name or ""):lower():find(q, 1, true) ~= nil or (d.desc or ""):lower():find(q, 1, true) ~= nil
				W.set(r.row.gui, "Visible", hit)
				if hit then any = true end
			end
			W.set(sec.header, "Visible", any)
		end
		local curve = s:get("easing") == "Custom" and sw.rows.easing.row.gui.Visible
		W.set(sw.bezier.gui, "Visible", curve)
		relayout()
	end
	search.onInput = function(t) query = t; filter() end
	-- (the Glass row says when Frost can't be used here)
	local function frostNote()
		local r = sw.rows.glass
		if not (r and r.row.desc) then return end
		local why = s:get("glass") == "Frost" and ui.frost ~= nil and not ui.frost:available()
		W.set(r.row.desc, "Text", why and "Frost needs high graphics: Tint is used" or r.def.desc)
	end
	sw.offs[#sw.offs + 1] = s:changed("glass", frostNote)
	if ui.frost then sw.offs[#sw.offs + 1] = ui.frost:qualityChanged(frostNote) end
	frostNote()
	sw.offs[#sw.offs + 1] = s:changed("easing", function() filter() end)
	for _, secName in ipairs(SECTIONS) do
		sw.chips[secName].onClick = function()
			W.set(list, "CanvasPosition", Vector2.new(0, sw.sections[secName].y))
			W.bump()
		end
	end
	filter()
	ui.life:own(function() for _, off in ipairs(sw.offs) do off() end end)
	return sw
end

return SettingsWin
