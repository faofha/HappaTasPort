-- needs: v2fixtures
-- ================================================================================================
-- HappaTAS 3, phase 4: plugin plumbing (the new hooks, columns that aren't saved, a plugin column in place
-- of phase 3's carry column, the engine slots time control and the kit fill in)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
check(E.char:loaded(), "character loaded")
local Timeline = __T3("engine/timeline")
local Codec6 = __T3("persist/codec6")
local Run = __T3("persist/run")
local Util = __T3("engine/util")

-- codec calls yield: run them on a thread the mock steps
local function inThread(f)
	local res, done
	local co = coroutine.create(function() res = { f() }; done = true end)
	local ok, err = coroutine.resume(co)
	if not ok then error(err) end
	local g = 0
	while not done and g < 5000 do M.step(1 / 60); g = g + 1 end
	return table.unpack(res)
end
local HEADER = { frames = 0, length = 0, created = 1, saved = 2, script = "test", place = 1, kit = 0, speedHack = 0, name = "t" }

section("hook order")
do
	local log = {}
	local function probe(name, order)
		local p = { name = name, order = order }
		for _, h in ipairs({ "onFrameStart", "begin", "onPreSimulation", "fill", "onCut", "onUnpause", "onPause", "onRewind", "onSave" }) do
			p[h] = function(_, a, b) log[#log + 1] = { name, h, a, b } end
		end
		return E.plugins:add(p)
	end
	probe("p45", 45)
	probe("p56", 56)
	local function idx(name, h, from)
		for i = from or 1, #log do
			if log[i][1] == name and log[i][2] == h then return i end
		end
		return nil
	end
	E.modes:request("create")
	M.steps(2)
	E.modes:request("unpause")
	M.steps(6)
	E.modes:request("pause")
	M.steps(2)
	local n = E.tl:count()
	check(n >= 3, "recorded " .. n .. " frames")
	-- a recorded frame: onFrameStart, then begin (PreRender), then onPreSimulation, then fill (PreSimulation)
	local b = idx("p45", "begin")
	local fs = b and (function() for i = b, 1, -1 do if log[i][2] == "onFrameStart" and log[i][1] == "p45" then return i end end end)()
	check(fs ~= nil and fs < b, "onFrameStart before begin in the frame")
	local ps = idx("p45", "onPreSimulation", b)
	local fl = idx("p45", "fill", b)
	check(ps ~= nil and fl ~= nil and ps < fl, "onPreSimulation before fill")
	local f45, f56 = b and idx("p45", "fill", b), b and idx("p56", "fill", b)
	check(f45 ~= nil and f56 ~= nil and f45 < f56, "plugins in their order (45 before 56)")
	-- pausing: the kit's rewind, then the pause
	local rw = idx("p45", "onRewind")
	local pa = rw and idx("p45", "onPause", rw)
	check(rw ~= nil and pa ~= nil, "onRewind then onPause")
	-- back two frames, unpause: the frames after the current one are cut first
	log = {}
	E.modes:request("back1")
	M.steps(2)
	E.modes:request("back1")
	M.steps(2)
	local at = E.frame
	E.modes:request("unpause")
	M.steps(1)
	local cut = idx("p45", "onCut")
	check(cut ~= nil, "onCut on unpause after going back")
	eq(cut and log[cut][4], at, "cut to the frame it was on")
	local cuts = 0
	for _, e in ipairs(log) do if e[1] == "p45" and e[2] == "onCut" then cuts = cuts + 1 end end
	eq(cuts, 1, "once")
	local un = cut and idx("p45", "onUnpause", cut)
	check(un ~= nil, "onCut before onUnpause")
	E.modes:request("pause")
	M.steps(2)
	-- saving calls onSave once (before the file is built)
	log = {}
	local Files = __T3("platform/files")
	local Library = __T3("persist/library")
	local saved = E.library
	E.library = Library.new(Files.new(__T3("platform/env")), "HappaTasPort/pluginstest")
	check((E.persist:save("hooks")), "save started")
	local g = 0
	while E.busy and g < 2000 do M.step(1 / 60); g = g + 1 end
	local saves = 0
	for _, e in ipairs(log) do if e[1] == "p45" and e[2] == "onSave" then saves = saves + 1 end end
	eq(saves, 1, "onSave once per save")
	E.library = saved
	E.modes:request("idle")
	M.steps(2)
	for _, p in ipairs({ "p45", "p56" }) do
		for i, q in ipairs(E.plugins.list) do if q.name == p then table.remove(E.plugins.list, i) break end end
		E.plugins.byName[p] = nil
	end
end

section("columns marked save = false are not saved")
do
	local tl = Timeline.new()
	tl:addColumn("FrameTime", "f64", 1, { key = "FrameTime" })
	tl:addColumn("TotalTime", "f64", 1, { key = "TotalTime" })
	tl:addColumn("ProbeT", "u8", 1, { key = "ProbeT", save = false })
	for i = 1, 5 do
		tl:append()
		tl:set("FrameTime", i, 1, 1 / 60)
		tl:set("TotalTime", i, 1, i / 60)
		tl:set("ProbeT", i, 1, i)
		tl:setFilled(i)
	end
	eq(tl:get("ProbeT", 3, 1), 3, "the column holds values while recording")
	local h = table.clone(HEADER); h.frames = 5
	local with = inThread(function() return Codec6.encode(tl, h) end)
	local tl2 = Timeline.new()
	tl2:addColumn("FrameTime", "f64", 1, { key = "FrameTime" })
	tl2:addColumn("TotalTime", "f64", 1, { key = "TotalTime" })
	for i = 1, 5 do
		tl2:append()
		tl2:set("FrameTime", i, 1, 1 / 60)
		tl2:set("TotalTime", i, 1, i / 60)
		tl2:setFilled(i)
	end
	local without = inThread(function() return Codec6.encode(tl2, h) end)
	eq(with, without, "the same bytes as without the column")
	local back = Timeline.new()
	inThread(function() return Codec6.decode(with, back) end)
	eq(back.cols.ProbeT, nil, "decode doesn't create it")
	eq(back:count(), 5, "the frames are there")
end

section("a plugin column replaces phase 3's carry column")
do
	local function base()
		local tl = Timeline.new()
		tl:addColumn("FrameTime", "f64", 1, { key = "FrameTime" })
		tl:addColumn("TotalTime", "f64", 1, { key = "TotalTime" })
		return tl
	end
	local tl = base()
	tl:addColumn("v2CO", "list", 1, { key = "CO", keep = true })
	Run.registerCarry(tl)
	local n = 0
	for _, col in ipairs(tl.order) do if col.name == "v2CO" then n = n + 1 end end
	eq(n, 1, "one v2CO column")
	check(tl.cols.v2BT ~= nil, "the other carry columns are still made")
	local exp = FIXTURES["kitspeed.tas"].expected
	inThread(function() return Run.load(tl, FIXTURES["kitspeed.tas"].data) end)
	local same = true
	for i, f in ipairs(exp.frames) do
		if f.CO ~= tl:getList("v2CO", i) then same = false end
	end
	check(same, "a V2 file's CO data in the plugin's column")
	-- a v6 file written by phase 3 (only carry columns) loads into it too
	local old = base()
	Run.registerCarry(old)
	inThread(function() return Run.load(old, FIXTURES["kitspeed.tas"].data) end)
	local h = table.clone(HEADER); h.frames = old:count()
	local data = inThread(function() return Codec6.encode(old, h) end)
	local tl3 = base()
	tl3:addColumn("v2CO", "list", 1, { key = "CO", keep = true })
	Run.registerCarry(tl3)
	inThread(function() return Codec6.decode(data, tl3) end)
	same = true
	for i, f in ipairs(exp.frames) do
		if f.CO ~= tl3:getList("v2CO", i) then same = false end
	end
	check(same, "phase 3's v6 file's CO data in the plugin's column")
end

section("the engine calls the time control slots")
do
	local real = E.time
	check(real ~= nil and real.scale == 1 and real.anim == 1, "a default slot: scale 1, anim 1")
	eq(real:update(true, nil, nil, true), 1, "the default update gives 1")
	eq(real:stepTime(), nil, "the default stepTime gives nil")
	check(E.kitClock ~= nil and E.kitObjects ~= nil, "kit slots")
	local calls = {}
	local stub = { scale = 1, anim = 1, rate = 0.5, stepT = nil }
	function stub:frameStart() end
	function stub:stepTime() return self.stepT end
	function stub:update() return self.rate end
	function stub:stepping() return false end
	function stub:stepBegin() calls[#calls + 1] = "stepBegin" end
	function stub:humanoidPre() calls[#calls + 1] = "pre" end
	function stub:stepEnd() calls[#calls + 1] = "stepEnd" end
	function stub:humanoidPost() calls[#calls + 1] = "post" end
	E.time = stub
	E.modes:request("create")
	M.steps(2)
	E.modes:request("unpause")
	M.steps(4)
	eq(E.recScale, 0.5, "recScale from update")
	local n = E.tl:count()
	M.step(1 / 60)
	local i = E.tl:count()
	check(i == n + 1, "a frame")
	eq(E.tl:get("FrameTime", i, 1), Util.round(E.lastFrameTime * 0.5, 1000000), "its FrameTime is the frame time x 0.5")
	stub.stepT = 0
	local before = E.tl:count()
	M.steps(3)
	eq(E.tl:count(), before, "stepTime 0: no new frames")
	stub.stepT = nil
	calls = {}
	M.step(1 / 60)
	local seq = table.concat(calls, ",")
	check(seq:find("stepBegin,pre", 1, true) ~= nil, "PreSimulation: stepBegin then humanoidPre (" .. seq .. ")")
	check(seq:find("stepEnd,post", 1, true) ~= nil, "PostSimulation: stepEnd then humanoidPost")
	E.modes:request("pause")
	M.steps(2)
	E.modes:request("idle")
	M.steps(2)
	E.time = real
end
finish()
