-- ================================================================================================
--  SPEED HACK  (slow motion while recording in Create mode)
--
--  While a TAS is recorded (Create mode, unpaused) the character moves at s times its normal speed
--  (s = "Speed Hack Speed", 0.1 - 1), like a video played slower:
--    gravity x s^2, WalkSpeed and JumpPower x s, the character's velocity x s when the slow motion starts
--    (and / s when it stops with the character still moving), HappaTAS's animations x s.
--    JumpHeight is left alone: Roblox works the jump out from JumpHeight and the gravity, so with the
--    gravity x s^2 the jump starts s times slower and still reaches the same height.
--  Each recorded frame stores its time x s (FrameTime / TotalTime) and the velocity / s (Core), so the TAS
--  is in normal time and Test plays it at normal speed (the idea of Tasability's speed hack and its fork).
--  A value the game writes while the slow motion is on (a speed pad's WalkSpeed, a gravity change) is
--  taken as the new normal value. Paused, Idle, Test, dead: everything is normal.
--  Only the character is slowed (and falling parts, through the gravity): moving / spinning parts,
--  conveyors, Roblox's own humanoid timers and other players keep their speed. Timed buttons follow the
--  TAS clock (Sync Button Timers), so their timers slow down with it.
-- ================================================================================================
do
	local SH = SpeedHack
	SH.scale = 1 -- the factor in effect for the next physics step (1 = normal speed)
	local applied = false
	local hum, root = nil, nil
	local baseWalk, baseJump, lastWalk, lastJump = nil, nil, nil, nil
	local baseGravity, lastGravity = nil, nil

	local function near(a, b)
		return math.abs(a - b) <= 1e-4 * math.max(1, math.abs(b))
	end

	-- the factor the settings ask for (1 = off)
	function SH.Wanted()
		if not Settings.On("Speed Hack") then return 1 end
		local s = clampn(tonumber(Settings.Get("Speed Hack Speed")) or 0.5, 0.1, 1)
		if s >= 0.999 then return 1 end
		return s
	end

	-- only a character the physics moves (an anchored one is held by HappaTAS: nothing to keep)
	local function scaleMomentum(part, ratio)
		if not (part and part.Parent) or part.Anchored then return end
		pcall(function()
			part.AssemblyLinearVelocity = part.AssemblyLinearVelocity * ratio
			part.AssemblyAngularVelocity = part.AssemblyAngularVelocity * ratio
		end)
	end

	local function rescaleAnimations()
		local e = AnimEngine.current
		if e and e.Rescale then pcall(e.Rescale) end
	end

	local function applyValues(h, s)
		if h ~= hum then
			hum = h -- (a new character: its own values are the normal ones)
			baseWalk, baseJump, lastWalk, lastJump = h.WalkSpeed, h.JumpPower, nil, nil
		else
			-- the game wrote its own value since the last frame: that is the new normal value
			if lastWalk and not near(h.WalkSpeed, lastWalk) then baseWalk = h.WalkSpeed end
			if lastJump and not near(h.JumpPower, lastJump) then baseJump = h.JumpPower end
		end
		local w, j = baseWalk * s, baseJump * s
		if not near(h.WalkSpeed, w) then h.WalkSpeed = w end
		if not near(h.JumpPower, j) then h.JumpPower = j end
		lastWalk, lastJump = h.WalkSpeed, h.JumpPower
		local g = workspace.Gravity
		if baseGravity == nil or (lastGravity ~= nil and not near(g, lastGravity)) then baseGravity = g end
		local wantG = baseGravity * s * s
		if not near(g, wantG) then workspace.Gravity = wantG end
		lastGravity = workspace.Gravity
	end

	-- back to normal: the values HappaTAS wrote get the normal ones again (a value the game wrote since is
	-- kept). keepMomentum: a character still moving goes on at normal speed (velocity / s)
	function SH.Restore(keepMomentum)
		local s = SH.scale
		if applied then
			if hum and hum.Parent then
				pcall(function()
					if lastWalk and near(hum.WalkSpeed, lastWalk) then hum.WalkSpeed = baseWalk end
					if lastJump and near(hum.JumpPower, lastJump) then hum.JumpPower = baseJump end
				end)
			end
			if baseGravity and lastGravity and near(workspace.Gravity, lastGravity) then
				pcall(function() workspace.Gravity = baseGravity end)
			end
			if keepMomentum and s < 1 then scaleMomentum(root, 1 / s) end
		end
		applied, hum, root = false, nil, nil
		baseWalk, baseJump, lastWalk, lastJump, baseGravity, lastGravity = nil, nil, nil, nil, nil, nil
		SH.scale = 1
		if s ~= 1 then rescaleAnimations() end
	end

	-- once a frame, at the end of PreRender (after the frame was recorded: the factor used now is the one
	-- the next physics step runs with). active = the character records in Create mode (free and alive).
	-- keepMomentum: see Restore (false when Test takes over the character). Returns the factor.
	function SH.Update(active, h, part, keepMomentum)
		local s = 1
		if active and h and part then s = SH.Wanted() end
		if s >= 1 then
			if applied then SH.Restore(keepMomentum) end
			return 1
		end
		local ok, err = pcall(applyValues, h, s)
		if not ok then
			reportError("speed hack", err)
			return SH.scale
		end
		local prev = applied and SH.scale or 1
		root = part
		applied = true
		SH.scale = s
		if prev ~= s then
			scaleMomentum(part, s / prev) -- slow motion starts / the speed changed: same motion, slower
			rescaleAnimations()
		end
		return s
	end

	function SH.Start()
		local function announce()
			local s = SH.Wanted()
			local text = (s < 1) and ("Speed Hack: " .. tostring(r(s, 1000)) .. "x while recording") or "Speed Hack: Off"
			task.spawn(Core.SetStatus, text, true)
		end
		Settings.Changed("Speed Hack", announce)
		Settings.Changed("Speed Hack Speed", function() if Settings.On("Speed Hack") then announce() end end)
		Janitor.add(function() SH.Restore(true) end)
	end
end

