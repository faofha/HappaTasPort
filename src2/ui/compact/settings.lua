-- ================================================================================================
--  TASABILITY SETTINGS  (HappaTAS 3 ui, V3.1): the Tasability interface's own SETTINGS page (docs/superpowers/
--  specs/2026-11-22-tasability-settings-design.md). The rows the New Settings window shows (minus the New
--  interface's own look rows, newOnly), from the schema, drawn with the Tasability parts (ui/compact/parts): a
--  checkbox per switch, a value box per number, a dropdown per choice, a colour box per colour, a checkbox per
--  option of a multi row, the Theme row as a dropdown of the saved looks plus a "Save look as" box. Sections in
--  schema order, each placed in the shorter of two columns, a RESET chip each; hovering a row shows its
--  description in a strip at the bottom; filter(text) keeps the rows whose name or description matches. Every
--  part follows its setting. Fixed row heights: no list layouts.
-- ================================================================================================
local W = import("ui/write")
local K = import("ui/kit/base")
local CK = import("ui/compact/kit")
local P = import("ui/compact/parts")
local Settings = import("engine/settings")
local SettingsWin = import("ui/win/settings")

local TSettings = {}
TSettings.__index = TSettings

local SECTIONS = { "Appearance", "Playback", "Create", "Speed hack", "Glide", "Inputs", "World sync", "Interface" }
local BEZIER = { bezierX1 = true, bezierY1 = true, bezierX2 = true, bezierY2 = true }
local TITLE, PADT, PADB, GAP, SEC_GAP, STRIP = 22, 4, 6, 5, 7, 18

-- the rows this page shows
function TSettings.shown(def)
	return table.find(SECTIONS, def.section) ~= nil and not BEZIER[def.key] and not def.hidden and not def.newOnly
end

local function has(list, opt)
	for o in string.gmatch(tostring(list or ""), "[^,]+") do if o == opt then return true end end
	return false
end

function TSettings.build(cp)
	local ui, ctx = cp.ui, cp.ctx
	local E = ui.E
	local s = E.settings
	local self = setmetatable({ cp = cp, ui = ui, E = E, rows = {}, sections = {}, order = {}, offs = {}, parts = {},
		dropdowns = {}, query = "" }, TSettings)
	local root = cp.pages.settings
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "SettingsPage"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 2
	scroll.Position = UDim2.new(0, 6, 0, 6)
	scroll.Size = UDim2.new(1, -12, 1, -12 - STRIP)
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.Parent = root
	self.scroll = scroll
	local hover = K.text("TextLabel", "Hover", root)
	hover.Position = UDim2.new(0, 8, 1, -STRIP)
	hover.Size = UDim2.new(1, -16, 0, STRIP - 2)
	hover.TextXAlignment = Enum.TextXAlignment.Left
	hover.TextTruncate = Enum.TextTruncate.AtEnd
	hover.Text = ""
	self.hover = hover
	self.columns = { left = K.frame("Left", scroll), right = K.frame("Right", scroll) }
	self.columns.left.Size = UDim2.new(0.5, -4, 0, 0)
	self.columns.right.Position = UDim2.new(0.5, 4, 0, 0)
	self.columns.right.Size = UDim2.new(0.5, -4, 0, 0)
	local function hoverFn(desc) return function(on) if on then hover.Text = desc or "" elseif hover.Text == desc then hover.Text = "" end end end
	local function keep(p) self.parts[#self.parts + 1] = p; return p end
	local function follow(key, f) self.offs[#self.offs + 1] = s:changed(key, f) end

	-- one row: { def, part | parts, gui (its frame), h (its height), save (Theme only) }
	local function makeRow(sec, def)
		local key, body = def.key, sec.body
		local r = { def = def, section = sec }
		local onHover = hoverFn(def.desc)
		if def.kind == "toggle" then
			local p = keep(P.checkbox(ctx, body, def.name, { onHover = onHover, onChange = function(on) s:set(key, on and 1 or 0) end }))
			p:set(s:get(key) == 1)
			follow(key, function(v) p:set(v == 1) end)
			r.part, r.gui, r.h = p, p.gui, 18
		elseif def.kind == "number" then
			local p = keep(P.valueBox(ctx, body, def.name, { onHover = onHover,
				current = function() return SettingsWin.num(s:get(key)) end,
				commit = function(t) return s:set(key, t) ~= false end }))
			p:set(SettingsWin.num(s:get(key)))
			follow(key, function(v) p:set(SettingsWin.num(v)) end)
			r.part, r.gui, r.h = p, p.gui, 22
		elseif def.kind == "choice" then
			local p = keep(P.dropdown(ctx, body, def.name, def.options, { onHover = onHover, onChange = function(v) s:set(key, v) end }))
			p:set(s:get(key))
			follow(key, function(v) p:set(v) end)
			self.dropdowns[#self.dropdowns + 1] = p
			r.part, r.gui, r.h = p, p.gui, 22
		elseif def.kind == "color" then
			local p = keep(P.colorBox(ctx, body, def.name, { onHover = onHover, default = def.default,
				value = function() return s:get(key) end,
				onPreview = function(hex) s:set(key, hex) end, onApply = function(hex) s:set(key, hex) end }))
			p:set(s:get(key))
			follow(key, function(v) p:set(v) end)
			r.part, r.gui, r.h = p, p.gui, 22
		elseif def.kind == "multi" then
			local f = K.frame("Multi_" .. key, body)
			r.parts = {}
			for i, opt in ipairs(def.options) do
				local p = keep(P.checkbox(ctx, f, def.name .. ": " .. opt, { onHover = onHover, onChange = function(on)
					local out = {}
					for _, o in ipairs(def.options) do
						if (o == opt and on) or (o ~= opt and has(s:get(key), o)) then out[#out + 1] = o end
					end
					s:set(key, table.concat(out, ","))
				end }))
				p.gui.Position = UDim2.new(0, 0, 0, (i - 1) * (18 + GAP))
				p:set(has(s:get(key), opt))
				r.parts[i] = p
			end
			follow(key, function(v) for i, opt in ipairs(def.options) do r.parts[i]:set(has(v, opt)) end end)
			r.h = #def.options * (18 + GAP) - GAP
			f.Size = UDim2.new(1, 0, 0, r.h)
			r.gui = f
		elseif def.key == "theme" then
			local f = K.frame("Theme", body)
			r.h = 22 + GAP + 22
			f.Size = UDim2.new(1, 0, 0, r.h)
			local p = keep(P.dropdown(ctx, f, def.name, SettingsWin.lookNames(E), { onHover = onHover,
				onChange = function(v) SettingsWin.applyLook(E, v) end }))
			p:set(s:get(key))
			self.dropdowns[#self.dropdowns + 1] = p
			local save = keep(P.valueBox(ctx, f, "Save look as", { onHover = onHover, current = function() return "" end,
				commit = function(t)
					if tostring(t or ""):match("^%s*$") then return true end
					local ok, why = SettingsWin.saveLook(E, t)
					if not ok then E.bus:emit("status", why, true) end
					return ok
				end }))
			save.gui.Position = UDim2.new(0, 0, 0, 22 + GAP)
			follow(key, function(v) p.options = SettingsWin.lookNames(E); p:set(v) end)
			r.part, r.save, r.gui = p, save, f
		else
			return nil
		end
		return r
	end

	for _, name in ipairs(SECTIONS) do
		local sec = CK.section(ctx, self.columns.left, name)
		cp.pieces[#cp.pieces + 1] = sec
		sec.gui.AutomaticSize = Enum.AutomaticSize.None
		sec.body.AutomaticSize = Enum.AutomaticSize.None
		sec.body.Size = UDim2.new(1, 0, 1, -TITLE)
		for _, ch in ipairs(sec.body:GetChildren()) do
			if ch:IsA("UIListLayout") or ch:IsA("UIPadding") then ch:Destroy() end
		end
		local entry = { name = name, gui = sec.gui, body = sec.body, title = sec.title, rows = {}, column = "left" }
		local reset = CK.chip(ctx, sec.gui, "RESET", { button = true, onClick = function() self:resetSection(entry) end })
		reset.gui.AnchorPoint, reset.gui.Position, reset.gui.Size = Vector2.new(1, 0), UDim2.new(1, -4, 0, 4), UDim2.new(0, 44, 0, 14)
		cp.pieces[#cp.pieces + 1] = reset
		entry.reset = reset
		for _, def in ipairs(Settings.SCHEMA) do
			if def.section == name and TSettings.shown(def) then
				local r = makeRow(entry, def)
				if r then
					r.gui.Position = UDim2.new(0, 8, 0, 0)
					r.gui.Size = UDim2.new(1, -16, 0, r.h)
					entry.rows[#entry.rows + 1] = r
					self.rows[def.key] = r
				end
			end
		end
		if #entry.rows > 0 then
			self.sections[name] = entry
			self.order[#self.order + 1] = entry
		else
			sec.gui.Visible = false
		end
	end
	local function paint()
		local th = ui.theme
		W.set(hover, "FontFace", th.font("text"))
		W.set(hover, "TextSize", th.size(10.5))
		W.set(hover, "TextColor3", th.c.text2)
		W.set(scroll, "ScrollBarImageColor3", th.c.accent)
	end
	paint()
	self.offs[#self.offs + 1] = ui.theme:changed(paint)
	self:relayout()
	return self
end

-- a section's rows to their defaults (Appearance: the Default look)
function TSettings:resetSection(entry)
	local s = self.E.settings
	if entry.name == "Appearance" then
		SettingsWin.applyLook(self.E, "Default")
		return
	end
	for _, r in ipairs(entry.rows) do s:set(r.def.key, r.def.default) end
end

local function matches(def, q)
	if q == "" then return true end
	return (def.name or ""):lower():find(q, 1, true) ~= nil or (def.desc or ""):lower():find(q, 1, true) ~= nil
end

-- keeps the rows whose name or description has text in it (empty: every row)
function TSettings:filter(text)
	self.query = tostring(text or ""):lower()
	self:relayout()
end

-- places the rows that match in each section, the sections that have any in the shorter column
function TSettings:relayout()
	local h = { left = 0, right = 0 }
	for _, entry in ipairs(self.order) do
		local y = PADT
		for _, r in ipairs(entry.rows) do
			local on = matches(r.def, self.query)
			W.set(r.gui, "Visible", on)
			if on then
				W.set(r.gui, "Position", UDim2.new(0, 8, 0, y))
				y = y + r.h + GAP
			end
		end
		local any = y > PADT
		W.set(entry.gui, "Visible", any)
		if any then
			local height = TITLE + y - GAP + PADB
			local col = (h.left <= h.right) and "left" or "right"
			entry.column = col
			if entry.gui.Parent ~= self.columns[col] then entry.gui.Parent = self.columns[col] end
			W.set(entry.gui, "Position", UDim2.new(0, 0, 0, h[col]))
			W.set(entry.gui, "Size", UDim2.new(1, 0, 0, height))
			h[col] = h[col] + height + SEC_GAP
		end
	end
	local tall = math.max(h.left, h.right)
	W.set(self.columns.left, "Size", UDim2.new(0.5, -4, 0, h.left))
	W.set(self.columns.right, "Size", UDim2.new(0.5, -4, 0, h.right))
	W.set(self.scroll, "CanvasSize", UDim2.new(0, 0, 0, tall + 4))
end

-- open dropdown lists close (the window folds, the interface changes)
function TSettings:closePopups()
	for _, d in ipairs(self.dropdowns) do d.close() end
end

function TSettings:destroy()
	self:closePopups()
	for _, off in ipairs(self.offs) do pcall(off) end
	self.offs = {}
	for _, p in ipairs(self.parts) do pcall(function() p:destroy() end) end
	self.parts = {}
end

return TSettings
