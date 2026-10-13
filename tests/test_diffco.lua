-- Differential trace for client object edge cases (run with tools/diff_builds.sh, TEST=diffco):
-- props changing on odd / even frames, a platform that gets unanchored while recording, parts that
-- are destroyed / added / re-parented while recording and testing, Sync Client Objects off and on.
M.clockStep = 0
check(boot(30), "boots")
local S, Core, CO = __T.Settings, __T.Core, __T.ClientObjects
local C = Core.State
local guard = 0
while not (C.HRP and C.Humanoid) and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local hrp = C.HRP
local cam = workspace.CurrentCamera

local function T(...)
	local t = { ... }
	for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
	M.realPrint("T|" .. table.concat(t, "|"))
end
local function num(v) return string.format("%.5f", v) end
local function cfs(cf)
	local c = { cf:GetComponents() }
	for i = 1, 12 do c[i] = num(c[i]) end
	return table.concat(c, ",")
end
local function hex(str)
	if type(str) ~= "string" then return tostring(str) end
	return (str:gsub(".", function(ch) return string.format("%02x", string.byte(ch)) end))
end

local folder = Instance.new("Folder")
folder.Name = "ClientObjects"
folder.Parent = workspace
local objs = {}
local function mk(i, anchored)
	local p = Instance.new("Part")
	p.Name = "P" .. i
	p.Size = Vector3.new(4, 1, 4)
	p.CFrame = CFrame.new((i % 5) * 6 - 12, 3, -6 - math.floor(i / 5) * 5)
	p.Anchored = anchored
	p.Parent = folder
	return p
end
for i = 1, 15 do objs[i] = mk(i, true) end
local frameN = 0
local late = nil
local conn = M.services.RunService.Heartbeat:Connect(function(dt)
	if C.mode == 3 or (C.mode == 2 and C.paused) then return end
	frameN = frameN + 1
	local f = frameN
	-- 1: colour changes on odd frames, 2: transparency on even frames, 3: size every 3rd frame
	if objs[1] and objs[1].Parent then objs[1].Color = Color3.fromRGB((f * 7) % 256, 10, 10) end
	if f % 2 == 0 and objs[2] and objs[2].Parent then objs[2].Transparency = (f % 8) / 8 end
	if f % 3 == 0 and objs[3] and objs[3].Parent then objs[3].Size = Vector3.new(4, 1 + (f % 4), 4) end
	-- 4: slides, 5: turns
	if objs[4] and objs[4].Parent then objs[4].CFrame = CFrame.new(-6 + math.sin(f / 10) * 3, 3, -6) end
	if objs[5] and objs[5].Parent then objs[5].CFrame = CFrame.new(12, 3, -6) * CFrame.Angles(0, f / 20, 0) end
	-- 6: a falling platform: unanchored at frame 40, falls
	if f == 40 and objs[6] then objs[6].Anchored = false end
	if objs[6] and not objs[6].Anchored then
		objs[6].AssemblyLinearVelocity = Vector3.new(0, -5, 0)
		objs[6].CFrame = objs[6].CFrame + Vector3.new(0, -5 * dt, 0)
	end
	-- 7: destroyed at frame 60, 8: re-parented into a sub folder at frame 70
	if f == 60 and objs[7] then objs[7]:Destroy(); objs[7] = nil end
	if f == 70 and objs[8] then
		local sub = Instance.new("Folder"); sub.Name = "Moving Platforms"; sub.Parent = folder
		objs[8].Parent = sub
	end
	if objs[8] and objs[8].Parent then objs[8].CFrame = objs[8].CFrame + Vector3.new(0, 0, 0.05) end
	-- a part added at frame 80 that moves
	if f == 80 then late = mk(99, true) end
	if late and late.Parent then late.CFrame = late.CFrame + Vector3.new(0.1, 0, 0) end
	-- 9: material + can-collide flip at frame 90
	if f == 90 and objs[9] then objs[9].Material = Enum.Material.Neon; objs[9].CanCollide = false end
end)

S.Set("Sync Client Objects", 1)
local g = 0
while not CO.IsReady() and g < 600 do M.step(1 / 60); g = g + 1 end
check(CO.IsReady(), "ready")
local reg = CO.Counts()
T("registered", reg)

local function click()
	M.services.UserInputService.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	M.services.UserInputService.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
local function world(tag)
	local t = {}
	for i = 1, 15 do
		local p = objs[i]
		if p and p.Parent then t[#t + 1] = i .. ":" .. cfs(p.CFrame) .. ":" .. num(p.Transparency) .. ":" .. tostring(p.Color) .. ":" .. tostring(p.Size) .. ":" .. tostring(p.Anchored) .. ":" .. tostring(p.CanCollide) .. ":" .. tostring(p.Material) end
	end
	if late and late.Parent then t[#t + 1] = "late:" .. cfs(late.CFrame) .. ":" .. tostring(late.Anchored) end
	T("W", tag, C.mode, C.frame, table.concat(t, ";"))
end

key(Enum.KeyCode.Two)
M.steps(3)
click()
M.steps(2)
for i = 1, 130 do
	hrp.AssemblyLinearVelocity = Vector3.new(1, 0, 0)
	M.step(1 / 60)
	if i % 5 == 0 then world("rec" .. i) end
end
click()
M.steps(3)
local data = Core.GetTAS()
for i, fr in ipairs(data) do if fr.CO then T("CO", i, hex(fr.CO)) end end
T("frames", #data)
-- scrub back while paused, then test
M.pressKey(Enum.KeyCode.R)
for i = 1, 30 do M.step(1 / 60); if i % 3 == 0 then world("back" .. i) end end
M.releaseKey(Enum.KeyCode.R)
M.steps(2)
key(Enum.KeyCode.Three)
M.steps(1)
local n = 0
while C.mode == 3 and n < 400 do
	M.step(1 / 60)
	n = n + 1
	if n % 4 == 0 then world("play" .. n) end
end
T("played", n)
M.steps(3)
world("idle")
-- off and on again, record a little more after loading the saved file
S.Set("Sync Client Objects", 0)
M.steps(3)
world("off")
S.Set("Sync Client Objects", 1)
local g2 = 0
while not CO.IsReady() and g2 < 600 do M.step(1 / 60); g2 = g2 + 1 end
T("registered2", (CO.Counts()))
local okS = __T.Store.SaveSlot("co", Core.GetTAS())
local okL, loaded = __T.Store.LoadSlot("co")
T("saveload", tostring(okS), tostring(okL), okL and #loaded or -1)
if okL then Core.SetTAS(loaded) end
key(Enum.KeyCode.Three)
M.steps(1)
local n2 = 0
while C.mode == 3 and n2 < 400 do
	M.step(1 / 60)
	n2 = n2 + 1
	if n2 % 6 == 0 then world("play2-" .. n2) end
end
T("played2", n2)
conn:Disconnect()
finish()
