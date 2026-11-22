-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1: the update log's light box shows at once. Live, a self-sizing panel in a scrolling page wasn't
-- drawn after it grew until the page scrolled once (the texts were). Each panel that grows now moves the page's
-- canvas 1 px and back in the same frame (no visible scroll), which makes Roblox draw it. About (New, and the
-- Tasability ABOUT tab that hosts it) and Classic's credits / update log (headless mock: the canvas writes are checked)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end

local function nudged(panel, scroller)
	local log = {}
	M.writeLog = log
	panel:GetPropertyChangedSignal("AbsoluteSize"):Fire()
	M.steps(1)
	M.writeLog = nil
	local n = 0
	for _, w in ipairs(log) do if w[1] == scroller and w[2] == "CanvasPosition" then n = n + 1 end end
	return n
end

section("New: About's panels")
E.settings:set("interface", "New")
M.steps(2)
ui.wm:open("about")
M.steps(2)
local aw = ui.aboutWin
local before = aw.page.CanvasPosition
check(nudged(aw.log, aw.page) >= 2, "the update log growing moves the page's canvas and back")
eq(aw.page.CanvasPosition, before, "the page stays where it was")
check(nudged(aw.credits, aw.page) >= 2, "the credits panel too")

section("Classic: credits and update log")
E.settings:set("interface", "Classic")
M.steps(3)
local root = ui.classic and ui.classic.gui or nil
local logF, credF
for _, d in ipairs((root or game):GetDescendants()) do
	if d.Name == "3UpdateLog" then logF = d end
	if d.Name == "5Credits" then credF = d end
end
check(logF ~= nil and credF ~= nil, "Classic has its update log and credits")
local sc = logF and logF.Parent
while sc and not sc:IsA("ScrollingFrame") do sc = sc.Parent end
check(sc ~= nil, "inside a scrolling frame")
if logF and sc then
	check(nudged(logF, sc) >= 2, "Classic's update log growing moves the canvas and back")
	check(nudged(credF, sc) >= 2, "and its credits")
end
E.settings:set("interface", "New")
M.steps(2)
finish()
