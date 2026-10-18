-- Bugs found by testing in the live Roblox client (V2.37.2), reproduced in the mock:
--   * the game's camera module is only ever called from a thread of its own (in the client, calling
--     UpdateMouseBehavior / SetCameraToSubjectDistance / the mouse lock toggle took the calling thread's
--     access to CoreGui away until it yielded: the stats panels, the fake cursor and Unload broke)
--   * interfaces an older copy left behind are removed when the script starts
--   * HappaTAS's ScreenGuis don't go through Roblox's automatic translation (AutoLocalize)
--   * a part HappaTAS holds during playback that a game script lets go (the EToH kit's DistanceCulling
--     un-anchors its PrimaryPart every 0.2 s) is anchored again and put back on its recorded pose
--   * an error inside a frame handler is printed once, not only in debug builds
--   * rebinding a control: the key press that sets the new key doesn't also run the control's old action
--   * a key the replay pressed itself comes back as input: it plays no live key sound
--   * the default click sound is a real sound (the old asset id was a Place: Roblox printed load errors)

-- ------------------------------------------------------------------------------------------- before boot
-- a PlayerModule with a camera controller and a mouse lock controller that log the thread they run on
local callLog = {}
local ctrl = { dist = 12.5, inFirstPerson = false }
function ctrl:GetCameraToSubjectDistance() return self.dist end
function ctrl:SetCameraToSubjectDistance(d)
	callLog[#callLog + 1] = { "zoom", coroutine.running() }
	self.dist = d
	return d
end
function ctrl:UpdateMouseBehavior() callLog[#callLog + 1] = { "mouse", coroutine.running() } end
local mlc = { isMouseLocked = false }
function mlc:GetIsMouseLocked() return self.isMouseLocked end
function mlc:OnMouseLockToggled()
	callLog[#callLog + 1] = { "shift", coroutine.running() }
	self.isMouseLocked = not self.isMouseLocked
end
local cams = { activeCameraController = ctrl, activeMouseLockController = mlc }
local pmInst = Instance.new("ModuleScript")
pmInst.Name = "PlayerModule"
pmInst.Parent = M.player:FindFirstChild("PlayerScripts")
local modules = { [pmInst] = { GetCameras = function() return cams end } }
-- (V2.38.13) a ZoomController module (Bridge.RemoveZoomSpring runs its Update: in the client that takes the
-- access away too) and the mouse lock offset getter (also takes it away in the client)
local camModInst = Instance.new("ModuleScript")
camModInst.Name = "CameraModule"
camModInst.Parent = pmInst
local zoomInst = Instance.new("ModuleScript")
zoomInst.Name = "ZoomController"
zoomInst.Parent = camModInst
local zoomMod = {}
function zoomMod.Update() callLog[#callLog + 1] = { "zoomUpdate", coroutine.running() }; return 12.5 end
function zoomMod.SetZoomParameters() end
modules[zoomInst] = zoomMod
function mlc:GetMouseLockOffset() callLog[#callLog + 1] = { "lockOffset", coroutine.running() }; return Vector3.new(1.75, 0, 0) end
local realRequire = require
require = function(x)
	local m = modules[x]
	if m then return m end
	if typeof(x) == "Instance" then error("mock: no module " .. tostring(x)) end
	return realRequire(x)
end

-- interfaces an older copy could not remove
local hui = gethui()
local stale = {}
for _, spec in ipairs({ { "TASUserInterface", hui }, { "HappaProfiler", hui }, { "HappaCursor", M.services.CoreGui } }) do
	local sg = Instance.new("ScreenGui")
	sg.Name = spec[1]
	sg.Parent = spec[2]
	stale[#stale + 1] = sg
end
local other = Instance.new("ScreenGui")
other.Name = "SomeOtherGui"
other.Parent = hui

check(boot(30), "boots")
local S, Core, CO, Bridge = __T.Settings, __T.Core, __T.ClientObjects, __T.Bridge
local C = Core.State
local guard = 0
while not (C.HRP and C.Humanoid) and guard < 200 do M.step(1 / 60); guard = guard + 1 end
M.steps(90) -- (the bridge looks for the PlayerModule every 0.5 s)

section("stale interfaces are removed, others are kept")
for _, sg in ipairs(stale) do eq(sg.Parent, nil, "old " .. tostring(sg.Name) .. " removed") end
eq(other.Parent, hui, "a ScreenGui with another name is kept")
local n = 0
for _, ch in ipairs(hui:GetChildren()) do if ch.Name == "TASUserInterface" then n = n + 1 end end
eq(n, 1, "one interface under gethui()")
eq(__T.UI.ParentName, "gethui", "the interface is under gethui()")

section("no automatic translation")
eq(C.Gui.AutoLocalize, false, "main interface: AutoLocalize off")
local ov = __T.UI.Overlay("TestOverlay", 5)
check(ov ~= nil, "overlay created")
if ov then eq(ov.AutoLocalize, false, "overlay (profiler / cursor): AutoLocalize off"); ov:Destroy() end
S.Set("Show MicroProfiler", 1)
M.steps(3)
local prof = M.services.CoreGui:FindFirstChild("HappaProfiler")
check(prof ~= nil and prof.AutoLocalize == false, "MicroProfiler overlay (in CoreGui, above the top bar): AutoLocalize off")
S.Set("Show MicroProfiler", 0)

section("default sounds are sound assets")
-- (checked in the live client with MarketplaceService:GetProductInfo: 9119713951 = audio "Switch 2 (SFX)",
-- 9119714049 = a Place; rbxasset://sounds/clickfast.wav loads, 0.288 s, it ships with the client)
local soundFolder = C.Gui:FindFirstChild("Sounds")
check(soundFolder ~= nil, "the sound pool exists")
if soundFolder then
	local keys, clicks, bad = 0, 0, 0
	for _, s in ipairs(soundFolder:GetChildren()) do
		if s.SoundId == "rbxassetid://9119714049" then bad = bad + 1 end
		if s.Name:sub(1, 1) == "K" and s.SoundId == "rbxassetid://9119713951" then keys = keys + 1 end
		if s.Name:sub(1, 1) == "C" and s.SoundId == "rbxasset://sounds/clickfast.wav" then clicks = clicks + 1 end
	end
	eq(keys, 6, "6 key sounds: Switch 2 (SFX)")
	eq(clicks, 6, "6 click sounds: the client's clickfast.wav")
	eq(bad, 0, "no sound uses the old id (a Place)")
end

section("the camera module runs in a thread of its own")
check(Bridge.Controller() == ctrl, "the bridge found the mock camera controller")
callLog = {}
local caller, zoomAfter, lockedAfter
local co = coroutine.create(function()
	caller = coroutine.running()
	Bridge.SetZoom(20, true)
	zoomAfter = ctrl.dist
	Bridge.RefreshMouse(false)
	Bridge.ShiftlockSwitch()
	lockedAfter = mlc.isMouseLocked
end)
local okCo, errCo = coroutine.resume(co)
check(okCo, "bridge calls ran (" .. tostring(errCo) .. ")")
eq(zoomAfter, 20, "SetZoom changed the zoom before it returned (same order of events)")
eq(lockedAfter, true, "ShiftlockSwitch toggled shift lock before it returned")
local kinds, sameThread = {}, 0
for _, e in ipairs(callLog) do
	kinds[e[1]] = true
	if e[2] == caller then sameThread = sameThread + 1 end
end
check(kinds.zoom and kinds.mouse and kinds.shift, "zoom, mouse lock refresh and shift lock toggle were called")
check(kinds.zoomUpdate and kinds.lockOffset, "the zoom spring update and the mouse lock offset getter were called")
eq(sameThread, 0, "none of them ran on the caller's thread")
Bridge.ShiftlockSwitch()
Bridge.SetZoom(12.5, true)

section("frame handler errors are printed once")
local realUpdate = __T.Cursor.Update
__T.Cursor.Update = function() error("cursor test failure") end
M.steps(20)
__T.Cursor.Update = realUpdate
local hits = 0
for i, l in ipairs(M.logs) do
	if l:find("cursor test failure", 1, true) then
		hits = hits + 1
		check(l:find("[HappaTAS]", 1, true) ~= nil and l:find("render step", 1, true) ~= nil, "it says HappaTAS and where")
		M.logs[i] = "(expected test error removed)"
	end
end
eq(hits, 1, "20 frames with the same error print it once")

section("rebinding a control: the new key doesn't also run its old control")
for _, reverse in ipairs({ false, true }) do
	M.reverseSignals = reverse
	if reverse then section("(the same with the InputBegan handlers in the other order)") end
	local Controls = __T.Controls
	local row = C.Gui.MainMenu.ControlsFrame.List:FindFirstChild("Back")
	check(row ~= nil, "the Back row exists")
	if row then
		eq(Core.GetMode(), 1, "idle before")
		row.Key.MouseButton1Down:Fire()
		M.steps(2)
		eq(row.Key.Text, "Press Any Key", "waiting for a key")
		M.pressKey(Enum.KeyCode.Two); M.releaseKey(Enum.KeyCode.Two); M.steps(2)
		eq(Controls.Get("Back"), "2", "Back is bound to 2")
		eq(Core.GetMode(), 1, "2 (Create) did not switch to Create while it was being bound")
		M.pressKey(Enum.KeyCode.One); M.releaseKey(Enum.KeyCode.One); M.steps(2)
		eq(Controls.Get("Back"), "2", "the next key is a control again (not a new binding)")
		row.Key.MouseButton1Down:Fire()
		M.steps(2)
		M.pressKey(Enum.KeyCode.R); M.releaseKey(Enum.KeyCode.R); M.steps(2)
		eq(Controls.Get("Back"), "R", "bound back to R")
	end
	M.reverseSignals = false
end

section("a key the replay pressed itself doesn't play a live key sound")
do
	S.Set("Enable Keyboard Sounds", 1)
	S.Set("Replay Keyboard", 1)
	local function key(kc) M.pressKey(kc); M.releaseKey(kc); M.steps(2) end
	local function click()
		M.services.UserInputService.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
		M.services.UserInputService.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
		M.steps(2)
	end
	Core.SetTAS({})
	key(Enum.KeyCode.Two)
	click() -- record
	M.steps(5)
	S.Set("Sound Trigger Mode", 0)
	M.soundPlays = 0
	M.pressKey(Enum.KeyCode.W); M.steps(10); M.releaseKey(Enum.KeyCode.W); M.steps(10)
	eq(M.soundPlays, 1, "a real key press while recording plays one sound (mode 0)")
	click() -- pause
	for _, mode in ipairs({ 0, 2 }) do
		S.Set("Sound Trigger Mode", mode)
		M.inputLog = {}
		key(Enum.KeyCode.Three) -- test
		local sent, g = false, 0
		while not sent and g < 120 and C.mode == 3 do
			M.step(1 / 60); g = g + 1
			for _, e in ipairs(M.inputLog) do if e[1] == "keypress" and e[2] == 0x57 then sent = true end end
		end
		check(sent, "the replay pressed W (mode " .. mode .. ")")
		M.soundPlays = 0
		M.pressKey(Enum.KeyCode.W); M.steps(2) -- the injected press comes back as input (like Roblox)
		eq(M.soundPlays, 0, "it plays no live sound (mode " .. mode .. ")")
		local g2 = 0
		while C.mode == 3 and g2 < 300 do M.step(1 / 60); g2 = g2 + 1 end
		M.releaseKey(Enum.KeyCode.W); M.steps(2)
		key(Enum.KeyCode.Two) -- back to Create (paused) for the next round
	end
	key(Enum.KeyCode.One)
	S.Set("Sound Trigger Mode", 0)
end

section("a held part that a game script lets go is held again, on its recorded pose")
S.Set("Sync Client Objects", 1)
local folder = Instance.new("Folder")
folder.Name = "ClientObjects"
folder.Parent = workspace
local loose = Instance.new("Part") -- unanchored: HappaTAS anchors it while playing
loose.Name = "Loose"
loose.Size = Vector3.new(4, 1, 4)
loose.Anchored = false
loose.CFrame = CFrame.new(0, 3, -10)
loose.Parent = folder
local still = Instance.new("Part") -- unanchored, never moves: no records, frozen while paused / testing
still.Name = "Still"
still.Size = Vector3.new(4, 1, 4)
still.Anchored = false
still.CFrame = CFrame.new(-8, 3, -10)
still.Parent = folder
local mover = Instance.new("Part") -- anchored by the game, moved by a script
mover.Name = "Moving Platform"
mover.Size = Vector3.new(4, 1, 4)
mover.Anchored = true
mover.CFrame = CFrame.new(8, 3, -10)
mover.Parent = folder
local recFrame = 0
local driver = M.services.RunService.Heartbeat:Connect(function()
	if not (C.mode == 2 and not C.paused) then return end
	recFrame = recFrame + 1
	if recFrame <= 30 then
		loose.CFrame = loose.CFrame + Vector3.new(0.1, 0, 0)
		mover.CFrame = mover.CFrame + Vector3.new(0, 0, -0.1)
	end
end)
local g = 0
while not CO.IsReady() and g < 600 do M.step(1 / 60); g = g + 1 end
check(CO.IsReady(), "client objects ready")
local function key(kc) M.pressKey(kc); M.releaseKey(kc); M.steps(2) end
local function click()
	M.services.UserInputService.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	M.services.UserInputService.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
	M.steps(2)
end
key(Enum.KeyCode.Two)
click() -- unpause: record
M.steps(60) -- moves for 30 frames, then still
click() -- pause
eq(C.paused, true, "paused after recording")
check(#C.data > 50, "recorded frames (" .. #C.data .. ")")
driver:Disconnect()
key(Enum.KeyCode.Three)
eq(C.mode, 3, "testing")
M.steps(50) -- the parts are still in the recording here
local idLoose = CO.Reg.keyToId["ClientObjects/Loose"]
local idMover = CO.Reg.keyToId["ClientObjects/Moving Platform"]
check(idLoose ~= nil and idMover ~= nil, "both parts registered")
eq(loose.Anchored, true, "HappaTAS holds the loose part while testing")
local want = CO.shown[idLoose] and CO.shown[idLoose].cf
check(want ~= nil, "the loose part has a pose")
-- the game lets go of the loose part and physics moves it
loose.Anchored = false
loose.CFrame = loose.CFrame + Vector3.new(0, 5, 0)
-- and of the part that never moved (not recorded, held since the pause froze it)
local stillHeld = still.Anchored
still.Anchored = false
still.CFrame = still.CFrame + Vector3.new(0, 7, 0)
-- the game lets go of the scripted mover too (it is now held by HappaTAS) and it falls
mover.Anchored = false
mover.CFrame = mover.CFrame + Vector3.new(0, -5, 0)
M.steps(2)
if C.mode == 3 and want then
	eq(loose.Anchored, true, "the loose part is anchored again")
	near((loose.Position - CO.shown[idLoose].cf.Position).Magnitude, 0, 1e-3, "and back on its recorded pose")
	near(loose.Position.Y, want.Position.Y, 1e-3, "(not where the game moved it)")
	eq(stillHeld, true, "the part that never moved is held while testing")
	eq(still.Anchored, true, "after the game let go of it, it is anchored again")
	near(still.Position.Y, 3, 1e-3, "on the pose it had (no recorded pose: where HappaTAS took it)")
	eq(mover.Anchored, true, "the mover the game let go is anchored by HappaTAS")
	near((mover.Position - CO.shown[idMover].cf.Position).Magnitude, 0, 1e-3, "and on its recorded pose")
	check(math.abs(mover.Position.Y - 3) < 1e-3, "(not where the game moved it)")
else
	check(false, "still testing when the game let go of the parts")
end
local g2 = 0
while C.mode == 3 and g2 < 600 do M.step(1 / 60); g2 = g2 + 1 end
eq(C.mode, 1, "the test finished")
eq(loose.Anchored, false, "after the test the loose part is free again")

finish()
