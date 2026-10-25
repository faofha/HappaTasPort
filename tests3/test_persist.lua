-- needs: fsfail v2fixtures
-- ================================================================================================
-- HappaTAS 3, phase 3: loading and saving a run in the engine (V2 files keep the data phase 4's plugins
-- will use; v6 round trip; refusals; the busy guard)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
check(E.char:loaded(), "character loaded")
local Env = __T3("platform/env")
local Files = __T3("platform/files")
local Library = __T3("persist/library")
local Run = __T3("persist/run")
local Persist = __T3("persist/persist")
local Timeline = __T3("engine/timeline")
local Codec6 = __T3("persist/codec6")

local ROOT = "HappaTasPort/persisttest"
local files = Files.new(Env)
files:makeFolder(ROOT)
for _, name in ipairs({ "kitspeed.tas", "plain.tas", "legacy.json", "wrapped.tas" }) do
	files:write(ROOT .. "/" .. name, FIXTURES[name].data)
end
-- (main wires these from Task 7 on; here the suite does)
if not E.persist then
	Run.registerCarry(E.tl)
	E.library = Library.new(files, ROOT)
	E.persist = Persist.new(E)
else
	E.library = Library.new(files, ROOT)
end

local events, statuses = {}, {}
E.bus:on("persist", function(ev) events[#events + 1] = ev end)
E.bus:on("status", function(text) statuses[#statuses + 1] = text end)
local function waitIdle()
	local g = 0
	while E.busy and g < 2000 do M.step(1 / 60); g = g + 1 end
	return not E.busy
end

local function deepEqual(a, b, path)
	path = path or "value"
	if type(a) ~= type(b) then return false, path .. ": " .. type(a) .. " / " .. type(b) end
	if type(a) == "number" then
		if a ~= a then return b ~= b, path end
		if a == 0 and b == 0 then return 1 / a == 1 / b, path .. ": -0" end
		return a == b, path .. ": " .. tostring(a) .. " / " .. tostring(b)
	end
	if type(a) ~= "table" then return a == b, path .. ": " .. tostring(a) .. " / " .. tostring(b) end
	for k, v in pairs(a) do
		local ok, why = deepEqual(v, b[k], path .. "." .. tostring(k))
		if not ok then return false, why end
	end
	for k in pairs(b) do
		if a[k] == nil then return false, path .. "." .. tostring(k) .. " only on one side" end
	end
	return true
end

section("carry columns")
for _, key in ipairs({ "Mobile", "CO", "BT", "KE", "SK" }) do
	local col = E.tl.cols["v2" .. key]
	check(col and col.kind == "list" and col.v2.key == key and col.v2.keep == true, "carry column for " .. key)
end
local before = E.tl:count()
Run.registerCarry(E.tl)
check(E.tl.cols.v2CO ~= nil, "registering twice is harmless")

section("a V2 file into the engine")
do
	local exp = FIXTURES["kitspeed.tas"].expected
	local ok, msg = E.persist:load("kitspeed.tas")
	check(ok, "load started (" .. tostring(msg) .. ")")
	eq(E.busy, "loading", "busy while loading")
	for _, a in ipairs({ "idle", "create", "test", "deleteTas", "optimize", "toggleSpeedHack" }) do
		check(not E.modes:allowed(a), "no " .. a .. " while loading")
	end
	check(waitIdle(), "load finished")
	local last = events[#events]
	check(last and last.op == "load" and last.ok == true and last.path == "kitspeed.tas", "bus: persist load ok")
	eq(E.tl:count(), #exp.frames, "every frame")
	-- what the timeline holds is what it gets from V2's own frames
	local ref = Timeline.newLike(E.tl)
	ref:replaceFromV2(exp.frames)
	local same, why = deepEqual(E.tl:toV2All(), ref:toV2All(), "frames")
	check(same, "the same as V2's frames through the timeline " .. tostring(why))
	-- and the data with no plugin yet is V2's, frame for frame
	local carried = true
	for i, f in ipairs(exp.frames) do
		for _, key in ipairs({ "Mobile", "CO", "BT", "KE", "SK" }) do
			if not deepEqual(E.tl:getList("v2" .. key, i), f[key]) then carried = false; check(false, "frame " .. i .. " " .. key) break end
		end
		if not carried then break end
	end
	check(carried, "client objects, buttons, kit events, speed factors and mobile kept")
	check((deepEqual(E.tl.meta.v2kit, exp.kit)), "kit table kept")
	check((deepEqual(E.tl.meta.v2objects, exp.objects)), "object table kept")
	check((deepEqual(E.tl.meta.v2buttons, exp.buttons)), "button table kept")
	eq(E.tl.meta.kitVersion, 1, "kit version")
	eq(E.tl.meta.source, "v5", "source")
	check(statuses[#statuses]:find("Loaded", 1, true) ~= nil, "status: " .. tostring(statuses[#statuses]))
end

section("legacy files load too")
for _, name in ipairs({ "plain.tas", "legacy.json", "wrapped.tas" }) do
	E.persist:load(name)
	waitIdle()
	local ev = events[#events]
	check(ev.ok, name .. " loaded (" .. tostring(ev.message) .. ")")
	eq(E.tl:count(), #FIXTURES[name].expected.frames, name .. " frames")
end

section("save as v6, load it again")
do
	E.persist:load("kitspeed.tas")
	waitIdle()
	local snapshot = E.tl:toV2All()
	local meta = table.clone(E.tl.meta)
	local ok = E.persist:save("again")
	check(ok, "save started")
	eq(E.busy, "saving", "busy while saving")
	check(not E.modes:allowed("unpause") and not E.modes:allowed("idle") and not E.modes:allowed("deleteTas"), "no transitions while saving")
	check(waitIdle(), "save finished")
	local ev = events[#events]
	check(ev.op == "save" and ev.ok and ev.path == "again.tas", "bus: persist save ok (" .. tostring(ev.message) .. ")")
	local data = files:read(ROOT .. "/again.tas")
	local h = Codec6.readHeader(data)
	check(h ~= nil and h.frames == #snapshot, "a v6 file with the frame count")
	eq(h.kit, 1, "header: kit rules version")
	eq(h.speedHack, 1, "header: speed hack used (speed factors in the run)")
	check(h.created ~= nil and h.saved ~= nil and h.created <= h.saved, "header: created / saved")
	near(h.length, snapshot[#snapshot].TotalTime, 1e-9, "header: length")
	E.persist:load("again.tas")
	waitIdle()
	check((deepEqual(E.tl:toV2All(), snapshot)), "every frame the same after v6")
	check((deepEqual(E.tl.meta.v2kit, meta.v2kit)) and E.tl.meta.kitVersion == 1, "meta the same after v6")
	eq(E.tl.meta.created, h.created, "created kept")
	-- an attempt
	check((E.persist:save("again", nil, true)), "save as a new attempt")
	waitIdle()
	check(files:exists(ROOT .. "/again (2).tas"), "again (2).tas")
end

section("refusals (Review focus 5)")
do
	-- recording
	E.modes:request("create")
	M.steps(2)
	E.modes:request("unpause")
	M.steps(4)
	check(E.mode == 2 and not E.paused, "recording")
	local n = E.tl:count()
	local ok, msg = E.persist:save("rec")
	check(not ok and type(msg) == "string", "save refused while recording: " .. tostring(msg))
	check(not files:exists(ROOT .. "/rec.tas"), "nothing written")
	local okL = E.persist:load("plain.tas")
	check(not okL, "load refused while recording")
	E.modes:request("pause")
	M.steps(2)
	check(E.tl:count() >= n, "the run unchanged by the refusals")
	-- paused in Create: load works and the character goes to the last frame
	local okP = E.persist:load("plain.tas")
	check(okP, "load allowed while paused")
	waitIdle()
	eq(E.frame, E.tl:count(), "on the loaded run's last frame")
	-- Test
	E.modes:request("test")
	M.steps(2)
	eq(E.mode, 3, "testing")
	check(not E.persist:load("plain.tas"), "load refused in Test")
	local okT = E.persist:save("from test")
	check(okT, "save allowed in Test")
	waitIdle()
	E.modes:request("idle")
	M.steps(2)
	-- busy: a second save while one runs
	check((E.persist:save("one")), "first save")
	local okB, msgB = E.persist:save("two")
	check(not okB and type(msgB) == "string", "a second save while busy is refused: " .. tostring(msgB))
	waitIdle()
end

section("a damaged file leaves the run as it was")
do
	E.persist:load("again.tas")
	waitIdle()
	local data = files:read(ROOT .. "/again.tas")
	files:write(ROOT .. "/broken.tas", data:sub(1, #data - 40))
	local tlBefore, version, count = E.tl, E.tl.version, E.tl:count()
	check((E.persist:load("broken.tas")), "load started")
	waitIdle()
	local ev = events[#events]
	check(ev.op == "load" and ev.ok == false and type(ev.message) == "string", "bus: load failed with a message (" .. tostring(ev.message) .. ")")
	check(E.tl == tlBefore and E.tl.version == version and E.tl:count() == count, "the run is the same object, same version")
	-- a file whose damage shows only while its frames are written (header: 10 frames, the column: 1)
	local Bytes, Value = __T3("persist/bytes"), __T3("persist/value")
	local body = Bytes.writer()
	body:varint(1); body:str("FrameTime"); body:u8(1); body:u8(1)
	local comp = Bytes.writer(); comp:varint(0)
	local payload = Bytes.writer(); payload:varint(comp:len()); payload:raw(comp:tostring())
	body:varint(payload:len()); body:raw(payload:tostring())
	Value.write(body, {})
	local hw = Bytes.writer(); Value.write(hw, { frames = 10 })
	local raw = body:tostring()
	local late = Bytes.writer(); late:raw("HTAS"); late:u8(6); late:u8(0); late:varint(hw:len()); late:raw(hw:tostring())
	late:varint(#raw); late:raw(raw)
	files:write(ROOT .. "/late.tas", late:tostring())
	check((E.persist:load("late.tas")), "load started")
	waitIdle()
	check(events[#events].ok == false, "a file damaged inside a column fails")
	check(E.tl == tlBefore and E.tl.version == version and E.tl:count() == count, "and the run is still the same")
	local okM = E.persist:load("missing.tas")
	check(okM, "a missing file: started")
	waitIdle()
	check(events[#events].ok == false, "a missing file fails through the bus")
end

section("Delete TAS: the next run doesn't keep the old run's info")
do
	E.persist:load("again.tas")
	waitIdle()
	check(E.tl.meta.kitVersion == 1 and E.tl.meta.created ~= nil and E.tl.meta.v2kit ~= nil, "a loaded run with its info")
	E.modes:request("deleteTas")
	M.steps(1)
	E.modes:request("deleteTas")
	M.steps(1)
	eq(E.tl:count(), 0, "deleted")
	eq(next(E.tl.meta), nil, "no info left from the deleted run")
	E.modes:request("create")
	M.steps(2)
	E.modes:request("unpause")
	M.steps(4)
	E.modes:request("pause")
	M.steps(2)
	check(E.tl:count() > 0, "a new run recorded")
	check((E.persist:save("fresh")), "saved")
	waitIdle()
	local h = Codec6.readHeader(files:read(ROOT .. "/fresh.tas"))
	eq(h and h.kit, 0, "its header doesn't say kit rules from the old run")
	E.persist:load("fresh.tas")
	waitIdle()
	eq(E.tl.meta.v2kit, nil, "no old kit table in it")
	E.modes:request("idle")
	M.steps(2)
end

section("no file functions")
do
	local saved = E.library.files.available
	E.library.files.available = false
	local ok, msg = E.persist:save("x")
	eq(ok, false, "save refused")
	eq(msg, "Saving is unavailable on this executor", "the message")
	check(not E.persist:load("again.tas"), "load refused")
	E.library.files.available = saved
end
finish()
