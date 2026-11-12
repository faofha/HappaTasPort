-- ================================================================================================
-- HappaTAS 3: the mouse while paused in Create ("Keep Mouse Position (Paused)"): a cursor image shows where the
-- mouse was on the frame shown and follows Back / Forward (the real mouse stays free for the menus); unpausing
-- puts the real mouse back on the frame the recording goes on from, so the recorded mouse doesn't jump to
-- wherever it was left (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local tl = E.tl
local s = E.settings
local UIS = M.services.UserInputService

local function moved()
	local out = {}
	for _, e in ipairs(M.inputLog) do
		if e[1] == "mousemoveabs" then out[#out + 1] = { e[2], e[3] } end
	end
	return out
end
local function record(n, x0)
	E.modes:request("unpause")
	for i = 1, n do
		M.mouse = Vector2.new(x0 + i * 50, 200 + i * 10)
		M.step(1 / 60)
	end
	E.modes:request("pause")
	M.steps(3)
end
local function point(f) return tl:get("Mouse", f, 1), tl:get("Mouse", f, 2) end
local function imgAt()
	local img = E.cursor.img
	if not (img and img.Visible) then return nil end
	return img.Position.X.Offset, img.Position.Y.Offset
end

eq(s:get("pausedMouse"), 1, "Keep Mouse Position (Paused) is on by default")
E.modes:request("create")
M.steps(3)
record(8, 100)
local n = tl:count()
check(n >= 6, "a run was recorded (" .. n .. " frames)")

section("paused: a cursor image on the frame's mouse position")
do
	local mx, my = point(E.frame)
	local ix, iy = imgAt()
	eq(ix, mx, "the image is at the frame's mouse x")
	eq(iy, my, "and y")
	check(E.cursor.img and E.cursor.img.ImageTransparency > 0.2, "it is see-through (not the real cursor)")
	eq(UIS.MouseIconEnabled, true, "the real cursor stays visible")
	M.mouse = Vector2.new(1500, 900) -- (the real mouse goes off to a menu)
	M.steps(3)
	ix, iy = imgAt()
	eq(ix, mx, "the real mouse moved: the image stays on the frame's position")
	E.modes:back1()
	M.steps(3)
	eq(E.frame, n - 1, "Back 1 Frame")
	local bx, by = point(n - 1)
	check(bx ~= mx, "(the frame before had the mouse elsewhere)")
	ix, iy = imgAt()
	eq(ix, bx, "going back: the image goes to that frame's mouse x")
	eq(iy, by, "and y")
	E.modes:forward1()
	M.steps(3)
	ix, iy = imgAt()
	eq(ix, mx, "going forward again: back on the last frame's")
end

section("unpausing: the real mouse goes back to the frame the recording goes on from")
do
	E.modes:back1()
	E.modes:back1()
	M.steps(3)
	local f = E.frame
	local fx, fy = point(f)
	local u, v = tl:get("Mouse", f, 3), tl:get("Mouse", f, 4)
	M.mouse = Vector2.new(1700, 80)
	M.inputLog = {}
	E.modes:request("unpause")
	local mv = moved()
	eq(#mv, 1, "one mouse move when unpausing")
	eq(mv[1] and mv[1][1], fx, "to the frame's x")
	eq(mv[1] and mv[1][2], fy, "and y")
	for _ = 1, 6 do M.step(1 / 60) end
	E.modes:request("pause")
	M.steps(3)
	check(tl:count() > f, "the recording went on from frame " .. f .. " (" .. tl:count() .. " frames)")
	eq(tl:get("Mouse", f + 1, 1), fx, "the first new frame has the mouse where the frame had it")
	eq(tl:get("Mouse", f + 1, 2), fy, "(y)")
	near(tl:get("Mouse", f + 1, 3), u, 1e-9, "(the normalised position too)")
	near(tl:get("Mouse", f + 1, 4), v, 1e-9, "(v)")
	eq(M.mouse.X, fx, "and the real mouse is there")
	check(imgAt() ~= nil, "paused again: the image is back")
end

section("Real's mouse (lands late and a little off before its fit is measured): one correction")
do
	M.realMouse = { w = 1920, h = 1080, ox = 0, oy = 23 }
	M.osMouse = nil
	local f = E.frame
	local fx, fy = point(f)
	M.mouse = Vector2.new(300, 950)
	M.inputLog = {}
	E.modes:request("unpause")
	for _ = 1, 8 do M.step(1 / 60) end
	E.modes:request("pause")
	M.steps(3)
	local mv = moved()
	check(#mv >= 1 and #mv <= 2, "at most one correction (" .. #mv .. " moves)")
	eq(tl:get("Mouse", f + 1, 1), fx, "the first new frame has the frame's own position while the move lands")
	eq(tl:get("Mouse", f + 2, 1), fx, "and the second")
	check(math.abs(tl:get("Mouse", f + 3, 1) - fx) <= 1 and math.abs(tl:get("Mouse", f + 3, 2) - fy) <= 1,
		"then the real mouse is within a pixel of it (" .. tl:get("Mouse", f + 3, 1) .. ", " .. tl:get("Mouse", f + 3, 2) .. " for " .. fx .. ", " .. fy .. ")")
	M.realMouse, M.osMouse = nil, nil
end

section("not when the camera had the mouse locked on that frame, not with the setting off, not in Idle")
do
	local f = E.frame
	tl:set("ShiftLock", f, 1, 1)
	M.steps(2)
	M.inputLog = {}
	E.inputs:putMouseBack(tl, f)
	eq(#moved(), 0, "a shift lock frame: no move")
	tl:set("ShiftLock", f, 1, 0)
	s:set("pausedMouse", 0)
	M.steps(3)
	eq(imgAt(), nil, "setting off: no image while paused")
	M.inputLog = {}
	E.modes:request("unpause")
	M.steps(4)
	E.modes:request("pause")
	M.steps(3)
	eq(#moved(), 0, "setting off: unpausing moves nothing")
	s:set("pausedMouse", 1)
	M.steps(3)
	check(imgAt() ~= nil, "setting on again: the image shows")
	E.modes:request("idle")
	M.steps(4)
	eq(imgAt(), nil, "Idle: no image")
end
finish()
