-- Per-frame cost of HappaTAS in every mode (headless mock).
--   us   = Lua time per frame of the whole mock frame (HappaTAS + mock overhead)
--   rd   = Instance reads / method lookups per frame (each one is a Lua <-> C++ bridge crossing in Roblox)
--   wr   = Instance property writes per frame
-- Run against two builds to compare:  bash tools/build_test.sh bench <script>; luau tests/run_bench.lua
check(boot(30), "boots")
local S, Core, CO = __T.Settings, __T.Core, __T.ClientObjects
local C = Core.State
local guard = 0
while not (C.HRP and C.Humanoid) and guard < 200 do M.step(1 / 60); guard = guard + 1 end
check(C.HRP ~= nil, "character loaded")
local hrp = C.HRP

local rows = {}
local function topCounts(log, n, frames)
	local cnt = {}
	for _, k in ipairs(log) do cnt[k] = (cnt[k] or 0) + 1 end
	local list = {}
	for k, v in pairs(cnt) do list[#list + 1] = { k, v } end
	table.sort(list, function(a, b) return a[2] > b[2] end)
	local out = {}
	for i = 1, math.min(n, #list) do out[#out + 1] = string.format("%s %.1f", list[i][1], list[i][2] / frames) end
	return table.concat(out, ", ")
end
local function measure(name, n, perFrame)
	for _ = 1, 30 do if perFrame then perFrame() end; M.step(1 / 60) end -- warm up
	if BENCH_PROFILE then -- which reads / writes (per frame) - set with PRE='BENCH_PROFILE = true'
		M.readLog, M.writeLog = {}, {}
		for _ = 1, 60 do if perFrame then perFrame() end; M.step(1 / 60) end
		local wl = {}
		for _, w in ipairs(M.writeLog) do wl[#wl + 1] = rawget(w[1], "_d").class.Name .. "." .. tostring(w[2]) end
		M.realPrint("READS  " .. name .. ": " .. topCounts(M.readLog, 14, 60))
		M.realPrint("WRITES " .. name .. ": " .. topCounts(wl, 8, 60))
		M.readLog, M.writeLog = nil, nil
	end
	local r0, w0 = M.propReads, M.propWrites
	local t0 = M.realClock()
	for _ = 1, n do
		if perFrame then perFrame() end
		M.step(1 / 60)
	end
	local us = (M.realClock() - t0) / n * 1e6
	local rd, wr = (M.propReads - r0) / n, (M.propWrites - w0) / n
	rows[#rows + 1] = { name, us, rd, wr }
	M.realPrint(string.format("BENCH %-22s %8.1f us %8.1f rd %8.1f wr", name, us, rd, wr))
end
local function pressedClick()
	local inp = M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin)
	M.services.UserInputService.InputBegan:Fire(inp, false)
end

-- ------------------------------------------------------------------ plain modes
measure("idle (stats)", 600)
hrp.AssemblyLinearVelocity = Vector3.new(16, 0, 0)
measure("idle moving", 600)
hrp.AssemblyLinearVelocity = Vector3.zero

M.pressKey(Enum.KeyCode.Two); M.releaseKey(Enum.KeyCode.Two)
M.steps(5)
pressedClick()
M.steps(3)
check(Core.GetMode() == 2 and not Core.IsPaused(), "recording")
hrp.AssemblyLinearVelocity = Vector3.new(16, 0, 0)
M.pressKey(Enum.KeyCode.W)
local mx = 900
measure("create recording", 600, function()
	mx = mx + 1
	M.moveMouse(mx, 500)
end)
M.releaseKey(Enum.KeyCode.W)
pressedClick()
M.steps(3)
hrp.AssemblyLinearVelocity = Vector3.zero
check(Core.IsPaused(), "paused")
measure("create paused", 300)

hrp.AssemblyLinearVelocity = Vector3.zero
M.pressKey(Enum.KeyCode.Three); M.releaseKey(Enum.KeyCode.Three)
M.steps(2)
check(Core.GetMode() == 3, "testing")
measure("test playback", 500)
local g2 = 0
while Core.GetMode() == 3 and g2 < 400 do M.step(1 / 60); g2 = g2 + 1 end
M.pressKey(Enum.KeyCode.One); M.releaseKey(Enum.KeyCode.One)
M.steps(5)

-- ------------------------------------------------------------------ client objects
local folder = Instance.new("Folder")
folder.Name = "ClientObjects"
folder.Parent = workspace
local movers, phys = {}, {}
local N = 400
for i = 1, N do
	local p = Instance.new("Part")
	p.Name = "Part"
	p.Size = Vector3.new(4, 1, 4)
	local kind = i % 10
	local x, z = (i % 20) * 5 - 50, -10 - math.floor(i / 20) * 4
	if kind == 9 then x = x + 2000 end -- far away: never active
	p.CFrame = CFrame.new(x, 2, z)
	p.Anchored = kind ~= 7
	p.Parent = folder
	if kind == 5 or kind == 6 then movers[#movers + 1] = { p, x, z, i } end
	if kind == 7 then phys[#phys + 1] = p end
end
local tMove = 0
local moveConn = M.services.RunService.Heartbeat:Connect(function(dt)
	tMove = tMove + dt
	for _, m in ipairs(movers) do
		local p, x, z, i = m[1], m[2], m[3], m[4]
		if i % 2 == 0 then
			p.CFrame = CFrame.new(x + math.sin(tMove * 2 + i) * 3, 2, z)
		else
			p.CFrame = CFrame.new(x, 2, z) * CFrame.Angles(0, tMove * 3, 0)
		end
	end
	for _, p in ipairs(phys) do
		p.AssemblyLinearVelocity = Vector3.new(0, -2, 0)
		p.CFrame = p.CFrame + Vector3.new(0, -2 * dt, 0)
	end
end)
hrp.CFrame = CFrame.new(0, 3, 0)
hrp.AssemblyLinearVelocity = Vector3.zero
measure("world movers only", 300) -- the test's own movers (subtract from the CO rows)
S.Set("Sync Client Objects", 1)
local g3 = 0
while not CO.IsReady() and g3 < 600 do M.step(1 / 60); g3 = g3 + 1 end
check(CO.IsReady(), "client objects scanned")
local nReg = CO.Counts()
M.realPrint("client objects registered: " .. tostring(nReg))
measure("idle + CO enabled", 300)

Core.SetTAS({})
M.pressKey(Enum.KeyCode.Two); M.releaseKey(Enum.KeyCode.Two)
M.steps(5)
pressedClick()
M.steps(3)
hrp.AssemblyLinearVelocity = Vector3.new(4, 0, 0)
measure("CO recording", 600)
pressedClick()
M.steps(3)
hrp.AssemblyLinearVelocity = Vector3.zero
measure("CO paused", 300)
M.pressKey(Enum.KeyCode.Three); M.releaseKey(Enum.KeyCode.Three)
M.steps(2)
check(Core.GetMode() == 3, "CO testing")
measure("CO playback", 500)
local g4 = 0
while Core.GetMode() == 3 and g4 < 600 do M.step(1 / 60); g4 = g4 + 1 end
moveConn:Disconnect()
S.Set("Sync Client Objects", 0)
M.steps(5)

-- ------------------------------------------------------------------ profiler
S.Set("Show MicroProfiler", 1)
measure("idle + profiler", 600)
S.Set("Show MicroProfiler", 0)

local tus, trd, twr = 0, 0, 0
for _, r in ipairs(rows) do tus, trd, twr = tus + r[2], trd + r[3], twr + r[4] end
M.realPrint(string.format("BENCH %-22s %8.1f us %8.1f rd %8.1f wr", "SUM", tus, trd, twr))
finish()
