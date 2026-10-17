-- ================================================================================================
-- Client objects v3 (V2.38.5): each part's own clock (simulation / wall / TAS), the screw-motion model,
-- the velocity at the part's position, chains that go on after Unpause (1 Frame), old v2 data playing
-- like before, save / load
-- ================================================================================================
M.clockStep = 0
check(boot(30), "boots")
local S, Core, CO, Store = __T.Settings, __T.Core, __T.ClientObjects, __T.Store
local C = Core.State
local RS = M.services.RunService
local guard = 0
while not (C.HRP and C.Humanoid) and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local hrp = C.HRP

-- ~240 FPS with uneven frames (2.8 - 5.6 ms); physics in 1/240 s steps (a frame simulates 0, 1 or 2)
local seed = 7
local function nextDt()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return (2.8 + (seed % 1000) / 1000 * 2.8) / 1000
end
local simAcc = 0
M.simDt = function(dt)
	simAcc = simAcc + dt
	local n = math.floor(simAcc * 240 + 1e-9)
	simAcc = simAcc - n / 240
	return n / 240
end
local function run(n) for _ = 1, n do M.step(nextDt()) end end

local folder = Instance.new("Folder")
folder.Name = "ClientObjects"
folder.Parent = workspace
local function part(name, anchored, cf, size)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size or Vector3.new(4, 1, 4)
	p.Anchored = anchored
	p.CFrame = cf
	p.Parent = folder
	return p
end
local base = hrp.Position + Vector3.new(0, 0, -15)
-- a physics spinner (unanchored, moves on the simulation clock): a bar spinning on its hub, an arm 6 studs out
local HUB = base + Vector3.new(-8, 0, 0)
local W_SPIN = 1.5
local bar = part("Spinning Bar", false, CFrame.new(HUB), Vector3.new(10, 1, 1))
local arm = part("Spinning Arm", false, CFrame.new(HUB + Vector3.new(6, 0, 0)))
-- a scripted part going round a centre (anchored, its script uses os.clock(): the wall clock)
local KEYC = base + Vector3.new(8, 0, 0)
local W_KEY = 2.5
local keyPart = part("Key Part", true, CFrame.new(KEYC + Vector3.new(3, 0, 0)), Vector3.new(1, 1, 1))
-- a scripted slider moved by the simulated time (like a bullet moved in Stepped), back to the start every 30 studs
local SLIDE0 = base + Vector3.new(0, 4, 0)
local slide = part("Bullet", true, CFrame.new(SLIDE0), Vector3.new(1, 1, 1))
local still = part("Still", true, CFrame.new(base + Vector3.new(0, -4, 0)))

local spinA, slideX, lastSim = 0, 0, M.simNow
local function recording() return C.mode == 2 and not C.paused end
local spinOn = true -- the spinner's physics runs (until the test is over)
local function placeSpinner()
	local hub = CFrame.new(HUB) * CFrame.Angles(0, spinA, 0)
	for _, p in ipairs({ bar, arm }) do
		p.AssemblyLinearVelocity = Vector3.zero
		p.AssemblyAngularVelocity = Vector3.new(0, W_SPIN, 0)
		p.AssemblyCenterOfMass = HUB
	end
	bar.CFrame = hub
	arm.CFrame = hub * CFrame.new(6, 0, 0)
end
placeSpinner()
-- the "game", at the start of each frame: physics moves the spinner whenever HappaTAS doesn't hold it (it
-- anchors it while paused / testing); the scripts run all the time (the bullet's script adds up the
-- simulated time, the key's uses os.clock()), their poses are shown while recording (HappaTAS's otherwise)
local truth = {}
local drive = RS.PreRender:Connect(function()
	local sdt = M.simNow - lastSim
	lastSim = M.simNow
	if spinOn and not bar.Anchored then
		spinA = spinA + W_SPIN * sdt
		placeSpinner()
	end
	slideX = slideX + 20 * sdt
	if slideX > 30 then slideX = 0 end
	if not recording() then return end
	keyPart.CFrame = CFrame.new(KEYC) * CFrame.Angles(0, W_KEY * os.clock(), 0) * CFrame.new(3, 0, 0)
	slide.CFrame = CFrame.new(SLIDE0 + Vector3.new(slideX, 0, 0))
end)
-- where the parts really were when HappaTAS sampled them (it records in PreSimulation)
local log = RS.PreSimulation:Connect(function()
	if not recording() then return end
	local fd = C.data[#C.data]
	if fd and fd.Cframe then
		truth[#C.data] = { bar = bar.CFrame, arm = arm.CFrame, key = keyPart.CFrame, slide = slide.CFrame }
	end
end)

S.Set("Sync Client Objects", 1)
local g = 0
while not CO.IsReady() and g < 600 do M.step(1 / 60); g = g + 1 end
check(CO.IsReady(), "client objects ready")
local ids = {}
for _, n in ipairs({ "Spinning Bar", "Spinning Arm", "Key Part", "Bullet", "Still" }) do
	ids[n] = CO.Reg.keyToId["ClientObjects/" .. n]
	check(ids[n] ~= nil, n .. " registered")
end

local function key(kc, steps) M.pressKey(kc); M.releaseKey(kc); run(steps or 2) end
local function click()
	M.services.UserInputService.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	M.services.UserInputService.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
	run(2)
end

-- a small reader for the frames' client object data
local function rv(str, p)
	local result, mul = 0, 1
	while true do
		local b = string.byte(str, p)
		p = p + 1
		if b < 128 then return result + b * mul, p end
		result = result + (b - 128) * mul
		mul = mul * 128
	end
end
local function rz(str, p)
	local z
	z, p = rv(str, p)
	if z % 2 == 0 then return z / 2, p end
	return -(z + 1) / 2, p
end
local band = bit32.band
-- { kind (2-5), clocks = { [1..3] = stored change }, recs = { {id, flags} } }
local function parse(str)
	local b = string.byte(str, 1)
	local kind, p, cl = b, 2, {}
	if b >= 4 then
		kind = b % 8
		local fl = math.floor(b / 8)
		for i = 1, 3 do
			if fl % 2 == 1 then
				local v
				v, p = rz(str, p)
				cl[i] = v
			end
			fl = math.floor(fl / 2)
		end
	end
	local recs = {}
	while p <= #str do
		local id, flags
		id, p = rv(str, p)
		flags, p = rv(str, p)
		recs[#recs + 1] = { id, flags }
		if band(flags, 1024) == 0 then
			local skip = 0
			if band(flags, 1) ~= 0 then
				skip = 3
				if band(flags, 2) ~= 0 then skip = skip + 9 end
				if band(flags, 4) ~= 0 then skip = skip + 3 end
				if band(flags, 8) ~= 0 then skip = skip + 3 end
			end
			if band(flags, 16) ~= 0 then skip = skip + 1 end
			for _ = 1, skip do _, p = rv(str, p) end
			if band(flags, 128) ~= 0 then p = p + 3 end -- colour bytes, then size and material
			skip = 0
			if band(flags, 256) ~= 0 then skip = skip + 3 end
			if band(flags, 512) ~= 0 then skip = skip + 1 end
			for _ = 1, skip do _, p = rv(str, p) end
		end
	end
	return { kind = kind, clocks = cl, recs = recs }
end
-- per part: keyframes, and the clocks of its moving keyframes
local function keyStats(data, from, to)
	local st = {}
	for i = from or 1, to or #data do
		local str = data[i].CO
		if str then
			for _, r in ipairs(parse(str).recs) do
				local s = st[r[1]] or { keys = 0, sim = 0, wall = 0, game = 0, tas = 0 }
				st[r[1]] = s
				if band(r[2], 1) ~= 0 then
					s.keys = s.keys + 1
					if band(r[2], 12) ~= 0 then
						local c = (band(r[2], 2048) ~= 0 and 1 or 0) + (band(r[2], 4096) ~= 0 and 2 or 0)
						if c == 1 then s.sim = s.sim + 1
						elseif c == 2 then s.wall = s.wall + 1
						elseif c == 3 then s.game = s.game + 1
						else s.tas = s.tas + 1 end
					end
				end
			end
		end
	end
	return st
end
local function rotErr(a, b)
	local ca, cb = { a:GetComponents() }, { b:GetComponents() }
	local m = 0
	for i = 4, 12 do m = math.max(m, math.abs(ca[i] - cb[i])) end
	return m
end
-- every recorded frame shown (paused) puts every part where it really was
local function accuracy(from, to)
	local worstP, worstR, n = 0, 0, 0
	for f = from, to do
		local tr = truth[f]
		if tr then
			CO.ShowFrame(C.data, f)
			for name, p in pairs({ bar = bar, arm = arm, key = keyPart, slide = slide }) do
				local want = tr[name]
				worstP = math.max(worstP, (p.Position - want.Position).Magnitude)
				worstR = math.max(worstR, rotErr(p.CFrame, want))
			end
			n = n + 1
		end
	end
	return worstP, worstR, n
end

section("recording at ~240 FPS: every part on its own clock, the screw model keeps orbits")
key(Enum.KeyCode.Two)
eq(C.mode, 2, "Create mode")
click() -- unpause: record
run(1200)
click() -- pause
eq(C.paused, true, "paused")
local data = C.data
local nRec = #data
-- one frame in ~10 has no physics step (no PreSimulation): those frames are recorded too, so the TAS
-- keeps every frame and its time matches the time that passed
local noStep = 0
for _, f in ipairs(data) do if not f.Cframe then noStep = noStep + 1 end end
eq(noStep, 0, "every recorded frame is complete")
check(nRec >= 1195, "recorded " .. nRec .. " frames of 1200 (frames without a physics step included)")
local st = keyStats(data)
local secs = data[#data].TotalTime - data[1].TotalTime
M.realPrint(string.format("   %.2f s: keys bar %d, arm %d, key %d, bullet %d, still %d", secs,
	(st[ids["Spinning Bar"]] or {}).keys or 0, (st[ids["Spinning Arm"]] or {}).keys or 0, (st[ids["Key Part"]] or {}).keys or 0,
	(st[ids["Bullet"]] or {}).keys or 0, (st[ids["Still"]] or {}).keys or 0))
local sBar, sArm, sKey, sSl = st[ids["Spinning Bar"]], st[ids["Spinning Arm"]], st[ids["Key Part"]], st[ids["Bullet"]]
check(sBar and sBar.keys <= 5, "the bar spinning in place: a key every 2 s at most (" .. (sBar and sBar.keys or -1) .. ")")
check(sArm and sArm.keys <= 5, "the arm going round the hub: the same (" .. (sArm and sArm.keys or -1) .. ")")
check(sKey and sKey.keys <= 8, "the scripted orbit on the wall clock (" .. (sKey and sKey.keys or -1) .. ")")
check(sSl and sSl.keys <= 14, "the bullet: a key when it jumps back, otherwise every 2 s (" .. (sSl and sSl.keys or -1) .. ")")
eq(st[ids["Still"]], nil, "the part that never moves is never written")
check(sBar and sBar.sim > 0 and sBar.wall == 0 and sBar.tas == 0 and sBar.game == 0, "the physics bar moves on the simulation clock (without pauses)")
check(sArm and sArm.sim > 0 and sArm.wall == 0 and sArm.game == 0, "the physics arm moves on the simulation clock")
check(sKey and sKey.wall > 0 and sKey.wall >= sKey.keys - 2, "the os.clock() orbit moves on the wall clock (" .. (sKey and sKey.wall or -1) .. " of " .. (sKey and sKey.keys or -1) .. ")")
check(sSl and sSl.game > 0 and sSl.game >= sSl.keys - 3, "the Stepped bullet moves on game time (with pauses) (" .. (sSl and sSl.game or -1) .. " of " .. (sSl and sSl.keys or -1) .. ")")
local kinds, bytes = {}, 0
for i = 1, nRec do
	local str = data[i].CO
	if str then
		local k = string.byte(str, 1)
		if k >= 4 then k = k % 8 end
		kinds[k] = (kinds[k] or 0) + 1
		bytes = bytes + #str
	end
end
eq(kinds[2] or 0, 0, "no v2 frames")
check((kinds[5] or 0) >= 1 and (kinds[5] or 0) <= 2, "one full snapshot at the start (+ one every 10 s): " .. tostring(kinds[5]))
check(bytes < nRec * 12, "client object data is small: " .. bytes .. " bytes for " .. nRec .. " frames")
local wP, wR, nF = accuracy(1, nRec)
check(nF > 1000, "truth for " .. nF .. " frames")
check(wP <= 0.02, string.format("every shown frame within 0.02 studs of the real pose (worst %.4f)", wP))
check(wR <= 0.003, string.format("and within 0.003 in rotation (worst %.5f)", wR))

section("Unpause 1 Frame where the recorder stopped: the chains go on (no full snapshot)")
local n0 = #C.data
for _ = 1, 6 do key(Enum.KeyCode.V, 8) end
check(C.data[#C.data].Cframe ~= nil, "Unpause 1 Frame leaves no unfinished frame")
local n1 = #C.data
check(n1 > n0 and n1 <= n0 + 14, "Unpause 1 Frame recorded " .. (n1 - n0) .. " frames")
local fullAfter, keysAfter = 0, 0
for i = n0 + 1, n1 do
	local str = C.data[i].CO
	if str then
		local pr = parse(str)
		if pr.kind == 5 then fullAfter = fullAfter + 1 end
		for _, r in ipairs(pr.recs) do if band(r[2], 1) ~= 0 then keysAfter = keysAfter + 1 end end
	end
end
eq(fullAfter, 0, "no full snapshot after Unpause 1 Frame")
check(keysAfter <= 6, "parts are not written again (" .. keysAfter .. " keys in " .. (n1 - n0) .. " frames)")
local wP2, wR2, nF2 = accuracy(n0 + 1, n1)
check(nF2 >= n1 - n0 - 1, "truth for the stepped frames (" .. nF2 .. ")")
check(wP2 <= 0.02 and wR2 <= 0.003, string.format("the stepped frames are still exact (%.4f, %.5f)", wP2, wR2))

section("after going back (cut frames) the recorder starts again with a full snapshot")
local f0 = C.frame
key(Enum.KeyCode.F, 4)
key(Enum.KeyCode.F, 4)
eq(C.frame, f0 - 2, "back 2 frames")
key(Enum.KeyCode.V, 8)
local cutFirst = C.data[f0 - 1]

check(cutFirst ~= nil and cutFirst.CO ~= nil and parse(cutFirst.CO).kind == 5, "the first frame after the cut is a full snapshot")

section("a long Unpause on the same frames: chains go on, the paused time is skipped")
local n2 = #C.data
run(240) -- paused for a while: the clocks run on
click()
run(240)
click()
local n3 = #C.data
local fullLong = 0
for i = n2 + 1, n3 do
	local str = C.data[i].CO
	if str and parse(str).kind == 5 then fullLong = fullLong + 1 end
end
eq(fullLong, 0, "no full snapshot after unpausing on the last frame")
local stL = keyStats(C.data, n2 + 1, n3)
local function keysOf(n) return (stL[ids[n]] or { keys = 0 }).keys end
check(keysOf("Spinning Bar") <= 2, "the physics bar continues its chain across the pause (" .. keysOf("Spinning Bar") .. " keys)")
check(keysOf("Key Part") <= 2, "so does the os.clock() orbit: its clock counts the pause (" .. keysOf("Key Part") .. " keys)")
local wP3, wR3 = accuracy(n2 + 1, n3)
check(wP3 <= 0.02 and wR3 <= 0.003, string.format("frames after the pause are exact (%.4f, %.5f)", wP3, wR3))
-- the stored clock changes: the pause once (wall clock / game time), then small numbers: simulation steps
-- 1 byte; the wall clock is stored minus the frame's FrameTime (the mock hands Heartbeat's dt over one
-- frame later than Roblox, so here its changes are up to a frame's dt apart: 2 bytes)
local big, small = 0, 0
for i = n2 + 1, n3 do
	local str = C.data[i].CO
	if str then
		local pr = parse(str)
		for c = 1, 3 do
			local v = pr.clocks[c]
			if v then
				local lim = (c == 2) and 300 or 63
				if math.abs(v) > lim then big = big + 1 else small = small + 1 end
			end
		end
	end
end
check(big <= 4 and small > 400, "clock changes are small except after the pause (" .. big .. " big, " .. small .. " small)")

section("save / load: file version 4, the client object data comes back the same")
local okS, nfS, nbS, info = Store.SaveSlot("coclock", C.data)
check(okS, "saved")
eq(info and info.version, 4, "file version 4 (v3 client object frames)")
local raw = M.fs["HappaTasPort/1234567/coclock.tas"]
check(raw ~= nil and string.byte(raw, 5) == 4, "version byte 4 in the file")
local okL, back = Store.LoadSlot("coclock")
check(okL and #back == #C.data, "loaded " .. tostring(okL and #back))
local same = okL
if okL then
	for i = 1, #back do
		if back[i].CO ~= C.data[i].CO then same = false break end
	end
end
check(same, "every frame's client object data is identical after loading")

section("old v2 data still plays with the straight-line model, v3 with the screw model on its clock")
key(Enum.KeyCode.One, 4)
local function zig(v) if v >= 0 then return v * 2 end return -v * 2 - 1 end
local function var(buf, n)
	while n >= 128 do buf[#buf + 1] = string.char(n % 128 + 128); n = math.floor(n / 128) end
	buf[#buf + 1] = string.char(n)
end
local P0 = still.Position
-- clocks = { [1..3] = value } (carried clocks)
local function header(kind, clocks)
	local b, bits = kind, { 8, 16, 32 }
	for i = 1, 3 do if clocks and clocks[i] then b = b + bits[i] end end
	local out = { string.char(b) }
	for i = 1, 3 do if clocks and clocks[i] then var(out, zig(clocks[i])) end end
	return out
end
local function keyString(kind, flags, lv, av, clocks)
	local b = header(kind, clocks)
	var(b, ids.Still)
	var(b, flags)
	for _, v in ipairs({ P0.X, P0.Y, P0.Z }) do var(b, zig(math.floor(v * 1000 + 0.5))) end
	for _, v in ipairs({ 1000, 0, 0, 0, 1000, 0, 0, 0, 1000 }) do var(b, zig(v)) end
	for _, v in ipairs(lv) do var(b, zig(v)) end
	for _, v in ipairs(av) do var(b, zig(v)) end
	return table.concat(b)
end
local function marker(clocks) return table.concat(header(4, clocks)) end
local P0q = Vector3.new(math.floor(P0.X * 1000 + 0.5) / 1000, math.floor(P0.Y * 1000 + 0.5) / 1000, math.floor(P0.Z * 1000 + 0.5) / 1000)
-- v2: 10 studs/s along X, 1 rad/s around Y, 0.5 s later: a straight line
local d2 = { { TotalTime = 0, FrameTime = 0, CO = keyString(3, 15, { 10000, 0, 0 }, { 0, 1000, 0 }) }, { TotalTime = 0.5, FrameTime = 0.5 } }
CO.ShowFrame(d2, 2)
near((still.Position - (P0q + Vector3.new(5, 0, 0))).Magnitude, 0, 1e-4, "v2: straight line (5 studs along X)")
near(rotErr(still.CFrame, CFrame.fromAxisAngle(Vector3.yAxis, 0.5)), 0, 1e-4, "v2: turned 0.5 rad")
-- v3, the same key (on the TAS clock): a circle around the screw axis
local ctr = P0q + Vector3.new(0, 1, 0):Cross(Vector3.new(10, 0, 0)) / 1
local function screw(ang) return ctr + CFrame.fromAxisAngle(Vector3.yAxis, ang) * (P0q - ctr) end
local d3 = { { TotalTime = 0, FrameTime = 0, CO = keyString(5, 15, { 10000, 0, 0 }, { 0, 1000, 0 }) }, { TotalTime = 0.5, FrameTime = 0.5 } }
CO.ShowFrame(d3, 2)
near((still.Position - screw(0.5)).Magnitude, 0, 1e-3, "v3: on the circle (screw motion)")
-- the stored clocks: the key at simulation step 24 (0.1 s), frame 2 (TotalTime 0.5) at step 156 (0.65 s): the
-- part has moved on 0.55 s of simulated time
local d4 = { { TotalTime = 0, FrameTime = 0, CO = keyString(5, 15 + 2048, { 10000, 0, 0 }, { 0, 1000, 0 }, { 24 }) },
	{ TotalTime = 0.5, FrameTime = 0.5, CO = marker({ 132 }) } }
CO.ShowFrame(d4, 2)
near((still.Position - screw(0.55)).Magnitude, 0, 1e-3, "v3 on the simulation clock: 0.55 s of simulated time")
-- the wall clock in 20 us units: -1000 (-0.02 s), then 26500 (0.53 s): stored as the change minus FrameTime
local d5 = { { TotalTime = 0, FrameTime = 0, CO = keyString(5, 15 + 4096, { 10000, 0, 0 }, { 0, 1000, 0 }, { nil, -1000 }) },
	{ TotalTime = 0.5, FrameTime = 0.5, CO = marker({ nil, 26500 + 1000 - 25000 }) } }
CO.ShowFrame(d5, 2)
near((still.Position - screw(0.55)).Magnitude, 0, 1e-3, "v3 on the wall clock: its own clock (0.55 s)")
-- game time (clock 3) the same way
local d6 = { { TotalTime = 0, FrameTime = 0, CO = keyString(5, 15 + 6144, { 10000, 0, 0 }, { 0, 1000, 0 }, { nil, nil, 1000 }) },
	{ TotalTime = 0.5, FrameTime = 0.5, CO = marker({ nil, nil, 132 }) } }
CO.ShowFrame(d6, 2)
near((still.Position - screw(0.55)).Magnitude, 0, 1e-3, "v3 on game time (0.55 s)")
CO.Release()

spinOn = false
drive:Disconnect()
log:Disconnect()
M.simDt = nil
finish()
