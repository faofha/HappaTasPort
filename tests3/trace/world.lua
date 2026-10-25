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

finish()
