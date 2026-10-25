-- ================================================================================================
-- Trace scenario "world" (tools/trace3.sh with SCENARIO=world): the world plugins on V2.38.17 and
-- HappaTAS 3, one part per system, each recorded, paused, scrubbed and tested.
--   part A: an EToH kit timed button (W.bt: Pressed, the timer's TAS time, the button part's look)
-- ================================================================================================
M.clockStep = 0
check(A.boot(), "boots")
local hrp = A.char()

local function out(...)
	local t = { ... }
	for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
	M.realPrint("T|" .. table.concat(t, "|"))
end
local function num(v) return string.format("%.4f", v) end
local function modeLine(tag) out("mode", tag, A.mode(), A.frame(), tostring(A.paused()), A.count()) end
local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
local function click()
	local UIS = M.services.UserInputService
	UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	UIS.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
local function frames(tag, fields)
	for i = 1, A.count() do
		local fr = A.frameV2(i)
		for _, k in ipairs(fields) do
			local v = fr[k]
			if v ~= nil then
				local s
				if type(v) == "table" then
					local parts = {}
					for _, e in ipairs(v) do
						local q = {}
						for j, x in ipairs(e) do q[j] = type(x) == "number" and num(x) or tostring(x) end
						parts[#parts + 1] = table.concat(q, ",")
					end
					s = table.concat(parts, ";")
				else
					s = tostring(v)
				end
				out("F", tag, i, k, s)
			end
		end
	end
	modeLine(tag)
end

-- ---------------------------------------------------------------------------------------------- part A
local folder = Instance.new("Folder"); folder.Name = "Buttons"; folder.Parent = workspace
local model = Instance.new("Model"); model.Name = "Button"; model.Parent = folder
local bp = Instance.new("Part"); bp.Name = "ButtonPart"; bp.Anchored = true; bp.Parent = model
local cfg = Instance.new("Configuration"); cfg.Name = "ButtonConfiguration"; cfg.Parent = model
local timer = Instance.new("NumberValue"); timer.Name = "Timer"; timer.Value = 1.5; timer.Parent = cfg
local timerStart = Instance.new("NumberValue"); timerStart.Name = "TimerStart"; timerStart.Parent = cfg
local pressed = Instance.new("BoolValue"); pressed.Name = "Pressed"; pressed.Parent = model
local kitLoop = M.services.RunService.Heartbeat:Connect(function()
	if pressed.Value and timer.Value - (os.clock() - timerStart.Value) <= 0 then pressed.Value = false end
end)
local function press()
	timerStart.Value = os.clock()
	pressed.Value = true
end
local function bt(tag)
	out("W.bt", tag, A.mode(), A.frame(), tostring(pressed.Value), num(os.clock() - timerStart.Value),
		tostring(bp.CFrame.Position), tostring(bp.Material), tostring(bp.CanTouch))
end

A.setSetting("Sync Button Timers", 1)
M.steps(5)
key(Enum.KeyCode.Two)
M.steps(3)
click()
M.steps(2)
for i = 1, 60 do
	hrp.AssemblyLinearVelocity = Vector3.new(1, 0, 0)
	if i == 20 then press() end
	M.step(1 / 60)
	if i % 5 == 0 then bt("rec" .. i) end
end
click()
M.steps(3)
bt("paused")
for i = 1, 90 do M.step(1 / 60); if i % 15 == 0 then bt("hold" .. i) end end
frames("A.recorded", { "BT" })
M.pressKey(Enum.KeyCode.R)
for i = 1, 30 do M.step(1 / 60); if i % 3 == 0 then bt("back" .. i) end end
M.releaseKey(Enum.KeyCode.R)
M.steps(2)
M.pressKey(Enum.KeyCode.T)
for i = 1, 30 do M.step(1 / 60); if i % 3 == 0 then bt("fwd" .. i) end end
M.releaseKey(Enum.KeyCode.T)
M.steps(2)
click()
for i = 1, 90 do
	M.step(1 / 60)
	if i % 5 == 0 then bt("rec2-" .. i) end
end
click()
M.steps(3)
frames("A.recorded2", { "BT" })
key(Enum.KeyCode.Three)
M.steps(1)
local n = 0
while A.mode() == 3 and n < 400 do
	M.step(1 / 60)
	n = n + 1
	if n % 3 == 0 then bt("play" .. n) end
end
out("mode", "A.played", n)
A.setSetting("Playback Speed", 2)
key(Enum.KeyCode.Three)
M.steps(1)
n = 0
while A.mode() == 3 and n < 400 do
	M.step(1 / 60)
	n = n + 1
	if n % 2 == 0 then bt("play2x" .. n) end
end
out("mode", "A.played2x", n)
A.setSetting("Playback Speed", 1)
M.steps(3)
press()
for i = 1, 30 do M.step(1 / 60); if i % 5 == 0 then bt("idle" .. i) end end
kitLoop:Disconnect()
folder:Destroy()
key(Enum.KeyCode.Backspace)
M.steps(2)
key(Enum.KeyCode.Backspace)
M.steps(2)
modeLine("A.end")

-- ---------------------------------------------------------------------------------------------- part B
-- a light changer: ClockTime, FogColor, an effect's Saturation and a new BloomEffect while recording
local lighting = game:GetService("Lighting")
local cc = Instance.new("ColorCorrectionEffect"); cc.Name = "CC"; cc.Parent = lighting
local function lt(tag)
	local e = {}
	for _, ch in ipairs(lighting:GetChildren()) do
		if ch:IsA("ColorCorrectionEffect") then e[#e + 1] = ch.Name .. ":" .. num(ch.Saturation) .. ":" .. tostring(ch.Enabled)
		elseif ch:IsA("BloomEffect") then e[#e + 1] = ch.Name .. ":" .. num(ch.Intensity) end
	end
	table.sort(e)
	out("W.lt", tag, A.mode(), A.frame(), num(lighting.ClockTime), tostring(lighting.FogColor), num(lighting.Brightness), table.concat(e, ";"))
end
A.setSetting("Sync Lighting", 1)
M.steps(3)
key(Enum.KeyCode.Two)
M.steps(3)
click()
M.steps(2)
local bloom
for i = 1, 80 do
	if i == 15 then lighting.ClockTime = 18 end
	if i == 30 then lighting.FogColor = Color3.fromRGB(10, 20, 30); cc.Saturation = -0.5 end
	if i == 45 then bloom = Instance.new("BloomEffect"); bloom.Name = "Bloom"; bloom.Parent = lighting end
	if i == 60 then bloom.Intensity = 3; lighting.Brightness = 1 end
	M.step(1 / 60)
	if i % 5 == 0 then lt("rec" .. i) end
end
click()
M.steps(3)
lt("paused")
M.pressKey(Enum.KeyCode.R)
for i = 1, 40 do M.step(1 / 60); if i % 4 == 0 then lt("back" .. i) end end
M.releaseKey(Enum.KeyCode.R)
M.steps(2)
-- unpause in the middle: the frames after it are cut
click()
for i = 1, 20 do
	if i == 10 then lighting.ClockTime = 6 end
	M.step(1 / 60)
	if i % 5 == 0 then lt("rec2-" .. i) end
end
click()
M.steps(3)
lt("paused2")
key(Enum.KeyCode.Three)
M.steps(1)
n = 0
while A.mode() == 3 and n < 400 do
	M.step(1 / 60)
	n = n + 1
	if n % 4 == 0 then lt("play" .. n) end
end
out("mode", "B.played", n)
M.steps(3)
lt("idle")
A.setSetting("Sync Lighting", 0)
M.steps(2)
lt("off")
modeLine("B.end")

-- ---------------------------------------------------------------------------------------------- part C
-- time control, Smooth: walking, a jump, a spinner (hinge motor), a conveyor (anchored part with a
-- velocity), a free box, a VectorForce and a bounce pad's kit config, recorded at 0.5x and at 2x, tested
M.humanoidPhysics = true
M.robloxController = true
local _, hum = A.char()
local cfolder = Instance.new("Folder"); cfolder.Name = "ClientParts"; cfolder.Parent = workspace
local function cpart(name, cf, anchored)
	local p = Instance.new("Part"); p.Name = name; p.Size = Vector3.new(2, 1, 2); p.CFrame = cf; p.Anchored = anchored; p.Parent = cfolder
	return p
end
local hub = cpart("Spinner", CFrame.new(20, 3, 0), false)
local hinge = Instance.new("HingeConstraint"); hinge.ActuatorType = Enum.ActuatorType.Motor; hinge.AngularVelocity = -1.5
hinge.MotorMaxTorque = 1e6; hinge.Parent = hub
local conveyor = cpart("Conveyor", CFrame.new(-20, 3, 0), true)
conveyor.AssemblyLinearVelocity = Vector3.new(0, 0, 10)
local box = cpart("Box", CFrame.new(0, 10, 20), false)
local push = Instance.new("VectorForce"); push.Force = Vector3.new(0, 0, 4000); push.Parent = box
local padInst = Instance.new("Configuration"); padInst.Name = "BouncePadConfiguration"
local padCfg = { __instance = padInst, __defaults = {}, Power = 100 }
M.gcTables[#M.gcTables + 1] = padCfg
local function tw(tag)
	local hrp2 = A.char()
	out("W.time", tag, A.mode(), A.frame(), num(workspace.Gravity), num(hum.WalkSpeed), num(hum.JumpPower),
		num(hinge.AngularVelocity), num(hinge.MotorMaxTorque), tostring(conveyor.AssemblyLinearVelocity), tostring(push.Force),
		num(padCfg.Power), num(box.AssemblyLinearVelocity.Y))
	out("W.char", tag, tostring(hrp2.CFrame.Position), tostring(hrp2.AssemblyLinearVelocity), tostring(hum:GetState()))
end
local function runC(speed, tag)
	A.setSetting("Speed Hack Speed", speed)
	A.setSetting("Speed Hack", 1)
	key(Enum.KeyCode.One)
	M.steps(3)
	key(Enum.KeyCode.Backspace); M.steps(2); key(Enum.KeyCode.Backspace); M.steps(2)
	hrp.CFrame = CFrame.new(0, 3, 0)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hum.MoveDirection = Vector3.zero
	box.CFrame = CFrame.new(0, 10, 20)
	box.AssemblyLinearVelocity = Vector3.zero
	M.resetHumanoidModel()
	M.resetRobloxController()
	key(Enum.KeyCode.Two)
	M.steps(3)
	click()
	for i = 1, 90 do
		if i == 2 then hum.MoveDirection = Vector3.new(1, 0, 0) end
		if i == 30 then M.jumpNow = true end
		if i == 60 then local v = hrp.AssemblyLinearVelocity; hrp.AssemblyLinearVelocity = Vector3.new(v.X, padCfg.Power, v.Z) end
		M.step(1 / 60)
		if i % 6 == 0 then tw(tag .. ".rec" .. i) end
	end
	click()
	M.steps(3)
	tw(tag .. ".paused")
	hum.MoveDirection = Vector3.zero
	frames(tag .. ".recorded", { "FrameTime", "TotalTime", "SK" })
	A.setSetting("Speed Hack", 0)
	key(Enum.KeyCode.Three)
	M.steps(1)
	local m = 0
	while A.mode() == 3 and m < 400 do
		M.step(1 / 60)
		m = m + 1
		if m % 6 == 0 then tw(tag .. ".play" .. m) end
	end
	out("mode", tag .. ".played", m)
	M.steps(3)
end
runC(0.5, "C05")
runC(2, "C2")
modeLine("C.end")

-- ---------------------------------------------------------------------------------------------- part D
-- Frame Step at 0.5x and 0.25x (the same walk / jump / world), then walking off an edge with a pause inside
-- the coyote window and a jump after unpausing
A.setSetting("Speed Hack Frame Step", 1)
runC(0.5, "D05")
runC(0.25, "D025")
A.setSetting("Speed Hack Frame Step", 0)
local function edge(speed, tag)
	A.setSetting("Speed Hack Speed", speed)
	A.setSetting("Speed Hack", speed == 1 and 0 or 1)
	key(Enum.KeyCode.One)
	M.steps(3)
	key(Enum.KeyCode.Backspace); M.steps(2); key(Enum.KeyCode.Backspace); M.steps(2)
	hrp.CFrame = CFrame.new(0, 3, 0)
	hrp.AssemblyLinearVelocity = Vector3.zero
	hum.MoveDirection = Vector3.zero
	M.resetHumanoidModel()
	M.resetRobloxController()
	M.floorEdgeX = 6
	key(Enum.KeyCode.Two)
	M.steps(3)
	click()
	hum.MoveDirection = Vector3.new(1, 0, 0)
	local left, k = nil, 0
	for _ = 1, 600 do
		M.step(1 / 240)
		k = k + 1
		if not left and hrp.Position.X >= 6 then left = k end
		if left and k - left >= math.floor(0.05 * 240 / speed) then break end
	end
	click()
	M.steps(20)
	tw(tag .. ".paused")
	click()
	hum.Jump = true
	for i = 1, 60 do
		M.step(1 / 240)
		if i % 6 == 0 then tw(tag .. ".after" .. i) end
	end
	hum.Jump = false
	hum.MoveDirection = Vector3.zero
	click()
	M.steps(3)
	frames(tag .. ".recorded", { "FrameTime", "TotalTime", "SK", "State" })
	M.floorEdgeX = nil
end
edge(1, "E1")
edge(0.5, "E05")
A.setSetting("Speed Hack", 0)
A.setSetting("Speed Hack Speed", 0.5)
M.humanoidPhysics = false
M.robloxController = false
cfolder:Destroy()
key(Enum.KeyCode.One)
M.steps(3)
modeLine("D.end")

-- ---------------------------------------------------------------------------------------------- part E
-- the Kit Clock: a kit module (its own environment, like the kit's) moves a platform every 0.25 s with
-- task.wait, starts a 0.4 s push with task.delay and reads os.clock; recorded at 1x, paused, at 0.5x, tested
local RSt = M.services.ReplicatedStorage
local fw = Instance.new("Folder"); fw.Name = "Framework"; fw.Parent = RSt
local kitF = Instance.new("Folder"); kitF.Name = "Kit"; kitF.Parent = fw
local repo = Instance.new("Folder"); repo.Name = "Repository"; repo.Parent = kitF
local ms = Instance.new("ModuleScript"); ms.Name = "Mover"; ms.Parent = repo
local env = setmetatable({ script = ms }, { __index = setmetatable({ os = os }, { __index = getfenv(1) }) })
local chunk = loadstring([[
local Mo = { steps = 0, pushes = 0, clock0 = os.clock() }
function Mo.Loop(p)
	while true do
		task.wait(0.25)
		p.CFrame = p.CFrame + Vector3.new(0, 0, 1)
		Mo.steps = Mo.steps + 1
		if Mo.steps % 4 == 0 then
			task.delay(0.4, function() Mo.pushes = Mo.pushes + 1 end)
		end
	end
end
function Mo.Clock() return os.clock() - Mo.clock0 end
return Mo
]], "=Mover")
setfenv(chunk, env)
local Mover = chunk()
M.modules[ms] = Mover
local plat = Instance.new("Part"); plat.Name = "KitPlatform"; plat.Anchored = true; plat.CFrame = CFrame.new(30, 3, 30); plat.Parent = workspace
A.setSetting("Kit Scripts On TAS Clock", 0)
M.steps(2)
A.setSetting("Kit Scripts On TAS Clock", 1)
M.steps(3)
local loop = task.spawn(Mover.Loop, plat)
local function kt(tag)
	out("W.kit", tag, A.mode(), A.frame(), tostring(plat.CFrame.Position), Mover.steps, Mover.pushes, num(Mover.Clock()))
end
for i = 1, 30 do M.step(1 / 60); if i % 10 == 0 then kt("idle" .. i) end end
key(Enum.KeyCode.Two)
M.steps(3)
click()
for i = 1, 120 do M.step(1 / 60); if i % 6 == 0 then kt("rec" .. i) end end
click()
for i = 1, 60 do M.step(1 / 60); if i % 15 == 0 then kt("paused" .. i) end end
A.setSetting("Speed Hack Speed", 0.5)
A.setSetting("Speed Hack", 1)
click()
for i = 1, 120 do M.step(1 / 60); if i % 6 == 0 then kt("slow" .. i) end end
click()
M.steps(3)
A.setSetting("Speed Hack", 0)
kt("paused2")
key(Enum.KeyCode.Three)
M.steps(1)
n = 0
while A.mode() == 3 and n < 400 do
	M.step(1 / 60)
	n = n + 1
	if n % 6 == 0 then kt("play" .. n) end
end
out("mode", "E.played", n)
M.steps(3)
kt("idle2")
task.cancel(loop)
plat:Destroy()
modeLine("E.end")

-- ---------------------------------------------------------------------------------------------- part F
-- kit objects: a beat block group (4 groups, Interval 1, indicator for the last 0.5 s) and a turret firing at a
-- wall, with the kit's own loops (kit-style modules); recorded, paused and scrubbed, tested
local visual = Instance.new("Folder"); visual.Name = "Visual"; visual.Parent = repo
local inter = Instance.new("Folder"); inter.Name = "Interactables"; inter.Parent = repo
local function kitModule(parent, name, src)
	local m = Instance.new("ModuleScript"); m.Name = name; m.Parent = parent
	local en = setmetatable({ script = m }, { __index = setmetatable({ os = os }, { __index = getfenv(1) }) })
	local ch = loadstring(src, "=" .. m:GetFullName())
	setfenv(ch, en)
	local mod = ch()
	M.modules[m] = mod
	return m, mod
end
local bbMs, BeatKit = kitModule(visual, "BeatBlock", [[
local B = {}
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
		local lv = Instance.new("LinearVelocity"); lv.VectorVelocity = part.CFrame.LookVector * speed; lv.Parent = p
		m.Parent = model
	end
end
return T
]])
local CPF = Instance.new("Folder"); CPF.Name = "ClientParts"; CPF.Parent = workspace
local bbFolder = Instance.new("Folder"); bbFolder.Name = "BeatBlockGroup"; bbFolder.Parent = CPF
local bbCfg = Instance.new("Configuration"); bbCfg.Name = "BeatBlockConfiguration"
for k, v in pairs({ Interval = 1, IndicatorInterval = 0.5, Indicator = true, IndicatorSize = Vector3.new(3, 3, 3),
	OffTransparency = 0.7, OnTransparency = 0, OffCanCollide = false, OnCanCollide = true, OnCanTouch = true, OffCanTouch = false,
	MaterialIndicator = Enum.Material.SmoothPlastic, IndicatorScaleMultiplier = 1, ToggleChildren = false }) do bbCfg:SetAttribute(k, v) end
bbCfg:AddTag("CO_Visual/BeatBlock")
bbCfg.Parent = bbFolder
local beatParts, beatGroups = {}, {}
for i = 1, 4 do
	local p = Instance.new("Part"); p.Name = tostring(i); p.Size = Vector3.new(4, 4, 4); p.CFrame = CFrame.new(100 + i * 5, 2, 100)
	p.Anchored = true; p.Material = Enum.Material.Plastic; p.Parent = bbFolder
	beatParts[i] = p
	beatGroups[i] = { p }
end
local turModel = Instance.new("Model"); turModel.Name = "Turret"; turModel.Parent = CPF
local turPart = Instance.new("Part"); turPart.Name = "Turret"; turPart.Size = Vector3.new(2, 2, 2); turPart.Anchored = true
turPart.CFrame = CFrame.lookAt(Vector3.new(0, 5, 50), Vector3.new(0, 5, 100)); turPart.Parent = turModel
local fireSnd = Instance.new("Sound"); fireSnd.Name = "Fire"; fireSnd.Volume = 0.6; fireSnd.TimeLength = 0.3; fireSnd.Parent = turPart
local turCfg = Instance.new("Configuration"); turCfg.Name = "TurretConfiguration"
for k, v in pairs({ FireRate = 1, Speed = 50, MaxLifetime = 2, Damage = 5, Range = 500, DestroyOnTouch = true }) do turCfg:SetAttribute(k, v) end
turCfg:AddTag("CO_Interactables/Turret")
turCfg.Parent = turModel
local wallF = Instance.new("Part"); wallF.Name = "Wall"; wallF.Size = Vector3.new(10, 10, 1); wallF.Anchored = true
wallF.CFrame = CFrame.new(0, 5, 70); wallF.Parent = workspace
A.setSetting("Sync Kit Objects", 0)
M.steps(2)
A.setSetting("Sync Kit Objects", 1)
M.steps(3)
local bLoop = task.spawn(BeatKit.Loop, beatGroups, 4, 2)
local tLoop = task.spawn(TurretKit.Loop, turModel, turPart, 1, 50)
local function kf(tag)
	local b = {}
	for i, p in ipairs(beatParts) do b[i] = string.format("%s:%s:%s:%s", num(p.Transparency), tostring(p.CanCollide), tostring(p.Size.X), tostring(p.Material)) end
	local hf = workspace.CurrentCamera:FindFirstChild("HappaTASKit")
	local bl = {}
	if hf then for _, m in ipairs(hf:GetChildren()) do bl[#bl + 1] = tostring(m:GetPivot().Position) end end
	table.sort(bl)
	local kitB = 0
	for _, c in ipairs(turModel:GetChildren()) do if c:IsA("Model") then kitB = kitB + 1 end end
	out("W.kit", tag, A.mode(), A.frame(), table.concat(b, ";"), table.concat(bl, ";"), kitB, num(ding.Volume), num(fireSnd.Volume))
end
for i = 1, 20 do M.step(1 / 60); if i % 10 == 0 then kf("F.idle" .. i) end end
key(Enum.KeyCode.One)
M.steps(2)
key(Enum.KeyCode.Backspace); M.steps(2); key(Enum.KeyCode.Backspace); M.steps(2)
key(Enum.KeyCode.Two)
M.steps(3)
click()
for i = 1, 180 do M.step(1 / 60); if i % 6 == 0 then kf("F.rec" .. i) end end
click()
M.steps(3)
frames("F.recorded", { "KE" })
M.pressKey(Enum.KeyCode.R)
for i = 1, 40 do M.step(1 / 60); if i % 4 == 0 then kf("F.back" .. i) end end
M.releaseKey(Enum.KeyCode.R)
M.steps(2)
key(Enum.KeyCode.Three)
M.steps(1)
n = 0
while A.mode() == 3 and n < 400 do
	M.step(1 / 60)
	n = n + 1
	if n % 6 == 0 then kf("F.play" .. n) end
end
out("mode", "F.played", n)
M.steps(3)
kf("F.idle2")
task.cancel(bLoop)
task.cancel(tLoop)
modeLine("F.end")

finish()
