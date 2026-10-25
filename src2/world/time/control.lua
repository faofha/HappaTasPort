-- ================================================================================================
--  TIME CONTROL  (HappaTAS 3 world plugin, order 57): the speed hack, slow / fast motion while recording in
--  Create mode (V2.38.17 p16_speedhack.lua, both blocks function by function; the other systems are reached
--  through the engine: E.co, E.kitClock, E.anim, E.settings).
--  While a TAS is recorded (Create mode, unpaused) the character moves at s times its normal speed
--  (s = "Speed Hack Speed", 0.1 - 4; above 1 = fast motion, the same rules), like a video played slower:
--    gravity x s^2, WalkSpeed and JumpPower x s, the character's velocity x s when the slow motion starts
--    (and / s when it stops with the character still moving), HappaTAS's animations x s. JumpHeight is left
--    alone. Each recorded frame stores its time x s and the velocity / s (the engine, character), and its
--    factor (column v2SK), so the TAS is in normal time and Test plays it at normal speed.
--  The world slows down with it: constraints and body movers get their slowed values, free client objects
--  keep their motion, conveyors move x s, the kit's bounce pad Power / swing Boost are slowed.
--  Frame Step (below 1x): no scaling; Roblox's normal physics runs on some steps and everything is held for
--  the others. The humanoid's own controllers (walking, turning, coyote time, jumps, gravity above Roblox's
--  1000 limit) are put back on the game clock (the second block, SH.Humanoid).
-- ================================================================================================
local Env = import("platform/env")
local Util = import("engine/util")

local Players = Env.svc("Players")
local engine = nil -- (the engine, set by TimeControl.new)
local SpeedHack = {}
local function clampn(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

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
		if engine.co:isReady() then
			engine.co:eachPart(fn)
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
		local ch = Players.LocalPlayer and Players.LocalPlayer.Character
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
	-- gravity Roblox can't hold (workspace.Gravity stops at 1000): free assemblies get the rest each frame
	function W.Kick(dy)
		local done = {}
		eachWorldPart(function(p)
			if p.Anchored or charOf(p) then return end
			local rootP = p.AssemblyRootPart or p
			if done[rootP] or rootP.Anchored then return end
			done[rootP] = true
			pcall(function() rootP.AssemblyLinearVelocity = rootP.AssemblyLinearVelocity + Vector3.new(0, dy, 0) end)
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
		engine.life:connect(workspace.DescendantAdded, function(d)
			if TIME_PROPS[d.ClassName] then
				known[d] = true
				if wf ~= 1 then addEntry(d) end
			elseif KIT_CONFIG[d.Name] then
				-- (the kit makes the object's configuration table a little later)
				cfgScan, cfgScanIn = true, 30
			end
		end)
		engine.life:connect(workspace.DescendantRemoving, function(d)
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
		if not engine.settings:on("speedHack") then return 1 end
		local s = clampn(tonumber(engine.settings:get("speedHackSpeed")) or 0.5, 0.1, 4)
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
		engine.anim.physScale = SH.scale
		engine.anim:rescale()
	end
	local function setAnim(k)
		if SH.anim == k then return end
		SH.anim = k
		engine.anim.rate = k
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
			engine.kitClock:advance(dt)
			return true
		end
		FS.scanIn = FS.scanIn - 1
		if FS.scanIn <= 0 then
			FS.scanIn = 30
			local ok, err = pcall(collectStepParts)
			if not ok then engine.errs:report("speed hack frame step", err) end
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
		engine.co:skipSim(dt)
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
		-- (Roblox keeps workspace.Gravity at 1000 or less: the rest is a force, see SH.Humanoid)
		local wantG = SH.Humanoid.SetGravity(baseGravity * s * s)
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
			SH.Humanoid.ClearGravity()
			if keepMomentum and s ~= 1 then scaleMomentum(root, 1 / s) end
		end
		local okW, errW = pcall(W.SetFactor, 1)
		if not okW then engine.errs:report("speed hack world", errW) end
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
		if s < 1 and engine.settings:on("speedHackFrameStep") then
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
		root = part
		local ok, err = pcall(applyValues, h, s)
		if not ok then
			engine.errs:report("speed hack", err)
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
		if not okW then engine.errs:report("speed hack world", errW) end
		return s
	end

end

do
	local SH = SpeedHack
	local HC = {}
	SH.Humanoid = HC
	local STEP = 1 / 240
	local GAIN = 0.625            -- of the speed gap closed per physics step
	local WALK_CAP = 741.6        -- studs/s^2 on a Plastic floor
	local AIR_CAP = 143           -- studs/s^2 in the air
	local TURN_A = 0.58312        -- AutoRotate: the spin kept per step (damping)
	local TURN_B = 10 / 3         -- AutoRotate: rad/s of spin per rad of angle left, per step
	local TURN_AIR = 1            -- AutoRotate in the air: the angle left counts up to this (rad)
	local COYOTE = 0.13           -- s of game time after the floor is lost
	local GRACE = 0.125           -- s after the floor is lost before Running turns into Freefall
	local MAX_GRAVITY = 1000      -- Roblox's limit for workspace.Gravity
	HC.WALK_CAP, HC.AIR_CAP, HC.TURN_A, HC.TURN_B, HC.COYOTE = WALK_CAP, AIR_CAP, TURN_A, TURN_B, COYOTE
	local Air = Enum.Material.Air
	local JUMPING = Enum.HumanoidStateType.Jumping
	local FREEFALL = Enum.HumanoidStateType.Freefall
	local TURNING = { [Enum.HumanoidStateType.Running] = true, [Enum.HumanoidStateType.RunningNoPhysics] = true,
		[Enum.HumanoidStateType.Freefall] = true, [Enum.HumanoidStateType.Jumping] = true, [Enum.HumanoidStateType.Landed] = true }
	local MOVING = { [Enum.HumanoidStateType.Running] = true, [Enum.HumanoidStateType.RunningNoPhysics] = true,
		[Enum.HumanoidStateType.Freefall] = true, [Enum.HumanoidStateType.Jumping] = true, [Enum.HumanoidStateType.Landed] = true }
	local caps = {}               -- floor material -> the cap the engine showed on it
	local pre = nil               -- PreSimulation: the state the frame's physics starts from
	local cy = { off = nil, jumped = false, restored = false, disabled = false, noFall = false } -- off = game time since the floor was lost
	HC.coyote = cy

	local function yawOf(cf)
		local l = cf.LookVector
		return math.atan2(-l.X, -l.Z)
	end
	local function wrap(a)
		a = (a + math.pi) % (2 * math.pi)
		return a - math.pi
	end
	-- Roblox's stepping: each 1/240 s step the velocity changes first (change(v, f, moved so far), f = the part of
	-- a step), then
	-- the position moves at it for the step. From `phase` (time into the current step; 0 = a step starts) over time
	-- t. keep: the phase goes on to the next call (Roblox's whole steps, and the game-time grid below 1x: a frame there
	-- is part of a step); without it the last step is a fraction of a step (only the mock's uneven frames have that).
	local function stepping(v, t, phase, keep, change)
		local disp = v * 0
		local eps = STEP * 1e-6
		while t > eps do
			local take
			if phase <= eps then
				phase = 0
				take = math.min(STEP, t)
				v = change(v, keep and 1 or take / STEP, disp)
			else
				take = math.min(STEP - phase, t)
			end
			disp = disp + v * take
			phase, t = phase + take, t - take
			if phase >= STEP - eps then phase = 0 end
		end
		return v, disp, keep and phase or 0
	end
	HC.Stepping = stepping
	-- the walking controller as a step's change
	local function walker(target, cap)
		return function(v, f)
			local err = target - v
			local m = err.Magnitude
			if m > 1e-9 then v = v + err * (math.min(m * GAIN * f, cap * STEP * f) / m) end
			return v
		end
	end
	-- gravity as a step's change; pin.n steps first held at pin.vt (a jump's push)
	local function faller(g, pin)
		return function(v, f)
			if pin.n > 0 then
				pin.n = pin.n - 1
				return pin.vt
			end
			return v - g * STEP * f
		end
	end

	-- ------------------------------------------------------------------------------------------- gravity
	-- the gravity the speed hack wants: what workspace.Gravity can hold; the rest is added after each physics
	-- frame in the air (HC.Post). (A VectorForce was tried live: Roblox's jump keeps pushing against it, a 4x
	-- jump went 12.9 studs high instead of 7.3.)
	local extra = 0
	function HC.SetGravity(want)
		extra = math.max(0, want - MAX_GRAVITY)
		return math.min(want, MAX_GRAVITY)
	end
	function HC.Extra() return extra end
	function HC.ClearGravity() extra = 0 end

	-- ------------------------------------------------------------------------------------------- coyote time
	local function setFreefall(hum, on)
		if on then
			if cy.noFall then
				cy.noFall = false
				pcall(function() hum:SetStateEnabled(FREEFALL, true) end)
			end
		elseif not cy.noFall then
			cy.noFall = true
			pcall(function() hum:SetStateEnabled(FREEFALL, false) end)
		end
	end
	local function setJumping(hum, on)
		if on then
			if cy.disabled then
				cy.disabled = false
				pcall(function() hum:SetStateEnabled(JUMPING, true) end)
			end
		elseif not cy.disabled then
			cy.disabled = true
			pcall(function() hum:SetStateEnabled(JUMPING, false) end)
		end
	end
	-- the timer's state for a recorded frame (nil = on the floor)
	function HC.CoyoteState()
		if cy.off == nil then return nil end
		return { cy.off, cy.jumped and 1 or 0 }
	end
	-- unpausing from a recorded frame: its timer as it was
	function HC.CoyoteRestore(state)
		if type(state) == "table" then
			cy.off, cy.jumped, cy.restored = tonumber(state[1]) or 0, state[2] == 1, true
		else
			cy.off, cy.jumped, cy.restored = nil, false, false
		end
	end
	function HC.CoyoteReset(hum)
		cy.off, cy.jumped, cy.restored = nil, false, false
		cy.grid, cy.pinN, cy.vt, cy.finish = 0, nil, nil, nil
		if hum then
			setJumping(hum, true)
			setFreefall(hum, true)
		end
	end

	-- PreSimulation while recording: the coyote rule for the step that comes, the state the frame starts from.
	-- scaled = the scaled slow / fast motion is on
	function HC.Pre(dt, hum, root, scaled)
		pre = nil
		cy.vy0 = nil
		if not (hum and root and root.Parent) or root.Anchored then return end
		cy.vy0 = root.AssemblyLinearVelocity.Y
		if cy.finish then
			cy.finish = nil
			if hum:GetState() == JUMPING then pcall(function() hum:ChangeState(FREEFALL) end) end
		end
		local stateBefore = hum:GetState()
		local s = SH.scale
		local enforce = (scaled and s ~= 1) or cy.restored
		cy.enforce = enforce
		if cy.off ~= nil and enforce then
			if hum:GetState() == JUMPING then cy.jumped = true end
			-- (the engine decides on a jump at the end of the step: the game's window then; a jump the engine
			-- would no longer make is made in HC.Post)
			setJumping(hum, (not cy.jumped) and cy.off + dt * s <= COYOTE)
			-- Running turns into Freefall GRACE seconds after the floor is lost, in game time too: not by the
			-- engine's real-time grace (HC.Post switches it, after the step's jump, like Roblox's state table)
			local st = hum:GetState()
			setFreefall(hum, not (st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.RunningNoPhysics))
		else
			if cy.disabled then setJumping(hum, true) end
			if cy.noFall then setFreefall(hum, true) end
		end
		if not scaled or s == 1 then cy.grid = 0; return end
		local floor = hum.FloorMaterial
		pre = { v = root.AssemblyLinearVelocity, w = root.AssemblyAngularVelocity.Y, yaw = yawOf(root.CFrame), floor = floor, s = s, hum = hum, root = root,
			state = stateBefore, airborne = cy.off ~= nil or stateBefore == JUMPING or stateBefore == FREEFALL }
		-- gravity above Roblox's limit for the free world parts (the character has its VectorForce)
		if extra > 0 and SH.World and SH.World.Kick then SH.World.Kick(-extra * dt) end
	end

	-- PostSimulation: the coyote timer moves on (recording), the controllers on the game clock (scaled motion)
	function HC.Post(dt, hum, root, recording)
		if recording and hum and root and root.Parent and not root.Anchored then
			-- the floor is lost when gravity alone changed the vertical speed this frame (on something, the
			-- floor holds it): that frame exactly. FloorMaterial turns Air ~3.2 frames later, a fallback.
			local vy1 = root.AssemblyLinearVelocity.Y
			local gEff = workspace.Gravity -- (the engine's own gravity: the rest is added after this check)
			local falling = cy.vy0 ~= nil and math.abs(vy1) > 1e-3
				and math.abs((vy1 - cy.vy0) + gEff * dt) < 0.05 * gEff * dt + 1e-3
			if hum.FloorMaterial ~= Air and not falling then
				if cy.off ~= nil then
					-- (landed: a jump held down is taken on this step; it was off for the step, so it is made here)
					local blocked = cy.disabled
					cy.off, cy.jumped, cy.restored = nil, false, false
					cy.pinN, cy.vt, cy.finish = nil, nil, nil -- (the next push is a new jump)
					setJumping(hum, true)
					setFreefall(hum, true)
					if blocked and hum.Jump and hum:GetState() ~= JUMPING then pcall(function() hum:ChangeState(JUMPING) end) end
				end
			else
				local s = SH.scale
				if cy.off == nil then
					-- (lost during this frame: FloorMaterial turns Air on that frame too, measured)
					cy.off = dt * s
				else
					cy.off = cy.off + dt * s
				end
				if hum:GetState() == JUMPING then cy.jumped = true end
				-- the engine's own window is over (slow motion, or after a pause): a jump inside the game's window
				-- is made here, at the end of the step like the engine's own (only from Running, like Roblox's
				-- state table: once Running has turned into Freefall there is no jump)
				local stJ = hum:GetState()
				if cy.enforce and not cy.jumped and cy.off <= COYOTE and hum.Jump
					and (stJ == Enum.HumanoidStateType.Running or stJ == Enum.HumanoidStateType.RunningNoPhysics) then
					cy.jumped = true
					setJumping(hum, true)
					pcall(function() hum:ChangeState(JUMPING) end)
				end
				-- no jump on this step and the grace is over: Freefall (Roblox checks the jump first)
				stJ = hum:GetState()
				if cy.enforce and cy.off > GRACE and (stJ == Enum.HumanoidStateType.Running or stJ == Enum.HumanoidStateType.RunningNoPhysics) then
					setFreefall(hum, true)
					pcall(function() hum:ChangeState(FREEFALL) end)
				end
			end
		end
		local p = pre
		pre = nil
		-- (a frame with no physics step: nothing to correct, and the turn ratio would be 0 / 0)
		if not dt or dt < 1e-5 then return end
		if not p or p.root ~= root or p.hum ~= hum or not root.Parent or root.Anchored then return end
		if not MOVING[p.state] then return end
		local s = p.s
		local n = dt / STEP
		-- the frame's game time on Roblox's 1x step grid (whole steps: Roblox's dt always is, up to a few
		-- nanoseconds of noise - measured live: taken as one more step that noise stopped every correction)
		local whole = math.abs(n - math.floor(n + 0.5)) < 1e-3
		if whole then
			n = math.floor(n + 0.5)
			dt = n * STEP
		end
		local T = s * dt
		-- vertical: what the engine did (see below)
		local stNow = hum:GetState()
		local jumping = stNow == JUMPING or p.state == JUMPING
		local gWs = workspace.Gravity
		local vy0 = p.v.Y
		local vy1 = root.AssemblyLinearVelocity.Y
		local eFall = stepping(vy0, dt, 0, whole, faller(gWs, { n = 0 })) -- (gravity alone)
		local pushed = jumping and vy1 > 1e-2 and vy1 > eFall + 1e-2
		local zeroPush = stepping(0, dt, 0, whole, faller(gWs, { n = 1, vt = 0 })) -- (the end speed after a push to 0)
		local jumpE = vy1 - zeroPush -- (the speed the engine held, if it pushed)
		local first = pushed and cy.vt == nil
		local again = pushed and cy.vt ~= nil and math.abs(jumpE - cy.vt * s) < 1e-2
		local fell = math.abs(vy1 - eFall) < 1e-3 + 1e-5 * math.abs(vy0)
		-- (a push: the game's held step is the next one on its grid, like Roblox's at 1x)
		if first then cy.pinN, cy.vt = 1, jumpE / s end
		local phase0 = whole and (cy.grid or 0) or 0
		local _, _, phase1 = stepping(0, T, phase0, whole, function(v) return v end)
		cy.grid = phase1
		-- walking / stopping / air control
		local v0 = Vector3.new(p.v.X, 0, p.v.Z)
		local v1 = root.AssemblyLinearVelocity
		local v1h = Vector3.new(v1.X, 0, v1.Z)
		local md = hum.MoveDirection
		local target = Vector3.new(md.X, 0, md.Z) * hum.WalkSpeed
		-- which cap the engine used (FloorMaterial changes a few frames after the floor is lost or found):
		-- the floor's or the air's, whichever explains the engine's result
		local floorCap = (p.floor ~= Air and caps[p.floor]) or WALK_CAP
		local gEnd, gDisp = stepping(v0, dt, 0, whole, walker(target, floorCap))
		local aEnd, aDisp = stepping(v0, dt, 0, whole, walker(target, AIR_CAP))
		local airborne = p.floor == Air or p.state == JUMPING or p.state == Enum.HumanoidStateType.Freefall
		local cap, eEnd, eDisp = floorCap, gEnd, gDisp
		local otherEnd, otherDisp, otherCap = aEnd, aDisp, AIR_CAP
		if airborne then
			cap, eEnd, eDisp = AIR_CAP, aEnd, aDisp
			otherEnd, otherDisp, otherCap = gEnd, gDisp, floorCap
		end
		-- (the other one only when it clearly explains the engine's result better)
		if (v1h - otherEnd).Magnitude < (v1h - eEnd).Magnitude - 1e-3 then cap, eEnd, eDisp = otherCap, otherEnd, otherDisp end
		-- learn the cap of this floor from a frame the engine spent fully capped on it
		if cap ~= AIR_CAP and p.floor ~= Air then
			local err0 = target - v0
			local m = err0.Magnitude
			if m > cap * STEP * n / GAIN + 1 then
				local along = (v1h - v0):Dot(err0 / m)
				if along > 0 and math.abs(along - cap * STEP * n) > 0.05 * cap * STEP * n then
					caps[p.floor] = along / (STEP * n)
					cap = caps[p.floor]
					eEnd, eDisp = stepping(v0, dt, 0, whole, walker(target, cap))
				end
			end
		end
		-- the same controller in normal units over the frame's game time, back to real units
		local uEnd, uDisp = stepping(v0 / s, T, phase0, whole, walker(target / s, cap))
		local dv = uEnd * s - eEnd
		local dp = uDisp - eDisp
		if dv.Magnitude > 1e-6 or dp.Magnitude > 1e-6 then
			root.AssemblyLinearVelocity = Vector3.new(v1.X + dv.X, v1.Y, v1.Z + dv.Z)
			root.CFrame = root.CFrame + Vector3.new(dp.X, 0, dp.Z)
			-- (the walk animation follows the corrected speed, see AnimEngine Running)
			local st = hum:GetState()
			if st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.RunningNoPhysics then
				engine.anim:running(Vector3.new(v1.X + dv.X, 0, v1.Z + dv.Z).Magnitude)
			end
		end
		-- jumps and gravity Roblox can't hold (see the header): the vertical motion in game time. The engine: a
		-- jump held at full speed for one real step, then workspace.Gravity; the game: held for one step of game time,
		-- then the whole gravity (gN, in normal units). The difference is added, like the walking.
		-- Roblox's Jumping state pushes the speed up to the jump speed at the start of every step until a step starts
		-- there (Eternal Obbying's copy: jumpingComputeForce), so a corrected speed below it is pushed back up (measured
		-- live: a 4x jump went 12.5 studs high): such a push back to the same jump speed is not part of the game's
		-- motion, and the jump is finished (Freefall) once the game's hold is over.
		-- Only frames whose vertical motion is known are changed: the jump's push, the same push again, or gravity
		-- alone (in the air); a floor, a landing or a ceiling is the engine's.
		if first or again or fell then
			local gN = (gWs + extra) / (s * s)
			local eEndY, eDy = stepping(vy0, dt, 0, whole, faller(gWs, { n = (first or again) and 1 or 0, vt = jumpE }))
			-- (the game continues from where it was: its held step, or the speed it had)
			local pin = { n = cy.pinN or 0, vt = cy.vt }
			local uEndY, iDy = stepping(vy0 / s, T, phase0, whole, faller(gN, pin))
			cy.pinN = pin.n
			local dvy, dy = uEndY * s - eEndY, iDy - eDy
			if math.abs(dvy) > 1e-6 or math.abs(dy) > 1e-6 then
				local v = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity = Vector3.new(v.X, v.Y + dvy, v.Z)
				root.CFrame = root.CFrame + Vector3.new(0, dy, 0)
			end
			-- the game's hold is over and the speed is below the jump speed: Roblox would finish the jump at the next
			-- step, which here would push it again: Freefall from the next PreSimulation (like the engine's own finish)
			if stNow == JUMPING and cy.vt and cy.pinN <= 0 and uEndY < cy.vt - 1e-4 then cy.finish = true end
		elseif not jumping then
			cy.pinN, cy.vt, cy.finish = nil, nil, nil
		end
		-- turning (AutoRotate, see the header)
		if hum.AutoRotate and TURNING[p.state] then
			local air = p.state == JUMPING or p.state == FREEFALL
			local w0, w1 = p.w, root.AssemblyAngularVelocity.Y
			-- the engine: the frame's steps with the angle it started with
			local function held(e)
				return function(w, f) return w + f * ((TURN_A - 1) * w + TURN_B * e) end
			end
			local wFree = stepping(w0, dt, 0, whole, held(0))
			local wUnit = stepping(0, dt, 0, whole, held(1))
			local eEng = wUnit > 1e-9 and (w1 - wFree) / wUnit or nil
			if eEng and math.abs(eEng) <= math.pi + 0.01 then
				-- (a capped frame in the air only says the angle was at least TURN_AIR: the move direction's, if
				-- it is bigger the same way)
				local e0 = eEng
				if air and math.abs(eEng) >= TURN_AIR - 1e-3 then
					local md = hum.MoveDirection
					if md.Magnitude > 1e-3 then
						local t = wrap(math.atan2(-md.X, -md.Z) - p.yaw)
						if math.abs(t) > math.abs(eEng) and (t > 0) == (eEng > 0) then e0 = t end
					end
				end
				local _, eDisp = stepping(w0, dt, 0, whole, held(eEng))
				local cap = air and TURN_AIR or math.huge
				-- the game: the same controller per game step, the angle left updated each step (the mock's
				-- uneven frames: held for the frame, like the engine)
				local uEnd, uDisp
				if whole then
					uEnd, uDisp = stepping(w0 / s, T, phase0, true, function(w, f, d)
						local e = math.max(-cap, math.min(cap, e0 - d))
						return w + f * ((TURN_A - 1) * w + TURN_B * e)
					end)
				else
					uEnd, uDisp = stepping(w0 / s, T, 0, false, held(math.max(-cap, math.min(cap, e0))))
				end
				local dYaw, dW = uDisp - eDisp, uEnd * s - w1
				if math.abs(dYaw) > 1e-7 or math.abs(dW) > 1e-6 then
					local cf = root.CFrame
					root.CFrame = CFrame.new(cf.Position) * CFrame.Angles(0, dYaw, 0) * cf.Rotation
					local w = root.AssemblyAngularVelocity
					root.AssemblyAngularVelocity = Vector3.new(w.X, w.Y + dW, w.Z)
				end
			end
		end
	end
end

-- ------------------------------------------------------------------------------------------------ the plugin
local SH = SpeedHack
local TimeControl = { name = "time", order = 57 }
TimeControl.__index = TimeControl

local function announce()
	local s = SH.Wanted()
	local text = (s ~= 1) and ("Speed Hack: " .. tostring(Util.round(s, 1000)) .. "x while recording") or "Speed Hack: Off"
	engine.modes:status(text, true)
end

function TimeControl.new(E)
	engine = E
	local self = setmetatable({ E = E, scale = 1, anim = 1, SH = SH }, TimeControl)
	E.tl:addColumn("v2SK", "list", 1, { key = "SK", keep = true })
	-- (the coyote timer at the start of each frame: in memory only, like V2)
	E.tl:addColumn("CY", "list", 1, { key = "CY", save = false })
	-- (the animations' game time: the real dt x the factor, or with Frame Step the time of the step that ran)
	E.anim.gameDt = function(_, dt) return SH.GameDt(dt) end
	E.life:own(E.settings:changed("speedHack", function(v)
		announce()
		if v ~= 0 then SH.World.Track() end
	end))
	E.life:own(E.settings:changed("speedHackSpeed", function()
		if E.settings:on("speedHack") then announce() end
	end))
	-- (the list of the world's constraints is kept from the moment the speed hack is switched on)
	if E.settings:on("speedHack") then SH.World.Track() end
	E.life:own(function() SH.Restore(true); self:sync() end)
	return self
end

-- (the factors the engine and the animations read)
function TimeControl:sync()
	self.scale, self.anim = SH.scale, SH.anim
	local anim = self.E.anim
	anim.physScale, anim.rate = SH.scale, SH.anim
end

function TimeControl:wanted() return SH.Wanted() end
function TimeControl:update(recording, hum, root, keepMomentum)
	local k = SH.Update(recording, hum, root, keepMomentum)
	if SH.scale ~= self.scale or SH.anim ~= self.anim then self:sync() end
	return k
end
function TimeControl:restore(keepMomentum)
	SH.Restore(keepMomentum)
	self:sync()
end
function TimeControl:stepTime() return SH.StepTime() end
function TimeControl:stepping() return SH.Stepping() end
function TimeControl:stepDt() return SH.StepDt() end
function TimeControl:gameDt(dt) return SH.GameDt(dt) end
function TimeControl:frameStart() SH.FrameStart() end
function TimeControl:stepBegin(dt) return SH.StepBegin(dt) end
function TimeControl:stepEnd() SH.StepEnd() end
function TimeControl:humanoidPre(dt, hum, root, scaled) SH.Humanoid.Pre(dt, hum, root, scaled) end
function TimeControl:humanoidPost(dt, hum, root, recording) SH.Humanoid.Post(dt, hum, root, recording) end

-- the coyote timer (V2.38.17): kept with each frame, restored when the recording goes on from a frame, reset
-- by Idle and every pause
function TimeControl:coyoteReset(hum) SH.Humanoid.CoyoteReset(hum) end
function TimeControl:fill(tl, n) tl:setList("CY", n, SH.Humanoid.CoyoteState()) end
function TimeControl:onBeginRecording(tl, n)
	SH.Humanoid.CoyoteRestore((n >= 1 and n <= tl:count()) and tl:getList("CY", n) or nil)
end

-- the frame's factor (V2: SK = the factor its physics ran with, r(k, 10000), nil at 1x)
function TimeControl:begin(tl, i)
	local k = self.E.recScale
	tl:setList("v2SK", i, (k ~= 1) and Util.round(k, 10000) or nil)
end

return TimeControl
