-- ================================================================================================
--  SPEED HACK  (slow / fast motion while recording in Create mode)
--
--  While a TAS is recorded (Create mode, unpaused) the character moves at s times its normal speed
--  (s = "Speed Hack Speed", 0.1 - 4; above 1 = fast motion, the same rules), like a video played slower:
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
--  conveyors move x s, so spinners, moving platforms, swings, pushboxes and the jump launcher's push run in
--  slow motion too; a bounce pad's Power (a velocity the kit sets itself) is slowed the same way (V2.38.15).
--  The kit's scripts follow the TAS clock through the Kit Clock (p16_kit), timed buttons through Sync Button
--  Timers. Roblox's own humanoid timers and other players keep their speed, and so does the walking force your
--  character pushes things with (measured in the client: about 658 x its mass, the same at any gravity or
--  WalkSpeed): a platform you push yourself (the kit's Pushing Platform) still speeds up too fast. Two other
--  ways were tried in the client and are not used: a counter-force from a model of Roblox's walking
--  controller (0.5x far too slow, 0.25x too fast), and PhysicsSettings.PhysicsEnvironmentalThrottle (Skip2 /
--  Skip4 slow every part but the character exactly, but a throttled platform pushed by the full-speed
--  character moved too slowly at Skip2 and not at all at Skip4). Frame Step (V2.38.16, below) gets much closer:
--  no scaling, Roblox's normal physics on some frames only.
--  The camera's zoom spring follows the TAS clock (SH.anim -> Bridge.timeRate, p09).
-- ================================================================================================
do
	local SH = SpeedHack
	SH.scale = 1 -- the factor the physics is scaled by for the next physics step (1 = normal speed)
	SH.anim = 1  -- how fast the TAS clock runs against real time (animations, the camera's zoom spring)
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

	-- kit configuration values a kit script turns into a velocity itself, with no constraint to slow: the
	-- bounce pad (Interactables/BouncePad) sets the character's velocity to its Power when touched, so with
	-- the gravity x s^2 a slowed bounce went 1 / s^2 as high. The kit keeps each object's configuration as a
	-- plain table (Utility/Config GetConfig: __instance = the Configuration, then one field per attribute,
	-- rewritten when the attribute changes), found with filtergc by its keys. Same rules as the constraints:
	-- the value x s while slowed, a value the kit writes meanwhile is the new normal one, put back after.
	-- (A booster's Power is a WalkSpeed / JumpPower: the character's values are slowed already.)
	-- (a swing sets its handle's velocity to Boost when you grab it: the same rule)
	local KIT_CONFIG = { BouncePadConfiguration = { Power = 1 }, SwingConfiguration = { Boost = 1 } }
	W.KIT_CONFIG = KIT_CONFIG
	local knownCfg = setmetatable({}, { __mode = "k" }) -- config table -> its props (from the last scans)
	local cfgEnts = {} -- the ones slowed now: config table -> { props, base, last }
	local cfgScan, cfgScanIn = true, 0 -- look again (a kit object was added), in that many slowed frames
	local function scanConfigs()
		cfgScan = false
		if not Env.filtergc then return end
		local ok, found = pcall(Env.filtergc, "table", { Keys = { "__instance", "__defaults" } })
		if not ok or type(found) ~= "table" then return end
		for _, t in ipairs(found) do
			if type(t) == "table" and not knownCfg[t] then
				local inst = rawget(t, "__instance")
				local props = typeof(inst) == "Instance" and KIT_CONFIG[inst.Name] or nil
				if props then knownCfg[t] = props end
			end
		end
	end
	local function writeCfg(t, e, k)
		local want = (wf == 1) and e.base[k] or scaled(e.base[k], e.props[k], wf)
		rawset(t, k, want)
		e.last[k] = want
	end
	local function addCfg(t, props)
		local e = { props = props, base = {}, last = {} }
		for k in pairs(props) do
			local v = rawget(t, k)
			if type(v) == "number" and v == v then e.base[k] = v end
		end
		if next(e.base) == nil then return end -- (a table the kit cleared: its object is gone)
		cfgEnts[t] = e
		for k in pairs(e.base) do writeCfg(t, e, k) end
	end
	local function restoreCfgs()
		for t, e in pairs(cfgEnts) do
			for k, b in pairs(e.base) do
				-- (a value the kit wrote since is kept: it is already a normal value)
				if rawget(t, k) == e.last[k] then rawset(t, k, b) end
			end
		end
		cfgEnts = {}
	end
	-- while slowed: a value the kit wrote is the new normal one; new kit objects are looked for
	local function stepCfgs()
		for t, e in pairs(cfgEnts) do
			for k in pairs(e.base) do
				local now = rawget(t, k)
				if now == nil then
					cfgEnts[t] = nil
					break
				elseif now ~= e.last[k] then
					e.base[k] = now
					writeCfg(t, e, k)
				end
			end
		end
		if cfgScan then
			cfgScanIn = cfgScanIn - 1
			if cfgScanIn <= 0 then
				scanConfigs()
				for t, props in pairs(knownCfg) do
					if not cfgEnts[t] then addCfg(t, props) end
				end
			end
		end
	end

	function W.Track()
		if tracking then return end
		tracking = true
		on(workspace.DescendantAdded, function(d)
			if TIME_PROPS[d.ClassName] then
				known[d] = true
				if wf ~= 1 then addEntry(d) end
			elseif KIT_CONFIG[d.Name] then
				-- (the kit makes the object's configuration table a little later)
				cfgScan, cfgScanIn = true, 30
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
		local from = wf
		local ratio = f / from
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
			-- (every time the slow motion starts: about 1 ms in the EToH kit test place)
			if cfgScan or from == 1 then scanConfigs() end
			for t, props in pairs(knownCfg) do
				local e = cfgEnts[t]
				if e then
					for k in pairs(e.base) do writeCfg(t, e, k) end
				else
					addCfg(t, props)
				end
			end
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
			restoreCfgs()
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
		stepCfgs()
	end
	function W.Factor() return wf end
	function W.Count()
		local n, m, c = 0, 0, 0
		for _ in pairs(ents) do n = n + 1 end
		for _ in pairs(vparts) do m = m + 1 end
		for _ in pairs(cfgEnts) do c = c + 1 end
		return n, m, c
	end

	-- the factor the settings ask for (1 = off)
	function SH.Wanted()
		if not Settings.On("Speed Hack") then return 1 end
		local s = clampn(tonumber(Settings.Get("Speed Hack Speed")) or 0.5, 0.1, 4)
		if math.abs(s - 1) < 0.001 then return 1 end
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
	local function setAnim(k)
		if SH.anim == k then return end
		SH.anim = k
		rescaleAnimations()
	end

	-- ----------------------------------------------------------------------------------------- frame step
	-- "Speed Hack Frame Step" (speeds below 1): no scaling at all. Roblox runs its normal physics on some
	-- frames only, and everything that moves is held still for the physics step of the frames in between
	-- (acc += s every physics step; a step runs when acc reaches 1), like Eternal Obbying's fixed steps fed by
	-- its TAS pace. Only frames whose physics step ran are recorded, each with the simulated time of that step,
	-- so walking, jumping and falling are exactly normal-speed physics (checked in the client: same heights,
	-- states and times), and a platform you push yourself (the kit's Pushing Platform) speeds up at the normal
	-- rate (~158 stud/s^2), which the scaling above can't do (Roblox's walking force can't be slowed). Not exact:
	-- the moment the character bumps into it (anchoring breaks the contact each held step: the push starts a
	-- little later, and now and then stalls - 3 of ~20 live runs).
	-- Held = the character's root and every free assembly of the world's parts anchored from PreSimulation to
	-- PostSimulation of that frame, then put back with the velocities they had: outside the physics step
	-- nothing is held, so pausing, testing and Idle never see it. The kit's clock moves on by each step that ran
	-- (KitClock.Advance), the client objects' physics clock skips the held steps (ClientObjects.SkipSim).
	local FS = { on = false, s = 1, acc = 0, pending = 0, ranDt = 0, held = false, n = 0, saved = {}, parts = {}, scanIn = 0,
		root = nil }
	SH.FS = FS
	local function collectStepParts()
		local list, done = {}, {}
		eachWorldPart(function(p)
			if p.Anchored or charOf(p) then return end
			local rootP = p.AssemblyRootPart or p
			if done[rootP] or rootP.Anchored then return end
			done[rootP] = true
			list[#list + 1] = rootP
		end)
		FS.parts = list
	end
	local function hold(p)
		local n = FS.n + 1
		local e = FS.saved[n]
		if not e then e = {}; FS.saved[n] = e end
		e[1], e[2], e[3] = p, p.AssemblyLinearVelocity, p.AssemblyAngularVelocity
		p.Anchored = true
		FS.n = n
	end
	-- PreSimulation (after the frame was filled): true = this physics step runs, false = everything is held for
	-- it. dt = the time the step simulates
	function SH.StepBegin(dt)
		if not FS.on then return true end
		dt = tonumber(dt) or 0
		FS.acc = FS.acc + FS.s
		if FS.acc >= 1 - 1e-6 then
			FS.acc = FS.acc - 1
			FS.pending = FS.pending + dt
			FS.ranDt = FS.ranDt + dt
			FS.frameDt = dt
			KitClock.Advance(dt)
			return true
		end
		FS.scanIn = FS.scanIn - 1
		if FS.scanIn <= 0 then
			FS.scanIn = 30
			local ok, err = pcall(collectStepParts)
			if not ok then reportError("speed hack frame step", err) end
		end
		FS.n = 0
		FS.held = true
		local root = FS.root
		if root and root.Parent and not root.Anchored then pcall(hold, root) end
		local parts = FS.parts
		for i = 1, #parts do
			local p = parts[i]
			if p.Parent and not p.Anchored then pcall(hold, p) end
		end
		ClientObjects.SkipSim(dt)
		return false
	end
	-- PostSimulation: the held parts go on as they were
	function SH.StepEnd()
		if not FS.held then return end
		FS.held = false
		for i = 1, FS.n do
			local e = FS.saved[i]
			local p = e[1]
			e[1] = nil
			if p and p.Parent then
				pcall(function()
					p.Anchored = false
					p.AssemblyLinearVelocity = e[2]
					p.AssemblyAngularVelocity = e[3]
				end)
			end
		end
		FS.n = 0
	end
	-- the recording takes the simulated time of the steps that ran since its last frame (nil = not frame stepping)
	function SH.StepTime()
		if not FS.on then return nil end
		local t = FS.pending
		FS.pending = 0
		return t
	end
	function SH.Stepping() return FS.on end
	-- the time the physics step of this frame simulated while frame stepping (0 = held, or no step yet: the core
	-- calls SH.FrameStart in PreRender)
	function SH.StepDt() return FS.frameDt or 0 end
	function SH.FrameStart() FS.frameDt = 0 end
	-- the game time the animations move on by this frame (Heartbeat): the real dt x the factor, or with Frame Step
	-- exactly the time of the physics step that ran (0 when everything was held)
	function SH.GameDt(dt)
		if not FS.on then return dt * SH.anim end
		local d = FS.ranDt
		FS.ranDt = 0
		return d
	end
	local function stopStep()
		if not FS.on then return end
		SH.StepEnd()
		FS.on, FS.pending, FS.ranDt, FS.root, FS.parts = false, 0, 0, nil, {}
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
			if keepMomentum and s ~= 1 then scaleMomentum(root, 1 / s) end
		end
		local okW, errW = pcall(W.SetFactor, 1)
		if not okW then reportError("speed hack world", errW) end
		applied, hum, root = false, nil, nil
		baseWalk, baseJump, lastWalk, lastJump, baseGravity, lastGravity = nil, nil, nil, nil, nil, nil
		SH.scale = 1
		stopStep()
		setAnim(1)
	end

	-- once a frame, at the end of PreRender (after the frame was recorded: the factor used now is the one
	-- the next physics step runs with). active = the character records in Create mode (free and alive).
	-- keepMomentum: see Restore (false when Test takes over the character). Returns the factor.
	function SH.Update(active, h, part, keepMomentum)
		local s = 1
		if active and h and part then s = SH.Wanted() end
		if s == 1 then
			if applied or FS.on or SH.anim ~= 1 then SH.Restore(keepMomentum) end
			return 1
		end
		if s < 1 and Settings.On("Speed Hack Frame Step") then
			-- (from the scaled slow motion: its values off, the character's velocity back to normal)
			if applied then SH.Restore(keepMomentum) end
			if not FS.on then
				FS.on, FS.pending, FS.ranDt, FS.scanIn = true, 0, 0, 0
				FS.acc = 1 - s -- (the first step runs)
			end
			FS.s, FS.root = s, part
			setAnim(s)
			return 1
		end
		stopStep()
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
		end
		setAnim(s)
		local okW, errW = pcall(function()
			if W.Factor() ~= s then W.SetFactor(s) else W.Step() end
		end)
		if not okW then reportError("speed hack world", errW) end
		return s
	end

	function SH.Start()
		local function announce()
			local s = SH.Wanted()
			local text = (s ~= 1) and ("Speed Hack: " .. tostring(r(s, 1000)) .. "x while recording") or "Speed Hack: Off"
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

