-- ================================================================================================
--  CLASSIC SETTINGS ROWS  (HappaTAS 3 ui, spec 8.5): the classic Settings tab as V2.38.17 had it: a row per
--  setting V2.38.17 has (its label and section names), plus the Classic interface switch and a switch per mode of
--  Speed Hack In ("Speed Hack in Idle" / "in Create": the one multi setting); the New interface's
--  own settings (Appearance) are not shown here and keep their values. A switch for a toggle, V2's input box for
--  everything else. A row shows the store when it is built and follows its change events; a value the store
--  refuses shows the old one again. Nothing here keeps a copy of a setting.
-- ================================================================================================
local Env = import("platform/env")
local Settings = import("engine/settings")
local ClassicTree = import("ui/classic/tree")
local ClassicBuild = import("ui/classic/build")
local SettingsWin = import("ui/win/settings")
local ClassicPicker = import("ui/classic/colorpicker")

local SettingsRows = {}

local u, v2 = UDim2.new, Vector2.new
local ROW_H, HEADER_H = 30, 28
-- (V2.38.17's knobs; their colours are the Classic Look's Switch On / Switch Off)
local SWITCH_ON = { Position = u(1, 0, 0.5, 0), color = "classicSwitchOn" }
-- V2.38.17's labels and section names where they differ from its setting names
local LABELS = { speedHack = "Speed Hack (slow / fast motion)", speedHackSpeed = "Speed (0.1 - 4, 0.5 = half, 2 = double)",
	invisibleMouseSpeed = "Invisible Mouse Speed", syncKitObjects = "Sync Kit Objects (Beat Blocks, Turrets)",
	microProfilerScale = "MicroProfiler Size (1 = Roblox)", microProfilerTextOffset = "MicroProfiler Text Offset (px, - = up)",
	allowPlayerGuiInterface = "Allow Visible Interface (PlayerGui)" }
local SECTIONS = { ["Speed hack"] = "Speed Hack", ["World sync"] = "World Sync", ["Classic look"] = "Classic Look" }
-- (and a multi row with Classic labels: a switch per option, keyed "<key>:<option>")
-- (and Classic Look: the rows only Classic has)
local function shownHere(def) return def.v2 ~= nil or def.key == "interface" or (def.kind == "multi" and def.classic ~= nil) or def.classicOnly == true end
local SWITCH_OFF = { Position = u(0, 0, 0.5, 0), color = "classicSwitchOff" }

-- V2's row shapes (p04_ui.lua toggleRow / numberRow)
local function toggleRow(def, order)
	return { "Frame", def.key, 34, { Size = u(1, 0, 0, ROW_H), LayoutOrder = order }, {
		{ "UICorner", "UICorner", 5, {} },
		{ "TextLabel", "N", 35, { Position = u(0, 10, 0, 0), Size = u(0.75, 0, 1, 0), Text = LABELS[def.key] or def.name, TextSize = 16 } },
		{ "TextButton", "Switch", 36, { Position = u(0.9, 0, 0.5, 0), Size = u(0, 30, 0, 15), AnchorPoint = v2(0.5, 0.5), Text = "", TextSize = 13 }, {
			{ "UICorner", "UICorner", 37, {} },
			{ "Frame", "Switcher", 38, { Position = u(0, 0, 0.5, 0), Size = u(0, 22, 0, 22), AnchorPoint = v2(0.5, 0.5) }, {
				{ "UICorner", "UICorner", 37, {} },
			} },
		} },
		{ "Frame", "Border", 39, { Position = u(0, 0, 1, 0), Size = u(1, 0, 0, 1), AnchorPoint = v2(0, 1) } },
	} }
end
local function inputRow(def, order)
	local label = LABELS[def.key] or def.name
	local labelSize = (#label > 24) and 13 or 16
	return { "Frame", def.key, 34, { Size = u(1, 0, 0, ROW_H), LayoutOrder = order }, {
		{ "UICorner", "UICorner", 5, {} },
		{ "TextBox", "Input", 40, { Position = u(0.9, 0, 0.5, 0), Size = u(0.15, 0, 0.7, 0), AnchorPoint = v2(0.5, 0.5), Text = "", TextSize = 13, PlaceholderText = "" }, {
			{ "UICorner", "UICorner", 5, {} },
			{ "UIStroke", "UIStroke", 41, {} },
		} },
		{ "TextLabel", "N", 35, { Position = u(0, 10, 0, 0), Size = u(0.75, 0, 1, 0), Text = label, TextSize = labelSize } },
		{ "Frame", "Border", 39, { Position = u(0, 0, 1, 0), Size = u(1, 0, 0, 1), AnchorPoint = v2(0, 1) } },
	} }
end

-- every row into classic's Settings list; returns { [key] = row } (row: frame, label, and switch / knob / on,
-- or input)
function SettingsRows.build(classic)
	local E, life = classic.E, classic.ui.life
	local s = E.settings
	local list = classic.byPath["MainMenu.SettingsFrame.List"]
	local scroller = classic.byPath["MainMenu.SettingsFrame"]
	local ts = Env.svc("TweenService")
	local look = classic.look
	local rows, last, order, height = {}, nil, 0, 0
	local titles = {}
	-- (knobs and section titles are painted here: repainted when the Classic Look changes)
	classic.offs[#classic.offs + 1] = look:changed(function()
		for _, h in ipairs(titles) do h.TextColor3 = look:color("classicSectionTitle") end
		for _, r in pairs(rows) do
			if r.knob and r.on ~= nil then r.knob.BackgroundColor3 = look:color(r.on and "classicSwitchOn" or "classicSwitchOff") end
		end
	end)
	for _, def in ipairs(Settings.SCHEMA) do
		if not shownHere(def) then
			-- (the New interface's only)
		elseif def.section ~= last then
			last = def.section
			order = order + 1
			local secName = SECTIONS[def.section] or def.section
			local h = ClassicBuild.node({ "TextLabel", "Section_" .. secName, 16, { Size = u(1, 0, 0, HEADER_H), Text = secName,
				TextSize = 14, LayoutOrder = order } }, ClassicTree.STYLES)
			pcall(function() h.TextColor3 = look:color("classicSectionTitle") end) -- (V2's section colour by default)
			look:own(h, "TextColor3")
			titles[#titles + 1] = h
			h.Parent = list
			height = height + HEADER_H
		end
		if shownHere(def) and def.kind == "multi" then
		-- a switch per option ("Speed Hack in Idle"): each one ticks or unticks its option in the one setting
		local key = def.key
		for _, o in ipairs(def.options) do
			order = order + 1
			local f = ClassicBuild.node(toggleRow({ key = key .. ":" .. o, name = def.classic[o] or o }, order), ClassicTree.STYLES)
			f.Parent = list
			local r = { frame = f, label = f.N, switch = f.Switch, knob = f.Switch.Switcher, on = nil }
			look:own(r.knob, "BackgroundColor3")
			local function show(instant)
				local on = s:has(key, o)
				if r.on == on then return end
				r.on = on
				local target = on and SWITCH_ON or SWITCH_OFF
				if instant or not ts then
					r.knob.Position, r.knob.BackgroundColor3 = target.Position, look:color(target.color)
				else
					r.knob.BackgroundColor3 = look:color(target.color)
					ts:Create(r.knob, TweenInfo.new(0.25), { Position = target.Position }):Play()
				end
			end
			show(true)
			life:connect(r.switch.MouseButton1Click, function()
				local out = {}
				for _, x in ipairs(def.options) do
					local on = s:has(key, x)
					if x == o then on = not on end
					if on then out[#out + 1] = x end
				end
				s:set(key, table.concat(out, ","))
			end)
			classic.offs[#classic.offs + 1] = s:changed(key, function() show(false) end)
			rows[key .. ":" .. o] = r
			height = height + ROW_H
		end
		elseif shownHere(def) then
		order = order + 1
		local key = def.key
		local r
		if def.kind == "toggle" or def.switch then
			local f = ClassicBuild.node(toggleRow(def, order), ClassicTree.STYLES)
			f.Parent = list
			r = { frame = f, label = f.N, switch = f.Switch, knob = f.Switch.Switcher, on = nil }
			look:own(r.knob, "BackgroundColor3")
			local sw = def.switch -- (a choice of two shown as a switch: off = sw[1], on = sw[2])
			local function show(v, instant)
				local on
				if sw then on = v == sw[2] else on = v ~= 0 end
				if r.on == on then return end
				r.on = on
				local target = on and SWITCH_ON or SWITCH_OFF
				local bg = look:color(target.color)
				if instant or not ts then
					r.knob.Position, r.knob.BackgroundColor3 = target.Position, bg
				else
					r.knob.BackgroundColor3 = bg
					ts:Create(r.knob, TweenInfo.new(0.25), { Position = target.Position }):Play()
				end
			end
			show(s:get(key), true)
			life:connect(r.switch.MouseButton1Click, function()
				if sw then s:set(key, (s:get(key) == sw[2]) and sw[1] or sw[2]) else s:set(key, s:on(key) and 0 or 1) end
			end)
			classic.offs[#classic.offs + 1] = s:changed(key, function(v) show(v, false) end)
		else
			local f = ClassicBuild.node(inputRow(def, order), ClassicTree.STYLES)
			f.Parent = list
			r = { frame = f, label = f.N, input = f.Input }
			local inp = r.input
			inp.Text = tostring(s:get(key))
			if def.kind == "color" or def.kind == "autocolor" then
				-- (Classic Look: a swatch of the colour in use; a click opens the colour picker)
				local sw = Instance.new("TextButton")
				sw.Name, sw.Text, sw.BorderSizePixel, sw.AutoButtonColor = "Swatch", "", 0, false
				sw.AnchorPoint, sw.Position, sw.Size = Vector2.new(0.5, 0.5), u(0.77, 0, 0.5, 0), u(0, 22, 0, 18)
				sw.ZIndex = inp.ZIndex
				local sc = Instance.new("UICorner")
				sc.CornerRadius = UDim.new(0, 4)
				sc.Parent = sw
				look:own(sw, "BackgroundColor3")
				sw.Parent = f
				r.swatch = sw
				local function paint()
					if def.kind == "autocolor" then
						sw.BackgroundColor3 = look:color(key)
					else
						sw.BackgroundColor3 = Color3.fromHex(tostring(s:get(key)):sub(2))
					end
				end
				paint()
				classic.offs[#classic.offs + 1] = look:changed(paint)
				classic.offs[#classic.offs + 1] = s:changed(key, paint)
				life:connect(sw.MouseButton1Click, function() ClassicPicker.open(classic, key) end)
			end
			life:connect(inp.FocusLost, function()
				local text = inp.Text:gsub("^%s+", ""):gsub("%s+$", "")
				if key == "theme" then
					-- (a look by name, as the Settings window's list: an empty box or an unknown name changes nothing)
					if text ~= "" and text ~= s:get(key) and not SettingsWin.applyLook(E, text) then
						E.bus:emit("status", "No saved look named \"" .. text .. "\"", true)
					end
				elseif text ~= "" or def.kind == "autocolor" or def.default == "" then
					s:set(key, inp.Text) -- (an empty colour box = Auto; an empty Background = none)
				end
				inp.Text = tostring(s:get(key)) -- (the store's own spelling, or the old value when refused)
			end)
			classic.offs[#classic.offs + 1] = s:changed(key, function(v) inp.Text = tostring(v) end)
		end
		rows[key] = r
		height = height + ROW_H
		end
	end
	-- (the list and its scroller fit every row: V2's lists were sized by hand for V2's settings)
	list.Size = u(0, 360, 0, height)
	scroller.CanvasSize = u(0, 0, 0, height + 50)
	return rows
end

return SettingsRows
