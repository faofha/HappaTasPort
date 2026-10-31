-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5b: the timeline bar: a strip in Idle without a run, transport, seeking by dragging
-- (clamped, never while recording), wheel zoom, readout / mode / speed, markers, the unsaved dot, a run
-- changing under it, a long run, no writes while nothing changes (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local W = __T3("ui/write")
local Util = __T3("engine/util")
local Timeline = __T3("engine/timeline")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local bar = ui.bar
check(bar ~= nil, "the bar")
local function height() return bar.gui.Size.Y.Offset end
local function waitIdle()
	local g = 0
	while E.busy and g < 2000 do M.step(1 / 60); g = g + 1 end
	return not E.busy
end
local function trackY() return bar.track.AbsolutePosition.Y + bar.track.AbsoluteSize.Y / 2 end
local function tx(f) return bar.track.AbsolutePosition.X + bar:xOf(f) * ui.root.scale.Scale end

section("a strip in Idle without a run, full in Create")
eq(E.tl:count(), 0, "no run")
eq(height(), 10, "a strip")
eq(bar.buttons.back1.enabled, false, "step back can't be used")
E.modes:request("create")
M.steps(3)
eq(height(), 40, "full in Create")

section("transport")
UIH.click(bar.buttons.rec.gui)
M.steps(1)
check(E.mode == 2 and not E.paused, "record: recording")
eq(bar.modeLabel.Text, "Recording", "the mode label")
M.steps(40, 1 / 60)
UIH.click(bar.buttons.rec.gui)
M.steps(2)
eq(E.paused, true, "record again: paused")
local n = E.tl:count()
check(n > 30, "frames recorded (" .. n .. ")")
eq(bar.modeLabel.Text, "Paused", "Paused")
local f0 = E.frame
UIH.click(bar.buttons.back1.gui)
M.steps(2)
eq(E.frame, f0 - 1, "step back")
UIH.click(bar.buttons.forward1.gui)
M.steps(2)
eq(E.frame, f0, "step forward")
UIH.click(bar.buttons.start.gui)
M.steps(2)
eq(E.frame, 1, "start: frame 1")
UIH.click(bar.buttons.test.gui)
M.steps(2)
eq(E.mode, 3, "Test")
eq(bar.modeLabel.Text, "Test", "the label says Test")
UIH.click(bar.buttons.test.gui)
M.steps(2)
eq(E.mode, 2, "back to Create")

section("seek by dragging (clamped; never while recording)")
local a, s = bar.track.AbsolutePosition, bar.track.AbsoluteSize
local y = trackY()
UIH.drag(Vector2.new(a.X + s.X / 2, y), Vector2.new(a.X - 200, y))
eq(E.frame, 1, "dragged past the start: frame 1")
UIH.drag(Vector2.new(a.X + s.X / 2, y), Vector2.new(a.X + s.X + 200, y))
eq(E.frame, E.tl:count(), "past the end: the last frame")
eq(bar:frameAt(a.X - 50), 1, "frameAt clamps low")
eq(bar:frameAt(a.X + s.X + 50), E.tl:count(), "and high")
UIH.drag(Vector2.new(a.X + s.X / 2, y), Vector2.new(a.X + s.X / 4, y))
check(math.abs(E.frame - bar:frameAt(a.X + s.X / 4)) <= 1, "the frame under the pointer")
UIH.click(bar.buttons.rec.gui)
M.steps(2)
local fr = E.frame
UIH.click(Vector2.new(a.X + 5, y))
M.steps(1)
check(E.mode == 2 and not E.paused, "a click on the track while recording: still recording")
check(E.frame >= fr, "no seek while recording")
UIH.click(bar.buttons.rec.gui)
M.steps(2)
E.modes:request("test")
M.steps(2)
UIH.drag(Vector2.new(a.X + s.X / 2, y), Vector2.new(a.X + s.X + 50, y))
eq(E.frame, E.tl:count() - 1, "scrubbed in Test past the end: count - 1")
E.modes:request("create")
M.steps(2)

section("wheel zoom")
local mid = Vector2.new(a.X + s.X * 0.5, y)
local fm = bar:frameAt(mid.X)
UIH.wheel(mid, 1)
M.steps(1)
check(bar.view.last - bar.view.first < E.tl:count() - 1, "zoomed in")
check(math.abs(tx(fm) - mid.X) <= s.X / (bar.view.last - bar.view.first) + 1, "the frame under the pointer stays under it")
for _ = 1, 60 do UIH.wheel(mid, 1) end
M.steps(1)
check(bar.view.last - bar.view.first + 1 >= 10, "never fewer than 10 frames (" .. bar.view.last - bar.view.first + 1 .. ")")
for _ = 1, 80 do UIH.wheel(mid, -1) end
M.steps(1)
eq(bar.view.first, 1, "zoomed out: from frame 1")
eq(bar.view.last, E.tl:count(), "to the last")

section("readout, speed")
UIH.click(bar.buttons.start.gui)
M.steps(2)
n = E.tl:count()
check(bar.readout.Text:find("^1 / " .. n) ~= nil, "frame / count (" .. bar.readout.Text .. ")")
check(bar.readout.Text:find(Util.toTime(E.tl:get("TotalTime", 1, 1)), 1, true) ~= nil, "the frame's time")
E.settings:set("speedHackSpeed", 0.5)
E.settings:set("speedHack", 1)
M.steps(1)
eq(bar.speedLabel.Text, "0.5x", "the speed hack's speed")
E.settings:set("speedHack", 0)
M.steps(1)
eq(bar.speedLabel.Text, "", "no speed shown at 1x")

section("marker button")
E.modes:request("seek", { frame = 5 })
M.steps(2)
UIH.click(bar.buttons.marker.gui)
M.steps(7)
eq(bar.model:markerAt(5), true, "a marker on frame 5")
local function markAt(f)
	for _, m in ipairs(bar.marks) do
		if m.Visible and math.abs(m.Position.X.Offset - bar:xOf(f)) <= 1 then return true end
	end
	return false
end
check(markAt(5), "drawn at frame 5's x")
UIH.click(bar.buttons.marker.gui)
M.steps(7)
eq(bar.model:markerAt(5), nil, "removed")
check(not markAt(5), "and gone from the track")

section("the unsaved dot")
eq(bar.unsaved.Visible, true, "recorded, never saved: shown")
check((E.persist:save("bar test", "")), "save started")
check(waitIdle(), "saved")
M.steps(1)
eq(bar.unsaved.Visible, false, "saved: hidden")
E.modes:request("seek", { frame = E.tl:count() })
M.steps(2)
E.modes:request("unpause")
M.steps(10, 1 / 60)
E.modes:request("pause")
M.steps(2)
eq(bar.unsaved.Visible, true, "more frames: shown")
check((E.persist:load("bar test.tas")), "load started")
check(waitIdle(), "loaded")
M.steps(1)
eq(bar.unsaved.Visible, false, "loaded: hidden")

section("the run changes under the bar")
local frames = E.tl:toV2All()
local k = math.max(2, #frames - 5)
check(#frames > k, "a shorter run (" .. k .. " of " .. #frames .. ")")
local short = {}
for i = 1, k do short[i] = frames[i] end
local fresh = Timeline.newLike(E.tl)
fresh:replaceFromV2(short)
E.tl:adopt(fresh)
E.modes:runLoaded()
M.steps(1)
check(bar.readout.Text:find("^" .. k .. " / " .. k .. " ") ~= nil, "the readout on the new run (" .. bar.readout.Text .. ")")
near(bar.playhead.Position.X.Offset, bar:xOf(k), 1, "the playhead on its last frame")
near(bar:xOf(k), bar.trackW, 1e-6, "the last frame at the track's end")

section("no writes while nothing changes")
local writes = 0
local origSet, origPaint = W.set, W.paint
local function counted(f)
	return function(inst, prop, value)
		local done = f(inst, prop, value)
		if done and inst:IsDescendantOf(bar.gui) then writes = writes + 1 end
		return done
	end
end
W.set, W.paint = counted(origSet), counted(origPaint)
M.steps(30, 1 / 60)
W.set, W.paint = origSet, origPaint
eq(writes, 0, "paused 30 frames: nothing written")

section("a long run (10 minutes at 240 FPS)")
E.modes:request("idle")
M.steps(2)
local small = #bar.gui:GetDescendants()
local tl = E.tl
tl:cut(0)
for i = 1, 144000 do
	local j = tl:append()
	tl:set("State", j, 1, 8)
	tl:setN("FrameTime", j, 1 / 240)
	tl:setN("TotalTime", j, j / 240)
	if j % 1000 == 0 then tl:setList("Marker", j, true) end
	tl:setFilled(j)
end
E.modes:runLoaded()
M.steps(2)
eq(#bar.gui:GetDescendants(), small, "no more GUI objects than the pools (" .. small .. ")")
check(bar.readout.Text:find("144000", 1, true) ~= nil, "the readout")
finish()
