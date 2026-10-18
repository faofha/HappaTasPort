-- ================================================================================================
--  BRIDGE   (the game's own camera scripts: zoom, shift lock, first person, mouse lock)
--
--  * Zoom is read / written through PlayerModule's active camera controller, plus every controller
--    getgc() finds (games that run their own copy of the camera module).
--  * ZoomController.Update is wrapped so a zoom change can skip the zoom spring for one update.
--  * BaseCamera.UpdateMouseBehavior is wrapped so HappaTAS can free the mouse while paused and so
--    the character doesn't turn with the camera while it is held still.
--  * RefreshMouse() asks the camera to re-apply its mouse lock. Older camera scripts only do that
--    on events (right click, zoom change), which is why the camera used to need a right click after
--    unpausing in first person.
-- ================================================================================================
do
	Bridge.timeRate = 1 -- how fast the TAS clock runs against real time while recording (speed hack)
	local UserGameSettings
	pcall(function() UserGameSettings = UserSettings():GetService("UserGameSettings") end)

	local Default = Enum.MouseBehavior.Default
	local LockCenter = Enum.MouseBehavior.LockCenter
	local Scriptable = Enum.CameraType.Scriptable
	local FIRST_PERSON = 0.55

	local cameras                 -- CameraModule (PlayerModule:GetCameras())
	local activeCamCtrl = nil
	local zoomModTbl = nil
	local transparencyCtrl = nil
	local patchedModule = nil
	local originals = {}          -- { table, key, original, wrapper } or { hooked = function }
	local rotate = true
	local shiftlockBlocked = false
	local freeMouse = false
	local camFreeze = false
	local camFreezeZoom = false
	local forceLockCenter = false
	local snapZoom = false
	local pendingRestore = nil
	local mouseLockCtrl = nil
	local zoomControllers = {}
	local gcDone = false
	local lastResolveTry = 0
	local patchedLockClasses = setmetatable({}, { __mode = "k" })

	local ghost = { last = nil, parts = {}, char = nil, tick = 0, active = false }

	-- Calls that make the game's camera module change something (mouse lock refresh, zoom, shift lock
	-- toggle) run in a thread of their own. Found in the live client: right after such a call the calling
	-- thread loses access to CoreGui until it next yields ("The current thread cannot access 'Instance'
	-- (lacking capability Plugin)", and gethui() returns nil), so whatever touched the HappaTAS interface
	-- next in the same frame failed. task.spawn runs the call straight away, so the order of events is
	-- the same, and only the short-lived thread loses its access. (Reading values is not affected.)
	local function gameCall(f, ...)
		task.spawn(pcall, f, ...)
	end
	-- the same for a call whose result is needed (V2.38.13, checked in the client: even the getter
	-- MouseLockController:GetMouseLockOffset takes the access away, like SetIsMouseLocked,
	-- SetCameraToSubjectDistance and ZoomController.Update; GetCameraToSubjectDistance, GetIsMouseLocked,
	-- SetMouseLockOffset and ZoomController.SetZoomParameters don't). ok is false if f errored or yielded.
	local function gameGet(f, ...)
		local ok, v = false, nil
		task.spawn(function(...)
			ok, v = pcall(f, ...)
		end, ...)
		return ok, v
	end

	-- Changes the behaviour of one of the camera script's functions. With the executor's hookfunction the
	-- function itself is changed and stays the same function value (Real docs: it "returns a callable copy
	-- of the original"), so a game script that keeps or compares the function sees nothing new; undone with
	-- restorefunction. Without them the table field is swapped for the wrapper (as before V2.38.3).
	local function patch(tbl, key, makeWrapper)
		if type(tbl) ~= "table" then return false end
		local ok = pcall(function()
			local orig = rawget(tbl, key) or tbl[key]
			if type(orig) ~= "function" then error("missing " .. tostring(key)) end
			if Env.hookfunction and Env.restorefunction then
				local copy
				local okH = pcall(function()
					copy = Env.hookfunction(orig, makeWrapper(function(...) return copy(...) end))
				end)
				if okH and type(copy) == "function" then
					originals[#originals + 1] = { hooked = orig }
					return
				end
				pcall(Env.restorefunction, orig) -- a half-done hook
			end
			local wrapper = makeWrapper(orig)
			tbl[key] = wrapper
			originals[#originals + 1] = { tbl, key, orig, wrapper }
		end)
		if not ok then log("could not patch", key) end
		return ok
	end

	local function setMouseBehavior(b)
		if UIS.MouseBehavior ~= b then pcall(function() UIS.MouseBehavior = b end) end
	end

	local restored = false -- Bridge.Restore ran (Unload): the camera script is never patched again
	local function applyPatches(playerModule)
		if restored or patchedModule == playerModule then return end
		patchedModule = playerModule
		local camMod = playerModule:FindFirstChild("CameraModule")
		if not camMod then return end
		local camInp = camMod:FindFirstChild("CameraInput")
		if camInp then
			local okI, CameraInput = pcall(require, camInp)
			if okI and type(CameraInput) == "table" then
				if type(CameraInput.getRotation) == "function" then
					patch(CameraInput, "getRotation", function(orig)
						return function(...)
							local rot = orig(...)
							if camFreeze then return Vector2.zero end
							return rot
						end
					end)
				end
				if type(CameraInput.getZoomDelta) == "function" then
					patch(CameraInput, "getZoomDelta", function(orig)
						return function(...)
							local dz = orig(...)
							if camFreezeZoom then return 0 end
							return dz
						end
					end)
				end
			end
		end
		local baseCam = camMod:FindFirstChild("BaseCamera")
		if baseCam then
			local okR, BaseCamera = pcall(require, baseCam)
			if okR and type(BaseCamera) == "table" then
				patch(BaseCamera, "UpdateMouseBehavior", function(orig)
					return function(self, ...)
						if type(self) == "table" then
							activeCamCtrl = self
							if pendingRestore then
								local pr = pendingRestore
								pendingRestore = nil
								pcall(function()
									if type(pr.zoom) == "number" and pr.zoom > 0 then
										self.currentSubjectDistance = pr.zoom < FIRST_PERSON and 0.5 or pr.zoom
										if type(self.SetCameraToSubjectDistance) == "function" then
											self:SetCameraToSubjectDistance(pr.zoom)
										end
										if pr.zoom < FIRST_PERSON then
											if type(self.EnterFirstPerson) == "function" then self:EnterFirstPerson() else self.inFirstPerson = true end
										elseif self.inFirstPerson then
											if type(self.LeaveFirstPerson) == "function" then self:LeaveFirstPerson() else self.inFirstPerson = false end
										end
									end
								end)
							end
							if not freeMouse and not camFreeze then
								local isShift = Bridge.IsShiftlocked()
								if self.inMouseLockedMode ~= isShift then
									pcall(function()
										if type(self.SetIsMouseLocked) == "function" then
											self:SetIsMouseLocked(isShift)
										else
											self.inMouseLockedMode = isShift
										end
										if type(self.SetMouseLockOffset) == "function" then
											self:SetMouseLockOffset(isShift and Vector3.new(1.75, 0, 0) or Vector3.zero)
										end
									end)
								end
							end
						end
						if freeMouse then
							setMouseBehavior(Default)
							return
						end
						if forceLockCenter or (camFreeze and (self.inFirstPerson or self.inMouseLockedMode or Bridge.IsInFirstPerson() or Bridge.IsShiftlocked())) then
							setMouseBehavior(LockCenter)
							if (not rotate or camFreeze) and UserGameSettings then
								pcall(function() UserGameSettings.RotationType = Enum.RotationType.MovementRelative end)
							end
							return
						end
						if camFreeze then
							setMouseBehavior(Default)
							return
						end
						local res = orig(self, ...)
						local lockedNow = self.inFirstPerson or self.inMouseLockedMode or Bridge.IsInFirstPerson() or Bridge.IsShiftlocked()
						if lockedNow then
							setMouseBehavior(LockCenter)
							if UserGameSettings then
								local wantRot = (rotate and not camFreeze) and Enum.RotationType.CameraRelative or Enum.RotationType.MovementRelative
								pcall(function() UserGameSettings.RotationType = wantRot end)
							end
						elseif UIS.MouseBehavior == LockCenter then
							setMouseBehavior(Default)
							if UserGameSettings then
								pcall(function() UserGameSettings.RotationType = Enum.RotationType.MovementRelative end)
							end
						end
						return res
					end
				end)
				if type(BaseCamera.CalculateNewLookCFrameFromArg) == "function" then
					patch(BaseCamera, "CalculateNewLookCFrameFromArg", function(orig)
						return function(self, suppliedLookVector, rotateInput, ...)
							if camFreeze then rotateInput = Vector2.zero end
							return orig(self, suppliedLookVector, rotateInput, ...)
						end
					end)
				end
			end
		end
		local classicCam = camMod:FindFirstChild("ClassicCamera")
		if classicCam then
			local okC, ClassicCamera = pcall(require, classicCam)
			if okC and type(ClassicCamera) == "table" and type(ClassicCamera.Update) == "function" then
				patch(ClassicCamera, "Update", function(orig)
					return function(self, ...)
						if type(self) == "table" then activeCamCtrl = self end
						return orig(self, ...)
					end
				end)
			end
		end
		local zoomMod = camMod:FindFirstChild("ZoomController")
		if zoomMod then
			local okR, Zoom = pcall(require, zoomMod)
			if okR and type(Zoom) == "table" then
				zoomModTbl = Zoom
				patch(Zoom, "Update", function(orig)
					return function(renderDt, ...)
						if snapZoom then
							snapZoom = false
							local res = orig(100, ...)
							if type(Zoom.ReleaseSpring) == "function" then
								pcall(Zoom.ReleaseSpring)
							end
							return res
						end
						-- (speed hack: the zoom spring runs on the TAS clock, so a zoom recorded in slow / fast
						-- motion plays back at its normal speed)
						local k = Bridge.timeRate
						if k ~= 1 and type(renderDt) == "number" then renderDt = renderDt * k end
						return orig(renderDt, ...)
					end
				end)
			end
		end
		local transMod = camMod:FindFirstChild("TransparencyController")
		if transMod then
			local okT, TC = pcall(require, transMod)
			if okT and type(TC) == "table" and type(TC.Update) == "function" then
				patch(TC, "Update", function(orig)
					return function(self, ...)
						if type(self) == "table" then transparencyCtrl = self end
						return orig(self, ...)
					end
				end)
			end
		end
	end

	-- one table from the garbage collector: a camera controller (zoom) and / or the mouse lock controller
	local function checkTable(t)
		if type(rawget(t, "currentSubjectDistance")) == "number"
			and type(t.SetCameraToSubjectDistance) == "function"
			and type(t.GetCameraToSubjectDistance) == "function"
			and not table.find(zoomControllers, t) then
			zoomControllers[#zoomControllers + 1] = t
		end
		if type(rawget(t, "activeCameraController")) == "table"
			or type(rawget(t, "activeTransparencyController")) == "table"
			or type(rawget(t, "activeMouseLockController")) == "table" then
			cameras = t
			if type(rawget(t, "activeTransparencyController")) == "table" then
				transparencyCtrl = rawget(t, "activeTransparencyController")
			end
		end
		if not transparencyCtrl and rawget(t, "transparencyDirty") ~= nil and type(rawget(t, "cachedParts")) == "table" then
			transparencyCtrl = t
		end
		if not mouseLockCtrl then
			local amc = rawget(t, "activeMouseLockController")
			if type(amc) == "table" then
				mouseLockCtrl = amc
			elseif type(t.GetIsMouseLocked) == "function" and type(t.DoMouseLockSwitch) == "function"
				and rawget(t, "isMouseLocked") ~= nil then
				mouseLockCtrl = t
			end
		end
	end
	-- filtergc matches the tables natively, only the ones with these keys come back (Real docs).
	-- getgc(true) first puts every object of the game's memory in one table, which can freeze the client
	-- in a big game (Real's own tools refuse to run it); it is only used when there is no filtergc.
	local GC_KEYS = { "currentSubjectDistance", "activeCameraController", "activeTransparencyController", "activeMouseLockController", "isMouseLocked", "transparencyDirty" }
	local function scanFiltered()
		for _, key in ipairs(GC_KEYS) do
			local found = Env.filtergc("table", { Keys = { key } })
			if type(found) ~= "table" then return false end
			for _, t in ipairs(found) do
				if type(t) == "table" then pcall(checkTable, t) end
			end
		end
		return true
	end
	local function scanGC()
		if gcDone then return end
		gcDone = true
		if Env.filtergc then
			local ok, done = pcall(scanFiltered)
			if ok and done then
				log(#zoomControllers .. " zoom controller(s) found (filtergc)")
				return
			end
		end
		if not Env.getgc then return end
		pcall(function()
			local n = 0
			for _, t in ipairs(Env.getgc(true)) do
				if type(t) == "table" then pcall(checkTable, t) end
				n = n + 1
				if n % 20000 == 0 then task.wait() end
				if Janitor.unloading then break end
			end
		end)
		log(#zoomControllers .. " zoom controller(s) found")
	end

	local function resolve()
		local known = cameras ~= nil
			and (rawget(cameras, "activeCameraController") ~= nil or rawget(cameras, "activeTransparencyController") ~= nil)
		-- (the camera script's patches go in even when the garbage collector scan found the cameras first: with
		-- filtergc it finishes before the first look, and the patches were never made - found live in V2.38.16)
		if known and (restored or (patchedModule ~= nil and patchedModule.Parent)) then return cameras end
		local now = os.clock()
		if now - lastResolveTry < 1 then return cameras end
		lastResolveTry = now
		local ps = LocalPlayer:FindFirstChild("PlayerScripts")
		local pm = ps and ps:FindFirstChild("PlayerModule")
		if not pm then return cameras end
		applyPatches(pm)
		if known then return cameras end
		local ok, mod = pcall(require, pm)
		if not ok or type(mod) ~= "table" then return cameras end
		local cams
		pcall(function()
			if type(mod.GetCameras) == "function" then cams = mod:GetCameras() end
			if not cams and type(mod.cameras) == "table" then cams = mod.cameras end
		end)
		if type(cams) == "table" and (rawget(cams, "activeCameraController") ~= nil or rawget(cams, "activeTransparencyController") ~= nil or rawget(cams, "activeMouseLockController") ~= nil) then
			cameras = cams
			if not mouseLockCtrl and type(cams.activeMouseLockController) == "table" then
				mouseLockCtrl = cams.activeMouseLockController
			end
			if not transparencyCtrl and type(cams.activeTransparencyController) == "table" then
				transparencyCtrl = cams.activeTransparencyController
			end
		end
		return cameras
	end

	local function activeController()
		local cams = resolve()
		local ctrl = activeCamCtrl or (cams and cams.activeCameraController)
		if type(ctrl) == "table" then return ctrl end
		for _, zc in ipairs(zoomControllers) do
			if rawget(zc, "enabled") == true then return zc end
		end
		return zoomControllers[1]
	end
	local function getTransparencyController()
		if transparencyCtrl then return transparencyCtrl end
		local cams = resolve()
		if cams and type(cams.activeTransparencyController) == "table" then
			transparencyCtrl = cams.activeTransparencyController
		end
		return transparencyCtrl
	end
	Bridge.Controller = activeController

	function Bridge.Init()
		on(UIS:GetPropertyChangedSignal("MouseBehavior"), function()
			if forceLockCenter and not freeMouse and not (GuiService and GuiService.MenuIsOpen) and UIS.MouseBehavior ~= LockCenter then
				pcall(function() UIS.MouseBehavior = LockCenter end)
			end
		end)
		task.spawn(scanGC)
		task.spawn(function()
			local t0 = os.clock()
			while not Janitor.unloading and not activeController() and os.clock() - t0 < 120 do
				task.wait(0.5)
			end
			if not activeController() and not Janitor.unloading then
				warnf("Could not find the game's PlayerModule, zoom/shiftlock syncing is limited.")
			end
		end)
	end

	function Bridge.GetZoom()
		local ctrl = activeController()
		if ctrl and ctrl.inFirstPerson == true then
			return 0.5
		end
		if zoomModTbl and type(zoomModTbl.GetZoomRadius) == "function" then
			local ok, z = pcall(zoomModTbl.GetZoomRadius)
			if ok and type(z) == "number" and z == z and z > 0 then return z end
		end
		if ctrl and type(ctrl.GetCameraToSubjectDistance) == "function" then
			local ok, z = pcall(ctrl.GetCameraToSubjectDistance, ctrl)
			if ok and type(z) == "number" and z == z then return z end
		end
		local cam = workspace.CurrentCamera
		if cam then
			return (cam.CFrame.Position - cam.Focus.Position).Magnitude
		end
		return 12.5
	end
	local function forEachCamController(fn)
		local seen = {}
		local function visit(c)
			if type(c) == "table" and not seen[c] then
				seen[c] = true
				gameCall(fn, c) -- fn calls the camera module (zoom, first person, mouse lock)
			end
		end
		visit(activeCamCtrl)
		local cams = resolve()
		if cams then visit(cams.activeCameraController) end
		for _, zc in ipairs(zoomControllers) do visit(zc) end
	end

	function Bridge.RemoveZoomSpring()
		snapZoom = true
		if zoomModTbl and type(zoomModTbl.Update) == "function" then
			local cam = workspace.CurrentCamera
			gameCall(zoomModTbl.Update, 100, cam and cam.Focus or CFrame.new(), 0)
		end
	end

	-- static = land on the zoom instantly (no spring)
	function Bridge.SetZoom(zoom, static)
		if type(zoom) ~= "number" or zoom ~= zoom or zoom == math.huge or zoom <= 0 then return end
		local targetZ = zoom < FIRST_PERSON and 0.5 or zoom
		local ctrl = activeController()
		local curR
		if zoomModTbl and type(zoomModTbl.GetZoomRadius) == "function" then
			local okR, r = pcall(zoomModTbl.GetZoomRadius)
			if okR and type(r) == "number" and r == r then curR = r end
		end
		local okG, cur = false, nil
		if ctrl and type(ctrl.GetCameraToSubjectDistance) == "function" then
			okG, cur = pcall(ctrl.GetCameraToSubjectDistance, ctrl)
		end
		local checkDist = curR or (okG and cur)
		local same = not static and type(checkDist) == "number" and math.abs(checkDist - targetZ) < 1e-3
			and ctrl ~= nil
			and not (zoom < FIRST_PERSON and ctrl.inFirstPerson == false)
			and not (zoom >= FIRST_PERSON and ctrl.inFirstPerson == true)
		if same then return end
		if zoomModTbl and type(zoomModTbl.SetZoomParameters) == "function" then
			pcall(zoomModTbl.SetZoomParameters, targetZ, 0)
		end
		forEachCamController(function(c)
			if rawget(c, "currentSubjectDistance") ~= nil then
				c.currentSubjectDistance = targetZ
			end
			if type(c.SetCameraToSubjectDistance) == "function" then
				c:SetCameraToSubjectDistance(targetZ)
			end
			if zoom < FIRST_PERSON then
				if type(c.EnterFirstPerson) == "function" then
					c:EnterFirstPerson()
				elseif rawget(c, "inFirstPerson") ~= nil then
					c.inFirstPerson = true
				end
			elseif c.inFirstPerson then
				if type(c.LeaveFirstPerson) == "function" then
					c:LeaveFirstPerson()
				else
					c.inFirstPerson = false
				end
			end
		end)
		if zoomModTbl and type(zoomModTbl.SetZoomParameters) == "function" then
			pcall(zoomModTbl.SetZoomParameters, targetZ, 0)
		end
		if static then Bridge.RemoveZoomSpring() end
	end

	-- --------------------------------------------------------------------------------------------
	--  GHOST MODE: the camera script's see-through character does not run while the camera is
	--  Scriptable (test playback), so the same maths is applied here.
	-- --------------------------------------------------------------------------------------------
	local function collectGhostParts(char)
		local list = {}
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and not d:FindFirstAncestorWhichIsA("Tool") then
				list[#list + 1] = d
			end
		end
		return list
	end

	function Bridge.UpdateGhost(zoom, dt, snap)
		local char = LocalPlayer.Character
		if not char then return end
		local dist = tonumber(zoom) or 12.5
		local cam = workspace.CurrentCamera
		if cam then
			local head = char:FindFirstChild("Head")
			local hrp = char:FindFirstChild("HumanoidRootPart")
			local focusPos = (head and head.Position) or (hrp and (hrp.Position + Vector3.new(0, 1.5, 0))) or cam.Focus.Position
			local camDist = (cam.CFrame.Position - focusPos).Magnitude
			if camDist < dist then dist = camDist end
		end
		local target = 0
		if dist < 2 then
			target = 1 - (dist - 0.5) / 1.5
			if target < 0.5 then target = 0 end
		end
		local value = target
		if not snap and ghost.last ~= nil and not (target == 1 and ghost.last >= 0.95) then
			local maxDelta = 2.8 * (dt or 0.016)
			value = ghost.last + clampn(target - ghost.last, -maxDelta, maxDelta)
		end
		value = clampn(math.floor(value * 100 + 0.5) / 100, 0, 1)
		ghost.tick = ghost.tick + 1
		local rebuild = snap or ghost.char ~= char or ghost.tick % 60 == 1
		if rebuild then
			ghost.char = char
			ghost.parts = collectGhostParts(char)
		end
		for _, part in ipairs(ghost.parts) do
			if part.Parent and part.LocalTransparencyModifier ~= value then
				part.LocalTransparencyModifier = value
			end
		end
		local tc = getTransparencyController()
		if tc then
			tc.lastTransparency = value
			tc.transparencyDirty = false
		end
		ghost.last = value
		ghost.active = true
	end

	function Bridge.ResetGhost(keepCurrent)
		if not ghost.active then
			local tc = getTransparencyController()
			if tc then tc.transparencyDirty = true end
			return
		end
		ghost.active = false
		local lastVal = ghost.last
		ghost.last = nil
		if not keepCurrent then
			for _, part in ipairs(ghost.parts) do
				if part.Parent then part.LocalTransparencyModifier = 0 end
			end
		end
		ghost.parts = {}
		pcall(function()
			local tc = getTransparencyController()
			if tc then
				tc.lastTransparency = keepCurrent and lastVal or nil
				tc.transparencyDirty = true
			end
		end)
	end

	-- --------------------------------------------------------------------------------------------
	--  SHIFT LOCK / FIRST PERSON / MOUSE
	-- --------------------------------------------------------------------------------------------
	local function lockController()
		if mouseLockCtrl then return mouseLockCtrl end
		local cams = resolve()
		if cams and type(cams.activeMouseLockController) == "table" then
			mouseLockCtrl = cams.activeMouseLockController
		end
		return mouseLockCtrl
	end

	local mouseObj
	function Bridge.IsShiftlocked()
		local ctrl = lockController()
		if ctrl then
			if type(ctrl.GetIsMouseLocked) == "function" then
				local ok, locked = pcall(ctrl.GetIsMouseLocked, ctrl)
				if ok and type(locked) == "boolean" then return locked end
			end
			if type(ctrl.isMouseLocked) == "boolean" then return ctrl.isMouseLocked end
		end
		if not mouseObj then pcall(function() mouseObj = LocalPlayer:GetMouse() end) end
		return mouseObj ~= nil and mouseObj.Icon == "rbxasset://textures/MouseLockedCursor.png"
	end
	function Bridge.SyncShiftlockToCamera()
		local lctrl = lockController()
		local isLocked = Bridge.IsShiftlocked()
		local off = Vector3.zero
		if isLocked then
			if lctrl and type(lctrl.GetMouseLockOffset) == "function" then
				local okO, v = gameGet(lctrl.GetMouseLockOffset, lctrl)
				if okO and typeof(v) == "Vector3" then off = v else off = Vector3.new(1.75, 0, 0) end
			else
				off = Vector3.new(1.75, 0, 0)
			end
		end
		forEachCamController(function(cctrl)
			if type(cctrl.SetIsMouseLocked) == "function" then
				cctrl:SetIsMouseLocked(isLocked)
			elseif rawget(cctrl, "inMouseLockedMode") ~= nil then
				cctrl.inMouseLockedMode = isLocked
			end
			if type(cctrl.SetMouseLockOffset) == "function" then
				cctrl:SetMouseLockOffset(off)
			end
		end)
	end

	function Bridge.ShiftlockSwitch()
		local ctrl = lockController()
		if not ctrl then return end
		if type(ctrl.DoMouseLockSwitch) == "function" then
			local wasBlocked = shiftlockBlocked
			shiftlockBlocked = false
			gameCall(ctrl.DoMouseLockSwitch, ctrl, "MouseLockSwitchAction", Enum.UserInputState.Begin, game)
			shiftlockBlocked = wasBlocked
		elseif type(ctrl.OnMouseLockToggled) == "function" then
			gameCall(ctrl.OnMouseLockToggled, ctrl)
		end
		Bridge.SyncShiftlockToCamera()
	end
	function Bridge.RestoreCameraAfterTest(zoom, wantShiftlock)
		pendingRestore = { zoom = zoom, shiftlock = wantShiftlock }
		local function applyRestore()
			if wantShiftlock ~= nil then
				local curShift = Bridge.IsShiftlocked() and 1 or 0
				if curShift ~= wantShiftlock then Bridge.ShiftlockSwitch() end
			end
			Bridge.SyncShiftlockToCamera()
			if type(zoom) == "number" and zoom > 0 then
				Bridge.SetZoom(zoom, true)
			end
			Bridge.RefreshMouse(Menu.IsModalOpen and Menu.IsModalOpen())
		end
		applyRestore()
		task.defer(function()
			if Core.GetMode and Core.GetMode() == 1 then
				applyRestore()
				task.delay(0.05, function()
					if Core.GetMode and Core.GetMode() == 1 then
						pendingRestore = nil
						applyRestore()
					end
				end)
			end
		end)
	end

	-- while testing the player can't toggle shift lock by hand (the TAS does it)
	function Bridge.LockShiftlock(lock)
		shiftlockBlocked = lock and true or false
		local ctrl = lockController()
		if not ctrl then return end
		local cls = getmetatable(ctrl)
		if type(cls) == "table" and not patchedLockClasses[cls] and type(cls.DoMouseLockSwitch) == "function" then
			patchedLockClasses[cls] = true
			patch(cls, "DoMouseLockSwitch", function(orig)
				return function(self, name, state, input, ...)
					if shiftlockBlocked then return Enum.ContextActionResult.Pass end
					return orig(self, name, state, input, ...)
				end
			end)
		end
	end

	function Bridge.IsInFirstPerson()
		local ctrl = activeController()
		if ctrl and type(ctrl.inFirstPerson) == "boolean" then
			return ctrl.inFirstPerson
		end
		return Bridge.GetZoom() < FIRST_PERSON
	end
	function Bridge.SetCameraFreeze(freeze, forceLock, freezeZoom)
		camFreeze = freeze and true or false
		camFreezeZoom = freezeZoom and true or false
		forceLockCenter = forceLock and true or false
	end

	-- free = the mouse can move freely (paused with a locked camera, testing with a scriptable camera)
	function Bridge.SetFreeMouse(free)
		free = free and true or false
		if freeMouse == free then return end
		freeMouse = free
		if free then
			setMouseBehavior(Default)
		else
			Bridge.RefreshMouse()
		end
	end
	function Bridge.IsMouseFree() return freeMouse end

	local function rotationFor(locked)
		if not UserGameSettings then return end
		local want = (locked and rotate and not camFreeze) and Enum.RotationType.CameraRelative or Enum.RotationType.MovementRelative
		if UserGameSettings.RotationType ~= want then
			pcall(function() UserGameSettings.RotationType = want end)
		end
	end

	-- modalOpen: a HappaTAS window is open (its Modal button frees the mouse, don't lock it again)
	function Bridge.GuardMouse(modalOpen, forceLocked)
		if freeMouse or modalOpen or (GuiService and GuiService.MenuIsOpen) then
			if freeMouse or modalOpen then setMouseBehavior(Default) end
			return
		end
		local cam = workspace.CurrentCamera
		if not cam or cam.CameraType == Scriptable then return end
		local locked = forceLocked or forceLockCenter or Bridge.IsInFirstPerson() or Bridge.IsShiftlocked()
		if locked then
			if UIS.MouseBehavior ~= LockCenter then setMouseBehavior(LockCenter) end
			rotationFor(true)
		else
			rotationFor(false)
			if camFreeze then
				if UIS.MouseBehavior ~= Default then setMouseBehavior(Default) end
			elseif UIS.MouseBehavior == LockCenter then
				setMouseBehavior(Default)
			end
		end
	end

	-- asks the camera script to apply its mouse lock again (fixes the "right click needed" bug)
	function Bridge.RefreshMouse(modalOpen)
		if freeMouse then setMouseBehavior(Default) return end
		local ctrl = activeController()
		if ctrl and type(ctrl.UpdateMouseBehavior) == "function" then
			gameCall(ctrl.UpdateMouseBehavior, ctrl)
		end
		Bridge.GuardMouse(modalOpen)
	end

	function Bridge.ShiftlockRotation(value)
		rotate = value and true or false
		local locked = Bridge.IsInFirstPerson() or Bridge.IsShiftlocked()
		rotationFor(locked)
		Bridge.RefreshMouse()
	end

	function Bridge.Restore()
		restored = true
		pcall(Bridge.ResetGhost)
		shiftlockBlocked = false
		snapZoom = false; camFreezeZoom = false
		rotate = true
		freeMouse = false
		camFreeze = false
		forceLockCenter = false
		for i = #originals, 1, -1 do
			local o = originals[i]
			pcall(function()
				if o.hooked then Env.restorefunction(o.hooked)
				elseif o[1][o[2]] == o[4] then o[1][o[2]] = o[3] end
			end)
		end
		originals = {}
		patchedModule = nil
		pcall(Bridge.RefreshMouse)
	end

	-- the animation engine fills these in
	function Bridge.GetAnimation() return nil end
	function Bridge.SetAnimation() end
	function Bridge.LockAnimations() end
end

