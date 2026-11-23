-- ================================================================================================
--  TRAJECTORY  (HappaTAS 3 world plugin, order 70, V3.1 Show Trajectory, spec 2026-11-23): like Geometry Dash's
--  Show Trajectory mods. Green: where the character goes with the keys held now; red: where it goes if it jumps now
--  (only while jump isn't held and a jump can start: on the floor or in coyote time). Predicted by world/trajectory/sim
--  from the character's real position and speed (Idle, recording) or the paused frame's (Create, paused), for
--  Trajectory Time seconds, every 4th frame while moving and once per change while paused, within a time budget.
--  Settings: Show Trajectory, Trajectory Time, Show Trajectory In (Idle / Create). Never in Test. The lines only
--  draw: they never move the character, touch the world or change the run.
-- ================================================================================================
local Env = import("platform/env")
local Sim = import("world/trajectory/sim")
local Draw = import("world/trajectory/draw")

local Trajectory = { name = "trajectory", order = 70 }
Trajectory.__index = Trajectory
Trajectory.Sim = Sim -- (this copy's predictor, for live checks: several loaded builds leave several in memory)

local GREEN, RED = Color3.fromRGB(0, 255, 0), Color3.fromRGB(255, 60, 60)
-- (seconds of work per update: green may use 60 % of it, red the rest. The lines are worked out again on every frame
-- the character or its keys change (every 4th frame before: it looked slow to follow). Live, 1 s lines: both together
-- about 0.6 - 1.2 ms walking in the open, more near walls and moving parts; the budget cuts a line short rather than
-- the frame going over it)
local BUDGET = 0.003
local EVERY = 1 -- (frames between updates while the character moves)
local Air = Enum.Material.Air
local JUMPING, FREEFALL, CLIMBING = Enum.HumanoidStateType.Jumping, Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.Climbing
local MAX_SEGMENTS = 60 -- (per line: a long Trajectory Time gets longer segments, not more of them)
-- (phase 3: moving parts near the character, nearest first; one that moves less than this is part of the still world)
local MAX_MOVERS, STILL = 24, 1e-3
local SPIN = 0.01 -- (rad/s: slower spins are taken as none, 0.03 studs a second 3 studs from the centre)
local CAND_MOVE = 16 -- (studs the character may move before the list of parts in reach is made again)

function Trajectory.new(E)
	local self = setmetatable({ E = E, uis = Env.svc("UserInputService"), n = 0, air = 0, key = nil, draw = nil,
		lines = {}, budget = nil, runs = 0, jumped = false, clock = 0, seen = setmetatable({}, { __mode = "k" }), movers = {} }, Trajectory)
	E.life:own(function()
		if self.draw then self.draw:destroy() end
		if self.gui then pcall(function() self.gui:Destroy() end) end
	end)
	return self
end

function Trajectory:wanted()
	local E = self.E
	local s = E.settings
	if not s:on("showTrajectory") or not E.char:loaded() then return false end
	if not E.char.model:IsDescendantOf(workspace) then return false end -- (a removed character: respawning)
	local hum = E.char.hum
	if not hum or hum.Health <= 0 then return false end
	if E.mode == 1 then return s:has("showTrajectoryIn", "Idle") end
	if E.mode == 2 then return s:has("showTrajectoryIn", "Create") end
	return false
end

function Trajectory:clear()
	self.lines = {}
	self.key = nil
	if self.draw then self.draw:hide() end
end

function Trajectory:jumpHeld()
	local hum = self.E.char.hum
	local held = false
	local typing = self.E.typing and self.E.typing:active(nil)
	if self.uis and not typing then pcall(function() held = self.uis:IsKeyDown(Enum.KeyCode.Space) end) end
	return held or (hum ~= nil and hum.Jump == true)
end

-- the world as the predictor sees it: Roblox's own casts, without the character or HappaTAS's parts (under the camera)
-- the highest point of a part (its box, turned)
local function topOf(part)
	local cf, sz = part.CFrame, part.Size
	return part.Position.Y + (math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y + math.abs(cf.LookVector.Y) * sz.Z) / 2
end

-- what a part does to the character (phase 2: the EToH kit's objects, with the kit's defaults, v6.1.3): a bounce pad
-- (BouncePadConfiguration: Power 100, RelativeForce false), a conveyor (ConveyorConfiguration: Speed 10, along
-- LookVector; any other anchored part that moves too), a truss (TrussPart: top). Attributes are the unscaled values:
-- the speed hack scales the kit's config tables, not them
local function effectOf(part)
	if part:IsA("TrussPart") then return { kind = "truss", top = topOf(part) } end
	if part:GetAttribute("Activated") == false then return nil end
	local c = part:FindFirstChild("BouncePadConfiguration")
	if c then
		local power = tonumber(c:GetAttribute("Power")) or 100
		local rel = c:GetAttribute("RelativeForce") == true
		return { kind = "bounce", power = power, relative = rel and (-part.CFrame.RightVector * power) or nil }
	end
	local cc = part:FindFirstChild("ConveyorConfiguration")
	if cc then return { kind = "conveyor", vel = part.CFrame.LookVector * (tonumber(cc:GetAttribute("Speed")) or 10) } end
	if part.Anchored and part.AssemblyLinearVelocity.Magnitude > 1e-3 then return { kind = "conveyor", vel = part.AssemblyLinearVelocity } end
	return nil
end

-- a kit jump launcher's hitbox (JumpLauncherHitbox, next to the launcher with LauncherConfiguration: Force 60)
local function launcherOf(hitbox)
	local parent = hitbox.Parent
	if not parent then return nil end
	for _, k in ipairs(parent:GetChildren()) do
		if k:IsA("BasePart") and k:FindFirstChild("LauncherConfiguration") then
			if k:GetAttribute("Activated") == false then return nil end
			return { up = k.CFrame.UpVector, force = tonumber(k.LauncherConfiguration:GetAttribute("Force")) or 60 }
		end
	end
	return nil
end

-- ------------------------------------------------------------------------------------------------ moving parts (phase 3)
-- a moving part's motion { part, o, v (the speed at o), w (spin, rad/s), carry }: its pose t seconds on is guessed
-- from that (turning about o by w x t while o moves on by v x t). Live, a physics part carries a character standing
-- on it (the floor's speed, like a conveyor); an anchored part moved by setting its CFrame carries nothing, velocity
-- set or not (2026-11-23)
local function poseAt(m, t)
	local c = m.cache
	if c.t == t then return c.M, c.inv end
	Trajectory.poseBuilds = (Trajectory.poseBuilds or 0) + 1
	local M = CFrame.new(m.v * t)
	local a = m.w.Magnitude * t
	if a > 1e-9 then M = M * CFrame.new(m.o) * CFrame.fromAxisAngle(m.w.Unit, a) * CFrame.new(-m.o) end
	c.t, c.M, c.inv = t, M, M:Inverse()
	return M, c.inv
end

-- (a part's motion read from the CO player's state for the frame shown: 1-3 its keyframe's position, 36-38 speed,
-- 39-41 spin, x1000; 49 = 3: the speed is the one at that position, else the assembly's at its centre of mass)
local function recorded(s)
	if not (s and s[1] and s[36]) then return nil end
	return Vector3.new(s[1], s[2], s[3]) / 1000, Vector3.new(s[36], s[37], s[38]) / 1000, Vector3.new(s[39], s[40], s[41]) / 1000
end

-- how a part moves now: live: a loose part's assembly velocity and spin; an anchored one by its CFrame change since the
-- last update (game time between them). Paused in Create: the frame's recorded motion (the parts are held there)
function Trajectory:motionOf(part, paused, reg, player)
	local o, v, w, carry
	if paused then
		local id = reg and reg.ids and reg.ids[part]
		local cur = player and player.cur
		local s = id and cur and cur[id]
		local key
		key, v, w = recorded(s)
		if not key then return nil end
		-- (the part is held on the frame's pose, turned on from its keyframe: the speed where it is now)
		o = part.Position
		local from = key
		if s[49] ~= 3 then
			local okC, com = pcall(function() return part.AssemblyCenterOfMass end)
			from = (okC and typeof(com) == "Vector3") and com or o
		end
		v = v + w:Cross(o - from)
		local was = reg.orig and reg.orig[part]
		if was == nil then was = part.Anchored end
		carry = was == false
	elseif not part.Anchored then
		o, v, w, carry = part.AssemblyCenterOfMass, part.AssemblyLinearVelocity, part.AssemblyAngularVelocity, true
	else
		local cf, now = part.CFrame, self.clock
		local last = self.seen[part]
		if not last then
			self.seen[part] = { cf = cf, t = now }
			self.watching = true -- (looked at once: the next update measures it)
			return nil
		end
		local lcf, dt = last.cf, now - last.t
		last.cf, last.t = cf, now
		if lcf == cf then return nil end -- (still: nothing to measure, the lines can rest)
		self.watching = true -- (it moves: the lines keep updating to follow it)
		-- (0.15 s at most between the two looks: longer, a fast spin could read backwards)
		if dt < 1e-4 or dt > 0.15 then return nil end
		cf, last = cf, { cf = lcf }
		local axis, angle = (cf.Rotation * last.cf.Rotation:Inverse()):ToAxisAngle()
		o, v, w, carry = cf.Position, (cf.Position - last.cf.Position) / dt, (angle > 1e-9) and axis * (angle / dt) or Vector3.zero, false
	end
	if v.Magnitude < STILL and w.Magnitude < STILL then return nil end
	return { part = part, o = o, v = v, w = w, carry = carry, r = part.Size.Magnitude / 2, cache = {} }
end

-- forget the anchored parts' last looks (a pause, a mode change: their next look starts a new measure)
function Trajectory:clearSeen()
	table.clear(self.seen)
	self.cand = nil
end

-- the moving parts near `center`: client objects (the CO registry) or, without it, loose parts within reach
function Trajectory:findMovers(paused, center, reach)
	local E = self.E
	local co = E.co
	local reg = co and co.reg
	local player = co and co.player
	local list = {}
	self.watching = false
	-- (the parts in reach are listed about once a second, or after the character moved CAND_MOVE studs: a tower's
	-- registry can hold thousands of client objects; each update then looks at that short list only)
	local ready = reg and reg.isReady and reg:isReady()
	local cand = self.cand
	if not cand or os.clock() - cand.at > 1 or (center - cand.c).Magnitude > CAND_MOVE or cand.reach ~= reach
		or cand.ready ~= (ready and true or false) or cand.paused ~= paused then
		cand = { at = os.clock(), c = center, reach = reach, ready = ready and true or false, paused = paused, parts = {} }
		local within = reach + CAND_MOVE
		local function list1(part)
			if part.Parent and part.CanCollide and (part.Position - center).Magnitude <= within + part.Size.Magnitude / 2 then
				cand.parts[#cand.parts + 1] = part
			end
		end
		if ready then
			reg:eachPart(list1)
		elseif not paused then
			local op = OverlapParams.new()
			op.FilterType = Enum.RaycastFilterType.Exclude
			op.FilterDescendantsInstances = { E.char.model }
			for _, part in ipairs(workspace:GetPartBoundsInRadius(center, within, op)) do
				if not part.Anchored then list1(part) end
			end
		end
		self.cand = cand
	end
	for _, part in ipairs(cand.parts) do
		if part.Parent and part.CanCollide and (part.Position - center).Magnitude <= reach + part.Size.Magnitude / 2 then
			local m = self:motionOf(part, paused, reg, player)
			if m then m.d = (part.Position - center).Magnitude; list[#list + 1] = m end
		end
	end
	table.sort(list, function(a, b) return a.d < b.d end)
	for k = MAX_MOVERS + 1, #list do list[k] = nil end
	return list
end

function Trajectory:world(movers)
	movers = movers or {}
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local ex = { self.E.char.model }
	if workspace.CurrentCamera then ex[#ex + 1] = workspace.CurrentCamera end
	for _, m in ipairs(movers) do
		ex[#ex + 1] = m.part
		local mp = RaycastParams.new()
		mp.FilterType = Enum.RaycastFilterType.Include
		mp.FilterDescendantsInstances = { m.part }
		mp.RespectCanCollide = true
		m.params = mp
	end
	p.FilterDescendantsInstances = ex
	p.RespectCanCollide = true
	local o = OverlapParams.new()
	o.FilterType = Enum.RaycastFilterType.Exclude
	o.FilterDescendantsInstances = { self.E.char.model, workspace.CurrentCamera }
	local effects, launchers, surfaces = {}, {}, {}
	-- (each mover's box at the update: turned parts by their turned size, spinning ones as a ball; at t its centre has
	-- moved by v x t, plus at most its distance from the spin's centre when it spins about another point)
	for _, m in ipairs(movers) do
		local cf, sz = m.part.CFrame, m.part.Size / 2
		-- (physics jitter: live the kit's sliding platform read 0.00009 rad/s; under SPIN it doesn't turn)
		if m.w.Magnitude < SPIN then m.w = Vector3.zero end
		m.c, m.ws, m.arm = cf.Position, m.w.Magnitude, (cf.Position - m.o).Magnitude
		if m.ws > 1e-9 then
			m.half = Vector3.new(m.r, m.r, m.r)
		else
			local R, U, L = cf.RightVector, cf.UpVector, cf.LookVector
			m.half = Vector3.new(math.abs(R.X) * sz.X + math.abs(U.X) * sz.Y + math.abs(L.X) * sz.Z,
				math.abs(R.Y) * sz.X + math.abs(U.Y) * sz.Y + math.abs(L.Y) * sz.Z,
				math.abs(R.Z) * sz.X + math.abs(U.Z) * sz.Y + math.abs(L.Z) * sz.Z)
		end
	end
	-- (can mover m at time t touch the box lo .. hi)
	local function touches(m, t, lo, hi)
		local c, h = m.c + m.v * t, m.half
		local g = m.arm * math.min(2, m.ws * t)
		return c.X + h.X + g >= lo.X and c.X - h.X - g <= hi.X and c.Y + h.Y + g >= lo.Y and c.Y - h.Y - g <= hi.Y
			and c.Z + h.Z + g >= lo.Z and c.Z - h.Z - g <= hi.Z
	end
	-- (the movers' hit at time t, if nearer than `best`: the query moved back to where the part was at the update; a
	-- part that only slides is just shifted back, no turned pose)
	local function moverHit(t, a, d, reach, best, query)
		local hit = nil
		t = t or 0
		local b = a + d
		local lo = Vector3.new(math.min(a.X, b.X) - reach, math.min(a.Y, b.Y) - reach, math.min(a.Z, b.Z) - reach)
		local hi = Vector3.new(math.max(a.X, b.X) + reach, math.max(a.Y, b.Y) + reach, math.max(a.Z, b.Z) + reach)
		for _, m in ipairs(movers) do
			if m.part.Parent and touches(m, t, lo, hi) then
				local r, pos, normal
				if m.ws <= 1e-9 then
					local off = m.v * t
					r = query(m, nil, off)
					if r then pos, normal = r.Position + off, r.Normal end
				else
					local M, inv = poseAt(m, t)
					r = query(m, inv)
					if r then pos, normal = M * r.Position, M:VectorToWorldSpace(r.Normal) end
				end
				local dist = r and r.Distance
				if r and dist < best then
					best = dist
					hit = { pos = pos, normal = normal, dist = dist, part = r.Instance,
						vel = m.v + m.w:Cross(pos - (m.o + m.v * t)), carry = m.carry }
				end
			end
		end
		return hit
	end
	return {
		-- (a mover may be near pos at t: the predictor checks for walls on that step instead of trusting a clear look-ahead)
		near = function(pos, t)
			-- (the wall check: the body box (1 stud above and below the root) and its look-ahead)
			local lo, hi = pos - Vector3.new(2.5, 1.1, 2.5), pos + Vector3.new(2.5, 1.1, 2.5)
			for _, m in ipairs(movers) do
				if touches(m, t or 0, lo, hi) then return true end
			end
			return false
		end,
		ray = function(origin, d, t)
			local r = workspace:Raycast(origin, d, p)
			local hit = r and { pos = r.Position, normal = r.Normal, part = r.Instance, dist = r.Distance } or nil
			if #movers == 0 then return hit end
			return moverHit(t, origin, d, 0, hit and hit.dist or math.huge, function(m, inv, off)
				if off then return workspace:Raycast(origin - off, d, m.params) end
				return workspace:Raycast(inv * origin, inv:VectorToWorldSpace(d), m.params)
			end) or hit
		end,
		cast = function(cf, size, d, t)
			local r = workspace:Blockcast(cf, size, d, p)
			local hit = r and { pos = r.Position, normal = r.Normal, dist = r.Distance, part = r.Instance } or nil
			if #movers == 0 then return hit end
			return moverHit(t, cf.Position, d, size.Magnitude / 2, hit and hit.dist or math.huge, function(m, inv, off)
				if off then return workspace:Blockcast(cf - off, size, d, m.params) end
				return workspace:Blockcast(inv * cf, size, inv:VectorToWorldSpace(d), m.params)
			end) or hit
		end,
		-- (a part's elasticity and friction for a head bounce; nil: Plastic)
		surface = function(part)
			local sf = surfaces[part]
			if sf == nil then
				local ok, pp = pcall(function() return part.CurrentPhysicalProperties end)
				sf = (ok and pp and { elasticity = pp.Elasticity, elasticityWeight = pp.ElasticityWeight, friction = pp.Friction,
					frictionWeight = pp.FrictionWeight }) or false
				surfaces[part] = sf
			end
			return sf or nil
		end,
		effect = function(part)
			local e = effects[part]
			if e == nil then e = effectOf(part) or false; effects[part] = e end
			return e or nil
		end,
		-- (asked only while a jump is wanted: one box query at the body)
		launcher = function(pos, box, rot)
			for _, hit in ipairs(workspace:GetPartBoundsInBox(rot + pos, box, o)) do
				if hit.Name == "JumpLauncherHitbox" then
					local l = launchers[hit]
					if l == nil then l = launcherOf(hit) or false; launchers[hit] = l end
					if l then return l end
				end
			end
			return nil
		end,
	}
end

-- a climbing character's truss: the TrussPart in front of the root; `anyPart` (the humanoid is climbing): any part
-- there, Roblox climbs the edges of plain parts too
function Trajectory:trussAhead(cf, anyPart)
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if look.Magnitude < 1e-6 then return nil end
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = { self.E.char.model, workspace.CurrentCamera }
	-- (from the root down to the feet: near the top the root is already above the truss, live; Roblox climbs on to
	-- 2.4 studs above it)
	local r
	for _, dy in ipairs({ 0, -1.5, -2.9 }) do
		r = workspace:Raycast(cf.Position + Vector3.new(0, dy, 0), look.Unit * 3, p)
		if r and r.Instance and (anyPart or r.Instance:IsA("TrussPart")) then break end
		r = nil
	end
	if not r then return nil end
	local n = Vector3.new(r.Normal.X, 0, r.Normal.Z)
	if n.Magnitude < 1e-6 then return nil end
	return { n = n.Unit, top = topOf(r.Instance) }
end

-- the body's collision box (R6 Torso, R15 UpperTorso + LowerTorso) and how far its head reaches above the root (R6:
-- 2.2, the head's top; the default 2 hit ceilings 0.2 studs late), worked out once per character
function Trajectory:body(model, hrp, r6)
	if self.bodyOf == model and self.bodyBox then return self.bodyBox, self.bodyTop end
	local box, top = Vector3.new(2, 2, 1), 2
	pcall(function()
		local parts = r6 and { model:FindFirstChild("Torso") } or { model:FindFirstChild("UpperTorso"), model:FindFirstChild("LowerTorso") }
		if #parts > 0 then
			local x, y, z = 0, 0, 0
			for _, q in ipairs(parts) do x, y, z = math.max(x, q.Size.X), y + q.Size.Y, math.max(z, q.Size.Z) end
			if x > 0 and y > 0 and z > 0 then box = Vector3.new(x, y, z) end
		end
		local head = model:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			local h = hrp.CFrame:PointToObjectSpace(head.Position).Y + head.Size.Y / 2
			if h > 0.5 and h < 10 then top = h end
		end
	end)
	self.bodyOf, self.bodyBox, self.bodyTop = model, box, top
	return box, top
end

-- where the prediction starts: the paused frame (Create, paused) or the character now
function Trajectory:start(paused)
	local E = self.E
	local ch, hum, hrp = E.char, E.char.hum, E.char.hrp
	local r6 = hum.RigType == Enum.HumanoidRigType.R6
	local box, top = self:body(ch.model, hrp, r6)
	local st = { ground = (r6 and 2 or hum.HipHeight) + hrp.Size.Y / 2, box = box, top = top,
		walkSpeed = hum.WalkSpeed, jumpSpeed = hum.UseJumpPower and hum.JumpPower or math.sqrt(2 * workspace.Gravity * hum.JumpHeight) / Sim.JUMP_SCALE,
		maxSlope = hum.MaxSlopeAngle, gravity = workspace.Gravity, jumping = false }
	local cf, vel
	if paused and E.frame >= 1 and E.frame <= E.tl:count() then
		cf, vel = ch:cframeAt(E.tl, E.frame), ch:linAt(E.tl, E.frame)
		local cy = E.tl:getList("CY", E.frame)
		local state = E.tl:get("State", E.frame, 1)
		local air = state == JUMPING.Value or state == FREEFALL.Value
		-- (CY isn't saved: a run loaded from a file has none, so a fall is told by its speed and state)
		st.onFloor = cy == nil and math.abs(vel.Y) <= 1e-3 and not air
		st.offTime = (type(cy) == "table" and tonumber(cy[1])) or (st.onFloor and 0 or 1)
		st.airJumped = (type(cy) == "table" and cy[2] == 1) or state == JUMPING.Value
	else
		cf, vel = hrp.CFrame, hrp.AssemblyLinearVelocity
		st.onFloor = hum.FloorMaterial ~= Air
		st.offTime = st.onFloor and 0 or self.air
		st.airJumped = not st.onFloor and (self.jumped or hum:GetState() == JUMPING or (hum:GetState() == FREEFALL and vel.Y > 1))
	end
	local climbing = (paused and E.frame >= 1 and E.frame <= E.tl:count() and E.tl:get("State", E.frame, 1) == CLIMBING.Value) or (not paused and hum:GetState() == CLIMBING)
	if climbing then st.climb = self:trussAhead(cf, true) end
	local look = cf.LookVector
	st.pos, st.vel = cf.Position, vel
	st.cf = CFrame.lookAt(Vector3.zero, Vector3.new(look.X, 0, look.Z).Magnitude > 1e-6 and Vector3.new(look.X, 0, look.Z) or Vector3.new(0, 0, -1))
	return st
end

function Trajectory:onFrameEnd(dt)
	local E = self.E
	if not self:wanted() then
		-- (off: no engine read at all; turned on mid-air, the coyote timer starts from 0)
		self.air, self.jumped = 0, false
		if self.lines.green or self.lines.red then self:clear() end
		return
	end
	local hum = E.char.hum
	local rate = E.time and E.time.rate and E.time:rate() or 1
	self.clock = self.clock + (dt or 0) * rate -- (game time: anchored movers' speeds are measured on it)
	-- (time off the floor in game time: the speed hack slows it like Roblox's own timer; a jump since the floor)
	if hum.FloorMaterial == Air then
		self.air = self.air + (dt or 0) * rate
		if hum:GetState() == JUMPING then self.jumped = true end
	else
		self.air, self.jumped = 0, false
	end
	local paused = E.mode == 2 and E.paused
	local state = tostring(E.mode) .. tostring(paused)
	if state ~= self.state then self.state = state; self:clearSeen() end
	local move = hum.MoveDirection
	local held = self:jumpHeld()
	if paused then
		local key = tostring(E.frame) .. "|" .. tostring(E.tl.version) .. "|" .. tostring(E.tl:count()) .. "|" .. tostring(move) .. "|"
			.. tostring(held) .. "|" .. tostring(E.settings:get("trajectoryTime"))
		if key == self.key then return end
		self.key = key
	else
		self.n = self.n + 1
		if self.n % EVERY ~= 0 and self.lines.green then return end
		-- (nothing changed since the last prediction: standing still costs nothing)
		local hrp = E.char.hrp
		local p, v = hrp.Position, hrp.AssemblyLinearVelocity
		local key = string.format("%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|", p.X, p.Y, p.Z, v.X, v.Y, v.Z) .. tostring(move) .. "|"
			.. tostring(held) .. "|" .. tostring(hum.FloorMaterial) .. "|" .. tostring(E.settings:get("trajectoryTime"))
		-- (moving parts near: the lines follow them even while the character stands still)
		if key == self.key and self.lines.green and #self.movers == 0 and not self.watching then return end
		self.key = key
	end
	local ok, err = pcall(function()
		local st = self:start(paused)
		local budget, t0 = self.budget or BUDGET, os.clock()
		local time = E.settings:get("trajectoryTime")
		self.movers = self:findMovers(paused, st.pos, 16 + 60 * time)
		local world = self:world(self.movers)
		local every = math.max(1 / 30, time / MAX_SEGMENTS)
		self.runs = self.runs + 1
		local green = Sim.run(st, { move = move, jump = held }, world, { time = time, every = every, deadline = t0 + budget * 0.6 })
		local red = nil
		if not held and Sim.canJump(st) then
			red = Sim.run(st, { move = move, tap = true }, world, { time = time, every = every, deadline = math.max(os.clock(), t0 + budget * 0.6) + budget * 0.4 })
		end
		-- (Smooth Slow Motion draws the character a little behind its real place: the lines start at the picture)
		local pic = not paused and E.time and E.time.picture and E.time:picture()
		if pic then
			table.insert(green, 1, pic.Position)
			if red then table.insert(red, 1, pic.Position) end
		end
		self.lines = { green = green, red = red }
		self:paint()
	end)
	if not ok then E.errs:report("trajectory", err) end
end

-- (the lines get their own ScreenGui next to HappaTAS's interface: the interface's own is switched off in Classic and
-- while hidden, and a disabled ScreenGui draws no adornment)
function Trajectory:paint()
	local E = self.E
	local root = E.ui and E.ui.root and E.ui.root.gui
	local place = root and root.Parent
	if not place then return end
	if not (self.gui and self.gui.Parent) then
		local g = Instance.new("ScreenGui")
		g.Name = "HappaTASTrajectory"
		g.ResetOnSpawn = false
		g.Enabled = true
		g.Parent = place
		self.gui = g
		if self.draw then self.draw:destroy() end
		self.draw = nil
	end
	self.draw = self.draw or Draw.new(self.gui)
	self.draw:line("green", self.lines.green or {}, GREEN)
	self.draw:line("red", self.lines.red or {}, RED)
end

return Trajectory
