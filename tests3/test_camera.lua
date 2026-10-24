-- ================================================================================================
-- HappaTAS 3, phase 2: the camera plugin (recorded camera, zoom, shift lock; the camera held while paused,
-- Look Around, Test's scriptable camera, the mouse rules)
-- ================================================================================================
-- a shift lock controller the camera script finds in the garbage collector
local mlc = { isMouseLocked = false }
function mlc:GetIsMouseLocked() return self.isMouseLocked end
function mlc:OnMouseLockToggled() self.isMouseLocked = not self.isMouseLocked end
M.gcTables = { { activeMouseLockController = mlc }, mlc }

check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local UIS = M.services.UserInputService
local tl, cam = E.tl, workspace.CurrentCamera
local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
local function click()
	UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	UIS.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
local function camAt(i)
	local c = { tl:getN("CamCframe", i) }
	return CFrame.new(table.unpack(c))
end

section("recording: the camera, zoom and shift lock of each frame")
key(Enum.KeyCode.Two)
M.steps(2)
click()
local yaw = 0
for f = 1, 12 do
	local hrp = E.char.hrp
	yaw = yaw + 0.05
	cam.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 4, 12.3456)
	if f == 6 then mlc.isMouseLocked = true end
	M.step(1 / 60)
end
local n = tl:count()
check(n >= 10, "frames recorded")
local x = tl:get("CamCframe", n, 1)
eq(x, math.round(x * 1000) / 1000, "camera position at 1/1000")
eq(tl:get("Zoom", n, 1), math.round(E.cs:getZoom() * 1000) / 1000, "zoom = the camera script's, at 1/1000")
eq(tl:get("ShiftLock", 1, 1), 0, "shift lock off on the first frame")
eq(tl:get("ShiftLock", n, 1), 1, "on after it was locked")

section("paused (Lock Camera (Paused)): the camera stays on the frame")
click()
M.step(1 / 60)
local want = camAt(tl:count())
-- (the game writes the camera after HappaTAS each frame; what a frame draws is seen in PreSimulation)
local seen
local conn = M.services.RunService.Heartbeat:Connect(function() cam.CFrame = CFrame.new(100, 100, 100) end)
local probe = M.services.RunService.PreSimulation:Connect(function() seen = cam.CFrame end)
M.steps(3)
check((seen.Position - want.Position).Magnitude < 1e-6, "a game write to the camera is undone every frame")
eq(mlc.isMouseLocked, true, "shift lock as on the frame")

section("Look Around frees the camera")
key(Enum.KeyCode.L)
M.steps(2)
check((seen.Position - Vector3.new(100, 100, 100)).Magnitude < 1e-6, "the game's camera stays")
key(Enum.KeyCode.L)
M.steps(2)
check((seen.Position - want.Position).Magnitude < 1e-6, "held again")
conn:Disconnect()
probe:Disconnect()

section("mouse: locked on a shift-locked frame, free on a normal one")
M.steps(2)
eq(UIS.MouseBehavior, Enum.MouseBehavior.LockCenter, "shift-locked frame: LockCenter")
key(Enum.KeyCode.F); key(Enum.KeyCode.F); key(Enum.KeyCode.F); key(Enum.KeyCode.F); key(Enum.KeyCode.F); key(Enum.KeyCode.F); key(Enum.KeyCode.F); key(Enum.KeyCode.F)
M.steps(2)
eq(tl:get("ShiftLock", E.frame, 1), 0, "(on an unlocked frame)")
eq(mlc.isMouseLocked, false, "shift lock follows the frame")
eq(UIS.MouseBehavior, Enum.MouseBehavior.Default, "free mouse while paused")
check(E.cs:isMouseFree(), "the camera script knows")
tl:set("Zoom", E.frame, 1, 0.5)
M.steps(2)
eq(UIS.MouseBehavior, Enum.MouseBehavior.LockCenter, "first-person zoom (0.55 or less): locked")

section("Test: a scriptable camera, handed back at the end")
key(Enum.KeyCode.Three)
M.step(1 / 60)
eq(cam.CameraType, Enum.CameraType.Scriptable, "Scriptable while testing")
eq(UIS.MouseBehavior, Enum.MouseBehavior.Default, "free mouse in Test")
local g = 0
while E.mode == 3 and g < 300 do M.step(1 / 60); g = g + 1 end
eq(E.mode, 1, "Test ended")
eq(cam.CameraType, Enum.CameraType.Custom, "Custom again")
E.settings:set("lockCameraTest", 0)
key(Enum.KeyCode.Three)
M.step(1 / 60)
eq(cam.CameraType, Enum.CameraType.Custom, "Lock Camera (Test) off: the game's camera")
key(Enum.KeyCode.One)
finish()
