-- Differential trace: one fixed session (record with keys / mouse / camera / client objects / a kit
-- button, pause, scrub, cut + re-record, save, load, optimize, playback). Every observable result is
-- printed as "T|..." lines. tools/diff_builds.sh runs two builds and diffs the traces, so an
-- optimisation that changes behaviour shows up as a diff line.
M.clockStep = 0 -- os.clock() = frame time, so the trace does not depend on how often a build calls it
check(boot(30), "boots")
local S, Core, CO, Store = __T.Settings, __T.Core, __T.ClientObjects, __T.Store
local C = Core.State
local guard = 0
while not (C.HRP and C.Humanoid) and guard < 200 do M.step(1 / 60); guard = guard + 1 end
check(C.HRP ~= nil, "character loaded")
local hrp = C.HRP
local cam = workspace.CurrentCamera

local function T(...)
	local t = { ... }
	for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
	M.realPrint("T|" .. table.concat(t, "|"))
end
local function num(v) return string.format("%.6f", v) end
local function fmt(v)
	local t = typeof(v)
	if t == "number" then return string.format("%.9g", v) end
	if t == "string" then
		if v:find("[^%w%p ]") then return "x" .. (v:gsub(".", function(c) return string.format("%02x", string.byte(c)) end)) end
		return string.format("%q", v)
	end
	if t == "boolean" or t == "nil" then return tostring(v) end
	if t == "Instance" then return "<" .. tostring(v.Name) .. ">" end
	if t == "Font" then return "Font(" .. tostring(v.Family) .. "," .. tostring(v.Weight) .. "," .. tostring(v.Style) .. ")" end
	if t == "CFrame" then
		local c = { v:GetComponents() }
		for i = 1, 12 do c[i] = num(c[i]) end
		return "CF(" .. table.concat(c, ",") .. ")"
	end
	if t == "Vector3" then return "V3(" .. num(v.X) .. "," .. num(v.Y) .. "," .. num(v.Z) .. ")" end
	if t == "Rect" or t == "NumberRange" then return t .. "(" .. tostring(v.Min) .. "," .. tostring(v.Max) .. ")" end
	local ok, s = pcall(tostring, v)
	return t .. "(" .. (ok and s or "?") .. ")"
end
local function ser(v, out)
	if type(v) == "table" and typeof(v) == "table" then
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b)
			local ta, tb = type(a), type(b)
			if ta ~= tb then return ta < tb end
			return a < b
		end)
		out[#out + 1] = "{"
		for _, k in ipairs(keys) do
			out[#out + 1] = tostring(k) .. "="
			ser(v[k], out)
			out[#out + 1] = ","
		end
		out[#out + 1] = "}"
	else
		out[#out + 1] = fmt(v)
	end
	return out
end
local function S_(v) return table.concat(ser(v, {})) end
local function hash(s)
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = (h * 16777619) % 4294967296
	end
	return string.format("%08x", h)
end

-- ------------------------------------------------------------------ GUI dump (every instance + every property set)
local function dumpTree(root, prefix)
	local d = rawget(root, "_d")
	local keys = {}
	for k in pairs(d.props) do if k ~= "Name" then keys[#keys + 1] = k end end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. fmt(d.props[k]) end
	T("G", prefix, d.class.Name, table.concat(parts, ";"))
	local kids = root:GetChildren()
	for i, ch in ipairs(kids) do dumpTree(ch, prefix .. "/" .. i .. ":" .. tostring(ch.Name)) end
end
for _, g in ipairs(M.hui:GetChildren()) do dumpTree(g, tostring(g.Name)) end
for _, g in ipairs(M.services.CoreGui:GetChildren()) do
	if g ~= M.hui then dumpTree(g, "core:" .. tostring(g.Name)) end
end

-- ------------------------------------------------------------------ world: client objects + a kit button
local folder = Instance.new("Folder")
folder.Name = "ClientObjects"
folder.Parent = workspace
local objs = {}
for i = 1, 24 do
	local p = Instance.new("Part")
	p.Name = (i % 5 == 0) and "Spinner" or "Part"
	p.Size = Vector3.new(4, 1, 4)
	p.CFrame = CFrame.new((i % 6) * 6 - 15, 2 + math.floor(i / 6), -8 - math.floor(i / 6) * 5)
	p.Anchored = (i % 7) ~= 3
	p.Parent = folder
	objs[i] = p
end
local btnModel = Instance.new("Model")
btnModel.Name = "Button1"
btnModel.Parent = workspace
local pressed = Instance.new("BoolValue"); pressed.Name = "Pressed"; pressed.Parent = btnModel
local timerStart = Instance.new("NumberValue"); timerStart.Name = "TimerStart"; timerStart.Parent = btnModel
local bpart = Instance.new("Part"); bpart.Name = "ButtonPart"; bpart.Anchored = true; bpart.Parent = btnModel

local tW = 0
local worldConn = M.services.RunService.Heartbeat:Connect(function(dt)
	tW = tW + dt
	for i, p in ipairs(objs) do
		local k = i % 7
		if C.mode == 3 or (C.mode == 2 and C.paused) then
			-- HappaTAS drives them while testing / paused; the game keeps fighting on scripted ones
			if k == 1 then p.CFrame = p.CFrame * CFrame.Angles(0, 0.05, 0) end
		elseif k == 1 then
			p.CFrame = CFrame.new((i % 6) * 6 - 15, 2, -8 - math.floor(i / 6) * 5) * CFrame.Angles(0, tW * 2, 0)
		elseif k == 2 then
			p.CFrame = CFrame.new((i % 6) * 6 - 15 + math.sin(tW * 3) * 4, 2, -8 - math.floor(i / 6) * 5)
		elseif k == 3 then
			p.AssemblyLinearVelocity = Vector3.new(0, -3, 0)
			p.CFrame = p.CFrame + Vector3.new(0, -3 * dt, 0)
		elseif k == 4 then
			local s = math.floor(tW * 4) % 4
			p.Transparency = s * 0.25
			p.Color = Color3.fromRGB(50 * s, 200, 10)
			p.CanCollide = s % 2 == 0
			if s == 3 then p.Size = Vector3.new(4, 2, 4) else p.Size = Vector3.new(4, 1, 4) end
		end
	end
end)

S.Set("Sync Client Objects", 1)
local g3 = 0
while not CO.IsReady() and g3 < 600 do M.step(1 / 60); g3 = g3 + 1 end
check(CO.IsReady(), "client objects ready")
M.steps(5)

local function click()
	local inp = M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin)
	M.services.UserInputService.InputBegan:Fire(inp, false)
	M.services.UserInputService.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
local function worldState(tag)
	local parts = {}
	for i, p in ipairs(objs) do
		parts[#parts + 1] = fmt(p.CFrame) .. fmt(p.Transparency) .. fmt(p.Color) .. fmt(p.Size) .. fmt(p.CanCollide) .. fmt(p.Anchored)
	end
	T("W", tag, C.mode, C.frame, tostring(C.paused), fmt(hrp.CFrame), fmt(hrp.AssemblyLinearVelocity), fmt(cam.CFrame),
		hash(table.concat(parts, ";")), tostring(pressed.Value), string.format("%.4f", timerStart.Value))
end
local logPos = 0
local function inputLog(tag)
	local lines = {}
	for i = logPos + 1, #M.inputLog do
		local e = M.inputLog[i]
		local t = {}
		for k = 1, #e do t[k] = tostring(e[k]) end
		lines[#lines + 1] = table.concat(t, ",")
	end
	logPos = #M.inputLog
	if #lines > 0 then T("I", tag, table.concat(lines, " ")) end
end
local function stats(tag)
	for _, name in ipairs({ "IdleStats", "CreateStats", "TestStats" }) do
		local f = C.Gui and C.Gui:FindFirstChild(name)
		if f and f.Visible then
			local texts = {}
			for _, ch in ipairs(f:GetChildren()) do
				if ch:IsA("TextLabel") then texts[#texts + 1] = tostring(ch.Name) .. ":" .. ch.Text end
			end
			table.sort(texts)
			T("S", tag, name, table.concat(texts, "|"))
		end
	end
end

-- ------------------------------------------------------------------ idle
stats("idle")
worldState("idle")

-- ------------------------------------------------------------------ record
key(Enum.KeyCode.Two)
M.steps(5)
worldState("create")
click()
M.steps(2)
T("rec-start", C.mode, tostring(C.paused), #Core.GetTAS())
local yaw = 0
local function recordFrames(n, startAt)
	for f = startAt, startAt + n - 1 do
		yaw = yaw + 0.01
		cam.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 4, 12)
		if f == 10 then M.pressKey(Enum.KeyCode.W) end
		if f == 30 then key(Enum.KeyCode.Space) end
		if f == 50 then M.pressKey(Enum.KeyCode.A) end
		if f == 60 then M.mouseDown(2, false) end
		if f == 70 then pressed.Value = true; timerStart.Value = os.clock() end
		if f == 80 then M.releaseKey(Enum.KeyCode.W) end
		if f == 90 then M.mouseUp(2, false) end
		if f == 100 or f == 110 then M.wheel(f == 100 and 1 or -1) end
		if f == 120 then M.releaseKey(Enum.KeyCode.A) end
		if f == 150 then pressed.Value = false end
		hrp.AssemblyLinearVelocity = Vector3.new(8 + (f % 20), (f % 40 < 20) and 2 or -2, (f % 30) - 15)
		M.moveMouse(800 + f * 2, 400 + (f % 50))
		M.step(1 / 60)
		if f % 10 == 0 then stats("rec" .. f) end
	end
end
recordFrames(200, 1)
click()
M.steps(3)
T("paused", C.mode, tostring(C.paused), #Core.GetTAS(), C.frame)
worldState("paused")
stats("paused")

-- ------------------------------------------------------------------ scrub while paused
M.pressKey(Enum.KeyCode.R)
for i = 1, 20 do M.step(1 / 60); worldState("back" .. i) end
M.releaseKey(Enum.KeyCode.R)
M.steps(2)
key(Enum.KeyCode.G); M.steps(2); worldState("fwd1")
key(Enum.KeyCode.F); M.steps(2); worldState("back1")
key(Enum.KeyCode.F); M.steps(2); worldState("back1b")
M.pressKey(Enum.KeyCode.T)
for i = 1, 5 do M.step(1 / 60); worldState("fwd" .. i) end
M.releaseKey(Enum.KeyCode.T)
M.steps(2)
stats("scrubbed")
T("scrubbed", C.frame, #Core.GetTAS())

-- ------------------------------------------------------------------ cut + record more
click()
M.steps(2)
recordFrames(60, 300)
click()
M.steps(3)
T("paused2", C.mode, tostring(C.paused), #Core.GetTAS(), C.frame)
worldState("paused2")

local data = Core.GetTAS()
local all = {}
for i, fr in ipairs(data) do
	local s = S_(fr)
	all[#all + 1] = s
	T("F", i, s)
end
local memHash = hash(table.concat(all, "\n"))
T("frames", #data, memHash)

-- ------------------------------------------------------------------ save + load
local okS, nF, nB = Store.SaveSlot("diff", data)
T("save", tostring(okS), tostring(nF), tostring(nB))
local bytes = M.fs[Store.SlotPath("diff")]
T("file", bytes and #bytes or -1, bytes and hash(bytes) or "-")
local okL, loaded = Store.LoadSlot("diff")
T("load", tostring(okL), type(loaded) == "table" and #loaded or -1)
if okL then
	local all2 = {}
	for i, fr in ipairs(loaded) do all2[#all2 + 1] = S_(fr) end
	T("loadedHash", hash(table.concat(all2, "\n")))
	for i = 1, #loaded do T("L", i, all2[i]) end
	Core.SetTAS(loaded)
end
M.steps(2)

-- ------------------------------------------------------------------ playback
key(Enum.KeyCode.Three)
M.steps(1)
T("test", C.mode, C.frame)
local n = 0
while C.mode == 3 and n < 600 do
	M.step(1 / 60)
	n = n + 1
	worldState("play" .. n)
	inputLog("play" .. n)
	if n % 15 == 0 then stats("play" .. n) end
end
T("test-done", n, C.mode)
M.steps(3)
stats("after")
worldState("after")

-- ------------------------------------------------------------------ optimize (two presses, the first one waits)
local co1 = coroutine.create(function() C.inputs.Optimize() end)
M.resume(co1)
M.steps(2)
local co2 = coroutine.create(function() C.inputs.Optimize() end)
M.resume(co2)
M.steps(120)
local opt = Core.GetTAS()
local all3 = {}
for i, fr in ipairs(opt) do all3[#all3 + 1] = S_(fr) end
T("optimized", #opt, hash(table.concat(all3, "\n")))

-- second playback of the optimized TAS at playback speed 2 (no interpolation)
S.Set("Playback Speed", 2)
S.Set("Interpolate Playback", 0)
key(Enum.KeyCode.Three)
M.steps(1)
local n2 = 0
while C.mode == 3 and n2 < 600 do
	M.step(1 / 60)
	n2 = n2 + 1
	worldState("play2-" .. n2)
	inputLog("play2-" .. n2)
end
T("test2-done", n2)
S.Set("Playback Speed", 1)
S.Set("Interpolate Playback", 1)
worldConn:Disconnect()
finish()
