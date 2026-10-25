-- ================================================================================================
--  CO PLAYER  (HappaTAS 3, client objects): puts the parts where a run had them (V2.38.17
--  p13_clientobjects.lua 1196-1798, function by function). The records are applied onto a state per part
--  (v1, v2 and v3 records, each the way it was recorded); the pose at time t comes from the model, blended
--  towards the next keyframe over one frame ("Smooth Client Objects"). Poses are written in Heartbeat and
--  again at the end of the render step, so game scripts can't override them. Seeking starts from the
--  nearest checkpoint (made while paused) or the last full snapshot.
--  state layout: 1-3 position (x1000)  4-12 rotation (x1000)  13 transparency  14 can-collide  15-17 colour
--    18-20 size  21 material  23 mask  36-38 linear vel (x1000)  39-41 angular vel (x1000)  42-44 v1 spin
--    45 keyframe time (on its clock)  46 v1 spin flag  47 clock  48 "moves by velocity"  49 model (3 = screw
--    motion, v3)  50 version (new number on every change, so a pose / property write can be skipped)
-- ================================================================================================
local Format = import("world/co/format")

local Player = {}
Player.__index = Player

local floor, abs = math.floor, math.abs
local byte = string.byte
local V3, CF = Vector3.new, CFrame.new
local has, addMask = bit32.btest, bit32.bor
local rv, rz = Format.rv, Format.rz
local readClocks, clockValues = Format.readClocks, Format.clockValues
local buildPose, buildPose3 = Format.buildPose, Format.buildPose3
local F_CF, F_TR, F_CC, F_CCV, F_COL, F_SZ, F_MAT, F_ROT = Format.F_CF, Format.F_TR, Format.F_CC, Format.F_CCV, Format.F_COL, Format.F_SZ, Format.F_MAT, Format.F_ROT
local F_VEL, F_SPIN, F_SKIP = Format.F_VEL, Format.F_SPIN, Format.F_SKIP
local K_KEY, K_ROT, K_LV, K_AV = Format.K_KEY, Format.K_ROT, Format.K_LV, Format.K_AV
local K_TR, K_CC, K_CCV, K_COL, K_SZ, K_MAT, K_DROP = Format.K_TR, Format.K_CC, Format.K_CCV, Format.K_COL, Format.K_SZ, Format.K_MAT, Format.K_DROP
local K_CK1, K_CK2 = Format.K_CK1, Format.K_CK2
local I_TR, I_CC, I_COL, I_SZ, I_MAT, I_MASK, I_VER = Format.I_TR, Format.I_CC, Format.I_COL, Format.I_SZ, Format.I_MAT, Format.I_MASK, Format.I_VER
local CK, MAX_CK = 120, 64
local IDENT = CFrame.new()

local function newState() return table.create(50, 0) end
local function copyState(s) return table.clone(s) end

-- co = the plugin: co.dataVersion, co.settings
function Player.new(R, co)
	local self = setmetatable({ R = R, co = co, verN = 0, touched = {}, cvScratch = { 0, 0, 0 }, nextScratch = {} }, Player)
	self:reset()
	return self
end

function Player:reset()
	self.cur, self.dyn, self.dropped = {}, {}, {}
	self.active, self.kind = false, "test"
	self.data, self.version, self.frame, self.sweep = nil, -1, nil, 0
	self.ck, self.ckN, self.ckData, self.ckVer, self.ckRun = {}, 0, nil, -1, {}
	self.t, self.curT, self.nextT = 0, 0, 0
	self.next, self.nextFor = {}, nil
	-- v3 clocks: run = the stored values as of the current frame (like the recorder's), cv / nv = the clocks
	-- of the current / next frame in seconds
	self.run, self.cv, self.nv = { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }
	self.hasData, self.hasVer, self.has, self.hasLen = nil, nil, nil, nil
	self.R.playActive = false
end

function Player:setActive(on)
	self.active = on
	self.R.playActive = on
end

-- the start states' recorder changed frames the checkpoints were made from
function Player:resetCheckpoints()
	self.ck, self.ckN, self.ckRun, self.ckData = {}, 0, {}, nil
	self.data, self.nextFor, self.hasData = nil, nil, nil
end

function Player:invalidate() self.nextFor = nil end

-- ------------------------------------------------------------------------------------------------ the model
-- playback time t (TAS clock) on clock c of a v3 keyframe (0 = TAS clock): the clock's values in the current
-- and the next frame, blended like the time itself
function Player:objTime(c, t)
	if c == 0 then return t end
	local v0, v1 = self.cv[c], self.nv[c]
	local span = self.nextT - self.curT
	local a = 0
	if span > 1e-6 then
		a = (t - self.curT) / span
		if a < 0 then a = 0 elseif a > 1 then a = 1 end
	end
	return v0 + (v1 - v0) * a
end

function Player:poseAt(s, t)
	local dt = nil
	if t and s[48] == 1 then dt = self:objTime(s[47], t) - s[45] end
	local build = buildPose
	if s[49] == 3 then build = buildPose3 end
	return build(
		s[1] / 1000, s[2] / 1000, s[3] / 1000,
		s[4] / 1000, s[5] / 1000, s[6] / 1000, s[7] / 1000, s[8] / 1000, s[9] / 1000, s[10] / 1000, s[11] / 1000, s[12] / 1000,
		s[36] / 1000, s[37] / 1000, s[38] / 1000, s[39] / 1000, s[40] / 1000, s[41] / 1000, dt)
end

-- ------------------------------------------------------------------------------------------------ decoding
-- old format (v1)
function Player:applyV1(str, cur, touched)
	local p, n = 2, #str
	while p <= n do
		local id, flags
		id, p = rv(str, p)
		flags, p = rv(str, p)
		local s = cur[id]
		if not s then s = newState(); cur[id] = s end
		self.verN = self.verN + 1
		s[I_VER] = self.verN
		s[48] = 0
		if has(flags, F_SKIP) then
			if s[46] == 1 then
				local sx, sy, sz = s[42] / 60000, s[43] / 60000, s[44] / 60000
				local cf = CF(s[1] / 1000, s[2] / 1000, s[3] / 1000, s[4] / 1000, s[5] / 1000, s[6] / 1000, s[7] / 1000, s[8] / 1000, s[9] / 1000, s[10] / 1000, s[11] / 1000, s[12] / 1000)
				cf = cf * CFrame.fromEulerAnglesYXZ(sx, sy, sz)
				local x, y, z, r1, r2, r3, r4, r5, r6, r7, r8, r9 = cf:GetComponents()
				s[1], s[2], s[3] = floor(x * 1000 + 0.5), floor(y * 1000 + 0.5), floor(z * 1000 + 0.5)
				s[4], s[5], s[6] = floor(r1 * 1000 + 0.5), floor(r2 * 1000 + 0.5), floor(r3 * 1000 + 0.5)
				s[7], s[8], s[9] = floor(r4 * 1000 + 0.5), floor(r5 * 1000 + 0.5), floor(r6 * 1000 + 0.5)
				s[10], s[11], s[12] = floor(r7 * 1000 + 0.5), floor(r8 * 1000 + 0.5), floor(r9 * 1000 + 0.5)
			end
			touched[id] = true
		else
			local mask = s[I_MASK]
			if has(flags, F_CF) then
				for i = 1, 3 do local d; d, p = rz(str, p); s[i] = s[i] + d end
				mask = addMask(mask, F_CF)
			end
			if has(flags, F_ROT) then
				for i = 4, 12 do local d; d, p = rz(str, p); s[i] = s[i] + d end
				mask = addMask(mask, F_ROT)
			end
			if has(flags, F_TR) then
				local d; d, p = rz(str, p); s[I_TR] = s[I_TR] + d
				mask = addMask(mask, F_TR)
			end
			if has(flags, F_CC) then
				s[I_CC] = has(flags, F_CCV) and 1 or 0
				mask = addMask(mask, F_CC)
			end
			if has(flags, F_COL) then
				local b1, b2, b3 = byte(str, p, p + 2)
				if not b3 then error("client object record is cut off", 0) end
				s[I_COL], s[I_COL + 1], s[I_COL + 2] = b1, b2, b3
				p = p + 3
				mask = addMask(mask, F_COL)
			end
			if has(flags, F_SZ) then
				for i = 0, 2 do local d; d, p = rz(str, p); s[I_SZ + i] = s[I_SZ + i] + d end
				mask = addMask(mask, F_SZ)
			end
			if has(flags, F_MAT) then
				s[I_MAT], p = rv(str, p)
				mask = addMask(mask, F_MAT)
			end
			if has(flags, F_VEL) then
				for i = 36, 41 do local d; d, p = rz(str, p); s[i] = (s[i] or 0) + d end
			end
			if has(flags, F_SPIN) then
				s[42], p = rz(str, p)
				s[43], p = rz(str, p)
				s[44], p = rz(str, p)
				s[46] = 1
			end
			s[I_MASK] = mask
			touched[id] = true
		end
	end
end

-- one v2 / v3 record payload onto a state table (cvs = the frame's clocks in seconds, v3 only)
function Player:applyPayloadV2(str, p, s, flags, tNow, cvs)
	self.verN = self.verN + 1
	s[I_VER] = self.verN
	local mask = s[I_MASK]
	if has(flags, K_KEY) then
		for i = 1, 3 do local d; d, p = rz(str, p); s[i] = s[i] + d end
		mask = addMask(mask, F_CF)
		if has(flags, K_ROT) then
			for i = 4, 12 do local d; d, p = rz(str, p); s[i] = s[i] + d end
			mask = addMask(mask, F_ROT)
		end
		local moving = false
		if has(flags, K_LV) then
			for i = 36, 38 do s[i], p = rz(str, p) end
			moving = true
		else
			s[36], s[37], s[38] = 0, 0, 0
		end
		if has(flags, K_AV) then
			for i = 39, 41 do s[i], p = rz(str, p) end
			moving = true
		else
			s[39], s[40], s[41] = 0, 0, 0
		end
		if cvs then
			local c = (has(flags, K_CK1) and 1 or 0) + (has(flags, K_CK2) and 2 or 0)
			s[47], s[49] = c, 3
			s[45] = (c == 0) and tNow or cvs[c]
		else
			s[47], s[49] = 0, 0
			s[45] = tNow
		end
		s[48] = moving and 1 or 0
	end
	if has(flags, K_TR) then
		local d; d, p = rz(str, p); s[I_TR] = s[I_TR] + d
		mask = addMask(mask, F_TR)
	end
	if has(flags, K_CC) then
		s[I_CC] = has(flags, K_CCV) and 1 or 0
		mask = addMask(mask, F_CC)
	end
	if has(flags, K_COL) then
		local b1, b2, b3 = byte(str, p, p + 2)
		if not b3 then error("client object record is cut off", 0) end
		s[I_COL], s[I_COL + 1], s[I_COL + 2] = b1, b2, b3
		p = p + 3
		mask = addMask(mask, F_COL)
	end
	if has(flags, K_SZ) then
		for i = 0, 2 do local d; d, p = rz(str, p); s[I_SZ + i] = s[I_SZ + i] + d end
		mask = addMask(mask, F_SZ)
	end
	if has(flags, K_MAT) then
		s[I_MAT], p = rv(str, p)
		mask = addMask(mask, F_MAT)
	end
	s[I_MASK] = mask
	return p
end

function Player:applyV2(str, cur, touched, tNow, ft)
	local p, n = 2, #str
	local cvs = nil
	if byte(str, 1) >= 4 then
		p = readClocks(str, self.run, ft)
		cvs = clockValues(self.run, self.cvScratch)
	end
	while p <= n do
		local id, flags
		id, p = rv(str, p)
		flags, p = rv(str, p)
		if has(flags, K_DROP) then
			cur[id] = nil
			touched[id] = nil
			self.dropped[id] = true
		else
			local s = cur[id]
			if not s then s = newState(); cur[id] = s end
			p = self:applyPayloadV2(str, p, s, flags, tNow, cvs)
			touched[id] = true
		end
	end
end

local function isFull(str)
	local b = byte(str, 1)
	return b == 1 or b == 3 or (b >= 4 and b % 8 == 5)
end

function Player:applyString(str, cur, touched, tNow, ft)
	if isFull(str) then
		for id in pairs(cur) do
			self.dropped[id] = true
			cur[id] = nil
		end
	end
	if byte(str, 1) >= 2 then
		self:applyV2(str, cur, touched, tNow or 0, ft)
	else
		self:applyV1(str, cur, touched)
	end
end

-- ------------------------------------------------------------------------------------------------ writing
local function writeProps(part, s, sh)
	local mask = s[I_MASK]
	if has(mask, F_TR) and sh[I_TR] ~= s[I_TR] then
		part.Transparency = s[I_TR] / 1000
		sh[I_TR] = s[I_TR]
	end
	if has(mask, F_CC) and sh[I_CC] ~= s[I_CC] then
		part.CanCollide = s[I_CC] == 1
		sh[I_CC] = s[I_CC]
	end
	if has(mask, F_COL) and (sh[I_COL] ~= s[I_COL] or sh[I_COL + 1] ~= s[I_COL + 1] or sh[I_COL + 2] ~= s[I_COL + 2]) then
		part.Color = Color3.fromRGB(s[I_COL], s[I_COL + 1], s[I_COL + 2])
		sh[I_COL], sh[I_COL + 1], sh[I_COL + 2] = s[I_COL], s[I_COL + 1], s[I_COL + 2]
	end
	if has(mask, F_SZ) and (sh[I_SZ] ~= s[I_SZ] or sh[I_SZ + 1] ~= s[I_SZ + 1] or sh[I_SZ + 2] ~= s[I_SZ + 2]) then
		part.Size = V3(s[I_SZ] / 1000, s[I_SZ + 1] / 1000, s[I_SZ + 2] / 1000)
		sh[I_SZ], sh[I_SZ + 1], sh[I_SZ + 2] = s[I_SZ], s[I_SZ + 1], s[I_SZ + 2]
	end
	if has(mask, F_MAT) and sh[I_MAT] ~= s[I_MAT] then
		local okM, mat = pcall(function() return Enum.Material:FromValue(s[I_MAT]) end)
		if okM and mat then part.Material = mat end
		sh[I_MAT] = s[I_MAT]
	end
end

local function hasPose(s)
	local mask = s[I_MASK]
	return has(mask, F_CF) and has(mask, F_ROT)
end

-- pose at playback time t. With a keyframe coming in the next frame, the small correction towards it is
-- spread over this frame (the motion itself keeps its speed); returns the pose and whether it was blended
function Player:targetPose(id, s, t)
	local cf = self:poseAt(s, t)
	local nx = self.next[id]
	if nx then
		local span = self.nextT - self.curT
		if span > 1e-6 then
			local alpha = (t - self.curT) / span
			if alpha > 1 then alpha = 1 end
			if alpha > 0 then
				local rot = cf.Rotation
				if nx[2] then rot = IDENT:Lerp(nx[2], alpha) * rot end
				return rot + (cf.Position + nx[1] * alpha), true
			end
		end
	end
	return cf, false
end

function Player:writePart(id, s, t, renderPass)
	local R = self.R
	local part = R.parts[id]
	if not part then return end -- (removed parts are unregistered)
	local shown = R.shown
	local sh = shown[id]
	if not sh then sh = {}; shown[id] = sh end
	local rs = R.S[id]
	local orig = R.orig
	if rs.lost then
		rs.lost = false
		R.lost[part] = nil
		if orig[part] ~= nil then part.Anchored = true end
		sh.cf = nil
	end
	local v = s[I_VER]
	if hasPose(s) then
		local cf = sh.cf
		if renderPass and sh.t == t and cf then
			-- the render pass shows the pose Heartbeat computed for the same time
		elseif not (cf and sh.v == v and not sh.b and (sh.t == t or s[48] ~= 1) and not self.next[id]) then
			-- (the same state, not moving, not blended = the same pose as last time)
			cf, sh.b = self:targetPose(id, s, t)
		end
		local fresh = R:ensureAnchored(part, rs)
		-- parts HappaTAS anchored itself only need a write when the pose changed (or when they were free until
		-- now); parts anchored by the game (scripted movers) are written every time so scripts can't win
		if fresh or orig[part] == nil or sh.cf ~= cf then
			part.CFrame = cf
		end
		sh.cf, sh.t, sh.v = cf, t, v
	end
	if (not renderPass and sh.pv ~= v) or rs.pd then
		if rs.pd then
			sh[I_TR], sh[I_CC], sh[I_COL], sh[I_SZ], sh[I_MAT] = nil, nil, nil, nil, nil
		end
		writeProps(part, s, sh)
		rs.pd = false
		sh.pv = v
	end
end

function Player:writeAll(t, renderPass)
	for id, s in pairs(self.cur) do self:writePart(id, s, t, renderPass) end
end

-- ------------------------------------------------------------------------------------------------ seeking
local function cloneCur(cur)
	local c = {}
	for id, s in pairs(cur) do c[id] = copyState(s) end
	return c
end

function Player:ckPut(i)
	if self.ck[i] then return end
	if self.ckN >= MAX_CK then
		local far, farD = nil, -1
		for k in pairs(self.ck) do
			local d = abs(k - i)
			if d > farD then far, farD = k, d end
		end
		if far then self.ck[far], self.ckRun[far] = nil, nil; self.ckN = self.ckN - 1 end
	end
	self.ck[i] = cloneCur(self.cur)
	self.ckRun[i] = { self.run[1], self.run[2], self.run[3] }
	self.ckN = self.ckN + 1
end

function Player:finalize(touched)
	local cur, dyn = self.cur, self.dyn
	for id in pairs(touched) do
		local s = cur[id]
		if s and s[48] == 1 then dyn[id] = true else dyn[id] = nil end
	end
	for id in pairs(dyn) do
		if not cur[id] then dyn[id] = nil end
	end
	for id in pairs(self.dropped) do
		if not cur[id] then self.R:releasePart(id) end
		self.dropped[id] = nil
	end
end

local function frameTime(tl, f)
	if f >= 1 and f <= tl:count() then return tl:get("TotalTime", f, 1) end
	return 0
end
local function recordAt(tl, f)
	if f >= 1 and f <= tl:count() then return tl:getList("v2CO", f) end
	return nil
end

function Player:applyRange(tl, from, to, touched, makeCk)
	for i = from, to do
		local str = recordAt(tl, i)
		if str then
			self:applyString(str, self.cur, touched, tl:get("TotalTime", i, 1), tl:get("FrameTime", i, 1))
			if makeCk and (i % CK == 0 or isFull(str)) then self:ckPut(i) end
		end
	end
end

-- look one frame ahead: pose of every object that gets a new keyframe in frame f + 1
function Player:computeNext(tl, f)
	self.next = {}
	self.nextFor = f
	local n = tl:count()
	self.curT = frameTime(tl, f)
	self.nextT = (f + 1 <= n) and frameTime(tl, f + 1) or self.curT
	-- the next frame's clocks (from this frame's running values)
	local nr = { self.run[1], self.run[2], self.run[3] }
	local nstr = recordAt(tl, f + 1)
	local np = 2
	if nstr and byte(nstr, 1) >= 4 then np = readClocks(nstr, nr, tl:get("FrameTime", f + 1, 1)) end
	clockValues(nr, self.nv)
	local nvReal = { self.nv[1], self.nv[2], self.nv[3] }
	if nstr and byte(nstr, 1) >= 64 then
		-- the next frame starts a new recording with new clocks: up to it, the clocks of this one go on (at the
		-- TAS clock's rate) instead of being blended into the new numbers
		local span = self.nextT - self.curT
		for c = 1, 3 do self.nv[c] = self.cv[c] + span end
	end
	if not nstr or not self.co.settings:on("smoothClientObjects") then return end
	local str = nstr
	if byte(str, 1) < 2 then return end
	local p, len = np, #str
	local cvs = nil
	if byte(str, 1) >= 4 then cvs = nvReal end
	local cur = self.cur
	local s = self.nextScratch -- (reused for every record: only dp / dr are kept)
	-- a full snapshot's records are whole values, not changes: they start from nothing
	local nextFull = isFull(str)
	local ok = pcall(function()
		while p <= len do
			local id, flags
			id, p = rv(str, p)
			flags, p = rv(str, p)
			if not has(flags, K_DROP) then
				local base = cur[id]
				local from = (not nextFull) and base or nil
				for i = 1, 50 do s[i] = from and from[i] or 0 end
				p = self:applyPayloadV2(str, p, s, flags, self.nextT, cvs)
				if base and hasPose(base) and hasPose(s) and has(flags, K_KEY) then
					-- where the current model would be vs. the next keyframe (the keyframe's own pose: it is the
					-- pose at the next frame)
					local want = self:poseAt(s, nil)
					local have = self:poseAt(base, self.nextT)
					local dp = want.Position - have.Position
					if dp.Magnitude < 25 then
						local dr = want.Rotation * have.Rotation:Inverse()
						local _, ang = dr:ToAxisAngle()
						self.next[id] = { dp, (ang == ang and ang > 1e-5) and dr or nil }
					end
				end
			end
		end
	end)
	if not ok then self.next = {} end
end

function Player:advanceTo(tl, f, touched)
	local ver = self.co.dataVersion
	if self.ckData ~= tl or self.ckVer ~= ver then
		self.ck, self.ckN, self.ckRun = {}, 0, {}
		self.ckData, self.ckVer = tl, ver
	end
	local makeCk = self.kind == "show"

	if self.data == tl and self.version == ver and self.frame and f >= self.frame and f - self.frame <= 600 then
		if f > self.frame then self:applyRange(tl, self.frame + 1, f, touched, makeCk) end
		self.frame = f
		self:finalize(touched)
	else
		-- seek: nearest checkpoint, otherwise the last full snapshot
		for id in pairs(self.cur) do self.dropped[id] = true end
		local bestF
		for cfm in pairs(self.ck) do
			if cfm <= f and f - cfm <= 3000 and (not bestF or cfm > bestF) then bestF = cfm end
		end
		local start
		if bestF then
			self.cur = cloneCur(self.ck[bestF])
			local cr = self.ckRun[bestF]
			self.run[1], self.run[2], self.run[3] = cr[1], cr[2], cr[3]
			start = bestF + 1
		else
			self.run[1], self.run[2], self.run[3] = 0, 0, 0
			local base = f
			local limit = math.max(1, f - 3000)
			while base >= limit do
				local str = recordAt(tl, base)
				if str and isFull(str) then break end
				base = base - 1
			end
			self.cur = {}
			start = (base >= limit) and base or (f + 1)
		end
		self:applyRange(tl, start, f, touched, makeCk)
		self.data, self.version, self.frame = tl, ver, f
		for id in pairs(self.cur) do touched[id] = true end
		self:finalize(touched)
	end
	clockValues(self.run, self.cv)
	if self.nextFor ~= f then self:computeNext(tl, f) end
end

-- ------------------------------------------------------------------------------------------------ holding
-- a held part goes back on the pose HappaTAS last gave it, or the one it had when HappaTAS took it
function Player:restoreHeld(part)
	local R = self.R
	part.Anchored = true
	local sh = R.shown[R.ids[part]]
	local ov = R.origVel[part]
	local cf = (sh and sh.cf) or (ov and ov[3])
	if cf then part.CFrame = cf end
end
-- held parts a game script let go since the last pass (the EToH kit's DistanceCulling sets Anchored every
-- 0.2 s). Parts with a recorded pose were already put back by writePart, this handles the rest
function Player:fixLost()
	local R = self.R
	for part in pairs(R.lost) do
		R.lost[part] = nil
		if R.orig[part] ~= nil and part.Parent then
			self:restoreHeld(part)
			local rs = R.S[R.ids[part]]
			if rs then rs.lost = false end
		end
	end
end
function Player:sweepAnchors()
	local R = self.R
	if next(R.lost) then self:fixLost() end
	self.sweep = self.sweep + 1
	if self.sweep % 5 ~= 0 then return end
	for part in pairs(R.orig) do
		if part.Parent and not part.Anchored then self:restoreHeld(part) end
	end
end

function Player:freeze()
	local R = self.R
	for id, part in pairs(R.parts) do
		if part.Parent then R:ensureAnchored(part, R.S[id]) end
	end
	R.frozen = true
end

function Player:hasCOData(tl)
	local n = tl:count()
	local ver = self.co.dataVersion
	if self.hasData ~= tl or self.hasVer ~= ver or (not self.has and self.hasLen ~= n) then
		local any = false
		for i = 1, n do
			if tl:getList("v2CO", i) then any = true break end
		end
		self.hasData, self.hasVer, self.has, self.hasLen = tl, ver, any, n
	end
	return self.has
end

-- ------------------------------------------------------------------------------------------------ entry points
function Player:isPlaying() return self.active end
function Player:isTesting() return self.active and self.kind == "test" end
function Player:isHolding() return self.R.frozen or self.active or next(self.R.orig) ~= nil end

-- every held part goes back (V2 CO.Release)
function Player:release()
	self:setActive(false)
	self.R:releaseAll()
	self.next, self.nextFor = {}, nil
end

function Player:playbackBegin(tl, startFrame)
	if not self.R:isReady() then return false end
	self:setActive(false)
	if not self:hasCOData(tl) then return false end
	self.kind = "test"
	self:setActive(true)
	self.sweep = 0
	self.data = nil
	self.nextFor = nil
	self.t = frameTime(tl, startFrame)
	self:advanceTo(tl, startFrame, table.clear(self.touched) or self.touched)
	self:writeAll(self.t, false)
	return true
end

-- t = playback time in seconds (the same clock the character uses); nil = the frame's own time
function Player:playbackTo(tl, frame, t)
	if not self.active then return end
	self.t = t or frameTime(tl, frame)
	table.clear(self.touched)
	self:advanceTo(tl, frame, self.touched)
	self:writeAll(self.t, false)
	self:sweepAnchors()
end

-- every Heartbeat while paused in Create mode
function Player:tick()
	if not (self.active and self.kind == "show") then return end
	self:sweepAnchors()
end

-- last thing in the render step: same time as the character, re-asserted after game scripts
function Player:renderStep()
	if not self.active then return end
	self:writeAll(self.t, true)
	if next(self.R.lost) then self:fixLost() end
end

function Player:endPlayback()
	self:setActive(false)
	self:release()
end

function Player:showFrame(tl, frame)
	if not self.R:isReady() then return end
	if not self.R.frozen then self:freeze() end
	if not self:hasCOData(tl) then return end
	self.kind = "show"
	self:setActive(true)
	self.t = frameTime(tl, frame)
	table.clear(self.touched)
	self:advanceTo(tl, frame, self.touched)
	self.next, self.nextFor = {}, nil -- no blending while paused: show exactly the frame
	self:writeAll(self.t, false)
	self:sweepAnchors()
end

-- unpausing at another time: put every recorded part back WITH its recorded velocity
function Player:restoreUnpause(tl, frame)
	local R = self.R
	if not R:isReady() then return end
	if self:hasCOData(tl) and frame and frame >= 1 and frame <= tl:count() then
		self.kind = "show"
		table.clear(self.touched)
		self:advanceTo(tl, frame, self.touched)
		local t = frameTime(tl, frame)
		-- a frame recorded in slow motion (speed hack, SK = its factor) has slowed velocities: they go back in
		-- normal units, time control slows the world again when the slow motion goes on
		local skCol = tl.cols.v2SK
		local sk = tonumber(skCol and tl:getList("v2SK", frame)) or 1
		if sk <= 0 then sk = 1 end
		local orig, origVel = R.orig, R.origVel
		for id, s in pairs(self.cur) do
			local part = R.parts[id]
			if part and part.Parent and hasPose(s) then
				part.CFrame = self:poseAt(s, t)
				local sh = R.shown[id]
				if not sh then sh = {}; R.shown[id] = sh end
				writeProps(part, s, sh)
				if orig[part] ~= nil then
					part.Anchored = orig[part]
					orig[part], origVel[part] = nil, nil
				end
				if not part.Anchored then
					local L = V3(s[36] / 1000, s[37] / 1000, s[38] / 1000)
					local W = V3(s[39] / 1000, s[40] / 1000, s[41] / 1000)
					local w2 = W:Dot(W)
					if s[49] == 3 and w2 > 1e-10 then
						-- v3 keeps the velocity at the part's position; the assembly's is the one at its centre of
						-- mass: the part's motion along the screw axis + w x (centre of mass - axis point)
						local okC, com = pcall(function() return part.AssemblyCenterOfMass end)
						if okC and typeof(com) == "Vector3" then
							local ctr = V3(s[1] / 1000, s[2] / 1000, s[3] / 1000) - L:Cross(W) / w2
							L = W * (L:Dot(W) / w2) + W:Cross(com - ctr)
						end
					end
					part.AssemblyLinearVelocity = L / sk
					part.AssemblyAngularVelocity = W / sk
				end
			end
		end
	end
	self:release()
end

return Player
