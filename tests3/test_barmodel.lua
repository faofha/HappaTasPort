-- ================================================================================================
-- HappaTAS 3, phase 5b: the timeline model (the run's events by kind, grown by the frames added, rebuilt
-- when the run changes) and markers (headless mock)
-- ================================================================================================
check(boot(3), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local BarModel = __T3("ui/bar/model")
local Run = __T3("persist/run")
local Timeline = __T3("engine/timeline")
local tl = E.tl

-- a filled frame with a state and optional list values
local function frame(state, lists)
	local i = tl:append()
	tl:set("State", i, 1, state)
	tl:setN("FrameTime", i, 1 / 60)
	tl:setN("TotalTime", i, i / 60)
	for k, v in pairs(lists or {}) do tl:setList(k, i, v) end
	tl:setFilled(i)
	return i
end
local function list(t) return table.concat(t, ",") end

section("events by kind")
tl:cut(0)
local states = { 8, 8, 3, 3, 8, 8, 8, 8, 8, 8 }
for i, s in ipairs(states) do
	local l = {}
	if i == 4 then l.Died = true end
	if i == 2 or i == 7 then l.Input = { 32 } end
	if i == 5 then l.Tools = { { "Equip", "Heal" } } end
	frame(s, l)
end
local m = BarModel.new(E)
m:sync()
eq(list(m:events("state")), "3,5", "state changes")
eq(list(m:events("death")), "4", "deaths")
eq(list(m:events("input")), "2,7", "inputs")
eq(list(m:events("tool")), "5", "tools")
eq(#m:events("kit"), 0, "no kit events")
eq(#m:events("nonsense"), 0, "an unknown kind is empty")

section("grows by the added frames")
local reads = {}
local origGetList = tl.getList
tl.getList = function(self, name, i) reads[i] = true; return origGetList(self, name, i) end
local v0 = m.version
for i = 11, 15 do frame(8, (i == 13) and { Input = { 33 } } or nil) end
m:sync()
local early = 0
for i in pairs(reads) do if i <= 10 then early = early + 1 end end
eq(early, 0, "frames 1-10 not read again")
check(reads[11] and reads[15], "frames 11-15 read")
eq(list(m:events("input")), "2,7,13", "the new input")
check(m.version ~= v0, "the version moved")
reads = {}
v0 = m.version
m:sync()
eq(next(reads), nil, "nothing changed: nothing read")
eq(m.version, v0, "and the same version")
-- (a frame appended but not filled yet, as while recording before PreSimulation: not indexed)
local half = tl:append()
tl:setList("Input", half, { 34 })
m:sync()
eq(list(m:events("input")), "2,7,13", "an unfilled frame waits")
tl:setFilled(half)
m:sync()
eq(list(m:events("input")), "2,7,13," .. half, "indexed once filled")
tl.getList = origGetList

section("rebuilds on change")
tl:cut(6)
m:sync()
eq(list(m:events("input")), "2", "nothing past the cut")
eq(list(m:events("tool")), "5", "tool kept")
local other = Timeline.newLike(tl)
for i = 1, 3 do
	local j = other:append()
	other:set("State", j, 1, 8)
	if i == 2 then other:setList("Died", j, true) end
	other:setFilled(j)
end
tl:adopt(other)
m:sync()
eq(list(m:events("death")), "2", "the adopted run's events")
eq(#m:events("input"), 0, "no inputs in it")

section("markers round trip")
tl:cut(0)
for i = 1, 6 do frame(8) end
m:sync()
eq(m:toggleMarker(3, "Jump"), true, "added")
eq(list(m:events("marker")), "3", "listed")
eq(m:markerAt(3), "Jump", "its label")
-- (Run.build / Run.load pace themselves with task.wait: run them on a thread, the mock stepping)
local data, fresh = nil, Timeline.newLike(tl)
task.spawn(function()
	data = Run.build(tl, "markers")
	Run.load(fresh, data)
end)
local guard = 0
while fresh:count() == 0 and guard < 600 do M.step(1 / 60); guard = guard + 1 end
eq(fresh:getList("Marker", 3), "Jump", "saved and loaded")
eq(m:toggleMarker(3), false, "removed")
eq(#m:events("marker"), 0, "none left")
eq(m:markerAt(3), nil, "no label")
m:toggleMarker(5)
eq(m:markerAt(5), true, "a marker without a label")

section("range")
tl:cut(0)
for i = 1, 500 do frame(8, (i % 100 == 0) and { Input = { 32 } } or nil) end
m:sync()
local a, b = m:range("input", 150, 450)
local got = {}
for k = a, b do got[#got + 1] = m:events("input")[k] end
eq(list(got), "200,300,400", "the inputs in 150-450")
a, b = m:range("input", 1, 50)
check(a > b, "none in 1-50")

section("long run (10 minutes at 240 FPS)")
tl:cut(0)
for i = 1, 144000 do
	local j = tl:append()
	tl:set("State", j, 1, 8)
	if j % 100 == 0 then tl:setList("Input", j, { 32 }) end
	tl:setFilled(j)
end
local t0 = os.clock()
m:sync()
local took = os.clock() - t0
check(took < 2, "built in under 2 s (" .. string.format("%.3f", took) .. " s)")
eq(#m:events("input"), 1440, "every input")
reads = {}
tl.getList = function(self, name, i) reads[i] = true; return origGetList(self, name, i) end
m:sync()
eq(next(reads), nil, "a second sync reads nothing")
tl.getList = origGetList
finish()
