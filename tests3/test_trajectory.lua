-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1: Show Trajectory (like Geometry Dash's mods): green = what the held keys do, red = what a jump
-- now does, predicted ahead by HappaTAS's copy of the measured movement rules (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local s = E.settings
local Settings = __T3("engine/settings")
local guard = 0
local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end

section("settings")
do
	local st, tt, si = Settings.byKey.showTrajectory, Settings.byKey.trajectoryTime, Settings.byKey.showTrajectoryIn
	check(st ~= nil and st.default == 0, "Show Trajectory, off by default")
	check(tt ~= nil and tt.default == 1 and tt.min == 0.1 and tt.max == 5, "Trajectory Time: 1 s, 0.1 - 5")
	check(si ~= nil and si.kind == "multi" and si.default == "Idle,Create", "Show Trajectory In: Idle and Create")
	eq(st and st.section, "Trajectory", "in a Trajectory section")
	ui.wm:open("settings")
	M.steps(2)
	local rows = ui.settingsWin.rows
	check(rows.showTrajectory ~= nil and rows.trajectoryTime ~= nil and rows.showTrajectoryIn ~= nil, "New's Settings window has the three rows")
	ui.wm:close("settings")
	s:set("interface", "Classic")
	M.steps(2)
	local cr = ui.classic.settingsRows
	check(cr.showTrajectory ~= nil and cr.trajectoryTime ~= nil, "Classic has Show Trajectory and Trajectory Time")
	check(cr["showTrajectoryIn:Idle"] ~= nil and cr["showTrajectoryIn:Create"] ~= nil, "and a switch per mode")
	s:set("interface", "New")
	M.steps(2)
end

-- ------------------------------------------------------------------------------------------------ the predictor
local Sim = __T3("world/trajectory/sim")
Sim.JUMP_SCALE = 1 -- (the mock controller pushes to JumpPower; live Roblox pushes 1.06 x, measured)
local hrp, hum = E.char.hrp, E.char.hum
M.humanoidPhysics = true
M.robloxController = true
M.floorY = 0
M.floorEdgeX = 40
local world = Instance.new("Folder")
world.Name = "TrajWorld"
world.Parent = workspace
local function part(name, size, pos)
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.Size, p.Position = name, true, size, pos
	p.Parent = world
	return p
end
-- (the floor the mock character walks on: top at M.floorY, ending at x = M.floorEdgeX)
part("Floor", Vector3.new(400, 1, 400), Vector3.new(40 - 200, -0.5, 0))
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { E.char.model }
local W = {
	ray = function(o, d)
		local r = workspace:Raycast(o, d, params)
		return r and { pos = r.Position, normal = r.Normal } or nil
	end,
	cast = function(cf, size, d)
		local r = workspace:Blockcast(cf, size, d, params)
		return r and { pos = r.Position, normal = r.Normal, dist = r.Distance } or nil
	end,
}
local function place(p, v)
	M.resetRobloxController()
	hum:ChangeState(Enum.HumanoidStateType.Running)
	hrp.CFrame = CFrame.new(p)
	hrp.AssemblyLinearVelocity = v or Vector3.zero
	hrp.AssemblyAngularVelocity = Vector3.zero
	hum:Move(Vector3.zero)
	hum.Jump = false
end
local function startNow(extra)
	local v = hrp.AssemblyLinearVelocity
	local onFloor = hrp.Position.Y <= M.floorY + 3 + 1e-6 and v.Y <= 1e-9 and hrp.Position.X < M.floorEdgeX
	local st = { pos = hrp.Position, vel = v, onFloor = onFloor, offTime = onFloor and 0 or 1, jumping = false, ground = 3,
		box = Vector3.new(2, 2, 1), walkSpeed = hum.WalkSpeed, jumpSpeed = hum.JumpPower, maxSlope = 89, gravity = workspace.Gravity,
		cf = CFrame.new() }
	for k, x in pairs(extra or {}) do st[k] = x end
	return st
end
-- the prediction against the mock character for `time`: the worst distance between a predicted point and where
-- the root really was then (points every 1/30 s; the mock stepped one physics step (1/240 s) at a time, as Roblox
-- checks the floor every step: the mock only checks it at a frame start)
local function compare(st, input, time)
	local pts = Sim.run(st, input, W, { time = time, every = 1 / 30 })
	local worst = 0
	for k = 2, #pts do
		for _ = 1, 8 do M.step(1 / 240) end
		local d = (pts[k] - hrp.Position).Magnitude
		if d > worst then worst = d end
	end
	return worst, pts
end
key(Enum.KeyCode.One)
M.steps(2)

section("predictor: standing")
place(Vector3.new(0, 3, 0))
M.steps(2)
do
	local pts = Sim.run(startNow(), { move = Vector3.zero, jump = false }, W, { time = 1, every = 1 / 30 })
	eq(#pts, 31, "a point every 1/30 s for 1 s, and the start")
	local far = 0
	for _, p in ipairs(pts) do far = math.max(far, (p - pts[1]).Magnitude) end
	check(far < 1e-6, "all at the start (" .. far .. ")")
end

section("predictor: walking")
place(Vector3.new(0, 3, 0))
M.steps(2)
hum:Move(Vector3.new(1, 0, 0))
do
	local worst = compare(startNow(), { move = Vector3.new(1, 0, 0), jump = false }, 1)
	check(worst < 0.002, "on the real walk (the same rules as the measured controller: " .. worst .. ")")
end

section("predictor: a jump")
place(Vector3.new(-60, 3, 0))
M.steps(2)
hum:Move(Vector3.new(1, 0, 0))
M.steps(10)
hum.Jump = true
M.step(1 / 60) -- (the mock turns the state Jumping after this frame's steps: the push starts on the next one)
do
	local worst = compare(startNow({ jumping = true, onFloor = true }), { move = Vector3.new(1, 0, 0), jump = false }, 0.7)
	check(worst < 0.05, "within 0.05 studs of the real jump, up to the landing (" .. worst .. ")")
end

section("predictor: walking off the edge")
place(Vector3.new(30, 3, 0))
M.steps(2)
hum:Move(Vector3.new(1, 0, 0))
M.steps(2)
do
	local worst = compare(startNow(), { move = Vector3.new(1, 0, 0), jump = false }, 1.2)
	check(worst < 0.05, "within 0.05 studs of the real fall (" .. worst .. ")")
end

section("predictor: coyote time")
check(Sim.canJump({ onFloor = false, offTime = 0.1, jumping = false }), "a jump 0.1 s off the floor")
check(not Sim.canJump({ onFloor = false, offTime = 0.14, jumping = false }), "none 0.14 s off it")
check(Sim.canJump({ onFloor = true, offTime = 0, jumping = false }), "on the floor")
check(not Sim.canJump({ onFloor = false, offTime = 0.05, jumping = true }), "not while a jump is going on")
do
	-- (a held jump in the air: it starts inside coyote time, once, not after it)
	local base = { pos = Vector3.new(0, 50, 0), vel = Vector3.zero, onFloor = false, jumping = false, ground = 3,
		box = Vector3.new(2, 2, 1), walkSpeed = 16, jumpSpeed = 50, maxSlope = 89, gravity = 196.2 }
	local none = { ray = function() return nil end, cast = function() return nil end }
	base.offTime = 0.05
	local pts, info = Sim.run(base, { move = Vector3.zero, jump = true }, none, { time = 0.5, every = 1 / 30 })
	check(info.jumped and pts[2].Y > 50, "held 0.05 s off the floor: it jumps (" .. pts[2].Y .. ")")
	local apex = -math.huge
	for _, p in ipairs(pts) do apex = math.max(apex, p.Y) end
	check(apex < 50 + 7.5, "once, not again in the air (apex " .. apex .. ")")
	base.offTime = 0.2
	local _, info2 = Sim.run(base, { move = Vector3.zero, jump = true }, none, { time = 0.5, every = 1 / 30 })
	check(not info2.jumped, "held 0.2 s off the floor: no jump")
end

section("predictor: a tap (one jump, the red line)")
do
	local st = startNow({ pos = Vector3.new(-60, 3, 0), vel = Vector3.zero, onFloor = true })
	local pts, info = Sim.run(st, { move = Vector3.zero, tap = true }, W, { time = 1.5, every = 1 / 30 })
	check(info.jumped, "it jumps")
	local ups = 0
	for k = 2, #pts do if pts[k].Y > pts[k - 1].Y + 1e-6 and (k == 2 or pts[k - 1].Y <= pts[k - 2].Y + 1e-6) then ups = ups + 1 end end
	eq(ups, 1, "once: it lands and stays down")
	check(math.abs(pts[#pts].Y - 3) < 1e-6, "on the floor at the end (" .. pts[#pts].Y .. ")")
	local st2 = startNow({ pos = Vector3.new(-60, 40, 0), vel = Vector3.zero, onFloor = false, offTime = 1 })
	local _, info2 = Sim.run(st2, { move = Vector3.zero, tap = true }, W, { time = 1, every = 1 / 30 })
	check(not info2.jumped, "no tap jump in the air past coyote time")
end

section("predictor: a wall")
local wall = part("Wall", Vector3.new(2, 20, 40), Vector3.new(-80, 10, 0))
do
	local st = startNow({ pos = Vector3.new(-90, 3, 0), vel = Vector3.zero, onFloor = true })
	local pts = Sim.run(st, { move = Vector3.new(1, 0, 0), jump = false }, W, { time = 1.5, every = 1 / 30 })
	local face = -81
	local maxX = -math.huge
	for _, p in ipairs(pts) do maxX = math.max(maxX, p.X) end
	-- (the body turns to the move direction like Roblox's AutoRotate: the 1 stud deep torso meets the wall, live)
	check(maxX <= face - 0.5 + 0.01 and maxX > face - 0.5 - 0.05, "stops at the wall face, torso turned to it (" .. maxX .. ")")
	local diag = Vector3.new(1, 0, 1).Unit
	local pts2 = Sim.run(st, { move = diag, jump = false }, W, { time = 1.5, every = 1 / 30 })
	local last = pts2[#pts2]
	check(last.X <= face - 0.3 and last.Z > 10, "a diagonal walk slides along it (" .. tostring(last) .. ")")
end
wall:Destroy()

section("predictor: fewer wall checks, the same line")
do
	local wall2 = part("Wall2", Vector3.new(2, 20, 40), Vector3.new(-80, 10, 0))
	local st = startNow({ pos = Vector3.new(-95, 3, 0), vel = Vector3.zero, onFloor = true })
	local c0 = M.casts
	local pts = Sim.run(st, { move = Vector3.new(1, 0, 1).Unit, jump = false }, W, { time = 1.5, every = 1 / 30 })
	local used = M.casts - c0
	Sim.CLEAR = 0 -- (no clear distance: a check every step)
	local c1 = M.casts
	local ref = Sim.run(st, { move = Vector3.new(1, 0, 1).Unit, jump = false }, W, { time = 1.5, every = 1 / 30 })
	local every = M.casts - c1
	Sim.CLEAR = nil
	local worst = 0
	for k = 1, #ref do worst = math.max(worst, (pts[k] - ref[k]).Magnitude) end
	check(worst < 1e-6, "the same line as checking every step (" .. worst .. ")")
	check(used < every / 2, "with far fewer wall checks (the open part; pressed against the wall every step still meets it: " .. used .. " vs " .. every .. ")")
	wall2:Destroy()
end

section("predictor: slopes")
do
	local function slopeWorld(deg)
		local n = Vector3.new(-math.sin(math.rad(deg)), math.cos(math.rad(deg)), 0)
		return {
			-- (a plane through the origin with normal n)
			ray = function(o, d)
				local den = n:Dot(d)
				if math.abs(den) < 1e-9 then return nil end
				local t = -n:Dot(o) / den
				if t < 0 or t > 1 then return nil end
				return { pos = o + d * t, normal = n }
			end,
			cast = function() return nil end,
		}
	end
	local st = startNow({ pos = Vector3.new(0, 3, 0), vel = Vector3.zero, onFloor = true, maxSlope = 89 })
	local pts = Sim.run(st, { move = Vector3.new(1, 0, 0), jump = false }, slopeWorld(30), { time = 1, every = 1 / 30 })
	local last = pts[#pts]
	check(last.X > 10 and math.abs(last.Y - (last.X * math.tan(math.rad(30)) + 3)) < 0.2, "a 30 degree slope is walked up (" .. tostring(last) .. ")")
	-- (Roblox walks along the surface at the walk speed: across, that is walk speed x cos(slope); live on an 18 degree
	-- wedge the line drifted 0.7 studs ahead in 0.8 s without it)
	local across = (pts[#pts].X - pts[#pts - 3].X) / (3 / 30)
	check(math.abs(across - 16 * math.cos(math.rad(30))) < 0.3, "across the slope at walk speed x cos 30 (" .. across .. ")")
	st.maxSlope = 45
	local pts2 = Sim.run(st, { move = Vector3.new(1, 0, 0), jump = false }, slopeWorld(60), { time = 1, every = 1 / 30 })
	check(pts2[#pts2].Y < 3, "a 60 degree slope with Max Slope 45 cannot be walked up: it slides down (" .. tostring(pts2[#pts2]) .. ")")
end

-- ------------------------------------------------------------------------------------------------ phase 2: kit effects
-- (a made-up world: a floor at y = 0, its x 10..14 strip a bounce pad; a pad wall at x = 20 (its face at 19);
-- the floor at z >= 100 a conveyor moving +Z at 10)
local FLOOR, PAD, SIDEPAD, BELT = {}, {}, {}, {}
local effects = {
	[PAD] = { kind = "bounce", power = 100 },
	[SIDEPAD] = { kind = "bounce", power = 100 },
	[BELT] = { kind = "conveyor", vel = Vector3.new(0, 0, 10) },
}
local function kitWorld(relative)
	return {
		ray = function(o, d)
			if math.abs(d.Y) < 1e-9 then return nil end
			local t = -o.Y / d.Y
			if t < 0 or t > 1 then return nil end
			local p = o + d * t
			local part = FLOOR
			if p.X >= 10 and p.X <= 14 then part = PAD end
			if p.Z >= 100 then part = BELT end
			return { pos = p, normal = Vector3.yAxis, part = part }
		end,
		cast = function(cf, size, d)
			local o = cf.Position
			local half = 0.5 -- (the turned box's depth along +X)
			if d.X <= 0 then return nil end
			local face = 19 - half
			if o.X > face or o.X + d.X < face then return nil end
			local t = (face - o.X) / d.X
			return { pos = o + d * t, normal = Vector3.new(-1, 0, 0), dist = d.Magnitude * t, part = SIDEPAD }
		end,
		effect = function(part)
			local e = effects[part]
			if e and e.kind == "bounce" and relative then return { kind = "bounce", power = 100, relative = relative } end
			return e
		end,
	}
end
local function base(extra)
	local st = { pos = Vector3.new(0, 3, 0), vel = Vector3.zero, onFloor = true, offTime = 0, jumping = false, ground = 3,
		box = Vector3.new(2, 2, 1), walkSpeed = 16, jumpSpeed = 50, maxSlope = 89, gravity = 196.2, cf = CFrame.new() }
	for k, v in pairs(extra or {}) do st[k] = v end
	return st
end
local function top(pts, from)
	local m = -math.huge
	for k = from or 1, #pts do m = math.max(m, pts[k].Y) end
	return m
end

section("phase 2: a bounce pad from above")
do
	local pts = Sim.run(base({ pos = Vector3.new(12, 20, 0), onFloor = false, offTime = 1 }), { move = Vector3.zero }, kitWorld(), { time = 1.6, every = 1 / 30 })
	local up = top(pts) -- (it starts at 20, below the bounce's top)
	local want = 3 + 100 * 100 / (2 * 196.2)
	check(math.abs(up - want) < 0.5, "it bounces as high as Power 100 gives (" .. up .. " vs " .. want .. ")")
end

section("phase 2: a bounce pad from the side")
do
	local pts = Sim.run(base({ pos = Vector3.new(15, 3, 0) }), { move = Vector3.new(1, 0, 0) }, kitWorld(), { time = 0.6, every = 1 / 30 })
	check(top(pts) > 10, "touching the pad wall bounces too (" .. top(pts) .. ")")
end

section("phase 2: a relative pad")
do
	local pts = Sim.run(base({ pos = Vector3.new(12, 6, 0), onFloor = false, offTime = 1 }), { move = Vector3.zero }, kitWorld(Vector3.new(40, 60, 0)), { time = 0.6, every = 1 / 30 })
	check(pts[#pts].X > 12 + 5, "pushed along -RightVector x Power (" .. pts[#pts].X .. ")")
end

section("phase 2: a conveyor")
do
	local pts = Sim.run(base({ pos = Vector3.new(0, 3, 100) }), { move = Vector3.zero }, kitWorld(), { time = 1, every = 1 / 30 })
	local z = pts[#pts].Z - 100
	check(math.abs(z - 10) < 0.3, "standing: carried at the belt speed (" .. z .. ")")
	local pts2 = Sim.run(base({ pos = Vector3.new(0, 3, 200) }), { move = Vector3.new(0, 0, -1) }, kitWorld(), { time = 0.5, every = 1 / 30 })
	local v = (pts2[#pts2].Z - pts2[#pts2 - 3].Z) / (3 / 30)
	check(math.abs(v - (-6)) < 0.3, "walking against it: 16 - 10 = 6 (" .. v .. ")")
	local pts3 = Sim.run(base({ pos = Vector3.new(0, 3, 100), vel = Vector3.new(0, 0, 10) }), { move = Vector3.zero, tap = true }, kitWorld(), { time = 0.4, every = 1 / 30 })
	local late = (pts3[13].Z - pts3[10].Z) / (3 / 30)
	check(math.abs(late) < 0.5, "jumped off: the belt speed fades in the air (" .. late .. ")")
end

section("predictor: a start inside a part")
do
	local block = part("Block", Vector3.new(6, 6, 6), Vector3.new(-120, 3, 0))
	local st = startNow({ pos = Vector3.new(-120, 3, 0), vel = Vector3.zero, onFloor = true })
	local ok, pts = pcall(Sim.run, st, { move = Vector3.new(1, 0, 0), jump = false }, W, { time = 1, every = 1 / 30 })
	check(ok and type(pts) == "table", "no error")
	local far = 0
	if ok then for _, p in ipairs(pts) do far = math.max(far, (p - st.pos).Magnitude) end end
	check(far <= 16 + 0.1, "nothing shoots off (" .. far .. ")")
	block:Destroy()
end
hum:Move(Vector3.zero)
M.humanoidPhysics, M.robloxController, M.floorEdgeX = false, false, nil

-- ------------------------------------------------------------------------------------------------ the lines
local TR = E.trajectory
local function shownSegments()
	local n = 0
	for _, d in ipairs(game:GetDescendants()) do
		if d.ClassName == "LineHandleAdornment" and d.Visible and d.Parent then n = n + 1 end
	end
	for _, d in ipairs(game:GetService("CoreGui"):GetDescendants()) do
		if d.ClassName == "LineHandleAdornment" and d.Visible and d.Parent then n = n + 1 end
	end
	return n
end
M.humanoidPhysics, M.robloxController, M.floorEdgeX = true, true, 40
s:set("showTrajectory", 1)
key(Enum.KeyCode.One)
M.steps(2)

section("lines: drawn in Idle")
place(Vector3.new(0, 3, 0))
M.steps(6)
check(TR ~= nil and TR.lines.green ~= nil and #TR.lines.green > 1, "a green line")
check(TR and TR.lines.red ~= nil, "and a red one (on the floor a jump can start)")
check(shownSegments() > 0, "drawn")

section("lines: standing still, nothing to recompute")
do
	local r0 = TR.runs or 0
	M.steps(12)
	eq((TR.runs or 0) - r0, 0, "no prediction while nothing changes")
	hum:Move(Vector3.new(1, 0, 0))
	M.steps(6)
	check((TR.runs or 0) > r0, "moving again: predicted again")
	place(Vector3.new(0, 3, 0))
	M.steps(6)
end
do
	-- (each line has its own share of the budget: a green line that runs out leaves red its own time)
	check(TR.lines.red ~= nil and #TR.lines.red == 31, "red has all its points (" .. tostring(TR.lines.red and #TR.lines.red) .. ")")
end

section("lines: holding jump shows only green")
M.pressKey(Enum.KeyCode.Space)
M.steps(6)
check(TR.lines.green ~= nil and TR.lines.red == nil, "only green")
M.releaseKey(Enum.KeyCode.Space)
place(Vector3.new(0, 3, 0))
M.steps(6)

section("lines: in the air past coyote time, only green")
place(Vector3.new(0, 60, 0))
M.steps(20)
check(TR.lines.green ~= nil and TR.lines.red == nil, "only green (" .. tostring(TR.lines.red) .. ")")
place(Vector3.new(0, 3, 0))
M.steps(6)

section("lines: Show Trajectory In = Create, nothing in Idle")
s:set("showTrajectoryIn", "Create")
M.steps(6)
check(TR.lines.green == nil and shownSegments() == 0, "nothing in Idle")

section("lines: paused in Create, from the frame shown")
key(Enum.KeyCode.Two)
M.steps(2)
E.modes:request("unpause")
hum:Move(Vector3.new(1, 0, 0))
M.steps(20)
E.modes:request("pause")
M.steps(2)
hum:Move(Vector3.zero)
E.modes:seek(5)
M.steps(4)
do
	local want = E.char:cframeAt(E.tl, E.frame).Position
	check(TR.lines.green ~= nil and (TR.lines.green[1] - want).Magnitude < 1e-3, "the line starts on the paused frame")
	check(TR.lines.green ~= nil and (TR.lines.green[2] - TR.lines.green[1]).Magnitude > 0.01,
		"with the frame's own speed (it was recorded walking; the held character has none)")
end
s:set("showTrajectoryIn", "Idle")
E.modes:seek(6)
M.steps(4)
check(TR.lines.green == nil and shownSegments() == 0, "Show Trajectory In = Idle: nothing while paused in Create")
s:set("showTrajectoryIn", "Idle,Create")

section("lines: not in Test")
E.modes:request("test")
M.steps(6)
check(TR.lines.green == nil and shownSegments() == 0, "nothing while testing")
key(Enum.KeyCode.One)
M.steps(4)

section("lines: off hides them")
place(Vector3.new(0, 3, 0))
M.steps(6)
check(shownSegments() > 0, "(shown)")
s:set("showTrajectory", 0)
M.steps(1)
eq(shownSegments(), 0, "all hidden at once")
s:set("showTrajectory", 1)
M.steps(6)

section("lines: respawn")
do
	local errs0 = #E.errs.last
	local old = E.char.model
	old.Parent = nil
	M.steps(4)
	check(TR.lines.green == nil, "no line without a character")
	local ch2 = M.makeCharacter(Vector3.new(0, 3, 0))
	M.player.CharacterAdded:Fire(ch2)
	local g2 = 0
	while not E.char:loaded() and g2 < 100 do M.step(1 / 60); g2 = g2 + 1 end
	M.steps(6)
	check(TR.lines.green ~= nil, "back with the new character")
	eq(#E.errs.last, errs0, "no error (" .. tostring(E.errs.last[#E.errs.last]) .. ")")
	hrp, hum = E.char.hrp, E.char.hum
end

section("lines: the time budget cuts the line, not the frame")
s:set("trajectoryTime", 5)
TR.budget = 0
M.steps(6)
check(TR.lines.green ~= nil and #TR.lines.green < 5 * 30 + 1, "cut short (" .. tostring(TR.lines.green and #TR.lines.green) .. " points)")
TR.budget = nil
s:set("trajectoryTime", 1)
s:set("showTrajectory", 0)
M.humanoidPhysics, M.robloxController, M.floorEdgeX = false, false, nil

-- ------------------------------------------------------------------------------------------------ review fixes
local function drawnSegments()
	-- (a segment counts only inside a ScreenGui that is switched on: a disabled one draws nothing, live)
	local n = 0
	for _, root in ipairs({ game:GetService("CoreGui"), game }) do
		for _, d in ipairs(root:GetDescendants()) do
			if d.ClassName == "LineHandleAdornment" and d.Visible and d.Parent then
				local sg = d:FindFirstAncestorWhichIsA("ScreenGui")
				if sg == nil or sg.Enabled then n = n + 1 end
			end
		end
	end
	return n
end
M.humanoidPhysics, M.robloxController, M.floorEdgeX = true, true, 40
s:set("showTrajectory", 1)
s:set("trajectoryTime", 1)
key(Enum.KeyCode.One)
M.steps(2)

section("review: the lines draw in Classic too")
s:set("interface", "Classic")
M.steps(2)
place(Vector3.new(0, 3, 0))
hum:Move(Vector3.new(1, 0, 0))
M.steps(8)
check(drawnSegments() > 0, "drawn while the interface is Classic (" .. drawnSegments() .. ")")
s:set("interface", "New")
M.steps(2)
hum:Move(Vector3.zero)

section("review: a jump going up is not jumped again")
place(Vector3.new(-60, 3, 0))
M.steps(4)
hum.Jump = true
M.steps(3)
do
	local v = hrp.AssemblyLinearVelocity
	check(v.Y > 0, "(rising: " .. v.Y .. ")")
	local st = TR:start(false)
	check(not Sim.canJump(st), "no jump can start mid-jump")
	TR.key = nil
	M.steps(4)
	check(TR.lines.red == nil, "no red line mid-jump")
end
for _ = 1, 60 do M.step(1 / 60) end
place(Vector3.new(0, 3, 0))
M.steps(4)

section("review: a paused falling frame without coyote data is not on the floor")
key(Enum.KeyCode.Two)
M.steps(2)
place(Vector3.new(0, 30, 0))
E.modes:request("unpause")
M.steps(10)
E.modes:request("pause")
M.steps(2)
do
	local n = E.tl:count()
	E.modes:seek(n - 2)
	M.steps(2)
	E.tl:setList("CY", E.frame, nil) -- (a run loaded from a file has no CY)
	local st = TR:start(true)
	check(st.vel.Y < -1, "(falling: " .. st.vel.Y .. ")")
	check(not st.onFloor, "not on the floor")
end
key(Enum.KeyCode.One)
M.steps(4)

section("review: coyote time counts game time (speed hack)")
do
	local realRate = E.time.rate
	E.time.rate = function() return 0.1 end
	place(Vector3.new(30, 3, 0))
	hum:Move(Vector3.new(1, 0, 0))
	local g0 = 0
	while hrp.Position.X < 40.5 and g0 < 200 do M.step(1 / 60); g0 = g0 + 1 end
	for _ = 1, 12 do M.step(1 / 60) end -- (0.2 s of real time off the floor = 0.02 s of game time)
	check(TR:start(false).offTime < 0.13, "0.2 s real at 0.1x is inside coyote time (" .. TR:start(false).offTime .. ")")
	E.time.rate = realRate
	hum:Move(Vector3.zero)
	place(Vector3.new(0, 3, 0))
	M.steps(4)
end

section("review: long lines stay at most 60 segments")
s:set("trajectoryTime", 5)
TR.key = nil
hum:Move(Vector3.new(0, 0, 1))
M.steps(8)
check(TR.lines.green ~= nil and #TR.lines.green <= 61, "5 s: at most 61 points (" .. tostring(TR.lines.green and #TR.lines.green) .. ")")
hum:Move(Vector3.zero)
s:set("trajectoryTime", 1)
s:set("showTrajectory", 0)
M.humanoidPhysics, M.robloxController, M.floorEdgeX = false, false, nil

section("help and the update log")
do
	local body
	for _, t in ipairs(__T3("ui/win/helptext").topics(E)) do
		if t.body:find("Show Trajectory", 1, true) then body = t.body end
	end
	check(body ~= nil and body:find("red", 1, true) ~= nil and body:find("green", 1, true) ~= nil, "a Help topic explains Show Trajectory")
	local v31 = table.concat(__T3("ui/updatelog").ENTRIES[1].bullets, " ")
	check(v31:lower():find("trajectory", 1, true) ~= nil, "V3.1 has it in the log")
end

finish()
