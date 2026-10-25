-- ================================================================================================
-- HappaTAS 3, phase 1: start, re-run over an older copy, Unload (nothing left behind)
-- ================================================================================================
local RS = M.services.RunService
VARIANT = VARIANT or "plain" -- (tests3/main.variants: "nofiles" runs the suite on an executor without writefile)
local genv = getgenv()
local function counts() return { RS.PreRender:Count(), RS.PreSimulation:Count(), RS.PostSimulation:Count() } end
local function lateBound()
	for _, b in ipairs(M.binds) do if b.name == "HappaTAS3Late" then return true end end
	return false
end
local before = counts()

-- an older HappaTAS (V2.38.x) is still running
local oldUnloaded = false
genv.__HappaTAS = { Version = "V2.38.16", Unload = function() oldUnloaded = true end }

section("start")
check(boot(3), "boots")
check(oldUnloaded, "the older V2 copy was unloaded")
local h = genv.__HappaTAS3
check(type(h) == "table" and h.Version == "3.0.0-dev", "handle published with the version")
local T = genv.__HappaTAS3_T
check(type(T) == "table" and T.pipe ~= nil and T.state ~= nil, "debug tables published (test builds have Debug on)")
eq(T.state:get("mode"), "Idle", "initial mode Idle")
local ticks = 0
T.pipe:add("PreRender", 50, "ticker", function() ticks = ticks + 1 end)
M.steps(3)
eq(ticks, 3, "a pipeline handler runs once a frame")
eq(RS.PreRender:Count(), before[1] + 1, "exactly one PreRender connection")

section("running the script again unloads the first copy")
-- (the second copy starts with saved settings: Settings3.json read before any plugin)
M.fs["HappaTasPort/Settings3.json"] = '{"format":"HappaTAS3 settings","version":1,"settings":{"playbackSpeed":2.5},"controls":{"pause":"E"}}'
M.resume(coroutine.create(function() __SCRIPT__() end))
M.steps(2)
local ticksAfter = ticks
M.steps(3)
eq(ticks, ticksAfter, "the first copy's handlers stopped")
eq(RS.PreRender:Count(), before[1] + 1, "still exactly one PreRender connection")
local h2, T2 = genv.__HappaTAS3, genv.__HappaTAS3_T
check(h2 ~= h and T2 ~= T, "the new copy published its own handle")

section("saves through the handle [" .. VARIANT .. "]")
do
	local E = T2.engine
	local guard = 0
	while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
	check(E.files ~= nil and E.library ~= nil and E.persist ~= nil and E.settingsFile ~= nil, "persistence wired")
	eq(E.settings:get("playbackSpeed"), 2.5, "saved settings loaded at start")
	eq(E.controls:get("pause"), "E", "saved keys loaded at start")
	check(E.tl.cols.v2CO ~= nil and E.tl.cols.v2KE ~= nil, "carry columns registered")
	local function waitIdle()
		local g = 0
		while E.busy and g < 2000 do M.step(1 / 60); g = g + 1 end
	end
	E.modes:request("create")
	M.steps(2)
	E.modes:request("unpause")
	for _ = 1, 121 do
		E.char.hrp.AssemblyLinearVelocity = Vector3.new(8, 0, 0)
		M.step(1 / 60)
	end
	E.modes:request("pause")
	M.steps(2)
	local n = E.tl:count()
	check(n >= 120, "recorded " .. n .. " frames")
	local lastCf = E.tl:getArray("Cframe", n)
	if VARIANT == "nofiles" then
		for _, call in ipairs({ { "Save", "a" }, { "SaveAttempt", "a" }, { "Load", "a.tas" }, { "List" } }) do
			local ok, msg = h2[call[1]](call[2])
			eq(ok, false, call[1] .. " refused")
			eq(msg, "Saving is unavailable on this executor", call[1] .. ": the message")
		end
	else
		local ok, msg = h2.Save("a")
		check(ok, "Save started (" .. tostring(msg) .. ")")
		waitIdle()
		check((h2.SaveAttempt("a")), "SaveAttempt started")
		waitIdle()
		local list = h2.List()
		local a
		for _, e in ipairs(list) do if e.path == "a.tas" then a = e end end
		check(a and a.name == "a" and a.frames == n and a.length > 0 and a.saved ~= nil, "List shows a with " .. n .. " frames")
		local a2
		for _, e in ipairs(list) do if e.path == "a (2).tas" then a2 = e end end
		check(a2 ~= nil, "List shows the attempt a (2)")
		E.modes:request("idle")
		M.steps(2)
		E.modes:request("deleteTas")
		M.steps(2)
		E.modes:request("deleteTas")
		M.steps(2)
		eq(E.tl:count(), 0, "run deleted")
		check((h2.Load("a.tas")), "Load started")
		waitIdle()
		eq(E.tl:count(), n, "loaded every frame")
		local cf = E.tl:getArray("Cframe", n)
		check(cf[1] == lastCf[1] and cf[2] == lastCf[2] and cf[3] == lastCf[3], "the same last frame")
		E.modes:request("test")
		local g, p = 0, nil
		while E.mode == 3 and g < 400 and not p do
			M.step(1 / 60)
			g = g + 1
			if E.frame >= n then p = E.char.hrp.Position end
		end
		check(p ~= nil, "Test reached the last frame")
		-- (the step that reaches the last frame also runs that frame's physics: one frame of travel at 8 studs/s)
		if p then
			near(p.X, lastCf[1], 8 / 60 + 0.01, "on the last frame: root X")
			near(p.Z, lastCf[3], 0.01, "on the last frame: root Z")
		end
		E.modes:request("idle")
		M.steps(2)
	end
	-- a settings change right before Unload (the next section) is still saved
	E.settings:set("playbackSpeed", 1.75)
end

section("Unload from inside a frame handler")
local afterUnload = 0
T2.pipe:add("PreRender", 1, "unloader", function() h2.Unload() end)
T2.pipe:add("PreRender", 2, "after", function() afterUnload = afterUnload + 1 end)
M.step(1 / 60)
eq(afterUnload, 0, "the rest of that frame is skipped")
local c = counts()
eq(c[1], before[1], "PreRender connections back to before")
eq(c[2], before[2], "PreSimulation connections back to before")
eq(c[3], before[3], "PostSimulation connections back to before")
check(not lateBound(), "no late render-step bind")
eq(genv.__HappaTAS3, nil, "handle removed")
eq(genv.__HappaTAS3_T, nil, "debug tables removed")
local ok = pcall(h2.Unload)
check(ok, "Unload twice is fine")
if VARIANT ~= "nofiles" then
	local raw = M.fs["HappaTasPort/Settings3.json"]
	check(raw ~= nil and raw:find('"playbackSpeed":1.75', 1, true) ~= nil, "Unload saved the waiting settings change")
end
M.steps(3)
eq(afterUnload, 0, "nothing runs after Unload")

section("a Start that fails halfway leaves nothing behind")
local Pipeline = __T3("kernel/pipeline")
local realStart = Pipeline.start
Pipeline.start = function(self)
	self.life:connect(RS.PreRender, function() end) -- (got this far, then broke)
	error("start broke")
end
local okStart = pcall(__T3("main").Start)
Pipeline.start = realStart
check(okStart, "Start doesn't throw")
eq(RS.PreRender:Count(), before[1], "the connection made before the failure is gone")
eq(genv.__HappaTAS3, nil, "no handle left behind")
local reported, kept = false, {}
for _, l in ipairs(M.logs) do
	if l:find("start failed", 1, true) then reported = true else kept[#kept + 1] = l end
end
check(reported, "the failure is reported")
M.logs = kept
finish()
