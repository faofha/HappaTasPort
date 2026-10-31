-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5a: glass windows and the window manager: open / close / focus, drag by the title,
-- resize from the edges and the grip, minimise, layout per screen size (Review Focus 3), Reset layout,
-- sheets on touch-only devices, restyled by the theme, no per-frame work (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local ui = E.ui
local wm = ui.wm
check(wm ~= nil, "the window manager")
local Windows = __T3("ui/windows")
local cam = workspace.CurrentCamera
local function setScreen(w, h)
	M.viewport = Vector2.new(w, h)
	cam:GetPropertyChangedSignal("ViewportSize"):Fire()
end
local function pos(win) return Vector2.new(win.holder.Position.X.Offset, win.holder.Position.Y.Offset) end
local function size(win) return Vector2.new(win.holder.Size.X.Offset, win.holder.Size.Y.Offset) end
local built = {}
for _, id in ipairs({ "a", "b" }) do
	wm:define(id, { title = "Window " .. id, w = 300, h = 200, minW = 200, minH = 120,
		build = function(body, win) built[id] = (built[id] or 0) + 1 end })
end

section("open / close / toggle / focus")
eq(wm:isOpen("a"), false, "closed at first")
eq(E.modalOpen(), false, "no window open: the mouse isn't freed")
wm:open("a")
wm:open("b")
local A, B = wm.windows.a, wm.windows.b
eq(built.a, 1, "built on first open")
check(A.holder.Visible and B.holder.Visible, "both shown")
eq(E.modalOpen(), true, "a window open: E.modalOpen")
check(B.holder.ZIndex > A.holder.ZIndex, "the last opened is in front")
wm:focus("a")
check(A.holder.ZIndex > B.holder.ZIndex, "focus brings a to the front")
UIH.click(UIH.center(B.body))
check(A.holder.ZIndex > B.holder.ZIndex, "a click where a covers b goes to a (in front)")
-- (b is 24 px right of / below a: its body's bottom right corner isn't under a)
UIH.click(B.body.AbsolutePosition + B.body.AbsoluteSize - Vector2.new(10, 22))
check(B.holder.ZIndex > A.holder.ZIndex, "a press on b's body brings b to the front")
eq(ui:pointerOver(), true, "the pointer over a window is on the interface")
wm:close("a")
eq(wm:isOpen("a"), false, "closed")
eq(A.holder.Visible, false, "hidden")
wm:toggle("a")
eq(wm:isOpen("a"), true, "toggle opens")
eq(built.a, 1, "not built again")
UIH.click(UIH.center(A.closeDot))
eq(wm:isOpen("a"), false, "the close dot closes")
wm:open("a")
eq(wm:anyOpen(), true, "anyOpen")

section("drag by the title")
setScreen(1920, 1080)
wm:place("a", 400, 300)
local t = A.titleBar
UIH.drag(UIH.center(t), UIH.center(t) + Vector2.new(100, 50))
eq(pos(A), Vector2.new(500, 350), "moved by the drag")
UIH.drag(UIH.center(t), UIH.center(t) + Vector2.new(-2000, 0))
eq(pos(A).X, 0, "stops at the left edge")
UIH.drag(UIH.center(t), UIH.center(t) + Vector2.new(5000, 5000))
eq(pos(A).X + size(A).X, 1920, "stops at the right edge")
eq(pos(A).Y + size(A).Y, 1080, "stops at the bottom")
UIH.drag(UIH.center(t), UIH.center(t) + Vector2.new(0, -5000))
eq(pos(A).Y, M.inset, "the title bar stays below the top bar")

section("resize")
wm:place("a", 400, 300)
local left = A.holder.AbsolutePosition + Vector2.new(2, A.holder.AbsoluteSize.Y / 2)
UIH.drag(left, left + Vector2.new(-50, 0))
eq(pos(A).X, 350, "the left edge moves the window's left side")
eq(size(A).X, 350, "and makes it wider")
UIH.drag(UIH.center(A.grip), UIH.center(A.grip) + Vector2.new(60, 40))
eq(size(A), Vector2.new(410, 240), "the grip resizes")
UIH.drag(UIH.center(A.grip), UIH.center(A.grip) + Vector2.new(-1000, -1000))
eq(size(A), Vector2.new(200, 120), "never smaller than the window's minimum")

section("minimise")
wm:place("a", 400, 300)
local h0 = size(A).Y
UIH.click(UIH.center(A.minDot))
eq(size(A).Y, A.titleH, "only the title bar")
eq(A.body.Visible, false, "the body hidden")
UIH.click(UIH.center(A.minDot))
eq(size(A).Y, h0, "back to its height")
eq(A.body.Visible, true, "the body back")

section("layout per screen size (Review Focus 3)")
setScreen(1920, 1080)
wm:place("a", 40, 60)
wm:save("a")
local layout = E.settingsFile:getUi().layout
eq(layout["1920x1080"] and layout["1920x1080"].a and layout["1920x1080"].a.x, 40, "saved under 1920x1080")
setScreen(1280, 720)
eq(pos(A), Vector2.new(40, 60), "no layout for 1280x720: kept where it was (it fits)")
wm:place("a", 10, 70)
wm:save("a")
setScreen(1920, 1080)
eq(pos(A), Vector2.new(40, 60), "1920x1080's own place")
setScreen(1280, 720)
eq(pos(A), Vector2.new(10, 70), "1280x720's own place")
setScreen(1920, 1080)
do
	local wm2 = Windows.new(E, ui)
	wm2:define("a", { title = "again", w = 300, h = 200, minW = 200, minH = 120, build = function() end })
	wm2:open("a")
	eq(Vector2.new(wm2.windows.a.holder.Position.X.Offset, wm2.windows.a.holder.Position.Y.Offset), Vector2.new(40, 60), "a new start uses the saved place")
	wm2:destroy()
end

section("a smaller screen keeps open windows on screen (Review Focus 3)")
setScreen(1920, 1080)
wm:place("b", 1600, 860)
wm:save("b")
setScreen(1024, 600)
check(pos(B).X >= 0 and pos(B).X + size(B).X <= 1024, "b inside the width (" .. tostring(pos(B)) .. ")")
check(pos(B).Y >= M.inset and pos(B).Y + size(B).Y <= 600, "b inside the height")
setScreen(1920, 1080)
eq(pos(B), Vector2.new(1600, 860), "back on the big screen: its place there")

section("Reset layout")
wm:resetLayout()
local ly = E.settingsFile:getUi().layout["1920x1080"]
check(ly == nil or next(ly) == nil, "the screen size's saved places gone")
local step = (table.find(wm.order, "a") - 1) * 24 -- (windows defined earlier, like Settings, cascade the later ones)
eq(pos(A), Vector2.new(math.floor((1920 - 300) / 2) + step, math.floor((1080 - 200) / 2) + step), "a back at its default place and size")
eq(size(A), Vector2.new(300, 200), "default size")

section("restyled by the theme")
E.settings:set("glassColor", "#102030")
local pc = A.panel.BackgroundColor3
check(math.abs(pc.R - 16 / 255) < 1e-6 and math.abs(pc.G - 32 / 255) < 1e-6, "the panel's colour at once")
E.settings:set("glassColor", "#242A38")
E.settings:set("shadows", 0)
eq(A.shadow.Visible, false, "Shadows off")
E.settings:set("shadows", 1)
eq(A.shadow.Visible, true, "Shadows on")

section("no per-frame work while nothing moves")
local w0 = M.propWrites
M.steps(60, 1 / 60)
eq(M.propWrites - w0, 0, "no GUI writes over 60 idle frames with two windows open")

section("sheets on a touch-only device")
local uis = game:GetService("UserInputService")
uis.TouchEnabled, uis.KeyboardEnabled = true, false
wm:define("c", { title = "Sheet", w = 300, h = 200, minW = 200, minH = 120, build = function() end })
wm:open("c")
local Cw = wm.windows.c
eq(size(Cw).X, 1920, "full width")
eq(size(Cw).Y, math.floor(1080 * 0.6), "60 % high")
eq(pos(Cw).Y + size(Cw).Y, 1080, "at the bottom")
local p0 = pos(Cw)
UIH.drag(UIH.center(Cw.titleBar), UIH.center(Cw.titleBar) + Vector2.new(0, -200))
eq(pos(Cw), p0, "a sheet doesn't move")
uis.TouchEnabled, uis.KeyboardEnabled = false, true
wm:close("c")

section("a bigger interface scale keeps windows on screen (review: one ended off screen)")
setScreen(1920, 1080)
wm:open("a")
wm:place("a", 1600, 200)
E.settings:set("interfaceScale", 150)
M.steps(2)
local ha = wm.windows.a.holder
check(ha.AbsolutePosition.X + ha.AbsoluteSize.X <= 1920 + 0.5, "fully on screen at 150 % (right edge " .. ha.AbsolutePosition.X + ha.AbsoluteSize.X .. ")")
check(ha.AbsolutePosition.X >= -0.5, "left edge too")
E.settings:set("interfaceScale", 100)
M.steps(2)

section("Unload")
getgenv().__HappaTAS3.Unload()
M.steps(2)
eq(A.holder.Parent, nil, "windows gone")
finish()
