-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1: a long Help topic is shown whole. Live, a self-sizing text in a scrolling page stopped growing
-- at about the page's height (431 px for "Moving through your TAS": its end was cut off). The text is far taller
-- than any topic and the page scrolls as far as its measured text, for every topic and text size (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
E.settings:set("interface", "New")
M.steps(2)
ui.wm:open("help")
M.steps(2)
local hw = ui.helpWin
local b = hw.body
local function h() return hw.page.CanvasSize.Y.Offset end
local function fits()
	return b.AutomaticSize == Enum.AutomaticSize.None and b.Size.Y.Offset >= 10000
		and hw.page.AutomaticCanvasSize == Enum.AutomaticSize.None and h() >= b.Position.Y.Offset + b.TextBounds.Y
end

section("the page scrolls as far as the text")
hw:show("inputs")
M.steps(1)
check(fits(), "a long topic: the page scrolls " .. h() .. " for text " .. b.TextBounds.Y)
local long = h()
hw:show("missing")
M.steps(1)
check(fits() and h() < long, "a short topic is shorter (" .. h() .. ")")

section("a bigger text size: it grows again")
hw:show("inputs")
M.steps(1)
E.settings:set("textSize", 17)
M.steps(2)
check(fits() and h() > long, "taller after the text size went up (" .. h() .. ")")
E.settings:set("textSize", 13)
M.steps(2)
finish()
