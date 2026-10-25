-- ================================================================================================
-- HappaTAS 3, phase 4: the Kit Clock (V2.38.17's tests/test_kit.lua Kit Clock sections, the same kit
-- stand-ins and numbers, through a shim for the V2 internals they read): the kit modules' task.wait /
-- task.delay / os.clock and Utility.Functions.tween run on the TAS clock (real time in Idle, stopped while
-- paused, x the speed hack while recording); the kit's frame listeners get the kit's dt; a pause gives the
-- kit no extra frame; Unload gives the environments back. Plus Frame Step: the kit's clock moves on by the
-- steps that run (V2's tests/test_speedhack.lua:287).
-- (headless mock: the kit modules are small stand-ins written like the kit's, not the real kit)
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
-- ------------------------------------------------------------------------------------------------ boot
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local SettingsMod = __T3("engine/settings")
local S = {
	Set = function(name, v) return E.settings:set(SettingsMod.byV2[name].key, v) end,
	Get = function(name) return E.settings:get(SettingsMod.byV2[name].key) end,
}
local KC = E.kitClock.KC
-- (the parts of V2's Core.State these sections read)
local C = setmetatable({}, { __index = function(_, k)
	if k == "data" then return E.tl:toV2All() end
	if k == "paused" then return E.paused end
	if k == "mode" then return E.mode end
	if k == "frame" then return E.frame end
	if k == "Humanoid" then return E.char.hum end
	if k == "HRP" then return E.char.hrp end
	return nil
end })
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
local function newTAS() idle(); E.modes:setRun({}); steps(1) end

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

section("Frame Step: the kit's clock moves on by the steps that run only")
newTAS()
S.Set("Speed Hack", 1)
S.Set("Speed Hack Speed", 0.5)
S.Set("Speed Hack Frame Step", 1)
create()
click()
steps(2)
local k0 = KC.Now()
steps(40)
local k1 = KC.Now()
click()
steps(2)
near(k1 - k0, 20 / 60, 1e-6, "the kit's clock moved on by the 20 steps that ran (" .. (k1 - k0) .. ")")
S.Set("Speed Hack Frame Step", 0)
S.Set("Speed Hack", 0)
idle()

section("the frame listeners: only kit functions are looked into (HappaTAS's own code keeps its fast paths)")
do
	-- asking for a function's environment switches Luau's fast paths off for that environment: never for
	-- HappaTAS's own listeners (or anything that isn't a kit module's)
	local Env = __T3("platform/env")
	local realEnvOf = Env.envOf
	local asked = {}
	Env.envOf = function(f) asked[#asked + 1] = f; return realEnvOf(f) end
	newTAS()
	Ride.Start(5)
	create()
	steps(20) -- (paused: the kit clock stopped, its listeners are looked for every frame)
	Ride.Stop()
	idle()
	Env.envOf = realEnvOf
	local bad = 0
	for _, f in ipairs(asked) do
		local src = debug.info(f, "s")
		if not (src and src:find("Framework.Kit", 1, true)) then bad = bad + 1 end
	end
	check(#asked > 0, "the kit's listeners were looked into (" .. #asked .. ")")
	eq(bad, 0, "nothing else was")
end

section("no executor support: without getloadedmodules nothing is patched, nothing errors")
do
	local Env = __T3("platform/env")
	local saved = Env.getloadedmodules
	Env.getloadedmodules = nil
	S.Set("Kit Scripts On TAS Clock", 0)
	steps(2)
	S.Set("Kit Scripts On TAS Clock", 1)
	steps(2)
	eq(KC.patched, 0, "no kit environment patched")
	Env.getloadedmodules = saved
	S.Set("Kit Scripts On TAS Clock", 0)
	steps(2)
	S.Set("Kit Scripts On TAS Clock", 1)
	steps(2)
	eq(KC.patched, 8, "patched again with it")
end

section("unload: the kit gets its own task / os back, waiting kit threads finish in real time")
idle()
local late = nil
task.spawn(function() Timer.WaitOnce(1); late = M.now end)
local uStart = M.now
steps(10)
local handle = getgenv().__HappaTAS3
handle.Unload()
steps(2)
eq(rawget(timerEnv, "task"), nil, "the module's own task again")
eq(rawget(timerEnv, "os"), nil, "and its own os")
eq(Functions.tween, origTween, "Functions.tween back")
check(isreadonly(Functions), "still read-only")
steps(60)
check(late ~= nil and late - uStart >= 1 - 1e-6 and late - uStart <= 1 + 2 / 60 + 1e-6, "a wait started before Unload ends on time (" .. tostring(late and (late - uStart)) .. ")")
if beatConn then beatConn:Disconnect() end
end
end
kitTests()
finish()
