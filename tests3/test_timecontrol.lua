-- ================================================================================================
-- HappaTAS 3: time control's settings: off by default, the speed 0.1 - 1 (slow motion only: fast motion was
-- taken out), the Toggle Speed Hack key (never recorded). Slow motion itself (Frame Step) and the coyote timer:
-- tests3/test_humanoidclock.lua, tests3/test_smoothview.lua.
-- (headless mock with a small humanoid model, not a real game)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local SettingsMod = __T3("engine/settings")
local S = {
	Set = function(name, v) return E.settings:set(SettingsMod.byV2[name].key, v) end,
	Get = function(name) return E.settings:get(SettingsMod.byV2[name].key) end,
}
local SH = setmetatable({ Wanted = function() return E.time:wanted() end }, { __index = function(_, k) return E.time[k] end })
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

section("off by default: nothing changes")
eq(S.Get("Speed Hack"), 0, "Speed Hack off by default")
eq(S.Get("Speed Hack Speed"), 0.5, "speed 0.5 by default")
local plain = record(DTS, 1, walkThenJump())
eq(SH.scale, 1, "factor 1")
check(#plain >= 230, "recorded (" .. #plain .. " frames)")

section("settings and the toggle key")
eq(S.Set("Speed Hack Speed", 0.05), true, "below 0.1 is allowed in...")
eq(S.Get("Speed Hack Speed"), 0.1, "...and clamped to 0.1")
S.Set("Speed Hack Speed", 3)
eq(S.Get("Speed Hack Speed"), 1, "above 1 clamped to 1 (slow motion only)")
S.Set("Speed Hack Speed", 1)
eq(SH.Wanted(), 1, "speed 1 = off")
S.Set("Speed Hack Speed", 0.5)
local statuses = {}
E.bus:on("status", function(text) statuses[#statuses + 1] = text end)
eq(E.controls:get("toggleSpeedHack"), "None", "no key by default")
E.controls:set("toggleSpeedHack", "H")
local before = S.Get("Speed Hack")
key(Enum.KeyCode.H)
steps(2)
eq(S.Get("Speed Hack"), 1 - before, "the key switches it")
key(Enum.KeyCode.H)
steps(2)
eq(S.Get("Speed Hack"), before, "and back")
check(statuses[#statuses] == "Speed Hack: 0.5x while recording" or statuses[#statuses] == "Speed Hack: Off", "a status line (" .. tostring(statuses[#statuses]) .. ")")
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

finish()
