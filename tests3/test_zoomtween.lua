-- ================================================================================================
-- HappaTAS 3: the zoom tween goes on through a pause (Create: scroll, pause half way, unpause)
-- The game's ZoomController keeps its spring (distance x, speed v, goal) in an upvalue of Update, like
-- Roblox's PlayerModule (live, EToH kit: upvalue 1 = { x, v, goal, freq 4.5, minValue, maxValue }).
-- Before: an unpause landed on the goal at once (the tween was cut).
-- ================================================================================================
local spring = { x = 12.5, v = 0, goal = 12.5, freq = 4.5, minValue = 0.5, maxValue = 128 }
-- (Roblox's ConstrainedSpring:Step, critically damped)
local function stepSpring(s, dt)
	local f = s.freq * 2 * math.pi
	local offset = s.goal - s.x
	local st = f * dt
	local decay = math.exp(-st)
	local x1 = s.goal + (s.v * dt - offset * (st + 1)) * decay
	local v1 = ((offset * f - s.v) * st + s.v) * decay
	s.x, s.v = math.clamp(x1, s.minValue, s.maxValue), v1
	return s.x
end
local ZoomController = {}
function ZoomController.Update(dt) return stepSpring(spring, dt) end
function ZoomController.SetZoomParameters(target) spring.goal = target end
-- (the executor's upvalue reader: Real / sUNC debug.getupvalues; the mock's debug table is read-only)
local upvals = { [ZoomController.Update] = { spring, 0, 0.5, 128 } }
getupvalues = function(f) return upvals[f] or {} end

local camCtrl = { currentSubjectDistance = 12.5, inFirstPerson = false }
function camCtrl:GetCameraToSubjectDistance() return self.currentSubjectDistance end
function camCtrl:SetCameraToSubjectDistance(d) self.currentSubjectDistance = d end
local mlc = { isMouseLocked = false }
function mlc:GetIsMouseLocked() return self.isMouseLocked end
function mlc:OnMouseLockToggled() self.isMouseLocked = not self.isMouseLocked end
local cams = { activeCameraController = camCtrl, activeMouseLockController = mlc }
M.gcTables = { cams, mlc }
do
	local pm = Instance.new("ModuleScript"); pm.Name = "PlayerModule"; pm.Parent = M.player:FindFirstChild("PlayerScripts")
	local cm = Instance.new("ModuleScript"); cm.Name = "CameraModule"; cm.Parent = pm
	local zc = Instance.new("ModuleScript"); zc.Name = "ZoomController"; zc.Parent = cm
	local mods = { [pm] = { GetCameras = function() return cams end }, [zc] = ZoomController }
	local realRequire = require
	require = function(x)
		if mods[x] then return mods[x] end
		return realRequire(x)
	end
end

check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
-- (the camera script is looked at once a second of os.clock: step until its zoom update is patched)
local origUpdate = ZoomController.Update
guard = 0
local function hooked() return ZoomController.Update ~= origUpdate or M.hooks[origUpdate] ~= nil end
while not hooked() and guard < 300 do M.step(1 / 60); guard = guard + 1 end
check(hooked(), "the zoom update is patched")
local UIS = M.services.UserInputService
local RS = M.services.RunService
local tl, cam = E.tl, workspace.CurrentCamera
local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
local function click()
	UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	UIS.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
-- the game's camera: each frame the zoom spring steps (through the patched Update) and the camera sits at its
-- distance behind the head (HappaTAS poses it itself while paused)
local camConn = RS.RenderStepped:Connect(function(dt)
	local x = M.callHooked(ZoomController.Update, dt)
	if E.mode == 2 and E.paused then return end
	local head = E.char.model and E.char.model:FindFirstChild("Head")
	if head then cam.CFrame = CFrame.new(head.Position) * CFrame.new(0, 0, x) end
end)
local function scroll(to)
	camCtrl:SetCameraToSubjectDistance(to)
	ZoomController.SetZoomParameters(to, 1)
end
local staticCalls = {}
local origSetZoom = E.cs.setZoom
E.cs.setZoom = function(selfCs, z, static)
	if static then staticCalls[#staticCalls + 1] = z end
	return origSetZoom(selfCs, z, static)
end

section("recording: the spring's distance and speed are kept with each frame (memory only)")
key(Enum.KeyCode.Two)
M.steps(2)
click() -- (recording)
M.steps(3)
scroll(20)
M.steps(4)
local n = tl:count()
local sx, sv = tl:getN("ZoomSpring", n)
check(sx and sx > 12.5 and sx < 20, "the last frame has the spring half way (" .. tostring(sx) .. ")")
check(sv and sv > 0, "and its speed (" .. tostring(sv) .. ")")
eq(tl:get("Zoom", n, 1), 20, "Zoom is still the goal")

section("pause half way, unpause: the tween goes on from where it was")
click() -- (pause)
M.steps(10)
local nP = tl:count()
local px, pv = tl:getN("ZoomSpring", nP)
click() -- (unpause)
staticCalls = {}
M.step(1 / 60)
local want = { x = px, v = pv, goal = 20, freq = 4.5, minValue = 0.5, maxValue = 128 }
stepSpring(want, 1 / 60)
check(spring.x < 19.9, "the camera did not land on the goal at once (" .. spring.x .. ")")
check(math.abs(spring.x - want.x) < 1e-6, "it went on from the paused frame's distance and speed (" .. spring.x .. " vs " .. want.x .. ")")
for _ = 1, 40 do M.step(1 / 60) end
check(math.abs(spring.x - 20) < 0.05, "and reaches the goal (" .. spring.x .. ")")

section("a tween inward: the unpause guard lets it come in (only pulls past the goal count)")
M.steps(5)
scroll(8)
M.steps(4)
click() -- (pause)
M.steps(5)
click() -- (unpause)
staticCalls = {}
for _ = 1, 12 do M.step(1 / 60) end
eq(#staticCalls, 0, "no zoom set at once while the tween comes in")
check(spring.x < 8.5, "it came in to the goal (" .. spring.x .. ")")

section("a tween into first person, pause, unpause: it goes on, no snap (V3.1)")
M.steps(20)
scroll(0.5)
M.steps(3)
click() -- (pause)
M.steps(5)
local nF = tl:count()
local fx, fv = tl:getN("ZoomSpring", nF)
check(fx > 1, "paused part way in (" .. tostring(fx) .. ")")
click() -- (unpause)
staticCalls = {}
M.step(1 / 60)
local wantF = { x = fx, v = fv, goal = 0.5, freq = 4.5, minValue = 0.5, maxValue = 128 }
stepSpring(wantF, 1 / 60)
eq(#staticCalls, 0, "no zoom set at once")
check(math.abs(spring.x - wantF.x) < 1e-6, "it went on from the paused frame's distance (" .. spring.x .. " vs " .. wantF.x .. ")")
eq(camCtrl.inFirstPerson, true, "and the camera is in first person, as recorded")
for _ = 1, 60 do M.step(1 / 60) end
check(spring.x < 0.6, "it reaches first person (" .. spring.x .. ")")
scroll(12.5)
camCtrl.inFirstPerson = false
M.steps(60)

section("a frame without a kept spring (e.g. loaded from a file): the zoom lands at once, as before")
scroll(15)
M.steps(4)
click() -- (pause)
M.steps(3)
tl:setN("ZoomSpring", tl:count(), 0, 0)
click() -- (unpause)
M.step(1 / 60)
check(math.abs(spring.x - 15) < 1e-6, "landed on the goal (" .. spring.x .. ")")

camConn:Disconnect()
E.cs.setZoom = origSetZoom
click()
M.steps(2)
key(Enum.KeyCode.One)
finish()
