-- ================================================================================================
-- Bench: per-frame cost in each mode, the same session on V2.38.16 and on HappaTAS 3 (through the trace
-- adapters; tools/bench3.sh runs and compares them). V2's stats panels, client objects and MicroProfiler
-- are off: phase 2 of HappaTAS 3 has none of them yet.
--   us = Lua time per frame of the whole mock frame (HappaTAS + mock), rd / wr = Instance reads / writes
-- ================================================================================================
check(A.boot(), "boots")
for _, name in ipairs({ "Show Stats (Idle)", "Show Stats (Create)", "Show Stats (Test)", "Sync Client Objects", "Show MicroProfiler" }) do
	A.setSetting(name, 0)
end
M.steps(30)
local hrp = A.char()
local function measure(name, n, perFrame)
	for _ = 1, 30 do if perFrame then perFrame() end; M.step(1 / 60) end -- warm up
	local best = math.huge
	local rd, wr
	for _ = 1, 5 do -- (the fastest of 5 runs: less noise from the machine)
		local r0, w0 = M.propReads, M.propWrites
		local t0 = M.realClock()
		for _ = 1, n do
			if perFrame then perFrame() end
			M.step(1 / 60)
		end
		local us = (M.realClock() - t0) / n * 1e6
		if us < best then best = us end
		rd, wr = (M.propReads - r0) / n, (M.propWrites - w0) / n
	end
	M.realPrint(string.format("BENCH|%s|%.1f|%.1f|%.1f", name, best, rd, wr))
end
local function click()
	M.services.UserInputService.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
end
local function key(kc) M.pressKey(kc); M.releaseKey(kc) end

measure("idle", 1000)
hrp.AssemblyLinearVelocity = Vector3.new(16, 0, 0)
measure("idle moving", 1000)
hrp.AssemblyLinearVelocity = Vector3.zero
key(Enum.KeyCode.Two)
M.steps(5)
click()
M.steps(3)
hrp.AssemblyLinearVelocity = Vector3.new(16, 0, 0)
M.pressKey(Enum.KeyCode.W)
local mx = 900
measure("create recording", 300, function()
	mx = mx + 1
	M.moveMouse(mx, 500)
end)
M.releaseKey(Enum.KeyCode.W)
click()
M.steps(3)
hrp.AssemblyLinearVelocity = Vector3.zero
measure("create paused", 300)
key(Enum.KeyCode.Three)
M.steps(2)
measure("test playback", 250)
local g = 0
while A.mode() == 3 and g < 2000 do M.step(1 / 60); g = g + 1 end
finish()
