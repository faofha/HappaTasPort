-- ================================================================================================
--  LIVE PHYSICS (test tool, never shipped): the same scripted moves with no script, with V2.38.16 and with
--  HappaTAS 3, recorded in Create at 1x. Load it through Real with
--      local P = loadfile("HappaTasTest/phys3.lua")()
--  P.use(kind, path): "none", "v216" (a V2 build with getgenv().__V2T) or "h3" (CONFIG.Debug on).
--  P.run(name, opts): one scenario (see SCEN); returns its numbers. P.fps(): FPS and physics steps per
--  PostSimulation. P.done(): unloads, removes the platforms, puts the controls back.
--  Moves go through Humanoid:Move / Humanoid.Jump with the ControlModule off (no window focus needed).
-- ================================================================================================
local P = {}
local RS = game:GetService("RunService")
local lp = game:GetService("Players").LocalPlayer
local AIR = Enum.Material.Air
local ST = Enum.HumanoidStateType

local function parts()
	local c = lp.Character
	return c, c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart")
end

local plat, ground
local TOP = 502
local function platforms()
	if not (plat and plat.Parent) then
		plat = Instance.new("Part")
		plat.Name, plat.Anchored, plat.Size = "zzPhysPlat", true, Vector3.new(60, 4, 60)
		plat.CFrame, plat.Material = CFrame.new(0, TOP - 2, 0), Enum.Material.Plastic
		plat.Parent = workspace
	end
	if not (ground and ground.Parent) then
		ground = Instance.new("Part")
		ground.Name, ground.Anchored, ground.Size = "zzPhysGround", true, Vector3.new(400, 4, 400)
		ground.CFrame, ground.Material = CFrame.new(0, TOP - 32, 0), Enum.Material.Plastic
		ground.Parent = workspace
	end
end

local function controls(on)
	task.spawn(function()
		local pm = require(lp.PlayerScripts:WaitForChild("PlayerModule"))
		local c = pm:GetControls()
		if on then c:Enable() else c:Disable() end
	end)
end

-- the driver: what the "player" holds now
local drive = { dir = Vector3.zero, jump = false }
local driveConn
local function driver(on)
	if driveConn then driveConn:Disconnect(); driveConn = nil end
	if not on then return end
	driveConn = RS.RenderStepped:Connect(function()
		local _, hum = parts()
		if not hum then return end
		hum:Move(drive.dir, false)
		if drive.jump then hum.Jump = true end
	end)
end

-- the script under test
local kind, api = "none", nil
local function unloadAll()
	local g = getgenv()
	if g.__HappaTAS3 then pcall(g.__HappaTAS3.Unload) end
	if g.__HappaTAS then pcall(g.__HappaTAS.Unload) end
	g.__HappaTAS3_T, g.__V2T = nil, nil
	task.wait(1)
end
function P.use(k, path)
	unloadAll()
	kind, api = k, nil
	controls(false)
	driver(true)
	platforms()
	if k == "none" then return true end
	assert(loadfile(path, "=Under test"))()
	task.wait(2.5)
	if k == "v216" then
		local T = assert(getgenv().__V2T, "no __V2T")
		api = {
			idle = function() T.C.inputs.Idle() end, create = function() T.C.inputs.Create(true) end,
			unpause = function() T.C.inputs.Unpause() end, pause = function() T.C.inputs.Pause() end,
			clear = function() T.Core.SetTAS({}) end, frames = function() return #T.C.data end,
		}
	else
		local E = assert(getgenv().__HappaTAS3_T, "no __HappaTAS3_T").engine
		E.settings:set("speedHack", 0)
		api = {
			idle = function() E.modes:request("idle") end, create = function() E.modes:create(true) end,
			unpause = function() E.modes:unpause() end, pause = function() E.modes:pause() end,
			clear = function() E.modes:setRun({}) end, frames = function() return E.tl:count() end,
			E = E,
		}
	end
	return true
end

-- FPS and physics steps per PostSimulation over `secs`
function P.fps(secs)
	secs = secs or 2
	local frames, posts, steps, hist, dts = 0, 0, 0, {}, {}
	local c1 = RS.RenderStepped:Connect(function() frames = frames + 1 end)
	local c2 = RS.PostSimulation:Connect(function(dt)
		posts = posts + 1
		local n = dt * 240
		steps = steps + n
		local k = string.format("%.2f", n)
		hist[k] = (hist[k] or 0) + 1
	end)
	local t0 = os.clock()
	task.wait(secs)
	c1:Disconnect(); c2:Disconnect()
	local el = os.clock() - t0
	local out = {}
	for k, v in pairs(hist) do out[#out + 1] = k .. "x" .. v end
	table.sort(out)
	return { fps = frames / el, postPerSec = posts / el, postPerFrame = posts / frames, stepsPerPost = steps / math.max(1, posts),
		stepsPerSec = steps / el, hist = table.concat(out, " ") }
end

-- scenarios: x0 = where the character starts (the platform's +X edge is at x 30); f(t, s) the moves at game
-- time t (s = the run's state, s.tAir = game time the floor was lost); pause = { at = function(t, s) -> bool,
-- secs } once
local SCEN = {
	walkstop = { x0 = -20, len = 1.6, f = function(t) return t < 0.6 and 1 or 0, false end },
	jump = { x0 = 0, len = 1.6, f = function(t) return 0, t >= 0.2 and t < 0.3 end },
	coyoteIn = { x0 = 22, len = 2.4, f = function(t, s) return 1, s.tAir ~= nil and t >= s.tAir + 0.08 and t < s.tAir + 0.14 end },
	coyoteOut = { x0 = 22, len = 2.4, f = function(t, s) return 1, s.tAir ~= nil and t >= s.tAir + 0.2 and t < s.tAir + 0.26 end },
	pauseAirJump = { x0 = 0, len = 1.6, f = function(t) return 0, t >= 0.2 and t < 0.3 end,
		pause = { at = function(t) return t >= 0.35 end, secs = 1 } },
	pauseCoyoteIn = { x0 = 22, len = 2.4, f = function(t, s) return 1, s.tAir ~= nil and t >= s.tAir + 0.09 and t < s.tAir + 0.15 end,
		pause = { at = function(t, s) return s.tAir ~= nil and t >= s.tAir + 0.03 end, secs = 1 } },
	pauseCoyoteOut = { x0 = 22, len = 2.4, f = function(t, s) return 1, s.tAir ~= nil and t >= s.tAir + 0.2 and t < s.tAir + 0.26 end,
		pause = { at = function(t, s) return s.tAir ~= nil and t >= s.tAir + 0.03 end, secs = 1 } },
	hold = { x0 = 0, len = 3, f = function(t) return 0, t >= 0.2 end },
	pauseHold = { x0 = 0, len = 3, f = function(t) return 0, t >= 0.2 end,
		pause = { at = function(t) return t >= 0.35 end, secs = 1 } },
}
P.SCEN = SCEN

local function placeAt(x)
	local _, hum, hrp = parts()
	hrp.Anchored = false
	hrp.CFrame = CFrame.lookAt(Vector3.new(x, TOP + 3, 0), Vector3.new(x + 10, TOP + 3, 0))
	hrp.AssemblyLinearVelocity, hrp.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
	local t0 = os.clock()
	repeat task.wait() until (hum.FloorMaterial ~= AIR and hrp.AssemblyLinearVelocity.Magnitude < 0.05) or os.clock() - t0 > 3
	task.wait(0.3)
end

-- opts: { lag = "spikes" | "jitter" } adds frame time in RenderStepped
function P.run(name, opts)
	opts = opts or {}
	local sc = assert(SCEN[name], "no scenario " .. name)
	if sc.pause and kind == "none" then return { skipped = "no pause without a script" } end
	local _, hum, hrp = parts()
	drive.dir, drive.jump = Vector3.zero, false
	if api then api.idle(); task.wait(0.3); api.clear(); task.wait(0.2) end
	placeAt(sc.x0)
	if api then api.create(); task.wait(0.4) end
	local s = { t = 0, tAir = nil, paused = false, pausedOnce = false, done = false }
	local log = {}
	local lagConn
	if opts.lag then
		local nextSpike = os.clock() + 0.5
		lagConn = RS.RenderStepped:Connect(function()
			local busy = 0
			if opts.lag == "jitter" then busy = math.random() * 0.012
			elseif os.clock() >= nextSpike then busy = 0.12; nextSpike = os.clock() + 0.6 + math.random() * 0.4 end
			local e = os.clock() + busy
			while os.clock() < e do end
		end)
	end
	local postConn = RS.PostSimulation:Connect(function(dt)
		if s.done or s.paused or hrp.Anchored then return end
		s.t = s.t + dt
		local p, v = hrp.Position, hrp.AssemblyLinearVelocity
		local air = hum.FloorMaterial == AIR
		if air and s.tAir == nil and p.X > 29 then s.tAir = s.t end
		log[#log + 1] = { s.t, dt * 240, p.X, p.Y, v.X, v.Y, hum:GetState().Value, air and 1 or 0, hrp.AssemblyAngularVelocity.Y }
		local mx, jmp = sc.f(s.t, s)
		drive.dir, drive.jump = Vector3.new(mx, 0, 0), jmp
		if sc.pause and not s.pausedOnce and sc.pause.at(s.t, s) then
			s.pausedOnce, s.paused = true, true
			task.spawn(function()
				api.pause()
				task.wait(sc.pause.secs)
				-- (the recording goes on from its last frame: its game time)
				s.t = api.E and api.E.tl:count() > 0 and api.E.tl:get("TotalTime", api.E.tl:count(), 1) or s.t
				if not api.E then local d = getgenv().__V2T.C.data; s.t = d[#d] and d[#d].TotalTime or s.t end
				api.unpause()
				s.paused = false
			end)
		end
		if s.t >= sc.len then s.done = true end
	end)
	if api then task.wait(0.1); api.unpause() end
	local t0 = os.clock()
	repeat task.wait() until s.done or os.clock() - t0 > sc.len + 6
	postConn:Disconnect()
	if lagConn then lagConn:Disconnect() end
	drive.dir, drive.jump = Vector3.zero, false
	local frames = api and api.frames() or 0
	if api then api.pause(); task.wait(0.1); api.idle() end
	-- the numbers
	local y0 = log[1] and log[1][4] or 0
	local r = { frames = frames, steps = 0, posts = #log }
	local apex, minVy, jumps, lands, prevSt = -math.huge, 0, {}, {}, nil
	local stopX, endX
	for _, e in ipairs(log) do
		r.steps = r.steps + e[2]
		if e[4] > apex then apex = e[4] end
		if e[6] < minVy then minVy = e[6] end
		if e[7] ~= prevSt then
			if e[7] == ST.Jumping.Value then jumps[#jumps + 1] = string.format("%.3f", e[1]) end
			if e[7] == ST.Landed.Value then lands[#lands + 1] = string.format("%.3f", e[1]) end
		end
		prevSt = e[7]
		if name == "walkstop" and stopX == nil and e[1] >= 0.6 then stopX = e[3] end
		endX = e[3]
	end
	r.apex = apex - y0
	r.minVy = minVy
	r.jumps = table.concat(jumps, " ")
	r.lands = table.concat(lands, " ")
	if stopX then r.slide = endX - stopX end
	r.tAir = s.tAir
	r.endY = log[#log] and log[#log][4] - y0
	r.endX = endX
	P.lastLog = log
	return r
end

-- ------------------------------------------------------------------------------------------------
-- Speed hack runs (HappaTAS 3 only): moves and results in GAME time and game units, read from the
-- recording itself (TotalTime, Cframe, Lin, Ang, State per recorded frame).
--   P.speed(s, frameStep)          the speed hack (s = 1: off)
--   P.runG(name, opts)              opts.seed: the random timing; returns { frames = { {t, x, y, z, vx, vy, vz, wy, st} } }
-- Extra parts: a step down (top TOP - 5, x 30..60) and trapdoors (opts.trap = "med" | "tall").
local extra = {}
local function extras()
	if extra.step and extra.step.Parent then return end
	local function part(name, size, cf)
		local p = Instance.new("Part")
		p.Name, p.Anchored, p.Size, p.CFrame, p.Material = name, true, size, cf, Enum.Material.Plastic
		p.Parent = workspace
		return p
	end
	extra.step = part("zzPhysStep", Vector3.new(30, 4, 60), CFrame.new(45, TOP - 7, 0))
	extra.trapMed = part("zzPhysTrapMed", Vector3.new(6, 1, 6), CFrame.new(45, TOP - 0.5, 20))
	extra.trapTall = part("zzPhysTrapTall", Vector3.new(6, 1, 6), CFrame.new(100, TOP - 0.5, 0))
end
P.SURF = { plat = TOP, step = TOP - 5, ground = TOP - 30 }

function P.speed(s, frameStep)
	local E = api.E
	E.settings:set("speedHack", s == 1 and 0 or 1)
	E.settings:set("speedHackSpeed", s)
	E.settings:set("speedHackFrameStep", frameStep and 1 or 0)
end

local W, S_, A, D = Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, -1), Vector3.new(0, 0, 1)
local function u(v) return v.Magnitude > 0 and v.Unit or v end
-- f(t, s, rnd) -> dir, jump. s.tAir: game time the floor was lost
local GSCEN = {
	-- extra velocity
	switch = { at = Vector3.new(0, 0, 0), len = 1.5, f = function(t, s, r)
		local j0 = 0.5 + r[1] * 0.1
		return t < 0.5 and A or D, t >= j0 and t < j0 + 0.05 end },
	spinW = { at = Vector3.new(0, 0, 0), len = 1.5, f = function(t, s, r)
		local k = math.floor(t / (0.06 + r[2] * 0.06)) % 2
		local j0 = 0.3 + r[1] * 0.2
		return u((k == 0 and A or D) + W), t >= j0 and t < j0 + 0.05 end },
	spinS = { at = Vector3.new(0, 0, 0), len = 1.5, f = function(t, s, r)
		local k = math.floor(t / (0.06 + r[2] * 0.06)) % 2
		local j0 = 0.3 + r[1] * 0.2
		return u((k == 0 and A or D) + S_), t >= j0 and t < j0 + 0.05 end },
	spinAll = { at = Vector3.new(0, 0, 0), len = 1.5, f = function(t, s, r)
		local seq = { W, u(W + D), D, u(D + S_), S_, u(S_ + A), A, u(A + W) }
		local k = math.floor(t / (0.04 + r[2] * 0.04)) % 8 + 1
		local j0 = 0.3 + r[1] * 0.3
		return seq[k], t >= j0 and t < j0 + 0.05 end },
	-- landing
	jumpStand = { at = Vector3.new(0, 0, 0), len = 1.6, surf = "plat", f = function(t) return Vector3.zero, t >= 0.2 and t < 0.25 end },
	jumpWalk = { at = Vector3.new(-20, 0, 0), len = 1.6, surf = "plat", f = function(t) return W, t >= 0.3 and t < 0.35 end },
	dropMedWalk = { at = Vector3.new(24, 0, 0), len = 1.8, surf = "step", f = function(t) return W, false end },
	dropTallWalk = { at = Vector3.new(54, 0, -10), len = 2.6, startSurf = "step", surf = "ground", f = function(t) return W, false end },
	dropMedStand = { at = Vector3.new(45, 0, 20), len = 1.8, startSurf = "plat", surf = "step", trap = "trapMed", f = function() return Vector3.zero, false end },
	dropTallStand = { at = Vector3.new(100, 0, 0), len = 2.6, startSurf = "plat", surf = "ground", trap = "trapTall", f = function() return Vector3.zero, false end },
	hop = { at = Vector3.new(0, 0, 0), len = 0.9, surf = "plat", f = function(t) return Vector3.zero, t >= 0.2 and t < 0.25 end, jumpPower = 15 },
	-- basics
	walkstop = { at = Vector3.new(-20, 0, 0), len = 1.2, surf = "plat", f = function(t) return t < 0.6 and W or Vector3.zero, false end },
	turn = { at = Vector3.new(0, 0, 0), len = 1.0, surf = "plat", f = function(t) return t < 0.3 and W or S_, false end },
	coyote = { at = Vector3.new(22, 0, 0), len = 1.4, f = function(t, s, r) return W, s.tAir ~= nil and t >= s.tAir + r.k and t < s.tAir + r.k + 0.05 end },
}
P.GSCEN = GSCEN

local function placeAtV(v, surfTop)
	local _, hum, hrp = parts()
	hrp.Anchored = false
	local y = surfTop + 3
	hrp.CFrame = CFrame.lookAt(Vector3.new(v.X, y, v.Z), Vector3.new(v.X + 10, y, v.Z))
	hrp.AssemblyLinearVelocity, hrp.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
	local t0 = os.clock()
	repeat task.wait() until (hum.FloorMaterial ~= AIR and hrp.AssemblyLinearVelocity.Magnitude < 0.05) or os.clock() - t0 > 3
	task.wait(0.3)
end

function P.runG(name, opts)
	opts = opts or {}
	local sc = assert(GSCEN[name], "no scenario " .. name)
	extras()
	local E = api.E
	local _, hum, hrp = parts()
	drive.dir, drive.jump = Vector3.zero, false
	api.idle(); task.wait(0.3); api.clear(); task.wait(0.2)
	for _, k in ipairs({ "trapMed", "trapTall" }) do extra[k].CanCollide = true end
	local jp0 = hum.JumpPower
	if sc.jumpPower then hum.JumpPower = sc.jumpPower end
	placeAtV(sc.at, P.SURF[sc.startSurf or sc.surf or "plat"])
	api.create(); task.wait(0.4)
	local rnd = { opts.r1 or 0, opts.r2 or 0, k = opts.k or 0.1 }
	local s = { tAir = nil, done = false }
	local tl = E.tl
	local conn = RS.PostSimulation:Connect(function()
		if s.done then return end
		local n = tl:count()
		local t = n > 0 and tl:get("TotalTime", n, 1) or 0
		if s.tAir == nil and n > 0 and tl:get("Cframe", n, 1) > 29.5 and sc.at.X < 29 then
			local st = tl:get("State", n, 1)
			if st == ST.Freefall.Value or (hum.FloorMaterial == AIR) then s.tAir = t end
		end
		if sc.trap and t >= 0.3 then extra[sc.trap].CanCollide = false end
		local dir, jmp = sc.f(t, s, rnd)
		drive.dir, drive.jump = dir, jmp
		if t >= sc.len then s.done = true end
	end)
	task.wait(0.1)
	api.unpause()
	local t0 = os.clock()
	repeat task.wait() until s.done or os.clock() - t0 > sc.len * 12 + 8
	conn:Disconnect()
	drive.dir, drive.jump = Vector3.zero, false
	api.pause(); task.wait(0.1)
	local fr = {}
	for i = 1, tl:count() do
		fr[i] = { tl:get("TotalTime", i, 1), tl:get("Cframe", i, 1), tl:get("Cframe", i, 2), tl:get("Cframe", i, 3),
			tl:get("Lin", i, 1), tl:get("Lin", i, 2), tl:get("Lin", i, 3), tl:get("Ang", i, 2), tl:get("State", i, 1), -tl:get("Cframe", i, 6), -tl:get("Cframe", i, 12) }
	end
	api.idle()
	hum.JumpPower = jp0
	return { frames = fr, tAir = s.tAir, surf = P.SURF[sc.surf or "plat"], real = os.clock() - t0 }
end

-- numbers from a runG result (game units). restOff: root height above the surface when standing (from a 1x run)
local G = 196.2
function P.metrics(res, restOff)
	local fr, surf = res.frames, res.surf
	local m = {}
	local J, LD, RUN, FF = ST.Jumping.Value, ST.Landed.Value, ST.Running.Value, ST.Freefall.Value
	local js
	for i, f in ipairs(fr) do if f[9] == J then js = i break end end
	-- airborne span: from the jump (or the first Freefall) to the first Landed / Running after it
	local a0 = js
	if not a0 then for i, f in ipairs(fr) do if f[9] == FF then a0 = i break end end end
	local L
	if a0 then for i = a0 + 1, #fr do if fr[i][9] == LD or fr[i][9] == RUN then L = i break end end end
	m.jumped = js ~= nil
	if a0 then
		local maxH, maxW, apex = 0, 0, -math.huge
		for i = a0, (L or #fr) do
			local f = fr[i]
			local h = math.sqrt(f[5] * f[5] + f[7] * f[7])
			if h > maxH then maxH = h end
			if math.abs(f[8]) > maxW then maxW = math.abs(f[8]) end
			if f[3] > apex then apex = f[3] end
		end
		m.maxH, m.maxW, m.apex = maxH, maxW, apex - fr[a0][3]
		if L then
			m.air = fr[L][1] - fr[a0][1]
			m.dist = math.sqrt((fr[L][2] - fr[a0][2]) ^ 2 + (fr[L][4] - fr[a0][4]) ^ 2)
		end
	end
	-- landing: contact speed, sink, settle, states
	if L then
		local tL = fr[L][1]
		local minVy = 0
		for i = a0, L do if fr[i][6] < minVy then minVy = fr[i][6] end end
		m.vyContact = minVy
		local restY = surf + (restOff or 3)
		local minY, settle = math.huge, nil
		for i = L - 1, #fr do
			local f = fr[i]
			if f[1] - tL > 1 then break end
			if f[3] < minY then minY = f[3] end
		end
		m.sink = restY - minY
		for i = #fr, L, -1 do
			if math.abs(fr[i][3] - restY) > 0.01 then settle = (fr[i + 1] and fr[i + 1][1] or fr[i][1]) - tL break end
		end
		m.settle = settle or 0
		local sts, prev = {}, nil
		for i = math.max(1, L - 3), #fr do
			local f = fr[i]
			if f[1] - tL > 1 then break end
			if f[9] ~= prev then sts[#sts + 1] = string.format("%s@%+.3f", Enum.HumanoidStateType:FromValue(f[9]).Name, f[1] - tL); prev = f[9] end
		end
		m.states = table.concat(sts, " ")
		-- ground pull: going up from the landing, the frames whose vertical acceleration is off gravity by > 15 %
		-- (one unbroken run ending at the landing): the height above rest where it starts, and the worst one
		local pullH, worst = nil, 0
		for i = L - 1, a0 + 1, -1 do
			local f0, f1 = fr[i - 1], fr[i]
			local dt = f1[1] - f0[1]
			if dt > 1e-6 then
				local acc = (f1[6] - f0[6]) / dt
				if math.abs(acc + G) <= 0.15 * G then break end
				pullH = f0[3] - restY
				if math.abs(acc + G) > math.abs(worst) then worst = acc + G end
			end
		end
		m.pullH, m.pullAcc = pullH, worst
	end
	return m
end
P.unloadAll = unloadAll
function P.setDrive(dir, jump) drive.dir, drive.jump = dir or Vector3.zero, jump == true end
P.placeAtV = placeAtV

function P.done()
	driver(false)
	unloadAll()
	controls(true)
	if plat then plat:Destroy(); plat = nil end
	if ground then ground:Destroy(); ground = nil end
	for k, p in pairs(extra) do p:Destroy(); extra[k] = nil end
end

return P
