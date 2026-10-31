-- ================================================================================================
-- Bench: per-frame cost in each mode, the same session on V2.38.16 and on HappaTAS 3 (through the trace
-- adapters; tools/bench3.sh runs and compares them). V2's stats panels, client objects and MicroProfiler
-- are off: phase 2 of HappaTAS 3 has none of them yet.
--   us = Lua time per frame of the whole mock frame (HappaTAS + mock), rd / wr = Instance reads / writes
-- ================================================================================================
check(A.boot(), "boots")
for _, name in ipairs({ "Show Stats (Idle)", "Show Stats (Create)", "Show Stats (Test)", "Sync Client Objects", "Show MicroProfiler" }) do
	A.setSetting(name, 0)
end
M.steps(30)
local hrp = A.char()
local function measure(name, n, perFrame)
	for _ = 1, 30 do if perFrame then perFrame() end; M.step(1 / 60) end -- warm up
	local best = math.huge
	local rd, wr
	for _ = 1, 5 do -- (the fastest of 5 runs: less noise from the machine)
		local r0, w0 = M.propReads, M.propWrites
		local t0 = M.realClock()
		for _ = 1, n do
			if perFrame then perFrame() end
			M.step(1 / 60)
		end
		local us = (M.realClock() - t0) / n * 1e6
		if us < best then best = us end
		rd, wr = (M.propReads - r0) / n, (M.propWrites - w0) / n
	end
	M.realPrint(string.format("BENCH|%s|%.1f|%.1f|%.1f", name, best, rd, wr))
end
local function click()
	M.services.UserInputService.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
end
local function key(kc) M.pressKey(kc); M.releaseKey(kc) end

measure("idle", 1000)
hrp.AssemblyLinearVelocity = Vector3.new(16, 0, 0)
measure("idle moving", 1000)
hrp.AssemblyLinearVelocity = Vector3.zero
key(Enum.KeyCode.Two)
M.steps(5)
click()
M.steps(3)
hrp.AssemblyLinearVelocity = Vector3.new(16, 0, 0)
M.pressKey(Enum.KeyCode.W)
local mx = 900
measure("create recording", 300, function()
	mx = mx + 1
	M.moveMouse(mx, 500)
end)
M.releaseKey(Enum.KeyCode.W)
click()
M.steps(3)
hrp.AssemblyLinearVelocity = Vector3.zero
measure("create paused", 300)
key(Enum.KeyCode.Three)
M.steps(2)
measure("test playback", 250)
local g = 0
while A.mode() == 3 and g < 2000 do M.step(1 / 60); g = g + 1 end

-- (phase 5a) with a menu open: V2's main menu, HappaTAS 3's Settings window (it builds the first time)
A.request("idle")
M.steps(5)
A.openMenu()
M.steps(10)
measure("idle, menu open", 600)
A.request("create")
M.steps(5)
A.request("unpause")
M.steps(3)
hrp.AssemblyLinearVelocity = Vector3.new(16, 0, 0)
local my = 900
measure("recording, menu open", 300, function()
	my = my + 1
	M.moveMouse(my, 300)
end)
A.request("pause")
M.steps(3)
hrp.AssemblyLinearVelocity = Vector3.zero
measure("paused, menu open", 300)
A.closeMenu()
A.request("idle")
M.steps(5)

-- the world (phase 4): 100 client objects (20 moved by a script), a beat block group and a turret with the
-- kit's own loops (kit-style modules), the speed hack at 0.5x, recording
local RSt = M.services.ReplicatedStorage
local fw = Instance.new("Folder"); fw.Name = "Framework"; fw.Parent = RSt
local kitF = Instance.new("Folder"); kitF.Name = "Kit"; kitF.Parent = fw
local repo = Instance.new("Folder"); repo.Name = "Repository"; repo.Parent = kitF
local function kitModule(name, src)
	local ms = Instance.new("ModuleScript"); ms.Name = name; ms.Parent = repo
	local env = setmetatable({ script = ms }, { __index = setmetatable({ os = os }, { __index = getfenv(1) }) })
	local chunk = loadstring(src, "=" .. ms:GetFullName())
	setfenv(chunk, env)
	local mod = chunk()
	M.modules[ms] = mod
	return mod
end
local BeatKit = kitModule("BeatBlock", [[
local B = {}
function B.Loop(groups, n)
	local beat = 1
	while true do
		beat = beat % n + 1
		for i, list in pairs(groups) do for _, p in ipairs(list) do p.Transparency = (i == beat) and 0 or 0.7 end end
		task.wait(1)
	end
end
return B
]])
local TurretKit = kitModule("Turret", [[
local T = {}
function T.Loop(model, part)
	while true do
		task.wait(0.5)
		local m = Instance.new("Model"); m.Name = "Bullet"
		local p = Instance.new("Part"); p.Name = "Bullet"; p.Size = Vector3.new(1, 1, 1); p.CFrame = part.CFrame; p.Parent = m
		m.PrimaryPart = p
		m.Parent = model
	end
end
return T
]])
local CP = Instance.new("Folder"); CP.Name = "ClientParts"; CP.Parent = workspace
local cof = Instance.new("Folder"); cof.Name = "Moving Platforms"; cof.Parent = CP
local moving = {}
for i = 1, 100 do
	local p = Instance.new("Part"); p.Name = "P" .. i; p.Size = Vector3.new(4, 1, 4); p.Anchored = true
	p.CFrame = CFrame.new((i % 10) * 6, 3, 20 + math.floor(i / 10) * 6); p.Parent = cof
	if i <= 20 then moving[#moving + 1] = p end
end
local moveConn = M.services.RunService.Heartbeat:Connect(function()
	for k, p in ipairs(moving) do p.CFrame = p.CFrame * CFrame.Angles(0, 0.01 * k, 0) end
end)
local bb = Instance.new("Folder"); bb.Name = "BeatBlockGroup"; bb.Parent = CP
local bbCfg = Instance.new("Configuration"); bbCfg.Name = "BeatBlockConfiguration"
for k, v in pairs({ Interval = 1, IndicatorInterval = 0.5, Indicator = true, IndicatorSize = Vector3.new(3, 3, 3),
	OffTransparency = 0.7, OnTransparency = 0, OffCanCollide = false, OnCanCollide = true, OnCanTouch = true, OffCanTouch = false,
	MaterialIndicator = Enum.Material.SmoothPlastic, IndicatorScaleMultiplier = 1, ToggleChildren = false }) do bbCfg:SetAttribute(k, v) end
bbCfg:AddTag("CO_Visual/BeatBlock")
bbCfg.Parent = bb
local groups = {}
for i = 1, 4 do
	local p = Instance.new("Part"); p.Name = tostring(i); p.Size = Vector3.new(4, 4, 4); p.Anchored = true
	p.CFrame = CFrame.new(100 + i * 5, 2, 100); p.Parent = bb
	groups[i] = { p }
end
local turModel = Instance.new("Model"); turModel.Name = "Turret"; turModel.Parent = CP
local turPart = Instance.new("Part"); turPart.Name = "Turret"; turPart.Anchored = true
turPart.CFrame = CFrame.lookAt(Vector3.new(0, 5, 50), Vector3.new(0, 5, 100)); turPart.Parent = turModel
local turCfg = Instance.new("Configuration"); turCfg.Name = "TurretConfiguration"
for k, v in pairs({ FireRate = 2, Speed = 20, MaxLifetime = 3, Damage = 5, Range = 500, DestroyOnTouch = true }) do turCfg:SetAttribute(k, v) end
turCfg:AddTag("CO_Interactables/Turret")
turCfg.Parent = turModel
A.setSetting("Sync Client Objects", 1)
A.setSetting("Kit Scripts On TAS Clock", 0)
M.steps(2)
A.setSetting("Kit Scripts On TAS Clock", 1)
A.setSetting("Sync Kit Objects", 0)
M.steps(2)
A.setSetting("Sync Kit Objects", 1)
local gr = 0
while not A.coReady() and gr < 600 do M.step(1 / 60); gr = gr + 1 end
local loops = { task.spawn(BeatKit.Loop, groups, 4), task.spawn(TurretKit.Loop, turModel, turPart) }
A.setSetting("Speed Hack Speed", 0.5)
A.setSetting("Speed Hack", 1)
key(Enum.KeyCode.Backspace); M.steps(2); key(Enum.KeyCode.Backspace); M.steps(2)
key(Enum.KeyCode.Two)
M.steps(5)
click()
M.steps(3)
hrp.AssemblyLinearVelocity = Vector3.new(16, 0, 0)
measure("world recording", 300)
click()
M.steps(3)
A.setSetting("Speed Hack", 0)
for _, l in ipairs(loops) do task.cancel(l) end
moveConn:Disconnect()
finish()
