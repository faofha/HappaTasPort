-- ================================================================================================
--  LIVE PART F, animations and camera (test tool, never shipped): scenarios 14 and 15.
--  14: record climb (a truss by the spawn; walk on phys3's platform if the character won't climb), stop,
--      jump / fall; then rewind 10+ times to a frame in each part (timeline, hold Back, tap in turn): the main
--      track and its TimePosition each time, against what was saved and what played while recording; then
--      Test: the replayed TimePosition against the recording, per frame. At each speed given.
--  15: a copy of dzr's camera bug file (HappaTasTest/cam23740.tas): 20+ pause / unpause cycles after the bug
--      frame: camera distance to the head, the zoom controller's distance, CameraType, FieldOfView, before
--      (paused) and over the 40 frames after each unpause.
--  Load with  local A = loadfile("HappaTasTest/partf_anim.lua")(); A.anim(speeds, progress) / A.camera(cycles)
--  Results: HappaTasTest/pfa.json, pfc.json
-- ================================================================================================
local HttpService = game:GetService("HttpService")
local RS = game:GetService("RunService")
local P = loadfile("HappaTasTest/phys3.lua")()
local A = {}
local lp = game:GetService("Players").LocalPlayer

local function mainTrack()
	local an = lp.Character.Humanoid:FindFirstChildOfClass("Animator")
	local best
	for _, t in ipairs(an:GetPlayingAnimationTracks()) do if not best or t.WeightCurrent > best.WeightCurrent then best = t end end
	return best
end
local function trackName(t) return t and ((t.Animation and t.Animation.AnimationId or ""):match("%d+$") or t.Name) or "none" end

function A.anim(speeds, progress)
	progress = progress or function() end
	P.use("h3", "HappaTasTest/h3.lua")
	task.wait(1)
	local E = getgenv().__HappaTAS3_T.engine
	local tl = E.tl
	local function TT(f) if f < 1 or f > tl:count() then return 0 end return tl:get("TotalTime", f, 1) end
	-- (on phys3's platform, away from the kit's Seat by the spawn: a truss 12 studs ahead)
	local truss = Instance.new("TrussPart")
	truss.Name, truss.Anchored, truss.Size = "zzPhysTruss", true, Vector3.new(2, 20, 2)
	truss.CFrame = CFrame.new(12, P.SURF.plat + 10, 0)
	truss.Parent = workspace
	local out = {}
	local function one(s)
		local res = {}
		P.speed(s, true)
		E.modes:request("idle"); task.wait(0.3); E.modes:setRun({}); task.wait(0.2)
		local hrp, hum = E.char.hrp, E.char.hum
		P.placeAtV(Vector3.new(0, 0, 0), P.SURF.plat)
		E.modes:create(true); task.wait(0.3)
		local truth, states = {}, {}
		local conn = RS.RenderStepped:Connect(function()
			local n = tl:count()
			if n < 1 or E.paused then return end
			local t = mainTrack()
			truth[n] = { trackName(t), t and t.TimePosition or -1 }
			states[n] = hum:GetState().Name
		end)
		-- climb (walk into the truss) 1.2 s, let go 0.4 s, jump off backwards and fall
		P.setDrive(Vector3.new(1, 0, 0), false)
		E.modes:unpause()
		local t0 = os.clock()
		local function untilT(t) repeat task.wait() until TT(tl:count()) >= t or os.clock() - t0 > 120 end
		untilT(1.2)
		P.setDrive(Vector3.zero, false)
		untilT(1.6)
		P.setDrive(Vector3.new(-1, 0, 0), true)
		untilT(1.75)
		P.setDrive(Vector3.new(-1, 0, 0), false)
		untilT(2.6)
		P.setDrive(Vector3.zero, false)
		untilT(3.0)
		E.modes:pause(); conn:Disconnect(); task.wait(0.3)
		local n = tl:count()
		local seen = {}
		for f = 1, n do if states[f] then seen[states[f]] = (seen[states[f]] or 0) + 1 end end
		local sl = {}
		for k, c in pairs(seen) do sl[#sl + 1] = k .. " " .. c end
		res.states = table.concat(sl, ", ")
		res.climbed = seen.Climbing ~= nil
		-- one frame in each part
		local function frameAt(t) local b for f = 1, n do if TT(f) <= t then b = f end end return b end
		local picks = { climbOrWalk = frameAt(0.9), stopped = frameAt(1.5), falling = frameAt(2.2) }
		local methods = { "seek", "hold", "tap" }
		for name, f in pairs(picks) do
			local shown = {}
			for k = 1, 12 do
				local m = methods[(k - 1) % 3 + 1]
				if m == "seek" then
					E.modes:seek(math.min(n, f + 40 + k)); task.wait(0.1); E.modes:seek(f)
				elseif m == "hold" then
					E.modes:seek(math.min(n, f + 30 + k)); task.wait(0.1)
					E.modes:back()
					local g = os.clock()
					repeat task.wait() until E.frame <= f or os.clock() - g > 20
					E.modes:release("back")
					if E.frame ~= f then E.modes:seek(f) end
				else
					E.modes:seek(math.min(n, f + 6)); task.wait(0.1)
					while E.frame > f do E.modes:back1(); task.wait() end
				end
				task.wait(0.3)
				local t = mainTrack()
				shown[#shown + 1] = string.format("%.4f", t and t.TimePosition or -1)
			end
			local u = {}
			for _, x in ipairs(shown) do u[x] = true end
			local nu = 0
			for _ in pairs(u) do nu = nu + 1 end
			local tr = truth[f]
			res[name] = string.format("f%d %s: %d different value(s) in 12 rewinds [%s]; saved %s; while recording %s %s", f,
				states[f] or "?", nu, table.concat(shown, " "), tostring(tl:getList("AnimTime", f)), tr and tr[1] or "?", tr and string.format("%.4f", tr[2]) or "?")
		end
		-- replay
		local worst, cnt, mism = 0, 0, 0
		local c2 = RS.RenderStepped:Connect(function()
			if E.mode ~= 3 then return end
			local tr = truth[E.frame]
			local t = mainTrack()
			if tr and t then
				cnt = cnt + 1
				if trackName(t) ~= tr[1] then mism = mism + 1
				else worst = math.max(worst, math.abs(t.TimePosition - tr[2])) end
			end
		end)
		E.modes:request("test")
		t0 = os.clock()
		repeat task.wait() until E.mode ~= 3 or os.clock() - t0 > 60
		c2:Disconnect()
		res.test = string.format("%d frames compared: other track on %d, worst TimePosition off %.4f", cnt, mism, worst)
		E.modes:request("idle")
		return res
	end
	local ok, err = pcall(function()
		for _, s in ipairs(speeds) do
			out["anim" .. s] = one(s)
			progress("anim " .. s)
			writefile("HappaTasTest/pfa.json", HttpService:JSONEncode(out))
		end
	end)
	truss:Destroy()
	pcall(P.speed, 1, false)
	P.done()
	out.err = not ok and tostring(err) or nil
	writefile("HappaTasTest/pfa.json", HttpService:JSONEncode(out))
	return out.err or "ok"
end

function A.camera(cycles)
	P.use("h3", "HappaTasTest/h3.lua")
	task.wait(1)
	local E = getgenv().__HappaTAS3_T.engine
	local tl = E.tl
	local cam = workspace.CurrentCamera
	local root0 = E.library.root
	E.library.root = "HappaTasTest"
	local out = {}
	local ok, err = pcall(function()
		E.settings:set("speedHack", 0)
		local okL, why = E.persist:load("cam23740.tas")
		assert(okL, why)
		local t0 = os.clock()
		repeat task.wait(0.1) until (E.loaded and E.loaded.path == "cam23740.tas" and not E.busy) or os.clock() - t0 > 60
		E.library.root = root0
		out.loaded = tl:count()
		E.modes:request("create"); task.wait(0.5)
		local function camDist()
			local head = lp.Character and lp.Character:FindFirstChild("Head")
			if not head then return -1 end
			return (cam.CFrame.Position - head.Position).Magnitude
		end
		local rows, bad = {}, 0
		for c = 1, cycles do
			E.modes:seek(tl:count()); task.wait(0.3)
			local before = { camDist(), tostring(cam.CameraType), cam.FieldOfView, (lp.Character.Head.Position - cam.Focus.Position).Magnitude }
			local d, types, fovs = {}, {}, {}
			local conn = RS.RenderStepped:Connect(function()
				if #d < 40 then d[#d + 1] = camDist(); types[tostring(cam.CameraType)] = true; fovs[cam.FieldOfView] = true end
			end)
			E.modes:unpause()
			task.wait(0.25)
			E.modes:pause()
			conn:Disconnect()
			local mn, mx = math.huge, 0
			for _, x in ipairs(d) do mn = math.min(mn, x); mx = math.max(mx, x) end
			local nt, nf = 0, 0
			for _ in pairs(types) do nt = nt + 1 end
			for _ in pairs(fovs) do nf = nf + 1 end
			local same = math.abs(mn - before[1]) < 0.05 and math.abs(mx - before[1]) < 0.05 and nt == 1 and types[before[2]] and nf == 1 and fovs[before[3]]
			if not same then bad = bad + 1 end
			rows[c] = string.format("paused %.3f %s fov %.1f | after unpause %.3f..%.3f types %d fov %d%s", before[1], before[2], before[3], mn, mx, nt, nf, same and "" or " DIFFERENT")
			task.wait(0.2)
		end
		out.cycles = rows
		out.different = bad
		E.modes:request("idle")
	end)
	E.library.root = root0
	P.done()
	out.err = not ok and tostring(err) or nil
	writefile("HappaTasTest/pfc.json", HttpService:JSONEncode(out))
	return out.err or ("different " .. tostring(out.different))
end

return A
