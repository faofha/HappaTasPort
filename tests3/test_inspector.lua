-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5b: the Inspector: every value V2.38.16's stats panels showed (paused: the frame;
-- recording / Idle: the live character; Test: the playback), non-modal, open by default and remembered, pin /
-- hide, the stats settings, the run changing under it, its update rate, timing only while Performance shows
-- (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local wm = ui.wm
local Util = __T3("engine/util")
local IV = __T3("ui/win/inspectorvalues")
local Timeline = __T3("engine/timeline")
local W = __T3("ui/write")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local function rebind()
	T = getgenv().__HappaTAS3_T
	E = T.engine
	ui = E.ui
	wm = ui.wm
end
local function r3(v) return tostring(Util.round(v, 1000)) end
local function stateName(n)
	for _, it in ipairs(Enum.HumanoidStateType:GetEnumItems()) do
		if it.Value == n then return it.Name end
	end
	return "None"
end

section("open by default, and non-modal")
eq(wm:isOpen("inspector"), true, "open on the first start")
eq(E.modalOpen(), false, "it doesn't free the mouse")
eq(E.modal, false, "E.modal too")
check(ui.dock.buttons.inspector ~= nil, "a Dock button")
wm:open("settings")
eq(E.modalOpen(), true, "Settings does")
wm:close("settings")
eq(E.modalOpen(), false, "closed again: not modal")
do
	-- (top right, off the play area: a click in the middle of the screen is the game's)
	local win = wm.windows.inspector
	local sw = wm:screen()
	check(win.x + win.w >= sw - 40 and win.x > sw / 2, "opens at the right edge (x " .. win.x .. ")")
	check(win.y < 120, "near the top (y " .. win.y .. ")")
	check(not E.inputs:overOwnUI(), "the mouse in the middle of the screen isn't over it")
end

section("every V2 stats value (paused: the frame shown)")
E.modes:request("create")
M.steps(3)
E.modes:request("unpause")
M.steps(40, 1 / 60)
E.modes:request("pause")
M.steps(2)
local tl = E.tl
local f = math.floor(tl:count() / 2)
E.modes:request("seek", { frame = f })
M.steps(2)
local v = IV.values(E, { fps = 60, ms = 0.1 })
local cf = { tl:getN("Cframe", f) }
eq(v.frame, f .. " / " .. tl:count(), "frame")
eq(v.frameTime, tostring(tl:get("FrameTime", f, 1)), "frame time")
eq(v.totalTime, Util.toTime(tl:get("TotalTime", f, 1)), "total time")
eq(v.position, r3(cf[1]) .. ", " .. r3(cf[2]) .. ", " .. r3(cf[3]), "position")
eq(v.state, stateName(tl:get("State", f, 1)), "state")
eq(v.zoom, r3(tl:get("Zoom", f, 1)), "zoom")
eq(v.keys, E.inputs:describe(E.inputs:heldAt(tl, f)), "keys held at the frame")
eq(v.mouse, tl:get("Mouse", f, 1) .. ", " .. tl:get("Mouse", f, 2), "mouse")
local lin = { tl:getN("Lin", f) }
eq(v.velocity, r3(lin[1]) .. ", " .. r3(lin[2]) .. ", " .. r3(lin[3]), "velocity")
for _, row in ipairs(IV.LIST) do
	check(type(v[row.key]) == "string", "a value for " .. row.key)
end

section("Idle: the live character; Test: the playback")
E.modes:request("idle")
M.steps(2)
local hrp = E.char.hrp
local p = hrp.Position
v = IV.values(E, { fps = 60, ms = 0.1 })
eq(v.position, r3(p.X) .. ", " .. r3(p.Y) .. ", " .. r3(p.Z), "the live root's position")
E.settings:set("playbackSpeed", 0.5)
E.modes:request("test")
M.steps(5, 1 / 60)
v = IV.values(E, { fps = 60, ms = 0.1 })
eq(v.totalTime, Util.toTime(E.testTime), "the playback time")
eq(v.speed, "0.5", "the playback speed")
E.settings:set("playbackSpeed", 1)
E.modes:request("create")
M.steps(2)

-- (a section header scrolled into view, then clicked)
local function clickHeader(name)
	local sec = ui.inspector.sections[name]
	ui.inspector.list.CanvasPosition = Vector2.new(0, math.max(0, sec.gui.Position.Y.Offset - 10))
	M.steps(1)
	UIH.click(sec.header)
end

section("the window shows them")
local insp = ui.inspector
check(insp ~= nil, "the Inspector")
M.steps(3)
check(insp.rows.position.value.Text ~= "", "the position row has a value")
eq(insp.rows.state.label.Text, "State", "rows have their labels")

section("pin and hide")
UIH.click(insp.rows.zoom.pin.gui)
M.steps(2)
check(insp.pinned.zoom ~= nil and insp.pinned.zoom.gui.Visible, "Zoom in Pinned")
UIH.click(insp.rows.health.hide.gui)
M.steps(2)
eq(insp.rows.health.gui.Visible, false, "Health hidden")
UIH.click(insp.options.gui)
M.steps(2)
local show = insp.optionsPop and insp.optionsPop.showButtons and insp.optionsPop.showButtons.health
check(show ~= nil, "the options list Health with a Show button")
if show then UIH.click(show.gui) end
M.steps(2)
eq(insp.rows.health.gui.Visible, true, "Health back")
UIH.key(Enum.KeyCode.Escape)
UIH.click(insp.rows.floor.hide.gui)
M.steps(60, 1 / 60) -- (kept in the settings file a moment later)

section("stats settings (spec 6.3)")
E.settings:set("showStatsCreate", 0)
M.steps(2)
eq(insp.note.Visible, true, "a note in Create")
eq(insp.note.Text, "Hidden in Create", "what it says")
eq(insp.sections.Character.gui.Visible, false, "no values")
E.settings:set("showStatsCreate", 1)
M.steps(2)
eq(insp.note.Visible, false, "values back")
E.settings:set("statsTextSize", 20)
M.steps(2)
eq(insp.rows.position.value.TextSize, 20, "Stats Text Size sizes the values")
E.settings:set("statsTextSize", 11)
E.settings:set("showStatsTest", 0)
E.settings:set("playbackSpeed", 0.5)
E.modes:request("test")
M.steps(3)
eq(insp.sections.Frame.gui.Visible, true, "Test at another speed: the Frame section still shows")
eq(insp.sections.Character.gui.Visible, false, "the rest hidden")
E.modes:request("create")
E.settings:set("showStatsTest", 1)
E.settings:set("playbackSpeed", 1)
M.steps(2)

section("the run changes under it")
E.modes:request("seek", { frame = tl:count() })
M.steps(2)
local frames = tl:toV2All()
local k = math.max(2, #frames - 5)
local short = {}
for i = 1, k do short[i] = frames[i] end
local fresh = Timeline.newLike(tl)
fresh:replaceFromV2(short)
tl:adopt(fresh)
E.modes:runLoaded()
M.steps(2)
eq(insp.rows.frame.value.Text, k .. " / " .. k, "the frame row on the new run")

section("cost in Idle: about V2's Idle panel (6 property reads and the zoom every 2nd frame)")
do
	E.modes:request("idle")
	M.steps(120) -- (the switch to Idle settles first)
	local function reads(n)
		local r0 = M.propReads
		M.steps(n, 1 / 60)
		return (M.propReads - r0) / n
	end
	wm:close("inspector")
	M.steps(2)
	local closed = reads(120)
	wm:open("inspector")
	M.steps(2)
	local open = reads(120)
	-- (V2's panel: 7 reads and the zoom, about 5 more in the mock, every 2nd frame)
	check(open - closed <= 6, "Inspector reads per frame in Idle: " .. string.format("%.2f", open - closed))
	insp = ui.inspector
	-- (standing still: values that didn't change aren't written out again)
	local hrp = E.char.hrp
	hrp.AssemblyLinearVelocity, hrp.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
	insp:update(false, false)
	local oRound, rounds = Util.round, 0
	Util.round = function(...) rounds = rounds + 1; return oRound(...) end
	insp:update(false, false)
	Util.round = oRound
	check(rounds <= 1, "standing still: no number formatted again (" .. rounds .. ")")
	-- (standing still in Idle: the values are only worked out on the once-a-second ticks)
	local oValues, calls = IV.values, 0
	IV.values = function(...) calls = calls + 1; return oValues(...) end
	M.steps(120, 1 / 60)
	check(calls <= 2, "still: worked out " .. calls .. " times in 2 s")
	calls = 0
	hrp.AssemblyLinearVelocity = Vector3.new(10, 0, 0)
	M.steps(120, 1 / 60)
	hrp.AssemblyLinearVelocity = Vector3.zero
	check(calls >= 9, "moving: " .. calls .. " times in 2 s")
	calls = 0
	M.steps(13, 1 / 60)
	calls = 0
	UIH.key(Enum.KeyCode.H)
	M.steps(13, 1 / 60)
	check(calls >= 1, "a key press shows (" .. calls .. ")")
	IV.values = oValues
	E.modes:request("create")
	M.steps(3)
end

section("update rate")
local writeFrames, wrote = 0, false
local oSet, oPaint = W.set, W.paint
local function counted(fn)
	return function(inst, prop, value)
		local done = fn(inst, prop, value)
		if done and inst:IsDescendantOf(wm.windows.inspector.holder) then wrote = true end
		return done
	end
end
W.set, W.paint = counted(oSet), counted(oPaint)
E.modes:request("unpause")
for _ = 1, 60 do
	wrote = false
	M.step(1 / 60)
	if wrote then writeFrames = writeFrames + 1 end
end
E.modes:request("pause")
M.steps(3)
check(writeFrames >= 4 and writeFrames <= 5, "recording: written 5 times a second (" .. writeFrames .. " of 60 frames)")
-- (Performance's HappaTAS ms changes by nature: collapsed for the check below)
clickHeader("Performance")
M.steps(3)
writeFrames = 0
for _ = 1, 30 do
	wrote = false
	M.step(1 / 60)
	if wrote then writeFrames = writeFrames + 1 end
end
W.set, W.paint = oSet, oPaint
eq(writeFrames, 0, "paused, nothing changing: nothing written")

section("timing only while Performance shows")
eq(T.pipe.timing, false, "collapsed: not timed")
clickHeader("Performance")
M.steps(2)
eq(T.pipe.timing, true, "open again")
wm:close("inspector")
M.steps(2)
eq(T.pipe.timing, false, "window closed: not timed")
M.steps(60, 1 / 60)

section("remembered after a re-run")
check(boot(30), "runs again")
rebind()
eq(wm:isOpen("inspector"), false, "it stays closed")
wm:open("inspector")
M.steps(2)
insp = ui.inspector
check(insp.pinned.zoom ~= nil and insp.pinned.zoom.gui.Visible, "Zoom still pinned")
eq(insp.rows.floor.gui.Visible, false, "Floor still hidden")
finish()
