-- ================================================================================================
-- HappaTAS 3, phase 4: the EToH kit's objects (V2.38.17's tests/test_kit.lua kit object sections, the same
-- kit stand-ins and numbers, through a shim for the V2 internals they read): beat blocks from the TAS time,
-- turrets' bullets as events (positions, hits, damage, MaxLifetime, cut frames), pushbox spawns, bounce pad
-- / jump launcher effects, forces a kit script puts on the character, saving and loading (v6, ids by key),
-- and the world in slow motion with the kit's parts. V2's v5 codec section is left out (phase 3's reader
-- tests and tests3/test_world.lua cover V2 files).
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
local KO = E.kitObjects.KO
-- (V2's C.data: the run as V2 frames with its KitVersion, made again at most once per mock frame)
local snap = { frame = -1, count = -1, ver = -1, data = nil }
local function frames()
	local tl = E.tl
	if snap.frame ~= M.frame or snap.count ~= tl:count() or snap.ver ~= tl.version then
		local d = tl:toV2All()
		d.KitVersion = tl.meta and tl.meta.kitVersion
		snap.frame, snap.count, snap.ver, snap.data = M.frame, tl:count(), tl.version, d
	end
	return snap.data
end
local Core = { SetTAS = function(fr)
	E.modes:setRun(fr)
	E.tl.meta.kitVersion = fr.KitVersion
end }
local function waitIdle() local g = 0; while E.busy and g < 600 do task.wait(); g = g + 1 end end
local Store = {
	SaveSlot = function(name)
		local ok, why = E.persist:save(name)
		if ok then task.wait(); waitIdle() end
		return ok, why, nil, { version = 6 }
	end,
	LoadSlot = function(name)
		local ok, why = E.persist:load(name .. ".tas")
		if not ok then return false, why end
		task.wait(); waitIdle()
		return true, frames()
	end,
}
-- (the parts of V2's Core.State these sections read)
local C = setmetatable({}, { __newindex = function(_, k, v)
	if k == "frame" then E.frame = v else rawset(_, k, v) end
end, __index = function(_, k)
	if k == "data" then return frames() end
	if k == "TestingTimer" then return E.testTime end
	if k == "Char" then return E.char.model end
	if k == "inputs" then return { Back1F = function() E.modes:back1() end } end
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
check(C.data.KitVersion == 2, "the TAS knows it was made with the kit rules (KitVersion 2: vanishers too)")

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
section("turrets / kit events: save and load (file version 6), ids by key")
local okS, nS, bS, info = (function()
	local res
	M.resume(coroutine.create(function() res = table.pack(Store.SaveSlot("kit", C.data)) end))
	local g = 0
	while not res and g < 300 do M.step(1 / 60); g = g + 1 end
	return table.unpack(res or {})
end)()
check(okS, "saved")
eq(info and info.version, 6, "file version 6")
local loaded
M.resume(coroutine.create(function() local ok, fr = Store.LoadSlot("kit"); loaded = ok and fr end))
g2 = 0
while not loaded and g2 < 300 do M.step(1 / 60); g2 = g2 + 1 end
check(loaded ~= nil, "loaded")
eq(loaded and loaded.KitVersion, 2, "KitVersion 2 comes back")
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
-- ------------------------------------------------------------------------------------------------ vanishers
do
section("vanishers: the fade, the vanish and the respawn come from the TAS time")
-- (live: after going back mid-fade and unpausing, the kit's finished tween left the part stuck; in Test the
-- kit's leftover timer jumped it to vanished. Mock: no kit script at all, so only HappaTAS writes, plus one
-- write standing in for the kit's)
local vFolder = folder(CP, "VanisherGroup")
local vPart = part(vFolder, "Vanisher", Vector3.new(30, 2, 40), Vector3.new(4, 4, 4))
vPart:SetAttribute("Activated", false) -- (as live: not button activated)
-- (found while vanished, as live after a run: its normal values come from the kit's own table)
vPart.Transparency, vPart.CanCollide, vPart.CanTouch = 1, false, false
M.gcTables[#M.gcTables + 1] = { part = vPart, defaults = { DefaultTransparency = 0, DefaultCanCollide = true,
	TouchedTransparency = 1, TouchedCanCollide = false, OriginalTransparency = 0 } }
local vCfg = Instance.new("Configuration"); vCfg.Name = "VanisherConfiguration"
vCfg:SetAttribute("VanishMode", "Fade"); vCfg:SetAttribute("RespawnTime", 2)
local vTw = Instance.new("Configuration"); vTw.Name = "TweenConfiguration"; vTw:SetAttribute("Time", 1); vTw.Parent = vCfg
vCfg.Parent = vFolder
steps(5)
newTAS()
hrp.CFrame = CFrame.new(0, 3, 40)
steps(2)
create()
click()
steps(20)
hrp.CFrame = CFrame.new(30, 5, 40) -- (on it)
steps(1)
local function tAt(i) return E.tl:get("TotalTime", i, 1) end
local t0 = tAt(E.tl:count())
local truth = {}
local function rec(n)
	for _ = 1, n do
		M.step(1 / 60)
		truth[#truth + 1] = { tAt(E.tl:count()), vPart.Transparency, vPart.CanCollide, vPart.CanTouch }
	end
end
rec(18)
vPart.Transparency = 1 -- (the kit's own write, early)
rec(1)
check(vPart.Transparency < 0.5, "a write of the kit's is undone (" .. vPart.Transparency .. ")")
hrp.CFrame = CFrame.new(0, 3, 40) -- (off it)
rec(220)
click()
steps(2)
local function truthAt(t) local b for _, r in ipairs(truth) do if r[1] <= t + 1e-9 then b = r end end return b end
local half = truthAt(t0 + 0.5)
check(half and math.abs(half[2] - 0.5) < 0.04 and half[3] == true, "half way through the fade: Transparency 0.5, still solid (" .. tostring(half and half[2]) .. ")")
local gone = truthAt(t0 + 1.3)
check(gone and gone[2] == 1 and gone[3] == false and gone[4] == false, "after the 1 s fade: vanished, not solid, no touches")
local back = truthAt(t0 + 3.3)
check(back and back[2] == 0 and back[3] == true and back[4] == true, "2 s later: back")
local ev = 0
for i = 1, E.tl:count() do for _, e in ipairs(E.tl:getList("v2KE", i) or {}) do if e[1] == 5 then ev = ev + 1 end end end
eq(ev, 1, "one touch saved (kit event 5)")
eq(E.tl.meta.kitVersion, 2, "the kit rules version 2")

section("vanishers: paused on any frame, going on from it, Test")
local fMid
for i = 1, E.tl:count() do if tAt(i) <= t0 + 0.4 then fMid = i end end
E.modes:seek(fMid)
steps(2)
check(math.abs(vPart.Transparency - 0.4) < 0.04 and vPart.CanCollide, "on a frame 0.4 s into the fade: its Transparency (" .. vPart.Transparency .. ")")
E.modes:seek(E.tl:count())
steps(2)
eq(vPart.Transparency, 0, "on the last frame: back")
E.modes:seek(fMid)
steps(2)
click() -- (unpausing 0.4 s into the fade)
local after = {}
for _ = 1, 50 do
	M.step(1 / 60)
	after[#after + 1] = { tAt(E.tl:count()), vPart.Transparency, vPart.CanCollide }
end
click()
steps(2)
local worst, goneT = 0, nil
for _, a in ipairs(after) do
	local r = truthAt(a[1])
	if r then worst = math.max(worst, math.abs(r[2] - a[2])) end
	if not goneT and a[3] == false then goneT = a[1] end
end
check(worst < 0.04, "unpaused mid-fade: the fade goes on as recorded (worst " .. string.format("%.3f", worst) .. ")")
check(goneT and math.abs(goneT - (t0 + 1)) < 0.04, "and it vanishes at the same TAS time (" .. tostring(goneT) .. ")")
-- Test: the recording's fade, no jumps
key(Enum.KeyCode.Three)
local worstT, n = 0, 0
local g = 0
while E.mode == 3 and g < 600 do
	M.step(1 / 60)
	g = g + 1
	local r = truthAt(E.testTime)
	if r and E.testTime > t0 and E.testTime < t0 + 1.2 then
		worstT = math.max(worstT, math.abs(r[2] - vPart.Transparency))
		n = n + 1
	end
end
check(n > 20 and worstT < 0.05, "Test: the fade as recorded (worst " .. string.format("%.3f", worstT) .. " over " .. n .. " frames)")

section("vanishers: save / load, and a run from before keeps the kit's")
local res
M.resume(coroutine.create(function() res = table.pack(Store.SaveSlot("vanish", C.data)) end))
local g3 = 0
while not res and g3 < 300 do M.step(1 / 60); g3 = g3 + 1 end
local loaded
M.resume(coroutine.create(function() local ok, fr = Store.LoadSlot("vanish"); loaded = ok and fr end))
g3 = 0
while not loaded and g3 < 300 do M.step(1 / 60); g3 = g3 + 1 end
local ev2 = 0
for i = 1, loaded and #loaded or 0 do for _, e in ipairs(loaded[i].KE or {}) do if e[1] == 5 then ev2 = ev2 + 1 end end end
eq(ev2, 1, "the touch comes back")
eq(loaded and loaded.KitVersion, 2, "version 2 comes back")
local old = {}
for i = 1, 40 do old[i] = { FrameTime = 1 / 60, TotalTime = i / 60, Cframe = { 0, 3, 40, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
	Velocity = { Linear = { 0, 0, 0 }, Angular = { 0, 0, 0 } }, State = 8 } end
old.KitVersion = 1
idle()
Core.SetTAS(old)
create()
vPart.Transparency = 0.7
steps(3)
eq(vPart.Transparency, 0.7, "a run made with version 1: the vanisher is the kit's")
idle()
vPart.Transparency = 0
vFolder:Destroy()
end
-- ------------------------------------------------------------------------------------------------ the world
do
section("speed hack: the world speeds up with the character (the scaling: above 1x)")
newTAS()
S.Set("Speed Hack", 1)
S.Set("Speed Hack Speed", 2)
steps(5)
create()
click()
steps(3)
near(hinge.AngularVelocity, -3, 1e-9, "hinge motor AngularVelocity x 2")
eq(hinge.MotorMaxTorque, math.huge, "infinite torque stays infinite")
check(vf.Force == Vector3.new(0, 0, 16000), "VectorForce x 4 (" .. tostring(vf.Force) .. ")")
near(ap.MaxVelocity, 4000, 1e-9, "AlignPosition MaxVelocity x 2")
near(ap.Responsiveness, 30, 1e-9, "AlignPosition Responsiveness x 2")
near(ap.MaxForce, 40000, 1e-9, "AlignPosition MaxForce x 4")
check(bv.Velocity == Vector3.new(2, 4, 6), "BodyVelocity Velocity x 2")
near(bv.P, 2500, 1e-9, "BodyVelocity P x 2")
check(conveyor.AssemblyLinearVelocity == Vector3.new(20, 0, 0), "conveyor x 2 (" .. tostring(conveyor.AssemblyLinearVelocity) .. ")")
check(freeBox.AssemblyLinearVelocity == Vector3.new(0, 0, 16), "a free part goes on at twice the speed")
local push = Instance.new("LinearVelocity"); push.VectorVelocity = Vector3.new(0, 60, 0); push.MaxAxesForce = Vector3.new(40000, 40000, 40000)
push.Parent = hrp
steps(2)
check(push.VectorVelocity == Vector3.new(0, 120, 0), "a push added while sped up (jump launcher) x 2")
check(push.MaxAxesForce == Vector3.new(160000, 160000, 160000), "its force limit x 4")
hinge.AngularVelocity = -4 -- the game writes a new value
steps(2)
near(hinge.AngularVelocity, -8, 1e-9, "a value the game writes while sped up is the new normal value (x 2)")
click()
steps(3)
near(hinge.AngularVelocity, -4, 1e-9, "paused: the game's latest value")
check(vf.Force == Vector3.new(0, 0, 4000), "VectorForce back")
near(ap.MaxVelocity, 2000, 1e-9, "AlignPosition back")
near(ap.Responsiveness, 15, 1e-9, "Responsiveness back")
check(bv.Velocity == Vector3.new(1, 2, 3), "BodyVelocity back")
check(conveyor.AssemblyLinearVelocity == Vector3.new(10, 0, 0), "conveyor back")
check(freeBox.AssemblyLinearVelocity == Vector3.new(0, 0, 8), "the free part at full speed again")
check(push.VectorVelocity == Vector3.new(0, 60, 0), "the push back to its own value")
local sk = nil
for _, fr in ipairs(C.data) do if fr.SK then sk = fr.SK break end end
near(sk, 2, 1e-9, "fast frames carry their factor (SK 2)")
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

section("the frames view keeps no memory per frame (a long run read through it)")
do
	-- (V2's kit code reads the run frame by frame; one proxy kept per frame index was ~250 bytes a frame for
	-- the rest of the session: 35 MB for 10 minutes at 240 FPS)
	local Timeline = __T3("engine/timeline")
	local tl = Timeline.newLike(E.tl)
	local fr = {}
	for i = 1, 20000 do fr[i] = { TotalTime = i / 240, FrameTime = 1 / 240 } end
	tl:replaceFromV2(fr)
	fr = nil
	local view = E.plugins:get("kitobjects").framesOf(tl)
	collectgarbage("collect")
	local m0 = collectgarbage("count")
	local seen = 0
	for f = 1, #view do
		local p = view[f]
		if p and p.KE == nil and p.TotalTime then seen = seen + 1 end
	end
	collectgarbage("collect")
	local kb = collectgarbage("count") - m0
	eq(seen, 20000, "every frame read through the view")
	check(kb < 300, string.format("memory kept after reading 20000 frames: %.0f KB", kb))
	near(view[123].TotalTime, 123 / 240, 1e-9, "a frame read again after the collection")
end

if beatConn then beatConn:Disconnect() end
end
kitTests()
finish()
