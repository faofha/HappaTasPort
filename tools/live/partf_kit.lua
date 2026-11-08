-- ================================================================================================
--  LIVE PART F, kit objects (test tool, never shipped): scenarios 10-12 in the EToH kit test place.
--  Vanisher (ClientParts.VanisherGroup.Vanisher): one recording per speed (touch, full fade, vanished), then
--  rewinds with the timeline (seek), hold Back and tap, to mid-fade and to after the full fade: Transparency /
--  CanCollide two frames later against what was recorded at that frame; then Test: the largest change of
--  Transparency between two rendered frames, against the recorded fade's own largest change per game step.
--  X pusher (ClientParts."Pushing Platform"): walking into it, the slider's position at game times 0.1 .. 0.6.
--  Load with  local run = loadfile("HappaTasTest/partf_kit.lua")(); run(speeds, progress)
--  Results: HappaTasTest/pfk.json
-- ================================================================================================
local HttpService = game:GetService("HttpService")
local RS = game:GetService("RunService")
local P = loadfile("HappaTasTest/phys3.lua")()

return function(speeds, progress, pushRepeats)
	progress = progress or function() end
	P.use("h3", "HappaTasTest/h3.lua")
	task.wait(1)
	local E = getgenv().__HappaTAS3_T.engine
	local tl = E.tl
	local lp = game.Players.LocalPlayer
	local v = workspace.ClientParts.VanisherGroup.Vanisher
	local function TT(f) if f < 1 or f > tl:count() then return 0 end return tl:get("TotalTime", f, 1) end
	local log
	local conn = RS.RenderStepped:Connect(function()
		if log then log[#log + 1] = { E.mode, E.paused, E.frame, TT(E.frame), v.Transparency, v.CanCollide } end
	end)
	local out = {}

	local function vanisher(s)
		local res = {}
		P.speed(s, true)
		E.modes:request("idle"); task.wait(0.3); E.modes:setRun({}); task.wait(0.2)
		local hrp = lp.Character.HumanoidRootPart
		hrp.CFrame = CFrame.new(-25, 6, 122); task.wait(3.2)
		E.modes:create(true); task.wait(0.3)
		hrp.CFrame = CFrame.new(-31, 9, 121); task.wait(0.2)
		log = {}
		E.modes:unpause()
		local t0 = os.clock()
		repeat task.wait() until TT(tl:count()) >= 1.7 or os.clock() - t0 > 90
		E.modes:pause(); task.wait(0.2)
		-- what was recorded: per frame (game time), the part's values while recording
		local truth = {}
		for _, e in ipairs(log) do if e[1] == 2 and not e[2] then truth[e[3]] = { e[4], e[5], e[6] } end end
		local tTouch, tGone
		for f = 1, tl:count() do
			local r = truth[f]
			if r then
				if not tTouch and r[2] > 0.001 then tTouch = r[1] end
				if not tGone and r[2] >= 0.999 and not r[3] then tGone = r[1] end
			end
		end
		res.recorded = string.format("touch %.3f gone %s", tTouch or -1, tostring(tGone))
		-- the fade's largest change per recorded frame
		local maxRec, prevT = 0, nil
		for f = 1, tl:count() do
			local r = truth[f]
			if r then
				if prevT and r[1] <= (tGone or 1) then maxRec = math.max(maxRec, math.abs(r[2] - prevT)) end
				prevT = r[2]
			end
		end
		res.recMaxStep = maxRec
		local function frameAt(t) local b for f = 1, tl:count() do if TT(f) <= t + 1e-6 then b = f end end return b end
		local targets = { mid = (tTouch or 0) + 0.4, gone = (tGone or 1) + 0.2 }
		local rows = {}
		for _, method in ipairs({ "seek", "hold", "tap" }) do
			for name, tWant in pairs(targets) do
				E.modes:seek(tl:count()); task.wait(0.2)
				if method == "seek" then
					E.modes:seek(frameAt(tWant))
				elseif method == "hold" then
					E.modes:back()
					local g = os.clock()
					repeat task.wait() until TT(E.frame) <= tWant or os.clock() - g > 40
					E.modes:release("back")
				else
					local g = 0
					while TT(E.frame) > tWant and g < 4000 do E.modes:back1(); task.wait(); g = g + 1 end
				end
				-- two rendered frames later: the shown values against the recorded ones at that frame
				task.wait(); task.wait()
				local f = E.frame
				local r = truth[f]
				rows[#rows + 1] = string.format("%s %s t%.3f shown T%.3f cc %s | recorded T%.3f cc %s", method, name, TT(f), v.Transparency,
					tostring(v.CanCollide), r and r[2] or -1, r and tostring(r[3]) or "?")
			end
		end
		res.rewinds = rows
		-- Test: smooth?
		log = {}
		E.modes:request("test")
		t0 = os.clock()
		repeat task.wait() until E.mode ~= 3 or os.clock() - t0 > 90
		local worstOff, biggest, prev = 0, 0, nil
		for _, e in ipairs(log) do
			if e[1] == 3 and e[4] <= (tGone or 1) + 0.05 then
				local r = truth[e[3]]
				if r then worstOff = math.max(worstOff, math.abs(r[2] - e[5])) end
				if prev then biggest = math.max(biggest, math.abs(e[5] - prev)) end
				prev = e[5]
			end
		end
		res.test = string.format("worst T off the recording %.3f, biggest change per rendered frame %.3f (recorded per frame %.3f)", worstOff, biggest, maxRec)
		E.modes:request("idle")
		return res
	end

	local pp = workspace.ClientParts["Pushing Platform"]
	local pr = pp.Primary.PrismaticConstraint
	local function pusher(s)
		P.speed(s, true)
		E.modes:request("idle"); task.wait(0.3); E.modes:setRun({}); task.wait(0.2)
		local hrp = lp.Character.HumanoidRootPart
		hrp.CFrame = CFrame.lookAt(Vector3.new(10.5, 4.6, 121.6), Vector3.new(10.5, 4.6, 130))
		hrp.AssemblyLinearVelocity = Vector3.zero
		task.wait(1.5)
		E.modes:create(true); task.wait(0.3)
		local samples = {}
		local c = RS.RenderStepped:Connect(function()
			local n = tl:count()
			if n < 1 or E.paused then return end
			samples[#samples + 1] = { TT(n), pr.CurrentPosition }
		end)
		P.setDrive(Vector3.new(0, 0, 1), false)
		E.modes:unpause()
		local t0 = os.clock()
		repeat task.wait() until TT(tl:count()) >= 0.8 or os.clock() - t0 > 60
		E.modes:pause()
		P.setDrive(Vector3.zero, false)
		c:Disconnect()
		task.wait(0.2)
		local function at(t) local b for _, e in ipairs(samples) do if e[1] <= t then b = e[2] end end return b and string.format("%.2f", b) or "-" end
		E.modes:request("idle")
		return string.format("%s %s %s %s %s %s", at(0.1), at(0.2), at(0.3), at(0.4), at(0.5), at(0.6))
	end

	local ok, err = pcall(function()
		for _, s in ipairs(speeds) do
			out["van" .. s] = vanisher(s)
			progress("vanisher " .. s)
			writefile("HappaTasTest/pfk.json", HttpService:JSONEncode(out))
		end
		for _, s in ipairs(speeds) do
			local r = {}
			for i = 1, (pushRepeats or 3) do r[i] = pusher(s) end
			out["push" .. s] = r
			progress("pusher " .. s)
			writefile("HappaTasTest/pfk.json", HttpService:JSONEncode(out))
		end
	end)
	conn:Disconnect()
	pcall(P.speed, 1, false)
	P.done()
	out.err = not ok and tostring(err) or nil
	writefile("HappaTasTest/pfk.json", HttpService:JSONEncode(out))
	return out.err or "ok"
end
