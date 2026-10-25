-- ================================================================================================
--  CO RECORDER  (HappaTAS 3, client objects): what each recorded frame stores for the client objects
--  (V2.38.17 p13_clientobjects.lua 521-587, 674-1110, function by function; the bytes are V2's).
--  KEYFRAME + VELOCITY: a part is written when the velocity model stops explaining it, so spinners /
--  sliders cost a record every few frames and static parts cost nothing. Everything is measured on the
--  clocks playback rebuilds: 0 = TAS clock (TotalTime), 1 = simulation time without the pauses (physics
--  parts, HappaTAS holds them while paused), 2 = wall clock, 3 = simulation time with the pauses.
--  Start states (V2.38.15): a part skipped while on its registration state gets that state written into
--  the full snapshots recorded before its first change (this session only), so playback shows it there.
-- ================================================================================================
local Format = import("world/co/format")
local Registry = import("world/co/registry")

local Recorder = {}
Recorder.__index = Recorder

local floor, abs, sqrt = math.floor, math.abs, math.sqrt
local putVar, putZig, bufToString = Format.putVar, Format.putZig, Format.bufToString
local buildPose3, twistFrom = Format.buildPose3, Format.twistFrom
local readProps = Registry.readProps
local ZV = Vector3.zero
local K_KEY, K_ROT, K_LV, K_AV = Format.K_KEY, Format.K_ROT, Format.K_LV, Format.K_AV
local K_TR, K_CC, K_CCV, K_COL, K_SZ, K_MAT, K_DROP = Format.K_TR, Format.K_CC, Format.K_CCV, Format.K_COL, Format.K_SZ, Format.K_MAT, Format.K_DROP
local K_CK1, K_CK2 = Format.K_CK1, Format.K_CK2
local SIM_HZ, WALL_HZ = Format.SIM_HZ, Format.WALL_HZ
local CLOCK_FLAG = { 0, K_CK1, K_CK2, K_CK1 + K_CK2 }
local H_N = 4 -- poses kept per moving scripted part (its twist is measured over them)
local CARRY_BIT = { 8, 16, 32 }
local V_MIN, W_MIN = 0.05, 0.005
local SCRIPT_CLOCKS = { 1, 3, 4 }

-- co = the plugin: co:stampOf(i) (which recorded frame timeline frame i is), co.dataVersion, co.settings,
-- co.onStartsAdded() (the player's checkpoints were made from frames a start state was added to)
function Recorder.new(R, co)
	local cfg = R.cfg
	local self = setmetatable({
		R = R, co = co,
		FULL_EVERY = cfg.FullEvery or 2400, FULL_SECS = cfg.FullSeconds or 10, VIS_EVERY = cfg.VisEvery or 6,
		POS_TOL2 = (cfg.PosTolerance or 0.015) ^ 2, ROT_TOL = cfg.RotTolerance or 0.0015, MAX_AGE = cfg.MaxModelAge or 1.0,
		A = {}, P = {}, K = {},
		-- the clocks of the frame being recorded, in seconds, exactly as playback rebuilds them: CLK[c + 1] for
		-- clock c. DCLK = their change since the frame before (haveD: that frame was recorded too). base = the
		-- raw readings taken off (skip moves on by every pause, rawS = the simulation time of the last frame)
		CLK = { 0, 0, 0, 0 }, DCLK = { 0, 0, 0, 0 }, lastCLK = { 0, 0, 0, 0 }, haveD = false,
		base = { skip = 0, real = 0, wall = 0, rawS = nil },
		run = { 0, 0, 0 }, -- clocks 1-3 as last stored (since the last full snapshot), like the decoder keeps them
		usedPrev = { false, false, false },
		lastRec = nil, lastRecVer = -1, -- the stamp of the frame recorded last, and the data version then
		chainNo = 0, forceFull = true, newChain = true, recGen = 0, visCursor = 1,
		lastFullF = 0, lastFullT = -1e9,
		starts = { log = {}, tl = nil },
	}, Recorder)
	return self
end

function Recorder:reset()
	self.starts.log, self.starts.tl = {}, nil
	self.forceFull = true
end

-- ------------------------------------------------------------------------------------------------ visibility
local function isVisible(R, part, s, ppos, cam, camPos, vpX, vpY, tanHalf, strict)
	if s.vd then -- size / transparency changed (or never read)
		s.vd = false
		s.rad = part.Size.Magnitude * 0.5
		s.tr = part.Transparency
	end
	local pos = part.Position
	local dx, dy, dz = pos.X - ppos.X, pos.Y - ppos.Y, pos.Z - ppos.Z
	local d2 = dx * dx + dy * dy + dz * dz
	local rad = s.rad
	local maxR = R.RADIUS + rad
	if d2 > maxR * maxR then return false end
	if strict then
		-- Frustum Culling CO: close parts always, otherwise only visible parts on screen
		if d2 <= 625 then return true end
		if s.tr >= 1 and part.LocalTransparencyModifier >= 1 then return false end
		if not cam then return true end
		local sp, onScreen = cam:WorldToViewportPoint(pos)
		return onScreen and sp.Z > 0
	end
	local d = sqrt(d2)
	if d - rad <= R.ALWAYS then return true end
	if not cam then return true end
	if (pos - camPos).Magnitude <= rad * 1.2 + 6 then return true end
	local sp = cam:WorldToViewportPoint(pos)
	local z = sp.Z
	if z <= 0 then return false end
	local rpx = rad * vpY / (2 * tanHalf * z)
	local mx, my = vpX * 0.25 + rpx, vpY * 0.25 + rpx
	return sp.X >= -mx and sp.X <= vpX + mx and sp.Y >= -my and sp.Y <= vpY + my
end

function Recorder:updateVisibility(ppos, full)
	local R = self.R
	local plist = R.plist
	local n = #plist
	if n == 0 then return end
	local cam = workspace.CurrentCamera
	local camPos, vpX, vpY, tanHalf
	if cam then
		camPos = cam.CFrame.Position
		local vp = cam.ViewportSize
		vpX, vpY = vp.X, vp.Y
		tanHalf = math.tan(math.rad(cam.FieldOfView) * 0.5)
		if tanHalf < 0.01 then tanHalf = 0.01 end
	end
	local strict = self.co.settings:on("frustumCullingCO")
	local count = full and n or math.min(n, math.ceil(n / self.VIS_EVERY))
	local parts, S = R.parts, R.S
	for _ = 1, count do
		if self.visCursor > #plist then self.visCursor = 1 end
		local id = plist[self.visCursor]
		self.visCursor = self.visCursor + 1
		if id then
			local part, s = parts[id], S[id]
			if part and s and part.Parent then
				R:setActive(id, isVisible(R, part, s, ppos, cam, camPos, vpX, vpY, tanHalf, strict))
			else
				R:setActive(id, false)
			end
		end
	end
end

local function playerPosNow()
	local plr = game:GetService("Players").LocalPlayer
	local char = plr and plr.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return root and root.Position or ZV
end

-- ------------------------------------------------------------------------------------------------ start states
-- the record of a part's start state, as a full snapshot holds it (whole values: from nothing)
local function startRecord(id, s)
	local out, rc, rvv = {}, s.rc, s.rv
	putVar(out, id)
	putVar(out, K_KEY + K_ROT + K_TR + K_CC + (rvv[2] == 1 and K_CCV or 0) + K_COL + K_SZ + K_MAT)
	for i = 1, 12 do putZig(out, floor(rc[i] * 1000 + 0.5)) end
	putZig(out, rvv[1])
	out[#out + 1] = rvv[3] % 256; out[#out + 1] = rvv[4] % 256; out[#out + 1] = rvv[5] % 256
	for i = 6, 8 do putZig(out, rvv[i]) end
	putVar(out, rvv[9])
	return bufToString(out)
end

function Recorder:startsAdd(id, s)
	local starts, R, co = self.starts, self.R, self.co
	local log, tl = starts.log, starts.tl
	local rec, inChain = nil, false
	for i = #log, 1, -1 do
		local e = log[i]
		local str = (e.tl == tl) and co:stampOf(e.i) == e.stamp and tl:getList("v2CO", e.i) or nil
		if type(str) ~= "string" then
			table.remove(log, i) -- (cut frames, an optimized TAS or another TAS)
		elseif e.n > s.regN and e.n ~= R.frameNo then
			rec = rec or startRecord(id, s)
			tl:setList("v2CO", e.i, str .. rec)
			if e.n == self.lastFullF then inChain = true end
		end
	end
	if not rec then return end
	R.reg.used[id] = true
	if co.onStartsAdded then co.onStartsAdded() end
	if inChain then
		-- this chain starts with the start state now: the part's records go on from it
		local kp, pv, rc, rvv = s.kp, s.pv, s.rc, s.rv
		for i = 1, 12 do kp[i] = floor(rc[i] * 1000 + 0.5) end
		for i = 1, 9 do pv[i] = rvv[i] end
		s.lq[1], s.lq[2], s.lq[3], s.aq[1], s.aq[2], s.aq[3] = 0, 0, 0, 0, 0, 0
		s.dyn, s.chain, s.needBase = false, self.chainNo, false
	end
end

-- ------------------------------------------------------------------------------------------------ scripted parts
local function ringPush(s, cf, c1, c3, c4)
	local i = s.hp % H_N + 1
	s.hp = i
	s.hcf[i], s.h1[i], s.h3[i], s.h4[i] = cf, c1, c3, c4
	if s.hn < H_N then s.hn = s.hn + 1 end
end

-- scripted (anchored) parts: their last poses with the clock readings, and how steady each clock makes
-- the part's motion (the speed measured on the clock its script uses barely changes, on the others it
-- jumps with every frame's timing)
function Recorder:trackScripted(s, cf)
	local CLK, DCLK, lastCLK = self.CLK, self.DCLK, self.lastCLK
	local prev = s.prevCF
	if not (prev and self.haveD and s.prevFrame == self.R.frameNo - 1) then
		s.hn = 0
		ringPush(s, cf, CLK[1], CLK[3], CLK[4])
		return
	end
	local m = 0
	if cf ~= prev then
		local d = cf * prev:Inverse()
		local _, ang = d:ToAxisAngle()
		if ang == ang and ang > 1e-6 then
			local r = s.rad
			if r < 1 then r = 1 end
			m = ang * r
		end
		m = m + d.Position.Magnitude
	end
	-- (scripted parts: TAS clock, wall clock or game time; game time with or without the pauses changes the
	-- same from frame to frame, the one with them is used)
	local fit, esp = s.fit, s.esp
	for c = 1, 4 do
		local dt = DCLK[c]
		if dt > 1e-6 and dt < 0.25 then
			local sp = m / dt
			local e = esp[c]
			if e > 0 then
				local dev = (sp - e) / e
				if dev > 1 then dev = 1 elseif dev < -1 then dev = -1 end
				fit[c] = fit[c] * 0.9 + dev * dev * 0.1
				esp[c] = e * 0.7 + sp * 0.3
			elseif sp > 0 then
				esp[c] = sp
			end
		elseif m > 0 and dt <= 1e-6 then
			fit[c] = fit[c] * 0.9 + 0.1 -- it moved while this clock stood still: not its clock
		end
	end
	if s.hn == 0 then ringPush(s, prev, lastCLK[1], lastCLK[3], lastCLK[4]) end
	ringPush(s, cf, CLK[1], CLK[3], CLK[4])
end

-- the clock with the steadiest motion (another one has to be clearly better to take over)
local function bestClock(s)
	local fit, cur = s.fit, s.clk
	if cur == 2 then cur = 3 end
	local best = cur
	for _, c in ipairs(SCRIPT_CLOCKS) do
		if fit[c] < fit[best] then best = c end
	end
	if best ~= cur and fit[best] < fit[cur] * 0.7 then return best end
	return cur
end

-- a scripted part's twist over the poses it was seen in (the oldest kept one to now) on clock c
function Recorder:scriptedTwist(s, cf, c)
	local n = s.hn
	if n < 2 then return ZV, ZV end
	local j = (s.hp - n) % H_N + 1
	local hc = s.h3
	if c == 1 then hc = s.h1 elseif c == 4 then hc = s.h4 end
	return twistFrom(s.hcf[j], cf, self.CLK[c] - hc[j])
end

-- ------------------------------------------------------------------------------------------------ one part
function Recorder:recordObject(out, id, part, s)
	local R = self.R
	local A, P, K, CLK = self.A, self.P, self.K, self.CLK
	local POS_TOL2, ROT_TOL = self.POS_TOL2, self.ROT_TOL
	if s.gen ~= self.recGen then
		s.gen = self.recGen
		s.prevCF, s.hn = nil, 0
	end

	local cf = part.CFrame
	local cp = s.cp
	-- the properties are re-read only when one of them changed since the last read
	if s.pd then
		s.pd = false
		readProps(part, cp)
		local rvv, off = s.rv, false
		for i = 1, 9 do
			if cp[i] ~= rvv[i] then off = true break end
		end
		s.propsOff = off
	end

	-- most parts never move: still exactly on the start CFrame with the properties they started with,
	-- so only the bookkeeping is kept (no maths, no velocity reads)
	local anchored = s.an
	if not s.moved and not s.propsOff and cf == s.rcf then
		s.prevCF, s.prevFrame, s.hn = cf, R.frameNo, 0
		s.atStart = true
		return
	end
	if anchored then self:trackScripted(s, cf) end
	s.prevCF, s.prevFrame = cf, R.frameNo

	local filled = false
	if not s.moved then
		local dev = false
		if cf ~= s.rcf then -- the exact start CFrame can't be outside the tolerance
			A[1], A[2], A[3], A[4], A[5], A[6], A[7], A[8], A[9], A[10], A[11], A[12] = cf:GetComponents()
			filled = true
			local rcv = s.rc
			local dx, dy, dz = A[1] - rcv[1], A[2] - rcv[2], A[3] - rcv[3]
			dev = dx * dx + dy * dy + dz * dz > POS_TOL2
			if not dev then
				for i = 4, 12 do
					if abs(A[i] - rcv[i]) > ROT_TOL then dev = true break end
				end
			end
		end
		if not dev then
			local rvv = s.rv
			for i = 1, 9 do
				if cp[i] ~= rvv[i] then dev = true break end
			end
		end
		if not dev then
			s.atStart = true
			return
		end
		s.moved = true
		if s.atStart and self.starts.tl then self:startsAdd(id, s) end
	end
	if not filled then
		A[1], A[2], A[3], A[4], A[5], A[6], A[7], A[8], A[9], A[10], A[11], A[12] = cf:GetComponents()
	end
	local x, y, z = A[1], A[2], A[3]

	local first = s.needBase or s.chain ~= self.chainNo
	local kp, lq, aq, pv = s.kp, s.lq, s.aq, s.pv
	if first then
		for i = 1, 12 do kp[i] = 0 end
		lq[1], lq[2], lq[3], aq[1], aq[2], aq[3] = 0, 0, 0, 0, 0, 0
		for i = 1, 9 do pv[i] = 0 end
		s.dyn = false
	end

	-- does the model still explain the part? (the same maths and clock as playback)
	local needKey = first
	if not first then
		if s.dyn then
			local age = CLK[s.clk] - s.kT
			if age > self.MAX_AGE then
				needKey = true
			else
				local pc = buildPose3(
					kp[1] / 1000, kp[2] / 1000, kp[3] / 1000,
					kp[4] / 1000, kp[5] / 1000, kp[6] / 1000, kp[7] / 1000, kp[8] / 1000, kp[9] / 1000, kp[10] / 1000, kp[11] / 1000, kp[12] / 1000,
					lq[1] / 1000, lq[2] / 1000, lq[3] / 1000, aq[1] / 1000, aq[2] / 1000, aq[3] / 1000, age)
				P[1], P[2], P[3], P[4], P[5], P[6], P[7], P[8], P[9], P[10], P[11], P[12] = pc:GetComponents()
			end
		else
			for i = 1, 12 do P[i] = kp[i] / 1000 end
		end
		if not needKey then
			local dx, dy, dz = x - P[1], y - P[2], z - P[3]
			if dx * dx + dy * dy + dz * dz > POS_TOL2 then
				needKey = true
			else
				for i = 4, 12 do
					if abs(A[i] - P[i]) > ROT_TOL then needKey = true break end
				end
			end
		end
	end

	local trD  = first or cp[1] ~= pv[1]
	local ccD  = first or cp[2] ~= pv[2]
	local colD = first or cp[3] ~= pv[3] or cp[4] ~= pv[4] or cp[5] ~= pv[5]
	local szD  = first or cp[6] ~= pv[6] or cp[7] ~= pv[7] or cp[8] ~= pv[8]
	local matD = first or cp[9] ~= pv[9]
	if not (needKey or trD or ccD or colD or szD or matD) then return end

	local flags = 0
	local rotChanged = false
	local l1, l2, l3, a1, a2, a3 = 0, 0, 0, 0, 0, 0
	local clk = s.clk
	if needKey then
		for i = 1, 12 do K[i] = floor(A[i] * 1000 + 0.5) end
		rotChanged = first
		if not first then
			for i = 4, 12 do
				if K[i] ~= kp[i] then rotChanged = true break end
			end
		end
		-- physics parts move on the simulation clock (without the pauses: HappaTAS holds them) and report
		-- their velocity: the one at the part's position (an assembly's own velocity is its centre of
		-- mass's). Scripted parts: measured over the last frames on the clock their motion follows
		local L, W
		if anchored then
			clk = bestClock(s)
			L, W = self:scriptedTwist(s, cf, clk)
		else
			clk = 2
			W = part.AssemblyAngularVelocity
			L = part:GetVelocityAtPosition(cf.Position)
		end
		local lm, wm = L.Magnitude, W.Magnitude
		if lm >= V_MIN and lm < 5000 then
			l1, l2, l3 = floor(L.X * 1000 + 0.5), floor(L.Y * 1000 + 0.5), floor(L.Z * 1000 + 0.5)
		end
		if wm >= W_MIN and wm < 500 then
			a1, a2, a3 = floor(W.X * 1000 + 0.5), floor(W.Y * 1000 + 0.5), floor(W.Z * 1000 + 0.5)
		end
		flags = K_KEY
		if rotChanged then flags = flags + K_ROT end
		if l1 ~= 0 or l2 ~= 0 or l3 ~= 0 then flags = flags + K_LV end
		if a1 ~= 0 or a2 ~= 0 or a3 ~= 0 then flags = flags + K_AV end
		-- (the clock only matters for a part that moves on its own)
		if flags >= K_LV then flags = flags + CLOCK_FLAG[clk] end
	end
	if trD then flags = flags + K_TR end
	if ccD then flags = flags + K_CC + (cp[2] == 1 and K_CCV or 0) end
	if colD then flags = flags + K_COL end
	if szD then flags = flags + K_SZ end
	if matD then flags = flags + K_MAT end

	putVar(out, id)
	putVar(out, flags)
	if needKey then
		for i = 1, 3 do putZig(out, K[i] - kp[i]); kp[i] = K[i] end
		if rotChanged then
			for i = 4, 12 do putZig(out, K[i] - kp[i]); kp[i] = K[i] end
		end
		if l1 ~= 0 or l2 ~= 0 or l3 ~= 0 then putZig(out, l1); putZig(out, l2); putZig(out, l3) end
		if a1 ~= 0 or a2 ~= 0 or a3 ~= 0 then putZig(out, a1); putZig(out, a2); putZig(out, a3) end
		lq[1], lq[2], lq[3], aq[1], aq[2], aq[3] = l1, l2, l3, a1, a2, a3
		s.dyn = (l1 ~= 0 or l2 ~= 0 or l3 ~= 0 or a1 ~= 0 or a2 ~= 0 or a3 ~= 0)
		s.clk = clk
		s.kT = CLK[clk]
	end
	if trD then putZig(out, cp[1] - pv[1]); pv[1] = cp[1] end
	if ccD then pv[2] = cp[2] end
	if colD then
		out[#out + 1] = cp[3] % 256; out[#out + 1] = cp[4] % 256; out[#out + 1] = cp[5] % 256
		pv[3], pv[4], pv[5] = cp[3], cp[4], cp[5]
	end
	if szD then
		for i = 6, 8 do putZig(out, cp[i] - pv[i]); pv[i] = cp[i] end
	end
	if matD then putVar(out, cp[9]); pv[9] = cp[9] end

	s.needBase = false
	s.chain = self.chainNo
	R.reg.used[id] = true
end

-- ------------------------------------------------------------------------------------------------ frames
-- lastStamp = the stamp of the TAS's last frame when recording starts (after cut frames were removed), nil
-- for an empty TAS. Unpausing right where the recorder stopped keeps every chain going: the parts were put
-- back on their recorded poses with their recorded velocities, and the clocks skip the pause. After cut
-- frames, a loaded or edited TAS or the first recording, every part starts again (full snapshot)
function Recorder:beginRecording(lastStamp)
	local R, base = self.R, self.base
	self.recGen = self.recGen + 1
	R.dropQ = {}
	self.haveD = false
	local cont = lastStamp ~= nil and lastStamp == self.lastRec and self.lastRecVer == self.co.dataVersion and base.rawS ~= nil
	local rawS, rawW = time(), os.clock()
	if cont then
		-- physics parts were held while paused: their clock skips the pause; scripts ran on: the other
		-- clocks don't
		base.skip = base.skip + (rawS - base.rawS)
	else
		self.forceFull = true
		self.newChain = true
		base.skip, base.real, base.wall = rawS, rawS, rawW
	end
	if R:isReady() then self:updateVisibility(playerPosNow(), true) end
end

-- a physics step the speed hack's Frame Step held everything for: like a pause, physics parts didn't move
function Recorder:skipSim(dt)
	self.base.skip = self.base.skip + (tonumber(dt) or 0)
end

-- tNow = TotalTime of the frame being recorded (TAS clock); simNow / wallNow = time() and os.clock()
-- when that frame started (its render step); tl / n = the frame the result goes into (its stamp)
function Recorder:record(playerPos, tNow, simNow, wallNow, tl, n, stamp)
	local R = self.R
	if not R:isReady() then return nil end
	R.frameNo = R.frameNo + 1
	local frameNo = R.frameNo
	local starts, base, CLK, DCLK, lastCLK, run = self.starts, self.base, self.CLK, self.DCLK, self.lastCLK, self.run
	starts.tl = tl
	tNow = tNow or 0
	simNow, wallNow = simNow or tNow, wallNow or tNow
	local val = {
		floor((simNow - base.skip) * SIM_HZ + 0.5),
		floor((wallNow - base.wall) * WALL_HZ + 0.5),
		floor((simNow - base.real) * SIM_HZ + 0.5),
	}
	CLK[1], CLK[2], CLK[3], CLK[4] = tNow, val[1] / SIM_HZ, val[2] / WALL_HZ, val[3] / SIM_HZ
	for c = 1, 4 do DCLK[c] = CLK[c] - lastCLK[c] end

	-- a full snapshot every FULL_SECS of TAS time (and at most every FULL_EVERY frames: playback
	-- looks 3000 frames back for one when it seeks)
	local full = self.forceFull or frameNo - self.lastFullF >= self.FULL_EVERY or tNow - self.lastFullT >= self.FULL_SECS
		or tNow < self.lastFullT
	self.forceFull = false
	if full then
		self.chainNo = self.chainNo + 1
		self.lastFullF, self.lastFullT = frameNo, tNow
		if tl and n == tl:count() then
			local log = starts.log
			if log[1] and log[1].tl ~= tl then log = {}; starts.log = log end
			log[#log + 1] = { tl = tl, i = n, stamp = stamp, n = frameNo }
		end
	end

	self:updateVisibility(playerPos, false)

	local body = {}
	for id in pairs(R.dropQ) do
		putVar(body, id)
		putVar(body, K_DROP)
	end
	R.dropQ = {}

	local anyDyn = false
	local usedNow = { false, false, false }
	local actArr, parts, S = R.actArr, R.parts, R.S
	for i = 1, #actArr do
		local id = actArr[i]
		local part, s = parts[id], S[id]
		-- (removed parts are unregistered by DescendantRemoving; the visibility pass checks Parent too)
		if part and s then
			self:recordObject(body, id, part, s)
			if s.dyn and s.moved then
				anyDyn = true
				if s.clk > 1 then usedNow[s.clk - 1] = true end
			end
		end
	end

	lastCLK[1], lastCLK[2], lastCLK[3], lastCLK[4] = CLK[1], CLK[2], CLK[3], CLK[4]
	self.haveD = true
	base.rawS = simNow
	self.lastRec, self.lastRecVer = stamp, self.co.dataVersion
	-- a frame with only its header (the clocks) keeps frames alive while something moves by velocity
	-- (Optimize TAS keeps them, playback needs their clocks)
	if #body == 0 and not full and not anyDyn then
		self.usedPrev = usedNow
		return nil
	end
	-- the clocks moving parts use now or used in the frame before (playback blends from that frame)
	local b = full and 5 or 4
	if full then
		run[1], run[2], run[3] = 0, 0, 0
		if self.newChain then b = b + 64 end
		self.newChain = false
	end
	local carry = {}
	local usedPrev = self.usedPrev
	for i = 1, 3 do
		carry[i] = usedNow[i] or usedPrev[i]
		if carry[i] then b = b + CARRY_BIT[i] end
	end
	local out = { b }
	for i = 1, 3 do
		if carry[i] then
			local pred = 0
			if i == 2 and not full then pred = floor(((tl and n >= 1 and tl:get("FrameTime", n, 1)) or 0) * WALL_HZ + 0.5) end
			putZig(out, val[i] - run[i] - pred)
			run[i] = val[i]
		end
	end
	table.move(body, 1, #body, #out + 1, out)
	self.usedPrev = usedNow
	return bufToString(out)
end

return Recorder
