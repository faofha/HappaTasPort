-- ================================================================================================
-- HappaTAS 3: Glide Manipulation (world/glide.lua), the side-edge glide.
-- A glide (measured live, R6, built-in shift lock, strafing along a part while falling): a physics step that starts
-- with the torso box 0.10 - 0.22 studs inside the part's side glides now and then (about 18 % a step); shallower
-- (0.06 - 0.09) never did. A glide stops or slows the fall, throws the character outward and tilts it.
-- The plugin measures how deep the torso is in a part at the start of each physics step and, after one roll per
-- part:
--   * no glide wanted: the torso is moved out to SAFE deep; a glide Roblox makes anyway is undone
--   * a glide wanted: the torso is put TARGET deep; when Roblox doesn't glide, HappaTAS makes the glide
--   * nothing when off, in Test, paused, on a held Frame Step step, for R15, a slow fall, a part you can't collide
--     with, or a torso not touching anything
-- (headless mock: its physics never glides by itself; `fake` makes it glide like Roblox did)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local guard = 0
while not (E.char.hrp and E.char.hum) and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local hrp, hum = E.char.hrp, E.char.hum
M.humanoidPhysics = true
M.robloxController = true
M.floorY = -2000
local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
key(Enum.KeyCode.One)
M.steps(3)

local H = 1 / 240
local CPf = Instance.new("Folder")
CPf.Name = "GlideTest"
CPf.Parent = workspace
-- an upright cylinder, radius 8, axis at x 0, z 0 (Roblox's cylinder: length along X, turned up)
local cyl = Instance.new("Part")
cyl.Name = "Pillar"
cyl.Anchored = true
cyl.Shape = Enum.PartType.Cylinder
cyl.Size = Vector3.new(400, 16, 16)
cyl.CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90))
cyl.Parent = CPf

-- the torso box's depth in the cylinder (top view): 8 - the distance from the axis to the box's nearest point
local function depthCyl()
	local cf = hrp.CFrame
	local c = cf:PointToObjectSpace(Vector3.new(0, cf.Y, 0))
	local q = Vector3.new(math.clamp(c.X, -1, 1), 0, math.clamp(c.Z, -0.5, 0.5))
	local w = cf:PointToWorldSpace(q)
	return 8 - Vector3.new(w.X, 0, w.Z).Magnitude
end

-- the mock glides like Roblox did live when `fake` says so: "band" = a step started 0.10 - 0.22 deep, "any" = every
-- step that starts touching
local fake = nil
local log = nil
local realPhysics = M.physics
M.physics = function(dt)
	local d0 = depthCyl()
	local v0 = hrp.AssemblyLinearVelocity
	if log then log[#log + 1] = { d = d0, vy = v0.Y } end
	realPhysics(dt)
	if fake and v0.Y < -40 and ((fake == "band" and d0 >= 0.10 and d0 <= 0.22) or (fake == "any" and d0 > 0)) then
		local p = hrp.Position
		local out = Vector3.new(p.X, 0, p.Z).Unit
		hrp.AssemblyLinearVelocity = out * 20 + Vector3.new(0, -8, 0)
		hrp.AssemblyAngularVelocity = Vector3.new(10, 0, 10)
		hrp.CFrame = hrp.CFrame * CFrame.Angles(0.4, 0, 0)
	end
end

-- a fall along the cylinder: the torso faces it, turned `turn` degrees, its box `d` deep at the start; returns the
-- depth each physics step started with and the velocity after the first one
local function drop(d, v0, turn, frames)
	M.resetRobloxController()
	local ang = math.rad(30)
	local radial = Vector3.new(math.cos(ang), 0, math.sin(ang))
	local look = CFrame.Angles(0, math.rad(turn or 12), 0):VectorToWorldSpace(-radial)
	-- place the root so the box's depth is `d`: try radii and keep the one that gives it
	local lo, hi = 8, 10
	for _ = 1, 40 do
		local mid = (lo + hi) / 2
		local p = radial * mid + Vector3.new(0, 50, 0)
		hrp.CFrame = CFrame.lookAt(p, p + look)
		if depthCyl() > d then lo = mid else hi = mid end
	end
	hrp.AssemblyLinearVelocity = Vector3.new(0, -(v0 or 100), 0)
	hrp.AssemblyAngularVelocity = Vector3.zero
	hum:ChangeState(Enum.HumanoidStateType.Freefall)
	log = {}
	local after
	for k = 1, frames or 1 do
		M.step(H)
		if k == 1 then after = { v = hrp.AssemblyLinearVelocity, w = hrp.AssemblyAngularVelocity, up = hrp.CFrame.UpVector } end
	end
	local l = log
	log = nil
	-- (away from the cylinder, standing still: the hug is over, the next drop is a new roll)
	hrp.CFrame = CFrame.new(60, 50, 60)
	hrp.AssemblyLinearVelocity = Vector3.zero
	M.steps(30, 1 / 60)
	return { first = l[1] and l[1].d, steps = l, after = after }
end
local function setChance(c) E.settings:set("glideManipulation", 1); E.settings:set("glideChance", c) end

section("the settings")
local SettingsMod = __T3("engine/settings")
local rowOn, rowC = SettingsMod.byKey.glideManipulation, SettingsMod.byKey.glideChance
check(rowOn ~= nil and rowC ~= nil, "Glide Manipulation and Glide Chance exist")
eq(rowOn and rowOn.name, "Glide Manipulation", "its name")
eq(rowC and rowC.name, "Glide Chance (%)", "the chance's name")
eq(rowOn and rowOn.default, 0, "off by default")
eq(rowC and rowC.default, 50, "50 % by default")
eq(rowC and rowC.min, 0, "from 0")
eq(rowC and rowC.max, 100, "to 100")
local GL = E.glide or {}
check(E.glide ~= nil, "the plugin is there")
local SAFE, TARGET = GL.SAFE or 0.05, GL.TARGET or 0.15
check(SAFE < 0.08, "SAFE is shallower than any depth that glided live (" .. tostring(SAFE) .. ")")
check(TARGET >= 0.10 and TARGET <= 0.22, "TARGET is inside the band that glided live (" .. tostring(TARGET) .. ")")

section("off: the torso is left where it is")
E.settings:set("glideManipulation", 0)
do
	local r = drop(0.15)
	near(r.first or -1, 0.15, 1e-3, "the step starts 0.15 deep")
	fake = "band"
	local r2 = drop(0.15)
	fake = nil
	check(r2.after and r2.after.v.Y > -20, "and Roblox's glide happens (the mock's)")
end

section("0 %: never a glide")
setChance(0)
do
	local worst = 0
	for _, d in ipairs({ 0.09, 0.12, 0.15, 0.2, 0.3 }) do
		local r = drop(d)
		worst = math.max(worst, r.first or 1)
	end
	check(worst <= SAFE + 1e-3, "every step starts SAFE deep or less (" .. worst .. ")")
	fake = "band"
	local glides = 0
	for _, d in ipairs({ 0.11, 0.14, 0.18, 0.21 }) do
		local r = drop(d)
		if r.after and r.after.v.Y > -50 then glides = glides + 1 end
	end
	fake = nil
	eq(glides, 0, "a glide that needs the band never comes")
	local r0 = drop(0.03)
	near(r0.first or -1, 0.03, 1e-3, "a torso already shallower is left alone")
	-- (Roblox glided outside the band live too: whatever glides is undone)
	fake = "any"
	local r = drop(0.03)
	fake = nil
	check(r.after and r.after.v.Y < -95, "a glide Roblox makes anyway is undone: the fall goes on (" .. tostring(r.after and r.after.v.Y) .. ")")
	check(r.after and r.after.up.Y > 0.999, "the tilt is undone")
	check(r.after and r.after.w.Magnitude < 1e-6, "and the spin")
	eq(GL.last and GL.last.undone, true, "recorded as undone")
end

section("100 %: always a glide")
setChance(100)
do
	local worst, glides, outs, stops = 0, 0, {}, 0
	for _, d in ipairs({ 0.01, 0.05, 0.09, 0.15, 0.3 }) do
		local r = drop(d)
		worst = math.max(worst, math.abs((r.first or 9) - TARGET))
		local v = r.after and r.after.v
		if v and v.Y > -20 then glides = glides + 1 end
		if v then
			local p = hrp.Position
			outs[#outs + 1] = v.X * math.cos(math.rad(30)) + v.Z * math.sin(math.rad(30))
		end
	end
	check(worst < 2e-3, "every step starts TARGET deep (" .. worst .. ")")
	eq(glides, 5, "the fall is stopped every time (made by HappaTAS: the mock never glides itself)")
	local lo = math.huge
	for _, o in ipairs(outs) do lo = math.min(lo, o) end
	check(lo > 0.12 * 100, "thrown outward at about 17 % of the fall speed (" .. lo .. ")")
	local r = drop(0.1)
	check(r.after and r.after.w.Magnitude > 1, "and tilted (spin " .. tostring(r.after and r.after.w.Magnitude) .. ")")
	eq(GL.last and GL.last.filled, true, "recorded as made by HappaTAS")
	fake = "band"
	local r2 = drop(0.1)
	fake = nil
	near(r2.after and r2.after.v.Y or 0, -8, 1e-6, "a glide Roblox makes itself is kept as it is")
	eq(GL.last and GL.last.filled, false, "not filled in")
end

section("50 %: a roll per part")
setChance(50)
do
	local got = 0
	for k = 1, 40 do
		local r = drop(0.12 + (k % 5) * 0.01)
		if r.after and r.after.v.Y > -20 then got = got + 1 end
	end
	check(got >= 10 and got <= 30, "about half glide (" .. got .. " of 40)")
end

section("one roll for the whole hug")
setChance(50)
do
	-- (many steps against the same part: the same decision every step)
	local mixed = 0
	for k = 1, 6 do
		local r = drop(0.12, 100, 12, 6)
		local d = {}
		for _, s in ipairs(r.steps) do
			if s.d > SAFE + 1e-3 then d.deep = true elseif s.d > -1 then d.safe = true end
		end
		if d.deep and d.safe and r.after and r.after.v.Y < -50 then mixed = mixed + 1 end
	end
	eq(mixed, 0, "a no-glide roll keeps every step SAFE")
end

section("where it does nothing")
setChance(100)
local function untouched(label, d, v0, setup, undo)
	if setup then setup() end
	local r = drop(d, v0)
	if undo then undo() end
	check(r.first ~= nil and math.abs(r.first - d) < 1e-3, label .. " (" .. tostring(r.first) .. ")")
end
untouched("not touching", -0.3)
untouched("a slow fall", 0.12, 10)
untouched("an R15 character", 0.12, 100, function() hum.RigType = Enum.HumanoidRigType.R15 end, function() hum.RigType = Enum.HumanoidRigType.R6 end)
untouched("a part you can't collide with", 0.12, 100, function() cyl.CanCollide = false end, function() cyl.CanCollide = true end)
do
	local saveMode, savePaused = E.mode, E.paused
	E.mode = 3
	check(GL.active and not GL:active(), "Test: off")
	E.mode, E.paused = 2, true
	check(GL.active and not GL:active(), "Create paused: off")
	E.mode, E.paused = 2, false
	check(GL.active and GL:active(), "Create recording: on")
	E.mode, E.paused = 1, false
	check(GL.active and GL:active(), "Idle: on")
	E.mode, E.paused = saveMode, savePaused
	local FS = E.time.SH.FS
	local was, on = FS.plan, FS.on
	FS.plan, FS.on = false, true
	check(GL.stepRuns and not GL:stepRuns(), "a held Frame Step step: off")
	FS.plan, FS.on = was, on
end

section("a block's side too")
setChance(100)
do
	cyl.Parent = nil
	local wall = Instance.new("Part")
	wall.Name = "Wall"
	wall.Anchored = true
	wall.Size = Vector3.new(10, 400, 10)
	wall.CFrame = CFrame.new(-5, 0, 0) -- (its +X face at x 0)
	wall.Parent = CPf
	local function depthWall()
		local cf = hrp.CFrame
		local m = math.huge
		for _, sx in ipairs({ -1, 1 }) do for _, sz in ipairs({ -0.5, 0.5 }) do
			m = math.min(m, cf:PointToWorldSpace(Vector3.new(sx, 0, sz)).X)
		end end
		return -m
	end
	M.resetRobloxController()
	local look = CFrame.Angles(0, math.rad(12), 0):VectorToWorldSpace(Vector3.new(-1, 0, 0))
	local p = Vector3.new(0.6, 50, 0)
	hrp.CFrame = CFrame.lookAt(p, p + look)
	hrp.CFrame = hrp.CFrame + Vector3.new(0.12 - depthWall(), 0, 0) * -1
	hrp.AssemblyLinearVelocity = Vector3.new(0, -100, 0)
	hrp.AssemblyAngularVelocity = Vector3.zero
	hum:ChangeState(Enum.HumanoidStateType.Freefall)
	local d0
	local realP = M.physics
	M.physics = function(dt) d0 = d0 or depthWall(); realP(dt) end
	M.step(H)
	M.physics = realP
	near(d0 or -1, TARGET, 2e-3, "the step starts TARGET deep in the wall")
	check(hrp.AssemblyLinearVelocity.Y > -20 and hrp.AssemblyLinearVelocity.X > 10, "glided out of the wall (+X)")
	wall:Destroy()
	cyl.Parent = CPf
	M.steps(30, 1 / 60)
end

section("recording: the glide is in the run")
setChance(100)
key(Enum.KeyCode.Two)
M.steps(3)
E.modes:setRun({})
M.steps(2)
E.modes:unpause()
drop(0.1, 100, 12, 4)
E.modes:pause()
M.steps(2)
do
	local tl = E.tl
	local stopped = false
	for i = 1, tl:count() do
		if tl:get("Lin", i, 2) > -20 and tl:get("Lin", i, 2) < 5 then stopped = true end
	end
	check(stopped, "a recorded frame has the stopped fall")
end
key(Enum.KeyCode.One)
M.steps(3)

E.settings:set("glideManipulation", 0)
CPf:Destroy()
finish()
