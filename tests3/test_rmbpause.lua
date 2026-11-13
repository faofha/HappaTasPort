-- ================================================================================================
-- HappaTAS 3: right (or middle) click held while paused.
-- Found live (EToH kit test place, old camera script): paused with a held camera, HappaTAS frees the mouse
-- (MouseBehavior Default), so with right click held the cursor drifted with the mouse; on unpause the camera
-- script locked it again, Roblox pulled it back to where right click was pressed, and that pull arrived as a mouse
-- move: the camera turned by it on the first frame (0 - 165 degrees, as far as the cursor had drifted), away from
-- the frame's camera. Fix: while the button is held the cursor stays locked where it is (LockCurrentPosition, as
-- Roblox does while the button is held), and unpausing doesn't move it back to the frame's mouse position (a moved
-- locked cursor turns the camera). No mouse input after the unpause is dropped.
-- ================================================================================================
-- a camera script (the game's): its UpdateMouseBehavior runs on its own (on mouse button events)
local ctrlClass = {}
ctrlClass.__index = ctrlClass
local camCtrl = setmetatable({ currentSubjectDistance = 12.5, inFirstPerson = false }, ctrlClass)
function camCtrl:GetCameraToSubjectDistance() return self.currentSubjectDistance end
function camCtrl:SetCameraToSubjectDistance(d) self.currentSubjectDistance = d end
local mlc = { isMouseLocked = false }
function mlc:GetIsMouseLocked() return self.isMouseLocked end
function mlc:OnMouseLockToggled() self.isMouseLocked = not self.isMouseLocked end
function mlc:GetMouseLockOffset() return Vector3.new(1.75, 0, 0) end
local cams = { activeCameraController = camCtrl, activeMouseLockController = mlc }
M.gcTables = { cams, mlc }
local BaseCamera = {}
-- (the game's own rule: right button down = locked where it is, else free)
local gameMouse = true -- (false: the game's camera script leaves the mouse alone)
function BaseCamera.UpdateMouseBehavior()
	if not gameMouse then return end
	local held = M.services.UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
	M.services.UserInputService.MouseBehavior = held and Enum.MouseBehavior.LockCurrentPosition or Enum.MouseBehavior.Default
end
function camCtrl:UpdateMouseBehavior() return M.callHooked(BaseCamera.UpdateMouseBehavior, self) end
do
	local pm = Instance.new("ModuleScript"); pm.Name = "PlayerModule"; pm.Parent = M.player:FindFirstChild("PlayerScripts")
	local cm = Instance.new("ModuleScript"); cm.Name = "CameraModule"; cm.Parent = pm
	local bc = Instance.new("ModuleScript"); bc.Name = "BaseCamera"; bc.Parent = cm
	local mods = { [pm] = { GetCameras = function() return cams end }, [bc] = BaseCamera }
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
-- (the camera script is looked for at most once a second of os.clock)
guard = 0
while M.hooks[BaseCamera.UpdateMouseBehavior] == nil and guard < 3000 do M.step(1 / 60); guard = guard + 1 end
check(M.hooks[BaseCamera.UpdateMouseBehavior] ~= nil, "the game's camera script is patched")
local tl = E.tl
local s = E.settings
local UIS = M.services.UserInputService
local RMB, MMB = Enum.UserInputType.MouseButton2, Enum.UserInputType.MouseButton3
local LockPos, Default = Enum.MouseBehavior.LockCurrentPosition, Enum.MouseBehavior.Default

local function moved()
	local out = 0
	for _, e in ipairs(M.inputLog) do
		if e[1] == "mousemoveabs" then out = out + 1 end
	end
	return out
end
local function record(n, x0)
	E.modes:request("unpause")
	for i = 1, n do
		M.mouse = Vector2.new(x0 + i * 50, 200 + i * 10)
		M.step(1 / 60)
	end
	E.modes:request("pause")
	M.steps(3)
end

eq(s:get("lockCameraPaused"), 1, "Lock Camera (Paused) is on by default")
E.modes:request("create")
M.steps(3)
record(10, 100)
check(tl:count() >= 8, "a run was recorded (" .. tl:count() .. " frames)")
E.modes:seek(4)
M.steps(3)

section("paused, nothing held: the mouse is free")
eq(UIS.MouseBehavior, Default, "the cursor moves freely (menus)")

section("paused, right click held: the cursor stays locked where it is")
do
	M.mouseDown(2)
	M.steps(2)
	eq(UIS.MouseBehavior, LockPos, "LockCurrentPosition while right click is held")
	camCtrl:UpdateMouseBehavior() -- (the game's camera script reacts to the button)
	eq(UIS.MouseBehavior, LockPos, "the game's camera script doesn't free it while the camera is held")
	M.mouseUp(2)
	M.steps(2)
	eq(UIS.MouseBehavior, Default, "released: free again")
	M.mouseDown(3)
	M.steps(2)
	eq(UIS.MouseBehavior, LockPos, "the middle button too")
	M.mouseUp(3)
	M.steps(2)
	eq(UIS.MouseBehavior, Default, "(released)")
end

section("the window loses focus with the button down (its release never comes): not held any more")
do
	M.mouseDown(2)
	M.steps(2)
	eq(UIS.MouseBehavior, LockPos, "(held: locked)")
	M.buttonsDown[RMB] = nil -- (released somewhere else: no InputEnded)
	M.services.UserInputService.WindowFocusReleased:Fire()
	M.steps(2)
	eq(UIS.MouseBehavior, Default, "focus lost: free again")
end

section("a HappaTAS window open: the mouse stays free for it")
do
	E.modal = true
	M.mouseDown(2)
	M.steps(2)
	eq(UIS.MouseBehavior, Default, "a window is open: free")
	M.mouseUp(2)
	E.modal = false
	M.steps(2)
end

section("unpausing with right click held: the cursor isn't moved back to the frame's position")
do
	M.mouse = Vector2.new(1700, 80) -- (far from where the frame had it)
	M.mouseDown(2)
	M.steps(2)
	M.inputLog = {}
	E.modes:request("unpause")
	eq(moved(), 0, "no mouse move when unpausing (a locked cursor moved turns the camera)")
	M.steps(4)
	M.mouseUp(2)
	E.modes:request("pause")
	M.steps(3)
	M.mouse = Vector2.new(1700, 80)
	M.inputLog = {}
	E.modes:request("unpause")
	eq(moved(), 1, "nothing held: the cursor goes back to the frame's position as before")
	M.steps(3)
	E.modes:request("pause")
	M.steps(3)
end

section("lock camera off: right click while paused is the game's (the camera turns as usual)")
do
	s:set("lockCameraPaused", 0)
	M.steps(3)
	M.mouseDown(2)
	M.steps(2)
	check(UIS.MouseBehavior ~= Default or not E.cs:isMouseFree(), "the mouse isn't freed by HappaTAS")
	M.mouseUp(2)
	s:set("lockCameraPaused", 1)
	M.steps(3)
end

section("leaving the pause right as the button is let go: HappaTAS's lock is given back")
do
	gameMouse = false
	M.mouseDown(2)
	M.steps(2)
	M.mouseUp(2)
	E.modes:request("idle")
	M.steps(3)
	check(UIS.MouseBehavior ~= LockPos, "Idle with nothing held: not locked by HappaTAS")
	gameMouse = true
end

finish()
