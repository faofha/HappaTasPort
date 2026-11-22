-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1 Compact (Task 2): the theme's compact mode (Gotham, square, solid shades tinted from the
-- accent, no shadows) and the New look back exactly when it ends (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local th = ui.theme
local Theme = __T3("ui/theme")
local Glass = __T3("ui/kit/glass")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end

local function lum(c)
	local function ch(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
	return 0.2126 * ch(c.R) + 0.7152 * ch(c.G) + 0.0722 * ch(c.B)
end
local function contrast(a, b)
	local la, lb = lum(a), lum(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end
local function hueDist(a, b)
	local d = math.abs(a - b) % 1
	return math.min(d, 1 - d) * 360
end

section("the shades")
local ORDER = { "deep", "window", "inline", "panel", "element", "hover" }
for _, hex in ipairs({ "#3FB950", "#F85149", "#3F7CF0" }) do
	local accent = Color3.fromHex(hex:sub(2))
	local sh = Theme.compactShades(accent)
	local ah = accent:ToHSV()
	for i, k in ipairs(ORDER) do
		local c = sh[k]
		check(c ~= nil and lum(c) < 0.2, hex .. " " .. k .. " is dark")
		if i > 1 then check(lum(c) > lum(sh[ORDER[i - 1]]), hex .. " " .. k .. " lighter than " .. ORDER[i - 1]) end
		local h, s = c:ToHSV()
		check(s > 0 and hueDist(h, ah) <= 30, hex .. " " .. k .. " tinted toward the accent")
	end
	check(sh.border ~= nil and sh.outline ~= nil, hex .. " border and outline shades")
	check(contrast(Color3.new(1, 1, 1), sh.panel) >= 7, hex .. " white text readable on a panel")
end

section("compact mode")
local holder = Instance.new("Frame")
holder.Parent = ui.root.layer
local g = Glass.panel(th, holder, {})
local before = { corner = g.corner.CornerRadius, t = g.panel.BackgroundTransparency, font = th.font("text").Family,
	shadow = g.shadow.Visible }
local fired = 0
local off = th:changed(function() fired = fired + 1 end)
th:setCompact(true)
eq(fired, 1, "one change when it turns on")
th:setCompact(true)
eq(fired, 1, "none for a no-op")
eq(th.compact, true, "compact")
eq(th.corner("window"), 0, "square windows")
eq(th.corner("control"), 0, "square controls")
eq(th.font("text"), Font.fromEnum(Enum.Font.GothamMedium), "GothamMedium text")
eq(th.font("bold"), Font.fromEnum(Enum.Font.GothamBold), "GothamBold titles")
eq(th.font("number"), Font.fromEnum(Enum.Font.GothamMedium), "GothamMedium numbers")
check(th.shades ~= nil, "the shades")
eq(g.corner.CornerRadius, UDim.new(0, 0), "a glass panel is square")
eq(g.panel.BackgroundTransparency, 0, "and solid")
eq(g.panel.BackgroundColor3, th.shades.window, "in the window shade")
eq(g.shadow.Visible, false, "without a shadow")
eq(g.rim.Color, th.shades.outline, "its rim is the outline shade")
eq(g.rim.Transparency, 0, "a solid rim")
local oldWindow = th.shades.window
E.settings:set("accentColor", "#F85149")
check(th.shades.window ~= oldWindow, "a new accent re-tints the shades")
E.settings:set("accentColor", "#3FB950")
th:setCompact(false)
eq(fired >= 2, true, "a change when it turns off")
eq(th.compact, false, "not compact")
eq(th.shades, nil, "no shades outside compact mode")
eq(g.corner.CornerRadius, before.corner, "the New corner back")
eq(g.panel.BackgroundTransparency, before.t, "the New transparency back")
eq(th.font("text").Family, before.font, "the New font back")
eq(g.shadow.Visible, before.shadow, "the shadow back")
eq(g.rim.Color, Color3.new(1, 1, 1), "the white rim back")

section("the interface switch drives it")
E.settings:set("interface", "Compact")
M.steps(2)
eq(th.compact, true, "Compact: compact mode")
E.settings:set("interface", "New")
M.steps(2)
eq(th.compact, false, "New: not")
off()
g:destroy()
holder:Destroy()
finish()
