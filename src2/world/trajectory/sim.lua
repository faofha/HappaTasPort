-- ================================================================================================
--  TRAJECTORY SIM  (HappaTAS 3 world, V3.1 Show Trajectory): a copy of the character's movement, stepped ahead
--  at Roblox's 1/240 s from a start state, with the rules measured in the client for the speed hack (V2.38.17):
--  walking closes 62.5 % of the speed gap per step (at most 741.6 stud/s^2 on the floor, 143 in the air); a jump:
--  each step that starts below the jump speed is pushed to it, the first one that starts at it ends the jump;
--  gravity otherwise (workspace.Gravity, clamped to 1000); a jump starts from the floor or until 0.13 s off it
--  (coyote time), once until the next landing. Floors, walls, slopes and ceilings come from `world` (Roblox's own
--  Raycast / Blockcast in the game), so any part shape and rotation counts. Pure: no engine, no instances.
--  Sim.run(start, input, world, opts) -> points (every opts.every s, the start first), info { jumped, cut }
--    start = { pos, vel, onFloor, offTime, jumping, airJumped (jumped since the floor: no coyote jump), climb?
--              ({ n = the truss face's outward normal, top = its top's height }: climbing), ground (root
--              height over the floor), box (collision box),
--              cf (its rotation), walkSpeed, jumpSpeed, maxSlope (degrees), gravity, top? (head room) }
--    input = { move (horizontal unit vector or zero), jump (held the whole time), tap (one jump at the start, if it
--              can: the red line) }
--    world = { ray(origin, dir, t) -> { pos, normal, part, vel?, carry? }?, cast(cf, size, dir, t) -> { pos, normal,
--              dist, part, vel?, carry? }? (t = the step's game time from the start: moving parts are asked where they
--              will be then; vel = that surface's speed, carry = it carries a character standing on it),
--              near(pos, t)? (true while a moving part may be near pos: that step checks for walls),
--              (launcher gets the whole body: box from the feet to the head, centred at pos)
--              effect(part) -> effect? (phase 2: { kind = "bounce", power, relative? } a kit bounce pad,
--              { kind = "conveyor", vel } a moving floor), launcher(pos, box, rot) -> { up, force }? (a kit jump
--              launcher's hitbox the body is in) }
--    opts  = { time, every, deadline? (os.clock() limit: the line is cut there) }
-- ================================================================================================
local Sim = {}

Sim.STEP = 1 / 240
-- (live, EToH kit test place 2026-11-23, R6, JumpPower 50: a jump's top 7.485 studs above the floor in three runs;
-- this push model reaches it at 1.0757 x JumpPower. V2.38.17's 1.06 gave 7.269, measured then)
Sim.JUMP_SCALE = 1.0757
Sim.COYOTE = 0.13
-- (trusses, measured live 2026-11-23: a climb starts when the body touches a truss face it walks into (a 0.05 s delay
-- put the line half a stud behind the whole way up, live); climbing speed 0.7 x
-- WalkSpeed, up for any move unless it points more than 0.2 away from the truss (down), none: it hangs (measured again
-- 2026-11-23: at 45 degrees, sideways and 0.19 away it still climbs up at 11.2); at 2.4 studs above the top it steps over. A jump off it, live on a
-- lone truss (2026-11-23, "(SPOOKY) Practice."): the jump speed (JUMP_SCALE x JumpPower) at 45 degrees out and up, and
-- half the climbing speed moved from out to up: still 38.03 / 38.03, climbing up 32.43 out / 43.63 up, climbing down
-- 43.63 / 32.43 (each within 0.03). The first measure (35.4 / 35.4) was on a wall of trusses whose neighbours deflected it)
Sim.CLIMB_DELAY, Sim.CLIMB_K, Sim.CLIMB_OVER = 0, 0.7, 2.4
Sim.LAUNCH_TIME = 0.125
Sim.LAUNCH_DELAY = 0.05 -- (the kit polls for the launch once a frame, its push starts the frame after: live ~0.05 s,
-- with a normal jump going meanwhile) -- (a kit jump launcher's LinearVelocity, JumpLauncher.lua: destroyed after 0.125 s)
local GAIN, CAP_FLOOR, CAP_AIR = 0.625, 741.6, 143
local SKIN = 0.01
local FOOT = 0.1 -- (the footprint that keeps standing on an edge: the body box less this, live)
local BACK = 0.05 -- (studs a wall check starts behind the body)
local CLIMB_AWAY = 0.2 -- (how far a move must point away from a truss to climb down, live)
-- (the body against a wall: Roblox's contacts let the box in a little, live the root rests 0.39 - 0.48 from a wall face
-- (the box's half depth is 0.5): the wall check uses the box this much smaller across)
local WALL_SHRINK = 0.15
local HEAD_FRICTION = 0.73 -- (sideways speed lost per (1 + elasticity) x vertical speed, per unit of friction: live, Plastic)
Sim.CLEAR = nil -- (how far one wall check looks ahead, studs: 1 when nil; 0 = a check every step, for tests)
local UP = Vector3.yAxis

-- can a jump start from this state
function Sim.canJump(st)
	if st.climb then return true end -- (a jump off the truss)
	if st.jumping or st.airJumped then return false end
	return st.onFloor == true or (st.offTime or math.huge) <= Sim.COYOTE
end

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

-- the horizontal move d from pos: stops at a wall (a surface too steep to walk), the speed loses its part into it,
-- what is left slides along it once more; returns the new position and speed
-- clear = { dir, left, y }: a check that looked ahead and found nothing: the steps after it in that direction, at that
-- height, need no check until they have used up `left` (one check a stud instead of one a step; live a step pressed
-- against a wall cost 7 us, 1.5 in the open)
local function moveFlat(world, pos, d, hv, rot, box, minUp, clear, t)
	local wallBox = Vector3.new(math.max(0.1, box.X - WALL_SHRINK), box.Y, math.max(0.1, box.Z - WALL_SHRINK))
	local met, metN = nil, nil
	for pass = 1, 2 do
		local len = d.Magnitude
		if len < 1e-9 then break end
		local dir = d / len
		if pass == 1 and not (world.near and world.near(pos, t)) and clear.dir and clear.left >= len and dir:Dot(clear.dir) > 0.9999 and math.abs(pos.Y - clear.y) < 1e-3 then
			clear.left = clear.left - len
			pos = pos + d
			break
		end
		local look = math.max(len, Sim.CLEAR or 1)
		-- (the check starts BACK studs behind the body: Roblox's casts skip a part the box starts in, and a box left a
		-- hair inside a wall (stepping over a truss top into the wall above it, live) walked through it)
		local hit = world.cast(rot + (pos - dir * BACK), wallBox, dir * (look + BACK), t)
		if hit and hit.normal.Y >= minUp then hit = nil end
		local dist = hit and math.max(0, (hit.dist or look) - BACK) or look
		if not hit or dist > len then
			if pass == 1 then clear.dir, clear.left, clear.y = dir, dist - SKIN - len, pos.Y else clear.dir = nil end
			pos = pos + d
			break
		end
		clear.dir = nil
		met, metN = hit.part or met, hit.normal
		local t = math.max(0, dist - SKIN) / len
		pos = pos + d * t
		local n = flat(hit.normal)
		if n.Magnitude < 1e-6 then break end
		n = n.Unit
		local into = hv:Dot(n)
		if into < 0 then hv = hv - n * into end
		local rest = d * (1 - t)
		d = rest - n * math.min(0, rest:Dot(n))
	end
	return pos, hv, met, metN
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
	local airJumped = jumping or st.airJumped == true
	local floorN = UP -- (the floor's normal: walking follows its surface)
	local floorVel = Vector3.zero -- (a conveyor's speed under the feet: walking aims at it + the move, live)
	local effect = world.effect or function() return nil end
	local clear = {}
	local hv = flat(vel)
	local vy = onFloor and not jumping and 0 or vel.Y
	-- a kit bounce pad touched: the root's velocity as the kit sets it, a jump in progress ends (it goes to Freefall)
	local launchLeft, launchV, launchAll = 0, Vector3.zero, false
	local launchWait, launchNext = 0, nil
	local climb = st.climb and { n = flat(st.climb.n).Unit, top = st.climb.top } or nil
	-- (a climbing body faces its truss and keeps facing it after the climb: turning to the move there would put the box's
	-- corner into a part above the truss, live (a 2 x 2 part on its top); the real body can't turn into it)
	if climb then rot = CFrame.lookAt(Vector3.zero, -climb.n) end
	local climbContact = 0
	local lqPos, lqL = nil, nil
	local ws, jp = st.walkSpeed or 16, st.jumpSpeed or 50
	-- the room above the head for a rise of `rise`: a ray from the root, else the body's footprint (live: a block the
	-- body's width touched but the root's centre didn't stopped the real jump; the ray alone went through it)
	local function ceiling(rise, t)
		local hit = world.ray(pos, UP * (top + rise), t)
		if hit then return math.max(0, hit.pos.Y - top - pos.Y), hit end
		local c = world.cast(rot + (pos + UP * (top - 0.05)), Vector3.new(box.X, 0.1, box.Z), UP * rise, t)
		if c then return math.max(0, c.dist or 0), c end
		return nil
	end
	local function bounce(e)
		if e.relative then hv, vy = flat(e.relative), e.relative.Y else vy = e.power end
		jumping, onFloor, airJumped = false, false, true -- (no coyote jump after a bounce)
	end
	local steps = math.max(0, math.floor((opts.time or 1) / h + 0.5))
	local every = math.max(1, math.floor((opts.every or 1 / 30) / h + 0.5))
	local points, info = { pos }, { jumped = jumping, cut = false }
	for i = 1, steps do
		if opts.deadline and i % 24 == 0 and os.clock() > opts.deadline then info.cut = true break end
		local skip = false
		local t = (i - 1) * h
		-- a jump inside a kit launcher's hitbox launches instead (its up x Force for 0.125 s; only Y when upright, all
		-- axes when tilted; no normal jump with it, live); otherwise a held jump starts one whenever it can
		local wants = input.jump or (input.tap and i == 1)
		if climb then
			-- climbing a truss: up / down along its face as the move points at it, a jump leaves it, at the top it steps
			-- over, at the floor it lets go
			if wants then
				local V = (climb.n + UP) * (jv / math.sqrt(2)) + (UP - climb.n) * (vy / 2)
				hv, vy = flat(V), V.Y
				climb, airJumped, onFloor, info.jumped = nil, true, false, true
				pos = pos + (hv + UP * vy) * h
			else
				-- (live: any move climbs up at full speed, sideways too, unless it points more than 0.2 away from the truss:
				-- then down at full speed; no move: it hangs)
				local dir = 0
				if move.Magnitude > 1e-6 then dir = (move.Unit:Dot(-climb.n) < -CLIMB_AWAY) and -1 or 1 end
				vy, hv = Sim.CLIMB_K * ws * dir, Vector3.zero
				local ny = pos.Y + vy * h
				if vy > 0 then
					local room = ceiling(vy * h, t)
					if room then ny, vy = math.min(ny, pos.Y + room), 0 end
				elseif vy < 0 then
					local hit = world.ray(pos + UP, -UP * (ground + 1 - vy * h + 0.05), t)
					if hit and hit.pos.Y + ground >= ny then ny, climb, onFloor, vy, airJumped = hit.pos.Y + ground, nil, true, 0, false end
				end
				pos = Vector3.new(pos.X, ny, pos.Z)
				if climb and pos.Y >= climb.top + Sim.CLIMB_OVER then hv, vy, climb = -climb.n * ws, 0, nil end
			end
			offTime = 0
			if i % every == 0 then points[#points + 1] = pos end
			skip = true
		end
		if not skip then
		local L = nil
		if wants and launchLeft <= 0 and not launchNext and world.launcher then
			-- (one box query per quarter stud the body moved, not one a step)
			if not lqPos or (pos - lqPos).Magnitude >= 0.25 then
				lqPos, lqL = pos, world.launcher(pos + UP * ((top - ground) / 2), Vector3.new(box.X, ground + top, box.Z), rot)
			end
			L = lqL
		end
		if L then
			launchNext, launchWait, info.jumped = L, Sim.LAUNCH_DELAY, true
			-- (the jump key starts a normal jump meanwhile, live; the launch takes over when it comes)
			if not jumping and (onFloor or (offTime <= Sim.COYOTE and not airJumped)) then jumping, airJumped = true, true end
		end
		if launchNext then
			launchWait = launchWait - h
			if launchWait <= 1e-9 then
				launchLeft, launchV = Sim.LAUNCH_TIME, launchNext.up * launchNext.force
				launchAll = not (math.abs(launchNext.up.X) < 0.1 and math.abs(launchNext.up.Z) < 0.1)
				jumping, airJumped, onFloor, launchNext = false, true, false, nil
			end
		elseif wants and launchLeft <= 0 and not jumping and (onFloor or (offTime <= Sim.COYOTE and not airJumped)) then
			jumping, airJumped, info.jumped = true, true, true
		end
		-- walking
		local want = target
		if onFloor and floorVel.Magnitude > 1e-9 then want = target + floorVel end
		if onFloor and floorN.Y < 0.9999 and target.Magnitude > 1e-6 then
			-- (along the floor's surface at the walk speed: across a slope that is the walk speed x cos(slope))
			local along = target - floorN * target:Dot(floorN)
			if along.Magnitude > 1e-6 then want = flat(along.Unit * target.Magnitude) + floorVel end
		end
		local err = want - hv
		local m = err.Magnitude
		if m > 1e-9 then hv = hv + err * (math.min(m * GAIN, (onFloor and CAP_FLOOR or CAP_AIR) * h) / m) end
		-- vertical (the speed changes at the step's start, then the position moves at it)
		local wasFloor = onFloor
		if launchLeft > 1e-9 then
			launchLeft = launchLeft - h
			vy = launchV.Y
			if launchAll then hv = flat(launchV) end
		elseif jumping then
			if jv - vy > 1e-3 then vy = jv else jumping = false; vy = vy - g * h end
		elseif onFloor then
			vy = 0
		else
			vy = vy - g * h
		end
		local wallPart, wallN
		pos, hv, wallPart, wallN = moveFlat(world, pos, hv * h, hv, rot, box, minUp, clear, t)
		local wallE = wallPart and effect(wallPart)
		if wallE and wallE.kind == "bounce" then bounce(wallE) end
		-- walking into a truss face starts a climb after CLIMB_DELAY of contact
		local trussN = wallE and wallE.kind == "truss" and wallN and flat(wallN)
		if not trussN and wallN and target.Magnitude > 1e-6 then
			-- (the wall check met a plain part, maybe with a truss under it: a block sitting on a truss's top, live; a ray
			-- at the body's middle and at its legs looks for the truss face there)
			local into = -flat(wallN)
			if into.Magnitude > 1e-6 then
				into = into.Unit
				for _, dy in ipairs({ 0, -1.5 }) do
					local r = world.ray(pos + UP * dy, into * (box.Z / 2 + 0.3), t)
					local e = r and r.part and effect(r.part)
					if e and e.kind == "truss" then wallE, trussN = e, flat(r.normal) break end
				end
			end
		end
		if trussN and trussN.Magnitude > 1e-6 and target:Dot(trussN.Unit) < -0.5 * target.Magnitude then
			climbContact = climbContact + h
			if climbContact >= Sim.CLIMB_DELAY - 1e-9 then
				climb, climbContact, jumping, launchLeft, launchNext = { n = trussN.Unit, top = wallE.top }, 0, false, 0, nil
				rot = CFrame.lookAt(Vector3.zero, -climb.n)
				vy, hv = 0, Vector3.zero
			end
		else
			climbContact = 0
		end
		local dy = vy * h
		if dy > 0 then
			local room, hit = ceiling(dy, t)
			if room then
				local e = hit.part and effect(hit.part)
				-- (a bounce pad touched from below pushes too)
				if e and e.kind == "bounce" then
					bounce(e)
					dy = math.min(room, vy * h)
				else
					-- (the head bounces off: Roblox averages the two surfaces' elasticity (the body is Plastic, 0.5), and
					-- friction takes sideways speed, live: Plastic 40.7 up -> about -20 down and 16 -> 4 sideways, Ice
					-- about a third back down and 16 -> 12 - 14)
					local sf = world.surface and hit.part and world.surface(hit.part)
					local ew, fw = sf and sf.elasticityWeight or 1, sf and sf.frictionWeight or 1
					local el = (0.5 + (sf and sf.elasticity or 0.5) * ew) / (1 + ew)
					local mu = (0.3 + (sf and sf.friction or 0.3) * fw) / (1 + fw)
					local push = (1 + el) * vy
					local hs = hv.Magnitude
					if hs > 1e-9 then hv = hv * (math.max(0, hs - HEAD_FRICTION * mu * push) / hs) end
					dy, vy, jumping = room, -el * vy, false
				end
			end
		end
		local newY = pos.Y + dy
		-- the floor under the new position: stand on it (walkable), slide on it (too steep) or nothing
		onFloor = false
		floorVel = Vector3.zero
		if vy <= 0 then
			local reach = ground + math.max(0, -dy) + (wasFloor and 0.5 or 0.05)
			local hit = world.ray(pos + UP, -UP * (reach + 1), t)
			local low = newY - (wasFloor and 0.5 or 0) - 1e-6
			if not (hit and hit.pos.Y + ground >= low) then
				-- (no floor under the root: the body's footprint still stands on an edge, live until the root is 0.45 studs
				-- past it facing that way: the box less 0.05 a side; falling, it lands on an edge the same way)
				local fp = world.cast(rot + (pos + UP), Vector3.new(math.max(0.1, box.X - FOOT), 0.1, math.max(0.1, box.Z - FOOT)), -UP * (reach + 1), t)
				if fp and fp.pos.Y + ground >= low and fp.normal.Y >= minUp then hit = fp end
			end
			if hit and hit.pos.Y + ground >= low then
				local e = hit.part and effect(hit.part)
				if e and e.kind == "bounce" then
					newY = hit.pos.Y + ground
					bounce(e)
				elseif hit.normal.Y >= minUp then
					newY, vy, onFloor, airJumped, floorN = hit.pos.Y + ground, 0, true, false, hit.normal
					if e and e.kind == "conveyor" then floorVel = flat(e.vel) elseif hit.carry and hit.vel then floorVel = flat(hit.vel) end
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
	end
	return points, info
end

return Sim
