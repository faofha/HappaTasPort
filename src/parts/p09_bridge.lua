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
	local UserGameSettings
	pcall(function() UserGameSettings = UserSettings():GetService("UserGameSettings") end)

	local Default = Enum.MouseBehavior.Default
	local LockCenter = Enum.MouseBehavior.LockCenter
	local Scriptable = Enum.CameraType.Scriptable
	local FIRST_PERSON = 1.0      -- BaseCamera's FIRST_PERSON_DISTANCE_THRESHOLD

	local cameras                 -- CameraModule (PlayerModule:GetCameras())
	local patchedModule = nil
	local originals = {}          -- { table, key, original, wrapper } or { hooked = function }
	local rotate = true
	local shiftlockBlocked = false
	local freeMouse = false
	local snapUntil = 0
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

	local function applyPatches(playerModule)
		if patchedModule == playerModule then return end
		patchedModule = playerModule
		local camMod = playerModule:FindFirstChild("CameraModule")
		if not camMod then return end
		local baseCam = camMod:FindFirstChild("BaseCamera")
		if baseCam then
			local okR, BaseCamera = pcall(require, baseCam)
			if okR and type(BaseCamera) == "table" then
				patch(BaseCamera, "UpdateMouseBehavior", function(orig)
					return function(self, ...)
						if freeMouse then
							setMouseBehavior(Default)
							return
						end
						local res = orig(self, ...)
						if not rotate and UserGameSettings and (self.inFirstPerson or self.inMouseLockedMode) then
							pcall(function() UserGameSettings.RotationType = Enum.RotationType.MovementRelative end)
						end
						return res
					end
				end)
			end
		end
		local zoomMod = camMod:FindFirstChild("ZoomController")
		if zoomMod then
			local okR, Zoom = pcall(require, zoomMod)
			if okR and type(Zoom) == "table" then
				patch(Zoom, "Update", function(orig)
					return function(renderDt, ...)
						if snapUntil > 0 then
							if os.clock() <= snapUntil and type(renderDt) == "number" then
								renderDt = renderDt * 1000000
							end
							snapUntil = 0 -- consumed by the first update after the request
						end
						return orig(renderDt, ...)
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
	local GC_KEYS = { "currentSubjectDistance", "activeMouseLockController", "isMouseLocked" }
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
		if cameras then return cameras end
		local now = os.clock()
		if now - lastResolveTry < 1 then return nil end -- don't re-require every frame while it's missing
		lastResolveTry = now
		local ps = LocalPlayer:FindFirstChild("PlayerScripts")
		local pm = ps and ps:FindFirstChild("PlayerModule")
		if not pm then return nil end
		local ok, mod = pcall(require, pm)
		if not ok or type(mod) ~= "table" then return nil end
		local cams
		pcall(function()
			if type(mod.GetCameras) == "function" then cams = mod:GetCameras() end
			if not cams and type(mod.cameras) == "table" then cams = mod.cameras end
		end)
		if cams then
			cameras = cams
			applyPatches(pm)
			if not mouseLockCtrl and type(cams.activeMouseLockController) == "table" then
				mouseLockCtrl = cams.activeMouseLockController
			end
		end
		return cameras
	end

	local function activeController()
		local cams = resolve()
		local ctrl = cams and cams.activeCameraController
		if type(ctrl) == "table" then return ctrl end
		return nil
	end
	Bridge.Controller = activeController

	function Bridge.Init()
		task.spawn(scanGC)
		task.spawn(function()
			local t0 = os.clock()
			while not Janitor.unloading and not resolve() and os.clock() - t0 < 120 do
				task.wait(0.5)
			end
			if not cameras and not Janitor.unloading then
				warnf("Could not find the game's PlayerModule, zoom/shiftlock syncing is limited.")
			end
		end)
	end

	function Bridge.GetZoom()
		local ctrl = activeController()
		if ctrl and type(ctrl.GetCameraToSubjectDistance) == "function" then
			local ok, z = pcall(ctrl.GetCameraToSubjectDistance, ctrl)
			if ok and type(z) == "number" and z == z then return z end
		end
		for _, zc in ipairs(zoomControllers) do
			local ok, z = pcall(zc.GetCameraToSubjectDistance, zc)
			if ok and type(z) == "number" and z == z and z ~= 12.5 then return z end
		end
		local cam = workspace.CurrentCamera
		if cam then
			return (cam.CFrame.Position - cam.Focus.Position).Magnitude
		end
		return 12.5
	end

	function Bridge.RemoveZoomSpring()
		snapUntil = os.clock() + 0.25
	end

	-- static = land on the zoom instantly (no spring)
	function Bridge.SetZoom(zoom, static)
		if type(zoom) ~= "number" or zoom ~= zoom or zoom == math.huge or zoom <= 0 then return end
		if static then Bridge.RemoveZoomSpring() end
		local ctrl = activeController()
		if ctrl and type(ctrl.SetCameraToSubjectDistance) == "function" then
			local okG, cur = pcall(ctrl.GetCameraToSubjectDistance, ctrl)
			local same = okG and type(cur) == "number" and math.abs(cur - zoom) < 1e-4
				and not (zoom < FIRST_PERSON and ctrl.inFirstPerson == false)
			if not same then gameCall(ctrl.SetCameraToSubjectDistance, ctrl, zoom) end
		end
		for _, zc in ipairs(zoomControllers) do
			if zc ~= ctrl then
				local okG, cur = pcall(zc.GetCameraToSubjectDistance, zc)
				if not (okG and type(cur) == "number" and math.abs(cur - zoom) < 1e-4) then
					gameCall(zc.SetCameraToSubjectDistance, zc, zoom)
				end
			end
		end
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

	function Bridge.UpdateGhost(zoom, dt)
		local char = LocalPlayer.Character
		if not char then return end
		zoom = tonumber(zoom) or 12.5
		local target = 0
		if zoom < 2 then target = 1 - (zoom - 0.5) / 1.5 end
		if target < 0.5 then target = 0 end
		local value = target
		if ghost.last ~= nil then
			local maxDelta = 2.8 * (dt or 0.016)
			value = ghost.last + clampn(target - ghost.last, -maxDelta, maxDelta)
		end
		value = clampn(math.floor(value * 100 + 0.5) / 100, 0, 1)
		ghost.tick = ghost.tick + 1
		local rebuild = ghost.char ~= char or ghost.tick % 60 == 1
		if rebuild then
			ghost.char = char
			ghost.parts = collectGhostParts(char)
		end
		if rebuild or value ~= ghost.last then
			for _, part in ipairs(ghost.parts) do
				if part.Parent then part.LocalTransparencyModifier = value end
			end
		end
		ghost.last = value
		ghost.active = true
	end

	function Bridge.ResetGhost()
		if not ghost.active then return end
		ghost.active = false
		ghost.last = nil
		for _, part in ipairs(ghost.parts) do
			if part.Parent then part.LocalTransparencyModifier = 0 end
		end
		ghost.parts = {}
		pcall(function()
			local cams = resolve()
			local tc = cams and cams.activeTransparencyController
			if tc then
				tc.lastTransparency = nil
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

	function Bridge.ShiftlockSwitch()
		local ctrl = lockController()
		if not ctrl then return end
		if type(ctrl.OnMouseLockToggled) == "function" then
			gameCall(ctrl.OnMouseLockToggled, ctrl)
		elseif type(ctrl.DoMouseLockSwitch) == "function" then
			local wasBlocked = shiftlockBlocked
			shiftlockBlocked = false
			gameCall(ctrl.DoMouseLockSwitch, ctrl, "MouseLockSwitchAction", Enum.UserInputState.Begin, game)
			shiftlockBlocked = wasBlocked
		end
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
		local want = (locked and rotate) and Enum.RotationType.CameraRelative or Enum.RotationType.MovementRelative
		if UserGameSettings.RotationType ~= want then
			pcall(function() UserGameSettings.RotationType = want end)
		end
	end

	-- modalOpen: a HappaTAS window is open (its Modal button frees the mouse, don't lock it again)
	function Bridge.GuardMouse(modalOpen)
		if freeMouse then
			setMouseBehavior(Default)
			return
		end
		if modalOpen or (GuiService and GuiService.MenuIsOpen) then return end
		local cam = workspace.CurrentCamera
		if not cam or cam.CameraType == Scriptable then return end
		local locked = Bridge.IsInFirstPerson() or Bridge.IsShiftlocked()
		if locked and UIS.MouseBehavior == Default then
			setMouseBehavior(LockCenter)
			rotationFor(true)
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
		pcall(Bridge.ResetGhost)
		shiftlockBlocked = false
		snapUntil = 0
		rotate = true
		freeMouse = false
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

