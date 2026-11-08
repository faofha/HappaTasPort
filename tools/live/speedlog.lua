-- ================================================================================================
--  SPEED LOG (TEMPORARY DIAGNOSTIC TOOL, never shipped, not part of wow): measures the speed hack's jump /
--  landing / input delays, freezes (conveyors) and animation glitches in the live client, and writes a
--  summary to HappaTasPort/SpeedLog/. It only READS: it never writes a property, never yields inside a
--  physics step, and the one engine function it wraps (E.time.stepBegin, to see whether each physics step ran
--  or was held) returns exactly what the original returned. Nothing is saved to disk until you press F8 or
--  call SpeedLog.Save() (a file write can cost a frame, so it never happens on its own while you test).
--
--  Needs a DEBUG copy of HappaTAS 3 (CONFIG Debug = true shares the engine as getgenv().__HappaTAS3_T; nothing
--  else changes). Run, in this order, in the executor:
--      loadfile("HappaTasTest/h3_<commit>.lua")()
--      loadfile("HappaTasTest/speedlog.lua")("<commit>")
--  Keys: F8 = save the log now (it keeps logging). getgenv().SpeedLog.Save(), .Stop(), .Mark("text")
-- ================================================================================================
local LABEL = ... or "?"
local genv = getgenv()
if genv.SpeedLog and genv.SpeedLog.Stop then pcall(genv.SpeedLog.Stop) end

local RS = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
local cam = workspace.CurrentCamera
local ST = Enum.HumanoidStateType
local AIR = Enum.Material.Air
local clock = os.clock

local T = genv.__HappaTAS3_T
local E = T and T.engine
local conns = {}
local function on(sig, f) conns[#conns + 1] = sig:Connect(f) end

-- ------------------------------------------------------------------------------------------------ state
local hum, root
local function refresh()
	local c = lp.Character
	hum = c and c:FindFirstChildOfClass("Humanoid")
	root = c and c:FindFirstChild("HumanoidRootPart")
end
refresh()
on(lp.CharacterAdded, function() task.wait(0.5); refresh() end)

local function gameT()
	if not E then return nil end
	local tl = E.tl
	local n = tl:count()
	return n > 0 and tl:get("TotalTime", n, 1) or 0
end
local function speedNow()
	if not E then return 1 end
	local ok, s = pcall(function() return E.time:wanted() end)
	return ok and s or 1
end
local function recording() return E ~= nil and E.mode == 2 and not E.paused end
local renderFrame, fps, dtHist, dtSum = 0, 0, {}, 0

-- events: per segment key (speed / fps / speed hack on) lists of numbers
local seg = {}
local function segKey()
	local s = speedNow()
	local f = fps
	local fb = (f < 75 and "60") or (f < 170 and "144") or (f < 300 and "240") or "uncapped"
	local on_ = E and E.settings:on("speedHack") and "on" or "off"
	return string.format("speed %s (hack %s), %s FPS", tostring(math.floor(s * 1000 + 0.5) / 1000), on_, fb)
end
local function add(name, v)
	local k = segKey()
	local s = seg[k]
	if not s then s = {}; seg[k] = s end
	local l = s[name]
	if not l then l = {}; s[name] = l end
	l[#l + 1] = v
end
local events = {} -- text lines, capped
local function event(text)
	if #events < 3000 then events[#events + 1] = string.format("%9.3f  %s  %s", clock(), segKey(), text) end
end

-- ------------------------------------------------------------------------------------------------ physics steps
-- the speed hack's decision for each physics step (Frame Step): run / held and why
local decision, decisions = "-", {}
-- held streaks: every step held for longer than Frame Step's own gap (1/s frames + 2), with what forced the steps
-- before it (the time paid back afterwards); and how long each run of forced steps lasted (game time)
local streak = { heldSince = nil, lastForced = nil, forcedGame = 0, forcedReason = nil }
local function streakStep(dec, dt)
	local t = clock()
	if dec == "held" then
		if not streak.heldSince then streak.heldSince = t end
		if streak.forcedGame > 0 then
			add("forced steps in a row: " .. streak.forcedReason .. " (game ms)", streak.forcedGame * 1000)
			streak.forcedGame = 0
		end
		return
	end
	if streak.heldSince then
		local s = E and E.time and E.time:wanted() or 1
		local limit = ((s < 1) and (math.ceil(1 / s) + 2) or 3) / math.max(fps, 20)
		local dur = t - streak.heldSince
		if dur > limit and streak.lastForced and t - streak.lastForced.t < 2 then
			add("held longer than the slider's gap, after " .. streak.lastForced.reason .. " (real ms)", dur * 1000)
			if dur > 0.15 then event(string.format("HELD %.0f ms after %s steps (limit %.0f ms)", dur * 1000, streak.lastForced.reason, limit * 1000)) end
		end
		streak.heldSince = nil
	end
	if dec:sub(1, 7) == "forced:" then
		local reason = dec:sub(8)
		streak.lastForced = { t = t, reason = reason }
		if streak.forcedReason ~= reason and streak.forcedGame > 0 then
			add("forced steps in a row: " .. streak.forcedReason .. " (game ms)", streak.forcedGame * 1000)
			streak.forcedGame = 0
		end
		streak.forcedReason = reason
		streak.forcedGame = streak.forcedGame + dt
	elseif streak.forcedGame > 0 then
		add("forced steps in a row: " .. streak.forcedReason .. " (game ms)", streak.forcedGame * 1000)
		streak.forcedGame = 0
	end
end
local origStepBegin
if E and E.time and E.time.stepBegin then
	origStepBegin = E.time.stepBegin
	E.time.stepBegin = function(self, dt, ...)
		local FS = self.SH and self.SH.FS
		local acc0 = FS and FS.acc
		local st = hum and hum.Parent and hum:GetState() or nil
		local fm = hum and hum.Parent and hum.FloorMaterial or nil
		local r = origStepBegin(self, dt, ...)
		if FS and FS.on then
			if r == false then
				decision = "held"
			else
				-- (ran because the slider's time was there, or forced: a timed state / a touched free part. The
				-- accumulator counts time since d8792e7 (acc += s x dt, a step costs dt) and steps before it (acc += s,
				-- a step costs 1): which one is told by how it changed)
				local d, s, a1 = tonumber(dt) or 0, FS.s or 1, FS.acc
				local slider = true
				if acc0 ~= nil and a1 ~= nil then
					if math.abs(a1 - (acc0 + s * d - d)) < 1e-9 then slider = acc0 + s * d >= d - 1e-9
					elseif math.abs(a1 - (acc0 + s - 1)) < 1e-6 then slider = acc0 + s >= 1 - 1e-6 end
				end
				if slider then decision = "run"
				elseif st == ST.Jumping or st == ST.Landed or ((st == ST.Running or st == ST.RunningNoPhysics) and fm == AIR) then
					decision = "forced:" .. (st and st.Name or "?") .. ((fm == AIR) and "/air" or "")
				else decision = "forced:touch" end
			end
		else
			decision = "normal"
		end
		decisions[decision] = (decisions[decision] or 0) + 1
		streakStep(decision, tonumber(dt) or 0)
		return r
	end
end

local ring, RING = {}, 2400 -- the last 10 s of physics steps at 240 steps/s
local ringN = 0
local function pushRow(r) ringN = ringN + 1; ring[(ringN - 1) % RING + 1] = r end
local function rowsSince(t0)
	local out = {}
	local first = math.max(1, ringN - RING + 1)
	for i = first, ringN do
		local r = ring[(i - 1) % RING + 1]
		if r and r.t >= t0 then out[#out + 1] = r end
	end
	return out
end
local function rowText(r)
	return string.format("    %8.3f g%s dt%.4f %-22s %-16s floor %-10s anch %s pos %.2f,%.2f,%.2f vel %.2f,%.2f,%.2f md %.2f jump %s",
		r.t, r.g and string.format("%.3f", r.g) or "-", r.dt, r.dec, r.st, r.fm, r.an and "y" or "n",
		r.p.X, r.p.Y, r.p.Z, r.v.X, r.v.Y, r.v.Z, r.md, r.j and "y" or "n")
end

-- pending measurements
local jumpP, moveP, air, land = nil, nil, nil, nil
local freeze = { still = 0, since = nil, lastPos = nil, dumps = 0 }
local stepAfterPress = nil

on(RS.PostSimulation, function(dt)
	if not (hum and hum.Parent and root and root.Parent) then return end
	local t = clock()
	local p, v = root.Position, root.AssemblyLinearVelocity
	local st = hum:GetState()
	local fm = hum.FloorMaterial
	local row = { t = t, g = gameT(), dt = dt, dec = decision, st = st.Name, fm = fm.Name, an = root.Anchored, p = p, v = v,
		md = hum.MoveDirection.Magnitude, j = hum.Jump }
	pushRow(row)
	decision = "-"
	if not recording() then
		-- (paused / Idle / Test: nothing pending, and a standstill doesn't carry over to the next recording)
		jumpP, moveP, air, land = nil, nil, nil, nil
		freeze.still, freeze.since, freeze.lastPos = 0, nil, nil
		return
	end
	-- jump: from the press to the root rising (physics)
	if jumpP and not jumpP.phys and p.Y > jumpP.y0 + 0.05 and v.Y > 1 then
		jumpP.phys = { t = t, g = row.g, f = renderFrame }
	end
	if jumpP and not jumpP.state and st == ST.Jumping then jumpP.state = { t = t, g = row.g } end
	-- airborne / landing: first contact = the floor seen again (FloorMaterial), or the fall stopped by something
	-- (the vertical speed jumps up from a fall), whichever comes first; held steps (root anchored) are skipped
	local inAir = fm == AIR
	if air and not root.Anchored then
		local stopped = air.lastVy and air.lastVy < -3 and v.Y > air.lastVy + 5
		if not inAir or stopped then
			if t - air.t > 0.05 and (row.g == nil or air.g == nil or row.g - air.g > 0.08) then
				land = { t = t, g = row.g, f = renderFrame, h = air.maxY - p.Y, vy = air.minVy }
				event(string.format("contact (%s): fell %.2f studs, vy %.2f", stopped and "fall stopped" or "floor seen", land.h, land.vy))
			end
			air = nil
		end
	end
	if inAir and not land then
		if not air then air = { t = t, g = row.g, maxY = p.Y, minVy = 0 } end
		if p.Y > air.maxY then air.maxY = p.Y end
		if v.Y < air.minVy then air.minVy = v.Y end
		if not root.Anchored then air.lastVy = v.Y end
	end
	if land then
		if not land.landed and st == ST.Landed then land.landed = { t = t, g = row.g } end
		local canJump = (st == ST.Running or st == ST.RunningNoPhysics) and hum:GetStateEnabled(ST.Jumping)
		if not land.ready and canJump then
			land.ready = { t = t, g = row.g, f = renderFrame }
			local function d(a) return a and (a.t - land.t) * 1000 or -1 end
			local function dg(a) return (a and a.g and land.g) and (a.g - land.g) * 1000 or -1 end
			add("land: contact -> Landed (real ms)", d(land.landed))
			add("land: contact -> can walk / jump (real ms)", d(land.ready))
			add("land: contact -> can walk / jump (game ms)", dg(land.ready))
			add("land: contact -> can walk / jump (frames)", land.ready.f - land.f)
			event(string.format("landed: Landed +%.1f ms, ready +%.1f ms real / +%.1f ms game / %d frames (fell %.2f, vy %.2f)",
				d(land.landed), d(land.ready), dg(land.ready), land.ready.f - land.f, land.h, land.vy))
			land = nil
		elseif t - land.t > 3 then
			event("landed: never ready to walk / jump within 3 s (state " .. st.Name .. ")")
			add("land: never ready", 1)
			land = nil
		end
	end
	-- input -> movement
	if moveP and not moveP.phys then
		local d = Vector3.new(p.X - moveP.p.X, 0, p.Z - moveP.p.Z).Magnitude
		if d > 0.05 then moveP.phys = { t = t, g = row.g, f = renderFrame } end
	end
	-- freeze: a direction held, recording, and the root doesn't move for longer than the speed hack's own gaps
	-- (below 1x Frame Step holds up to 1/s frames in a row by design: the limit is that + 3 frames, in time)
	local s = speedNow()
	local limitSec = ((s < 1) and (math.ceil(1 / s) + 3) or 4) / math.max(fps, 20)
	local movedNow = freeze.lastPos and (p - freeze.lastPos).Magnitude >= 1e-3
	if row.md > 0.1 and freeze.lastPos and not movedNow then
		freeze.still = freeze.still + 1
		if freeze.still == 1 then freeze.since = t end
	else
		-- (moving again, or the direction let go: was the standstill longer than the limit?)
		if freeze.still > 0 and freeze.since and (t - freeze.since) > limitSec then
			local dur = (t - freeze.since) * 1000
			local rp = RaycastParams.new()
			rp.FilterDescendantsInstances = { lp.Character }
			rp.FilterType = Enum.RaycastFilterType.Exclude
			local ground = workspace:Raycast(p, Vector3.new(0, -5, 0), rp)
			local floorName = ground and ground.Instance and ground.Instance:GetFullName() or "?"
			add("freeze: count", 1)
			add("freeze: real ms", dur)
			local held, forced, ran = 0, 0, 0
			local rows = rowsSince(freeze.since - 0.2)
			for _, r in ipairs(rows) do
				if r.dec == "held" then held = held + 1 elseif r.dec:sub(1, 6) == "forced" then forced = forced + 1 elseif r.dec == "run" then ran = ran + 1 end
			end
			event(string.format("FREEZE %.0f ms while a direction was held, floor %s, steps held %d / run %d / forced %d", dur, floorName, held, ran, forced))
			if freeze.dumps < 8 then
				freeze.dumps = freeze.dumps + 1
				for i = 1, math.min(#rows, 160) do events[#events + 1] = rowText(rows[i]) end
			end
		end
		freeze.still = 0
	end
	freeze.lastPos = p
end)

-- ------------------------------------------------------------------------------------------------ render frames
local anim = { name = nil, tp = nil, still = 0, switches = {}, }
local function mainTrack()
	local a = hum and hum:FindFirstChildOfClass("Animator")
	if not a then return nil end
	local best
	for _, tr in ipairs(a:GetPlayingAnimationTracks()) do
		if not best or tr.WeightCurrent > best.WeightCurrent then best = tr end
	end
	return best
end
local function trackName(tr)
	local a = tr and tr.Animation
	if not a then return "none" end
	local n = a.Name
	if n == "" or n == "Animation" then n = (a.AnimationId or ""):match("%d+$") or "?" end
	return n
end
local focus0
on(RS.RenderStepped, function(dt)
	renderFrame = renderFrame + 1
	dtHist[#dtHist + 1] = dt
	dtSum = dtSum + dt
	if #dtHist > 60 then dtSum = dtSum - table.remove(dtHist, 1) end
	fps = #dtHist / math.max(1e-6, dtSum)
	if not (hum and hum.Parent and root and root.Parent) then return end
	local t = clock()
	if not recording() then anim.name = nil; return end
	-- jump: shown on screen (the camera's focus rising: smoothing of the character or the camera would show here)
	if jumpP and not jumpP.disp and cam.Focus.Position.Y > jumpP.fy0 + 0.05 then jumpP.disp = { t = t, f = renderFrame } end
	if jumpP and (jumpP.phys and jumpP.disp or t - jumpP.t > 3) then
		local function d(a) return a and (a.t - jumpP.t) * 1000 or -1 end
		local gd = (jumpP.phys and jumpP.phys.g and jumpP.g) and (jumpP.phys.g - jumpP.g) * 1000 or -1
		if jumpP.phys then
			add("jump: press -> root rises (real ms)", d(jumpP.phys))
			add("jump: press -> root rises (game ms)", gd)
			add("jump: press -> root rises (frames)", jumpP.phys.f - jumpP.f)
			add("jump: press -> shown rising (real ms)", d(jumpP.disp))
			add("jump: press -> Jumping state (real ms)", d(jumpP.state))
		else
			add("jump: no jump within 3 s", 1)
		end
		event(string.format("jump: rises +%.1f ms real / +%.1f ms game / %d frames, shown +%.1f ms, Jumping state +%.1f ms",
			d(jumpP.phys), gd, jumpP.phys and (jumpP.phys.f - jumpP.f) or -1, d(jumpP.disp), d(jumpP.state)))
		jumpP = nil
	end
	if moveP and moveP.phys then
		add("move: press -> root moves (real ms)", (moveP.phys.t - moveP.t) * 1000)
		add("move: press -> root moves (frames)", moveP.phys.f - moveP.f)
		if moveP.phys.g and moveP.g then add("move: press -> root moves (game ms)", (moveP.phys.g - moveP.g) * 1000) end
		moveP = nil
	elseif moveP and t - moveP.t > 3 then
		add("move: no movement within 3 s", 1); moveP = nil
	end
	-- animations: the main track, its time and speed
	local tr = mainTrack()
	local name = trackName(tr)
	local st = hum:GetState()
	if name ~= anim.name then
		local sw = anim.switches
		sw[#sw + 1] = { t = t, from = anim.name, to = name }
		if #sw > 3 then table.remove(sw, 1) end
		-- A -> B -> A within 0.3 s: flipping
		if #sw >= 2 then
			local a, b = sw[#sw - 1], sw[#sw]
			if b.to == a.from and b.t - a.t < 0.3 then
				add("anim: flip " .. tostring(a.from) .. "<->" .. tostring(a.to), 1)
				event(string.format("anim FLIP %s -> %s -> %s within %.0f ms (state %s, speed %.2f)", tostring(a.from), tostring(a.to), tostring(b.to),
					(b.t - a.t) * 1000, st.Name, Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude))
			end
		end
		add("anim: changes", 1)
		anim.name, anim.tp, anim.still = name, tr and tr.TimePosition, 0
		return
	end
	if not tr then return end
	local tp, len, spd = tr.TimePosition, tr.Length, tr.Speed
	if anim.tp then
		local d = tp - anim.tp
		local wrapped = tr.Looped and len > 0 and anim.tp > len - 0.15 and tp < 0.15
		local expect = spd * dt
		if d < -0.03 and not wrapped then
			add("anim: time jumps back (" .. name .. ")", 1)
			event(string.format("anim JUMP BACK %s %.3f -> %.3f (speed %.3f, state %s)", name, anim.tp, tp, spd, st.Name))
		elseif d > expect + 0.05 then
			add("anim: time jumps forward (" .. name .. ")", 1)
			event(string.format("anim JUMP FORWARD %s %.3f -> %.3f (expected +%.3f, speed %.3f, state %s)", name, anim.tp, tp, expect, spd, st.Name))
		end
		if spd > 0.01 and math.abs(d) < 1e-5 and not (not tr.Looped and len > 0 and tp >= len - 0.02) then
			anim.still = anim.still + 1
			if anim.still == 15 then
				add("anim: stuck (" .. name .. ")", 1)
				event(string.format("anim STUCK %s at %.3f for 15 frames (speed %.3f, state %s)", name, tp, spd, st.Name))
			end
		else
			anim.still = 0
		end
	end
	-- a walk while in the air, or idle while running: the wrong animation for the state
	local hs = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
	if (name == "walk" and (st == ST.Freefall or st == ST.Jumping)) or (name == "idle" and st == ST.Running and hs > 4) then
		add("anim: wrong for the state (" .. name .. " in " .. st.Name .. ")", 1)
	end
	anim.tp = tp
end)

-- ------------------------------------------------------------------------------------------------ input
local MOVE_KEYS = { [Enum.KeyCode.W] = true, [Enum.KeyCode.A] = true, [Enum.KeyCode.S] = true, [Enum.KeyCode.D] = true }
local save
-- a press (a key, or SpeedLog.Press from a test script that moves the character itself)
local function press(kind)
	if not (hum and root and recording()) then return end
	local t = clock()
	if kind == "jump" and hum.FloorMaterial ~= AIR and not jumpP then
		jumpP = { t = t, g = gameT(), f = renderFrame, y0 = root.Position.Y, fy0 = cam.Focus.Position.Y }
	elseif kind == "move" and not moveP and hum.FloorMaterial ~= AIR
		and Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude < 0.5 then
		moveP = { t = t, g = gameT(), f = renderFrame, p = root.Position }
	end
end
on(UIS.InputBegan, function(input)
	if input.KeyCode == Enum.KeyCode.F8 then task.defer(function() save() end) return end
	if input.KeyCode == Enum.KeyCode.Space then press("jump")
	elseif MOVE_KEYS[input.KeyCode] then press("move") end
end)

-- ------------------------------------------------------------------------------------------------ the file
local started = os.date("%Y%m%d-%H%M%S")
local function stats(l)
	local c = table.clone(l)
	table.sort(c)
	local n = #c
	local sum = 0
	for _, x in ipairs(c) do sum = sum + x end
	local function q(p) return c[math.max(1, math.min(n, math.floor(p * (n - 1) + 1.5)))] end
	return string.format("n %d  median %.1f  mean %.1f  min %.1f  p90 %.1f  max %.1f", n, q(0.5), sum / n, c[1], q(0.9), c[n])
end
save = function()
	local out = {}
	out[#out + 1] = "HappaTAS speed log (temporary diagnostic tool) - build " .. tostring(LABEL) .. ", started " .. started .. ", saved " .. os.date("%Y-%m-%d %H:%M:%S")
	out[#out + 1] = "engine seen: " .. tostring(E ~= nil) .. " (a debug copy is needed for game times and the step decisions)"
	local dl = {}
	for k, n in pairs(decisions) do dl[#dl + 1] = k .. " " .. n end
	table.sort(dl)
	out[#out + 1] = "physics steps by decision: " .. table.concat(dl, ", ")
	out[#out + 1] = ""
	out[#out + 1] = "== SUMMARY (per speed / FPS; delays in ms unless it says frames)"
	local keys = {}
	for k in pairs(seg) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do
		out[#out + 1] = "-- " .. k
		local names = {}
		for name in pairs(seg[k]) do names[#names + 1] = name end
		table.sort(names)
		for _, name in ipairs(names) do
			local l = seg[k][name]
			local single = name:find("count", 1, true) or name:find("no ", 1, true) or name:find("never", 1, true) or name:sub(1, 6) == "anim: "
			if single then
				local sum = 0
				for _, x in ipairs(l) do sum = sum + x end
				out[#out + 1] = string.format("   %-48s %d", name, sum)
			else
				out[#out + 1] = string.format("   %-48s %s", name, stats(l))
			end
		end
	end
	out[#out + 1] = ""
	out[#out + 1] = "== EVENTS (real clock, then the speed / FPS, then what happened; freezes list the physics steps around them)"
	for _, e in ipairs(events) do out[#out + 1] = e end
	pcall(function() if not isfolder("HappaTasPort/SpeedLog") then makefolder("HappaTasPort/SpeedLog") end end)
	local path = "HappaTasPort/SpeedLog/speedlog_" .. tostring(LABEL):gsub("[^%w_%-]", "_") .. "_" .. started .. ".txt"
	writefile(path, table.concat(out, "\n"))
	print("[SpeedLog] saved " .. path)
	return path
end

genv.SpeedLog = {
	Save = save,
	Mark = function(text) event("MARK " .. tostring(text)) end,
	Press = press,
	Stop = function()
		for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
		conns = {}
		if E and origStepBegin and E.time then E.time.stepBegin = origStepBegin end
		genv.SpeedLog = nil
	end,
}
-- (HappaTAS unloaded: give its function back too)
if E and E.life and E.life.own then pcall(function() E.life:own(function() if genv.SpeedLog then genv.SpeedLog.Stop() end end) end) end
print("[SpeedLog] logging (" .. tostring(LABEL) .. ", engine " .. tostring(E ~= nil) .. "). F8 saves to HappaTasPort/SpeedLog/")
