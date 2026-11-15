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
-- (walking and turning only: no timed humanoid state, so Frame Step runs and holds steps strictly by the slider)
local function walkTurn()
	return { [1] = function() hum.MoveDirection = Vector3.new(1, 0, 0) end, [150] = function() hum.MoveDirection = Vector3.new(0, 0, 1) end }
end
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
section("Frame Step: normal physics on every other frame, everything held on the others")
-- normal frame i <-> frame step frames 2i - 1 (physics runs) and 2i (held, the same dt). Even frames: Frame Step
-- banks time, so uneven ones change which frames run (that case: the timed-state section below)
local EVEN = 1 / 120
local N2 = 120
local fsDts, fsEv, wt2 = {}, {}, walkTurn()
for i = 1, N2 do
	fsDts[2 * i - 1], fsDts[2 * i] = EVEN, EVEN
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
for i = 1, N2 do dtsN2[i] = EVEN end
local plainS = record(dtsN2, 1, walkTurn())
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
local q4Dts, q4Ev, wt4 = {}, {}, walkTurn()
for i = 1, 60 do
	for k = 0, 3 do q4Dts[4 * i - 3 + k] = EVEN end
	if wt4[i] then q4Ev[4 * i - 3] = wt4[i] end
end
for k = 238, 240 do q4Dts[k] = nil end
local steppedQ = record(q4Dts, 1, q4Ev)
S.Set("Speed Hack", 0)
local dts60 = {}
for i = 1, 60 do dts60[i] = EVEN end
local plainQ4 = record(dts60, 1, walkTurn())
S.Set("Speed Hack", 1)
sameTAS(plainQ4, steppedQ, "Frame Step 0.25x")
S.Set("Speed Hack Speed", 0.5)

section("Frame Step: a step in one of the humanoid's timed states always runs")
-- (Roblox's humanoid keeps its timers through held steps; live at 0.1x / 0.5x there was no coyote jump even
-- 0.05 s after the edge, and Landed ran out 6x too soon. Coyote time here: the mock's off-floor timer)
do
	M.floorEdgeX = 6
	local function ledgeAt(gameT)
		local ev = { [1] = function()
			hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + Vector3.new(1, 0, 0))
			hum.MoveDirection = Vector3.new(1, 0, 0)
		end }
		local leftT = nil
		for i = 2, 900 do
			ev[i] = function()
				local n = E.tl:count()
				local t = n > 0 and E.tl:get("TotalTime", n, 1) or 0
				if not leftT and hrp.Position.X >= 6 then leftT = t end
				if leftT and t >= leftT + gameT then hum.Jump = true end
			end
		end
		return ev
	end
	local function jumpedIn(r)
		for _, fr in ipairs(r) do
			if fr.State == Enum.HumanoidStateType.Jumping.Value then return true end
		end
		return false
	end
	local frames = {}
	for i = 1, 900 do frames[i] = 1 / 240 end
	for _, s in ipairs({ 1, 0.5, 0.25 }) do
		S.Set("Speed Hack", s == 1 and 0 or 1)
		S.Set("Speed Hack Speed", s)
		check(jumpedIn(record(frames, 1, ledgeAt(0.06))), s .. "x: a jump 0.06 s of game time after leaving the floor works")
		check(not jumpedIn(record(frames, 1, ledgeAt(0.2))), s .. "x: one 0.2 s after doesn't")
	end
	M.floorEdgeX = nil
	local tops = {}
	for _, s in ipairs({ 1, 0.25 }) do
		S.Set("Speed Hack", s == 1 and 0 or 1)
		S.Set("Speed Hack Speed", s)
		local top = 0
		for _, fr in ipairs(record(frames, 1, jumpAt(20))) do if fr.Cframe then top = math.max(top, fr.Cframe[2]) end end
		tops[s] = top
	end
	check(tops[1] > 7 and math.abs(tops[1] - tops[0.25]) < 0.002, "a standing jump at 0.25x is as high as at 1x (" .. tops[0.25] .. " / " .. tops[1] .. ")")
	-- a held step moves no timer of HappaTAS's own: in the air the off-floor timer is the game time since the jump
	S.Set("Speed Hack Speed", 0.25)
	local seenOff = {}
	local evJ = jumpAt(20)
	for i = 21, 400 do
		evJ[i] = function()
			local n = E.tl:count()
			seenOff[#seenOff + 1] = { E.time.SH.Humanoid.coyote.off, n > 0 and E.tl:get("TotalTime", n, 1) or 0 }
		end
	end
	record(frames, 1, evJ)
	local first, worstOff = nil, 0
	for _, e in ipairs(seenOff) do
		if e[1] then
			first = first or (e[2] - e[1])
			worstOff = math.max(worstOff, math.abs((e[2] - first) - e[1]))
		elseif first then break end
	end
	check(first ~= nil and worstOff < 0.02, "0.25x: the off-floor timer follows game time in the air (worst off by " .. string.format("%.3f", worstOff) .. " s)")
	-- holding Back / Forward goes through the run's game time at the slider's speed (live, Frame Step 0.1x: one
	-- frame per rendered frame was 1.1 s of game time a second, 11x the recording speed)
	local walkR = { [1] = function() hum.MoveDirection = Vector3.new(1, 0, 0) end }
	local runB = record(frames, 1, walkR)
	local function tt(f) return E.tl:get("TotalTime", f, 1) end
	local f0 = E.frame
	E.modes:back()
	for _ = 1, 120 do M.step(1 / 240) end
	E.modes:release("back")
	local backT = tt(f0) - tt(E.frame)
	check(#runB > 100 and math.abs(backT - 0.5 * 0.25) < 0.01, "0.25x: holding Back for 0.5 s goes back 0.125 s of game time (" .. string.format("%.4f", backT) .. ")")
	local f1 = E.frame
	E.modes:forward()
	for _ = 1, 120 do M.step(1 / 240) end
	E.modes:release("forward")
	local fwdT = tt(E.frame) - tt(f1)
	check(math.abs(fwdT - 0.5 * 0.25) < 0.01, "0.25x: holding Forward the same (" .. string.format("%.4f", fwdT) .. ")")
	-- the game time follows the slider by time, not by counting physics events: frames of 1 and 3 steps in turn
	-- (counted, 0.5x ran only one kind and went 0.25x or 0.75x)
	local uneven = {}
	for i = 1, 600 do uneven[i] = (i % 2 == 1) and 1 / 240 or 3 / 240 end
	local walk = { [1] = function() hum.MoveDirection = Vector3.new(1, 0, 0) end }
	for _, s in ipairs({ 0.5, 0.25, 0.7 }) do
		S.Set("Speed Hack Speed", s)
		local r = record(uneven, 1, walk)
		local real = 0
		for i = 1, 600 do real = real + uneven[i] end
		local ratio = r[#r].TotalTime / real
		check(math.abs(ratio - s) < 0.02 * s + 0.005, s .. "x with frames of 1 and 3 steps: game time / real time " .. string.format("%.4f", ratio))
	end
	S.Set("Speed Hack", 1)
	S.Set("Speed Hack Speed", 0.5)
	M.floorEdgeX = nil
	hum.Jump = false
end

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
-- (as at 1x, a frame is the state a step starts from: the 20th step's result would be the frame the 21st starts from)
near(boxRec[#boxRec].TotalTime, 19 / 60, 1e-5, "TAS time = the time of the steps before the last frame's (" .. boxRec[#boxRec].TotalTime .. ")")
-- a part the game adds while frame stepping (a pushbox, a bullet) is held from the next held step on
local late = Instance.new("Part")
late.Name = "LateBox"
late.Anchored = false
late.CFrame = CFrame.new(60, 10, 0)
late.AssemblyLinearVelocity = Vector3.new(0, 0, 6)
local lz0, lz1
local evL = {}
evL[5] = function() late.Parent = CPf; M.freeParts[#M.freeParts + 1] = late end
evL[6] = function() lz0 = late.Position.Z end
evL[36] = function() lz1 = late.Position.Z end
record(fixed, 1, evL)
check(lz0 and lz1 and math.abs((lz1 - lz0) - 6 * 15 / 60) < 6 / 60 + 1e-6, "a part added while frame stepping moves on the steps that ran only (" .. tostring(lz1 and lz1 - lz0) .. ")")
-- a free part your character touches (a platform it pushes or stands on) is held with it like every other: with
-- the humanoid frozen on the held steps their contact holds (live: the kit's Pushing Platform pushed as at 1x).
-- Before, every step ran while they touched: full speed on any loose platform
M.freeParts = {}
late:Destroy()
local touch = Instance.new("Part")
touch.Name = "Touched"
touch.Anchored = false
touch.Size = Vector3.new(2, 2, 2)
touch.CFrame = CFrame.new(1, 3, 0)
touch.AssemblyLinearVelocity = Vector3.new(0, 0, 6)
touch.Parent = CPf
M.freeParts = { touch }
local tz0, tz1
local evT = {}
evT[1] = function() tz0 = touch.Position.Z end
evT[11] = function() tz1 = touch.Position.Z end
record({ table.unpack(fixed, 1, 12) }, 1, evT)
check(tz0 and tz1 and math.abs((tz1 - tz0) - 6 * 5 / 60) < 6 / 60 + 1e-6, "a free part touching the character moves on the steps that ran only (" .. tostring(tz1 and tz1 - tz0) .. ")")
M.freeParts = {}
touch:Destroy()
boxF:Destroy()

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
for _, s in ipairs({ 1, 2 }) do
	local ok, at = coyoteBack(s)
	check(ok, s .. "x: back to 0.06 s after leaving the floor, unpaused: a jump works (from frame " .. tostring(at) .. ")")
end
M.floorEdgeX = nil
hum.Jump = false

section("1x: jump held through a pause in the air, the next jump is Roblox's")
-- (found live: on landing after a pause in the air with the jump held, HappaTAS made the jump itself as soon as it
-- saw the floor, still Landed, ~25 ms after touching it instead of Roblox's ~55 ms, at 75 FPS and up: Roblox makes
-- it once Jumping is enabled again. Slow motion is Frame Step: Roblox's own steps, the same there)
do
	local HC = E.time.SH.Humanoid
	local cy = HC.coyote
	local function landing(scale)
		local calls = {}
		local fakeHum = { Jump = true, FloorMaterial = Enum.Material.Plastic }
		function fakeHum:GetState() return Enum.HumanoidStateType.Landed end
		function fakeHum:ChangeState(st) calls[#calls + 1] = st end
		function fakeHum:SetStateEnabled() end
		local fakeRoot = { Parent = workspace, Anchored = false, AssemblyLinearVelocity = Vector3.zero }
		local saved = E.time.SH.scale
		E.time.SH.scale = scale
		cy.off, cy.jumped, cy.restored, cy.disabled, cy.vy0 = 0.5, true, true, true, 0
		HC.Post(1 / 240, fakeHum, fakeRoot, true)
		E.time.SH.scale = saved
		cy.disabled = false
		local jumps = 0
		for _, st in ipairs(calls) do if st == Enum.HumanoidStateType.Jumping then jumps = jumps + 1 end end
		return jumps, cy.off
	end
	local j1, off1 = landing(1)
	eq(off1, nil, "1x: the landing ends the timer")
	eq(j1, 0, "1x: HappaTAS makes no jump on landing (Roblox does)")
end

-- (Roblox's Landed state, real-time, as measured live: the mock models it from here on)
local function stateTimes(run, a, b)
	-- the game time from the first frame in state a to the first frame after it in state b
	local ta
	for _, fr in ipairs(run) do
		if not ta and fr.State == a.Value then ta = fr.TotalTime end
		if ta and fr.State == b.Value then return fr.TotalTime - ta end
	end
	return nil
end
local LANDED, RUNNING = Enum.HumanoidStateType.Landed, Enum.HumanoidStateType.Running

section("Frame Step: no freeze after a jump or a landing (the forced steps aren't paid back)")
-- (live, 0.1x: every step of the jump's push and of Landed ran, then everything was held until that time was paid
-- back: 131 ms frozen in the air after a jump, 486 ms after a landing)
do
	M.landedTime = 0.05
	S.Set("Speed Hack", 1)
	S.Set("Speed Hack Speed", 0.25)
	local frames = {}
	for i = 1, 700 do frames[i] = 1 / 240 end
	local log = {}
	local orig = E.time.stepBegin
	E.time.stepBegin = function(self, dt) local r = orig(self, dt); log[#log + 1] = r; return r end
	local run = record(frames, 1, jumpAt(20))
	E.time.stepBegin = orig
	local held, worst = 0, 0
	for i = 30, #log do
		if log[i] == false then held = held + 1; if held > worst then worst = held end else held = 0 end
	end
	local landed = stateTimes(run, LANDED, RUNNING)
	check(landed ~= nil and math.abs(landed - 0.05) < 0.005, "0.25x: the landing takes 0.05 s of game time, as at 1x (" .. tostring(landed) .. ")")
	check(worst <= 3, "0.25x: never more than the slider's 3 held steps in a row after the jump and the landing (" .. worst .. ")")
	M.landedTime = nil
	S.Set("Speed Hack Speed", 0.5)
end

section("Frame Step: the humanoid itself is frozen for the held steps, nothing is run at full speed")
-- (live: with Humanoid.EvaluateStateMachine off for the held steps a jump at 0.1x / 0.25x went Running > Jumping >
-- Freefall > Landed > Running at the same game times as at 1x, Landed 50 ms, apex 7.49 studs, with every held step
-- held. Before, the humanoid's timers ran on through the held steps, so every step of a jump's push, of Landed and of
-- the coyote time was run at full speed: a stall and a snap before each landing)
do
	M.landedTime = 0.05
	S.Set("Speed Hack", 1)
	S.Set("Speed Hack Speed", 0.25)
	local frames = {}
	for i = 1, 1000 do frames[i] = 1 / 240 end
	local log = {}
	local orig = E.time.stepBegin
	E.time.stepBegin = function(self, dt) local r = orig(self, dt); log[#log + 1] = r; return r end
	-- (frame 21 runs: 1, 5, 9 ... ; the 6th step of the game. The physics steps of the recording only: paused, the
	-- character is anchored by the pause)
	local evJ, elog, elogN = jumpAt(21), nil, 0
	evJ[1] = function() M.esmLog = {}; elog = M.esmLog end
	evJ[#frames] = function() elogN = #elog end
	local run = record(frames, 1, evJ)
	E.time.stepBegin = orig
	M.esmLog = nil
	local wrong, heldN = 0, 0
	for i = 1, elogN do
		local e = elog[i]
		if e[1] then heldN = heldN + 1 end
		if e[1] == e[2] then wrong = wrong + 1 end
	end
	check(heldN > 600, "0.25x: most steps are held (" .. heldN .. ")")
	eq(wrong, 0, "the humanoid is worked out on the steps that run, and frozen on every held one")
	local runs, total = 0, 0
	for i = 30, #log do
		total = total + 1
		if log[i] then runs = runs + 1 end
	end
	check(math.abs(runs / total - 0.25) < 0.005, "0.25x: one step in four runs, through the jump, the fall and the landing too ("
		.. string.format("%.4f", runs / total) .. ")")
	local landed = stateTimes(run, LANDED, RUNNING)
	check(landed ~= nil and math.abs(landed - 0.05) < 1e-4, "0.25x: Landed lasts 0.05 s of game time (" .. tostring(landed) .. ")")
	eq(hum.EvaluateStateMachine, true, "paused: the humanoid is worked out again")
	S.Set("Speed Hack", 0)
	local plainFrames = {}
	for i = 1, 250 do plainFrames[i] = 1 / 240 end
	local plain = record(plainFrames, 1, jumpAt(6))
	S.Set("Speed Hack", 1)
	local cut = {}
	for i = 1, #plain do cut[i] = run[i] end
	sameTAS(plain, cut, "a jump and its landing at 0.25x vs 1x")
	-- a frame is made and filled on a frame whose own step runs, right before that step, as at 1x (made on the
	-- first held frame after the step before, its state was a frame old: live, Freefall and Landed came a frame late)
	do
		local FS = E.time.SH.FS
		local made, madeHeld, unfilledHeld = 0, 0, 0
		local oAppend = E.tl.append
		E.tl.append = function(self, ...)
			if FS.on then
				made = made + 1
				if FS.plan == false then madeHeld = madeHeld + 1 end
			end
			return oAppend(self, ...)
		end
		local evF = { [1] = function() hum.MoveDirection = Vector3.new(1, 0, 0) end }
		for i = 2, 200 do
			evF[i] = function()
				local n = E.tl:count()
				if FS.on and n > 0 and not E.tl:isFilled(n) then unfilledHeld = unfilledHeld + 1 end
			end
		end
		local short = {}
		for i = 1, 200 do short[i] = 1 / 240 end
		record(short, 1, evF)
		E.tl.append = oAppend
		check(made >= 40, "0.25x: frames were made (" .. made .. ")")
		eq(madeHeld, 0, "none of them on a frame whose step is held")
		eq(unfilledHeld, 0, "and no frame waits unfilled through the held steps")
	end
	-- a jump tapped while the steps are held (the key down on frame 22, up again on 23; 25 is the next that runs)
	local tap = { [22] = function() hum.Jump = true end, [23] = function() hum.Jump = false end }
	local jumped = false
	for _, fr in ipairs(record(frames, 1, tap)) do
		if fr.State == Enum.HumanoidStateType.Jumping.Value then jumped = true end
	end
	check(jumped, "0.25x: a jump tapped during the held steps is made on the next step that runs")
	key(Enum.KeyCode.One)
	steps(2)
	eq(hum.EvaluateStateMachine, true, "Idle: the humanoid is worked out")
	M.landedTime = nil
	hum.Jump = false
	S.Set("Speed Hack Speed", 0.5)
end

section("Speed Hack In: Idle and / or Create")
do
	local function idleFor(n)
		key(Enum.KeyCode.One) -- Idle
		steps(2)
		hrp.CFrame = CFrame.new(0, 3, 0)
		hrp.AssemblyLinearVelocity = Vector3.zero
		local log = {}
		local orig = E.time.stepBegin
		E.time.stepBegin = function(self, dt) local r = orig(self, dt); log[#log + 1] = r; return r end
		local seen = { count0 = E.tl:count() }
		for i = 1, n do
			M.step(1 / 240)
			if i == math.floor(n / 2) then seen.g, seen.walk = workspace.Gravity, hum.WalkSpeed end
		end
		E.time.stepBegin = orig
		local held = 0
		for _, r in ipairs(log) do if r == false then held = held + 1 end end
		seen.held, seen.steps, seen.count1 = held, #log, E.tl:count()
		return seen
	end
	S.Set("Speed Hack", 1)
	-- Create only (the default): Idle stays normal
	E.settings:set("speedHackModes", "Create")
	S.Set("Speed Hack Speed", 0.5)
	local a = idleFor(40)
	eq(a.held, 0, "Create only, 0.5x: nothing held in Idle")
	-- Idle ticked, 0.5x: Frame Step in Idle (every other step held), nothing recorded
	E.settings:set("speedHackModes", "Idle,Create")
	local c = idleFor(40)
	eq(c.count1, c.count0, "Idle ticked: nothing recorded in Idle (the run keeps its frames)")
	check(c.held >= 18 and c.held <= 22, "Idle ticked, 0.5x: Frame Step holds every other step in Idle (" .. c.held .. " of " .. c.steps .. ")")
	near(c.g, G0, 1e-9, "Idle ticked, 0.5x: gravity normal (Frame Step scales nothing)")
	-- Idle only: recording is at normal speed
	E.settings:set("speedHackModes", "Idle")
	S.Set("Speed Hack Speed", 2)
	local seenG
	local evN = { [20] = function() seenG = workspace.Gravity end }
	local frames = {}
	for i = 1, 40 do frames[i] = 1 / 240 end
	local runN = record(frames, 1, evN)
	near(seenG, G0, 1e-9, "Idle only, 2x: gravity normal while recording in Create")
	near(runN[#runN].TotalTime, 39 / 240, 1 / 240 + 1e-6, "Idle only: the recording's frames are real time (" .. runN[#runN].TotalTime .. ")")
	-- back to normal on leaving Idle
	E.settings:set("speedHackModes", "Idle,Create")
	idleFor(10)
	key(Enum.KeyCode.Two) -- Create (paused)
	steps(3)
	near(workspace.Gravity, G0, 1e-9, "leaving Idle (Create, paused): gravity back to normal")
	near(hum.WalkSpeed, 16, 1e-9, "leaving Idle: WalkSpeed back to normal")
	E.settings:set("speedHackModes", "Create")
	S.Set("Speed Hack Speed", 0.5)
	key(Enum.KeyCode.One)
	steps(2)
end

section("Frame Step: a key let go between steps is in the frame the next step starts from (as at 1x)")
-- (live, a 0.1x walk: the key-up was written one frame late, into the frame after the step it stopped: the stop slide
-- looked one step shorter than at 1x, with the same physics)
do
	local W = Enum.KeyCode.W
	local function walkStop(at)
		local frames = {}
		for i = 1, 200 do frames[i] = 1 / 240 end
		local ev = {
			[2] = function() M.pressKey(W); hum.MoveDirection = Vector3.new(1, 0, 0) end,
			[at] = function() M.releaseKey(W); hum.MoveDirection = Vector3.zero end,
		}
		local run = record(frames, 1, ev)
		local keyAt, slowAt
		for i, fr in ipairs(run) do
			local inp = fr.Input
			if not keyAt and type(inp) == "table" then
				for _, e in ipairs(inp) do if e < 0 then keyAt = i end end
			end
			if keyAt and not slowAt and i > keyAt - 2 and fr.Velocity.Linear[1] < 15.99 then slowAt = i end
		end
		return keyAt, slowAt
	end
	S.Set("Speed Hack", 0)
	local k1, s1 = walkStop(120)
	check(k1 ~= nil and s1 == k1 + 1, "1x: the frame after the key-up is the first one slowing down (key " .. tostring(k1) .. ", slowing " .. tostring(s1) .. ")")
	S.Set("Speed Hack", 1)
	S.Set("Speed Hack Speed", 0.25)
	for _, at in ipairs({ 120, 121, 122, 123 }) do
		local k, sl = walkStop(at)
		check(k ~= nil and sl == k + 1, "0.25x, key-up before real frame " .. at .. ": the same (key " .. tostring(k) .. ", slowing " .. tostring(sl) .. ")")
	end
	S.Set("Speed Hack Speed", 0.5)
end

finish()
