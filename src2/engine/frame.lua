-- ================================================================================================
--  FRAME  (HappaTAS 3 engine): what HappaTAS does in each part of a Roblox frame (V2.38.16 p18_core.lua
--  1043-1433, same order of effects), registered in the kernel pipeline as module "engine":
--    PreRender 0        deferred steps of a transition (Modes.resumeDeferred)
--    PreRender 50       recording: a new frame (time, velocities, camera, inputs); Test: the pose to draw
--    PreSimulation 50   recording: fill the frame (pose, state, animation, tools...); Test: pose for physics
--    Heartbeat 50       paused stepping, a frame without a physics step filled here, Test playback clock
--    Heartbeat 90       arms the deferred step of a transition made before this frame
--    LateRender 50      paused camera hold, plugins' late work, mouse rules
--  plus the key dispatch (InputBegan / InputEnded / JumpRequest).
-- ================================================================================================
local Env = import("platform/env")
local Util = import("engine/util")

local round = Util.round
local Frame = {}

function Frame.start(E)
	local M_ = E.modes
	local tl = E.tl
	local pipe = E.pipe
	local MOD = "engine"

	-- ---------------------------------------------------------------------------------------- recording
	local function fillFrame()
		local n = tl:count()
		if n == 0 or tl:isFilled(n) then return end
		E.plugins:call("fill", tl, n)
		E.char:fillDeath(tl, n)
		tl:setFilled(n)
	end

	local function preRender(dt)
		local mode = E.mode
		if not (mode == 2 and (not E.paused or E.firstFrame)) then E.inputs:clear() end
		local ch = E.char
		if mode == 2 and ch:loaded() then
			if not E.paused and ch:notDead() and not E.firstFrame then
				local n = tl:count()
				local dtN = E.lastFrameTime * E.recScale
				local ft = round(dtN, 1000000)
				local total = (n >= 1) and round(tl:get("TotalTime", n, 1) + dtN, 1000000) or ft
				E.recSim, E.recWall = time(), os.clock()
				local i = tl:append()
				tl:set("FrameTime", i, 1, ft)
				tl:set("TotalTime", i, 1, total)
				E.plugins:call("begin", tl, i)
			end
			if E.paused then E.cam:holdPaused() end
			E.cam:updateMouseMode()
		elseif mode == 3 and ch:loaded() and E.frame + 1 <= tl:count() and E.testTime >= 0 then
			local p = M_:playbackPose()
			ch:sync(p.root, p.lin, p.ang)
			E.cam:update(p)
			if M_:setCam() then E.cs:updateGhost(p.Zoom, dt, false) end
		end
		E.plugins:call("frameEnd", dt)
	end

	local function preSimulation(dt)
		local ch = E.char
		if E.mode == 2 and ch:loaded() and not E.paused and not E.firstFrame and ch:notDead() then
			fillFrame()
		elseif E.mode == 3 and ch:loaded() and E.frame + 1 <= tl:count() and E.testTime >= 0 then
			if E.settings:on("interpolatePlayback") then
				local p = M_:playbackPose()
				ch:sync(p.root, p.lin, p.ang)
			elseif E.frame >= 1 and tl:isFilled(E.frame) then
				ch:syncFrame(tl, E.frame)
			end
			ch.hum:Move(ch.hrp.AssemblyLinearVelocity)
		end
	end

	-- ---------------------------------------------------------------------------------------- playback
	-- the character, camera and animation stay on frame f (no blending)
	local function holdPose(f)
		if tl:isFilled(f) then E.char:syncFrame(tl, f) end
		E.cam:update(f)
		E.anim:playFrame(tl, f, 0)
	end

	local function playbackStep(dt)
		local speed = E.settings:get("playbackSpeed")
		E.testTime = E.testTime + E.lastFrameTime * speed
		local ch = E.char
		if E.settings:on("interpolatePlayback") then
			local prevFrame = E.frame
			local n = tl:count()
			while E.frame + 1 <= n and E.testTime > tl:get("TotalTime", E.frame + 1, 1) do E.frame = E.frame + 1 end
			while E.frame > 1 and E.testTime < tl:get("TotalTime", E.frame - 1, 1) do E.frame = E.frame - 1 end
			local f = E.frame
			if f > 0 then E.inputs:replayTo(tl, f) end
			if f + 1 > n or f == 0 then return end
			E.inputs:replayMouse(tl, f)
			E.plugins:call("playTo", tl, f, E.testTime)
			if tl:get("FrameTime", f + 1, 1) > 0.1 then
				holdPose(f) -- a lag spike was recorded here: hold the frame instead of sliding through it
				return
			end
			local p = M_:playbackPose()
			ch:sync(p.root, p.lin, p.ang)
			ch:changeState(tl:get("State", f, 1))
			E.cam:update(p)
			local lo, hi = prevFrame + 1, f
			if lo > hi then lo, hi = f, f end
			for k = lo, hi do
				if k > prevFrame and k <= n then
					E.anim:passFrame(tl, k, speed)
					E.tools:replayFrame(tl, k, ch.model)
				end
			end
			if tl:getList("Died", f) then ch:changeState(Enum.HumanoidStateType.Dead) end
			E.tools:step(ch.model, ch.hum)
		else
			E.frame = E.frame + 1
			local f = E.frame
			if f > tl:count() then return end
			E.inputs:replayTo(tl, f)
			E.inputs:replayMouse(tl, f)
			E.plugins:call("playTo", tl, f, nil)
			local frameTime = tl:get("FrameTime", f, 1)
			if E.freezeRemaining > dt then
				holdPose(f)
				E.freezeRemaining = E.freezeRemaining - dt
				return
			end
			if frameTime > 2 * dt then
				E.freezeRemaining = frameTime - dt
				return
			end
			M_:loadFrame(f)
			E.anim:playFrame(tl, f, speed)
			E.tools:replayFrame(tl, f, ch.model)
			E.tools:step(ch.model, ch.hum)
		end
		E.plugins:call("playedFrame", tl, E.frame)
	end

	local function finishTest()
		local n = tl:count()
		local last = (n > 0) and n or nil
		local endZoom = (last and E.cam:zoomAt(tl, last)) or (E.pose and E.pose.Zoom) or E.cs:getZoom()
		local endShift = last and E.cam:shiftAt(tl, last) or nil
		E.cs:resetGhost()
		pcall(function() workspace.CurrentCamera.CameraType = Enum.CameraType.Custom end)
		E.inputs:replayEnd()
		E.plugins:call("endPlayback")
		E.plugins:call("release")
		E.tools:replayEnd()
		E.mode, E.frame = 1, 1
		E.char:anchor(false)
		E.cs:setCameraFreeze(false, false)
		E.cs:lockShiftlock(false)
		E.anim:lock(false)
		E.cs:setFreeMouse(false)
		E.cs:restoreAfterTest(endZoom, endShift)
		E.guardFrames = 45
		E.plugins:call("cursorReset")
		if not E.quitTest and n > 0 and E.settings:on("showCompletionMessage") then
			M_:status("TAS Completed [Time: " .. Util.toTime(tl:get("TotalTime", n, 1)) .. "]")
		end
		M_:publish()
	end

	local function heartbeat(dt)
		local mode = E.mode
		if mode ~= 3 and E.inputs:isReplaying() then E.inputs:replayEnd() end
		E.plugins:call("heartbeatStart", mode)
		local ch = E.char
		if ch:loaded() then
			if mode == 2 then
				local n = tl:count()
				if E.paused then
					E.plugins:call("pausedTick")
					if n > 1 and E.back and E.frame > 1 then
						E.frame = E.frame - 1
						M_:loadFrame(E.frame, false, true)
						M_:publish()
					end
					if E.frame < n and E.forw then
						E.frame = E.frame + 1
						M_:loadFrame(E.frame, false, true)
						M_:publish()
					end
					E.plugins:call("step", M_:totalAt(E.frame))
				else
					if E.firstFrame and n == 1 then
						local t = round(E.lastFrameTime * E.recScale, 1000000)
						tl:set("FrameTime", 1, 1, t)
						tl:set("TotalTime", 1, 1, t)
					end
					-- a frame without a physics step had no PreSimulation: filled here (dropping it lost its
					-- time and inputs: a TAS recorded at 240 FPS replayed about 12 % too fast)
					if n > 0 and not tl:isFilled(n) and not E.firstFrame and ch:notDead() then fillFrame() end
					if tl:count() > 0 and not tl:isFilled(tl:count()) then tl:removeLast() end
					n = tl:count()
					E.frame = n
					if n > 0 and not E.firstFrame then E.plugins:call("afterPhysics", tl, n) end
					E.plugins:call("step", M_:totalAt(n))
					M_:publish()
				end
				E.plugins:call("createStats", tl, E.frame)
			elseif mode == 3 and E.frame + 1 <= tl:count() and E.testTime >= 0 then
				playbackStep(dt)
				M_:publish()
			elseif mode == 3 then
				finishTest()
			end
		end
		E.lastFrameTime = dt
		if E.currentFrameInput then
			E.inputDebounce = E.inputDebounce + 1
			if E.inputDebounce == 3 then E.inputDebounce = 0; E.currentFrameInput = false end
		end
	end

	local function lateRender(dt)
		if E.mode == 2 then
			if E.paused and not E.firstFrame and tl:count() > 0 and M_:setCam() and not E.lookAround then
				E.cam:holdPaused()
				if E.frame >= 1 and E.frame <= tl:count() then E.cs:updateGhost(E.cam:zoomAt(tl, E.frame), E.lastFrameTime, true) end
			else
				E.cs:resetGhost(true)
			end
		elseif E.mode == 3 and M_:setCam() then
			local z = (E.pose and E.pose.Zoom) or ((E.frame >= 1 and E.frame <= tl:count()) and E.cam:zoomAt(tl, E.frame)) or E.cs:getZoom()
			E.cs:updateGhost(z, E.lastFrameTime, false)
		end
		E.plugins:call("lateRender")
		E.cam:updateMouseMode()
	end

	pipe:add("PreRender", 0, "engine.deferred", function() M_:resumeDeferred() end, MOD)
	pipe:add("PreRender", 50, "engine.preRender", preRender, MOD)
	pipe:add("PreSimulation", 50, "engine.preSimulation", preSimulation, MOD)
	pipe:add("Heartbeat", 50, "engine.heartbeat", heartbeat, MOD)
	pipe:add("Heartbeat", 90, "engine.armDeferred", function()
		local d = E.deferred
		if d then d.armed = true end
	end, MOD)
	pipe:add("LateRender", 50, "engine.lateRender", lateRender, MOD)

	-- ---------------------------------------------------------------------------------------- keys
	local uis = Env.svc("UserInputService")
	local function is(inp, control) return E.controls:matches(inp, control) end
	E.life:connect(uis.JumpRequest, function()
		local ch = E.char
		if ch.hum and E.mode == 2 and E.frame > 1 and ch:canCoyoteJump() then
			ch.hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end)
	E.life:connect(uis.InputBegan, function(inp, proc)
		if E.typing:active(inp) then return end -- typing in chat / a text box, the Roblox menu, binding a key
		if E.inputs:isOverOwnUI(inp) then return end -- a click on a HappaTAS window is for the window
		if proc and not E.settings:on("ignoreGameProcessed") then return end
		if not E.char.hum then return end
		local mode, paused, n, merge = E.mode, E.paused, tl:count(), E.merge
		if is(inp, "idle") and not merge then M_:idle()
		elseif is(inp, "create") and not merge then M_:create()
		elseif is(inp, "test") and n > 0 and not merge then M_:test()
		elseif is(inp, "unpause") and mode == 2 and paused then M_:unpause()
		elseif is(inp, "pause") and mode == 2 and not paused then M_:pause()
		elseif is(inp, "unpause1") and mode == 2 and paused then M_:unpause1()
		elseif is(inp, "return") and mode == 2 and n > 0 then M_:returnToPause()
		elseif is(inp, "back1") and mode == 2 and n > 1 and E.frame > 1 then M_:back1()
		elseif is(inp, "forward1") and mode == 2 and E.frame < n then M_:forward1()
		elseif is(inp, "back") and mode == 2 then M_:back()
		elseif is(inp, "forward") and mode == 2 then M_:forward()
		elseif is(inp, "deleteTas") and not merge then M_:deleteTas()
		elseif is(inp, "optimize") then M_:optimize()
		elseif is(inp, "lookAround") and mode == 2 and paused and E.settings:on("lockCameraPaused") then M_:toggleLookAround()
		elseif is(inp, "toggleSpeedHack") then E.settings:set("speedHack", E.settings:on("speedHack") and 0 or 1) end
	end)
	E.life:connect(uis.InputEnded, function(inp)
		if is(inp, "back") then E.back = false end
		if is(inp, "forward") then E.forw = false end
	end)
end

return Frame
