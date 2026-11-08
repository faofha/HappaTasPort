-- ================================================================================================
--  SPEED LOG RUN (TEMPORARY DIAGNOSTIC TOOL, never shipped): drives the character for the speed log
--  (tools/live/speedlog.lua) through phys3.lua's harness (Humanoid:Move / Jump with the ControlModule off, no
--  window focus needed), recording in Create mode at each speed. Each press is marked with SpeedLog.Press, the
--  same way the logger marks a key press.
--      local run = loadfile("HappaTasTest/speedlog_run.lua")()
--      run.platform("HEAD", 144, { {1,false}, {0.1,true}, ... }, { jumps = 10, moves = 4, drops = 3 }, progress)
--      run.conveyor("HEAD", 144, { {1,false}, {0.25,true}, ... }, { walks = 4, jumps = 3 }, progress)
--  Each call loads the build, logs to HappaTasPort/SpeedLog/speedlog_<build>_<fps>[_conveyor]_<time>.txt,
--  unloads it and puts the controls back.
-- ================================================================================================
local RS = game:GetService("RunService")
local ST = Enum.HumanoidStateType
local AIR = Enum.Material.Air
local R = {}

local function setup(build, fps, suffix)
	local P = loadfile("HappaTasTest/phys3.lua")()
	setfpscap(fps)
	P.use("h3", "HappaTasTest/h3_" .. build .. ".lua")
	local E = getgenv().__HappaTAS3_T.engine
	assert(loadfile("HappaTasTest/speedlog.lua"))(build .. "_" .. fps .. (suffix or ""))
	return P, E, getgenv().SpeedLog
end
local function setSpeed(E, s, on)
	E.settings:set("speedHackFrameStep", 0) -- (a026bb8 only: its default, the scaled slow motion)
	E.settings:set("speedHackSpeed", s)
	E.settings:set("speedHack", on and 1 or 0)
end
local function waitUntil(f, secs)
	local t0 = os.clock()
	repeat task.wait() until f() or os.clock() - t0 > secs
	return f()
end
local function grounded(E)
	local h, r = E.char.hum, E.char.hrp
	local st = h:GetState()
	return h.FloorMaterial ~= AIR and (st == ST.Running or st == ST.RunningNoPhysics) and r.AssemblyLinearVelocity.Magnitude < 0.2
end
local function startRun(P, E, at, surf)
	E.modes:request("idle"); task.wait(0.3); E.modes:setRun({}); task.wait(0.2)
	P.placeAtV(at, surf)
	E.modes:create(true); task.wait(0.4)
	E.modes:unpause(); task.wait(0.3)
end
local function stopRun(P, E)
	P.setDrive(Vector3.zero, false)
	E.modes:pause(); task.wait(0.2); E.modes:request("idle"); task.wait(0.2)
end
local function finish(P, SL)
	local path = SL.Save()
	SL.Stop()
	P.done()
	setfpscap(240)
	return path
end

function R.platform(build, fps, speeds, opts, progress)
	progress = progress or function() end
	local P, E, SL = setup(build, fps)
	local ok, err = pcall(function()
		for _, sp in ipairs(speeds) do
			local s, on = sp[1], sp[2]
			local k = math.max(0.1, (on and s or 1))
			setSpeed(E, s, on)
			SL.Mark(string.format("platform: speed %s, hack %s", tostring(s), tostring(on)))
			-- jumps from standing (each one lands too)
			startRun(P, E, Vector3.new(0, 0, 0), P.SURF.plat)
			for _ = 1, opts.jumps or 10 do
				waitUntil(function() return grounded(E) end, 2 / k + 1)
				task.wait(0.15 / k)
				SL.Press("jump")
				P.setDrive(Vector3.zero, true)
				task.wait(0.1) -- (a 0.1 s key press, real time)
				P.setDrive(Vector3.zero, false)
				waitUntil(function() return E.char.hum.FloorMaterial == AIR end, 1 / k + 0.5)
				waitUntil(function() return grounded(E) end, 2.5 / k + 1)
			end
			-- from standing, a direction pressed for 0.4 s of game time (to +X, then -X)
			for i = 1, opts.moves or 4 do
				waitUntil(function() return grounded(E) end, 2 / k + 1)
				task.wait(0.15 / k)
				SL.Press("move")
				P.setDrive(Vector3.new((i % 2 == 1) and 1 or -1, 0, 0), false)
				task.wait(0.4 / k)
				P.setDrive(Vector3.zero, false)
			end
			waitUntil(function() return grounded(E) end, 2 / k + 1)
			stopRun(P, E)
			-- drops: walking off the platform onto the step 5 studs below
			for _ = 1, opts.drops or 3 do
				startRun(P, E, Vector3.new(24, 0, 0), P.SURF.plat)
				P.setDrive(Vector3.new(1, 0, 0), false)
				waitUntil(function() return E.char.hrp.Position.X > 30.5 end, 2 / k + 1)
				task.wait(0.05 / k)
				P.setDrive(Vector3.zero, false)
				waitUntil(function() return E.char.hum.FloorMaterial ~= AIR and E.char.hrp.Position.Y < P.SURF.plat end, 3 / k + 1)
				waitUntil(function() return grounded(E) end, 2 / k + 1)
				task.wait(0.2 / k)
				stopRun(P, E)
			end
			progress(string.format("%s %d platform %s%s", build, fps, tostring(s), on and "" or " off"))
		end
	end)
	pcall(stopRun, P, E)
	local path = finish(P, SL)
	return { path = path, err = not ok and tostring(err) or nil }
end

-- the test place's conveyor (anchored, belt velocity 0, 0, 10, 11 studs long): walking against the belt from its
-- far end, and standing jumps on it
function R.conveyor(build, fps, speeds, opts, progress)
	progress = progress or function() end
	local P, E, SL = setup(build, fps, "_conveyor")
	local cv = workspace.ClientParts.Conveyor
	local top = cv.Position.Y + cv.Size.Y / 2
	local ok, err = pcall(function()
		for _, sp in ipairs(speeds) do
			local s, on = sp[1], sp[2]
			local k = math.max(0.1, (on and s or 1))
			setSpeed(E, s, on)
			SL.Mark(string.format("conveyor: speed %s, hack %s", tostring(s), tostring(on)))
			for _ = 1, opts.walks or 4 do
				-- (from the far end, facing -Z: walking against the belt, 16 - 10 = 6 studs/s over the ground)
				E.modes:request("idle"); task.wait(0.3); E.modes:setRun({}); task.wait(0.2)
				local hrp = E.char.hrp
				hrp.CFrame = CFrame.lookAt(Vector3.new(cv.Position.X, top + 3, cv.Position.Z + 4.5), Vector3.new(cv.Position.X, top + 3, cv.Position.Z - 10))
				hrp.AssemblyLinearVelocity = Vector3.zero
				task.wait(0.5)
				E.modes:create(true); task.wait(0.3)
				E.modes:unpause()
				SL.Press("move")
				P.setDrive(Vector3.new(0, 0, -1), false)
				task.wait(1.4 / k)
				P.setDrive(Vector3.zero, false)
				stopRun(P, E)
			end
			for _ = 1, opts.jumps or 3 do
				E.modes:request("idle"); task.wait(0.3); E.modes:setRun({}); task.wait(0.2)
				local hrp = E.char.hrp
				hrp.CFrame = CFrame.new(cv.Position.X, top + 3, cv.Position.Z - 4.5)
				hrp.AssemblyLinearVelocity = Vector3.zero
				task.wait(0.4)
				E.modes:create(true); task.wait(0.3)
				E.modes:unpause()
				task.wait(0.1 / k)
				SL.Press("jump")
				P.setDrive(Vector3.zero, true)
				task.wait(0.1)
				P.setDrive(Vector3.zero, false)
				task.wait(0.8 / k)
				stopRun(P, E)
			end
			progress(string.format("%s %d conveyor %s%s", build, fps, tostring(s), on and "" or " off"))
		end
	end)
	pcall(stopRun, P, E)
	local path = finish(P, SL)
	return { path = path, err = not ok and tostring(err) or nil }
end

return R
