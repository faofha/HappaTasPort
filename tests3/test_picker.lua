-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5a: dropdowns (with the live font preview), the colour picker (V3.1: square, hue, one HEX
-- box, quick and recent colours, live preview, Reset / Cancel / Apply) and the custom easing curve (handles, presets, Preview)
-- (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local ui = E.ui
local wm = ui.wm
local Dropdown = __T3("ui/kit/dropdown")
local ColorPicker = __T3("ui/kit/colorpicker")
local Bezier = __T3("ui/kit/bezier")
local Tween = __T3("ui/tween")
local win
wm:define("pk", { title = "Pickers", w = 520, h = 640, minW = 300, minH = 200, build = function(body, w) win = w end })
wm:open("pk")
wm:place("pk", 100, 80)
local ctx, body = win.ctx, win.body
local function holder(y, h)
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Position = UDim2.new(0, 20, 0, y)
	f.Size = UDim2.new(0, 300, 0, h or 40)
	f.Parent = body
	return f
end

section("dropdown: opens, picks, closes on a press outside")
local dd = Dropdown.new(ctx, holder(0), { options = { "One", "Two", "Three" } })
local picked = {}
dd.onChange = function(v) picked[#picked + 1] = v end
dd:set("One")
UIH.click(dd.gui)
check(dd.list ~= nil and dd.list.Visible, "the list is open")
local item = UIH.find(dd.list, "Two")
check(item ~= nil, "it shows the options")
UIH.click(item)
eq(table.concat(picked, ","), "Two", "a pick reports")
eq(dd.value, "Two", "its value")
check(dd.list == nil or not dd.list.Visible, "and closes")
UIH.click(dd.gui)
check(dd.list and dd.list.Visible, "open again")
UIH.click(Vector2.new(1800, 1000))
check(dd.list == nil or not dd.list.Visible, "a press outside closes it")
eq(#picked, 1, "without picking")
eq(E.mode, 1, "and the press didn't reach the engine")
UIH.click(dd.gui)
UIH.key(Enum.KeyCode.Escape)
check(dd.list == nil or not dd.list.Visible, "Esc closes it")

section("font dropdown: each name in its font, live preview on hover, revert")
local Settings = __T3("engine/settings")
local fd = Dropdown.new(ctx, holder(50), { options = Settings.FONTS, fontPreview = true })
fd:set("BuilderSans")
UIH.click(fd.gui)
local osw = UIH.find(fd.list, "Oswald")
check(osw ~= nil and osw.FontFace.Family:find("Oswald", 1, true) ~= nil, "Oswald drawn in Oswald")
UIH.move(UIH.center(osw))
eq(ui.theme.font("text").Family, "rbxasset://fonts/families/Oswald.json", "hover previews it on the whole interface")
eq(win.titleLabel.FontFace.Family, "rbxasset://fonts/families/Oswald.json", "a window title shows it at once")
UIH.move(Vector2.new(1800, 1000))
eq(ui.theme.font("text").Family, "rbxasset://fonts/families/BuilderSans.json", "moving away reverts")
UIH.move(UIH.center(osw))
UIH.click(osw)
eq(fd.value, "Oswald", "a click keeps it")
eq(ui.theme.font("text").Family, "rbxasset://fonts/families/BuilderSans.json", "the preview ends (the owner stores the choice)")

section("colour picker (V3.1): one HEX box, quick and recent colours, live preview, Reset")
local applied, previews = {}, {}
local anchor = holder(100, 24)
local function openPicker(value, default)
	return ColorPicker.open(ctx, anchor, { value = value, default = default,
		onPreview = function(hex) previews[#previews + 1] = hex end,
		onApply = function(hex) applied[#applied + 1] = hex end })
end
local pk = openPicker("#6A5CFF", "#3F7CF0")
check(pk ~= nil and pk.frame.Visible, "the picker opens")
eq(pk:hex(), "#6A5CFF", "its value")
eq(pk.box.box.Text, "#6A5CFF", "the HEX box")
eq(pk.tabs, nil, "no RGB / HSV switch")
eq(#previews, 0, "opening previews nothing")
check(pk.square.AbsoluteSize.X >= 220 and pk.hueBar.AbsoluteSize.X >= 20, "big targets (" .. pk.square.AbsoluteSize.X .. ", " .. pk.hueBar.AbsoluteSize.X .. ")")

section("the square and the hue bar: press and drag, the new half and a live preview")
local old = pk.oldHalf.BackgroundColor3
local sq = pk.square
UIH.click(sq.AbsolutePosition + Vector2.new(sq.AbsoluteSize.X * 0.5, sq.AbsoluteSize.Y * 0.5))
local _, s2, v2 = pk:hsv()
eq(s2 .. " " .. v2, "50 50", "the square's middle: saturation 50, value 50")
eq(pk.oldHalf.BackgroundColor3, old, "the old half unchanged")
check(pk.newHalf.BackgroundColor3 ~= old, "the new half changed")
eq(previews[#previews], pk:hex(), "previewed live")
local hb = pk.hueBar
UIH.drag(hb.AbsolutePosition + Vector2.new(hb.AbsoluteSize.X / 2, 2), hb.AbsolutePosition + Vector2.new(hb.AbsoluteSize.X / 2, hb.AbsoluteSize.Y * 0.5))
eq(pk:hsv(), 180, "dragged to the hue bar's middle: 180")
eq(previews[#previews], pk:hex(), "the drag previews too")

section("typed values: #RRGGBB, RRGGBB or r, g, b")
UIH.typeInto(pk.box.box, "#12", true)
eq(pk.box.box.Text, pk:hex(), "#12 refused: the box shows the colour again")
UIH.typeInto(pk.box.box, "00ff80", true)
eq(pk:hex(), "#00FF80", "00ff80 taken")
UIH.typeInto(pk.box.box, "255, 255, 128", true)
eq(pk:hex(), "#FFFF80", "r, g, b taken")
UIH.typeInto(pk.box.box, "300, 0, 0", true)
eq(pk:hex(), "#FFFF80", "300, 0, 0 refused")

section("quick colours")
eq(#pk.quick, 8, "eight")
for i, hex in ipairs(ColorPicker.QUICK) do eq(pk.quick[i].BackgroundColor3, Color3.fromHex(hex:sub(2)), "quick " .. i .. " " .. hex) end
UIH.click(pk.quick[2])
eq(pk:hex(), ColorPicker.QUICK[2], "a quick swatch picks its colour")
UIH.typeInto(pk.box.box, "#FFFF80", true)

section("Apply, recent colours")
local data = E.settingsFile:getUi()
data.recentColors = { "#111111", "#222222", "#333333", "#444444", "#555555", "#666666", "#777777", "#888888" }
E.settingsFile:setUi(data)
local np = #previews
pk:apply()
eq(applied[#applied], "#FFFF80", "Apply reports the colour")
check(not pk.frame.Visible or pk.frame.Parent == nil, "and closes")
eq(#previews, np, "nothing put back after Apply")
local rec = E.settingsFile:getUi().recentColors
eq(rec[1], "#FFFF80", "first in the recent colours")
eq(#rec, 8, "at most 8")
eq(rec[8], "#777777", "the oldest one dropped")

section("Cancel puts the old colour back")
local pk2 = openPicker("#3F7CF0", "#3F7CF0")
check(#pk2.recent >= 1 and pk2.recent[1].BackgroundColor3 == Color3.fromHex("FFFF80"), "the recent row shows it")
UIH.click(pk2.recent[2])
eq(pk2:hex(), "#111111", "a recent swatch picks its colour")
eq(previews[#previews], "#111111", "and previews it")
local n = #applied
UIH.click(pk2.cancelButton.gui)
eq(#applied, n, "Cancel reports nothing")
eq(previews[#previews], "#3F7CF0", "and puts the old colour back")
eq(E.settingsFile:getUi().recentColors[1], "#FFFF80", "and stores nothing")
local pk3 = openPicker("#3F7CF0", "#3F7CF0")
UIH.click(pk3.quick[1])
UIH.key(Enum.KeyCode.Escape)
eq(previews[#previews], "#3F7CF0", "Esc puts it back too")
local pk4 = openPicker("#3F7CF0")
eq(pk4.resetButton, nil, "no Reset without a default")
local np4 = #previews
pk4:cancel()
eq(#previews, np4, "nothing previewed, nothing put back")

section("Reset to default")
local pk5 = openPicker("#123456", "#3F7CF0")
check(pk5.resetButton ~= nil, "a Reset to default button")
UIH.click(pk5.resetButton.gui)
eq(applied[#applied], "#3F7CF0", "it applies the default")
check(pk5.frame.Parent == nil, "and closes")

section("in the Settings window: the interface shows the colour while picking")
local s = E.settings
wm:open("settings")
M.steps(2)
local sw = ui.settingsWin
local row = sw.rows.accentColor
check(row ~= nil, "the accent row")
s:set("accentColor", "#3F7CF0")
UIH.click(row.ctl.gui)
M.steps(1)
local swPk
for _, d in ipairs(ui.root.layer:GetDescendants()) do if d.Name == "Popover" then swPk = d end end
check(swPk ~= nil, "the picker opened")
local swSq = swPk and swPk:FindFirstChild("Square", true)
UIH.click(swSq.AbsolutePosition + Vector2.new(swSq.AbsoluteSize.X - 1, 1))
check(s:get("accentColor") ~= "#3F7CF0", "the accent follows the picker (" .. s:get("accentColor") .. ")")
eq(ui.theme.c.accent, Color3.fromHex(s:get("accentColor"):sub(2)), "and the theme shows it")
UIH.key(Enum.KeyCode.Escape)
eq(s:get("accentColor"), "#3F7CF0", "closing without Apply: the old accent")
wm:close("settings")

section("the custom easing curve")
E.settings:set("easing", "Custom")
local bz = Bezier.new(ctx, holder(160, 200))
local box = bz.box
local h1 = bz.handles[1]
UIH.drag(UIH.center(h1), box.AbsolutePosition + Vector2.new(box.AbsoluteSize.X * 0.5, box.AbsoluteSize.Y * 0.25))
near(E.settings:get("bezierX1"), 0.5, 0.02, "the first handle writes x1")
near(E.settings:get("bezierY1"), 0.75, 0.02, "and y1")
UIH.drag(UIH.center(bz.handles[2]), box.AbsolutePosition + Vector2.new(box.AbsoluteSize.X * 3, -box.AbsoluteSize.Y * 5))
eq(E.settings:get("bezierX2"), 1, "x2 clamped to 1")
eq(E.settings:get("bezierY2"), 2, "y2 clamped to 2")
UIH.click(UIH.find(bz.gui, "Ease in"))
eq(E.settings:get("bezierX1") .. " " .. E.settings:get("bezierY1") .. " " .. E.settings:get("bezierX2") .. " " .. E.settings:get("bezierY2"), "0.42 0 1 1", "Ease in sets all four")
eq(bz.fields[1].box.Text, "0.42", "the x1 box shows it")
UIH.typeInto(bz.fields[2].box, "9", true)
eq(E.settings:get("bezierY1"), 2, "a typed y1 clamped to 2")
UIH.click(UIH.find(bz.gui, "Ease"))
E.settings:set("animationLength", 0.4)
UIH.click(UIH.find(bz.gui, "Preview"))
local track, dot = bz.track, bz.dot
M.step(0.2)
local want = Tween.bezier(0.25, 0.1, 0.25, 1)(0.5) * (track.AbsoluteSize.X - dot.AbsoluteSize.X)
near(dot.Position.X.Offset, want, 1.5, "at half the length the dot is where the curve says")
M.steps(30, 1 / 60)
near(dot.Position.X.Offset, track.AbsoluteSize.X - dot.AbsoluteSize.X, 1e-6, "and ends at the far end")
E.settings:set("easing", "Preset")
E.settings:set("animationLength", 0.2)

section("the curve editor at another interface scale (review: the handle ran ahead of the mouse)")
E.settings:set("interfaceScale", 150)
E.settings:set("easing", "Custom")
local bz2 = Bezier.new(ctx, holder(160, 200))
local box2 = bz2.box
UIH.drag(UIH.center(bz2.handles[1]), box2.AbsolutePosition + Vector2.new(box2.AbsoluteSize.X * 0.5, box2.AbsoluteSize.Y * 0.25))
near(E.settings:get("bezierX1"), 0.5, 0.02, "x1 where the mouse let go")
near(E.settings:get("bezierY1"), 0.75, 0.02, "y1 too")
UIH.click(UIH.find(bz2.gui, "Preview"))
M.steps(60, 1 / 60)
local t2, d2 = bz2.track, bz2.dot
near(d2.AbsolutePosition.X + d2.AbsoluteSize.X, t2.AbsolutePosition.X + t2.AbsoluteSize.X, 0.5, "the preview dot ends at the track's end")
E.settings:set("easing", "Preset")
E.settings:set("interfaceScale", 100)
finish()
