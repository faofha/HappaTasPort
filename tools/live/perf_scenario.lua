-- HappaTAS per-frame cost in every mode, measured in the live client (development only).
-- The build must be a profiling build: bash tools/live_build.sh, then
--     python3 tools/prof_patch.py build/HappaTAS_live.lua build/HappaTAS_prof.lua
-- Copy it, harness.lua and this file to <executor workspace>/HappaTasTest/, then (from a background job):
--     return loadfile("HappaTasTest/perf_scenario.lua")()("HappaTasTest/HappaTAS_prof.lua")
-- It uses the controls Create 2, Test 3, Pause / Unpause E and the EToH kit test place's layout.
return function(buildPath)
	local fn, err = loadfile(buildPath, "=HappaTAS")
	if not fn then return "compile: " .. tostring(err) end
	fn()
	task.wait(2)
	local H = loadfile("HappaTasTest/harness.lua")()
	local C, T = H.C, H.T
	local P = T.Profiler
	local RS = game:GetService("RunService")
	local HP = rawget(getgenv(), "__HPROF")
	T.Settings.Set("Show MicroProfiler", 1)
	T.Profiler.SetMode("Hidden")
	local function reset() for k in pairs(HP) do HP[k] = nil end end
	local function measure(secs, cond)
		reset()
		local hap, prof, n = 0, 0, 0
		local t0 = os.clock()
		while os.clock() - t0 < secs and (not cond or cond()) do
			RS.Heartbeat:Wait()
			local a, b = P.TimerStats("HappaTAS"), P.TimerStats("Profiler")
			if a and b then hap = hap + a.time; prof = prof + b.time; n = n + 1 end
		end
		local frames = math.max(HP.frames, 1)
		local keys = {}
		for k in pairs(HP) do if k ~= "frames" then keys[#keys + 1] = k end end
		table.sort(keys, function(x, y) return HP[x] > HP[y] end)
		local secsOut = {}
		for _, k in ipairs(keys) do
			local v = HP[k] * 1000 / frames
			if v >= 0.001 then secsOut[#secsOut + 1] = string.format("%s %.3f", k, v) end
		end
		return string.format("HappaTAS %.3f ms  Profiler %.3f ms  (%d frames) | %s", hap / math.max(n, 1), prof / math.max(n, 1), n, table.concat(secsOut, ", "))
	end
	local r = {}
	H.reset()
	C.Humanoid:UnequipTools()
	C.HRP.CFrame = CFrame.lookAt(Vector3.new(20, 4, 106), Vector3.new(20, 4, 125))
	H.frames(30)
	workspace.CurrentCamera.CFrame = CFrame.lookAt(Vector3.new(20, 14, 92), Vector3.new(20, 1, 122))
	H.frames(10)
	r.idle = measure(3)
	H.tap("2"); H.frames(10)
	r.paused = measure(3)
	H.tap("E"); H.frames(5)
	H.down("D")
	r.recording = measure(2)
	H.up("D"); H.down("A")
	task.wait(1)
	H.up("A")
	H.tap("E"); H.frames(10)
	r.frames = #C.data
	H.tap("3"); H.frames(3)
	r.playback = measure(15, function() return C.mode == 3 end)
	H.frames(10)
	H.done()
	return r
end
