-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5a: the theme (colours, transparencies, fonts, sizes from the Appearance settings, a
-- font preview) and the interface's tweens (Roblox easing, the custom cubic bezier, the Animations presets)
-- (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local Theme = __T3("ui/theme")
local Tween = __T3("ui/tween")
local ui = E.ui
local theme, tw = ui.theme, ui.tween
check(theme ~= nil and tw ~= nil, "E.ui has a theme and a tween runner")
local function c3(hex) return Color3.fromHex(hex) end
local function sameColor(a, b, label)
	check(math.abs(a.R - b.R) < 1e-6 and math.abs(a.G - b.G) < 1e-6 and math.abs(a.B - b.B) < 1e-6, label .. " (" .. a:ToHex() .. " vs " .. b:ToHex() .. ")")
end

section("the palette from the defaults")
sameColor(theme.c.glass, c3("#242A38"), "glass")
sameColor(theme.c.accent, c3("#3F7CF0"), "accent")
sameColor(theme.c.text, c3("#FFFFFF"), "text")
sameColor(theme.c.text2, c3("#B4BBC8"), "secondary text")
sameColor(theme.c.rec, c3("#FF5A5A"), "recording")
sameColor(theme.c.reset1, c3("#FFC86E"), "reset top")
sameColor(theme.c.reset2, c3("#F0A032"), "reset bottom")
sameColor(theme.c.close, c3("#FF6A6A"), "close dot")
near(theme.t.glass, 0.54, 1e-9, "glass transparency 54 %")
near(theme.t.rim, 0.84, 1e-9, "rim = 1 - edge light 16 %")

section("a settings change fires changed once")
local n = 0
local off = theme:changed(function() n = n + 1 end)
E.settings:set("accentColor", "#FF0000")
eq(n, 1, "once")
sameColor(theme.c.accent, c3("#FF0000"), "the new accent")
E.settings:set("playbackSpeed", 2)
eq(n, 1, "a setting that isn't Appearance: nothing")
E.settings:set("accentColor", "#3F7CF0")
E.settings:set("playbackSpeed", 1)
off()
E.settings:set("accentColor", "#00FF00")
eq(n, 2, "removed")
E.settings:set("accentColor", "#3F7CF0")

section("sizes and corners")
near(theme.size(13), 13, 1e-9, "13 at text size 13")
E.settings:set("textSize", 26 / 2 * 2) -- 26 is out of range: 24
near(theme.size(13), 24, 1e-9, "13 at text size 24")
E.settings:set("textSize", 13)
eq(theme.corner("window"), 16, "window corners 16")
eq(theme.corner("control"), 999, "Pill")
E.settings:set("buttonShape", "Rounded")
eq(theme.corner("control"), 8, "Rounded")
E.settings:set("buttonShape", "Square")
eq(theme.corner("control"), 2, "Square")
E.settings:set("buttonShape", "Pill")

section("fonts and the preview")
local f = theme.font("text")
eq(f.Family, "rbxasset://fonts/families/BuilderSans.json", "text font")
eq(f.Weight, Enum.FontWeight.Regular, "regular")
eq(theme.font("bold").Weight, Enum.FontWeight.Bold, "bold")
eq(theme.font("number").Family, "rbxasset://fonts/families/RobotoMono.json", "number font")
local fired = 0
local off2 = theme:changed(function() fired = fired + 1 end)
theme:preview("Oswald")
eq(theme.font("text").Family, "rbxasset://fonts/families/Oswald.json", "preview: the text font")
eq(theme.font("bold").Family, "rbxasset://fonts/families/Oswald.json", "preview: bold too")
eq(E.settings:get("font"), "BuilderSans", "the stored font unchanged")
theme:preview(nil)
eq(theme.font("text").Family, "rbxasset://fonts/families/BuilderSans.json", "back")
eq(fired, 2, "changed fires for the preview and its end")
off2()

section("the cubic bezier")
local bz = Tween.bezier(0.25, 0.1, 0.25, 1)
near(bz(0.5), 0.8024, 1e-3, "CSS ease at 0.5")
near(bz(0), 0, 1e-9, "starts at 0")
near(bz(1), 1, 1e-9, "ends at 1")
local lin = Tween.bezier(0, 0, 1, 1)
for _, x in ipairs({ 0.1, 0.33, 0.7 }) do near(lin(x), x, 1e-4, "0,0,1,1 is linear at " .. x) end
local over = Tween.bezier(0.34, 1.56, 0.64, 1)
local peak = 0
for i = 0, 100 do peak = math.max(peak, over(i / 100)) end
check(peak > 1.05, "y above 1 allowed (overshoot " .. peak .. ")")

section("curves from the settings")
E.settings:set("easing", "Custom")
local cv = Tween.curve(E.settings)
near(cv(0.5), 0.8024, 1e-3, "Custom: the bezier settings")
E.settings:set("easing", "Preset")
E.settings:set("animations", "Smooth")
near(Tween.length(E.settings), 0.2, 1e-9, "Smooth: the animation length")
E.settings:set("animations", "Snappy")
near(Tween.length(E.settings), 0.12, 1e-9, "Snappy: 0.6 x length")
E.settings:set("animations", "Off")
eq(Tween.length(E.settings), 0, "Off: no time")
E.settings:set("animations", "Smooth")

section("a tween ends on its goal, Off is instant, the handler idles")
local fr = Instance.new("Frame")
fr.BackgroundTransparency = 1
fr.Position = UDim2.new(0, 0, 0, 0)
fr.Parent = ui.root.layer
tw:play(fr, { BackgroundTransparency = 0, Position = UDim2.new(0, 100, 0, 50) })
check(tw:running() == 1, "one tween running")
M.step(0.1)
check(fr.BackgroundTransparency > 0 and fr.BackgroundTransparency < 1, "half way (" .. fr.BackgroundTransparency .. ")")
M.steps(20, 1 / 60)
eq(fr.BackgroundTransparency, 0, "exactly on the goal")
eq(fr.Position, UDim2.new(0, 100, 0, 50), "position on the goal")
eq(tw:running(), 0, "none running")
local function tweenHandlers()
	local n = 0
	for _, e in ipairs(getgenv().__HappaTAS3_T.pipe.stages.PreRender) do if e.name == "ui.tween" then n = n + 1 end end
	return n
end
eq(tweenHandlers(), 0, "no tween handler in the pipeline while idle (an idle handler costs a resume a frame)")
local w0 = M.propWrites
M.steps(60, 1 / 60)
eq(M.propWrites - w0, 0, "no writes while idle")
E.settings:set("animations", "Off")
tw:play(fr, { BackgroundTransparency = 0.5 })
eq(fr.BackgroundTransparency, 0.5, "Off: at once")
eq(tw:running(), 0, "nothing left running")
E.settings:set("animations", "Smooth")
tw:play(fr, { BackgroundTransparency = 1 })
tw:play(fr, { BackgroundTransparency = 0.25 })
eq(tw:running(), 1, "a new tween on the same object replaces the old one")
tw:finishAll()
eq(fr.BackgroundTransparency, 0.25, "finishAll: on the goal")
eq(tw:running(), 0, "finished")
local h = tw:play(fr, { BackgroundTransparency = 0.9 })
M.step(0.05)
tw:cancel(h)
local v = fr.BackgroundTransparency
M.steps(10, 1 / 60)
eq(fr.BackgroundTransparency, v, "cancel stops where it was")
finish()
