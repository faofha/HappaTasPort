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
check(tr.TimePosition > 0, "TimePosition set from the frame times (" .. tostring(tr.TimePosition) .. ")")

section("Test plays the recorded animations at playback speed")
key(Enum.KeyCode.Three)
M.steps(3)
tr = playing()[1]
check(tr.Speed > 0, "playing")
local g = 0
while E.mode == 3 and g < 200 do M.step(1 / 60); g = g + 1 end
eq(E.mode, 1, "Test ended")

section("unload gives the game its Animate back")
getgenv().__HappaTAS3.Unload()
M.steps(2)
eq(animate.Disabled, false, "Animate enabled again")
eq(#playing(), 0, "HappaTAS's tracks stopped")
finish()
