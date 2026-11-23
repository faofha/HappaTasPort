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

function Trajectory.new(E)
	local self = setmetatable({ E = E, uis = Env.svc("UserInputService"), n = 0, air = 0, key = nil, draw = nil,
		lines = {}, budget = nil, runs = 0 }, Trajectory)
	E.life:own(function() if self.draw then self.draw:destroy() end end)
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
function Trajectory:world()
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local ex = { self.E.char.model }
	if workspace.CurrentCamera then ex[#ex + 1] = workspace.CurrentCamera end
	p.FilterDescendantsInstances = ex
	p.RespectCanCollide = true
	return {
		ray = function(o, d)
			local r = workspace:Raycast(o, d, p)
			return r and { pos = r.Position, normal = r.Normal } or nil
		end,
		cast = function(cf, size, d)
			local r = workspace:Blockcast(cf, size, d, p)
			return r and { pos = r.Position, normal = r.Normal, dist = r.Distance } or nil
		end,
	}
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
		st.onFloor = cy == nil and vel.Y <= 1e-3
		st.offTime = (type(cy) == "table" and tonumber(cy[1])) or (st.onFloor and 0 or 1)
	else
		cf, vel = hrp.CFrame, hrp.AssemblyLinearVelocity
		st.onFloor = hum.FloorMaterial ~= Air
		st.offTime = st.onFloor and 0 or self.air
	end
	local look = cf.LookVector
	st.pos, st.vel = cf.Position, vel
	st.cf = CFrame.lookAt(Vector3.zero, Vector3.new(look.X, 0, look.Z).Magnitude > 1e-6 and Vector3.new(look.X, 0, look.Z) or Vector3.new(0, 0, -1))
	return st
end

function Trajectory:onFrameEnd(dt)
	local E = self.E
	local hum = E.char.hum
	if hum then
		if hum.FloorMaterial == Air then self.air = self.air + (dt or 0) else self.air = 0 end
	end
	if not self:wanted() then
		if self.lines.green or self.lines.red then self:clear() end
		return
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
		self.runs = self.runs + 1
		local green = Sim.run(st, { move = move, jump = held }, world, { time = time, every = 1 / 30, deadline = t0 + budget * 0.6 })
		local red = nil
		if not held and Sim.canJump(st) then
			red = Sim.run(st, { move = move, tap = true }, world, { time = time, every = 1 / 30, deadline = math.max(os.clock(), t0 + budget * 0.6) + budget * 0.4 })
		end
		self.lines = { green = green, red = red }
		self:paint()
	end)
	if not ok then E.errs:report("trajectory", err) end
end

function Trajectory:paint()
	local E = self.E
	local parent = E.ui and E.ui.root and E.ui.root.gui
	if not parent then return end
	self.draw = self.draw or Draw.new(parent)
	self.draw:line("green", self.lines.green or {}, GREEN)
	self.draw:line("red", self.lines.red or {}, RED)
end

return Trajectory
