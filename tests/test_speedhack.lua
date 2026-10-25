-- ================================================================================================
-- Speed hack (V2.38.13): slow motion while recording in Create mode, saved in normal time.
--   * a TAS recorded at speed s with real frames dt is the same TAS as one recorded at normal speed with
--     frames dt x s (positions, velocities, times, animation speeds, jump timer), at uneven frame rates
--   * gravity x s^2, WalkSpeed / JumpPower x s while recording, normal again while paused, in Idle / Test
--   * JumpHeight jumps (UseJumpPower off) reach the same height
--   * the speed or the switch changed while recording: the motion goes on (momentum scaled)
--   * a value the game writes while slowed becomes the new normal value (WalkSpeed, gravity)
--   * dead: normal time; a new character gets its own normal values
--   * Test plays a slow recording at normal speed; Unload puts everything back
--   * settings rows, the Toggle Speed Hack control (never recorded), stats row, saved settings
-- (headless mock with a small humanoid model, not a real game)
-- ================================================================================================
check(boot(30), "boots")
local S, Core, SH, Controls = __T.Settings, __T.Core, __T.SpeedHack, __T.Controls
local C = Core.State
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
	__T.Bridge.SetAnimation({ Pose = 2, JumpTime = 0, Speed = 1 }, { { 1, 0 } }, 1)
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

section("off by default: nothing changes")
eq(S.Get("Speed Hack"), 0, "Speed Hack off by default")
eq(S.Get("Speed Hack Speed"), 0.5, "speed 0.5 by default")
local plain = record(DTS, 0.5, walkThenJump())
eq(SH.scale, 1, "factor 1")
check(#plain >= 230, "recorded (" .. #plain .. " frames)")

section("a slow recording is the TAS a normal recording with shorter frames makes")
S.Set("Speed Hack", 1)
eq(SH.scale, 1, "switching it on while not recording changes nothing yet")
eq(workspace.Gravity, G0, "gravity untouched")
local ev = walkThenJump()
local walkSpeedSeen, gravSeen, jumpSeen, trackSeen = nil, nil, nil, nil
ev[30] = function()
	walkSpeedSeen, gravSeen, jumpSeen = hum.WalkSpeed, workspace.Gravity, hum.JumpPower
	local t = walkTrack()
	trackSeen = t and t.Speed
end
local slow = record(DTS, 1, ev)
near(walkSpeedSeen, 8, 1e-9, "recording: WalkSpeed x 0.5")
near(jumpSeen, 25, 1e-9, "recording: JumpPower x 0.5")
near(gravSeen, G0 * 0.25, 1e-6, "recording: gravity x 0.25")
near(trackSeen, (16 / 14.5) * 0.5, 1e-6, "recording: the walk animation plays at half its speed")
sameTAS(plain, slow, "0.5x at real frames dt vs 1x at frames dt x 0.5", 2)
-- the recorded time is normal time: the slow run took twice as long in real time
local realT = 0
for i = 1, #slow do realT = realT + DTS[i] end
near(slow[#slow].TotalTime, realT * 0.5, 1e-4, "TAS time = half the real recording time")
section("paused: everything normal again")
eq(C.paused, true, "paused")
eq(SH.scale, 1, "factor 1 while paused")
near(hum.WalkSpeed, 16, 1e-9, "WalkSpeed back")
near(hum.JumpPower, 50, 1e-9, "JumpPower back")
near(workspace.Gravity, G0, 1e-9, "gravity back")
local wt = walkTrack()
check(wt == nil or wt.Speed ~= (16 / 14.5) * 0.5, "the walk track isn't left at the slow speed")

section("other speeds, uneven frames")
S.Set("Speed Hack Speed", 0.25)
local slowQ = record(DTS, 1, walkThenJump())
S.Set("Speed Hack", 0)
local plainQ = record(DTS, 0.25, walkThenJump())
S.Set("Speed Hack", 1)
sameTAS(plainQ, slowQ, "0.25x", 2)
S.Set("Speed Hack Speed", 0.5)

section("fast motion (speeds above 1): the TAS a normal recording with longer frames makes")
S.Set("Speed Hack Speed", 2)
local evF = walkThenJump()
local seenF = {}
evF[30] = function()
	seenF.walk, seenF.jump, seenF.grav, seenF.rate = hum.WalkSpeed, hum.JumpPower, workspace.Gravity, __T.Bridge.timeRate
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
eq(__T.Bridge.timeRate, 1, "zoom spring at normal speed when paused")
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
	seenS.walk, seenS.grav, seenS.scale, seenS.rate = hum.WalkSpeed, workspace.Gravity, SH.scale, __T.Bridge.timeRate
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
evB[1] = function() z0, k0 = boxF.Position.Z, __T.KitClock.Now() end
evB[40] = function() z1, k1 = boxF.Position.Z, __T.KitClock.Now() end
local boxRec = record(fixed, 1, evB)
near(z1 - z0, 6 * 20 / 60, 1e-6, "the box moved on the 20 steps that ran only")
near(boxF.AssemblyLinearVelocity.Z, 6, 1e-9, "the box keeps its velocity")
eq(boxF.Anchored, false, "the box isn't left anchored")
near(k1 - k0, 20 / 60, 1e-6, "the kit's clock moved on by the 20 steps that ran")
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

section("JumpHeight jumps (UseJumpPower off) reach the same height")
hum.UseJumpPower = false
S.Set("Speed Hack", 0)
local plainH = record(DTS, 0.5, jumpAt(10))
S.Set("Speed Hack", 1)
local jh0 = hum.JumpHeight
local slowH = record(DTS, 1, jumpAt(10))
eq(hum.JumpHeight, jh0, "JumpHeight is never changed")
sameTAS(plainH, slowH, "JumpHeight jump", 1)
local topP, topS = 0, 0
for _, f in ipairs(plainH) do if f.Cframe then topP = math.max(topP, f.Cframe[2]) end end
for _, f in ipairs(slowH) do if f.Cframe then topS = math.max(topS, f.Cframe[2]) end end
check(topP > 7 and math.abs(topP - topS) < 0.002, "same jump height (" .. topP .. " / " .. topS .. ")")
hum.UseJumpPower = true

section("slow motion starting / stopping in mid-air keeps the jump going")
-- A: normal speed all along. B: the same jump, 0.5x from frame 70 (rising) to frame 100 (falling); B's real
-- frames are DTS x 0.5 at normal speed and DTS while slowed, so both record the same normal-time frames
local seen = {}
S.Set("Speed Hack", 0)
local realA, realB = {}, {}
for i = 1, 160 do
	realA[i] = DTS[i] * 0.5
	realB[i] = (i >= 70 and i < 100) and DTS[i] or DTS[i] * 0.5
end
local airA = record(realA, 1, jumpAt(40))
local evB = jumpAt(40)
evB[70] = function() S.Set("Speed Hack", 1); seen.vy70 = hrp.AssemblyLinearVelocity.Y end
evB[71] = function() seen.vy71 = hrp.AssemblyLinearVelocity.Y end
evB[100] = function() S.Set("Speed Hack", 0) end
local airB = record(realB, 1, evB)
check(seen.vy70 > 5, "frame 70 is in the rising part of the jump (" .. tostring(seen.vy70) .. ")")
check(math.abs(seen.vy71 - (seen.vy70 * 0.5 - G0 * 0.25 * DTS[70])) < 1e-6, "the vertical speed is halved when the slow motion starts")
sameTAS(airA, airB, "slow motion on / off in mid-air")
-- paused in mid-air, switched on while paused, unpaused: the jump goes on (the velocity HappaTAS puts back
-- on the character is the recorded normal one: x 0.5 when the slow motion starts)
local paused = record(realA, 1, jumpAt(140)) -- ends 20 frames after the jump: in mid-air
local last = paused[#paused]
check(last.Velocity.Linear[2] > 5, "paused in mid-air, rising (" .. last.Velocity.Linear[2] .. ")")
S.Set("Speed Hack", 1)
click() -- Unpause (continues the same TAS)
for i = 1, 6 do M.step(DTS[i]) end
click()
steps(2)
local after = C.data[#paused + 1]
local expect = last.Velocity.Linear[2] - G0 * after.FrameTime
check(after and math.abs(after.Velocity.Linear[2] - expect) < 0.01, "after unpausing at 0.5x the jump goes on: vy " .. tostring(after and after.Velocity.Linear[2]) .. " (" .. expect .. ")")
S.Set("Speed Hack Speed", 0.5)

section("speed changed / switched off while recording: the motion goes on")
local ev2 = {
	[1] = function() hum.MoveDirection = Vector3.new(1, 0, 0) end,
	[40] = function() seen.v40 = hrp.AssemblyLinearVelocity.X; S.Set("Speed Hack Speed", 0.25) end,
	[42] = function() seen.v42 = hrp.AssemblyLinearVelocity.X; seen.w42 = hum.WalkSpeed; seen.g42 = workspace.Gravity end,
	[80] = function() S.Set("Speed Hack", 0) end,
	[82] = function() seen.v82 = hrp.AssemblyLinearVelocity.X; seen.w82 = hum.WalkSpeed; seen.g82 = workspace.Gravity end,
}
local mixed = record({ table.unpack(DTS, 1, 120) }, 1, ev2)
near(seen.v40, 8, 1e-6, "0.5x: moving at 8")
near(seen.v42, 4, 1e-6, "0.25x: moving at 4")
near(seen.w42, 4, 1e-9, "0.25x: WalkSpeed 4")
near(seen.g42, G0 / 16, 1e-6, "0.25x: gravity / 16")
near(seen.v82, 16, 1e-6, "off: moving at 16 again")
near(seen.w82, 16, 1e-9, "off: WalkSpeed 16")
near(seen.g82, G0, 1e-9, "off: normal gravity")
local maxV, minV = 0, 1e9
for i = 12, #mixed do -- (from a standing start the walk takes a few frames to reach full speed)
	local vx = mixed[i].Velocity.Linear[1]
	maxV, minV = math.max(maxV, vx), math.min(minV, vx)
end
near(maxV, 16, 1e-3, "recorded velocity always the normal 16 (max)")
near(minV, 16, 1e-3, "recorded velocity always the normal 16 (min)")
local f60, f100 = mixed[60], mixed[100]
near(f60.FrameTime, r(DTS[60] * 0.25, 1000000), 2e-6, "0.25x frame time")
near(f100.FrameTime, r(DTS[100], 1000000), 2e-6, "normal frame time after switching off")
S.Set("Speed Hack", 1)
S.Set("Speed Hack Speed", 0.5)

section("values the game writes while slowed become the normal ones")
local ev3 = {
	[1] = function() hum.MoveDirection = Vector3.new(1, 0, 0) end,
	[20] = function() hum.WalkSpeed = 32 end, -- a speed pad
	[22] = function() seen.w22 = hum.WalkSpeed end,
	[28] = function() seen.v22 = hrp.AssemblyLinearVelocity.X end, -- (the walk speeds up over a few frames)
	[30] = function() workspace.Gravity = 100 end, -- a gravity change
	[32] = function() seen.g32 = workspace.Gravity end,
}
local padded = record({ table.unpack(DTS, 1, 60) }, 1, ev3)
near(seen.w22, 16, 1e-6, "WalkSpeed 32 from the game -> 16 while slowed")
near(seen.v22, 16, 1e-2, "moving at 16 (= 32 at normal speed)")
near(padded[40].Velocity.Linear[1], 32, 1e-3, "recorded velocity 32")
near(seen.g32, 25, 1e-6, "gravity 100 from the game -> 25 while slowed")
near(hum.WalkSpeed, 32, 1e-6, "paused: the game's WalkSpeed 32 stays")
near(workspace.Gravity, 100, 1e-6, "paused: the game's gravity 100 stays")
workspace.Gravity = G0
hum.WalkSpeed = 16

section("bounce pads (EToH kit): the pad's Power is a velocity, x s while slowed")
-- the kit keeps a pad's configuration as a plain table (Utility/Config GetConfig) and its Touched handler
-- sets the character's velocity to Power itself: the same bounce in TAS time at any speed
do
	local padInst = Instance.new("Configuration")
	padInst.Name = "BouncePadConfiguration"
	local other = Instance.new("Configuration")
	other.Name = "BoosterConfiguration" -- (a speed booster's Power is a WalkSpeed: left alone)
	local padCfg = { __instance = padInst, __defaults = {}, Power = 100, Cooldown = 0.05, RelativeForce = false }
	local boostCfg = { __instance = other, __defaults = {}, Power = 32 }
	M.gcTables[#M.gcTables + 1] = padCfg
	M.gcTables[#M.gcTables + 1] = boostCfg
	local function bounceAt(k)
		return { [k] = function()
			local v = hrp.AssemblyLinearVelocity
			hrp.AssemblyLinearVelocity = Vector3.new(v.X, padCfg.Power, v.Z)
		end }
	end
	S.Set("Speed Hack", 0)
	local plainB = record(DTS, 0.5, bounceAt(10))
	S.Set("Speed Hack", 1)
	local seenP, seenB
	local evB = bounceAt(10)
	evB[5] = function() seenP, seenB = padCfg.Power, boostCfg.Power end
	local slowB = record(DTS, 1, evB)
	near(seenP, 50, 1e-9, "recording at 0.5x: the pad's Power is 50")
	eq(seenB, 32, "a booster's Power is not touched")
	sameTAS(plainB, slowB, "bounce pad at 0.5x")
	local topP, topS = 0, 0
	for _, f in ipairs(plainB) do if f.Cframe then topP = math.max(topP, f.Cframe[2]) end end
	for _, f in ipairs(slowB) do if f.Cframe then topS = math.max(topS, f.Cframe[2]) end end
	check(topP > 20 and math.abs(topP - topS) < 0.002, "same bounce height (" .. topP .. " / " .. topS .. ")")
	eq(padCfg.Power, 100, "paused: Power 100 again")
	-- the kit writes a new Power while slowed (the pad's attribute changed): that is the new normal value
	local seen2
	local ev2b = {
		[5] = function() padCfg.Power = 80 end,
		[8] = function() seen2 = padCfg.Power end,
	}
	record({ table.unpack(DTS, 1, 20) }, 1, ev2b)
	near(seen2, 40, 1e-9, "the kit's own Power 80 while slowed -> 40")
	eq(padCfg.Power, 80, "paused: the kit's Power 80 stays")
	padCfg.Power = 100
	-- a pad the kit sets up while the speed hack is on is found too
	local lateInst = Instance.new("Configuration")
	lateInst.Name = "BouncePadConfiguration"
	local lateCfg = { __instance = lateInst, __defaults = {}, Power = 60 }
	local seen3
	local ev3b = {
		[3] = function()
			M.gcTables[#M.gcTables + 1] = lateCfg
			lateInst.Parent = workspace
		end,
		[100] = function() seen3 = lateCfg.Power end,
	}
	record({ table.unpack(DTS, 1, 110) }, 1, ev3b)
	near(seen3, 30, 1e-9, "a pad added while recording: Power 60 -> 30")
	eq(lateCfg.Power, 60, "paused: Power 60 again")
	lateInst:Destroy()
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

section("Idle and Test: normal speed")
key(Enum.KeyCode.One)
hum.MoveDirection = Vector3.new(1, 0, 0)
steps(5)
eq(SH.scale, 1, "Idle: factor 1")
near(hum.WalkSpeed, 16, 1e-9, "Idle: WalkSpeed 16")
near(workspace.Gravity, G0, 1e-9, "Idle: normal gravity")
hum.MoveDirection = Vector3.zero
-- Test plays the slow recording at normal speed
C.data = slow
C.DataChanged()
key(Enum.KeyCode.Three)
steps(1)
eq(C.mode, 3, "testing")
local t0, frames, gTest = M.now, 0, true
while C.mode == 3 and frames < 2000 do
	M.step(1 / 60)
	frames = frames + 1
	if workspace.Gravity ~= G0 or SH.scale ~= 1 then gTest = false end
end
check(gTest, "Test: normal gravity and factor 1 all along")
near(M.now - t0, slow[#slow].TotalTime, 0.05, "Test takes the TAS time (half the real recording time)")

section("dead: normal time, a new character gets its own values")
local ev4 = {
	[1] = function() hum.MoveDirection = Vector3.new(1, 0, 0) end,
	[20] = function() hum.Health = 0 end,
	[22] = function() seen.gDead = workspace.Gravity; seen.sDead = SH.scale end,
}
local dead = record({ table.unpack(DTS, 1, 40) }, 1, ev4)
near(seen.gDead, G0, 1e-9, "dead: normal gravity")
eq(seen.sDead, 1, "dead: factor 1")
near(dead[30].FrameTime, r(DTS[30], 1000000), 2e-6, "dead: frames in real time (the respawn wait isn't shortened)")
hum.Health = 100
-- a new character while recording
key(Enum.KeyCode.Two)
steps(2)
click()
steps(5)
eq(SH.scale, 0.5, "recording again at 0.5x")
local oldHum = hum
local newChar = M.makeCharacter(Vector3.new(0, 3, 10))
M.player.CharacterAdded:Fire(newChar)
steps(10)
hum, hrp = C.Humanoid, C.HRP
check(hum ~= oldHum, "new humanoid")
near(hum.WalkSpeed, 8, 1e-9, "new character: its own WalkSpeed 16 x 0.5")
click()
steps(2)
near(hum.WalkSpeed, 16, 1e-9, "new character: 16 again when paused")

section("settings, control, stats")
local list = C.Gui.MainMenu.SettingsFrame.List
check(list:FindFirstChild("Section_Speed Hack") ~= nil, "Settings: a Speed Hack section")
check(list:FindFirstChild("Speed Hack") and list["Speed Hack"]:FindFirstChild("Switch") ~= nil, "Settings: on / off switch")
check(list:FindFirstChild("Speed Hack Speed") and list["Speed Hack Speed"]:FindFirstChild("Input") ~= nil, "Settings: speed box")
local box = list["Speed Hack Speed"].Input
eq(box.Text, "0.5", "the box shows the speed")
eq(S.Set("Speed Hack Speed", 0.05), true, "below 0.1 is allowed in...")
eq(S.Get("Speed Hack Speed"), 0.1, "...and clamped to 0.1")
S.Set("Speed Hack Speed", 3)
eq(S.Get("Speed Hack Speed"), 3, "3x allowed")
S.Set("Speed Hack Speed", 9)
eq(S.Get("Speed Hack Speed"), 4, "above 4 clamped to 4")
check(list:FindFirstChild("Speed Hack Frame Step") and list["Speed Hack Frame Step"]:FindFirstChild("Switch") ~= nil, "Settings: Frame Step switch")
S.Set("Speed Hack Speed", 1)
eq(SH.Wanted(), 1, "speed 1 = off")
S.Set("Speed Hack Speed", 0.5)
local ctl = C.Gui.MainMenu.ControlsFrame.List:FindFirstChild("Toggle Speed Hack")
check(ctl ~= nil, "Controls: Toggle Speed Hack row")
eq(ctl and ctl.Key.Text, "None", "no key by default")
Controls.Set("Toggle Speed Hack", "H")
local before = S.Get("Speed Hack")
key(Enum.KeyCode.H)
steps(2)
eq(S.Get("Speed Hack"), 1 - before, "the key switches it")
key(Enum.KeyCode.H)
steps(2)
eq(S.Get("Speed Hack"), before, "and back")
-- the key is never recorded
key(Enum.KeyCode.Two)
steps(2)
click()
steps(3)
key(Enum.KeyCode.H)
steps(3)
key(Enum.KeyCode.H)
steps(3)
click()
steps(2)
local hRecorded = false
for _, fr in ipairs(C.data) do
	for _, e in ipairs(fr.Input or {}) do if e == 8 or e == -8 then hRecorded = true end end
end
check(not hRecorded, "the Toggle Speed Hack key is not recorded")
eq(S.Get("Speed Hack"), before, "switched twice while recording")
S.Set("Show Stats (Create)", 1)
steps(3)
local row = C.Gui.CreateStats:FindFirstChild("1")
check(row and row.Text:find("Speed Hack 0.5x", 1, true) ~= nil, "Create stats: the speed shows (" .. tostring(row and row.Text) .. ")")
S.Set("Speed Hack", 0)
steps(3)
check(row and row.Text:find("Speed Hack", 1, true) == nil, "Create stats: nothing when it is off")
S.Set("Speed Hack", 1)
steps(30)
local saved = M.fs["HappaTasPort/Settings.json"] or ""
check(saved:find("\"Speed Hack\":1", 1, true) ~= nil and saved:find("\"Speed Hack Speed\":0.5", 1, true) ~= nil, "saved in Settings.json")
check(saved:find("\"Toggle Speed Hack\":\"H\"", 1, true) ~= nil, "the key is saved")

section("Unload puts everything back")
key(Enum.KeyCode.Two)
steps(2)
hum.MoveDirection = Vector3.new(1, 0, 0)
click()
steps(10)
eq(SH.scale, 0.5, "recording at 0.5x")
near(workspace.Gravity, G0 * 0.25, 1e-6, "slowed gravity")
local vBefore = hrp.AssemblyLinearVelocity.X
getgenv().__HappaTAS.Unload()
near(workspace.Gravity, G0, 1e-9, "Unload: normal gravity")
near(hum.WalkSpeed, 16, 1e-9, "Unload: WalkSpeed 16")
near(hum.JumpPower, 50, 1e-9, "Unload: JumpPower 50")
near(hrp.AssemblyLinearVelocity.X, vBefore * 2, 1e-6, "Unload: the character goes on at normal speed")

finish()
