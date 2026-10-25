-- needs: v2fixtures
-- ================================================================================================
-- HappaTAS 3, phase 4: the world plugins together. Unload in every state puts the world back (client objects,
-- time control, the kit clock, kit objects, buttons, lighting); every world setting can be switched off and on
-- mid-run (recording, paused, Test) without touching the run; a V2 file with client object, button and kit
-- data plays and comes back the same after a v6 save and load.
-- (headless mock: the kit modules are small stand-ins written like the kit's, not the real kit)
-- ================================================================================================
local RS, UIS = M.services.RunService, M.services.UserInputService
local genv = getgenv()
local RSt = M.services.ReplicatedStorage

-- ------------------------------------------------------------------------------------------------ the world
local function folder(parent, name) local f = Instance.new("Folder"); f.Name = name; f.Parent = parent; return f end
local fw = folder(RSt, "Framework")
local kitF = folder(fw, "Kit")
local repo = folder(kitF, "Repository")
local visual, inter, physicsF = folder(repo, "Visual"), folder(repo, "Interactables"), folder(repo, "Physics")
local utilF = folder(kitF, "Utility")
local function kitModule(parent, name, src)
	local ms = Instance.new("ModuleScript"); ms.Name = name; ms.Parent = parent
	local env = setmetatable({ script = ms }, { __index = setmetatable({ os = os }, { __index = getfenv(1) }) })
	local chunk = loadstring(src, "=" .. ms:GetFullName())
	setfenv(chunk, env)
	local mod = chunk()
	M.modules[ms] = mod
	return ms, mod, env
end
local _, Timer, timerEnv = kitModule(physicsF, "Timer", [[
local T = { ticks = 0 }
function T.Run(d) while true do task.wait(d); T.ticks = T.ticks + 1 end end
return T
]])
local _, Ride = kitModule(physicsF, "Ride", [[
local RunService = game:GetService("RunService")
local R = { dist = 0 }
function R.Start(speed) R.conn = RunService.Heartbeat:Connect(function(dt) R.dist = R.dist + speed * dt end) end
return R
]])
local _, Functions = kitModule(utilF, "Functions", [[
local F = {}
local TweenService = game:GetService("TweenService")
function F.tween(instance, config, goal) local tw = TweenService:Create(instance, TweenInfo.new(config), goal); tw:Play(); return tw end
return F
]])
local origTween = Functions.tween
M.readonly[Functions] = true
local bbMs, BeatKit = kitModule(visual, "BeatBlock", [[
local B = {}
function B.Loop(groups, n, start)
	local beat = start
	while true do
		beat = beat % n + 1
		for i, list in pairs(groups) do for _, p in ipairs(list) do p.Transparency = (i == beat) and 0 or 0.7 end end
		task.wait(1)
	end
end
return B
]])
local ding = Instance.new("Sound"); ding.Name = "DefaultDingSound"; ding.Volume = 0.5; ding.TimeLength = 0.4; ding.Parent = bbMs
local _, TurretKit = kitModule(inter, "Turret", [[
local T = {}
function T.Loop(model, part, rate, speed)
	while true do
		task.wait(1 / rate)
		local m = Instance.new("Model"); m.Name = "Bullet"
		local p = Instance.new("Part"); p.Name = "Bullet"; p.Size = Vector3.new(1, 1, 1); p.CFrame = part.CFrame; p.Parent = m
		m.PrimaryPart = p
		m.Parent = model
	end
end
return T
]])
local CP = folder(workspace, "ClientParts")
local function part(parent, name, pos, anchored)
	local p = Instance.new("Part"); p.Name = name; p.Size = Vector3.new(4, 1, 4); p.CFrame = CFrame.new(pos)
	p.Anchored = anchored ~= false; p.Parent = parent
	return p
end
-- 50 client objects, 10 of them moved by a script, 5 free
local cof = folder(CP, "Moving Platforms")
local movers, free = {}, {}
for i = 1, 50 do
	local p = part(cof, "P" .. i, Vector3.new((i % 10) * 6, 3, 20 + math.floor(i / 10) * 6), i > 5)
	if i <= 5 then free[#free + 1] = p elseif i <= 15 then movers[#movers + 1] = p end
end
local moveConn = RS.Heartbeat:Connect(function()
	for k, p in ipairs(movers) do p.CFrame = p.CFrame * CFrame.Angles(0, 0.02 * k, 0) end
end)
-- the speed hack's world: a hinge motor, a conveyor, a bounce pad's kit config
local hinge = Instance.new("HingeConstraint"); hinge.ActuatorType = Enum.ActuatorType.Motor; hinge.AngularVelocity = -1.5
hinge.MotorMaxTorque = 1e6; hinge.Parent = part(CP, "Spinner", Vector3.new(50, 2, 0))
local conveyor = part(CP, "Conveyor", Vector3.new(60, 0, 0))
conveyor.AssemblyLinearVelocity = Vector3.new(10, 0, 0)
local padInst = Instance.new("Configuration"); padInst.Name = "BouncePadConfiguration"
local padCfg = { __instance = padInst, __defaults = {}, Power = 100 }
M.gcTables[#M.gcTables + 1] = padCfg
-- beat blocks and a turret
local bbFolder = folder(CP, "BeatBlockGroup")
local bbCfg = Instance.new("Configuration"); bbCfg.Name = "BeatBlockConfiguration"
for k, v in pairs({ Interval = 1, IndicatorInterval = 0.5, Indicator = true, IndicatorSize = Vector3.new(3, 3, 3),
	OffTransparency = 0.7, OnTransparency = 0, OffCanCollide = false, OnCanCollide = true, OnCanTouch = true, OffCanTouch = false,
	MaterialIndicator = Enum.Material.SmoothPlastic, IndicatorScaleMultiplier = 1, ToggleChildren = false }) do bbCfg:SetAttribute(k, v) end
bbCfg:AddTag("CO_Visual/BeatBlock")
bbCfg.Parent = bbFolder
local beatGroups = {}
for i = 1, 4 do beatGroups[i] = { part(bbFolder, tostring(i), Vector3.new(100 + i * 5, 2, 100)) } end
local turModel = Instance.new("Model"); turModel.Name = "Turret"; turModel.Parent = CP
local turPart = part(turModel, "Turret", Vector3.new(0, 5, 50))
turPart.CFrame = CFrame.lookAt(Vector3.new(0, 5, 50), Vector3.new(0, 5, 100))
local fireSnd = Instance.new("Sound"); fireSnd.Name = "Fire"; fireSnd.Volume = 0.6; fireSnd.TimeLength = 0.3; fireSnd.Parent = turPart
local turCfg = Instance.new("Configuration"); turCfg.Name = "TurretConfiguration"
for k, v in pairs({ FireRate = 2, Speed = 20, MaxLifetime = 5, Damage = 5, Range = 500, DestroyOnTouch = true }) do turCfg:SetAttribute(k, v) end
turCfg:AddTag("CO_Interactables/Turret")
turCfg.Parent = turModel
-- a timed button
local bModel = Instance.new("Model"); bModel.Name = "Button"; bModel.Parent = folder(workspace, "Buttons")
part(bModel, "ButtonPart", Vector3.new(-10, 1, -10))
local bCfg = Instance.new("Configuration"); bCfg.Name = "ButtonConfiguration"; bCfg.Parent = bModel
local bTimer = Instance.new("NumberValue"); bTimer.Name = "Timer"; bTimer.Value = 1; bTimer.Parent = bCfg
local bStart = Instance.new("NumberValue"); bStart.Name = "TimerStart"; bStart.Parent = bCfg
local bPressed = Instance.new("BoolValue"); bPressed.Name = "Pressed"; bPressed.Parent = bModel
local buttonLoop = RS.Heartbeat:Connect(function()
	if bPressed.Value and bTimer.Value - (os.clock() - bStart.Value) <= 0 then bPressed.Value = false end
end)
local function press() bStart.Value = os.clock(); bPressed.Value = true end
-- lighting
local lighting = M.services.Lighting
lighting.ClockTime = 14

local function counts() return { RS.PreRender:Count(), RS.PreSimulation:Count(), RS.PostSimulation:Count(), RS.Heartbeat:Count() } end
local before = counts()
local G0 = workspace.Gravity

-- ------------------------------------------------------------------------------------------------ helpers
check(boot(30), "boots")
local function engine()
	local T = genv.__HappaTAS3_T
	return T and T.engine
end
local function waitLoaded()
	local g = 0
	while not (engine() and engine().char:loaded()) and g < 200 do M.step(1 / 60); g = g + 1 end
	M.steps(10)
	local E = engine()
	g = 0
	while E and not E.co:isReady() and g < 600 do M.step(1 / 60); g = g + 1 end
	return E
end
local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
local function click()
	UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	UIS.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
local function restart()
	M.resume(coroutine.create(function() __SCRIPT__() end))
	return waitLoaded()
end
-- everything on: client objects, buttons, lighting, the kit, the speed hack at 0.5x
local function allOn(E, frameStep)
	for _, k in ipairs({ "syncClientObjects", "syncButtonTimers", "syncLighting", "kitScriptsOnTasClock", "syncKitObjects", "speedHack" }) do
		E.settings:set(k, 1)
	end
	E.settings:set("speedHackSpeed", 0.5)
	E.settings:set("speedHackFrameStep", frameStep and 1 or 0)
	local g = 0
	while not E.co:isReady() and g < 600 do M.step(1 / 60); g = g + 1 end
end
local loops = {}
local function startKit()
	loops[#loops + 1] = task.spawn(Timer.Run, 0.25)
	loops[#loops + 1] = task.spawn(BeatKit.Loop, beatGroups, 4, 2)
	loops[#loops + 1] = task.spawn(TurretKit.Loop, turModel, turPart, 2, 20)
	Ride.Start(5)
end
local function stopKit()
	for _, l in ipairs(loops) do pcall(task.cancel, l) end
	loops = {}
	if Ride.conn then Ride.conn:Disconnect(); Ride.conn = nil end
	for _, c in ipairs(turModel:GetChildren()) do if c:IsA("Model") then c:Destroy() end end
end
local function worldBack(tag)
	local c = counts()
	eq(c[1], before[1], tag .. ": PreRender connections back")
	eq(c[2], before[2], tag .. ": PreSimulation connections back")
	eq(c[3], before[3], tag .. ": PostSimulation connections back")
	eq(c[4], before[4], tag .. ": Heartbeat connections back")
	local anchoredFree = 0
	for _, p in ipairs(free) do if p.Anchored then anchoredFree = anchoredFree + 1 end end
	eq(anchoredFree, 0, tag .. ": no free client object left anchored")
	near(workspace.Gravity, G0, 1e-9, tag .. ": normal gravity")
	local hum = M.player.Character:FindFirstChildOfClass("Humanoid")
	near(hum.WalkSpeed, 16, 1e-9, tag .. ": WalkSpeed 16")
	near(hum.JumpPower, 50, 1e-9, tag .. ": JumpPower 50")
	near(hinge.AngularVelocity, -1.5, 1e-9, tag .. ": the hinge motor back")
	check(conveyor.AssemblyLinearVelocity == Vector3.new(10, 0, 0), tag .. ": the conveyor back")
	eq(padCfg.Power, 100, tag .. ": the bounce pad's Power back")
	eq(rawget(timerEnv, "task"), nil, tag .. ": the kit's module has its own task again")
	eq(rawget(timerEnv, "os"), nil, tag .. ": and its own os")
	eq(Functions.tween, origTween, tag .. ": the tween helper is the kit's")
	eq(workspace.CurrentCamera:FindFirstChild("HappaTASKit"), nil, tag .. ": no HappaTAS bullets left")
	near(ding.Volume, 0.5, 1e-9, tag .. ": the kit's ding not muted")
	near(fireSnd.Volume, 0.6, 1e-9, tag .. ": the turret's sound not muted")
	eq(genv.__HappaTAS3, nil, tag .. ": handle removed")
	-- the kit's button timer runs on os.clock again
	press()
	M.steps(70)
	eq(bPressed.Value, false, tag .. ": a button pressed now is released by the kit after its 1 s")
end
local function unload(E)
	genv.__HappaTAS3.Unload()
	M.steps(3)
end

-- ------------------------------------------------------------------------------------------------ Unload
section("Unload while recording at 0.5x (Smooth), the kit running")
do
	local E = engine()
	waitLoaded()
	allOn(E, false)
	startKit()
	key(Enum.KeyCode.Two)
	M.steps(3)
	click()
	M.steps(60)
	press()
	lighting.ClockTime = 20
	M.steps(30)
	near(workspace.Gravity, G0 * 0.25, 1e-6, "slowed while recording")
	check(rawget(timerEnv, "task") ~= nil, "the kit's module on the TAS clock")
	unload(E)
	stopKit()
	worldBack("recording 0.5x")
	near(lighting.ClockTime, 14, 1e-9, "recording 0.5x: the lighting from before the TAS")
end

section("Unload while paused with the client objects held")
do
	lighting.ClockTime = 14
	local E = restart()
	allOn(E, false)
	startKit()
	key(Enum.KeyCode.Two)
	M.steps(3)
	click()
	for _ = 1, 90 do
		for _, p in ipairs(free) do p.AssemblyLinearVelocity = Vector3.new(0, 0, 3) end
		M.step(1 / 60)
	end
	click()
	M.steps(5)
	for _ = 1, 10 do key(Enum.KeyCode.F); M.steps(4) end
	check(E.co:isHolding(), "the client objects are held while paused")
	local held = 0
	for _, p in ipairs(free) do if p.Anchored then held = held + 1 end end
	check(held > 0, "free parts held (" .. held .. ")")
	unload(E)
	stopKit()
	worldBack("paused")
end

section("Unload while recording with Frame Step 0.5x")
do
	local E = restart()
	allOn(E, true)
	startKit()
	key(Enum.KeyCode.Two)
	M.steps(3)
	click()
	M.steps(41) -- (an odd number: the last frame is one whose step was held)
	check(E.time:stepping(), "frame stepping")
	unload(E)
	stopKit()
	worldBack("Frame Step")
	check(not M.player.Character:FindFirstChild("HumanoidRootPart").Anchored, "Frame Step: the character isn't anchored")
end

section("Unload in Test with bullets in the air")
do
	local E = restart()
	allOn(E, false)
	E.settings:set("speedHack", 0)
	startKit()
	key(Enum.KeyCode.Two)
	M.steps(3)
	click()
	M.steps(150)
	click()
	M.steps(3)
	key(Enum.KeyCode.Three)
	M.steps(80)
	eq(E.mode, 3, "testing")
	local hf = workspace.CurrentCamera:FindFirstChild("HappaTASKit")
	check(hf and #hf:GetChildren() >= 1, "bullets in the air (" .. tostring(hf and #hf:GetChildren()) .. ")")
	unload(E)
	stopKit()
	worldBack("Test")
end

-- ------------------------------------------------------------------------------------------------ settings
section("every world setting off and on mid-run (recording, paused, Test)")
do
	local E = restart()
	allOn(E, false)
	startKit()
	key(Enum.KeyCode.Two)
	M.steps(3)
	click()
	M.steps(60)
	local KEYS = { "syncClientObjects", "smoothClientObjects", "frustumCullingCO", "syncButtonTimers", "syncLighting",
		"kitScriptsOnTasClock", "syncKitObjects", "speedHack", "speedHackFrameStep" }
	local function snapshot()
		local tl = E.tl
		local out = {}
		local n = tl:count() - 3 -- (the frames recorded before the switch; recording goes on)
		for i = 1, n do
			out[#out + 1] = tostring(tl:getList("v2CO", i)) .. "|" .. tostring(tl:getList("v2KE", i) and #tl:getList("v2KE", i))
				.. "|" .. tostring(tl:getList("v2BT", i) and #tl:getList("v2BT", i)) .. "|" .. tostring(tl:get("TotalTime", i, 1))
		end
		return table.concat(out, "\n"), n
	end
	local function toggleAll(state)
		for _, k in ipairs(KEYS) do
			local was = E.settings:get(k)
			local s0, n0 = snapshot()
			E.settings:set(k, was == 1 and 0 or 1)
			M.steps(3)
			local s1 = snapshot()
			local cut = s1:sub(1, #s0)
			eq(cut, s0, state .. ": " .. k .. " switched: the frames before it unchanged")
			E.settings:set(k, was)
			M.steps(3)
		end
	end
	toggleAll("recording")
	-- off while recording: released at once
	E.settings:set("syncKitObjects", 0)
	M.steps(2)
	eq(ding.Volume, 0.5, "Sync Kit Objects off while recording: the kit's ding back at once")
	E.settings:set("syncKitObjects", 1)
	E.settings:set("speedHack", 0)
	M.steps(2)
	near(workspace.Gravity, G0, 1e-9, "Speed Hack off while recording: normal gravity at once")
	E.settings:set("speedHack", 1)
	M.steps(5)
	click()
	M.steps(3)
	toggleAll("paused")
	E.settings:set("syncClientObjects", 0)
	M.steps(2)
	eq(E.co:isHolding(), false, "Sync Client Objects off while paused: nothing held")
	E.settings:set("syncClientObjects", 1)
	local g = 0
	while not E.co:isReady() and g < 600 do M.step(1 / 60); g = g + 1 end
	key(Enum.KeyCode.Three)
	M.steps(10)
	eq(E.mode, 3, "testing")
	for _, k in ipairs(KEYS) do
		local was = E.settings:get(k)
		E.settings:set(k, was == 1 and 0 or 1)
		M.steps(3)
		E.settings:set(k, was)
		M.steps(3)
	end
	check(true, "Test: every setting switched off and on")
	local gg = 0
	while E.mode == 3 and gg < 800 do M.step(1 / 60); gg = gg + 1 end
	unload(E)
	stopKit()
end

-- ------------------------------------------------------------------------------------------------ V2 files
section("a V2 file with client objects, buttons and kit data: plays, and comes back the same after v6")
do
	local E = restart()
	local Files = __T3("platform/files")
	local files = Files.new(__T3("platform/env"))
	local root = E.library.root
	files:makeFolder(root)
	for _, name in ipairs({ "kitspeed.tas", "objbuttons.tas" }) do
		files:write(root .. "/" .. name, FIXTURES[name].data)
		local okL = E.persist:load(name)
		check(okL, name .. ": load started")
		local g = 0
		M.step(1 / 60)
		while E.busy and g < 600 do M.step(1 / 60); g = g + 1 end
		local n = E.tl:count()
		eq(n, #FIXTURES[name].expected.frames, name .. ": every frame")
		local function lists()
			local out = {}
			for _, col in ipairs({ "v2CO", "v2BT", "v2KE", "v2SK" }) do
				local parts = {}
				for i = 1, E.tl:count() do
					local v = E.tl:getList(col, i)
					if type(v) == "table" then
						local q = {}
						for _, e in ipairs(v) do q[#q + 1] = (type(e) == "table") and table.concat(e, ",") or tostring(e) end
						v = table.concat(q, ";")
					end
					parts[#parts + 1] = tostring(v)
				end
				out[col] = table.concat(parts, "\n")
			end
			return out
		end
		local before = lists()
		local metaKit = E.tl.meta.kitVersion
		-- Test it: no errors
		key(Enum.KeyCode.Three)
		M.steps(5)
		local gt = 0
		while E.mode == 3 and gt < 2000 do M.step(1 / 60); gt = gt + 1 end
		M.steps(3)
		eq(E.mode, 1, name .. ": played to the end")
		-- v6 and back
		check((E.persist:save("roundtrip")), name .. ": save started")
		g = 0
		M.step(1 / 60)
		while E.busy and g < 600 do M.step(1 / 60); g = g + 1 end
		E.modes:setRun({})
		check((E.persist:load("roundtrip.tas")), name .. ": load started")
		g = 0
		M.step(1 / 60)
		while E.busy and g < 600 do M.step(1 / 60); g = g + 1 end
		local after = lists()
		for _, col in ipairs({ "v2CO", "v2BT", "v2KE", "v2SK" }) do
			eq(after[col], before[col], name .. ": " .. col .. " the same after v6")
		end
		eq(E.tl.meta.kitVersion, metaKit, name .. ": the kit rules the same")
	end
	unload(E)
end
moveConn:Disconnect()
buttonLoop:Disconnect()
finish()
