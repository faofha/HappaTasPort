-- ================================================================================================
-- Text placement when a TextSize-tall line holds the font's whole ascender..descender (the way
-- Roblox's text engine sizes fonts: TextLabel.TextSize = "the height of one line of rendered text")
-- ================================================================================================
M.textLineModel = true
check(boot(5), "boots")
local P, S = __T.Profiler, __T.Settings
S.Set("Show MicroProfiler", 1)
M.step(1 / 60)
local U, I = P.Internals()

section("6 px grid with a line-height TextSize")
near(P.TextSize, 10 * 2701 / 2048, 0.01, "TextSize 13.19 = a 10 px em = 6 px per Roboto Mono character")
near(U.title.sh.TextBounds.X, 13 * 6, 0.05, "MicroProfiler is 78 px wide")
near(U.readout.sh.TextBounds.X, #U.readout.s * 6, 0.05, "the readout keeps 6 px per character")
eq(I.menuX[1], 96, "Mode starts at x = 96 like Roblox's")

section("baseline")
-- baseline = 2146 / 2048 em = 10.48 px under the line top; Roblox's MicroProfiler has it 7.5 px
-- under the row top (capitals on rows 0-7), so the labels move up 3 px (baseline 7.48)
local dy, auto, nudge = P.TextOffset()
eq(auto, -3, "automatic offset -3")
eq(dy, -3, "applied")
eq(nudge, 0, "no manual correction")
check(U.title.sh.Position == UDim2.fromOffset(1, -2), "title shadow at (0+1, 0+1-3)")
check(U.title.lb.Position == UDim2.fromOffset(-1, -1), "white text 1 px up-left of its shadow")
S.Set("MicroProfiler Text Offset", 1)
check(U.title.sh.Position == UDim2.fromOffset(1, -1), "Text Offset +1 moves it down 1 px")
S.Set("MicroProfiler Text Offset", 0)

section("mouse still lines up")
M.moveMouse(I.menuX[2] + 3, 4)
M.step(1 / 60)
check(U.dd.f.Visible and I.dd.menu == 2, "Groups menu opens on hover")
M.moveMouse(I.menuX[2] + 10, 9 + 9 * 2 + 4) -- line 3, "   Engine"
M.step(1 / 60)
M.click(1)
M.step(1 / 60)
eq(P.Config().groups.Engine, false, "a click on '   Engine' turns the group off")
M.click(1)
M.step(1 / 60)
eq(P.Config().groups.Engine, true, "and on again")
finish()
