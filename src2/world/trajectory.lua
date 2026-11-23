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

local GREEN, RED = Color3.fromRGB(0, 255, 0), Color3.fromRGB(255, 60, 60)
-- (seconds of work per update: green may use 60 % of it, red the rest. Live, 1 s lines: both 0.75 ms standing, about
-- 2 ms walking into a wall (two checks every step there), so one update every 4th frame is about 0.5 ms a frame while
-- moving, and nothing while nothing changes)
local BUDGET = 0.004
local EVERY = 4 -- (frames between updates while the character moves)
local Air = Enum.Material.Air
local JUMPING, FREEFALL, CLIMBING = Enum.HumanoidStateType.Jumping, Enum.HumanoidStateType.Freefall, Enum.HumanoidStateType.Climbing
local MAX_SEGMENTS = 60 -- (per line: a long Trajectory Time gets longer segments, not more of them)

function Trajectory.new(E)
	local self = setmetatable({ E = E, uis = Env.svc("UserInputService"), n = 0, air = 0, key = nil, draw = nil,
		lines = {}, budget = nil, runs = 0, jumped = false }, Trajectory)
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
	if self.uis then pcall(function() held = self.uis:IsKeyDown(Enum.KeyCode.Space) end) end
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

function Trajectory:world()
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local ex = { self.E.char.model }
	if workspace.CurrentCamera then ex[#ex + 1] = workspace.CurrentCamera end
	p.FilterDescendantsInstances = ex
	p.RespectCanCollide = true
	local o = OverlapParams.new()
	o.FilterType = Enum.RaycastFilterType.Exclude
	o.FilterDescendantsInstances = ex
	local effects, launchers = {}, {}
	return {
		ray = function(origin, d)
			local r = workspace:Raycast(origin, d, p)
			return r and { pos = r.Position, normal = r.Normal, part = r.Instance } or nil
		end,
		cast = function(cf, size, d)
			local r = workspace:Blockcast(cf, size, d, p)
			return r and { pos = r.Position, normal = r.Normal, dist = r.Distance, part = r.Instance } or nil
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

-- a climbing character's truss: the TrussPart in front of the root
function Trajectory:trussAhead(cf)
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if look.Magnitude < 1e-6 then return nil end
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = { self.E.char.model }
	local r = workspace:Raycast(cf.Position, look.Unit * 3, p)
	if not (r and r.Instance and r.Instance:IsA("TrussPart")) then return nil end
	local n = Vector3.new(r.Normal.X, 0, r.Normal.Z)
	if n.Magnitude < 1e-6 then return nil end
	return { n = n.Unit, top = topOf(r.Instance) }
end

-- where the prediction starts: the paused frame (Create, paused) or the character now
function Trajectory:start(paused)
	local E = self.E
	local ch, hum, hrp = E.char, E.char.hum, E.char.hrp
	local r6 = hum.RigType == Enum.HumanoidRigType.R6
	local st = { ground = (r6 and 2 or hum.HipHeight) + hrp.Size.Y / 2, box = Vector3.new(2, 2, 1),
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
	if climbing then st.climb = self:trussAhead(cf) end
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
	-- (time off the floor in game time: the speed hack slows it like Roblox's own timer; a jump since the floor)
	if hum.FloorMaterial == Air then
		local rate = E.time and E.time.rate and E.time:rate() or 1
		self.air = self.air + (dt or 0) * rate
		if hum:GetState() == JUMPING then self.jumped = true end
	else
		self.air, self.jumped = 0, false
	end
	local paused = E.mode == 2 and E.paused
	local move = hum.MoveDirection
	local held = self:jumpHeld()
	if paused then
		local key = tostring(E.frame) .. "|" .. tostring(move) .. "|" .. tostring(held) .. "|" .. tostring(E.settings:get("trajectoryTime"))
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
		if key == self.key and self.lines.green then return end
		self.key = key
	end
	local ok, err = pcall(function()
		local st = self:start(paused)
		local world = self:world()
		local budget, t0 = self.budget or BUDGET, os.clock()
		local time = E.settings:get("trajectoryTime")
		local every = math.max(1 / 30, time / MAX_SEGMENTS)
		self.runs = self.runs + 1
		local green = Sim.run(st, { move = move, jump = held }, world, { time = time, every = every, deadline = t0 + budget * 0.6 })
		local red = nil
		if not held and Sim.canJump(st) then
			red = Sim.run(st, { move = move, tap = true }, world, { time = time, every = every, deadline = math.max(os.clock(), t0 + budget * 0.6) + budget * 0.4 })
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
