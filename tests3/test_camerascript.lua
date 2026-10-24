-- ================================================================================================
-- HappaTAS 3, phase 2: the game's camera script (zoom, shift lock, mouse lock, ghost, patches)
-- Fixtures from V2.38.16's tests (test_realinput, test_live, test_security): a PlayerModule whose camera
-- script has BaseCamera and ZoomController, controllers in the garbage collector, calls that log their thread.
-- ================================================================================================
local callLog = {}
local ctrlClass = { __index = {
	SetCameraToSubjectDistance = function(self, d) self.currentSubjectDistance = d end,
	GetCameraToSubjectDistance = function(self) return self.currentSubjectDistance end,
} }
local zc1 = setmetatable({ currentSubjectDistance = 12.5 }, ctrlClass)
local zc2 = setmetatable({ currentSubjectDistance = 20 }, ctrlClass)
local camCtrl = { currentSubjectDistance = 12.5, inFirstPerson = false }
function camCtrl:GetCameraToSubjectDistance() return self.currentSubjectDistance end
function camCtrl:SetCameraToSubjectDistance(d)
	callLog[#callLog + 1] = { "zoom", coroutine.running() }
	self.currentSubjectDistance = d
end
function camCtrl:UpdateMouseBehavior() callLog[#callLog + 1] = { "mouse", coroutine.running() } end
local mlc = { isMouseLocked = false }
function mlc:GetIsMouseLocked() return self.isMouseLocked end
function mlc:OnMouseLockToggled()
	callLog[#callLog + 1] = { "shift", coroutine.running() }
	self.isMouseLocked = not self.isMouseLocked
end
function mlc:GetMouseLockOffset() callLog[#callLog + 1] = { "lockOffset", coroutine.running() }; return Vector3.new(1.75, 0, 0) end
local cams = { activeCameraController = camCtrl, activeMouseLockController = mlc }
camsAvailable = true
-- (like the client: the GC scan finds the cameras table before the PlayerModule is looked at)
M.gcTables = { zc1, { currentSubjectDistance = "not a controller" }, zc2, cams, mlc }

local baseCalls = 0
local BaseCamera = {}
function BaseCamera.UpdateMouseBehavior(self) baseCalls = baseCalls + 1 return "base" end
local ZoomController = {}
function ZoomController.Update(dt) callLog[#callLog + 1] = { "zoomUpdate", coroutine.running() }; return dt end
function ZoomController.SetZoomParameters() end
local origUMB, origZU = BaseCamera.UpdateMouseBehavior, ZoomController.Update
do
	local pm = Instance.new("ModuleScript"); pm.Name = "PlayerModule"; pm.Parent = M.player:FindFirstChild("PlayerScripts")
	local cm = Instance.new("ModuleScript"); cm.Name = "CameraModule"; cm.Parent = pm
	local bc = Instance.new("ModuleScript"); bc.Name = "BaseCamera"; bc.Parent = cm
	local zc = Instance.new("ModuleScript"); zc.Name = "ZoomController"; zc.Parent = cm
	local mods = { [pm] = { GetCameras = function() if camsAvailable then return cams end return nil end }, [bc] = BaseCamera, [zc] = ZoomController }
	local realRequire = require
	require = function(x)
		if mods[x] then return mods[x] end
		return realRequire(x)
	end
end

check(boot(3), "boots")
local CameraScript = __T3("platform/camerascript")
local Lifecycle = __T3("kernel/lifecycle")
local Errors = __T3("kernel/errors")
local life = Lifecycle.new("cs")
local printed = {}
local mode = 1
local cs = CameraScript.new(life, Errors.new(function(m) printed[#printed + 1] = m end), { getMode = function() return mode end })
local gc0 = { getgc = M.gcCalls.getgc, filtergc = M.gcCalls.filtergc }
cs:start()
M.steps(90) -- (looks for the PlayerModule every 0.5 s, first after os.clock() reaches 1 s)

section("camera controllers are found with filtergc, not getgc(true)")
check(M.gcCalls.filtergc > gc0.filtergc, "filtergc was used")
eq(M.gcCalls.getgc, gc0.getgc, "getgc was not called")
eq(#cs.zoomControllers, 2, "both zoom controllers found, the other table skipped")
eq(cs.controller(), camCtrl, "the active camera controller")

section("patched even though the GC scan found the cameras first; hookfunction keeps the functions")
eq(BaseCamera.UpdateMouseBehavior, origUMB, "BaseCamera.UpdateMouseBehavior is the same function value")
eq(ZoomController.Update, origZU, "ZoomController.Update too")
check(M.hooks[origUMB] ~= nil and M.hooks[origZU] ~= nil, "both hooked (" .. tostring(M.hooks[origUMB] ~= nil) .. "," .. tostring(M.hooks[origZU] ~= nil) .. ")")
baseCalls = 0
eq(M.callHooked(origUMB, camCtrl), "base", "the hooked function still runs the original")
eq(baseCalls, 1, "once")
eq(M.callHooked(origZU, 0.5), 0.5, "the zoom update passes its value through")
cs.timeRate = 0.5
eq(M.callHooked(origZU, 0.5), 0.25, "slow motion: the zoom spring gets half the frame time")
cs.timeRate = 1

section("game calls run on a thread of their own")
callLog = {}
local caller, zoomAfter, lockedAfter
local co = coroutine.create(function()
	caller = coroutine.running()
	cs:setZoom(20, true)
	zoomAfter = camCtrl.currentSubjectDistance
	cs:refreshMouse(false)
	cs:shiftlockSwitch()
	lockedAfter = mlc.isMouseLocked
end)
local okCo, errCo = coroutine.resume(co)
check(okCo, "calls ran (" .. tostring(errCo) .. ")")
eq(zoomAfter, 20, "setZoom changed the zoom before it returned")
eq(lockedAfter, true, "shiftlockSwitch toggled shift lock before it returned")
local kinds, sameThread = {}, 0
for _, e in ipairs(callLog) do
	kinds[e[1]] = true
	if e[2] == caller then sameThread = sameThread + 1 end
end
check(kinds.zoom and kinds.shift and kinds.lockOffset, "zoom, shift lock toggle and the lock offset getter were called")
eq(sameThread, 0, "none of them ran on the caller's thread")
eq(cs:isShiftlocked(), true, "isShiftlocked reads the controller")
cs:shiftlockSwitch()
eq(cs:getZoom(), 20, "getZoom reads the controller")

section("ghost: the see-through character")
local char = M.player.Character
local head = char:FindFirstChild("Head")
local cam = workspace.CurrentCamera
cam.CFrame = CFrame.new(head.Position + Vector3.new(0, 0, 0.6))
cs:updateGhost(0.5, 1 / 60, true)
eq(head.LocalTransparencyModifier, 1, "close to the head: see-through at once (snap)")
cam.CFrame = CFrame.new(head.Position + Vector3.new(0, 0, 12))
cs:updateGhost(12.5, 1 / 60, false)
near(head.LocalTransparencyModifier, 1 - math.floor(2.8 / 60 * 100 + 0.5) / 100, 0.011, "eases back at 2.8 a second")
cs:resetGhost(false)
eq(head.LocalTransparencyModifier, 0, "reset puts it back")

section("restore: patches undone and never made again")
mode = 1
cs:restore()
check(M.hooks[origUMB] == nil and M.hooks[origZU] == nil, "restorefunction undid both")
cs:refreshMouse(false)
M.steps(80)
check(M.hooks[origUMB] == nil and M.hooks[origZU] == nil, "nothing hooked again after restore")
life:cleanup()

section("cameras not found: patched from the PlayerModule, and not again after restore")
do
	camsAvailable = false
	M.gcTables = {}
	local life3 = Lifecycle.new("cs3")
	local cs3 = CameraScript.new(life3, Errors.new(function() end), {})
	cs3:start()
	M.steps(80)
	check(M.hooks[origUMB] ~= nil, "patched without the cameras table")
	cs3:restore()
	M.steps(80)
	cs3:refreshMouse(false)
	check(M.hooks[origUMB] == nil, "not patched again after restore")
	life3:cleanup()
	camsAvailable = true
end

section("without hookfunction the table field is swapped, and put back")
do
	local Env = __T3("platform/env")
	local hf, rf = Env.hookfunction, Env.restorefunction
	Env.hookfunction, Env.restorefunction = nil, nil
	local life2 = Lifecycle.new("cs2")
	local cs2 = CameraScript.new(life2, Errors.new(function() end), {})
	cs2:start()
	M.steps(80)
	check(BaseCamera.UpdateMouseBehavior ~= origUMB, "the field holds a wrapper")
	life2:cleanup()
	eq(BaseCamera.UpdateMouseBehavior, origUMB, "cleanup puts the original back")
	Env.hookfunction, Env.restorefunction = hf, rf
end
finish()
