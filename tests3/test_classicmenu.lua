-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5c: the classic menu: every setting on the one store, both ways, in the same frame
-- (spec 8.5's test); a refused value; Appearance values Classic doesn't draw are never written; tabs, More,
-- Help; the menu's own place (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local wm = ui.wm
local Settings = __T3("engine/settings")
local HelpText = __T3("ui/win/helptext")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
wm:open("settings")
M.steps(2)
local sw = ui.settingsWin
E.settings:set("interface", "Classic")
M.steps(2)
local c = ui.classic
local rows = c.settingsRows
check(rows ~= nil, "the classic settings rows")

-- a valid value other than v for def
local function other(def, v)
	if def.kind == "toggle" then return (v ~= 0) and 0 or 1 end
	if def.kind == "choice" then
		for _, o in ipairs(def.options) do if o ~= v then return o end end
	end
	if def.kind == "color" then return (v == "#123456") and "#654321" or "#123456" end
	if def.kind == "number" then
		if def.min == nil or def.max == nil then return v + 1 end
		local t = (v == def.min) and def.max or def.min
		if def.nonzero and t == 0 then t = def.max end
		return t
	end
	return nil
end
-- the classic row shows v
local function classicShows(def, v)
	local r = rows[def.key]
	if not r then return false end
	if def.kind == "toggle" then return r.on == (v ~= 0) end
	return r.input.Text == tostring(v)
end
-- the new Settings window shows v
local function newShows(def, v)
	local r = sw.rows[def.key]
	if not r then return true end -- (the curve's four numbers are drawn in the curve, not as rows)
	local ctl = r.ctl
	if r.kind == "toggle" then return ctl.value == (v ~= 0) end
	if r.kind == "swatch" then return ctl.gui.BackgroundColor3 == Color3.fromHex(v:sub(2)) end
	if r.kind == "field" then return tonumber(ctl.text) == v end
	return ctl.value == v
end
local SKIP = { theme = true, interface = true } -- (theme loads saved looks; interface switches)

section("the store -> both interfaces, in the same frame")
local bad = {}
for _, def in ipairs(Settings.SCHEMA) do
	if not SKIP[def.key] then
		local v = other(def, E.settings:get(def.key))
		E.settings:set(def.key, v)
		local now = E.settings:get(def.key)
		if not classicShows(def, now) then bad[#bad + 1] = def.key .. " (classic)" end
		if not newShows(def, now) then bad[#bad + 1] = def.key .. " (new)" end
	end
end
eq(#bad, 0, "every setting shows in both (" .. table.concat(bad, ", ") .. ")")

section("classic -> the store -> the new window")
bad = {}
for _, def in ipairs(Settings.SCHEMA) do
	if not SKIP[def.key] then
		local r = rows[def.key]
		local want = other(def, E.settings:get(def.key))
		if def.kind == "toggle" then
			r.switch.MouseButton1Click:Fire()
		else
			r.input.Text = tostring(want)
			r.input.FocusLost:Fire(true, nil)
		end
		local now = E.settings:get(def.key)
		if now ~= want then bad[#bad + 1] = def.key .. " (store " .. tostring(now) .. ")" end
		if not newShows(def, now) then bad[#bad + 1] = def.key .. " (new)" end
	end
end
eq(#bad, 0, "every classic row reaches the store and the new window (" .. table.concat(bad, ", ") .. ")")

section("a refused value")
local r = rows.textSize
local before = E.settings:get("textSize")
r.input.Text = "abc"
r.input.FocusLost:Fire(true, nil)
eq(E.settings:get("textSize"), before, "the store unchanged")
eq(r.input.Text, tostring(before), "the row shows the old value again")

section("Classic never writes what it doesn't draw (spec 8.5)")
local KEEP = { "glass", "glassColor", "glassTransparency", "blurStrength", "edgeLight", "windowCorners", "buttonShape",
	"shadows", "animations", "animationLength", "easing", "easingDirection" }
local was = {}
for _, k in ipairs(KEEP) do was[k] = E.settings:get(k) end
local written = {}
local offAny = E.settings:onAny(function(key) written[#written + 1] = key end)
E.settings:set("interface", "New")
M.steps(1)
E.settings:set("interface", "Classic")
M.steps(1)
for _, t in ipairs({ "Controls", "Settings", "Saves", "Help", "More" }) do c:tab(t) M.steps(1) end
offAny()
local touched = {}
for _, k in ipairs(written) do if k ~= "interface" then touched[#touched + 1] = k end end
eq(#touched, 0, "nothing but the switch written (" .. table.concat(touched, ", ") .. ")")
for _, k in ipairs(KEEP) do eq(E.settings:get(k), was[k], k .. " kept") end

section("tabs, More, Help")
for _, t in ipairs({ "Controls", "Settings", "Saves", "Help", "More" }) do
	c:tab(t)
	M.steps(1)
	local shown = {}
	for _, o in ipairs({ "Controls", "Settings", "Saves", "Help", "More" }) do
		if c.byPath["MainMenu." .. o .. "Frame"].Visible then shown[#shown + 1] = o end
	end
	eq(table.concat(shown, ","), t, t .. ": only its frame")
end
eq(#c.helpRows, #HelpText.topics(E), "a Help row per topic")
c.helpRows[1].button.MouseButton1Click:Fire()
M.steps(1)
eq(c.helpRows[1].expansion.Visible, true, "the first opens")
c.helpRows[2].button.MouseButton1Click:Fire()
M.steps(1)
eq(c.helpRows[1].expansion.Visible, false, "opening another closes it")
eq(c.helpRows[2].expansion.Visible, true, "the second shows")
local mp = E.settings:get("showMicroProfiler")
c.byPath["MainMenu.MoreFrame.List.ToggleMicroProfiler"].MouseButton1Click:Fire()
eq(E.settings:get("showMicroProfiler"), (mp ~= 0) and 0 or 1, "More > Toggle MicroProfiler")

section("the Menu key opens V2's menu; Classic's place is its own")
eq(c.menu.Visible, false, "closed")
UIH.key(Enum.KeyCode.M)
M.steps(1)
eq(c.menu.Visible, true, "the Menu key opened it")
eq(E.modal, true, "the mouse is free")
local p0 = c.menu.AbsolutePosition
local layoutBefore = game:GetService("HttpService"):JSONEncode(E.settingsFile:getUi().layout)
local title = c.byPath["MainMenu.Title"]
UIH.drag(title, UIH.center(title) + Vector2.new(100, 40))
M.steps(2)
local moved = c.menu.AbsolutePosition - p0
eq(moved, Vector2.new(100, 40), "dragged by its title")
E.settings:set("interface", "New")
M.steps(2)
E.settings:set("interface", "Classic")
M.steps(2)
eq(c.menu.AbsolutePosition, p0 + Vector2.new(100, 40), "kept over a switch")
eq(game:GetService("HttpService"):JSONEncode(E.settingsFile:getUi().layout), layoutBefore, "the new interface's saved layout untouched")
M.steps(60, 1 / 60) -- (the settings file saved)
check(boot(30), "runs again")
T = getgenv().__HappaTAS3_T
E = T.engine
ui = E.ui
M.steps(2)
eq(ui.live, "Classic", "Classic again after a re-run")
eq(ui.classic.menu.AbsolutePosition, p0 + Vector2.new(100, 40), "the menu's place kept")

section("the theme row: a saved look by name, never an unknown or empty one (review)")
local tr = ui.classic.settingsRows.theme.input
local data = E.settingsFile:getUi()
data.themes["Mine"] = { accentColor = "#112233" }
E.settingsFile:setUi(data)
local theme0 = E.settings:get("theme")
tr.Text = ""
tr.FocusLost:Fire(false, nil)
eq(E.settings:get("theme"), theme0, "an empty box changes nothing")
eq(tr.Text, tostring(theme0), "the box shows the theme again")
tr.Text = "Nope"
tr.FocusLost:Fire(true, nil)
eq(E.settings:get("theme"), theme0, "an unknown name is refused")
eq(tr.Text, tostring(theme0), "the box shows the theme again")
tr.Text = "Mine"
tr.FocusLost:Fire(true, nil)
eq(E.settings:get("theme"), "Mine", "a saved look by name")
eq(E.settings:get("accentColor"), "#112233", "its values loaded")
finish()
