-- ================================================================================================
-- Client objects: the state a part had before it first changed (V2.38.15). A part that changes for the
-- first time while recording (the EToH kit's Morpher: its Morph grows and moves when a button is pressed)
-- gets its start state into the full snapshots recorded before, so playback shows it there even when the
-- part is somewhere else now (the script was run again, the TAS was loaded in a new session).
--   * the start state goes into every earlier full snapshot of this session (also the timed one after
--     10 s and the one after going back), the first change is recorded as a change from it
--   * a part made while recording doesn't appear in the snapshots from before it existed
--   * Test after the client objects were scanned again (the morph is pressed now): the morph is back on its
--     start state before the press; after saving / loading too
--   * parts that never change still cost nothing
-- (headless mock, not a real game)
-- ================================================================================================
check(boot(30), "boots")
local S, Core, CO, Store = __T.Settings, __T.Core, __T.ClientObjects, __T.Store
local C = Core.State
local RS = M.services.RunService
local guard = 0
while not (C.HRP and C.Humanoid) and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local hrp = C.HRP
local function run(n) for _ = 1, n do M.step(1 / 60) end end

local cp = Instance.new("Folder")
cp.Name = "ClientParts"
cp.Parent = workspace
local group = Instance.new("Folder")
group.Name = "Morpher Group"
group.Parent = cp
local P0 = hrp.Position + Vector3.new(6, -2, -6)
local P1 = P0 + Vector3.new(-5, 1.5, 2)
local RED, BLUE = Color3.fromRGB(255, 0, 0), Color3.fromRGB(0, 0, 255)
local function part(name, cf, size, color, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color or Color3.fromRGB(163, 162, 165)
	p.Parent = parent or group
	return p
end
local morph = part("Morph", CFrame.new(P0), Vector3.new(1, 1, 1), RED)
morph.Material = Enum.Material.Neon
local still = part("Still", CFrame.new(P0 + Vector3.new(0, 0, 8)), Vector3.new(2, 1, 2))
local fader = part("Vanisher", CFrame.new(P0 + Vector3.new(4, 0, 0)), Vector3.new(3, 1, 3))

S.Set("Sync Client Objects", 1)
local g = 0
while not CO.IsReady() and g < 600 do M.step(1 / 60); g = g + 1 end
check(CO.IsReady(), "client objects ready")
local idM = CO.Reg.keyToId["ClientParts/Morpher Group/Morph"]
local idS = CO.Reg.keyToId["ClientParts/Morpher Group/Still"]
local idF = CO.Reg.keyToId["ClientParts/Morpher Group/Vanisher"]
check(idM and idS and idF, "parts registered")

-- the "kit": the morph lerps to P1 / size 4 / blue over 30 recorded frames from frame PRESS on (like the
-- Morpher's Heartbeat lerp), the vanisher fades out at frame FADE, a part is made at frame MAKE and moves
-- at frame MOVE
local PRESS, FADE, MAKE, MOVE = 900, 930, 860, 960
local made = nil
local function recording() return C.mode == 2 and not C.paused end
local function stateAt(n)
	local a = math.clamp((n - PRESS) / 30, 0, 1)
	return Vector3.new(1, 1, 1):Lerp(Vector3.new(4, 4, 4), a), P0:Lerp(P1, a), RED:Lerp(BLUE, a)
end
local drive = RS.PreRender:Connect(function()
	if not recording() then return end
	local n = #C.data + 1 -- the frame being made now
	if n >= PRESS then
		local sz, pos, col = stateAt(n)
		morph.Size, morph.CFrame, morph.Color = sz, CFrame.new(pos), col
		if n > PRESS then morph.Material = Enum.Material.SmoothPlastic end -- (the kit's Morpher: the new morph's material)
	end
	if n >= FADE then fader.Transparency = 1 end
	if n == MAKE and not made then made = part("CloneMorph", CFrame.new(P0 + Vector3.new(0, 3, 0)), Vector3.new(1, 1, 1)) end
	if made and n >= MOVE then made.CFrame = CFrame.new(P0 + Vector3.new(0, 6, 0)) end
end)
-- what the parts really were when HappaTAS recorded them (PreSimulation)
local truth, loggedFor = {}, {}
local log = RS.PreSimulation:Connect(function()
	if not recording() then return end
	local n = #C.data
	local fd = C.data[n]
	if fd and fd.Cframe and loggedFor[n] ~= fd then
		loggedFor[n] = fd
		truth[n] = { size = morph.Size.X, pos = morph.Position, col = morph.Color, tr = fader.Transparency, mat = morph.Material }
	end
end)

local function click()
	M.services.UserInputService.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	M.services.UserInputService.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
	run(2)
end
local function key(kc, steps) M.pressKey(kc); M.releaseKey(kc); run(steps or 2) end
local function idsIn(n)
	local fr = C.data[n]
	return (fr and fr.CO) and CO.IdsOf(fr.CO) or {}
end
local function isFull(n)
	local fr = C.data[n]
	local b = fr and fr.CO and string.byte(fr.CO, 1)
	return b ~= nil and b >= 4 and b % 8 == 5
end

section("recording: the morph's start state goes into the earlier full snapshots")
key(Enum.KeyCode.Two) -- Create (paused)
click() -- Unpause
run(300)
click() -- Pause at about frame 300
-- go back 60 frames and record from there (cut frames: a new chain with its own full snapshot)
for _ = 1, 60 do key(Enum.KeyCode.F, 1) end
local backTo = C.frame
click() -- Unpause from there
run(800)
click() -- Pause
local data = C.data
check(#data > MOVE + 20, "recorded " .. #data .. " frames")
local fulls = {}
for i = 1, #data do if isFull(i) then fulls[#fulls + 1] = i end end
check(#fulls >= 3, "full snapshots at " .. table.concat(fulls, ", ") .. " (start, after going back, after 10 s)")
eq(fulls[1], 1, "the first one at frame 1")
eq(fulls[2], backTo + 1, "one where the recording went on after going back")
local beforePress = 0
for _, f in ipairs(fulls) do
	if f < PRESS then
		beforePress = beforePress + 1
		check(idsIn(f)[idM], "frame " .. f .. " (full, before the press) has the morph's start state")
		check(idsIn(f)[idF], "frame " .. f .. " (full, before the fade) has the vanisher's start state")
		check(not idsIn(f)[idS], "frame " .. f .. ": nothing for the part that never changes")
	end
end
check(beforePress >= 3, beforePress .. " full snapshots before the press")
local idC = CO.Reg.keyToId["ClientParts/Morpher Group/CloneMorph"]
check(idC ~= nil, "the part made while recording is registered")
for _, f in ipairs(fulls) do
	if f < MAKE then check(not idsIn(f)[idC], "frame " .. f .. ": nothing for the part made later") end
end
-- frames between the snapshots carry nothing new for the morph until it moves
local early = 0
for i = 2, PRESS - 1 do if not isFull(i) and idsIn(i)[idM] then early = early + 1 end end
eq(early, 0, "no morph records between the snapshots before the press")
check(idsIn(PRESS)[idM], "the press frame has the morph's change")

-- the record at the press is a change from the start state (not a whole new value): the playback state right
-- after it is still close to the start state
CO.ShowFrame(data, PRESS)
local sz = morph.Size.X
check(sz > 1 and sz < 1.5, "frame " .. PRESS .. ": the morph has just started growing (" .. sz .. ")")
CO.Release()
-- (the kit leaves the morph pressed: ShowFrame above moved it)
morph.Size, morph.CFrame, morph.Color = Vector3.new(4, 4, 4), CFrame.new(P1), BLUE
morph.Material = Enum.Material.SmoothPlastic

section("Test after the client objects were scanned again (the morph is pressed now)")
key(Enum.KeyCode.One, 4) -- Idle
S.Set("Sync Client Objects", 0)
run(2)
S.Set("Sync Client Objects", 1)
g = 0
while not CO.IsReady() and g < 600 do M.step(1 / 60); g = g + 1 end
check(CO.IsReady(), "scanned again")
near(morph.Size.X, 4, 1e-6, "the morph is in its pressed state now")
local seen = {}
local probe = RS.Heartbeat:Connect(function()
	if C.mode ~= 3 then return end
	if not seen[C.frame] then seen[C.frame] = { size = morph.Size.X, pos = morph.Position, col = morph.Color, tr = fader.Transparency, mat = morph.Material } end
end)
key(Enum.KeyCode.Three, 2) -- Test
local t0 = 0
while C.mode == 3 and t0 < 2000 do M.step(1 / 60); t0 = t0 + 1 end
local function compare(label)
	local checked, bad, worst, ex = 0, 0, 0, nil
	for f = 1, #data do
		local a, b = seen[f], truth[f]
		if a and b and (f < PRESS - 1 or f > PRESS + 32) then
			checked = checked + 1
			local d = math.max(math.abs(a.size - b.size), (a.pos - b.pos).Magnitude, math.abs(a.tr - b.tr),
				math.abs(a.col.R - b.col.R), math.abs(a.col.B - b.col.B))
			if d > worst then worst = d end
			if d > 2e-3 or a.mat ~= b.mat then
				bad = bad + 1
				ex = ex or ("frame " .. f .. ": size " .. a.size .. " / " .. b.size)
			end
		end
	end
	check(checked > 600, label .. ": " .. checked .. " frames compared")
	eq(bad, 0, label .. ": the morph and the vanisher as recorded (worst " .. worst .. (ex and (", " .. ex) or "") .. ")")
end
compare("Test")
local f10 = seen[10]
check(f10 and math.abs(f10.size - 1) < 1e-3 and (f10.pos - P0).Magnitude < 1e-3, "frame 10: the morph is small and back where it started")
check(f10 and f10.mat == Enum.Material.Neon, "frame 10: its own material (" .. tostring(f10 and f10.mat) .. ")")

section("save / load: the start states are in the file")
local function runAsync(fn)
	local done, res = false, nil
	M.resume(coroutine.create(function() res = table.pack(fn()); done = true end))
	local gg = 0
	while not done and gg < 3000 do M.step(1 / 60); gg = gg + 1 end
	return table.unpack(res or {})
end
key(Enum.KeyCode.One, 4)
local okS = runAsync(function() return Store.SaveSlot("cobase", data) end)
check(okS, "saved")
local okL, back = runAsync(function() return Store.LoadSlot("cobase") end)
check(okL and #back == #data, "loaded")
Core.SetTAS(back)
run(2)
seen = {}
key(Enum.KeyCode.Three, 2)
t0 = 0
while C.mode == 3 and t0 < 2000 do M.step(1 / 60); t0 = t0 + 1 end
compare("Test of the loaded TAS")
key(Enum.KeyCode.One, 4)

probe:Disconnect()
drive:Disconnect()
log:Disconnect()
finish()
