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
	hum.WalkSpeed, hum.JumpPower = 16, 50
	-- every run starts from the same animation state (idle, no jump timer left from an earlier run)
	M.resetHumanoidModel()
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
local function sameTAS(a, b, label)
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
		if fa.State ~= fb.State then badState = badState + 1 end
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
sameTAS(plain, slow, "0.5x at real frames dt vs 1x at frames dt x 0.5")
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
sameTAS(plainQ, slowQ, "0.25x")
S.Set("Speed Hack Speed", 0.5)

section("JumpHeight jumps (UseJumpPower off) reach the same height")
hum.UseJumpPower = false
S.Set("Speed Hack", 0)
local plainH = record(DTS, 0.5, jumpAt(10))
S.Set("Speed Hack", 1)
local jh0 = hum.JumpHeight
local slowH = record(DTS, 1, jumpAt(10))
eq(hum.JumpHeight, jh0, "JumpHeight is never changed")
sameTAS(plainH, slowH, "JumpHeight jump")
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
for i = 3, #mixed do
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
	[22] = function() seen.w22 = hum.WalkSpeed; seen.v22 = hrp.AssemblyLinearVelocity.X end,
	[30] = function() workspace.Gravity = 100 end, -- a gravity change
	[32] = function() seen.g32 = workspace.Gravity end,
}
local padded = record({ table.unpack(DTS, 1, 60) }, 1, ev3)
near(seen.w22, 16, 1e-6, "WalkSpeed 32 from the game -> 16 while slowed")
near(seen.v22, 16, 1e-6, "moving at 16 (= 32 at normal speed)")
near(padded[40].Velocity.Linear[1], 32, 1e-3, "recorded velocity 32")
near(seen.g32, 25, 1e-6, "gravity 100 from the game -> 25 while slowed")
near(hum.WalkSpeed, 32, 1e-6, "paused: the game's WalkSpeed 32 stays")
near(workspace.Gravity, 100, 1e-6, "paused: the game's gravity 100 stays")
workspace.Gravity = G0
hum.WalkSpeed = 16

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
eq(S.Get("Speed Hack Speed"), 1, "above 1 clamped to 1")
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
