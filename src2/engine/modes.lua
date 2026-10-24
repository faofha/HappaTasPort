-- ================================================================================================
--  MODES  (HappaTAS 3 engine): the mode machine. 1 = Idle, 2 = Create (paused or recording),
--  3 = Test (playback). Every transition is one function here (V2.38.16 p18_core.lua 583-843, same
--  order of effects); keys, buttons and the timeline request them, nothing else changes the mode.
--  The published state `mode` is "Idle" / "Paused" / "Recording" / "Testing".
--  V2's transitions that waited for frames (no jump on the first recorded frame, Unpause 1 Frame) are
--  deferred steps here: they continue at the start of a later PreRender (Frame runs them), which is
--  where V2's waiting threads resumed relative to HappaTAS's own handlers. Handlers never yield.
--  E (the engine context) holds the run state shared with Frame and the plugins.
-- ================================================================================================
local Env = import("platform/env")
local Util = import("engine/util")

local round, clamp = Util.round, Util.clamp
local Modes = {}
Modes.__index = Modes

local CONFIRM_SECONDS = 1.1 -- (V2: the confirm text faded for ~1.05 s)

function Modes.new(E)
	local self = setmetatable({ E = E, confirmDelete = 0, confirmOptimize = 0 }, Modes)
	E.mode, E.frame, E.paused = 1, 1, true
	E.back, E.forw, E.lookAround, E.firstFrame = false, false, false, false
	E.lastPause, E.testTime, E.lastFrameTime, E.freezeRemaining = 1, 0, 0, 0
	E.guardFrames, E.recScale, E.merge = 0, 1, false
	E.currentFrameInput, E.inputDebounce = false, 0
	E.deferred = nil
	return self
end

function Modes:status(text, inverse) self.E.bus:emit("status", text, inverse) end

function Modes:publish()
	local E = self.E
	local name = (E.mode == 1 and "Idle") or (E.mode == 3 and "Testing") or (E.paused and "Paused" or "Recording")
	E.state:set("mode", name)
	E.state:set("frame", E.frame)
end

-- (V2 C.DoubleInput: marks that a transition ran this frame; it never blocked one)
function Modes:doubleInput()
	self.E.currentFrameInput = true
	return false
end

function Modes:setCam()
	local E = self.E
	return (E.mode == 3 and E.settings:on("lockCameraTest")) or (E.mode == 2 and E.settings:on("lockCameraPaused"))
end

function Modes:totalAt(i)
	local tl = self.E.tl
	if i < 1 or i > tl:count() then return 0 end
	return tl:get("TotalTime", i, 1)
end

-- ------------------------------------------------------------------------------------------------ frames
-- the world on frame i (V2 C.LoadFrame): paused on it, or unpausing from it; backtrack = also put the
-- animation back to where it was at that frame
function Modes:loadFrame(i, unpausing, backtrack)
	local E = self.E
	local tl, ch = E.tl, E.char
	if tl:count() == 0 or not i or i < 1 or i > tl:count() then return end
	if not tl:isFilled(i) then return end
	if not ch:loaded() then return end
	local hrp = ch.hrp
	if not unpausing then
		if hrp.Anchored ~= (E.mode ~= 3) then ch:anchor(E.mode ~= 3) end
		ch:syncFrame(tl, i)
		E.cam:update(i)
		if E.mode == 2 then
			if self:setCam() and not E.lookAround then E.cs:updateGhost(E.cam:zoomAt(tl, i), 0, true) end
			E.plugins:call("onShowFrame", tl, i)
		end
	else
		E.plugins:call("onRestoreUnpause", tl, i)
		if self:setCam() then
			local z = E.cam:zoomAt(tl, i)
			E.cs:setZoom(z, true)
			E.cs:updateGhost(z, 0, true)
		end
		E.cs:resetGhost(true)
		E.lastPause = E.frame
		ch:anchor(false)
	end
	hrp.AssemblyLinearVelocity = ch:linAt(tl, i)
	hrp.AssemblyAngularVelocity = ch:angAt(tl, i)
	ch:changeState(tl:get("State", i, 1))
	if E.mode == 2 then E.anim:loadFrame(tl, i, unpausing, backtrack) end
end

function Modes:removeCutFrames()
	local E = self.E
	if E.tl:count() > E.frame then
		E.tl:cut(E.frame)
		E.plugins:call("onDataChanged")
	end
end

-- the interpolated pose between frames i and i + 1 at playback time t (V2 C.AveragedFrame)
function Modes:averaged(i1, i2, t)
	local E = self.E
	local tl, ch = E.tl, E.char
	local n = tl:count()
	local ok1 = i1 >= 1 and i1 <= n and tl:isFilled(i1)
	local ok2 = i2 >= 1 and i2 <= n and tl:isFilled(i2)
	if not ok1 or not ok2 then
		local f = (i1 >= 1 and i1 <= n) and i1 or ((i2 >= 1 and i2 <= n) and i2 or nil)
		if f and tl:isFilled(f) then
			local camCF, zoom = E.cam:averaged(tl, f, f, 0)
			return ch:cframeAt(tl, f), camCF or ch:cframeAt(tl, f), ch:linAt(tl, f), ch:angAt(tl, f), zoom
		end
		return CFrame.new(), CFrame.new(), Util.ZERO3, Util.ZERO3, 12.5
	end
	local t1, t2 = tl:get("TotalTime", i1, 1), tl:get("TotalTime", i2, 1)
	local w = (t2 > t1) and clamp((t - t1) / (t2 - t1), 0, 1) or 0
	local rootCF = ch:cframeAt(tl, i1):Lerp(ch:cframeAt(tl, i2), w)
	local camCF, zoom = E.cam:averaged(tl, i1, i2, w)
	local l1x, l1y, l1z = tl:getN("Lin", i1)
	local l2x, l2y, l2z = tl:getN("Lin", i2)
	local a1x, a1y, a1z = tl:getN("Ang", i1)
	local a2x, a2y, a2z = tl:getN("Ang", i2)
	local lin = Vector3.new(l1x + (l2x - l1x) * w, l1y + (l2y - l1y) * w, l1z + (l2z - l1z) * w)
	local ang = Vector3.new(a1x + (a2x - a1x) * w, a1y + (a2y - a1y) * w, a1z + (a2z - a1z) * w)
	return rootCF, camCF, lin, ang, zoom
end

-- the pose for the current playback time, worked out once and used by every stage (V2 C.PlaybackPose)
function Modes:playbackPose()
	local E = self.E
	local tl, f = E.tl, E.frame
	if E.poseT == E.testTime and E.poseFrame == f and E.poseVersion == tl.version and E.pose then return E.pose end
	local rootCF, camCF, lin, ang, zoom = self:averaged(f, f + 1, E.testTime)
	local p = E.pose or {}
	p.root, p.CamCF, p.lin, p.ang, p.Zoom = rootCF, camCF, lin, ang, zoom
	p.ShiftLock = (f >= 1 and f <= tl:count()) and E.cam:shiftAt(tl, f) or 0
	E.pose, E.poseT, E.poseFrame, E.poseVersion = p, E.testTime, f, tl.version
	return p
end

-- ------------------------------------------------------------------------------------------------ transitions
local function camType(t)
	pcall(function()
		local cam = workspace.CurrentCamera
		if cam and cam.CameraType ~= t then cam.CameraType = t end
	end)
end
Modes.camType = camType

function Modes:idle()
	local E = self.E
	self:cancelDeferred()
	E.cs:resetGhost()
	camType(Enum.CameraType.Custom)
	E.mode, E.frame = 1, 1
	E.pausedCamCF, E.pausedZoom = nil, nil
	E.char:anchor(false)
	E.cs:setCameraFreeze(false, false)
	E.cs:lockShiftlock(false)
	E.anim:lock(false)
	E.cs:setFreeMouse(false)
	E.plugins:call("onRelease")
	E.tools:replayEnd()
	E.plugins:call("onCursorReset")
	E.cs:refreshMouse(E.modalOpen and E.modalOpen())
	E.guardFrames = 45
	self:publish()
end

function Modes:create(force)
	local E = self.E
	if self:doubleInput() and not force then return end
	self:cancelDeferred()
	if E.inputs:isReplaying() then E.inputs:replayEnd() end
	E.plugins:call("onEndPlayback")
	E.tools:replayEnd()
	camType(Enum.CameraType.Custom)
	local tl = E.tl
	local n = tl:count()
	E.frame = n
	E.mode = 2
	E.paused = true
	E.lookAround = false
	if n > 0 then
		self:loadFrame(n, false, true)
		local z = E.cam:zoomAt(tl, n)
		E.cs:setZoom(z, true)
		if self:setCam() then E.cs:updateGhost(z, 0, true) else E.cs:resetGhost(true) end
	else
		E.cs:resetGhost(true)
		E.plugins:call("onPause", 0)
	end
	E.char:anchor(true)
	E.cs:lockShiftlock(n > 0)
	E.anim:lock(true)
	self:publish()
end

function Modes:test()
	local E = self.E
	if self:doubleInput() then return end
	self:cancelDeferred()
	local tl = E.tl
	local n = tl:count()
	if n < 2 then self:status("There is not enough TAS data to test.", true) return end
	local speed = E.settings:get("playbackSpeed")
	if E.settings:on("restartWhenTesting") then
		E.frame = (speed > 0) and 1 or n - 1
		E.testTime = (speed > 0) and 0 or self:totalAt(n - 1)
		if speed > 0 then E.anim:testBegin(tl, E.frame, speed) end
	else
		E.frame = clamp(E.frame, 1, n - 1)
		E.testTime = self:totalAt(E.frame)
	end
	camType(E.settings:on("lockCameraTest") and Enum.CameraType.Scriptable or Enum.CameraType.Custom)
	E.mode = 3
	if E.frame >= 1 and E.frame <= n then
		E.cam:update(E.frame, false)
		E.cs:setZoom(E.cam:zoomAt(tl, E.frame), true)
	end
	E.char:anchor(false)
	E.cs:lockShiftlock(true)
	E.anim:lock("ReplayAnimationsOnly")
	E.poseT = nil
	if speed > 0 then
		E.inputs:replayBegin(tl, E.frame)
		E.plugins:call("onPlaybackBegin", tl, E.frame)
	end
	E.plugins:call("onPlaybackBeginAlways", tl, E.frame)
	E.tools:replayBegin(tl, E.frame, E.char.model)
	self:publish()
end

local function beginRecordingAt(self)
	local E = self.E
	E.inputs:beginRecording(E.tl, E.merge and E.mergeBaseHeld or nil)
	E.plugins:call("onBeginRecording", E.tl, E.tl:count())
	E.tools:clear()
end

-- unpausing: cut the frames after the current one, camera back on the last frame
local function unpauseFrom(self)
	local E = self.E
	self:removeCutFrames()
	E.plugins:call("onUnpause", E.tl, E.tl:count())
	E.lookAround = false
	E.anim:lock(false)
	local n = E.tl:count()
	if n > 0 then
		E.cam:update(n, true)
		E.cs:setZoom(E.cam:zoomAt(E.tl, n), true)
	end
end

local function noJump(E)
	local hum = E.char.hum
	if hum then hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false) end
	E.noJumpHum = hum
end

function Modes:unpause()
	local E = self.E
	if self:doubleInput() then return end
	local tl = E.tl
	if tl:count() > 1 and E.frame > 1 and E.char:jumpedOffLadder() then E.frame = E.frame - 1 end
	unpauseFrom(self)
	self:loadFrame(tl:count(), true)
	E.char:anchor(false)
	E.cs:setCameraFreeze(false, false)
	E.cs:lockShiftlock(false)
	beginRecordingAt(self)
	E.firstFrame = true
	E.paused = false
	E.cs:setFreeMouse(false)
	noJump(E)
	-- (continues after the next Heartbeat, at the start of the frame after: Frame.runDeferred)
	E.deferred = { kind = "unpause", armed = false }
	self:publish()
end

function Modes:pause()
	local E = self.E
	if self:doubleInput() then return end
	self:cancelDeferred()
	E.anim:lock(true)
	E.paused = true
	local cam = workspace.CurrentCamera
	E.pausedCamCF = cam and cam.CFrame or E.pausedCamCF
	E.pausedZoom = E.cs:getZoom()
	local tl = E.tl
	if tl:count() > 0 and not tl:isFilled(tl:count()) then tl:removeLast() end
	local n = tl:count()
	E.frame = n
	E.cs:lockShiftlock(n > 0)
	self:loadFrame(n)
	E.plugins:call("onRewind", tl, n) -- (the step after the last frame is thrown away: the kit's clock too)
	E.plugins:call("onPause", self:totalAt(n))
	self:publish()
end

function Modes:unpause1()
	local E = self.E
	if self:doubleInput() then return end
	local tl = E.tl
	local count = 1
	if tl:count() > 1 and E.frame > 1 and E.char:jumpedOffLadder() then E.frame = E.frame - 1; count = 2 end
	if tl:count() > 1 and E.frame >= 1 and E.frame <= tl:count() and tl:get("State", E.frame, 1) == Enum.HumanoidStateType.Landed.Value then count = 2 end
	unpauseFrom(self)
	E.char:anchor(false)
	E.cs:setCameraFreeze(false, false)
	E.cs:lockShiftlock(false)
	beginRecordingAt(self)
	E.firstFrame = true
	self:loadFrame(tl:count(), true)
	noJump(E)
	E.deferred = { kind = "unpause1", armed = false, frames = count }
	self:publish()
end

-- another transition (or Unload) before a deferred step finished: the step ends here, jumping back on and
-- out of the first recorded frame (V2's waiting thread always ran to its end)
function Modes:cancelDeferred()
	local E = self.E
	if not E.deferred then return end
	E.deferred = nil
	self:endNoJump()
	E.firstFrame = false
end

-- the deferred steps (Frame calls these at PreRender order 0, see Modes.new)
function Modes:endNoJump()
	local E = self.E
	local hum = E.noJumpHum
	E.noJumpHum = nil
	if hum and hum.Parent then hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end
end

function Modes:resumeDeferred()
	local E = self.E
	local d = E.deferred
	if not d or not d.armed then return end
	if d.kind == "unpause" then
		E.deferred = nil
		self:endNoJump()
		E.firstFrame = false
		-- old camera scripts only re-lock the mouse on events: ask again now (first person fix)
		E.cs:refreshMouse(E.modalOpen and E.modalOpen())
		E.guardFrames = 45
	elseif d.kind == "unpause1" then
		if not d.resumed then
			d.resumed = true
			self:endNoJump()
			E.paused = false
			E.cs:setFreeMouse(false)
			E.firstFrame = false
			self:publish()
			return
		end
		d.frames = d.frames - 1
		if d.frames > 0 then return end
		E.deferred = nil
		E.anim:lock(true)
		E.paused = true
		local tl = E.tl
		local n = tl:count()
		E.frame = n
		E.cs:lockShiftlock(n > 0)
		self:loadFrame(n, false, true)
		E.plugins:call("onRewind", tl, n)
		E.plugins:call("onPause", self:totalAt(n))
		self:publish()
	end
end

-- paused on frame f (Back / Forward hold it while the key is down)
function Modes:holdAt(f)
	local E = self.E
	E.frame = f
	E.paused = true
	E.cs:lockShiftlock(E.tl:count() > 0)
	E.anim:lock(true)
	self:loadFrame(f, false, true)
	self:publish()
end

function Modes:returnToPause()
	local E = self.E
	if self:doubleInput() then return end
	E.frame = E.lastPause
	self:removeCutFrames()
	self:holdAt(E.frame)
end
function Modes:back1() if not self:doubleInput() then self:holdAt(self.E.frame - 1) end end
function Modes:forward1() if not self:doubleInput() then self:holdAt(self.E.frame + 1) end end
function Modes:back() if not self:doubleInput() then self.E.back = true; self:holdAt(self.E.frame) end end
function Modes:forward() if not self:doubleInput() then self.E.forw = true; self:holdAt(self.E.frame) end end

-- to frame f: shown while paused, or the playback clock moved there in Test (V2 Profiler.OnScrub)
function Modes:seek(f)
	local E = self.E
	local tl = E.tl
	f = clamp(math.floor(f), 1, math.max(1, tl:count()))
	if E.mode == 2 and E.paused and f <= tl:count() then
		E.frame = f
		self:loadFrame(f, false, true)
		self:publish()
	elseif E.mode == 3 and f + 1 <= tl:count() then
		E.frame = f
		E.testTime = self:totalAt(f)
		E.inputs:replayTo(tl, f)
		E.poseT = nil
		self:publish()
	end
end

function Modes:deleteTas(mobile)
	local E = self.E
	if os.clock() < self.confirmDelete then
		self.confirmDelete = 0
		E.tl:cut(0)
		E.plugins:call("onDataChanged")
		E.plugins:call("onReset")
		E.lastPause = 1
		E.frame = 0
		self:status("TAS Deleted")
		self:publish()
	else
		self.confirmDelete = os.clock() + CONFIRM_SECONDS
		self:status(mobile and "Delete TAS? Click To Confirm" or "Delete TAS? [" .. tostring(E.controls:get("deleteTas")) .. "] To Confirm")
	end
end

function Modes:optimize(mobile)
	local E = self.E
	if E.mode ~= 1 then
		self:status("Switch to idle to optimize TAS")
		return
	end
	if os.clock() < self.confirmOptimize then
		self.confirmOptimize = 0
		E.tl:optimize()
		E.plugins:call("onDataChanged")
		self:status("TAS Optimized")
	else
		self.confirmOptimize = os.clock() + CONFIRM_SECONDS
		self:status(mobile and "Optimize TAS? Click To Confirm" or "Optimize TAS? [" .. tostring(E.controls:get("optimize")) .. "] To Confirm")
	end
end

function Modes:toggleLookAround()
	local E = self.E
	E.lookAround = not E.lookAround
	E.guardFrames = 45
end

-- replaces the run (a loaded file); in Create the character goes to its last frame
function Modes:setRun(frames)
	local E = self.E
	E.tl:replaceFromV2(frames or {})
	E.plugins:call("onDataChanged")
	E.plugins:call("onLoaded", E.tl)
	if E.mode == 2 then
		local n = E.tl:count()
		E.frame = n
		if n > 0 then
			self:loadFrame(n)
			E.cs:setZoom(E.cam:zoomAt(E.tl, n), true)
		end
	end
	self:publish()
end

return Modes
