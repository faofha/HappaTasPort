-- Lua time spent per frame by the whole script with the MicroProfiler closed / open (Frame, Detailed, Timers)
check(boot(30), "boots")
local P, S = __T.Profiler, __T.Settings
M.mouse = Vector2.new(960, 900)
local function measure(n)
	local t0 = M.realClock()
	for _ = 1, n do M.step(1 / 60) end
	return (M.realClock() - t0) / n * 1e6
end
measure(60)
local closed = measure(600)
S.Set("Show MicroProfiler", 1)
measure(60)
local frame = measure(600)
P.SetMode("Detailed")
measure(60)
local detailed = measure(600)
P.SetMode("Timers")
measure(60)
local timers = measure(600)
P.SetMode("Hidden")
measure(60)
local hidden = measure(600)
M.realPrint(string.format("PERF us/frame (whole mock frame incl. HappaTAS): closed %.1f  frame %.1f  detailed %.1f  timers %.1f  hidden %.1f",
	closed, frame, detailed, timers, hidden))
check(frame - closed < 400, "profiler adds < 0.4 ms of Lua per frame in Frame mode (mock)")
finish()
