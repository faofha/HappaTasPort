-- ================================================================================================
--  ANIM FLIP PROBE (TEMPORARY DIAGNOSTIC TOOL, never shipped): one standing jump while recording, every
--  humanoid event (StateChanged, Running, Jumping, FreeFalling) and every render frame's main animation track,
--  root height and vertical speed, in order. Reads only.
--      return loadfile("HappaTasTest/animflip_probe.lua")()(build, fps, speed)
-- ================================================================================================
return function(build, fps, speed, pressSecs, walk)
	local RS = game:GetService("RunService")
	local P = loadfile("HappaTasTest/phys3.lua")()
	setfpscap(fps)
	P.use("h3", "HappaTasTest/h3_" .. build .. ".lua")
	local E = getgenv().__HappaTAS3_T.engine
	E.settings:set("speedHackFrameStep", 0)
	E.settings:set("speedHackSpeed", speed)
	E.settings:set("speedHack", speed == 1 and 0 or 1)
	local hum, hrp = E.char.hum, E.char.hrp
	local lines, t0 = {}, nil
	local function L(s) if t0 and #lines < 400 then lines[#lines + 1] = string.format("%7.1f ms  %s", (os.clock() - t0) * 1000, s) end end
	local function main()
		local best
		for _, tr in ipairs(hum:FindFirstChildOfClass("Animator"):GetPlayingAnimationTracks()) do
			if not best or tr.WeightCurrent > best.WeightCurrent then best = tr end
		end
		return best and (best.Animation and best.Animation.Name or "?") .. string.format(" %.3f w%.2f", best.TimePosition, best.WeightCurrent) or "none"
	end
	local cs = {}
	cs[#cs + 1] = hum.StateChanged:Connect(function(a, b) L("STATE " .. a.Name .. " -> " .. b.Name) end)
	cs[#cs + 1] = hum.Running:Connect(function(s) L(string.format("Running(%.3f)", s)) end)
	cs[#cs + 1] = hum.Jumping:Connect(function(a) L("Jumping(" .. tostring(a) .. ")") end)
	cs[#cs + 1] = hum.FreeFalling:Connect(function(a) L("FreeFalling(" .. tostring(a) .. ")") end)
	cs[#cs + 1] = RS.RenderStepped:Connect(function()
		L(string.format("frame  y %.3f vy %.2f  %s  anim %s  Jump %s", hrp.Position.Y, hrp.AssemblyLinearVelocity.Y, hum:GetState().Name, main(), tostring(hum.Jump)))
	end)
	local out = {}
	local ok, err = pcall(function()
		E.modes:request("idle"); task.wait(0.3); E.modes:setRun({}); task.wait(0.2)
		P.placeAtV(Vector3.new(0, 0, 0), P.SURF.plat)
		E.modes:create(true); task.wait(0.4)
		E.modes:unpause(); task.wait(0.5)
		t0 = os.clock()
		if walk then
			-- (a walk: a direction held for `walk` s of game time)
			L("PRESS W")
			P.setDrive(Vector3.new(1, 0, 0), false)
			task.wait(walk / speed)
			P.setDrive(Vector3.zero, false)
			L("RELEASE W")
			task.wait(0.3 / speed)
		else
			L("PRESS jump")
			P.setDrive(Vector3.zero, true)
			task.wait(pressSecs or 0.1)
			P.setDrive(Vector3.zero, false)
			L("RELEASE jump")
			task.wait(1.0 / speed + 0.3)
		end
		E.modes:pause(); task.wait(0.2)
		E.modes:request("idle")
	end)
	for _, c in ipairs(cs) do c:Disconnect() end
	P.done()
	setfpscap(240)
	out.err = not ok and tostring(err) or nil
	out.lines = lines
	return out
end
