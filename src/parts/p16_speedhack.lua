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
--  The world slows down with it (V2.38.14, "World"): every constraint and body mover gets its slowed values
--  (velocities x s, forces / torques / stiffness / accelerations x s^2, damping and responsiveness x s), free
--  client objects keep their motion (velocity x s when the slow motion starts, / s when it stops) and
--  conveyors move x s, so spinners, moving platforms, swings, pushers, pushboxes and the jump launcher's push
--  run in slow motion too. The kit's scripts follow the TAS clock through the Kit Clock (p16_kit), timed
--  buttons through Sync Button Timers. Roblox's own humanoid timers and other players keep their speed.
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

	-- --------------------------------------------------------------------------------------------- the world
	-- time scaling: a motion played s times slower has velocities x s and accelerations x s^2 (so forces,
	-- torques and springs x s^2), and whatever is "per second" (damping, responsiveness) x s. 1 = x s, 2 = x s^2
	local W = {}
	SH.World = W
	local TIME_PROPS = {
		AlignPosition = { MaxVelocity = 1, Responsiveness = 1, MaxForce = 2, MaxAxesForce = 2 },
		AlignOrientation = { MaxAngularVelocity = 1, Responsiveness = 1, MaxTorque = 2 },
		LinearVelocity = { VectorVelocity = 1, LineVelocity = 1, PlaneVelocity = 1, MaxForce = 2, MaxAxesForce = 2, MaxPlanarAxesForce = 2 },
		AngularVelocity = { AngularVelocity = 1, MaxTorque = 2 },
		VectorForce = { Force = 2 },
		Torque = { Torque = 2 },
		LineForce = { Magnitude = 2 },
		HingeConstraint = { AngularVelocity = 1, MotorMaxTorque = 2, MotorMaxAcceleration = 2, AngularSpeed = 1,
			ServoMaxTorque = 2, AngularResponsiveness = 1 },
		PrismaticConstraint = { Velocity = 1, MotorMaxForce = 2, MotorMaxAcceleration = 2, Speed = 1, ServoMaxForce = 2,
			LinearResponsiveness = 1 },
		CylindricalConstraint = { Velocity = 1, MotorMaxForce = 2, MotorMaxAcceleration = 2, Speed = 1, ServoMaxForce = 2,
			LinearResponsiveness = 1, AngularVelocity = 1, MotorMaxTorque = 2, MotorMaxAngularAcceleration = 2,
			AngularSpeed = 1, ServoMaxTorque = 2, AngularResponsiveness = 1 },
		SpringConstraint = { Stiffness = 2, Damping = 1, MaxForce = 2 },
		TorsionSpringConstraint = { Stiffness = 2, Damping = 1, MaxTorque = 2 },
		RopeConstraint = { WinchSpeed = 1, WinchForce = 2, WinchResponsiveness = 1 },
		BodyVelocity = { Velocity = 1, MaxForce = 2, P = 1 },
		BodyAngularVelocity = { AngularVelocity = 1, MaxTorque = 2, P = 1 },
		BodyPosition = { P = 2, D = 1, MaxForce = 2 },
		BodyGyro = { P = 2, D = 1, MaxTorque = 2 },
		BodyForce = { Force = 2 },
		BodyThrust = { Force = 2 },
		RocketPropulsion = { MaxSpeed = 1, MaxThrust = 2, ThrustP = 2, ThrustD = 1, MaxTorque = 2, TurnP = 2, TurnD = 1 },
	}
	W.TIME_PROPS = TIME_PROPS
	local known = {}  -- every constraint / body mover in the workspace (kept up to date once the speed hack is on)
	local ents = {}   -- the ones slowed now: inst -> { base = normal values, last = what HappaTAS wrote }
	local vparts = {} -- anchored parts with a velocity (conveyors) slowed now
	local wf = 1      -- the factor the world has now
	local tracking = false

	local function scaled(v, pow, f)
		if pow == 1 then return v * f end
		return v * (f * f)
	end
	-- (e.writing / e.last: the change signal of HappaTAS's own write, immediate or deferred, is not a game write)
	local function writeProp(e, prop)
		local inst, base = e.inst, e.base[prop]
		local want = (wf == 1) and base or scaled(base, e.props[prop], wf)
		e.last[prop] = want
		e.writing = true
		local okW = pcall(function() inst[prop] = want end)
		e.writing = false
		if okW then
			local ok, back = pcall(function() return inst[prop] end)
			if ok then e.last[prop] = back end
		end
	end
	local function addEntry(inst)
		if ents[inst] then return end
		local props = TIME_PROPS[inst.ClassName]
		if not props then return end
		local e = { inst = inst, props = props, base = {}, last = {}, conns = {} }
		for prop in pairs(props) do
			local ok, v = pcall(function() return inst[prop] end)
			if ok and ((type(v) == "number" and v == v) or typeof(v) == "Vector3" or typeof(v) == "Vector2") then
				e.base[prop] = v
			end
		end
		for prop in pairs(e.base) do
			local okC, cn = pcall(function()
				return inst:GetPropertyChangedSignal(prop):Connect(function()
					if e.writing then return end
					local ok, now = pcall(function() return inst[prop] end)
					-- a value the game wrote (not HappaTAS's own write): the new normal value
					if ok and now ~= e.last[prop] then
						e.base[prop] = now
						writeProp(e, prop)
					end
				end)
			end)
			if okC and cn then e.conns[#e.conns + 1] = cn end
			writeProp(e, prop)
		end
		ents[inst] = e
	end
	local function restoreEntry(e)
		for _, cn in ipairs(e.conns) do cn:Disconnect() end
		local inst = e.inst
		for prop, base in pairs(e.base) do
			local ok, now = pcall(function() return inst[prop] end)
			-- (a value the game wrote since is kept: it is already a normal value)
			if ok and now == e.last[prop] then pcall(function() inst[prop] = base end) end
		end
	end

	-- the parts to look at: HappaTAS's client objects, or the EToH kit's ClientParts folder without them
	local function eachWorldPart(fn)
		if ClientObjects.IsReady() and ClientObjects.EachPart then
			ClientObjects.EachPart(fn)
			return
		end
		local cp = workspace:FindFirstChild("ClientParts")
		if cp then
			for _, d in ipairs(cp:GetDescendants()) do
				if d:IsA("BasePart") then fn(d) end
			end
		end
	end
	local function charOf(p)
		local ch = LocalPlayer.Character
		return ch ~= nil and p:IsDescendantOf(ch)
	end
	-- free assemblies go on with their motion, ratio times as fast
	local function scaleFree(ratio)
		if ratio == 1 then return end
		local done = {}
		eachWorldPart(function(p)
			if p.Anchored or charOf(p) then return end
			local rootP = p.AssemblyRootPart or p
			if done[rootP] or rootP.Anchored then return end
			done[rootP] = true
			pcall(function()
				rootP.AssemblyLinearVelocity = rootP.AssemblyLinearVelocity * ratio
				rootP.AssemblyAngularVelocity = rootP.AssemblyAngularVelocity * ratio
			end)
		end)
	end
	local function writeVel(v)
		local p = v.part
		pcall(function()
			p.AssemblyLinearVelocity = v.lin * wf
			p.AssemblyAngularVelocity = v.ang * wf
			v.lastL, v.lastA = p.AssemblyLinearVelocity, p.AssemblyAngularVelocity
		end)
	end
	local function collectVParts()
		eachWorldPart(function(p)
			if not p.Anchored or vparts[p] then return end
			local ok, l, a = pcall(function() return p.AssemblyLinearVelocity, p.AssemblyAngularVelocity end)
			if ok and (l.Magnitude > 1e-6 or a.Magnitude > 1e-6) then
				local v = { part = p, lin = l, ang = a }
				vparts[p] = v
				writeVel(v)
			end
		end)
	end

	function W.Track()
		if tracking then return end
		tracking = true
		on(workspace.DescendantAdded, function(d)
			if TIME_PROPS[d.ClassName] then
				known[d] = true
				if wf ~= 1 then addEntry(d) end
			end
		end)
		on(workspace.DescendantRemoving, function(d)
			if known[d] then
				known[d] = nil
				local e = ents[d]
				if e then ents[d] = nil; for _, cn in ipairs(e.conns) do cn:Disconnect() end end
			end
			vparts[d] = nil
		end)
		task.spawn(function()
			local list = workspace:GetDescendants()
			for i = 1, #list do
				local d = list[i]
				if TIME_PROPS[d.ClassName] and d.Parent then
					known[d] = true
					if wf ~= 1 then addEntry(d) end
				end
				if i % 2000 == 0 then task.wait() end
			end
		end)
	end

	-- the world's factor (1 = normal): constraints from their normal values, free parts' motion x the ratio
	function W.SetFactor(f)
		if f == wf then return end
		local ratio = f / wf
		wf = f
		if f ~= 1 then
			for d in pairs(known) do
				if d.Parent then
					if ents[d] then
						for prop in pairs(ents[d].base) do writeProp(ents[d], prop) end
					else
						addEntry(d)
					end
				end
			end
			for _, v in pairs(vparts) do writeVel(v) end
			collectVParts()
		else
			for _, e in pairs(ents) do restoreEntry(e) end
			ents = {}
			for p, v in pairs(vparts) do
				if p.Parent then
					pcall(function()
						if p.AssemblyLinearVelocity == v.lastL then p.AssemblyLinearVelocity = v.lin end
						if p.AssemblyAngularVelocity == v.lastA then p.AssemblyAngularVelocity = v.ang end
					end)
				end
			end
			vparts = {}
		end
		scaleFree(ratio)
	end

	-- every frame while slowed: a conveyor's velocity the game wrote again (the kit's Conveyor writes it
	-- every PostSimulation for a free conveyor) is a new normal value
	function W.Step()
		if wf == 1 then return end
		for p, v in pairs(vparts) do
			if p.Parent then
				local ok, l, a = pcall(function() return p.AssemblyLinearVelocity, p.AssemblyAngularVelocity end)
				if ok and (l ~= v.lastL or a ~= v.lastA) then
					if l ~= v.lastL then v.lin = l end
					if a ~= v.lastA then v.ang = a end
					writeVel(v)
				end
			else
				vparts[p] = nil
			end
		end
	end
	function W.Factor() return wf end
	function W.Count()
		local n, m = 0, 0
		for _ in pairs(ents) do n = n + 1 end
		for _ in pairs(vparts) do m = m + 1 end
		return n, m
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
		local okW, errW = pcall(W.SetFactor, 1)
		if not okW then reportError("speed hack world", errW) end
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
		local okW, errW = pcall(function()
			if W.Factor() ~= s then W.SetFactor(s) else W.Step() end
		end)
		if not okW then reportError("speed hack world", errW) end
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
		-- the list of the world's constraints is kept from the moment the speed hack is switched on
		if Settings.On("Speed Hack") then W.Track() end
		Settings.Changed("Speed Hack", function(v) if v ~= 0 then W.Track() end end)
		Janitor.add(function() SH.Restore(true) end)
	end
end

