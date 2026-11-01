-- ================================================================================================
--  CLASSIC SETTINGS ROWS  (HappaTAS 3 ui, spec 8.5): the classic Settings tab, one V2.38.17-style row per
--  setting of the one store (spec 6.3), the Appearance ones too: a switch for a toggle, V2's input box for
--  everything else (a choice typed, matched without case; a colour as #RRGGBB). A row shows the store when
--  it is built and follows its change events; a value the store refuses shows the old one again. Nothing
--  here keeps a copy of a setting.
-- ================================================================================================
local Env = import("platform/env")
local Settings = import("engine/settings")
local ClassicTree = import("ui/classic/tree")
local ClassicBuild = import("ui/classic/build")

local SettingsRows = {}

local u, v2 = UDim2.new, Vector2.new
local ROW_H, HEADER_H = 30, 28
local SWITCH_ON = { Position = u(1, 0, 0.5, 0), BackgroundColor3 = Color3.fromRGB(75, 75, 75) }
local SWITCH_OFF = { Position = u(0, 0, 0.5, 0), BackgroundColor3 = Color3.fromRGB(255, 255, 255) }

-- V2's row shapes (p04_ui.lua toggleRow / numberRow)
local function toggleRow(def, order)
	return { "Frame", def.key, 34, { Size = u(1, 0, 0, ROW_H), LayoutOrder = order }, {
		{ "UICorner", "UICorner", 5, {} },
		{ "TextLabel", "N", 35, { Position = u(0, 10, 0, 0), Size = u(0.75, 0, 1, 0), Text = def.name, TextSize = 16 } },
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
	local labelSize = (#def.name > 24) and 13 or 16
	return { "Frame", def.key, 34, { Size = u(1, 0, 0, ROW_H), LayoutOrder = order }, {
		{ "UICorner", "UICorner", 5, {} },
		{ "TextBox", "Input", 40, { Position = u(0.9, 0, 0.5, 0), Size = u(0.15, 0, 0.7, 0), AnchorPoint = v2(0.5, 0.5), Text = "", TextSize = 13, PlaceholderText = "" }, {
			{ "UICorner", "UICorner", 5, {} },
			{ "UIStroke", "UIStroke", 41, {} },
		} },
		{ "TextLabel", "N", 35, { Position = u(0, 10, 0, 0), Size = u(0.75, 0, 1, 0), Text = def.name, TextSize = labelSize } },
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
	local rows, last, order, height = {}, nil, 0, 0
	for _, def in ipairs(Settings.SCHEMA) do
		if def.section ~= last then
			last = def.section
			order = order + 1
			local h = ClassicBuild.node({ "TextLabel", "Section_" .. def.section, 16, { Size = u(1, 0, 0, HEADER_H), Text = def.section,
				TextSize = 14, LayoutOrder = order } }, ClassicTree.STYLES)
			pcall(function() h.TextColor3 = Color3.fromRGB(140, 205, 255) end) -- (V2's section colour)
			h.Parent = list
			height = height + HEADER_H
		end
		order = order + 1
		local key = def.key
		local r
		if def.kind == "toggle" then
			local f = ClassicBuild.node(toggleRow(def, order), ClassicTree.STYLES)
			f.Parent = list
			r = { frame = f, label = f.N, switch = f.Switch, knob = f.Switch.Switcher, on = nil }
			local function show(v, instant)
				local on = v ~= 0
				if r.on == on then return end
				r.on = on
				local target = on and SWITCH_ON or SWITCH_OFF
				if instant or not ts then
					r.knob.Position, r.knob.BackgroundColor3 = target.Position, target.BackgroundColor3
				else
					ts:Create(r.knob, TweenInfo.new(0.25), target):Play()
				end
			end
			show(s:get(key), true)
			life:connect(r.switch.MouseButton1Click, function() s:set(key, s:on(key) and 0 or 1) end)
			classic.offs[#classic.offs + 1] = s:changed(key, function(v) show(v, false) end)
		else
			local f = ClassicBuild.node(inputRow(def, order), ClassicTree.STYLES)
			f.Parent = list
			r = { frame = f, label = f.N, input = f.Input }
			local inp = r.input
			inp.Text = tostring(s:get(key))
			life:connect(inp.FocusLost, function()
				s:set(key, inp.Text)
				inp.Text = tostring(s:get(key)) -- (the store's own spelling, or the old value when refused)
			end)
			classic.offs[#classic.offs + 1] = s:changed(key, function(v) inp.Text = tostring(v) end)
		end
		rows[key] = r
		height = height + ROW_H
	end
	-- (the list and its scroller fit every row: V2's lists were sized by hand for V2's settings)
	list.Size = u(0, 360, 0, height)
	scroller.CanvasSize = u(0, 0, 0, height + 50)
	return rows
end

return SettingsRows
