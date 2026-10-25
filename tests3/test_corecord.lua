-- ================================================================================================
-- HappaTAS 3, phase 4: the client object recorder (V2.38.17 p13_clientobjects.lua 520-1110): what goes
-- into a frame's client object record (column v2CO), in V2's byte layout
-- ================================================================================================
M.clockStep = 0
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local Format = __T3("world/co/format")
local tl = E.tl
local hrp = E.char.hrp

local folder = Instance.new("Folder")
folder.Name = "ClientObjects"
folder.Parent = workspace
local function mk(name, x, anchored)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(4, 1, 4)
	p.CFrame = CFrame.new(x, 3, -8)
	p.Anchored = anchored ~= false
	p.Parent = folder
	return p
end
local still = {}
for i = 1, 20 do still[i] = mk("Still" .. i, i * 5 - 50) end
local spinner = mk("Spinner", 0)
local slider = mk("Slider", 10)
local morph = mk("Morph", -10)
local frameN, spinOn = 0, false
local conn = M.services.RunService.Heartbeat:Connect(function()
	if E.mode == 3 or (E.mode == 2 and E.paused) then return end
	frameN = frameN + 1
	if spinOn then spinner.CFrame = CFrame.new(0, 3, -8) * CFrame.Angles(0, frameN / 30, 0) end
	if frameN == 200 then morph.CFrame = morph.CFrame + Vector3.new(0, 2, 0) end
end)

E.settings:set("syncClientObjects", 1)
local g = 0
while not E.co:isReady() and g < 600 do M.step(1 / 60); g = g + 1 end
check(E.co:isReady(), "client objects ready")
check(E.co:keyOf(spinner) == "ClientObjects/Spinner", "keyOf through E.co")

local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
local function click()
	local UIS = M.services.UserInputService
	UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	UIS.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
-- the ids a frame's record mentions, and each one's flags
local function records(i)
	local str = tl:getList("v2CO", i)
	if type(str) ~= "string" then return nil end
	return Format.parse(str)
end

section("static parts cost nothing")
key(Enum.KeyCode.Two)
M.steps(3)
click()
M.steps(2)
local first = tl:count()
for _ = 1, 150 do
	hrp.AssemblyLinearVelocity = Vector3.new(1, 0, 0)
	M.step(1 / 60)
end
local n = tl:count()
check(n >= 140, "recorded " .. n .. " frames")
local withRec = 0
for i = 1, n do if tl:getList("v2CO", i) then withRec = withRec + 1 end end
eq(withRec, 1, "only the first frame (a full snapshot) has a record")
local r1 = records(1)
check(r1 ~= nil and r1.byte % 8 == 5, "frame 1 is a full snapshot")
check(r1 and r1.byte >= 64, "the first snapshot of a recording starts new clocks (+ 64)")
eq(r1 and #r1.items, 0, "with nothing in it: every part is on its start state")

section("a scripted spinner records every few frames, on a script clock")
spinOn = true
local from = tl:count() + 1
for _ = 1, 120 do M.step(1 / 60) end
local to = tl:count()
local keyFrames, spinnerId = 0, nil
for i = from, to do
	local r = records(i)
	if r then
		for _, it in ipairs(r.items) do
			if it.id then
				spinnerId = spinnerId or it.id
				if Format.has(it.flags, Format.K_KEY) then keyFrames = keyFrames + 1 end
			end
		end
	end
end
check(keyFrames > 0, "the spinner has keyframes")
check(keyFrames < (to - from + 1) / 3, "fewer keyframes than a third of the frames (" .. keyFrames .. ")")
spinOn = false

section("a physics part records on the simulation clock")
local box = mk("Box", 20, false)
box.AssemblyLinearVelocity = Vector3.new(0, 0, 5)
M.steps(4)
local seen = false
for _ = 1, 60 do
	box.CFrame = box.CFrame + Vector3.new(0, 0, 5 / 60)
	M.step(1 / 60)
	local r = records(tl:count())
	if r then
		for _, it in ipairs(r.items) do
			if it.flags and Format.has(it.flags, Format.K_LV) and Format.has(it.flags, Format.K_CK1) and not Format.has(it.flags, Format.K_CK2) then seen = true end
		end
	end
end
check(seen, "a key with its velocity on clock 1 (flag 2048)")

section("a part's first change: its start state goes into the full snapshot logged before")
while frameN < 205 do M.step(1 / 60) end
local morphId = E.co.reg.reg.keyToId["ClientObjects/Morph"]
check(morphId ~= nil, "the morph has an id")
local r1b = records(1)
local start = nil
for _, it in ipairs(r1b.items) do if it.id == morphId then start = it end end
check(start ~= nil, "frame 1 now has the morph's start record")
check(start and Format.has(start.flags, Format.K_ROT) and start.key and math.abs(start.key.y - 3) < 0.01, "a whole pose at its start (y 3)")
local delta = nil
for i = 2, tl:count() do
	local r = records(i)
	if r then for _, it in ipairs(r.items) do if it.id == morphId and it.flags and Format.has(it.flags, Format.K_KEY) then delta = delta or it end end end
end
check(delta and not Format.has(delta.flags, Format.K_ROT), "the change is a move from the start state (no rotation in it)")

section("full snapshots every 10 s of TAS time")
for _ = 1, 620 do M.step(1 / 60) end
local fulls = 0
for i = 2, tl:count() do
	local r = records(i)
	if r and r.byte % 8 == 5 then fulls = fulls + 1; check(r.byte < 64, "not a new chain") end
end
check(fulls >= 1, "a full snapshot after 10 s")

section("cut frames: the next recording starts new clocks")
click()
M.steps(3)
key(Enum.KeyCode.F)
M.steps(2)
key(Enum.KeyCode.F)
M.steps(2)
local at = E.frame
click()
M.steps(3)
local r = records(at + 1)
check(r ~= nil and r.byte % 8 == 5 and r.byte >= 64, "the first frame after the cut is a full snapshot with + 64")
click()
M.steps(3)

section("skipSim (Frame Step's held steps)")
local before = E.co.rec.base.skip
E.co:skipSim(0.5)
near(E.co.rec.base.skip - before, 0.5, 1e-9, "the simulation clock skips the held time")

section("disable")
E.modes:request("idle")
M.steps(2)
E.settings:set("syncClientObjects", 0)
M.steps(2)
eq(E.co:isReady(), false, "off")
conn:Disconnect()
folder:Destroy()
finish()
