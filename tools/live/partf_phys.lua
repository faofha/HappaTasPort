-- ================================================================================================
--  LIVE PART F, physics (test tool, never shipped): scenarios 1-9 of the final tests, on HappaTAS 3, in
--  game time from its own recording (phys3.lua's runG / metrics). Load with
--      local run = loadfile("HappaTasTest/partf_phys.lua")()
--      run(fps, { 1, 0.5, 0.25, 0.1, 2, 4 }, progress)
--  Each speed's numbers go to HappaTasTest/pf_<fps>_<speed>.json as soon as they are done.
-- ================================================================================================
local HttpService = game:GetService("HttpService")
local P = loadfile("HappaTasTest/phys3.lua")()

local REST = 3
local function r4(v) return type(v) == "number" and math.floor(v * 10000 + 0.5) / 10000 or v end
local function round(t) for k, v in pairs(t) do t[k] = r4(v) end return t end

-- walk-stop: slide after letting go at 0.6 s
-- (from the last frame at full speed: the key release reaches Roblox +-1 step from 0.6 s, the harness's timing)
local function slide(res)
	local fr, x0 = res.frames, nil
	for _, f in ipairs(fr) do
		if f[1] >= 0.5 and x0 == nil and f[5] < 15.99 then x0 = f[2] end
	end
	return x0 and (fr[#fr][2] - x0) or nil
end
-- 180-degree turn: from 0.3 s (W -> S) until the root faces -X within 5 degrees
local function turnTime(res)
	for _, f in ipairs(res.frames) do
		if f[1] >= 0.3 and f[10] <= -0.9962 then return f[1] - 0.3 end
	end
	return nil
end
local function landingRow(m)
	return round({ sink = m.sink, settle = m.settle, vy = m.vyContact, pullH = m.pullH, pullAcc = m.pullAcc, states = m.states, apex = m.apex, air = m.air })
end

local function physSet(s, progress)
	local out = { speed = s }
	local full = s <= 1
	P.speed(s, true)
	if full then
		out.walkstop = r4(slide(P.runG("walkstop")))
		local j = P.metrics(P.runG("jumpStand"), REST)
		out.jump = landingRow(j)
		out.coyote = {}
		for _, k in ipairs({ 0.05, 0.10, 0.12, 0.14 }) do
			out.coyote[tostring(k)] = P.metrics(P.runG("coyote", { k = k }), REST).jumped
		end
		out.turn = r4(turnTime(P.runG("turn")))
		local pa = P.metrics(P.runG("jumpStand", { pauseAt = 0.35, pauseSecs = 1, pauseDefer = true }), REST)
		out.pauseAir = landingRow(pa)
		progress("basics " .. s)
	end
	-- extra velocity: A/D switch x10, spins x20 (the same random timings at every speed)
	local function ev(name, n, seed)
		local rows, extra = {}, 0
		for i = 1, n do
			local r1, r2 = ((i * 37 + seed) % 100) / 100, ((i * 61 + seed * 3) % 100) / 100
			local nm = name
			if name == "spin" then nm = ({ "spinW", "spinS", "spinAll" })[(i - 1) % 3 + 1] end
			local m = P.metrics(P.runG(nm, { r1 = r1, r2 = r2 }), REST)
			local bad = (m.maxH or 0) > 16.02 or (m.apex or 0) > 7.29 or not m.jumped
			if bad then extra = extra + 1 end
			rows[i] = string.format("%s maxH %.3f apex %.3f dist %.2f%s", nm, m.maxH or -1, m.apex or -1, m.dist or -1, m.jumped and "" or " NOJUMP")
		end
		return { extra = extra, runs = n, rows = rows }
	end
	out.switch = ev("switch", 10, 7)
	progress("switch " .. s)
	out.spin = ev("spin", 20, 11)
	progress("spin " .. s)
	-- landing and close to the ground
	out.land = {}
	for _, nm in ipairs({ "jumpWalk", "dropMedWalk", "dropTallWalk", "dropMedStand", "dropTallStand", "hop" }) do
		out.land[nm] = landingRow(P.metrics(P.runG(nm), REST))
	end
	if not full then out.land.jumpStand = landingRow(P.metrics(P.runG("jumpStand"), REST)) end
	progress("landing " .. s)
	return out
end

return function(fps, speeds, progress)
	progress = progress or function() end
	setfpscap(fps)
	P.use("h3", "HappaTasTest/h3.lua")
	task.wait(1)
	local done = {}
	local ok, err = pcall(function()
		for _, s in ipairs(speeds) do
			local t0 = os.clock()
			local res = physSet(s, progress)
			res.fps = fps
			res.measuredFps = r4(P.fps(1).fps)
			res.realSecs = r4(os.clock() - t0)
			writefile(string.format("HappaTasTest/pf_%d_%s.json", fps, tostring(s)), HttpService:JSONEncode(res))
			done[#done + 1] = s
		end
	end)
	pcall(P.speed, 1, false)
	P.done()
	return { done = done, err = not ok and tostring(err) or nil }
end
