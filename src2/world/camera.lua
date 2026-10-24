-- ================================================================================================
--  CAMERA  (HappaTAS 3 world plugin, order 20): the camera of each frame and how the camera and the
--  mouse behave while paused and in Test (V2.38.16 p18_core: UpdateCamera, holdPausedCamera,
--  updateMouseMode). Columns: CamCframe (12), Zoom, ShiftLock (u8), taken when a frame starts.
--  The camera is only posed while it is locked: Lock Camera (Paused) in Create, Lock Camera (Test) in
--  Test. FIRST_PERSON: a zoom at or below 0.55 counts as first person (the mouse stays locked).
-- ================================================================================================
local Util = import("engine/util")
local CameraScript = import("platform/camerascript")

local round = Util.round
local Camera = { name = "camera", order = 20 }
Camera.__index = Camera

function Camera.new(E)
	local self = setmetatable({ E = E }, Camera)
	local tl = E.tl
	tl:addColumn("CamCframe", "f64", 12, { key = "CamCframe", keepOnChange = true })
	tl:addColumn("Zoom", "f64", 1, { key = "Zoom" })
	tl:addColumn("ShiftLock", "u8", 1, { key = "ShiftLock" })
	return self
end

local function cfAt(tl, i)
	local x, y, z, a, b, c, d, e, f, g, h, k = tl:getN("CamCframe", i)
	return CFrame.new(x, y, z, a, b, c, d, e, f, g, h, k)
end

function Camera:begin(tl, i)
	local cs = self.E.cs
	local x, y, z, a, b, c, d, e, f, g, h, k = workspace.CurrentCamera.CFrame:GetComponents()
	tl:setN("CamCframe", i, round(x, 1000), round(y, 1000), round(z, 1000), round(a, 1000), round(b, 1000), round(c, 1000),
		round(d, 1000), round(e, 1000), round(f, 1000), round(g, 1000), round(h, 1000), round(k, 1000))
	tl:set("ShiftLock", i, 1, cs:isShiftlocked() and 1 or 0)
	tl:set("Zoom", i, 1, round(cs:getZoom(), 1000))
end

function Camera:zoomAt(tl, i) return tl:get("Zoom", i, 1) end
function Camera:shiftAt(tl, i) return tl:get("ShiftLock", i, 1) end

-- the camera between frames i1 and i2 (weight w), and its zoom
function Camera:averaged(tl, i1, i2, w)
	if i1 == i2 then return cfAt(tl, i1), tl:get("Zoom", i1, 1) end
	local z1, z2 = tl:get("Zoom", i1, 1), tl:get("Zoom", i2, 1)
	return cfAt(tl, i1):Lerp(cfAt(tl, i2), w), z1 + (z2 - z1) * w
end

-- the camera on a frame (index) or a playback pose ({ CamCF, ShiftLock, Zoom }); unlockShift = leave the
-- shift lock as it is (V2 C.UpdateCamera)
function Camera:update(src, unlockShift)
	local E = self.E
	if not E.modes:setCam() then return end
	local tl = E.tl
	local camCF, shift, zoom
	if type(src) == "table" then
		camCF, shift, zoom = src.CamCF, src.ShiftLock, src.Zoom
	else
		if not src or src < 1 or src > tl:count() then return end
		camCF, shift, zoom = cfAt(tl, src), tl:get("ShiftLock", src, 1), tl:get("Zoom", src, 1)
	end
	local cam = workspace.CurrentCamera
	cam.CFrame = camCF or CFrame.new()
	local ch = E.char
	local hrp, hum = ch.hrp, ch.hum
	if hrp and hrp.Parent then
		local off = hum and hum.CameraOffset or Util.ZERO3
		cam.Focus = CFrame.new(hrp.CFrame.Position + hrp.CFrame:VectorToWorldSpace(Vector3.new(0, 1.5, 0) + off))
	end
	if not unlockShift then
		local isShift = E.cs:isShiftlocked() and 1 or 0
		if isShift ~= shift then E.cs:shiftlockSwitch() end
	end
	E.cs:setZoom(tonumber(zoom) or 12.5, true)
end

-- paused with a locked camera: the camera stays on the frame shown
function Camera:holdPaused()
	local E = self.E
	if E.mode ~= 2 or not E.paused or E.firstFrame or E.lookAround or not E.modes:setCam() then return end
	if E.frame >= 1 and E.frame <= E.tl:count() then self:update(E.frame, false) end
end

-- mouse rules: free while paused with a locked camera / testing with a scriptable camera. For a short time
-- after HappaTAS hands the camera back, the camera's mouse lock is checked every frame (stale first person
-- state from older camera scripts), never longer.
function Camera:updateMouseMode()
	local E = self.E
	local cs, tl = E.cs, E.tl
	local modal = E.modalOpen ~= nil and E.modalOpen()
	local camFreeze = (E.mode == 2 and E.paused and not E.firstFrame and tl:count() > 0 and E.modes:setCam() and not E.lookAround)
	local lockedView = false
	if E.mode == 2 and not modal then
		local f = E.frame
		if camFreeze and f >= 1 and f <= tl:count() and tl:isFilled(f) then
			lockedView = tl:get("ShiftLock", f, 1) == 1 or tl:get("Zoom", f, 1) <= CameraScript.FIRST_PERSON
		else
			lockedView = cs:isFirstPerson() or cs:isShiftlocked()
		end
	end
	local forceLock = camFreeze and lockedView
	cs:setCameraFreeze(camFreeze, forceLock, camFreeze)
	local free = false
	if modal then
		free = true
	elseif E.mode == 3 and E.settings:on("lockCameraTest") then
		free = true
	elseif camFreeze and not lockedView then
		free = true
	end
	cs:setFreeMouse(free)
	if not free and E.mode ~= 3 then
		if E.mode == 2 or E.guardFrames > 0 then
			if E.guardFrames > 0 then E.guardFrames = E.guardFrames - 1 end
			cs:guardMouse(modal, forceLock)
		end
	end
end

return Camera
