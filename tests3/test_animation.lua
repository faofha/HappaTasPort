-- ================================================================================================
-- HappaTAS 3, phase 2: the animation plugin (HappaTAS's R6 Animate engine, recorded per frame)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local guard = 0
while not (E.char:loaded() and E.anim.current) and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local UIS = M.services.UserInputService
local tl = E.tl
local A = E.anim
local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
local function click()
	UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	UIS.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
local function playing()
	local out = {}
	local animator = E.char.hum:FindFirstChildOfClass("Animator")
	for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do out[#out + 1] = tr end
	return out
end
local WALK = "http://www.roblox.com/asset/?id=180426354"

section("the game's Animate is switched off while HappaTAS's engine runs")
check(A.current ~= nil, "the engine runs")
local animate = M.player.Character:FindFirstChild("Animate")
eq(animate.Disabled, true, "Animate disabled")

section("walking: the walk animation at speed / 14.5")
E.char.hum.Running:Fire(16)
local tracks = playing()
eq(#tracks, 1, "one track")
eq(tracks[1].Animation.AnimationId, WALK, "walk")
near(tracks[1].Speed, 16 / 14.5, 1e-9, "speed 16 / 14.5")

section("running(speed): the walk animation from the humanoid clock's speed (V2.38.17)")
A:running(8)
near(playing()[1].Speed, 8 / 14.5, 1e-9, "speed 8 / 14.5")
A:running(16)
near(playing()[1].Speed, 16 / 14.5, 1e-9, "back to 16 / 14.5")

section("recording: the animation numbers and the second frame's start state")
key(Enum.KeyCode.Two)
M.steps(2)
click()
M.steps(4)
E.char.hum.Jumping:Fire(true)
M.steps(4)
click()
M.steps(2)
local fr2 = tl:toV2(2).Anim
eq(#fr2.Anims, 1, "frame 2 holds the animation playing at the start")
eq(fr2.Anims[1][1], 2, "walk = 2 (V2's numbers)")
eq(fr2.Anims[1][2], 0, "no transition")
local jumpFrame
for i = 3, tl:count() do
	local a = tl:toV2(i).Anim
	if #a.Anims > 0 and a.Anims[1][1] == 4 then jumpFrame = i end
end
check(jumpFrame ~= nil, "the jump (4) recorded on its frame")
local fj = tl:toV2(jumpFrame).Anim
eq(fj.Pose, 3, "pose Jumping = 3")
near(fj.JumpTime, 0.3, 0.02, "jump time 0.3 when it started")

section("paused: the animation holds still (speed 0)")
local tr = playing()[1]
eq(tr.Speed, 0, "track speed 0 while paused")

section("backtrack: the track goes back to the time it had on the frame")
key(Enum.KeyCode.F)
tr = playing()[1]
near(tr.TimePosition, tl:getList("AnimTime", E.frame) or -1, 1e-6, "TimePosition: the time the track had on the frame (" .. tostring(tr.TimePosition) .. ")")

section("Test plays the recorded animations at playback speed")
key(Enum.KeyCode.Three)
M.steps(3)
tr = playing()[1]
check(tr.Speed > 0, "playing")
local g = 0
while E.mode == 3 and g < 200 do M.step(1 / 60); g = g + 1 end
eq(E.mode, 1, "Test ended")

section("the track's own time is saved with each frame and comes back on rewind / in Test")
-- (live, the user's climb: rewinding gave a time worked out from frame times and speeds, not the one shown
-- when recording. Here the mock track moves like Roblox's: looped, 0.8 s long, so the frame-time sum, which
-- doesn't wrap, can't give it)
do
	key(Enum.KeyCode.One)
	M.steps(2)
	E.modes:setRun({})
	M.steps(1)
	key(Enum.KeyCode.Two)
	M.steps(2)
	click()
	M.steps(3)
	E.char.hum.Running:Fire(16)
	M.steps(1)
	local walk
	for _, t in ipairs(playing()) do if t.Animation.AnimationId == WALK then walk = t end end
	check(walk ~= nil, "walking")
	walk.Looped, walk.Length = true, 0.8
	local seenAt = {}
	for _ = 1, 90 do
		M.step(1 / 60)
		if walk.IsPlaying then walk.TimePosition = (walk.TimePosition + walk.Speed / 60) % walk.Length end
		seenAt[tl:count()] = walk.TimePosition
	end
	click()
	M.steps(2)
	local k = 70
	check(tl:getList("AnimTime", k) ~= nil, "frame " .. k .. " has its track time")
	E.modes:seek(1)
	M.steps(1)
	E.modes:seek(k)
	M.steps(1)
	near(walk.TimePosition, tl:getList("AnimTime", k), 1e-6, "back on frame " .. k .. ": the saved track time")
	near(tl:getList("AnimTime", k), seenAt[k - 1] or -1, 0.02, "which is the time the track had then")
	-- Test from that frame (playback speed 1): the frame's time again
	tl:setList("AnimTime", k, 0.123)
	E.modes:seek(k)
	M.steps(1)
	near(walk.TimePosition, 0.123, 1e-6, "the frame's saved time, not a sum")
	tl:setList("AnimTime", k, seenAt[k - 1])
	-- Test (interpolated playback): the playing track stays on the saved time between animation starts (live,
	-- a 0.5x Frame Step run: the idle track ran on by itself and was 0.185 s off the recording); a track only a
	-- little off is left alone
	do
		local function TTf(f) return tl:get("TotalTime", f, 1) end
		local function want()
			local f = E.frame
			return tl:getList("AnimTime", f) + (E.testTime - TTf(f)) * tl:get("AnimSpeed", f, 1)
		end
		local function walkNow()
			for _, t in ipairs(playing()) do if t.Animation.AnimationId == WALK then return t end end
		end
		E.modes:request("test")
		M.steps(1)
		local g2 = 0
		while E.mode == 3 and not (walkNow() and E.frame >= 40) and g2 < 200 do M.step(1 / 60); g2 = g2 + 1 end
		local w = walkNow()
		check(E.mode == 3 and w ~= nil, "Test: the walk plays (frame " .. E.frame .. ")")
		if w then
			w.TimePosition = (want() + 0.3) % w.Length
			M.step(1 / 60)
			local d = math.abs(w.TimePosition - want() % w.Length)
			check(d < 0.02, "a track 0.3 s off the saved time is put back on it (off " .. d .. ")")
			local small = (want() + 0.01) % w.Length
			w.TimePosition = small
			local before = w.TimePosition
			-- (the mock's track doesn't move by itself: the frame moves the wanted time on by about 0.018)
			M.step(1 / 60)
			eq(w.TimePosition, before, "a track a little off (under 0.03 s) is left as it is")
		end
		local g3 = 0
		while E.mode == 3 and g3 < 300 do M.step(1 / 60); g3 = g3 + 1 end
		E.modes:request("create")
		M.steps(2)
		walk = walkNow() or walk -- (Test loads its own walk track)
	end
	-- a frame without a saved time (an older file): worked out as before
	for i = 1, tl:count() do tl:setList("AnimTime", i, nil) end
	E.modes:seek(1)
	M.steps(1)
	E.modes:seek(k)
	M.steps(1)
	check(walk.TimePosition > 0.8, "no saved time: the frame-time sum, as before (" .. walk.TimePosition .. ")")
	key(Enum.KeyCode.One)
	M.steps(2)
end

section("unload gives the game its Animate back")
getgenv().__HappaTAS3.Unload()
M.steps(2)
eq(animate.Disabled, false, "Animate enabled again")
eq(#playing(), 0, "HappaTAS's tracks stopped")
finish()
