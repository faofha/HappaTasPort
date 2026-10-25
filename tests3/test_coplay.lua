-- ================================================================================================
-- HappaTAS 3, phase 4: client object playback (V2.38.17 p13_clientobjects.lua 1196-1798): paused frames,
-- Test, releasing, unpausing with velocities, parts a game script lets go
-- ================================================================================================
M.clockStep = 0
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local tl = E.tl
local hrp = E.char.hrp

local folder = Instance.new("Folder")
folder.Name = "ClientObjects"
folder.Parent = workspace
local function mk(name, cf, anchored)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(4, 1, 4)
	p.CFrame = cf
	p.Anchored = anchored ~= false
	p.Parent = folder
	return p
end
local slider = mk("Slider", CFrame.new(10, 3, -8))
local spinner = mk("Spinner", CFrame.new(0, 3, -8))
local box = mk("Box", CFrame.new(-10, 3, -8), false)
local frameN = 0
local truth = {} -- recorded frame -> { slider, spinner } CFrames once the frame is filled
local conn = M.services.RunService.Heartbeat:Connect(function()
	if E.mode == 3 or (E.mode == 2 and E.paused) then return end
	frameN = frameN + 1
	slider.CFrame = CFrame.new(10 + frameN * 0.05, 3, -8)
	spinner.CFrame = CFrame.new(0, 3, -8) * CFrame.Angles(0, frameN / 40, 0)
end)
local truthConn = M.services.RunService.PreSimulation:Connect(function()
	if E.mode == 2 and not E.paused then
		local n = tl:count()
		if n > 0 then truth[n] = { slider.CFrame, spinner.CFrame } end
	end
end)

E.settings:set("syncClientObjects", 1)
local g = 0
while not E.co:isReady() and g < 600 do M.step(1 / 60); g = g + 1 end
check(E.co:isReady(), "ready")

local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
local function click()
	local UIS = M.services.UserInputService
	UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	UIS.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
local function dist(a, b) return (a.Position - b.Position).Magnitude end
local function angle(a, b)
	local _, ang = (a.Rotation * b.Rotation:Inverse()):ToAxisAngle()
	return math.abs(ang)
end

key(Enum.KeyCode.Two)
M.steps(3)
click()
M.steps(2)
for i = 1, 120 do
	box.AssemblyLinearVelocity = Vector3.new(0, 0, 2)
	box.CFrame = box.CFrame + Vector3.new(0, 0, 2 / 60)
	M.step(1 / 60)
end
click()
M.steps(3)
local n = tl:count()
check(n >= 110, "recorded " .. n .. " frames")

section("paused: the parts are on the frame shown")
key(Enum.KeyCode.F) -- one frame back
M.steps(2)
for _ = 1, 20 do key(Enum.KeyCode.F); M.steps(2) end
local f = E.frame
check(f < n - 10, "went back to frame " .. f)
local tr = truth[f]
check(tr ~= nil, "a truth for frame " .. f)
check(tr and dist(slider.CFrame, tr[1]) < 0.02, "slider on its recorded pose (" .. (tr and dist(slider.CFrame, tr[1]) or -1) .. ")")
check(tr and angle(spinner.CFrame, tr[2]) < 0.01, "spinner turned as recorded")
eq(slider.Anchored, true, "held while paused")
eq(box.Anchored, true, "the physics box is held too")

section("a held part a game script lets go is anchored again")
box.Anchored = false
M.steps(2)
eq(box.Anchored, true, "anchored again")

section("unpausing here: parts back with their recorded velocity, then let go")
click()
M.steps(1)
eq(box.Anchored, false, "the box is free again")
check(math.abs(box.AssemblyLinearVelocity.Z - 2) < 0.05, "with its recorded velocity (" .. box.AssemblyLinearVelocity.Z .. ")")
M.steps(20)
click()
M.steps(3)

section("Test: the parts follow the recording")
local worst, checked = 0, 0
key(Enum.KeyCode.Three)
M.steps(1)
local guardT = 0
while E.mode == 3 and guardT < 400 do
	M.step(1 / 60)
	guardT = guardT + 1
	local fr = E.frame
	local t = truth[fr]
	if t and fr > 2 and fr < tl:count() - 1 then
		-- (the pose is between frame fr and fr + 1: compare with the nearer of the two)
		local t2 = truth[fr + 1] or t
		local d = math.min(dist(slider.CFrame, t[1]), dist(slider.CFrame, t2[1]))
		if d > worst then worst = d end
		checked = checked + 1
	end
end
check(checked > 50, "checked " .. checked .. " frames")
check(worst < 0.06, "worst slider error " .. worst)
M.steps(3)

section("Idle: every part let go as it was")
eq(E.mode, 1, "idle")
M.steps(2)
eq(slider.Anchored, true, "the slider anchored as before (its own)")
eq(box.Anchored, false, "the box free")
eq(E.co:isHolding(), false, "nothing held")

section("Sync Client Objects off in Test releases at once")
key(Enum.KeyCode.Three)
M.steps(5)
eq(E.mode, 3, "testing")
check(E.co:isHolding(), "holding while testing")
E.settings:set("syncClientObjects", 0)
M.steps(1)
eq(box.Anchored, false, "released")
eq(E.co:isHolding(), false, "nothing held")
E.modes:request("idle")
M.steps(3)
conn:Disconnect()
truthConn:Disconnect()
folder:Destroy()
finish()
