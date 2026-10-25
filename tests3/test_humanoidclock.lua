-- ================================================================================================
-- HappaTAS 3, phase 4: time control, Frame Step and the humanoid on the TAS clock (V2.38.17's
-- tests/test_speedhack.lua sections, the same fixtures, numbers and mock models, through the shim of
-- tests3/test_timecontrol.lua). Smooth motion and the world: tests3/test_timecontrol.lua.
--   * a TAS recorded at speed s with real frames dt is the same TAS as one recorded at normal speed with
--     frames dt x s (positions, velocities, times, animation speeds, jump timer), at uneven frame rates
--   * gravity x s^2, WalkSpeed / JumpPower x s while recording, normal again while paused, in Idle / Test
--   * the speed or the switch changed while recording: the motion goes on; game writes are adopted
--   * bounce pads: the kit's Power x s; dead: normal time; Unload puts everything back
-- (headless mock with a small humanoid model, not a real game)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local SettingsMod = __T3("engine/settings")
local S = {
	Set = function(name, v) return E.settings:set(SettingsMod.byV2[name].key, v) end,
	Get = function(name) return E.settings:get(SettingsMod.byV2[name].key) end,
}
local SH = setmetatable({ Wanted = function() return E.time:wanted() end, Humanoid = E.time.SH.Humanoid },
	{ __index = function(_, k) return E.time[k] end })
-- (the parts of V2's Core.State this suite reads: the run as V2 frames, the mode, the character)
local C = setmetatable({ DataChanged = function() end }, {
	__index = function(_, k)
		if k == "data" then return E.tl:toV2All() end
		if k == "paused" then return E.paused end
		if k == "mode" then return E.mode end
		if k == "Humanoid" then return E.char.hum end
		if k == "HRP" then return E.char.hrp end
		return nil
	end,
	__newindex = function(_, k, v)
		if k == "data" then E.modes:setRun(v) else rawset(_, k, v) end
	end,
})
local UIS = M.services.UserInputService
local guard = 0
while not (C.HRP and C.Humanoid) and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local hrp, hum = C.HRP, C.Humanoid
M.humanoidPhysics = true
M.robloxController = true -- (Roblox's walk / turn / coyote controllers, see the mock)
local G0 = workspace.Gravity

local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
local function r(n, d) local v = math.round(n * d) / d; if v == 0 then v = 0 end; return v end
local function click()
	UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	UIS.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
local function steps(n, dt) for _ = 1, n do M.step(dt or 1 / 60) end end
local function walkTrack()
	local an = hum:FindFirstChildOfClass("Animator")
	for _, t in ipairs(an:GetPlayingAnimationTracks()) do
		if t.Animation and t.Animation.AnimationId == "http://www.roblox.com/asset/?id=180426354" then return t end
	end
	return nil
end

-- uneven frames (about 60 - 144 FPS)
local seed = 11
local function nextDt()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return (6.9 + (seed % 1000) / 1000 * 9.8) / 1000
end
local DTS = {}
for i = 1, 240 do DTS[i] = nextDt() end

-- records a TAS from a fresh start: frame i lasts dts[i] x mul real seconds; events[i]() runs before frame i
local function record(dts, mul, events)
	key(Enum.KeyCode.One) -- Idle
	steps(2)
	C.data = {}
	C.DataChanged()
	hum.MoveDirection = Vector3.zero
	hrp.CFrame = CFrame.new(0, 3, 0)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	hum.WalkSpeed, hum.JumpPower = 16, 50
	hum.Jump = false
	-- every run starts from the same animation state (idle, no jump timer left from an earlier run)
	M.resetHumanoidModel()
	M.resetRobloxController()
	E.anim:set({ Pose = 2, JumpTime = 0, Speed = 1 }, { { 1, 0 } }, 1)
	steps(2)
	key(Enum.KeyCode.Two) -- Create (paused)
	steps(2)
	click() -- Unpause: recording
	for i = 1, #dts do
		if events and events[i] then events[i]() end
		M.step(dts[i] * mul)
	end
	click() -- Pause
	steps(2)
	local out = {}
	for i, fr in ipairs(C.data) do out[i] = fr end
	return out
end

local function jumpAt(k) return { [k] = function() M.jumpNow = true end } end
local function walkThenJump()
	local ev = {}
	ev[1] = function() hum.MoveDirection = Vector3.new(1, 0, 0) end
	ev[60] = function() M.jumpNow = true end
	ev[150] = function() hum.MoveDirection = Vector3.new(0, 0, 1) end
	ev[200] = function() M.jumpNow = true end
	return ev
end

-- compares two recordings frame by frame
-- edges: how many Jumping / Freefall frames may differ (below 1x Roblox finishes a jump on its own real-time step,
-- up to one frame before the game's 1/240 s hold is over; positions and speeds are the same)
local function sameTAS(a, b, label, edges)
	shownDiff = 0
	eq(#a, #b, label .. ": same number of frames")
	local worstP, worstV, worstT, worstA, worstJ, badState = 0, 0, 0, 0, 0, 0
	for i = 1, math.min(#a, #b) do
		local fa, fb = a[i], b[i]
		if fa.Cframe and fb.Cframe then
			for c = 1, 3 do worstP = math.max(worstP, math.abs(fa.Cframe[c] - fb.Cframe[c])) end
		end
		for c = 1, 3 do worstV = math.max(worstV, math.abs(fa.Velocity.Linear[c] - fb.Velocity.Linear[c])) end
		worstT = math.max(worstT, math.abs(fa.TotalTime - fb.TotalTime), math.abs(fa.FrameTime - fb.FrameTime))
		if fa.Anim and fb.Anim then
			worstA = math.max(worstA, math.abs((fa.Anim.Speed or 1) - (fb.Anim.Speed or 1)))
			worstJ = math.max(worstJ, math.abs((fa.Anim.JumpTime or 0) - (fb.Anim.JumpTime or 0)))
		end
		if DEBUG_DIFF and shownDiff < 6 and (math.abs(fa.Velocity.Linear[2] - fb.Velocity.Linear[2]) > 0.002 or fa.State ~= fb.State) then
			shownDiff = shownDiff + 1
			M.realPrint(string.format("%s i=%d st %s/%s vy %.3f/%.3f y %.3f/%.3f vx %.3f/%.3f t %.4f", label, i, tostring(fa.State), tostring(fb.State), fa.Velocity.Linear[2], fb.Velocity.Linear[2], fa.Cframe[2], fb.Cframe[2], fa.Velocity.Linear[1], fb.Velocity.Linear[1], fa.TotalTime))
		end
		local J, F = Enum.HumanoidStateType.Jumping.Value, Enum.HumanoidStateType.Freefall.Value
		if fa.State ~= fb.State and (edges or 0) > 0 and ((fa.State == J and fb.State == F) or (fa.State == F and fb.State == J)) then
			edges = edges - 1
		elseif fa.State ~= fb.State then
			badState = badState + 1
			if DEBUG_STATES then M.realPrint(label .. " state frame " .. i .. ": " .. tostring(fa.State) .. " / " .. tostring(fb.State) .. " t " .. fa.TotalTime) end
		end
	end
	check(worstP <= 0.0011, label .. ": positions within 0.001 (" .. worstP .. ")")
	check(worstV <= 0.0011, label .. ": velocities within 0.001 (" .. worstV .. ")")
	check(worstT <= 2e-6, label .. ": frame / total times equal (" .. worstT .. ")")
	check(worstA <= 0.0011, label .. ": animation speeds equal (" .. worstA .. ")")
	check(worstJ <= 0.0011, label .. ": jump animation timers equal (" .. worstJ .. ")")
	eq(badState, 0, label .. ": same humanoid states")
end

eq(S.Get("Speed Hack"), 0, "Speed Hack off by default")
S.Set("Speed Hack", 1)
section("fast motion (speeds above 1): the TAS a normal recording with longer frames makes")
S.Set("Speed Hack Speed", 2)
local evF = walkThenJump()
local seenF = {}
evF[30] = function()
	seenF.walk, seenF.jump, seenF.grav, seenF.rate = hum.WalkSpeed, hum.JumpPower, workspace.Gravity, E.cs.timeRate
	local t = walkTrack()
	seenF.track = t and t.Speed
end
local fast = record(DTS, 1, evF)
S.Set("Speed Hack", 0)
local plainF = record(DTS, 2, walkThenJump())
S.Set("Speed Hack", 1)
near(seenF.walk, 32, 1e-9, "2x: WalkSpeed x 2")
near(seenF.jump, 100, 1e-9, "2x: JumpPower x 2")
near(seenF.grav, G0 * 4, 1e-6, "2x: gravity x 4")
near(seenF.track, (16 / 14.5) * 2, 1e-6, "2x: the walk animation plays twice as fast")
near(seenF.rate, 2, 1e-9, "2x: the camera's zoom spring runs twice as fast")
sameTAS(plainF, fast, "2x at real frames dt vs 1x at frames dt x 2")
near(hum.WalkSpeed, 16, 1e-9, "2x: WalkSpeed back when paused")
near(workspace.Gravity, G0, 1e-9, "2x: gravity back when paused")
eq(E.cs.timeRate, 1, "zoom spring at normal speed when paused")
S.Set("Speed Hack Speed", 0.5)

section("Frame Step: normal physics on every other frame, everything held on the others")
eq(S.Get("Speed Hack Frame Step"), 0, "off by default")
S.Set("Speed Hack Frame Step", 1)
-- normal frame i (DTS[i]) <-> frame step frames 2i - 1 (physics runs) and 2i (held, the same dt)
local N2 = 120
local fsDts, fsEv, wt2 = {}, {}, walkThenJump()
for i = 1, N2 do
	fsDts[2 * i - 1], fsDts[2 * i] = DTS[i], DTS[i]
	if wt2[i] then fsEv[2 * i - 1] = wt2[i] end
end
-- (ends on a frame whose step runs: the held frame after it would record that step, which the normal run
-- throws away when it pauses)
fsDts[2 * N2] = nil
local seenS = { betweenAnchored = 0 }
fsEv[31] = function()
	seenS.walk, seenS.grav, seenS.scale, seenS.rate = hum.WalkSpeed, workspace.Gravity, SH.scale, E.cs.timeRate
	local t = walkTrack()
	seenS.track = t and t.Speed
end
local plog = nil
for i = 1, 2 * N2 - 1 do
	local prev = fsEv[i]
	fsEv[i] = function()
		if prev then prev() end
		if i > 1 and hrp.Anchored then seenS.betweenAnchored = seenS.betweenAnchored + 1 end
		if i == 1 then M.physicsLog = {} end
		if i == 2 * N2 - 1 then plog = table.clone(M.physicsLog) end -- (the steps of frames 1 .. 2 x N2 - 2)
	end
end
local stepped = record(fsDts, 1, fsEv)
M.physicsLog = nil
S.Set("Speed Hack", 0)
local dtsN2 = {}
for i = 1, N2 do dtsN2[i] = DTS[i] end
local plainS = record(dtsN2, 1, walkThenJump())
S.Set("Speed Hack", 1)
near(seenS.walk, 16, 1e-9, "Frame Step: WalkSpeed untouched")
near(seenS.grav, G0, 1e-9, "Frame Step: gravity untouched")
eq(seenS.scale, 1, "Frame Step: the physics isn't scaled")
near(seenS.track, (16 / 14.5) * 0.5, 1e-6, "Frame Step: the walk animation plays at half its speed")
near(seenS.rate, 0.5, 1e-9, "Frame Step: the zoom spring runs at half speed")
eq(seenS.betweenAnchored, 0, "Frame Step: the character is never held between frames")
sameTAS(plainS, stepped, "Frame Step 0.5x at real frames dt vs 1x")
local heldSteps, freeSteps = 0, 0
for _, e in ipairs(plog) do
	if e[1] == hrp then
		if e[2] then heldSteps = heldSteps + 1 else freeSteps = freeSteps + 1 end
	end
end
eq(heldSteps, N2 - 1, "Frame Step: the physics saw the character held on every other step")
eq(freeSteps, N2 - 1, "Frame Step: and free on the others")

-- 0.25x: one step in four runs
S.Set("Speed Hack Speed", 0.25)
local q4Dts, q4Ev, wt4 = {}, {}, walkThenJump()
for i = 1, 60 do
	for k = 0, 3 do q4Dts[4 * i - 3 + k] = DTS[i] end
	if wt4[i] then q4Ev[4 * i - 3] = wt4[i] end
end
for k = 238, 240 do q4Dts[k] = nil end
local steppedQ = record(q4Dts, 1, q4Ev)
S.Set("Speed Hack", 0)
local dts60 = {}
for i = 1, 60 do dts60[i] = DTS[i] end
local plainQ4 = record(dts60, 1, walkThenJump())
S.Set("Speed Hack", 1)
sameTAS(plainQ4, steppedQ, "Frame Step 0.25x")
S.Set("Speed Hack Speed", 0.5)

section("Frame Step: free parts and the kit's clock only move on the steps that run")
local CPf = workspace:FindFirstChild("ClientParts")
if not CPf then CPf = Instance.new("Folder"); CPf.Name = "ClientParts"; CPf.Parent = workspace end
local boxF = Instance.new("Part")
boxF.Name = "FreeBox"
boxF.Anchored = false
boxF.CFrame = CFrame.new(50, 10, 0)
boxF.AssemblyLinearVelocity = Vector3.new(0, 0, 6)
boxF.Parent = CPf
M.freeParts = { boxF }
local z0, z1, k0, k1, t0, t1
local evB = {}
local fixed = {}
for i = 1, 40 do fixed[i] = 1 / 60 end
evB[1] = function() z0 = boxF.Position.Z end
evB[40] = function() z1 = boxF.Position.Z end
local boxRec = record(fixed, 1, evB)
near(z1 - z0, 6 * 20 / 60, 1e-6, "the box moved on the 20 steps that ran only")
near(boxF.AssemblyLinearVelocity.Z, 6, 1e-9, "the box keeps its velocity")
eq(boxF.Anchored, false, "the box isn't left anchored")
near(boxRec[#boxRec].TotalTime, 20 / 60, 1e-5, "TAS time = the time of the steps that ran (" .. boxRec[#boxRec].TotalTime .. ")")
M.freeParts = {}
boxF:Destroy()
S.Set("Speed Hack Frame Step", 0)

section("Frame Step only below 1x: above it the physics is scaled")
S.Set("Speed Hack Frame Step", 1)
S.Set("Speed Hack Speed", 2)
local fastFS = record(DTS, 1, walkThenJump())
S.Set("Speed Hack Frame Step", 0)
sameTAS(fast, fastFS, "2x with Frame Step on = 2x scaled")
S.Set("Speed Hack Speed", 0.5)

section("one recording through 0.5x Smooth, 2x, Frame Step 0.25x and off (Review Focus 5)")
do
	S.Set("Speed Hack", 1)
	S.Set("Speed Hack Speed", 0.5)
	S.Set("Speed Hack Frame Step", 0)
	local seenM = {}
	local ev = {
		[1] = function() hum.MoveDirection = Vector3.new(1, 0, 0) end,
		[50] = function() S.Set("Speed Hack Speed", 2) end,
		[100] = function() S.Set("Speed Hack Frame Step", 1); S.Set("Speed Hack Speed", 0.25) end,
		[130] = function() seenM.held = hrp.Anchored end,
		[180] = function() S.Set("Speed Hack", 0) end,
		[200] = function() seenM.g, seenM.w, seenM.j, seenM.an, seenM.scale = workspace.Gravity, hum.WalkSpeed, hum.JumpPower, hrp.Anchored, SH.scale end,
	}
	local run = record({ table.unpack(DTS, 1, 220) }, 1, ev)
	S.Set("Speed Hack Frame Step", 0)
	S.Set("Speed Hack Speed", 0.5)
	check(#run > 150, "frames recorded (" .. #run .. ")")
	local worstT, minV, maxV, nonPos = 0, 1e9, 0, 0
	for i = 2, #run do
		worstT = math.max(worstT, math.abs(run[i].TotalTime - (run[i - 1].TotalTime + run[i].FrameTime)))
		if run[i].FrameTime <= 0 then nonPos = nonPos + 1 end
		if i >= 12 then
			local vx = run[i].Velocity.Linear[1]
			minV, maxV = math.min(minV, vx), math.max(maxV, vx)
		end
	end
	check(worstT < 2e-6, string.format("TotalTime continuous (worst %.2e)", worstT))
	eq(nonPos, 0, "every frame has a positive frame time")
	near(minV, 16, 1e-3, "recorded walking speed the normal 16 throughout (min)")
	near(maxV, 16, 1e-3, "recorded walking speed the normal 16 throughout (max)")
	eq(seenM.held, false, "Frame Step: the character isn't anchored between frames")
	eq(seenM.scale, 1, "off: no scaling")
	near(seenM.g, G0, 1e-9, "off: normal gravity")
	near(seenM.w, 16, 1e-9, "off: WalkSpeed 16")
	near(seenM.j, 50, 1e-9, "off: JumpPower 50")
	eq(seenM.an, false, "off: nothing anchored")
	S.Set("Speed Hack", 1)
end

section("the humanoid on the TAS clock (V2.38.17): walk / stop, turning, coyote time, gravity above 1000")
-- every scenario recorded at speed s with real frames of 1/60 s is the same TAS as at normal speed with frames
-- of s/60 s (the mock's humanoid has Roblox's controllers: speed gap 62.5 % per 1/240 s step, caps 741.6 / 143,
-- AutoRotate as a PD controller, a jump until 0.13 s after the floor is lost in real time, Freefall after 0.125 s)
do
	local FR = {}
	for i = 1, 150 do FR[i] = 1 / 60 end
	local function yawOf(fr)
		local c = fr.Cframe
		return math.atan2(-c[6], -c[12])
	end
	-- the recording at s vs the normal one, rotation and states too
	local function compare(label, s, events, frames)
		S.Set("Speed Hack", 0)
		local plainR = record(frames or FR, s, events())
		S.Set("Speed Hack", 1)
		S.Set("Speed Hack Speed", s)
		local slowR = record(frames or FR, 1, events())
		S.Set("Speed Hack Speed", 0.5)
		sameTAS(plainR, slowR, label, s < 1 and 1 or 0)
		local worstYaw = 0
		for i = 1, math.min(#plainR, #slowR) do
			if plainR[i].Cframe and slowR[i].Cframe then
				local d = math.abs((yawOf(plainR[i]) - yawOf(slowR[i]) + math.pi) % (2 * math.pi) - math.pi)
				worstYaw = math.max(worstYaw, d)
			end
		end
		check(worstYaw <= 0.002, label .. ": same facing every frame (" .. worstYaw .. " rad)")
		return plainR, slowR
	end
	local function walkStop()
		return {
			[1] = function() hum.MoveDirection = Vector3.new(1, 0, 0) end,
			[40] = function() hum.MoveDirection = Vector3.zero end,
		}
	end
	local function turn180()
		return {
			[1] = function() hum.MoveDirection = Vector3.new(0, 0, -1) end,
			[50] = function() hum.MoveDirection = Vector3.new(0, 0, 1) end,
		}
	end
	-- (walking, turning and a standing jump against the normal TAS at 240 FPS: below, compareGame)
	-- a jump at 240 FPS (one physics step a frame, sometimes two, like the live client): Roblox's Jumping state
	-- pushes the speed back up to the jump speed while it lasts, so the corrected (game time) speed must not set
	-- it off again (live V2.38.17 draft: a 4x jump went 12.5 studs high, 2x 7.38 instead of 7.27)
	-- (with a few nanoseconds of noise: the live client's PostSimulation dt is whole steps only up to that)
	local F240 = {}
	for i = 1, 330 do F240[i] = ((i % 7 == 0) and 2 / 240 or 1 / 240) + ((i % 3) - 1) * 3e-9 end
	for _, s in ipairs({ 2, 4 }) do
		M.jumpPushes = 0
		-- (the push on frame 23, one step, with one-step frames after it: the live log's case)
		local plainR, slowR = compare(s .. "x standing jump at 240 FPS", s, function() return jumpAt(22) end, F240)
		local function apex(r)
			local m = -math.huge
			for _, fr in ipairs(r) do if fr.Cframe then m = math.max(m, fr.Cframe[2]) end end
			return m
		end
		near(apex(slowR), apex(plainR), 0.002, s .. "x at 240 FPS: the jump is as high as the normal one (" .. apex(slowR) .. " / " .. apex(plainR) .. ")")
		eq(M.jumpPushes, 2, s .. "x at 240 FPS: Roblox pushed the jump once in each recording")
	end
	-- below 1x a frame is part of a game step: the TAS at 0.5x / 0.25x (frames of one or two real steps, like the
	-- live client) against the normal one at 240 FPS, at the times both have (the game's steps are Roblox's 1x steps)
	do
		local function byGameTime(frames, s, events)
			-- events[t] (game seconds) run before the first frame that starts at or after t
			local ev, t, i = {}, 0, 1
			local times = {}
			for k in pairs(events) do times[#times + 1] = k end
			table.sort(times)
			for f = 1, #frames do
				while times[i] and t >= times[i] - 1e-6 do
					local prev = ev[f]
					local fn = events[times[i]]
					ev[f] = prev and function() prev(); fn() end or fn
					i = i + 1
				end
				t = t + frames[f] * s
			end
			return ev
		end
		local function compareGame(label, s, events, dur)
			local plainF, slowF = {}, {}
			for i = 1, math.floor(dur * 240 + 0.5) do plainF[i] = 1 / 240 end
			local t, i = 0, 0
			while t < dur / s - 1e-9 do
				i = i + 1
				slowF[i] = ((i % 5 == 0) and 2 / 240 or 1 / 240) + ((i % 3) - 1) * 3e-9
				t = t + slowF[i]
			end
			S.Set("Speed Hack", 0)
			-- events: function = from the start of the frame it falls in (MoveDirection is read at each step's
			-- start); { fn, atEnd = true } = at the end of that frame (a jump is decided at a step's end), so the
			-- normal run gets it before its frame that ends where the slow frame ends
			local function split(evs)
				local forPlain, forSlow, starts, tt = {}, {}, {}, 0
				for j = 1, #slowF do starts[j] = tt; tt = tt + slowF[j] * s end
				for te, e in pairs(evs) do
					local fn, tp = type(e) == "table" and e[1] or e, te
					if type(e) == "table" and e.atEnd then
						for j = 1, #slowF do
							if starts[j] >= te - 1e-6 then tp = starts[j] + slowF[j] * s - 1 / 240; break end
						end
					end
					forSlow[te], forPlain[tp] = fn, fn
				end
				return forPlain, forSlow
			end
			local evPlain = split(events())
			local plainR = record(plainF, 1, byGameTime(plainF, 1, evPlain))
			S.Set("Speed Hack", 1)
			S.Set("Speed Hack Speed", s)
			local _, evSlow = split(events())
			local slowR = record(slowF, 1, byGameTime(slowF, s, evSlow))
			S.Set("Speed Hack Speed", 0.5)
			-- (recorded frame j is frame j of the list: plain frame k ends at k / 240 s, a slow one at s x its frames)
			local cum, ends = 0, {}
			for j = 1, #slowF do cum = cum + slowF[j] * s; ends[j] = cum * 240 end
			local n, worstP, worstV, worstY, states, apexP, apexS = 0, 0, 0, 0, 0, -math.huge, -math.huge
			local J, F = Enum.HumanoidStateType.Jumping.Value, Enum.HumanoidStateType.Freefall.Value
			for j, fb in ipairs(slowR) do
				local k = ends[j]
				local fa = math.abs(k - math.floor(k + 0.5)) < 1e-4 and plainR[math.floor(k + 0.5)]
				if fa and fa.Cframe and fb.Cframe then
					if DEBUG_GAME and label:find(DEBUG_GAME, 1, true) and n < 40 and j > 6 then
						M.realPrint(label, j, math.floor(k + 0.5), fa.State, fb.State, fa.Velocity.Linear[2], fb.Velocity.Linear[2], fa.Cframe[2], fb.Cframe[2],
							math.atan2(-fa.Cframe[6], -fa.Cframe[12]), math.atan2(-fb.Cframe[6], -fb.Cframe[12]))
					end
					n = n + 1
					for c = 1, 3 do
						worstP = math.max(worstP, math.abs(fa.Cframe[c] - fb.Cframe[c]))
						worstV = math.max(worstV, math.abs(fa.Velocity.Linear[c] - fb.Velocity.Linear[c]))
					end
					local ya, yb = math.atan2(-fa.Cframe[6], -fa.Cframe[12]), math.atan2(-fb.Cframe[6], -fb.Cframe[12])
					worstY = math.max(worstY, math.abs((ya - yb + math.pi) % (2 * math.pi) - math.pi))
					if fa.State ~= fb.State and not ((fa.State == J and fb.State == F) or (fa.State == F and fb.State == J)) then states = states + 1 end
					apexP, apexS = math.max(apexP, fa.Cframe[2]), math.max(apexS, fb.Cframe[2])
				end
			end
			check(n >= math.min(#plainR, #slowR) * 0.4, label .. ": compared at " .. n .. " game times")
			check(worstP <= 0.0011, label .. ": positions within 0.001 (" .. worstP .. ")")
			check(worstV <= 0.0011, label .. ": velocities within 0.001 (" .. worstV .. ")")
			check(worstY <= 0.002, label .. ": same facing (" .. worstY .. " rad)")
			eq(states, 0, label .. ": same humanoid states (a jump's Jumping / Freefall switch may differ by a frame)")
			return apexP, apexS, plainR
		end
		for _, s in ipairs({ 0.25, 0.5, 2, 4 }) do
			local _, _, walkR = compareGame(s .. "x at 240 FPS walk and stop", s, function()
				return { [0] = function() hum.MoveDirection = Vector3.new(1, 0, 0) end,
					[0.5] = function() hum.MoveDirection = Vector3.zero end }
			end, 0.8)
			local slide = walkR[#walkR].Cframe[1] - walkR[120].Cframe[1]
			check(slide > 0.05, s .. "x walk and stop: it slides a little before stopping (" .. slide .. " studs)")
			compareGame(s .. "x at 240 FPS 180-degree turn", s, function()
				return { [0] = function() hum.MoveDirection = Vector3.new(0, 0, -1) end,
					[0.4] = function() hum.MoveDirection = Vector3.new(0, 0, 1) end }
			end, 0.9)
			local aP, aS = compareGame(s .. "x at 240 FPS standing jump", s, function()
				return { [0.1] = { function() M.jumpNow = true end, atEnd = true } }
			end, 1.0)
			near(aS, aP, 0.002, s .. "x at 240 FPS: the jump is as high as the normal one (" .. aS .. " / " .. aP .. ")")
			-- a 180-degree turn in the air (the angle counts up to 1 rad there)
			compareGame(s .. "x at 240 FPS turn in the air", s, function()
				return { [0.1] = { function() M.jumpNow = true end, atEnd = true },
					[0.2] = function() hum.MoveDirection = Vector3.new(0, 0, 1) end }
			end, 0.9)
		end
	end
	-- if ending the jump doesn't take (the state stays Jumping), Roblox pushes back up to the jump speed every
	-- frame: those pushes are left out of the game's motion, so the jump is still the normal one
	do
		S.Set("Speed Hack", 0)
		-- (the push on frame 23, the frames after it one step each, like the live log)
		local plainR = record(F240, 4, jumpAt(22))
		S.Set("Speed Hack", 1)
		S.Set("Speed Hack Speed", 4)
		M.refuseScriptFreefall, M.jumpPushes = true, 0
		local slowR = record(F240, 1, jumpAt(22))
		M.refuseScriptFreefall = false
		S.Set("Speed Hack Speed", 0.5)
		local worst = 0
		for i = 1, math.min(#plainR, #slowR) do
			if plainR[i].Cframe and slowR[i].Cframe then worst = math.max(worst, math.abs(plainR[i].Cframe[2] - slowR[i].Cframe[2])) end
		end
		check(M.jumpPushes > 3, "4x, the jump can't be ended: Roblox pushes again (" .. M.jumpPushes .. " pushes)")
		check(#plainR == #slowR and worst <= 0.002, "4x, the jump can't be ended: the same heights every frame (" .. worst .. ")")
	end
	-- coyote time: walk off the floor's edge (x = 6), jump k frames later (in game time the same for every speed)
	M.floorEdgeX = 6
	local function ledge(k)
		return function()
			-- (facing the way it walks: turning is checked above)
			local ev = { [1] = function()
				hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + Vector3.new(1, 0, 0))
				hum.MoveDirection = Vector3.new(1, 0, 0)
			end }
			local left = nil
			for i = 2, 260 do
				ev[i] = function()
					if not left and hrp.Position.X >= 6 then left = i end
					if left and i == left + k then hum.Jump = true end
				end
			end
			return ev
		end
	end
	local function jumped(r)
		for _, fr in ipairs(r) do
			if fr.State == Enum.HumanoidStateType.Jumping.Value then return true end
		end
		return false
	end
	for _, s in ipairs({ 0.5, 2, 4 }) do
		-- (at s, frames of s/120 game seconds: k frames = k s / 120 s)
		local inside = math.max(1, math.floor(0.06 * 120 / s))
		local outside = math.ceil(0.2 * 120 / s)
		local frames = {}
		for i = 1, 260 do frames[i] = 1 / 120 end
		local pIn, sIn = compare(s .. "x coyote jump inside the window", s, ledge(inside), frames)
		check(jumped(pIn) and jumped(sIn), s .. "x: a jump " .. inside .. " frames after leaving the floor works at both speeds")
		if s < 1 then
			-- 0.1 s of game time after leaving: Roblox's own window (0.13 s of real time = 0.065 s of game time) is
			-- over, the game's isn't
			local late = math.floor(0.1 * 120 / s)
			local pL, sL = compare(s .. "x coyote jump after Roblox's own window", s, ledge(late), frames)
			check(jumped(pL) and jumped(sL), s .. "x: a jump " .. late .. " frames after leaving the floor works at both speeds")
		end
		local pOut, sOut = compare(s .. "x coyote jump after the window", s, ledge(outside), frames)
		check(not jumped(pOut) and not jumped(sOut), s .. "x: a jump " .. outside .. " frames after leaving doesn't work at either speed")
	end
	-- the edge of the window: a jump k frames after leaving the floor works at s exactly when it works at normal
	-- speed, for every k from 0.11 to 0.14 s of game time (a frame: one real step, s / 240 s of game time)
	for _, s in ipairs({ 0.5, 2 }) do
		local frames = {}
		for i = 1, 300 do frames[i] = s / 240 end
		local slowFrames = {}
		for i = 1, 300 do slowFrames[i] = 1 / 240 end
		local differ = {}
		local seenYes, seenNo = false, false
		for k = math.floor(0.11 * 240 / s), math.ceil(0.14 * 240 / s) do
			S.Set("Speed Hack", 0)
			local pR = record(frames, 1, ledge(k)())
			S.Set("Speed Hack", 1)
			S.Set("Speed Hack Speed", s)
			local sR = record(slowFrames, 1, ledge(k)())
			S.Set("Speed Hack Speed", 0.5)
			if jumped(pR) ~= jumped(sR) then differ[#differ + 1] = k end
			if jumped(pR) then seenYes = true else seenNo = true end
		end
		check(seenYes and seenNo, s .. "x: the sweep crosses the end of the window")
		check(#differ == 0, s .. "x: a jump works at the same frames after leaving as at normal speed (differ: " .. table.concat(differ, ", ") .. ")")
	end
	-- the coyote timer across a pause: paused `off` s of game time after leaving the floor, 5 s later unpaused,
	-- a jump `after` s of game time later works only if off + after is inside the window (0.125 s). At 0.5x
	-- Roblox's own window (real time) is over when it pauses, so only the restored timer can make the jump.
	local function coyotePause(s, off, after)
		key(Enum.KeyCode.One)
		steps(2)
		C.data = {}
		C.DataChanged()
		hum.MoveDirection = Vector3.zero
		hrp.CFrame = CFrame.new(0, 3, 0)
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
		hum.WalkSpeed, hum.JumpPower = 16, 50
		hum.Jump = false
		M.resetHumanoidModel()
		M.resetRobloxController()
		steps(2)
		S.Set("Speed Hack", s == 1 and 0 or 1)
		S.Set("Speed Hack Speed", s)
		key(Enum.KeyCode.Two)
		steps(2)
		click()
		hum.MoveDirection = Vector3.new(1, 0, 0)
		local gt, left = 0, nil
		for _ = 1, 2000 do
			M.step(1 / 240)
			gt = gt + s / 240
			if not left and hrp.Position.X >= 6 then left = gt end
			if left and gt - left >= off - 1e-9 then break end
		end
		click() -- Pause
		for _ = 1, 300 do M.step(1 / 60) end
		local n0 = #C.data
		click() -- Unpause
		gt = 0
		while gt < after - 1e-9 do M.step(1 / 240); gt = gt + s / 240 end
		hum.Jump = true
		for _ = 1, 60 do M.step(1 / 240) end
		hum.Jump = false
		click()
		steps(2)
		S.Set("Speed Hack", 1)
		S.Set("Speed Hack Speed", 0.5)
		for i = n0 + 1, #C.data do
			if C.data[i].State == Enum.HumanoidStateType.Jumping.Value then return true end
		end
		return false
	end
	for _, s in ipairs({ 1, 0.5 }) do
		check(coyotePause(s, 0.08, 0), s .. "x: paused 0.08 s after leaving the floor, 5 s later: a jump right away still works")
		check(not coyotePause(s, 0.08, 0.06), s .. "x: paused 0.08 s after leaving the floor: a jump 0.06 s after unpausing (0.14 s) doesn't")
	end
	M.floorEdgeX = nil
	hum.Jump = false
	-- 4x: gravity x 16 = 3139, Roblox keeps workspace.Gravity at 1000: the rest is added in the air
	S.Set("Speed Hack", 1)
	S.Set("Speed Hack Speed", 4)
	local seenG
	record({ table.unpack(FR, 1, 20) }, 1, { [10] = function() seenG = { workspace.Gravity, SH.Humanoid.Extra() } end })
	near(seenG[1], 1000, 1e-6, "4x: workspace.Gravity at its limit 1000")
	near(seenG[2], G0 * 16 - 1000, 1e-3, "4x: the rest of the gravity is added in the air (" .. tostring(seenG[2]) .. ")")
	eq(SH.Humanoid.Extra(), 0, "paused: nothing added")
	S.Set("Speed Hack Speed", 0.5)
	M.robloxController = true
end


section("the coyote timer of the frame unpaused from (going back first)")
-- walk off the edge, pause well after the window, go back to the frame 0.06 s of game time after leaving the
-- floor, unpause, jump at once: the timer is that frame's (CY), so the jump works
M.floorEdgeX = 6
local function coyoteBack(s)
	key(Enum.KeyCode.One)
	steps(2)
	C.data = {}
	hum.MoveDirection = Vector3.zero
	hrp.CFrame = CFrame.new(0, 3, 0)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	hum.WalkSpeed, hum.JumpPower = 16, 50
	hum.Jump = false
	M.resetHumanoidModel()
	M.resetRobloxController()
	steps(2)
	S.Set("Speed Hack", s == 1 and 0 or 1)
	S.Set("Speed Hack Speed", s)
	key(Enum.KeyCode.Two)
	steps(2)
	click()
	hum.MoveDirection = Vector3.new(1, 0, 0)
	local gt, left = 0, nil
	for _ = 1, 2000 do
		M.step(1 / 240)
		gt = gt + s / 240
		if not left and hrp.Position.X >= 6 then left = gt end
		if left and gt - left >= 0.3 - 1e-9 then break end
	end
	click() -- Pause
	steps(10)
	local data = C.data
	local leftF = nil
	for i = 1, #data do if not leftF and data[i].Cframe[1] >= 6 then leftF = i end end
	local tLeft = data[leftF].TotalTime
	local target = leftF
	while data[target + 1] and data[target + 1].TotalTime - tLeft <= 0.06 + 1e-9 do target = target + 1 end
	local g = 0
	while E.frame > target and g < 400 do key(Enum.KeyCode.F); steps(4); g = g + 1 end
	local n0 = E.frame
	hum.MoveDirection = Vector3.zero
	click() -- Unpause
	hum.Jump = true
	for _ = 1, 60 do M.step(1 / 240) end
	hum.Jump = false
	click()
	steps(2)
	S.Set("Speed Hack", 1)
	S.Set("Speed Hack Speed", 0.5)
	local after = C.data
	for i = n0 + 1, #after do
		if after[i].State == Enum.HumanoidStateType.Jumping.Value then return true, n0 end
	end
	return false, n0
end
for _, s in ipairs({ 1, 0.5 }) do
	local ok, at = coyoteBack(s)
	check(ok, s .. "x: back to 0.06 s after leaving the floor, unpaused: a jump works (from frame " .. tostring(at) .. ")")
end
M.floorEdgeX = nil
hum.Jump = false

finish()
