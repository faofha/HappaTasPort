-- ================================================================================================
--  LIVE PART F, Frame Step (test tool, never shipped): scenario 13. Per speed: game time per real second for
--  the character (walking on phys3's platform) and the world (the test place's spinner, moving platform, beat
--  blocks, and a free part falling), how even the motion is per rendered frame, and the three rewinds (hold
--  Back: game time per real second; tap: game time per tap; the timeline: game time per frame, as it maps a
--  pixel to frames). Load with  local run = loadfile("HappaTasTest/partf_fs.lua")(); run(fps, speeds, progress)
--  Results: HappaTasTest/pfs_<fps>.json
-- ================================================================================================
local HttpService = game:GetService("HttpService")
local RS = game:GetService("RunService")
local P = loadfile("HappaTasTest/phys3.lua")()

local function r4(v) return type(v) == "number" and math.floor(v * 10000 + 0.5) / 10000 or v end

return function(fps, speeds, progress)
	progress = progress or function() end
	setfpscap(fps)
	P.use("h3", "HappaTasTest/h3.lua")
	task.wait(1)
	local E = getgenv().__HappaTAS3_T.engine
	local tl = E.tl
	local function TT(f) if f < 1 or f > tl:count() then return 0 end return tl:get("TotalTime", f, 1) end
	local cp = workspace.ClientParts
	local spin = cp.DistanceCulling["Spinning Platform"].Primary
	local mp = cp.MovingPlatform.Platform
	local bb = {}
	for _, d in ipairs(cp.BeatBlockGroup:GetDescendants()) do if d:IsA("BasePart") then bb[#bb + 1] = d end end
	local spawnL = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local out = { fps = fps }

	local function world(s)
		P.speed(s, true)
		E.modes:request("idle"); task.wait(0.3); E.modes:setRun({}); task.wait(0.2)
		local hrp = E.char.hrp
		hrp.CFrame = spawnL.CFrame + Vector3.new(0, 4, 0)
		hrp.AssemblyLinearVelocity = Vector3.zero
		task.wait(1)
		E.modes:create(true); task.wait(0.4)
		local box = Instance.new("Part")
		box.Name, box.Size, box.CFrame = "zzFallProbe", Vector3.new(2, 2, 2), spawnL.CFrame + Vector3.new(40, 900, 40)
		box.CanCollide, box.CanTouch, box.CanQuery = false, false, false
		box.Parent = workspace
		E.modes:unpause(); task.wait(0.6)
		local ang, path, beats = 0, 0, 0
		local pR, pM = spin.CFrame, mp.Position
		local st = {}
		for i, p in ipairs(bb) do st[i] = p.CanCollide end
		local c = RS.RenderStepped:Connect(function()
			local r = spin.CFrame
			local _, a = (pR:Inverse() * r):ToAxisAngle()
			ang = ang + math.abs(a); pR = r
			path = path + (mp.Position - pM).Magnitude; pM = mp.Position
			for i, p in ipairs(bb) do if p.CanCollide ~= st[i] then beats = beats + 1; st[i] = p.CanCollide end end
		end)
		local v0, t0, g0 = box.AssemblyLinearVelocity.Y, os.clock(), TT(tl:count())
		task.wait(3)
		local el = os.clock() - t0
		local v1, g1 = box.AssemblyLinearVelocity.Y, TT(tl:count())
		c:Disconnect()
		box:Destroy()
		E.modes:pause(); task.wait(0.2); E.modes:request("idle")
		return { spinRadPerSec = r4(ang / el), platStudsPerSec = r4(path / el), beatsPerSec = r4(beats / el),
			fallGPerSec = r4((v0 - v1) / el / workspace.Gravity), gamePerReal = r4((g1 - g0) / el) }
	end

	local function char(s)
		P.speed(s, true)
		E.modes:request("idle"); task.wait(0.3); E.modes:setRun({}); task.wait(0.2)
		P.placeAtV(Vector3.new(-25, 0, 0), P.SURF.plat)
		E.modes:create(true); task.wait(0.4)
		local hrp = E.char.hrp
		local frames, movedFrames, maxStep = 0, 0, 0
		local px
		local c = RS.RenderStepped:Connect(function()
			local x = hrp.Position.X
			if px then
				frames = frames + 1
				local d = math.abs(x - px)
				if d > 1e-4 then movedFrames = movedFrames + 1 end
				if d > maxStep then maxStep = d end
			end
			px = x
		end)
		P.setDrive(Vector3.new(1, 0, 0), false)
		E.modes:unpause()
		task.wait(0.5)
		local n0, x0, c0 = tl:count(), hrp.Position.X, os.clock()
		local t0 = TT(n0)
		frames, movedFrames, maxStep = 0, 0, 0
		task.wait(3)
		local n1, x1, el = tl:count(), hrp.Position.X, os.clock() - c0
		local t1 = TT(n1)
		local fr, mf, ms = frames, movedFrames, maxStep
		c:Disconnect()
		P.setDrive(Vector3.zero, false)
		E.modes:pause(); task.wait(0.2)
		local r = { gamePerReal = (t1 - t0) / el, studsPerReal = (x1 - x0) / el, framesPerReal = (n1 - n0) / el,
			movedFrameShare = mf / math.max(1, fr), maxStudsPerFrame = ms }
		-- hold Back for 1 real second
		local f0 = E.frame
		local tt0 = TT(f0)
		E.modes:back(); local h0 = os.clock(); task.wait(1); E.modes:release("back"); local hel = os.clock() - h0
		r.holdGamePerReal = (tt0 - TT(E.frame)) / hel
		-- 10 taps
		local ta = TT(E.frame)
		for _ = 1, 10 do if E.frame > 1 then E.modes:back1() end; task.wait(0.05) end
		r.gamePerTap = (ta - TT(E.frame)) / 10
		-- the timeline maps a pixel to frames: game time per frame
		r.gamePerFrame = TT(tl:count()) / math.max(1, tl:count())
		E.modes:request("idle")
		for k, v in pairs(r) do r[k] = r4(v) end
		return r
	end

	local ok, err = pcall(function()
		out.idleWorld = (function()
			P.speed(1, true)
			return nil
		end)()
		for _, s in ipairs(speeds) do
			out["world" .. s] = world(s)
			out["char" .. s] = char(s)
			progress("fs " .. s)
			writefile(string.format("HappaTasTest/pfs_%d.json", fps), HttpService:JSONEncode(out))
		end
	end)
	pcall(P.speed, 1, false)
	P.done()
	out.err = not ok and tostring(err) or nil
	writefile(string.format("HappaTasTest/pfs_%d.json", fps), HttpService:JSONEncode(out))
	return out.err or "ok"
end
