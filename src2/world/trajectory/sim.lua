-- ================================================================================================
--  TRAJECTORY SIM  (HappaTAS 3 world, V3.1 Show Trajectory): a copy of the character's movement, stepped ahead
--  at Roblox's 1/240 s from a start state, with the rules measured in the client for the speed hack (V2.38.17):
--  walking closes 62.5 % of the speed gap per step (at most 741.6 stud/s^2 on the floor, 143 in the air); a jump:
--  each step that starts below the jump speed is pushed to it, the first one that starts at it ends the jump;
--  gravity otherwise (workspace.Gravity, clamped to 1000); a jump starts from the floor or until 0.13 s off it
--  (coyote time), once until the next landing. Floors, walls, slopes and ceilings come from `world` (Roblox's own
--  Raycast / Blockcast in the game), so any part shape and rotation counts. Pure: no engine, no instances.
--  Sim.run(start, input, world, opts) -> points (every opts.every s, the start first), info { jumped, cut }
--    start = { pos, vel, onFloor, offTime, jumping, ground (root height over the floor), box (collision box),
--              cf (its rotation), walkSpeed, jumpSpeed, maxSlope (degrees), gravity, top? (head room) }
--    input = { move (horizontal unit vector or zero), jump (held the whole time), tap (one jump at the start, if it
--              can: the red line) }
--    world = { ray(origin, dir) -> { pos, normal }?, cast(cf, size, dir) -> { pos, normal, dist }? }
--    opts  = { time, every, deadline? (os.clock() limit: the line is cut there) }
-- ================================================================================================
local Sim = {}

Sim.STEP = 1 / 240
-- (live, EToH kit test place 2026-11-23, R6, JumpPower 50: a jump's top 7.485 studs above the floor in three runs;
-- this push model reaches it at 1.0757 x JumpPower. V2.38.17's 1.06 gave 7.269, measured then)
Sim.JUMP_SCALE = 1.0757
Sim.COYOTE = 0.13
local GAIN, CAP_FLOOR, CAP_AIR = 0.625, 741.6, 143
local SKIN = 0.01
local UP = Vector3.yAxis

-- can a jump start from this state
function Sim.canJump(st)
	if st.jumping then return false end
	return st.onFloor == true or (st.offTime or math.huge) <= Sim.COYOTE
end

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

-- the horizontal move d from pos: stops at a wall (a surface too steep to walk), the speed loses its part into it,
-- what is left slides along it once more; returns the new position and speed
local function moveFlat(world, pos, d, hv, rot, box, minUp)
	for _ = 1, 2 do
		local len = d.Magnitude
		if len < 1e-9 then break end
		local hit = world.cast(rot + pos, box, d)
		if not hit or hit.normal.Y >= minUp then
			pos = pos + d
			break
		end
		local t = math.max(0, (hit.dist or len) - SKIN) / len
		pos = pos + d * t
		local n = flat(hit.normal)
		if n.Magnitude < 1e-6 then break end
		n = n.Unit
		local into = hv:Dot(n)
		if into < 0 then hv = hv - n * into end
		local rest = d * (1 - t)
		d = rest - n * math.min(0, rest:Dot(n))
	end
	return pos, hv
end

function Sim.run(st, input, world, opts)
	local h = Sim.STEP
	local g = math.min(st.gravity or 196.2, 1000)
	local jv = (st.jumpSpeed or 50) * Sim.JUMP_SCALE
	local ground, box = st.ground or 3, st.box or Vector3.new(2, 2, 1)
	local top = st.top or (box.Y / 2 + 1)
	local rot = st.cf and (st.cf - st.cf.Position) or CFrame.new()
	-- (the body turns to face where it walks, Roblox's AutoRotate: its collision box with it, live 2026-11-23)
	if st.autoRotate ~= false and input.move and flat(input.move).Magnitude > 1e-6 then
		rot = CFrame.lookAt(Vector3.zero, flat(input.move).Unit)
	end
	local minUp = math.cos(math.rad(st.maxSlope or 89))
	local move = input.move and flat(input.move) or Vector3.zero
	local target = (move.Magnitude > 1e-6 and move.Unit or Vector3.zero) * (st.walkSpeed or 16)
	local pos, vel = st.pos, st.vel or Vector3.zero
	local onFloor, offTime, jumping = st.onFloor == true, st.offTime or 0, st.jumping == true
	local airJumped = jumping
	local hv = flat(vel)
	local vy = onFloor and not jumping and 0 or vel.Y
	local steps = math.max(0, math.floor((opts.time or 1) / h + 0.5))
	local every = math.max(1, math.floor((opts.every or 1 / 30) / h + 0.5))
	local points, info = { pos }, { jumped = jumping, cut = false }
	for i = 1, steps do
		if opts.deadline and i % 24 == 0 and os.clock() > opts.deadline then info.cut = true break end
		-- a held jump starts one whenever it can
		if (input.jump or (input.tap and i == 1)) and not jumping and (onFloor or (offTime <= Sim.COYOTE and not airJumped)) then
			jumping, airJumped, info.jumped = true, true, true
		end
		-- walking
		local err = target - hv
		local m = err.Magnitude
		if m > 1e-9 then hv = hv + err * (math.min(m * GAIN, (onFloor and CAP_FLOOR or CAP_AIR) * h) / m) end
		-- vertical (the speed changes at the step's start, then the position moves at it)
		local wasFloor = onFloor
		if jumping then
			if jv - vy > 1e-3 then vy = jv else jumping = false; vy = vy - g * h end
		elseif onFloor then
			vy = 0
		else
			vy = vy - g * h
		end
		pos, hv = moveFlat(world, pos, hv * h, hv, rot, box, minUp)
		local dy = vy * h
		if dy > 0 then
			local hit = world.ray(pos, UP * (top + dy))
			if hit then dy = math.max(0, hit.pos.Y - top - pos.Y); vy = 0; jumping = false end
		end
		local newY = pos.Y + dy
		-- the floor under the new position: stand on it (walkable), slide on it (too steep) or nothing
		onFloor = false
		if vy <= 0 then
			local reach = ground + math.max(0, -dy) + (wasFloor and 0.5 or 0.05)
			local hit = world.ray(pos + UP, -UP * (reach + 1))
			if hit and hit.pos.Y + ground >= newY - (wasFloor and 0.5 or 0) - 1e-6 then
				if hit.normal.Y >= minUp then
					newY, vy, onFloor, airJumped = hit.pos.Y + ground, 0, true, false
				else
					newY = math.max(newY, hit.pos.Y + ground)
					local v = hv + UP * vy
					local into = v:Dot(hit.normal)
					if into < 0 then v = v - hit.normal * into end
					hv, vy = flat(v), v.Y
				end
			end
		end
		pos = Vector3.new(pos.X, newY, pos.Z)
		offTime = onFloor and 0 or offTime + h
		if i % every == 0 then points[#points + 1] = pos end
	end
	return points, info
end

return Sim
