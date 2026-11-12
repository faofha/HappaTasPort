-- ================================================================================================
-- HappaTAS 3: the smooth view of slow motion (world/time/control.lua, "smooth view").
-- Frame Step holds the world on the frames between two physics steps, so the picture only changes when a step
-- runs. With "Smooth Slow Motion" the picture shows the character (its root), the loose parts that moved and
-- the camera where they were a short, fixed game time ago, on the way between the real poses of the last steps.
-- Only the picture: everything is back on its real pose before Roblox works the humanoid or the physics out,
-- so the recording is the same run with the setting on or off.
--   * the picture glides: on every frame it moves on by the speed x the slider x the frame's time, never ahead
--     of the real pose and never more than two steps behind it
--   * right after PreAnimation (where Roblox works the humanoid out), at PreSimulation and at Heartbeat the root,
--     the loose parts and the camera are on their real poses
--   * the TAS recorded is the same with the setting on and off
--   * a teleport isn't glided over, and a pose somebody else wrote while the picture was up is kept
--   * a frame without a physics step (Roblox fires no PreAnimation / PreSimulation on it) doesn't turn the
--     picture into the real pose
-- (headless mock, not a real game: "the picture" = the poses after PreRender, before PreAnimation)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local SettingsMod = __T3("engine/settings")
local S = {
	Set = function(name, v) return E.settings:set(SettingsMod.byV2[name].key, v) end,
	Get = function(name) return E.settings:get(SettingsMod.byV2[name].key) end,
}
local UIS = M.services.UserInputService
local RS = M.services.RunService
local guard = 0
while not (E.char.hrp and E.char.hum) and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local hrp, hum = E.char.hrp, E.char.hum
local cam = workspace.CurrentCamera
M.humanoidPhysics = true
M.robloxController = true

local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
local function click()
	UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	UIS.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
local function steps(n, dt) for _ = 1, n do M.step(dt or 1 / 60) end end

-- what each frame of a recording looked like: `pic` = the picture (after PreRender and the render binds, before
-- PreAnimation), `eval` = right after the PreAnimation handlers (what Roblox works the humanoid out from),
-- `real` = at PreSimulation (what the physics step starts from), `hb` = at Heartbeat
local log = nil
local box = nil -- (a loose part to watch, or nil)
local function snap(t)
	local i = #t + 1
	t[i] = { root = hrp.CFrame, cam = cam.CFrame, focus = cam.Focus, box = box and box.CFrame or nil, anchored = hrp.Anchored }
end
RS:BindToRenderStep("SmoothViewProbe", 9000, function() if log and #log.pic < log.n then snap(log.pic) end end)
M.afterPreAnimation = function() if log and #log.eval < log.n then snap(log.eval) end end
RS.PreSimulation:Connect(function() if log and #log.real < log.n then snap(log.real) end end)
RS.Heartbeat:Connect(function() if log and #log.hb < log.n then snap(log.hb) end end)

-- records a run from a fresh start (frame i lasts dts[i]; events[i]() runs before frame i) and returns the TAS as
-- V2 frames and the log of its frames
local function record(dts, events)
	key(Enum.KeyCode.One)
	steps(2)
	E.modes:setRun({})
	hum.MoveDirection = Vector3.zero
	hrp.CFrame = CFrame.new(0, 3, 0)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	hum.WalkSpeed, hum.JumpPower = 16, 50
	hum.Jump = false
	M.resetHumanoidModel()
	M.resetRobloxController()
	E.anim:set({ Pose = 2, JumpTime = 0, Speed = 1 }, { { 1, 0 } }, 1)
	cam.CFrame = CFrame.new(0, 10, 20)
	cam.Focus = CFrame.new(0, 4.5, 0)
	steps(2)
	key(Enum.KeyCode.Two)
	steps(2)
	click()
	local mine = { pic = {}, eval = {}, real = {}, hb = {}, n = #dts }
	log = mine
	for i = 1, #dts do
		if events and events[i] then events[i]() end
		M.step(dts[i])
	end
	log = nil
	click()
	steps(2)
	local out = {}
	for i, fr in ipairs(E.tl:toV2All()) do out[i] = fr end
	return out, mine
end

local EVEN = 1 / 120
local function even(n) local t = {}; for i = 1, n do t[i] = EVEN end; return t end
local function walk() return { [1] = function() hum.MoveDirection = Vector3.new(1, 0, 0) end } end
local function dist(a, b) return (a.Position - b.Position).Magnitude end
-- the frames whose physics step ran (the real pose moved on by the next frame)
local function ranFrames(lg)
	local out = {}
	for i = 1, #lg.real - 1 do
		if lg.real[i + 1].root ~= lg.real[i].root then out[#out + 1] = i end
	end
	return out
end

section("the setting")
local row = SettingsMod.byKey.smoothSlowMotion
check(row ~= nil, "there is a Smooth Slow Motion setting")
eq(row and row.section, "Speed hack", "in the Speed hack section")
eq(E.settings:on("smoothSlowMotion"), true, "on by default")
eq(row and row.name, "Smooth Slow Motion", "its name")

S.Set("Speed Hack", 1)
S.Set("Speed Hack Speed", 0.25)

section("0.25x: the picture glides between the steps")
local N = 160
local tasOn, on = record(even(N), walk())
E.settings:set("smoothSlowMotion", 0)
local tasOff, off = record(even(N), walk())
E.settings:set("smoothSlowMotion", 1)
eq(#on.pic, N, "every frame's picture was seen")
do
	local ran = ranFrames(off)
	check(#ran >= 30, "one step in four ran (" .. #ran .. " of " .. N .. ")")
	-- off: the picture is the real pose, the same one on every held frame
	local offSame, offMoves = 0, 0
	for i = 1, N do
		if off.pic[i].root == off.real[i].root then offSame = offSame + 1 end
		if i > 1 and off.pic[i].root ~= off.pic[i - 1].root then offMoves = offMoves + 1 end
	end
	eq(offSame, N, "off: the picture is the real pose on every frame")
	check(offMoves <= #ran, "off: the picture only changes when a step ran (" .. offMoves .. " changes)")
	-- on: the picture moves on every frame, at a steady walk (16 studs a second) by 16 x 0.25 x the frame's time
	local moves = 0
	local ranOn = ranFrames(on)
	for i = ranOn[3] + 1, ranOn[#ranOn] do
		if on.pic[i].root.Position.X > on.pic[i - 1].root.Position.X + 1e-9 then moves = moves + 1 end
	end
	eq(moves, ranOn[#ranOn] - ranOn[3], "on: the picture moves on every frame")
	local lo, hi = math.huge, 0
	for i = N - 60, N do
		local d = on.pic[i].root.Position.X - on.pic[i - 1].root.Position.X
		lo, hi = math.min(lo, d), math.max(hi, d)
	end
	local want = 16 * 0.25 * EVEN
	check(math.abs(lo - want) < 1e-6 and math.abs(hi - want) < 1e-6,
		"on: by the walking speed x the slider x the frame's time on each frame (" .. lo .. " .. " .. hi .. ", " .. want .. ")")
	-- behind the real pose, by two steps' way at most; on the real path (a straight walk: only x differs)
	local ahead, behind, side = 0, 0, 0
	for i = 1, N do
		local p, r = on.pic[i].root.Position, on.real[i].root.Position
		if p.X > r.X + 1e-9 then ahead = ahead + 1 end
		behind = math.max(behind, r.X - p.X)
		side = math.max(side, math.abs(p.Y - r.Y), math.abs(p.Z - r.Z))
	end
	eq(ahead, 0, "on: the picture is never ahead of the real pose")
	check(behind > 0.05 and behind <= 16 * 2 * EVEN + 1e-6, "on: and at most two steps behind it (" .. behind .. " studs)")
	check(side < 1e-9, "on: on the real path (" .. side .. ")")
end

section("only the picture: the physics and the recording see the real poses")
do
	local badReal, badHb, badCam, badHeld, badEval = 0, 0, 0, 0, 0
	for i = 1, N do
		if on.eval[i].root ~= on.real[i].root or on.eval[i].cam ~= on.real[i].cam then badEval = badEval + 1 end
		if on.real[i].root ~= off.real[i].root then badReal = badReal + 1 end
		if on.hb[i].root ~= off.hb[i].root then badHb = badHb + 1 end
		if on.real[i].cam ~= off.real[i].cam or on.hb[i].cam ~= off.hb[i].cam or on.real[i].focus ~= off.real[i].focus then badCam = badCam + 1 end
		if on.real[i].anchored ~= off.real[i].anchored then badHeld = badHeld + 1 end
	end
	eq(badEval, 0, "the root and the camera are back before Roblox works the humanoid out")
	eq(badReal, 0, "the root at PreSimulation is the same with the setting on and off")
	eq(badHb, 0, "and at Heartbeat")
	eq(badCam, 0, "the camera at PreSimulation and Heartbeat is where it was")
	eq(badHeld, 0, "the same steps are held")
	eq(#tasOn, #tasOff, "the same number of frames is recorded")
	local diff = 0
	for i = 1, math.min(#tasOn, #tasOff) do
		local a, b = tasOn[i], tasOff[i]
		for c = 1, #a.Cframe do if a.Cframe[c] ~= b.Cframe[c] then diff = diff + 1 end end
		for c = 1, #a.CamCframe do if a.CamCframe[c] ~= b.CamCframe[c] then diff = diff + 1 end end
		for c = 1, 3 do if a.Velocity.Linear[c] ~= b.Velocity.Linear[c] then diff = diff + 1 end end
		if a.FrameTime ~= b.FrameTime or a.TotalTime ~= b.TotalTime or a.State ~= b.State then diff = diff + 1 end
	end
	eq(diff, 0, "the TAS is the same with the setting on and off (poses, camera, velocities, times, states)")
end

section("the camera goes with the picture")
do
	local worst, moved = 0, 0
	for i = 1, N do
		local d = on.pic[i].root.Position - on.real[i].root.Position
		local c = on.pic[i].cam.Position - on.real[i].cam.Position
		local f = on.pic[i].focus.Position - on.real[i].focus.Position
		worst = math.max(worst, (c - d).Magnitude, (f - d).Magnitude)
		if d.Magnitude > 1e-6 then moved = moved + 1 end
	end
	check(moved > 80, "frames with a picture off the real pose (" .. moved .. ")")
	check(worst < 1e-9, "the camera and its focus are moved by what the character's picture is moved (" .. worst .. ")")
	local turned = 0
	for i = 1, N do
		if (on.pic[i].cam.LookVector - on.real[i].cam.LookVector).Magnitude > 1e-12 then turned = turned + 1 end
	end
	eq(turned, 0, "the camera isn't turned")
end

section("loose parts glide too")
local CPf = workspace:FindFirstChild("ClientParts")
if not CPf then CPf = Instance.new("Folder"); CPf.Name = "ClientParts"; CPf.Parent = workspace end
do
	local function newBox()
		local b = Instance.new("Part")
		b.Name = "FreeBox"
		b.Anchored = false
		b.CFrame = CFrame.new(50, 10, 0)
		b.AssemblyLinearVelocity = Vector3.new(0, 0, 6)
		b.Parent = CPf
		M.freeParts = { b }
		return b
	end
	local still = Instance.new("Part")
	still.Name = "StillBox"
	still.Anchored = false
	still.CFrame = CFrame.new(70, 10, 0)
	still.Parent = CPf
	box = newBox()
	local _, bOn = record(even(120), walk())
	box:Destroy()
	E.settings:set("smoothSlowMotion", 0)
	box = newBox()
	local _, bOff = record(even(120), walk())
	E.settings:set("smoothSlowMotion", 1)
	local badReal, between, ahead = 0, 0, 0
	for i = 1, 120 do
		if bOn.real[i].box ~= bOff.real[i].box or bOn.hb[i].box ~= bOff.hb[i].box or bOn.eval[i].box ~= bOn.real[i].box then badReal = badReal + 1 end
		local z, zr = bOn.pic[i].box.Position.Z, bOn.real[i].box.Position.Z
		if z < zr - 1e-9 then between = between + 1 end
		if z > zr + 1e-9 then ahead = ahead + 1 end
	end
	eq(badReal, 0, "the box after PreAnimation, at PreSimulation and at Heartbeat is where the physics left it")
	check(between > 60, "its picture is on the way on the held frames (" .. between .. ")")
	eq(ahead, 0, "never ahead of the real pose")
	-- (6 studs a second: 6 x 0.25 x the frame's time on every frame)
	local lo, hi = math.huge, 0
	for i = 70, 120 do
		local d = bOn.pic[i].box.Position.Z - bOn.pic[i - 1].box.Position.Z
		lo, hi = math.min(lo, d), math.max(hi, d)
	end
	local want = 6 * 0.25 * EVEN
	check(math.abs(lo - want) < 1e-6 and math.abs(hi - want) < 1e-6, "by its speed x the slider x the frame's time on each frame (" .. lo .. " .. " .. hi .. ")")
	eq(box.Anchored, false, "the box isn't left anchored")
	near(box.AssemblyLinearVelocity.Z, 6, 1e-9, "and keeps its velocity")
	eq(still.CFrame, CFrame.new(70, 10, 0), "a loose part that doesn't move is left alone")
	-- the game moves the box itself between two steps: its place is the game's, not the glide's
	box:Destroy()
	box = newBox()
	-- (moved before frames 62, 75, 80 and 85: whichever frame of four is the one whose step runs, three of the
	-- moves come on a held frame. Up to the next step that runs there is nothing to glide: it has not moved since)
	local AWAY = { [62] = CFrame.new(50, 30, 99), [75] = CFrame.new(50, 60, -40), [80] = CFrame.new(90, 30, 9), [85] = CFrame.new(20, 80, 0) }
	local evB = walk()
	for at, cf in pairs(AWAY) do evB[at] = function() box.CFrame = cf end end
	local _, bMoved = record(even(92), evB)
	local kept, glided, looked = 0, 0, 0
	for at, cf in pairs(AWAY) do
		if dist(bMoved.real[at].box, cf) < 1e-9 then kept = kept + 1 end
		local i = at
		while true do
			if dist(bMoved.pic[i].box, bMoved.real[i].box) > 1e-9 then glided = glided + 1 end
			looked = looked + 1
			if bMoved.real[i + 1].box ~= bMoved.real[i].box then break end -- (this frame's step ran)
			i = i + 1
		end
	end
	eq(kept, 4, "a loose part the game moved keeps the game's place")
	check(looked >= 8, "held frames after a move were looked at (" .. looked .. ")")
	eq(glided, 0, "and is drawn there, not on a way to it")
	-- a part that was held by the game for a while (anchored: no longer one of the loose parts), moved by it and
	-- let go again isn't drawn on a way from where it was before
	box:Destroy()
	box = newBox()
	local function rescan() -- (a part added to the world: the loose parts are looked up again on the next held step)
		local d = Instance.new("Part")
		d.Anchored = true
		d.Parent = CPf
		d:Destroy()
	end
	local evA = walk()
	evA[40] = function() box.Anchored = true; rescan() end
	evA[60] = function() box.CFrame = box.CFrame + Vector3.new(0, 0, 5) end
	evA[80] = function() box.Anchored = false; rescan() end
	local _, bHeld = record(even(110), evA)
	local farOff = 0
	for i = 80, 110 do
		if dist(bHeld.pic[i].box, bHeld.real[i].box) > 1 then farOff = farOff + 1 end
	end
	check(bHeld.real[110].box.Position.Z > bHeld.real[82].box.Position.Z + 0.1, "let go, the box moves on again")
	eq(farOff, 0, "a part that was out of the loose parts for a while isn't drawn on a way from its old place")
	M.freeParts = {}
	box:Destroy()
	still:Destroy()
	box = nil
end

section("a teleport isn't glided over")
do
	local ev = walk()
	local FAR = CFrame.new(500, 3, 40)
	local at = 62
	ev[at] = function() hrp.CFrame = FAR end
	local _, tp = record(even(100), ev)
	-- (the frame the game moved the character on, and every frame after it up to the next step)
	local glide = 0
	for i = at, at + 3 do
		if dist(tp.pic[i].root, tp.real[i].root) > 1e-9 then glide = glide + 1 end
	end
	eq(glide, 0, "the picture is on the new place at once")
	check(dist(tp.real[at].root, FAR) < 1e-9, "the game's own move is kept (" .. tostring(tp.real[at].root.Position) .. ")")
	local later = 0
	for i = at + 12, 100 do
		if dist(tp.pic[i].root, tp.real[i].root) > 1e-6 then later = later + 1 end
	end
	check(later > 10, "and the glide goes on from there (" .. later .. " frames)")
end

section("a short teleport isn't glided over either")
do
	-- (found in the client: a 9.7 stud teleport slid across the screen for 14 frames at 0.1x. 6 studs here, before
	-- frames 62 and 75: one of them at least comes on a held frame)
	local ev = walk()
	local at = { 62, 75 }
	for _, i in ipairs(at) do ev[i] = function() hrp.CFrame = hrp.CFrame + Vector3.new(0, 0, 6) end end
	local _, tp = record(even(100), ev)
	local glide = 0
	for _, i in ipairs(at) do
		for k = i, i + 3 do
			if math.abs(tp.pic[k].root.Position.Z - tp.real[k].root.Position.Z) > 1e-9 then glide = glide + 1 end
		end
	end
	eq(glide, 0, "the picture is on the new place at once")
	near(tp.real[100].root.Position.Z, 12, 1e-9, "and both moves are kept")
end

section("a small move by the game between two steps is kept")
do
	-- (a game script that nudges the character a stud sideways: before frames 62 and 75, one of them at least on a
	-- held frame whichever frames run a step)
	local ev = walk()
	ev[62] = function() hrp.CFrame = hrp.CFrame + Vector3.new(0, 0, 1) end
	ev[75] = function() hrp.CFrame = hrp.CFrame + Vector3.new(0, 0, 1) end
	local _, nd = record(even(100), ev)
	near(nd.real[62].root.Position.Z, 1, 1e-9, "the first nudge is where the physics goes on from")
	near(nd.real[75].root.Position.Z, 2, 1e-9, "and the second")
	near(nd.real[100].root.Position.Z, 2, 1e-9, "and it stays (" .. nd.real[100].root.Position.Z .. ")")
	local far = 0
	for i = 62, 100 do
		if math.abs(nd.pic[i].root.Position.Z - nd.real[i].root.Position.Z) > 1 + 1e-6 then far = far + 1 end
	end
	eq(far, 0, "the picture is never further off than the nudge")
end

section("the frame time changes: the picture never goes back, one long frame doesn't hold it up")
do
	S.Set("Speed Hack Speed", 0.1)
	local dts = {}
	for i = 1, 80 do dts[i] = 1 / 240 end
	for i = 81, 130 do dts[i] = 1 / 60 end
	local _, ch = record(dts, walk())
	local back = 0
	for i = 2, 130 do
		if ch.pic[i].root.Position.X < ch.pic[i - 1].root.Position.X - 1e-9 then back = back + 1 end
	end
	eq(back, 0, "240 to 60 frames a second at 0.1x: never back")
	S.Set("Speed Hack Speed", 0.25)
	-- one frame of 0.1 s among frames of 1/120 s: the picture goes on within a few frames (its lag is the usual
	-- step's, not the long frame's)
	local sp = even(110)
	sp[60] = 0.1
	local _, lg = record(sp, walk())
	local stuck = 0
	for i = 62, 78 do
		if lg.pic[i].root.Position.X <= lg.pic[i - 1].root.Position.X + 1e-9 then stuck = stuck + 1 end
	end
	check(stuck <= 6, "after one long frame the picture stands for a few frames at most (" .. stuck .. " of 17)")
end

section("a pose somebody else wrote while the picture was up is kept")
do
	-- (a game script that moves the character after HappaTAS drew its picture, in the same render step)
	local THERE = CFrame.new(-300, 3, 0)
	local fire, wrote = nil, nil
	RS:BindToRenderStep("SmoothViewMover", 8000, function()
		if fire and log and #log.pic == fire - 1 then
			wrote = hrp.CFrame ~= log.real[#log.real].root -- (a picture was up)
			hrp.CFrame = THERE
		end
	end)
	local ev = walk()
	fire = 63
	local _, mv = record(even(80), ev)
	fire = nil
	RS:UnbindFromRenderStep("SmoothViewMover")
	eq(wrote, true, "the game wrote over a picture")
	check(dist(mv.real[63].root, THERE) < 1e-9, "its pose is the one the physics gets (" .. tostring(mv.real[63].root.Position) .. ")")
end

section("uneven frames at 0.3x: the picture never goes back")
do
	S.Set("Speed Hack Speed", 0.3)
	local seed = 11
	local dts = {}
	for i = 1, 200 do
		seed = (seed * 1103515245 + 12345) % 2147483648
		dts[i] = (6.9 + (seed % 1000) / 1000 * 9.8) / 1000
	end
	local _, un = record(dts, walk())
	local back, ahead, moved = 0, 0, 0
	for i = 2, 200 do
		local x = un.pic[i].root.Position.X
		if x < un.pic[i - 1].root.Position.X - 1e-9 then back = back + 1 end
		if x > un.real[i].root.Position.X + 1e-9 then ahead = ahead + 1 end
		if x > un.pic[i - 1].root.Position.X + 1e-9 then moved = moved + 1 end
	end
	eq(back, 0, "never back")
	eq(ahead, 0, "never ahead of the real pose")
	check(moved > 185, "a new place on nearly every frame (" .. moved .. " of 199)")
	-- (the picture's move on frame i is the game time banked by the frame before: speed x slider x that frame's time)
	local even2 = 0
	for i = 100, 200 do
		local d = un.pic[i].root.Position.X - un.pic[i - 1].root.Position.X
		if math.abs(d - 16 * 0.3 * dts[i - 1]) < 1e-6 then even2 = even2 + 1 end
	end
	check(even2 >= 85, "by the walking speed x the slider x the frame's time on most frames (" .. even2 .. " of 101)")
	S.Set("Speed Hack Speed", 0.25)
end

section("frames without a physics step: the picture never becomes the real pose")
do
	-- (found in the client: about one frame in a thousand at 165 FPS has no physics step, and Roblox fires neither
	-- PreAnimation nor PreSimulation on it; the picture stayed up and the next frame took it for the real pose:
	-- a jump came out 0.07 - 0.26 studs lower)
	M.preAnimNeedsPhysics = true
	local k = 0
	M.simDt = function(dt)
		k = k + 1
		if k % 7 == 0 or k % 7 == 1 then return 0 end
		return dt
	end
	local function run(smooth)
		k = 0
		E.settings:set("smoothSlowMotion", smooth)
		return record(even(140), walk())
	end
	local tasA, a = run(1)
	local tasB, b = run(0)
	M.simDt = nil
	M.preAnimNeedsPhysics = nil
	E.settings:set("smoothSlowMotion", 1)
	check(#a.real > 80 and #a.real < 140, "some frames had no physics step (" .. #a.real .. " of 140 had one)")
	eq(#a.real, #b.real, "the same frames had one")
	local bad, gl = 0, 0
	for i = 1, math.min(#a.real, #b.real) do
		if a.real[i].root ~= b.real[i].root or a.real[i].cam ~= b.real[i].cam then bad = bad + 1 end
	end
	for i = 1, 140 do
		if a.pic[i].root ~= a.hb[i].root and i > 1 and a.pic[i].root ~= a.pic[i - 1].root then gl = gl + 1 end
	end
	eq(bad, 0, "the root and the camera every physics step starts from are the same with the setting on and off")
	check(gl > 60, "and the picture glides (" .. gl .. " frames)")
	eq(#tasA, #tasB, "the same number of frames is recorded")
	local diff = 0
	for i = 1, math.min(#tasA, #tasB) do
		for c = 1, #tasA[i].Cframe do if tasA[i].Cframe[c] ~= tasB[i].Cframe[c] then diff = diff + 1 end end
	end
	eq(diff, 0, "the TAS is the same with the setting on and off")
end

section("the speed hack ends while a picture is up: the real pose is back")
do
	local shownAt, after = nil, nil
	RS:BindToRenderStep("SmoothViewStop", 8500, function()
		if log and #log.pic == 70 and not shownAt then
			shownAt = hrp.CFrame -- (frame 71's picture is up)
			E.time:restore(true)
			after = hrp.CFrame
		end
	end)
	local _, st = record(even(80), walk())
	RS:UnbindFromRenderStep("SmoothViewStop")
	check(shownAt ~= nil and after ~= nil, "the speed hack was ended in the render step")
	check(shownAt ~= st.real[71].root, "while a picture off the real pose was up")
	check(after == st.real[71].root, "the root is on its real pose right away (" .. tostring(after and after.Position) .. ")")
	eq(st.pic[72].root, st.real[72].root, "and nothing is drawn elsewhere on the next frame")
end

section("above 1x and at 1x nothing is drawn elsewhere")
do
	S.Set("Speed Hack Speed", 2)
	local _, fast = record(even(60), walk())
	local offReal = 0
	for i = 1, 60 do if fast.pic[i].root ~= fast.real[i].root or fast.pic[i].cam ~= fast.real[i].cam then offReal = offReal + 1 end end
	eq(offReal, 0, "2x: the picture is the real pose")
	S.Set("Speed Hack", 0)
	local _, plain = record(even(60), walk())
	offReal = 0
	for i = 1, 60 do if plain.pic[i].root ~= plain.real[i].root or plain.pic[i].cam ~= plain.real[i].cam then offReal = offReal + 1 end end
	eq(offReal, 0, "speed hack off: the picture is the real pose")
end

RS:UnbindFromRenderStep("SmoothViewProbe")

finish()
