-- ================================================================================================
-- Trace scenario: one fixed session run on V2.38.16 and on HappaTAS 3 (through adapter_v2.lua /
-- adapter_v3.lua, which define the global A). Every observable result is printed as a "T|group|..." line;
-- tools/trace3.sh keeps the groups and frame fields being compared and diffs the two runs.
--   T|mode|tag|mode|frame|paused|count
--   T|F|tag|i|Field|value              (one line per field of each recorded frame)
--   T|W.char|tag|...  W.cam  W.input  W.anim  W.tool   (the world after each step)
-- Only the mock and A are used, so both builds see exactly the same inputs.
-- ================================================================================================
math.randomseed(7) -- (the Animate engine picks idle animations with math.random)
M.clockStep = 0 -- os.clock() = frame time: the trace doesn't depend on how often a build reads it
check(A.boot(), "boots")
local UIS = M.services.UserInputService
local cam = workspace.CurrentCamera

local function out(...)
	local t = { ... }
	for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
	M.realPrint("T|" .. table.concat(t, "|"))
end
local function num(v) return string.format("%.6f", v) end
local function fmt(v)
	local t = typeof(v)
	if t == "number" then return string.format("%.9g", v) end
	if t == "string" then return string.format("%q", v) end
	if t == "boolean" or t == "nil" then return tostring(v) end
	if t == "EnumItem" then return tostring(v) end
	if t == "Instance" then return "<" .. tostring(v.Name) .. ">" end
	if t == "CFrame" then
		local c = { v:GetComponents() }
		for i = 1, 12 do c[i] = num(c[i]) end
		return "CF(" .. table.concat(c, ",") .. ")"
	end
	if t == "Vector3" then return "V3(" .. num(v.X) .. "," .. num(v.Y) .. "," .. num(v.Z) .. ")" end
	if t == "table" then
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b)
			local ta, tb = type(a), type(b)
			if ta ~= tb then return ta < tb end
			return a < b
		end)
		local parts = {}
		for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. fmt(v[k]) end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return t .. "(" .. tostring(v) .. ")"
end

local function modeLine(tag) out("mode", tag, A.mode(), A.frame(), tostring(A.paused()), A.count()) end
local logPos = 0
local function world(tag)
	local hrp, hum = A.char()
	if hrp then
		out("W.char", tag, fmt(hrp.CFrame), fmt(hrp.AssemblyLinearVelocity), fmt(hrp.AssemblyAngularVelocity),
			hum and fmt(hum:GetState()) or "-", tostring(hrp.Anchored), hum and tostring(hum.AutoRotate) or "-",
			hum and tostring(hum:GetStateEnabled(Enum.HumanoidStateType.Jumping)) or "-")
		local head = hrp.Parent and hrp.Parent:FindFirstChild("Head")
		out("W.cam", tag, fmt(cam.CFrame), fmt(cam.Focus), fmt(cam.CameraType), fmt(UIS.MouseBehavior),
			head and fmt(head.LocalTransparencyModifier) or "-")
		local tracks = {}
		local anim = hum and hum:FindFirstChildOfClass("Animator")
		if anim then
			for _, tr in ipairs(anim:GetPlayingAnimationTracks()) do
				local id = tr.Animation and tr.Animation.AnimationId or "?"
				tracks[#tracks + 1] = id .. "@" .. math.floor((tr.Speed or 0) * 1000 + 0.5) .. "/" .. math.floor((tr.TimePosition or 0) * 1000 + 0.5)
			end
		end
		table.sort(tracks)
		out("W.anim", tag, table.concat(tracks, ";"))
		local tool = hrp.Parent and hrp.Parent:FindFirstChildOfClass("Tool")
		out("W.tool", tag, tool and tool.Name or "-")
	end
	local lines = {}
	for i = logPos + 1, #M.inputLog do
		local e = M.inputLog[i]
		local t = {}
		for k = 1, #e do t[k] = tostring(e[k]) end
		lines[#lines + 1] = table.concat(t, ",")
	end
	logPos = #M.inputLog
	if #lines > 0 then out("W.input", tag, table.concat(lines, " ")) end
end
-- skip: fields left out of this dump
local function frames(tag, skip)
	for i = 1, A.count() do
		local fr = A.frameV2(i)
		local keys = {}
		for k in pairs(fr) do
			if not (skip and skip[k]) then keys[#keys + 1] = k end
		end
		table.sort(keys)
		for _, k in ipairs(keys) do out("F", tag, i, k, fmt(fr[k])) end
	end
end
local function step(tag, n, dt)
	for k = 1, (n or 1) do
		M.step(dt or 1 / 60)
		world(tag .. (n and n > 1 and ("." .. k) or ""))
	end
	modeLine(tag)
end
local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
local function click()
	UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	UIS.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in pairs(t) do c[k] = deepCopy(v) end
	return c
end

-- a tool in the backpack
local sword = Instance.new("Tool")
sword.Name = "Sword"
sword.Parent = M.player:FindFirstChildOfClass("Backpack")

local yaw = 0
local function recordFrames(tag, n, startAt, perFrame)
	for f = startAt, startAt + n - 1 do
		local hrp, hum = A.char()
		yaw = yaw + 0.01
		cam.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 4, 12)
		if f == 10 then M.pressKey(Enum.KeyCode.W) end
		if f == 30 then key(Enum.KeyCode.Space) end
		if f == 40 then hum:EquipTool(sword) end
		if f == 45 then sword:Activate() end
		if f == 47 then sword:Deactivate() end
		if f == 50 then M.pressKey(Enum.KeyCode.A) end
		if f == 60 then M.mouseDown(2, false) end
		if f == 80 then M.releaseKey(Enum.KeyCode.W) end
		if f == 90 then M.mouseUp(2, false); hum:UnequipTools() end
		if f == 100 or f == 110 then M.wheel(f == 100 and 1 or -1) end
		if f == 120 then M.releaseKey(Enum.KeyCode.A) end
		if f >= 120 and f < 130 then hum:ChangeState(Enum.HumanoidStateType.Climbing) end
		if f == 130 then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
		if f == 140 then hum:ChangeState(Enum.HumanoidStateType.Freefall) end
		if f >= 170 and f <= 200 then hum:ChangeState(Enum.HumanoidStateType.Landed) end
		if perFrame then perFrame(f, hrp, hum) end
		hrp.AssemblyLinearVelocity = Vector3.new(8 + (f % 20), (f % 40 < 20) and 2 or -2, (f % 30) - 15)
		hrp.AssemblyAngularVelocity = Vector3.new(0, (f % 7) * 0.1, 0)
		M.moveMouse(800 + f * 2, 400 + (f % 50))
		M.step(1 / 60)
		world(tag .. f)
	end
	modeLine(tag)
end

-- ------------------------------------------------------------------ idle, create, record
world("idle"); modeLine("idle")
key(Enum.KeyCode.Two)
step("create", 5)
click()
step("unpause", 2)
recordFrames("rec", 200, 1)
click()
step("paused", 3)
frames("rec1")

-- ------------------------------------------------------------------ scrub while paused
M.pressKey(Enum.KeyCode.R)
step("back", 20)
M.releaseKey(Enum.KeyCode.R)
step("backEnd", 2)
key(Enum.KeyCode.G); step("fwd1", 2)
key(Enum.KeyCode.F); step("back1", 2)
key(Enum.KeyCode.F); step("back1b", 2)
M.pressKey(Enum.KeyCode.T)
step("fwd", 5)
M.releaseKey(Enum.KeyCode.T)
step("fwdEnd", 2)
key(Enum.KeyCode.V)
step("unpause1f", 6)
key(Enum.KeyCode.E)
step("return", 2)

-- ------------------------------------------------------------------ cut + record more (240 FPS frames without a physics step; a ladder jump at the end)
click()
step("unpause2", 2)
local phys = 0
M.simDt = function(dt) phys = phys + 1; return (phys % 5 == 0) and 0 or dt end
for f = 300, 329 do
	local hrp = A.char()
	hrp.AssemblyLinearVelocity = Vector3.new(4, 0, f % 9)
	M.moveMouse(700 + f, 300)
	M.step(1 / 240)
	world("r240-" .. f)
end
M.simDt = nil
recordFrames("rec2-", 30, 330, function(f, hrp, hum)
	if f == 357 or f == 358 then hum:ChangeState(Enum.HumanoidStateType.Climbing) end
	if f == 359 then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end)
click()
step("paused2", 3)

-- ------------------------------------------------------------------ death and respawn while recording (Record Death & Respawn on)
click()
step("unpause3", 2)
recordFrames("rec3-", 10, 400)
do
	local hrp, hum = A.char()
	hum.Health = 0
	hum:ChangeState(Enum.HumanoidStateType.Dead)
	hum.Died:Fire()
end
step("dead", 5)
do
	local old = M.player.Character
	old:Destroy()
	local ch = M.makeCharacter(Vector3.new(0, 3, 0))
	M.player.CharacterAdded:Fire(ch)
end
step("respawn", 5)
recordFrames("rec4-", 20, 420)
click()
step("paused3", 3)
frames("rec2")

-- ------------------------------------------------------------------ Test (Interpolate Playback on)
key(Enum.KeyCode.Three)
local n = 0
step("test", 1)
while A.mode() == 3 and n < 900 do n = n + 1; step("play" .. n) end
out("mode", "testDone", n, A.mode())
step("afterTest", 3)

-- Test from the middle (Restart When Testing off)
key(Enum.KeyCode.Two)
step("create2", 3)
M.pressKey(Enum.KeyCode.R)
step("backMid", 30)
M.releaseKey(Enum.KeyCode.R)
step("backMidEnd", 2)
A.setSetting("Restart When Testing", 0)
key(Enum.KeyCode.Three)
n = 0
step("testMid", 1)
while A.mode() == 3 and n < 900 do n = n + 1; step("playMid" .. n) end
A.setSetting("Restart When Testing", 1)
key(Enum.KeyCode.One)
step("idle2", 3)

-- ------------------------------------------------------------------ optimize (two presses in Idle)
A.optimizeTwice()
step("optimized", 2)
frames("opt")

-- Test at speed 2 without interpolation, then at speed -1 with it
A.setSetting("Playback Speed", 2)
A.setSetting("Interpolate Playback", 0)
key(Enum.KeyCode.Three)
n = 0
step("test2", 1)
while A.mode() == 3 and n < 900 do n = n + 1; step("play2-" .. n) end
A.setSetting("Interpolate Playback", 1)
A.setSetting("Playback Speed", -1)
key(Enum.KeyCode.Three)
n = 0
step("testRev", 1)
while A.mode() == 3 and n < 900 do n = n + 1; step("playRev" .. n) end
A.setSetting("Playback Speed", 1)
step("afterRev", 3)

-- ------------------------------------------------------------------ merge: record from the end of this run to its own start
local runB = deepCopy(A.frames())
A.merge(deepCopy(runB), "after")
step("merge", 3)
click()
step("mergeUnpause", 2)
do
	local start = runB[1].Cframe
	local goal = Vector3.new(start[1], start[2], start[3])
	recordFrames("mergeRec", 20, 500, function(f, hrp)
		hrp.CFrame = CFrame.new(hrp.Position:Lerp(goal, (f - 499) / 20))
	end)
end
click()
step("mergePaused", 5)
A.mergeClick()
step("merged", 3)
frames("merged")

-- ------------------------------------------------------------------ save, clear, load, Test (each build its own format)
key(Enum.KeyCode.One)
step("idleSave", 3)
A.save("traced")
step("saved", 3)
A.clearRun()
step("cleared", 2)
A.load("traced")
step("loaded", 3)
-- (V2's codec puts the viewport size on every frame after the one that recorded it; HappaTAS 3's v6 gives
-- the recording back as it was: the viewport stays on the frames that had it. Playback is the same.)
frames("loaded", { VX = true, VY = true })
key(Enum.KeyCode.Three)
n = 0
step("testLoaded", 1)
while A.mode() == 3 and n < 900 do n = n + 1; step("playLoaded" .. n) end
key(Enum.KeyCode.One)
step("idleLoaded", 3)

-- ------------------------------------------------------------------ the file V2 saved (HappaTAS 3 reads V2's bytes)
A.clearRun()
step("clearedV2", 2)
A.loadV2File()
step("loadedV2", 3)
frames("loadedV2")
key(Enum.KeyCode.Three)
n = 0
step("testV2File", 1)
while A.mode() == 3 and n < 900 do n = n + 1; step("playV2File" .. n) end
key(Enum.KeyCode.One)
step("idleV2File", 3)
finish()
