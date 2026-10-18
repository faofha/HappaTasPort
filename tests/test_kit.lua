-- ================================================================================================
-- The EToH kit on the TAS clock (V2.38.14):
--   * Kit Clock: the kit modules' task.wait / task.delay / os.clock and Utility.Functions.tween run on the TAS
--     clock: real time in Idle, stopped while paused, x the speed hack while recording; Unload gives the
--     environments back and lets waiting kit threads finish in real time
--   * beat blocks: the beat comes from the TAS time (recording, paused on any frame, playback), the kit's
--     own writes are undone, the ding plays on HappaTAS's beat, a TAS from before keeps the kit's beat
--   * turrets: the kit's bullet is replaced by HappaTAS's, saved as fire / end events, positioned on the TAS
--     clock, stopped by walls and by your character (the kit's damage), played back, cut when unpausing
--     earlier, saved and loaded (file version 5)
--   * pushbox spawns: a box from later in the TAS is hidden on earlier frames
--   * forces a kit script puts on the character: removed after unpausing earlier, off while testing
--   * the speed hack's world: constraints, conveyors and free parts slowed and put back, game writes adopted
--   * Sync Lighting: Idle / an empty TAS leave the lighting as it is
-- (headless mock: the kit modules here are small stand-ins written like the kit's, not the real kit)
-- ================================================================================================
local beatConn, turThread, g2 -- (shared by the sections)
local function kitTests()
local RS = M.services.ReplicatedStorage
local mockOs = os

-- ------------------------------------------------------------------------------------------------ the kit
local fw = Instance.new("Folder"); fw.Name = "Framework"; fw.Parent = RS
local kit = Instance.new("Folder"); kit.Name = "Kit"; kit.Parent = fw
local function folder(parent, name) local f = Instance.new("Folder"); f.Name = name; f.Parent = parent; return f end
local repo = folder(kit, "Repository")
local visual, inter, physicsF = folder(repo, "Visual"), folder(repo, "Interactables"), folder(repo, "Physics")
local utilF, managers = folder(kit, "Utility"), folder(kit, "Managers")

local function kitModule(parent, name, src)
	local ms = Instance.new("ModuleScript"); ms.Name = name; ms.Parent = parent
	local env = setmetatable({ script = ms }, { __index = setmetatable({ os = mockOs }, { __index = getfenv(1) }) })
	local chunk = loadstring(src, "=" .. ms:GetFullName())
	setfenv(chunk, env)
	local mod = chunk()
	M.modules[ms] = mod
	return ms, mod, env
end

local _, Timer, timerEnv = kitModule(physicsF, "Timer", [[
local T = { ticks = {}, kticks = {} }
function T.Run(d)
	while true do
		task.wait(d)
		T.ticks[#T.ticks + 1] = M.now
		T.kticks[#T.kticks + 1] = os.clock()
	end
end
function T.Delay(d, f) return task.delay(d, f) end
function T.Clock() return os.clock() end
function T.WaitOnce(d) return task.wait(d) end
return T
]])
-- like the kit's Zipline ride: moves by the Heartbeat's dt
local _, Ride = kitModule(physicsF, "Ride", [[
local RunService = game:GetService("RunService")
local R = { dist = 0, calls = 0 }
function R.Start(speed)
	R.conn = RunService.Heartbeat:Connect(function(dt) R.dist = R.dist + speed * dt; R.calls = R.calls + 1 end)
end
function R.Stop() R.conn:Disconnect() end
return R
]])
-- the Morpher: its Heartbeat turns a step into a velocity with the real dt (left alone)
local _, MorphKit = kitModule(inter, "Morpher", [[
local RunService = game:GetService("RunService")
local Mo = { dts = {} }
Mo.conn = RunService.Heartbeat:Connect(function(dt) Mo.dts[#Mo.dts + 1] = dt end)
function Mo.Count() return #Mo.dts end
return Mo
]])
local _, Button, buttonEnv = kitModule(inter, "Button", [[
local B = {}
function B.Clock() return os.clock() end
function B.Wait(d) return task.wait(d) end
return B
]])
local fnMs, Functions = kitModule(utilF, "Functions", [[
local F = {}
local TweenService = game:GetService("TweenService")
function F.tween(instance, config, goal, style, dir, ...)
	local info
	if typeof(config) == "number" then
		info = TweenInfo.new(config, style or Enum.EasingStyle.Linear, dir or Enum.EasingDirection.Out, ...)
	else
		info = TweenInfo.new(config.Time, config.Style, config.Direction)
	end
	local tw = TweenService:Create(instance, info, goal)
	tw:Play()
	return tw
end
return F
]])
local origTween = Functions.tween
M.readonly[Functions] = true
local _, CharMgr = kitModule(managers, "CharacterManager", [[
local CM = { damage = {} }
function CM:Damage(a) table.insert(self.damage, a) end
return CM
]])
local bbMs, BeatKit = kitModule(visual, "BeatBlock", [[
local B = { writes = 0 }
-- the kit's default loop with its own phase (groups[i] = parts), no indicator
function B.Loop(groups, n, start)
	local beat = start
	while true do
		beat = beat % n + 1
		for i, list in pairs(groups) do
			for _, p in ipairs(list) do
				p.CanCollide = (i == beat)
				p.CanTouch = (i == beat)
				p.Transparency = (i == beat) and 0 or 0.7
			end
		end
		B.writes = B.writes + 1
		task.wait(1)
	end
end
return B
]])
local ding = Instance.new("Sound"); ding.Name = "DefaultDingSound"; ding.Volume = 0.5; ding.TimeLength = 0.4; ding.Parent = bbMs
local _, TurretKit = kitModule(inter, "Turret", [[
local T = { fired = 0 }
-- the kit's passive firing: a new bullet every 1 / FireRate s, moved by a LinearVelocity
function T.Loop(model, part, rate, speed)
	while true do
		task.wait(1 / rate)
		local m = Instance.new("Model"); m.Name = "Bullet"
		local p = Instance.new("Part"); p.Name = "Bullet"; p.Size = Vector3.new(1, 1, 1); p.CFrame = part.CFrame; p.Parent = m
		m.PrimaryPart = p
		local lv = Instance.new("LinearVelocity"); lv.VectorVelocity = part.CFrame.LookVector * speed; lv.Parent = p
		m.Parent = model
		T.fired = T.fired + 1
	end
end
return T
]])

-- ------------------------------------------------------------------------------------------------ the tower
local CP = Instance.new("Folder"); CP.Name = "ClientParts"; CP.Parent = workspace
local function part(parent, name, pos, size, anchored)
	local p = Instance.new("Part"); p.Name = name; p.Size = size or Vector3.new(4, 4, 4); p.CFrame = CFrame.new(pos)
	p.Anchored = anchored ~= false; p.Parent = parent
	return p
end
-- beat blocks: 4 groups, Interval 1, indicator for the last 0.5 s
local bbFolder = folder(CP, "BeatBlockGroup")
local bbCfg = Instance.new("Configuration"); bbCfg.Name = "BeatBlockConfiguration"
for k, v in pairs({ Interval = 1, IndicatorInterval = 0.5, Indicator = true, IndicatorSize = Vector3.new(3, 3, 3),
	OffTransparency = 0.7, OnTransparency = 0, OffCanCollide = false, OnCanCollide = true, OnCanTouch = true, OffCanTouch = false,
	MaterialIndicator = Enum.Material.SmoothPlastic, IndicatorScaleMultiplier = 1, ToggleChildren = false }) do bbCfg:SetAttribute(k, v) end
bbCfg:AddTag("CO_Visual/BeatBlock")
bbCfg.Parent = bbFolder
local beatParts, beatGroups = {}, {}
for i = 1, 4 do
	local p = part(bbFolder, tostring(i), Vector3.new(100 + i * 5, 2, 100))
	p.Material = Enum.Material.Plastic
	beatParts[i] = p
	beatGroups[i] = { p }
end
-- a turret facing +Z, a wall 20 studs in front of it
local turModel = Instance.new("Model"); turModel.Name = "Turret"; turModel.Parent = CP
local turPart = part(turModel, "Turret", Vector3.new(0, 5, 50), Vector3.new(2, 2, 2))
turPart.CFrame = CFrame.lookAt(Vector3.new(0, 5, 50), Vector3.new(0, 5, 100))
local fireSnd = Instance.new("Sound"); fireSnd.Name = "Fire"; fireSnd.Volume = 0.6; fireSnd.TimeLength = 0.3; fireSnd.Parent = turPart
local turCfg = Instance.new("Configuration"); turCfg.Name = "TurretConfiguration"
for k, v in pairs({ FireRate = 1, Speed = 50, MaxLifetime = 2, Damage = 5, Range = 500, DestroyOnTouch = true }) do turCfg:SetAttribute(k, v) end
turCfg:AddTag("CO_Interactables/Turret")
turCfg.Parent = turModel
local wall = part(workspace, "Wall", Vector3.new(0, 5, 70), Vector3.new(10, 10, 1))
-- a pushbox spawner
local spModel = Instance.new("Model"); spModel.Name = "PushboxSpawnButton"; spModel.Parent = CP
part(spModel, "Button", Vector3.new(-20, 2, 132), Vector3.new(1, 3, 3))
local spCfg = Instance.new("Configuration"); spCfg.Name = "PushboxSpawnConfiguration"
spCfg:AddTag("CO_Interactables/PushboxSpawn")
spCfg.Parent = spModel
-- the world for the speed hack
local hingeBase = part(CP, "Spinner", Vector3.new(50, 2, 0))
local hinge = Instance.new("HingeConstraint"); hinge.ActuatorType = Enum.ActuatorType.Motor; hinge.AngularVelocity = -1.5
hinge.MotorMaxTorque = math.huge; hinge.Parent = hingeBase
local vf = Instance.new("VectorForce"); vf.Force = Vector3.new(0, 0, 4000); vf.Parent = part(CP, "Pusher", Vector3.new(60, 2, 0))
local ap = Instance.new("AlignPosition"); ap.MaxVelocity = 2000; ap.Responsiveness = 15; ap.MaxForce = 10000
ap.Parent = part(CP, "Mover", Vector3.new(70, 2, 0))
local bv = Instance.new("BodyVelocity"); bv.Velocity = Vector3.new(1, 2, 3); bv.P = 1250; bv.Parent = part(CP, "Old", Vector3.new(80, 2, 0))
local conveyor = part(CP, "Conveyor", Vector3.new(90, 0, 0), Vector3.new(4, 1, 20))
conveyor.AssemblyLinearVelocity = Vector3.new(10, 0, 0)
local freeBox = part(CP, "FreeBox", Vector3.new(95, 10, 0), Vector3.new(2, 2, 2), false)
freeBox.AssemblyLinearVelocity = Vector3.new(0, 0, 8)

-- ------------------------------------------------------------------------------------------------ boot
check(boot(30), "boots")
local S, Core, KC, KO, SH, Store, Codec = __T.Settings, __T.Core, __T.KitClock, __T.KitObjects, __T.SpeedHack, __T.Store, __T.Codec
local C = Core.State
local UIS = M.services.UserInputService
local guard = 0
while not (C.HRP and C.Humanoid) and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local hrp = C.HRP
local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
local RSvc = M.services.RunService
local function click()
	UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	UIS.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
local function steps(n, dt) for _ = 1, n do M.step(dt or 1 / 60) end end
local function idle() key(Enum.KeyCode.One); steps(2) end
local function create() key(Enum.KeyCode.Two); steps(2) end
local function newTAS() idle(); Core.SetTAS({}); steps(1) end

section("kit clock: the kit's module environments get HappaTAS's task / os, Functions.tween is replaced")
check(KC.IsEnabled(), "Kit Scripts On TAS Clock is on by default")
eq(KC.patched, 8, "the 8 kit modules on the clock")
check(rawget(timerEnv, "task") ~= nil and rawget(timerEnv, "task").wait ~= task.wait, "a repository module's task.wait is the kit clock's")
check(rawget(timerEnv, "os") ~= nil and rawget(timerEnv, "os").clock ~= mockOs.clock, "and its os.clock")
check(rawget(buttonEnv, "task") ~= nil, "the Button script's task too")
check(rawget(buttonEnv, "os") == nil, "but not its os.clock (Sync Button Timers owns the button clock)")
check(Functions.tween ~= origTween, "Utility.Functions.tween replaced")
check(isreadonly(Functions), "the frozen Functions table is read-only again afterwards")

do
section("kit clock: real time in Idle, stopped while paused, the TAS clock while recording")
idle()
task.spawn(Timer.Run, 0.5)
local t0 = M.now
steps(180)
local n = #Timer.ticks
check(n >= 5 and n <= 6, "Idle: a 0.5 s kit wait comes back every 0.5 s (" .. n .. " in 3 s)")
local gap = Timer.ticks[n] - Timer.ticks[n - 1]
near(gap, 0.5, 1 / 60 + 1e-6, "Idle: 0.5 s apart")
newTAS()
create()
local before = #Timer.ticks
local kc0 = Timer.Clock()
steps(120)
eq(#Timer.ticks, before, "Create, paused: the kit's waits stop")
near(Timer.Clock(), kc0, 1e-9, "Create, paused: the kit's os.clock stands still")
eq(KC.rate, 0, "kit clock rate 0 while paused")
click() -- unpause: recording
steps(120)
local recN = #Timer.ticks - before
check(recN >= 3 and recN <= 5, "recording: the kit's waits go on (" .. recN .. " in 2 s)")
eq(KC.rate, 1, "kit clock rate 1 while recording")
click() -- pause
steps(2)
end
do
section("kit clock: x the speed hack while recording")
S.Set("Speed Hack", 1)
S.Set("Speed Hack Speed", 0.5)
click()
steps(2)
local a = #Timer.ticks
steps(240)
local slowN = #Timer.ticks - a
check(slowN >= 3 and slowN <= 5, "0.5x: 4 s of real time = 2 s of kit time (" .. slowN .. " waits of 0.5 s)")
near(KC.rate, 0.5, 1e-9, "kit clock rate 0.5")
local kgap = Timer.kticks[#Timer.kticks] - Timer.kticks[#Timer.kticks - 1]
local rgap = Timer.ticks[#Timer.ticks] - Timer.ticks[#Timer.ticks - 1]
near(kgap, 0.5, 0.01, "kit time between two waits 0.5 s")
near(rgap, 1, 0.02, "real time between them 1 s")
click()
steps(2)
S.Set("Speed Hack", 0)
eq(KC.rate, 0, "paused again: rate 0")

end
do
section("kit clock: kit listeners on Heartbeat get the kit's dt (the Zipline ride, the Sequencer)")
newTAS()
Ride.Start(10)
steps(60)
near(Ride.dist, 10, 1e-6, "Idle: real time (60 frames of 1/60 s at 10 studs/s)")
eq(next(KC.FrameEvents.Heartbeat), nil, "Idle: the kit's listener is left alone")
create()
local d0 = Ride.dist
local m0 = MorphKit.Count()
steps(30)
near(Ride.dist, d0, 1e-9, "paused: the ride doesn't move")
eq(MorphKit.Count() - m0, 30, "paused: the Morpher's listener still runs once a frame, on Roblox's call")
near(MorphKit.dts[#MorphKit.dts], 1 / 60, 1e-9, "with the real dt (its velocities are distance / real dt)")
check(next(KC.FrameEvents.Heartbeat) ~= nil, "paused: HappaTAS calls the kit's listener itself")
S.Set("Speed Hack", 1)
S.Set("Speed Hack Speed", 0.5)
click()
steps(2)
d0 = Ride.dist
steps(60)
near(Ride.dist - d0, 5, 1e-6, "0.5x: half the distance in the same real time")
S.Set("Speed Hack Speed", 2)
steps(2)
d0 = Ride.dist
steps(60)
near(Ride.dist - d0, 20, 1e-6, "2x: twice the distance")
S.Set("Speed Hack Speed", 0.5)
S.Set("Speed Hack Frame Step", 1)
steps(2)
d0 = Ride.dist
steps(60)
near(Ride.dist - d0, 5, 1e-6, "Frame Step 0.5x: the distance of the steps that ran")
S.Set("Speed Hack Frame Step", 0)
click()
steps(2)
S.Set("Speed Hack", 0)
local c0 = Ride.calls
Ride.Stop()
steps(10)
eq(Ride.calls, c0, "a listener the kit disconnected isn't called again")
idle()
steps(2)
eq(next(KC.FrameEvents.Heartbeat), nil, "Idle: nothing taken over")
-- without getconnections nothing changes
M.noGetConnections = true
Ride.Start(10)
create()
d0 = Ride.dist
steps(10)
near(Ride.dist - d0, 10 * 10 / 60, 1e-6, "no getconnections: the kit's listener runs in real time as before")
Ride.Stop()
idle()
M.noGetConnections = nil
-- back at 1x with the kit's listener still connected: it gets its own connection back
Ride.Start(10)
create()
steps(5)
check(next(KC.FrameEvents.Heartbeat) ~= nil, "paused: taken over")
idle()
steps(2)
eq(next(KC.FrameEvents.Heartbeat), nil, "back at 1x: given back")
d0 = Ride.dist
steps(60)
near(Ride.dist - d0, 10, 1e-6, "back at 1x: the kit's own listener runs in real time again (once a frame)")
Ride.Stop()

end
do
section("kit clock: a pause gives the kit no extra frame (the step after the last frame is thrown away)")
newTAS()
create()
click() -- recording
steps(30)
local kLast = KC.Now() -- (the kit's time of the last recorded frame, + the mock's few microseconds since)
-- (in the Roblox client the pause key comes in the next frame, after the step that the pause throws away)
M.now = M.now + 1 / 60
check(KC.Now() > kLast + 0.015, "before the pause the kit's clock went on by a frame")
click() -- pause
local kPaused = KC.Now()
-- (+ 0.001: the mock's os.clock adds a microsecond per call and starts counting again in the frame)
check(kPaused <= kLast + 0.001 and kPaused >= kLast - 0.002, "pausing puts the kit's clock back on the last recorded frame ("
	.. string.format("%.4f s back", kLast - kPaused) .. ")")
eq(KC.rate, 0, "and stops it right away")
steps(30)
near(KC.Now(), kPaused, 1e-9, "paused: it stays there")
-- never forward, never on another TAS
M.now = M.now + 1 / 60
KC.Rewind({}, #C.data)
near(KC.Now(), kPaused, 1e-9, "a frame of another TAS doesn't move it")
click() -- recording again
steps(10)
local kRec = KC.Now()
-- (from the first frame's render step: 9 frame times after 10 frames)
check(kRec > kPaused + 0.149, "recording again: the kit's clock goes on (" .. string.format("%.3f", kRec - kPaused) .. " s in 10 frames)")
click()
steps(2)
end
do
section("kit clock: task.delay and cancelling it, the wait's return value")
idle()
local fired = nil
Timer.Delay(0.3, function() fired = M.now end)
local dStart = M.now
steps(25)
check(fired ~= nil and fired - dStart >= 0.3 - 1e-6 and fired - dStart <= 0.3 + 1 / 60 + 1e-6, "task.delay(0.3) runs after 0.3 s")
local cancelled = false
local th = Timer.Delay(0.2, function() cancelled = true end)
task.cancel(th)
steps(20)
check(not cancelled, "a cancelled task.delay never runs")
local ret = nil
task.spawn(function() ret = Timer.WaitOnce(0.25) end)
steps(20)
check(ret ~= nil and ret >= 0.25 - 1e-6 and ret < 0.25 + 0.04, "task.wait returns the kit time it waited (" .. tostring(ret) .. ")")

end
do
section("kit clock: Functions.tween on the kit clock (stops while paused, Completed fires)")
local tp = part(workspace, "TweenPart", Vector3.new(0, 50, 0))
tp.Transparency = 0
local tw = Functions.tween(tp, 1, { Transparency = 1 })
steps(30)
check(tp.Transparency > 0.4 and tp.Transparency < 0.6, "half way after 0.5 s (" .. tp.Transparency .. ")")
newTAS()
create()
local held = tp.Transparency
steps(60)
near(tp.Transparency, held, 1e-9, "paused: the tween stands still")
local done = false
task.spawn(function() tw.Completed:Wait(); done = true end)
idle()
steps(40)
near(tp.Transparency, 1, 1e-9, "ends on its goal")
check(done, "Completed:Wait() comes back")
eq(tw.PlaybackState, Enum.PlaybackState.Completed, "PlaybackState Completed")

end
-- ------------------------------------------------------------------------------------------------ beat blocks
do
section("beat blocks: the beat comes from the TAS time while recording, the kit's writes are undone")
task.spawn(BeatKit.Loop, beatGroups, 4, 2) -- the kit's own loop, its own phase
local function expected(t)
	local cycle = math.floor(t / 1)
	local active = cycle % 4 + 1
	local ind = ((t - cycle) >= 0.5) and (active % 4 + 1) or nil
	return active, ind
end
local function beatOK(t)
	local active, ind = expected(t)
	for i, p in ipairs(beatParts) do
		local on, isInd = i == active, i == ind
		if isInd then
			if not (p.Size == Vector3.new(3, 3, 3) and p.Material == Enum.Material.SmoothPlastic and p.CanCollide == false
				and p.CanTouch == false and p.Transparency == 0.7) then return false, "indicator " .. i end
		else
			if p.Size ~= Vector3.new(4, 4, 4) or p.Material ~= Enum.Material.Plastic then return false, "size " .. i end
			if p.CanCollide ~= on or p.CanTouch ~= on or p.Transparency ~= (on and 0 or 0.7) then return false, "state " .. i end
		end
	end
	return true
end
local checkMode, checked, bad, firstBad = nil, 0, 0, nil
beatConn = RSvc.PreSimulation:Connect(function()
	if not checkMode then return end
	local t
	if checkMode == "rec" and C.mode == 2 and not C.paused and #C.data > 0 then t = C.data[#C.data].TotalTime
	elseif checkMode == "test" and C.mode == 3 then t = C.TestingTimer
	elseif checkMode == "paused" and C.mode == 2 and C.paused and C.data[C.frame] then t = C.data[C.frame].TotalTime end
	if not t then return end
	checked = checked + 1
	local ok, why = beatOK(t)
	if not ok then bad = bad + 1; firstBad = firstBad or (string.format("t=%.3f ", t) .. why) end
end)
local dings = 0
for _, p in ipairs(beatParts) do p.ChildAdded:Connect(function(c) if c:IsA("Sound") then dings = dings + 1 end end) end
newTAS()
create()
local kitWrites0 = BeatKit.writes
checkMode = "rec"
click()
steps(300) -- 5 s
click()
steps(2)
checkMode = nil
check(checked >= 290, "checked " .. checked .. " recorded frames")
eq(bad, 0, "every recorded frame shows the beat of its TAS time" .. (firstBad and (" (first wrong: " .. firstBad .. ")") or ""))
check(BeatKit.writes > kitWrites0, "the kit's loop kept writing its own beat meanwhile (" .. (BeatKit.writes - kitWrites0) .. " times)")
check(dings >= 4 and dings <= 6, "the ding plays on each of HappaTAS's beats (" .. dings .. ")")
eq(ding.Volume, 0, "the kit's own ding is muted while HappaTAS plays it")
local recFrames = #C.data
check(C.data.KitVersion == 1, "the TAS knows it was made with the kit rules (KitVersion 1)")

section("beat blocks: paused on any frame, testing")
checkMode = "paused"
checked, bad, firstBad = 0, 0, nil
for _, f in ipairs({ 1, 40, 75, 140, 200, 241, recFrames - 5 }) do
	C.frame = f + 1
	C.inputs.Back1F()
	steps(3)
end
checkMode = nil
check(checked >= 14, "checked " .. checked .. " paused frames")
eq(bad, 0, "Back / Forward show the beat of that frame" .. (firstBad and (" (" .. firstBad .. ")") or ""))
checkMode = "test"
checked, bad, firstBad = 0, 0, nil
dings = 0
key(Enum.KeyCode.Three)
g2 = 0
while C.mode == 3 and g2 < 600 do M.step(1 / 60); g2 = g2 + 1 end
checkMode = nil
check(checked >= 280, "checked " .. checked .. " playback frames")
eq(bad, 0, "playback shows the recorded beat" .. (firstBad and (" (" .. firstBad .. ")") or ""))
check(dings >= 4 and dings <= 6, "the dings play back too (" .. dings .. ")")
steps(2)
eq(C.mode, 1, "back in Idle after the test")
near(ding.Volume, 0.5, 1e-9, "Idle: the kit's ding is back")
local w0 = BeatKit.writes
steps(130)
check(BeatKit.writes > w0, "Idle: the kit drives the beat blocks again")
section("beat blocks: a TAS from before V2.38.14 keeps the kit's beat")
local saved = C.data
local oldTAS = {}
for i, fr in ipairs(saved) do oldTAS[i] = fr end
oldTAS.KitVersion = 0
Core.SetTAS(oldTAS)
create()
steps(5)
local tr = {}
for i, p in ipairs(beatParts) do tr[i] = p.Transparency end
local onCount = 0
for _, v in ipairs(tr) do if v == 0 then onCount = onCount + 1 end end
eq(onCount, 1, "one group on (the kit's)")
check(ding.Volume == 0.5, "no takeover: the ding isn't muted")
idle()
Core.SetTAS(saved)

end
-- ------------------------------------------------------------------------------------------------ turrets
do
section("turrets: the kit fires, HappaTAS's bullet takes its place in the TAS")
turThread = task.spawn(TurretKit.Loop, turModel, turPart, 1, 50)
steps(70) -- Idle: the kit's own bullets
local kitBullets = 0
for _, c in ipairs(turModel:GetChildren()) do if c:IsA("Model") and c.Name == "Bullet" then kitBullets = kitBullets + 1 end end
check(kitBullets >= 1, "Idle: the kit's bullets are left alone (" .. kitBullets .. ")")
for _, c in ipairs(turModel:GetChildren()) do if c:IsA("Model") then c:Destroy() end end
newTAS()
create()
local holderF = workspace.CurrentCamera:FindFirstChild("HappaTASKit")
local posBad, posChecked, worst = 0, 0, 0
local recPos = {} -- frame -> { seq -> position }
local turConn = RSvc.PreSimulation:Connect(function()
	if C.mode ~= 2 or C.paused or #C.data == 0 then return end
	local hf = workspace.CurrentCamera:FindFirstChild("HappaTASKit")
	if not hf then return end
	local f = #C.data
	local t = C.data[f].TotalTime
	local list = {}
	for _, m in ipairs(hf:GetChildren()) do list[#list + 1] = m:GetPivot().Position end
	recPos[f] = list
end)
click()
steps(240) -- 4 s
click()
steps(2)
turConn:Disconnect()
local fires, ends, walls = 0, 0, 0
local fireT, endT = {}, {}
for f, fr in ipairs(C.data) do
	for _, e in ipairs(fr.KE or {}) do
		if e[1] == 1 then fires = fires + 1; fireT[e[3]] = fr.TotalTime end
		if e[1] == 2 then ends = ends + 1; endT[e[2]] = fr.TotalTime; if e[3] == 0 then walls = walls + 1 end end
	end
end
check(fires >= 3 and fires <= 5, "fire events saved (" .. fires .. ")")
eq(#turModel:GetChildren() - 2, 0, "the kit's bullets were removed (only the turret part and its configuration are left)")
check(ends >= 3, "the bullets ended (" .. ends .. ")")
local flight = nil
for seq, t in pairs(fireT) do if endT[seq] then flight = endT[seq] - t break end end
-- the bullet (1 stud) starts at z = 50, the wall's face is at z = 69.5: 19 studs at 50 studs/s
check(flight and flight >= 0.38 - 1e-6 and flight <= 0.38 + 1 / 60 + 1e-6, "a bullet ends at the wall after 0.38 s (" .. tostring(flight) .. ")")
eq(walls, ends, "no damage from a bullet that hit the wall")
local any = false
for f, list in pairs(recPos) do if #list > 0 then any = true break end end
check(any, "HappaTAS's bullets were on screen while recording")
check(fireSnd.Volume == 0, "the kit's fire sound is muted, HappaTAS plays it on its bullets")

section("turrets: positions on the TAS clock, the same in playback")
-- the bullets' positions from the saved events at a frame's time
local function bulletsAt(data, f, t)
	local out, ended = {}, {}
	for i = 1, f do for _, e in ipairs(data[i].KE or {}) do if e[1] == 2 then ended[e[2]] = i end end end
	for i = 1, f - 1 do
		for _, e in ipairs(data[i].KE or {}) do
			if e[1] == 1 and (ended[e[3]] == nil or ended[e[3]] >= f) and t - data[i].TotalTime <= e[13] then
				out[#out + 1] = Vector3.new(e[4], e[5], e[6]) + Vector3.new(e[10], e[11], e[12]) * (t - data[i].TotalTime)
			end
		end
	end
	return out
end
local function sameSet(a, b)
	if #a ~= #b then return false, math.huge end
	local w = 0
	for _, p in ipairs(a) do
		local best = math.huge
		for _, q in ipairs(b) do best = math.min(best, (p - q).Magnitude) end
		w = math.max(w, best)
	end
	return w < 1e-3, w
end
local recBad, recChecked, recWorst = 0, 0, 0
for f, list in pairs(recPos) do
	local ok, w = sameSet(list, bulletsAt(C.data, f, C.data[f].TotalTime))
	recChecked = recChecked + 1
	recWorst = math.max(recWorst, w)
	if not ok then recBad = recBad + 1 end
end
check(recChecked >= 170, "checked " .. recChecked .. " recorded frames with bullets")
eq(recBad, 0, "while recording every bullet is where its fire event puts it at that TAS time (worst " .. recWorst .. ")")
local tBad, tChecked, tWorst = 0, 0, 0
local testConn = RSvc.PreSimulation:Connect(function()
	if C.mode ~= 3 then return end
	local hf = workspace.CurrentCamera:FindFirstChild("HappaTASKit")
	local list = {}
	if hf then for _, m in ipairs(hf:GetChildren()) do list[#list + 1] = m:GetPivot().Position end end
	local ok, w = sameSet(list, bulletsAt(C.data, C.frame, C.TestingTimer))
	tChecked = tChecked + 1
	tWorst = math.max(tWorst, (w == math.huge) and 999 or w)
	if not ok then tBad = tBad + 1 end
end)
local firedBefore = TurretKit.fired
key(Enum.KeyCode.Three)
g2 = 0
while C.mode == 3 and g2 < 600 do M.step(1 / 60); g2 = g2 + 1 end
testConn:Disconnect()
check(tChecked >= 220, "checked " .. tChecked .. " playback frames")
eq(tBad, 0, "playback shows the saved bullets at the playback time (worst " .. tWorst .. ")")
check(TurretKit.fired > firedBefore, "the kit kept firing during the test (its bullets were removed)")
steps(2)
local leftover = 0
for _, c in ipairs(turModel:GetChildren()) do if c:IsA("Model") then leftover = leftover + 1 end end
eq(leftover, 0, "no kit bullet left from the test")
check(#workspace.CurrentCamera:FindFirstChild("HappaTASKit"):GetChildren() == 0, "Idle: HappaTAS's bullets are gone")
near(fireSnd.Volume, 0.6, 1e-9, "Idle: the kit's fire sound is back")

section("turrets: a bullet that hits your character does the kit's damage, saved and played back")
wall.Parent = nil
newTAS()
-- the character stands in the line of fire, 10 studs in front of the turret
hrp.CFrame = CFrame.new(0, 5, 60)
for _, p in ipairs(C.Char:GetChildren()) do if p:IsA("BasePart") and p ~= hrp then p.CFrame = CFrame.new(0, 5, 60) end end
local d0 = #CharMgr.damage
create()
click()
steps(150)
click()
steps(2)
local hits = 0
for _, fr in ipairs(C.data) do for _, e in ipairs(fr.KE or {}) do if e[1] == 2 and e[3] > 0 then hits = hits + 1; near(e[3], 5, 1e-9, "damage 5 saved") end end end
check(hits >= 1, "a bullet hit the character (" .. hits .. ")")
eq(#CharMgr.damage - d0, hits, "the kit's CharacterManager:Damage was called once per hit")
local d1 = #CharMgr.damage
key(Enum.KeyCode.Three)
g2 = 0
while C.mode == 3 and g2 < 600 do M.step(1 / 60); g2 = g2 + 1 end
eq(#CharMgr.damage - d1, hits, "the test deals the saved damage again")
hrp.CFrame = CFrame.new(0, 3, 0)
for _, p in ipairs(C.Char:GetChildren()) do if p:IsA("BasePart") and p ~= hrp then p.CFrame = CFrame.new(0, 3, 0) end end

section("turrets: a character that moves onto a bullet (already overlapping it) is hit too")
hrp.CFrame = CFrame.new(30, 5, 0)
for _, p in ipairs(C.Char:GetChildren()) do if p:IsA("BasePart") and p ~= hrp then p.CFrame = CFrame.new(30, 5, 0) end end
newTAS()
create()
click()
local hit2 = nil
for _ = 1, 150 do
	M.step(1 / 60)
	local hf = workspace.CurrentCamera:FindFirstChild("HappaTASKit")
	local m = hf and hf:GetChildren()[1]
	if m and not hit2 then
		-- the character jumps right onto the bullet, half a stud ahead of it
		local pos = m:GetPivot().Position + Vector3.new(0, 0, 0.5)
		hrp.CFrame = CFrame.new(pos)
		for _, p in ipairs(C.Char:GetChildren()) do if p:IsA("BasePart") and p ~= hrp then p.CFrame = CFrame.new(pos) end end
		hit2 = #C.data
	end
end
click()
steps(2)
local dmgF = nil
for f, fr in ipairs(C.data) do for _, e in ipairs(fr.KE or {}) do if e[1] == 2 and e[3] > 0 then dmgF = dmgF or f end end end
check(hit2 ~= nil and dmgF ~= nil and dmgF - hit2 <= 2, "the bullet ends with damage right after (" .. tostring(hit2) .. " -> " .. tostring(dmgF) .. ")")
hrp.CFrame = CFrame.new(0, 3, 0)
for _, p in ipairs(C.Char:GetChildren()) do if p:IsA("BasePart") and p ~= hrp then p.CFrame = CFrame.new(0, 3, 0) end end

section("turrets: MaxLifetime, paused, unpausing earlier")
newTAS()
create()
click()
steps(300)
click()
steps(2)
local life = nil
local f2 = {}
for f, fr in ipairs(C.data) do for _, e in ipairs(fr.KE or {}) do if e[1] == 1 then f2[e[3]] = fr.TotalTime elseif e[1] == 2 and f2[e[2]] then life = life or (fr.TotalTime - f2[e[2]]) end end end
check(life and life >= 2 - 1e-6 and life <= 2 + 1 / 60 + 1e-6, "no wall, no character: a bullet ends after MaxLifetime 2 s (" .. tostring(life) .. ")")
local firedP = TurretKit.fired
steps(120)
eq(TurretKit.fired, firedP, "paused: the kit doesn't fire (its clock stands still)")
local nEvents = 0
for _, fr in ipairs(C.data) do nEvents = nEvents + #(fr.KE or {}) end
-- go back to frame 100 and record from there
C.frame = 101
C.inputs.Back1F()
steps(2)
local shownAt100 = #workspace.CurrentCamera.HappaTASKit:GetChildren()
eq(shownAt100, #bulletsAt(C.data, 100, C.data[100].TotalTime), "paused on frame 100: its bullets are shown")
click()
steps(2)
local after = 0
for f = 1, #C.data do for _, e in ipairs(C.data[f].KE or {}) do after = after + 1 end end
check(after < nEvents, "unpausing at frame 100 cut the later events (" .. after .. " of " .. nEvents .. ")")
steps(120)
click()
steps(2)
local seqs, dup = {}, false
for _, fr in ipairs(C.data) do for _, e in ipairs(fr.KE or {}) do if e[1] == 1 then if seqs[e[3]] then dup = true end; seqs[e[3]] = true end end end
check(not dup, "bullet numbers stay unique after the cut")

end
do
section("turrets / kit events: save and load (file version 5), ids by key")
local okS, nS, bS, info = (function()
	local res
	M.resume(coroutine.create(function() res = table.pack(Store.SaveSlot("kit", C.data)) end))
	local g = 0
	while not res and g < 300 do M.step(1 / 60); g = g + 1 end
	return table.unpack(res or {})
end)()
check(okS, "saved")
eq(info and info.version, 5, "file version 5")
local loaded
M.resume(coroutine.create(function() local ok, fr = Store.LoadSlot("kit"); loaded = ok and fr end))
g2 = 0
while not loaded and g2 < 300 do M.step(1 / 60); g2 = g2 + 1 end
check(loaded ~= nil, "loaded")
eq(loaded and loaded.KitVersion, 1, "KitVersion 1 comes back")
local same = loaded ~= nil and #loaded == #C.data
if same then
	for i = 1, #loaded do
		local a1, b1 = C.data[i].KE or {}, loaded[i].KE or {}
		if #a1 ~= #b1 then same = false break end
		for k = 1, #a1 do
			for m = 1, #a1[k] do
				if math.abs((a1[k][m] or 0) - (b1[k][m] or 0)) > 1e-3 then same = false end
			end
		end
	end
end
check(same, "every kit event comes back (within the saved precision)")

end
do
section("codec: v5 columns round trip, an old file has no kit rules")
local frames = {}
for i = 1, 3 do
	frames[i] = { Cframe = { 0, 3, i, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, Velocity = { Linear = { 0, 0, 0 }, Angular = { 0, 0, 0 } }, State = 8,
		CamCframe = { 0, 10, 20, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, Zoom = 10, FrameTime = 1 / 60, TotalTime = i / 60, Mobile = 0,
		Anim = { Pose = 1, JumpTime = 0, Speed = 1, Anims = {} } }
end
frames[2].KE = { { 1, 7, 12, 1.5, -2.25, 3, 0.1, -0.2, 0.3, 0, 0, 50, 15 }, { 3, 4, 0 } }
frames[3].KE = { { 2, 12, 5 }, { 3, 4, 1 } }
frames[2].SK = 0.25
local bytes, inf = Codec.Encode(frames, nil, nil, nil, { version = 1, keys = { { id = 7, key = "ClientParts/Turret" }, { id = 4, key = "ClientParts/Spawner" } } })
eq(inf.version, 5, "kit events / speed factors make a v5 file")
local back, _, _, kitT = Codec.Decode(bytes)
eq(back[2].KE and #back[2].KE, 2, "frame 2: 2 events")
near(back[2].KE[1][5], -2.25, 1e-9, "fire position")
near(back[2].KE[1][8], -0.2, 1e-9, "fire rotation")
near(back[2].KE[1][12], 50, 1e-9, "fire velocity")
near(back[2].KE[1][13], 15, 1e-9, "lifetime")
eq(back[3].KE[1][2], 12, "end: bullet number")
near(back[3].KE[1][3], 5, 1e-9, "end: damage")
eq(back[2].KE[2][3], 0, "pushbox: there at the start")
eq(back[3].KE[2][3], 1, "pushbox: spawned")
near(back[2].SK, 0.25, 1e-9, "speed factor")
eq(back[1].SK, nil, "no factor on a normal frame")
eq(kitT and kitT.version, 1, "kit rules version")
eq(kitT and #kitT.keys, 2, "kit keys")
local plainBytes, plainInf = Codec.Encode({ frames[1] }, nil, nil, nil, { version = 0, keys = {} })
check(plainInf.version < 5, "a TAS without kit rules / events stays an older version (" .. plainInf.version .. ")")
M.fs["HappaTasPort/1234567/old.tas"] = plainBytes
local oldLoaded
M.resume(coroutine.create(function() local ok, fr = Store.LoadSlot("old"); oldLoaded = ok and fr end))
steps(2)
eq(oldLoaded and oldLoaded.KitVersion, 0, "loading an older file: KitVersion 0 (the kit's own behaviour)")

end
-- ------------------------------------------------------------------------------------------------ pushboxes
do
section("pushbox spawns: a box from later in the TAS is hidden on earlier frames")
coroutine.close(turThread)
newTAS()
create()
click()
steps(60)
local box = Instance.new("Model"); box.Name = "Pushbox"
local boxPart = part(box, "Pushbox", Vector3.new(-20, 2.5, 127), Vector3.new(4, 4, 4), false)
box.Parent = spModel
local spawnF = #C.data
steps(60)
click()
steps(2)
local spawnEv = nil
for f, fr in ipairs(C.data) do for _, e in ipairs(fr.KE or {}) do if e[1] == 3 and e[3] == 1 then spawnEv = f end end end
check(spawnEv ~= nil and math.abs(spawnEv - spawnF) <= 1, "the spawn was saved at frame " .. tostring(spawnEv))
C.frame = 31
C.inputs.Back1F()
steps(2)
eq(boxPart.Transparency, 1, "frame 30: the box is hidden")
eq(boxPart.CanCollide, false, "and can't be touched")
C.frame = spawnEv + 11
C.inputs.Back1F()
steps(2)
eq(boxPart.Transparency, 0, "after the spawn: visible again")
check(boxPart.CanCollide, "and solid")
C.frame = 21
C.inputs.Back1F()
steps(2)
idle()
eq(boxPart.Transparency, 0, "Idle: shown again")

end
-- ------------------------------------------------------------------------------------------------ effects
do
section("bounce pads / jump launchers: the effect is saved and played again while testing")
-- the kit's bounce pad: its sound in its configuration, a BounceParticle; the kit's playSoundFromInstance puts a
-- copy of the sound into the pad and plays it (Interactables/BouncePad bounce())
local pad = part(CP, "BouncePad", Vector3.new(-40, 1, 0), Vector3.new(4, 1, 4))
local padCfg = Instance.new("Configuration"); padCfg.Name = "BouncePadConfiguration"
local padSnd = Instance.new("Sound"); padSnd.Name = "BounceSound"; padSnd.Volume = 0.7; padSnd.TimeLength = 0.5
padSnd.Parent = padCfg
padCfg.Parent = pad
local att = Instance.new("Attachment"); att.Name = "ParticleAtt"; att.Parent = pad
local padBurst = Instance.new("ParticleEmitter"); padBurst.Name = "BounceParticle"; padBurst.Parent = att
-- a jump launcher: Sounds folder (Tick on entering, Bounce on the launch), Particles.BounceParticle
local lModel = Instance.new("Model"); lModel.Name = "JumpGroup"; lModel.Parent = CP
local launcher = part(lModel, "JumpLauncher", Vector3.new(-50, 1, 0), Vector3.new(4, 1, 4))
local lCfg = Instance.new("Configuration"); lCfg.Name = "LauncherConfiguration"; lCfg.Parent = launcher
local lSounds = Instance.new("Folder"); lSounds.Name = "Sounds"; lSounds.Parent = launcher
local tick = Instance.new("Sound"); tick.Name = "Tick"; tick.Volume = 0.4; tick.TimeLength = 0.2; tick.Parent = lSounds
local bounce = Instance.new("Sound"); bounce.Name = "Bounce"; bounce.Volume = 0.8; bounce.TimeLength = 0.4; bounce.Parent = lSounds
local lAtt = Instance.new("Attachment"); lAtt.Name = "Particles"; lAtt.Parent = launcher
local lBurst = Instance.new("ParticleEmitter"); lBurst.Name = "BounceParticle"; lBurst.Parent = lAtt
steps(2) -- (new kit objects are looked at a little later)
local function kitPlay(snd, into)
	local c = snd:Clone(); c.Parent = into; c:Play()
	return c
end
newTAS()
create()
click()
steps(20)
kitPlay(padSnd, pad); padBurst:Emit(1)
local padF = #C.data
steps(15)
kitPlay(tick, launcher)
local tickF = #C.data
steps(10)
kitPlay(bounce, launcher); lBurst:Emit(1)
local bounceF = #C.data
steps(20)
click()
steps(2)
local got = {}
for f, fr in ipairs(C.data) do
	for _, e in ipairs(fr.KE or {}) do if e[1] == 4 then got[#got + 1] = { f, e[3] } end end
end
eq(#got, 3, "3 effects saved")
eq(got[1] and got[1][1], padF, "the bounce pad's on its frame")
eq(got[1] and got[1][2], 1, "as BounceSound")
eq(got[2] and got[2][1], tickF, "the launcher's Tick on its frame")
eq(got[2] and got[2][2], 2, "as Tick")
eq(got[3] and got[3][1], bounceF, "the launch on its frame")
eq(got[3] and got[3][2], 3, "as Bounce")
-- testing: each one again when playback passes its frame
M.emitLog = {}
local testCopies = {}
local lCopies = {}
local cc = pad.ChildAdded:Connect(function(ch) if ch:IsA("Sound") then testCopies[#testCopies + 1] = ch end end)
local cl = launcher.ChildAdded:Connect(function(ch) if ch:IsA("Sound") then lCopies[#lCopies + 1] = ch.Name end end)
key(Enum.KeyCode.Three)
steps(30)
local kitCopy = kitPlay(padSnd, pad) -- (the kit plays its own while testing: muted, the TAS has its own)
steps(80)
cc:Disconnect()
cl:Disconnect()
eq(#testCopies, 2, "Test: the pad's sound played (+ the kit's own copy)")
eq(table.concat(lCopies, ","), "Tick,Bounce", "Test: the launcher's Tick, then its Bounce")
eq(kitCopy.Volume, 0, "Test: the kit's own sound is muted")
local padEmits, lEmits = 0, 0
for _, e in ipairs(M.emitLog) do
	if e[1] == padBurst then padEmits = padEmits + 1 elseif e[1] == lBurst then lEmits = lEmits + 1 end
end
eq(padEmits, 1, "Test: the pad's particle burst")
eq(lEmits, 1, "Test: the launcher's burst on the launch only (not on Tick)")
local ourPad = nil
for _, c in ipairs(testCopies) do if c ~= kitCopy then ourPad = c end end
check(ourPad ~= nil and math.abs(ourPad.Volume - 0.7) < 1e-9, "Test: HappaTAS's copy plays at the sound's volume")
idle()
-- save / load: ids by key
local okS2
M.resume(coroutine.create(function() okS2 = Store.SaveSlot("fx", C.data) end))
steps(5)
local loadedFx
M.resume(coroutine.create(function() local ok, fr = Store.LoadSlot("fx"); loadedFx = ok and fr end))
steps(5)
check(okS2 and loadedFx ~= nil, "saved and loaded")
local got2 = {}
for f, fr in ipairs(loadedFx or {}) do
	for _, e in ipairs(fr.KE or {}) do if e[1] == 4 then got2[#got2 + 1] = { f, e[2], e[3] } end end
end
eq(#got2, 3, "the 3 effects come back")
local key1 = got2[1] and KO.Reg.idToKey[got2[1][2]]
check(key1 ~= nil and key1:find("BouncePad", 1, true) ~= nil, "the pad's id points at the pad (" .. tostring(key1) .. ")")
eq(got2[3] and got2[3][3], 3, "the launch's sound code")

end
-- ------------------------------------------------------------------------------------------------ forces
do
section("forces a kit script puts on the character: removed after unpausing earlier, off while testing")
newTAS()
create()
click()
steps(60)
local lv = Instance.new("LinearVelocity"); lv.VectorVelocity = Vector3.new(0, 60, 0); lv.Parent = hrp
local lvF = #C.data
steps(30)
click()
steps(2)
C.frame = lvF - 10 + 1
C.inputs.Back1F()
steps(2)
click()
steps(3)
eq(lv.Parent, nil, "unpausing 10 frames before it was added: the launcher's push is gone")
steps(30)
click()
steps(2)
key(Enum.KeyCode.Three)
steps(5)
local lv2 = Instance.new("LinearVelocity"); lv2.VectorVelocity = Vector3.new(0, 60, 0); lv2.Parent = hrp
steps(2)
eq(lv2.Enabled, false, "testing: a push added by a kit script is switched off")
g2 = 0
while C.mode == 3 and g2 < 600 do M.step(1 / 60); g2 = g2 + 1 end
lv2:Destroy()

end
-- ------------------------------------------------------------------------------------------------ the world
do
section("speed hack: the world slows down with the character")
newTAS()
S.Set("Speed Hack", 1)
S.Set("Speed Hack Speed", 0.5)
steps(5)
create()
click()
steps(3)
near(hinge.AngularVelocity, -0.75, 1e-9, "hinge motor AngularVelocity x 0.5")
eq(hinge.MotorMaxTorque, math.huge, "infinite torque stays infinite")
check(vf.Force == Vector3.new(0, 0, 1000), "VectorForce x 0.25 (" .. tostring(vf.Force) .. ")")
near(ap.MaxVelocity, 1000, 1e-9, "AlignPosition MaxVelocity x 0.5")
near(ap.Responsiveness, 7.5, 1e-9, "AlignPosition Responsiveness x 0.5")
near(ap.MaxForce, 2500, 1e-9, "AlignPosition MaxForce x 0.25")
check(bv.Velocity == Vector3.new(0.5, 1, 1.5), "BodyVelocity Velocity x 0.5")
near(bv.P, 625, 1e-9, "BodyVelocity P x 0.5")
check(conveyor.AssemblyLinearVelocity == Vector3.new(5, 0, 0), "conveyor x 0.5 (" .. tostring(conveyor.AssemblyLinearVelocity) .. ")")
check(freeBox.AssemblyLinearVelocity == Vector3.new(0, 0, 4), "a free part goes on at half speed")
local push = Instance.new("LinearVelocity"); push.VectorVelocity = Vector3.new(0, 60, 0); push.MaxAxesForce = Vector3.new(40000, 40000, 40000)
push.Parent = hrp
steps(2)
check(push.VectorVelocity == Vector3.new(0, 30, 0), "a push added while slowed (jump launcher) x 0.5")
check(push.MaxAxesForce == Vector3.new(10000, 10000, 10000), "its force limit x 0.25")
hinge.AngularVelocity = -3 -- the game writes a new value
steps(2)
near(hinge.AngularVelocity, -1.5, 1e-9, "a value the game writes while slowed is the new normal value (x 0.5)")
click()
steps(3)
near(hinge.AngularVelocity, -3, 1e-9, "paused: the game's latest value")
check(vf.Force == Vector3.new(0, 0, 4000), "VectorForce back")
near(ap.MaxVelocity, 2000, 1e-9, "AlignPosition back")
near(ap.Responsiveness, 15, 1e-9, "Responsiveness back")
check(bv.Velocity == Vector3.new(1, 2, 3), "BodyVelocity back")
check(conveyor.AssemblyLinearVelocity == Vector3.new(10, 0, 0), "conveyor back")
check(freeBox.AssemblyLinearVelocity == Vector3.new(0, 0, 8), "the free part at full speed again")
check(push.VectorVelocity == Vector3.new(0, 60, 0), "the push back to its own value")
local sk = nil
for _, fr in ipairs(C.data) do if fr.SK then sk = fr.SK break end end
near(sk, 0.5, 1e-9, "slow frames carry their factor (SK 0.5)")
push:Destroy()
S.Set("Speed Hack", 0)

end
-- ------------------------------------------------------------------------------------------------ lighting
do
section("Sync Lighting: Idle and an empty TAS leave the lighting as it is")
local L = M.services.Lighting
newTAS()
L.ClockTime = 20
steps(2)
create()
steps(3)
near(L.ClockTime, 20, 1e-9, "Create on an empty TAS: the lighting stays")
click()
steps(30)
L.ClockTime = 6
steps(30)
click()
steps(2)
near(L.ClockTime, 6, 1e-9, "paused on the last frame: its lighting")
C.frame = 11
C.inputs.Back1F()
steps(2)
near(L.ClockTime, 20, 1e-9, "frame 10: the lighting it had then")
idle()
steps(3)
near(L.ClockTime, 20, 1e-9, "Idle (key 1): the lighting stays exactly as it was (not back to the old default 14)")

end
do
section("unload: the kit gets its own task / os back, waiting kit threads finish in real time")
idle()
local late = nil
task.spawn(function() Timer.WaitOnce(1); late = M.now end)
local uStart = M.now
steps(10)
__T.Core.State.inputs = __T.Core.State.inputs -- (keep the reference)
local handle = getgenv().__HappaTAS
handle.Unload()
steps(2)
eq(rawget(timerEnv, "task"), nil, "the module's own task again")
eq(rawget(timerEnv, "os"), nil, "and its own os")
eq(Functions.tween, origTween, "Functions.tween back")
check(isreadonly(Functions), "still read-only")
steps(60)
check(late ~= nil and late - uStart >= 1 - 1e-6 and late - uStart <= 1 + 2 / 60 + 1e-6, "a wait started before Unload ends on time (" .. tostring(late and (late - uStart)) .. ")")
beatConn:Disconnect()
end
end
kitTests()
finish()
