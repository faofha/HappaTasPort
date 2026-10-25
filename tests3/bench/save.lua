-- ================================================================================================
-- Save / load bench (tools/savebench3.sh, through tools/trace3.sh with SCENARIO=../bench/save): one
-- synthetic 10-minute run (144,000 frames at 240 FPS: walking, turning, jumps, a key and the mouse every
-- few frames) saved and loaded by each build with its own format. Prints
--   SAVEBENCH|save|<ms>|<bytes>     SAVEBENCH|load|<ms>|<frames>
-- The work runs on a thread the mock steps (both builds yield while saving); the time of those steps,
-- measured first with nothing to do, is taken off.
-- ================================================================================================
check(A.boot(), "boots")
local N = BENCH_FRAMES or 144000

local function r(n, d) return math.floor(n * d + 0.5) / d end
local frames = table.create(N)
local x, z, yaw, vy, y = 0, 0, 0, 0, 3
for i = 1, N do
	local t = i / 240
	if i % 600 < 400 then x, z = x + 0.066 * math.cos(yaw), z + 0.066 * math.sin(yaw) end
	if i % 960 == 0 then yaw = yaw + 1.2 end
	if i % 720 == 100 then vy = 50 end
	if vy ~= 0 or y > 3 then
		y = y + vy / 240
		vy = vy - 196.2 / 240
		if y <= 3 then y, vy = 3, 0 end
	end
	local c, s = math.cos(yaw), math.sin(yaw)
	local f = {
		FrameTime = r(1 / 240, 1e6), TotalTime = r(t, 1e6),
		Cframe = { r(x, 1000), r(y, 1000), r(z, 1000), r(c, 1000), 0, r(s, 1000), 0, 1, 0, r(-s, 1000), 0, r(c, 1000) },
		Velocity = { Linear = { (i % 600 < 400) and r(16 * c, 1000) or 0, r(vy, 1000), (i % 600 < 400) and r(16 * s, 1000) or 0 },
			Angular = { 0, 0, 0 } },
		State = (y > 3) and 5 or 8,
		CamCframe = { r(x - 8 * c, 1000), r(y + 4, 1000), r(z - 8 * s, 1000), r(c, 1000), 0, r(s, 1000), 0, 1, 0, r(-s, 1000), 0, r(c, 1000) },
		Zoom = 12.5, ShiftLock = 0,
		Anim = { Pose = (y > 3) and 3 or ((i % 600 < 400) and 1 or 0), JumpTime = 0, Speed = 1, Anims = {} },
		MX = 960 + (i // 8) % 40, MY = 540,
	}
	if i % 120 == 0 then f.Input = { 26 } elseif i % 120 == 60 then f.Input = { -26 } end
	frames[i] = f
end
A.setFrames(frames)

local function timed(work)
	local done, res
	local t0, t1
	M.resume(coroutine.create(function()
		t0 = M.realClock()
		res = work()
		t1 = M.realClock()
		done = true
	end))
	local steps = 0
	while not done and steps < 100000 do
		M.step(1 / 60)
		steps = steps + 1
	end
	return t1 - t0, steps, res
end

-- what a mock step costs with nothing to do
local s0 = M.realClock()
for _ = 1, 60 do M.step(1 / 60) end
local stepCost = (M.realClock() - s0) / 60

local tSave, stepsSave, bytes = timed(function() return A.saveWork("bench") end)
M.realPrint(string.format("SAVEBENCH|save|%.1f|%d", (tSave - stepsSave * stepCost) * 1000, bytes))
local tLoad, stepsLoad, count = timed(function() return A.loadWork("bench") end)
M.realPrint(string.format("SAVEBENCH|load|%.1f|%d", (tLoad - stepsLoad * stepCost) * 1000, count))
eq(count, N, "loaded every frame")
finish()
