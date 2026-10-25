-- ================================================================================================
--  CO FORMAT  (HappaTAS 3, client objects): V2.38.17's client object record layout and the maths the
--  recorder and the player share (p13_clientobjects.lua 15-30, 58-69, 589-672, 1112-1166; byte helpers
--  from p07_codec.lua 53-88).
--  record layout (v3):  frame byte = 4 (delta) / 5 (full snapshot) + 8 / 16 / 32 when the frame carries
--      clock 1 / 2 / 3, + 64 on the full snapshot that starts a new recording, then those clocks (zigzag, the
--      change since the last frame that carried them), then records: varint id, varint flags, payload
--  flags: 1 key (pos), 2 rotation, 4 linear velocity, 8 angular velocity, 16 transparency,
--         32 can-collide (64 = its value), 128 colour, 256 size, 512 material, 1024 dropped,
--         2048 + 4096 the key's clock (2048 = 1, 4096 = 2, both = 3, none = 0)
--  v2 data (frame byte 2 / 3) and v1 data (0 / 1) use the older flag sets (F_*) and play as recorded.
-- ================================================================================================
local Format = {}

local floor, sqrt = math.floor, math.sqrt
local byte, char = string.byte, string.char
local V3, CF = Vector3.new, CFrame.new
local ZV = Vector3.zero

-- v1 flags
Format.F_CF, Format.F_TR, Format.F_CC, Format.F_CCV, Format.F_COL, Format.F_SZ, Format.F_MAT, Format.F_ROT = 1, 2, 4, 8, 16, 32, 64, 128
Format.F_VEL, Format.F_SPIN, Format.F_SKIP = 256, 512, 1024
-- v2 / v3 flags
Format.K_KEY, Format.K_ROT, Format.K_LV, Format.K_AV = 1, 2, 4, 8
Format.K_TR, Format.K_CC, Format.K_CCV, Format.K_COL, Format.K_SZ, Format.K_MAT, Format.K_DROP = 16, 32, 64, 128, 256, 512, 1024
Format.K_CK1, Format.K_CK2 = 2048, 4096
-- playback state slots (see the player)
Format.I_TR, Format.I_CC, Format.I_COL, Format.I_SZ, Format.I_MAT, Format.I_MASK, Format.I_VER = 13, 14, 15, 18, 21, 23, 50
Format.SIM_HZ, Format.WALL_HZ = 240, 50000
Format.MAX_EXTRAP = 2.0

local has = bit32.btest
Format.has = has

-- ------------------------------------------------------------------------------------------------ bytes
-- (records are built as tables of byte values, like V2's codec buffers)
function Format.putVar(buf, n)
	n = floor(n or 0)
	if n < 0 then n = 0 end
	local i = #buf
	while n >= 128 do
		local m = n % 128
		i = i + 1
		buf[i] = m + 128
		n = (n - m) / 128
	end
	buf[i + 1] = n
end
local putVar = Format.putVar
function Format.putZig(buf, v)
	v = floor(v or 0)
	if v >= 0 then putVar(buf, v * 2) else putVar(buf, -v * 2 - 1) end
end
function Format.bufToString(buf)
	local parts = {}
	local n = #buf
	local i = 1
	while i <= n do
		local j = i + 3999
		if j > n then j = n end
		parts[#parts + 1] = char(table.unpack(buf, i, j))
		i = j + 1
	end
	return table.concat(parts)
end

function Format.rv(str, p)
	local result, mul = 0, 1
	while true do
		local b = byte(str, p)
		if not b then error("client object record is cut off", 0) end
		p = p + 1
		if b < 128 then return result + b * mul, p end
		result = result + (b - 128) * mul
		mul = mul * 128
		if mul > 2 ^ 49 then error("bad client object number", 0) end
	end
end
local rv = Format.rv
function Format.rz(str, p)
	local z
	z, p = rv(str, p)
	if z % 2 == 0 then return floor(z / 2), p end
	return -floor((z + 1) / 2), p
end
local rz = Format.rz
function Format.skipVars(str, p, count)
	for _ = 1, count do
		local b = byte(str, p)
		while b and b >= 128 do p = p + 1; b = byte(str, p) end
		if not b then error("client object record is cut off", 0) end
		p = p + 1
	end
	return p
end
local skipVars = Format.skipVars

-- the clocks a v3 frame carries, onto rn (the running values, updated in place); ft = the frame's FrameTime.
-- Returns where the records start
function Format.readClocks(str, rn, ft)
	local b = byte(str, 1)
	local full = b % 8 == 5
	if full then rn[1], rn[2], rn[3] = 0, 0, 0 end
	local fl, p = floor(b / 8), 2
	for i = 1, 3 do
		if fl % 2 == 1 then
			local d
			d, p = rz(str, p)
			if i == 2 and not full then d = d + floor((ft or 0) * Format.WALL_HZ + 0.5) end
			rn[i] = rn[i] + d
		end
		fl = floor(fl / 2)
	end
	return p
end
function Format.bodyStart(str)
	if byte(str, 1) >= 4 then return Format.readClocks(str, { 0, 0, 0 }, 0) end
	return 2
end
function Format.clockValues(rn, out)
	out[1], out[2], out[3] = rn[1] / Format.SIM_HZ, rn[2] / Format.WALL_HZ, rn[3] / Format.SIM_HZ
	return out
end

function Format.skipPayload(isV2, flags, str, p)
	if isV2 then
		if has(flags, Format.K_DROP) then return p end
		if has(flags, Format.K_KEY) then
			p = skipVars(str, p, 3)
			if has(flags, Format.K_ROT) then p = skipVars(str, p, 9) end
			if has(flags, Format.K_LV) then p = skipVars(str, p, 3) end
			if has(flags, Format.K_AV) then p = skipVars(str, p, 3) end
		end
		if has(flags, Format.K_TR) then p = skipVars(str, p, 1) end
		if has(flags, Format.K_COL) then p = p + 3 end
		if has(flags, Format.K_SZ) then p = skipVars(str, p, 3) end
		if has(flags, Format.K_MAT) then p = skipVars(str, p, 1) end
	else
		if has(flags, Format.F_CF) then p = skipVars(str, p, 3) end
		if has(flags, Format.F_ROT) then p = skipVars(str, p, 9) end
		if has(flags, Format.F_TR) then p = skipVars(str, p, 1) end
		if has(flags, Format.F_COL) then p = p + 3 end
		if has(flags, Format.F_SZ) then p = skipVars(str, p, 3) end
		if has(flags, Format.F_MAT) then p = skipVars(str, p, 1) end
		if has(flags, Format.F_VEL) then p = skipVars(str, p, 6) end
		if has(flags, Format.F_SPIN) then p = skipVars(str, p, 3) end
	end
	return p
end

-- the ids a record mentions (V2 CO.IdsOf)
function Format.idsOf(str, set)
	set = set or {}
	local isV2 = byte(str, 1) >= 2
	local p, n = Format.bodyStart(str), #str
	while p <= n do
		local id, flags
		id, p = rv(str, p)
		set[id] = true
		flags, p = rv(str, p)
		p = Format.skipPayload(isV2, flags, str, p)
	end
	return set
end

-- a v2 / v3 record read out (tests and tools): { byte, items = { { id, flags, key = {x, y, z}? } } };
-- key values are as stored (a change from the part's last key unless it starts from nothing)
function Format.parse(str)
	local b = byte(str, 1)
	local out = { byte = b, items = {} }
	if b < 2 then return out end
	local p, n = Format.bodyStart(str), #str
	while p <= n do
		local it = {}
		it.id, p = rv(str, p)
		it.flags, p = rv(str, p)
		local f = it.flags
		if not has(f, Format.K_DROP) and has(f, Format.K_KEY) then
			local x, y, z
			x, p = rz(str, p); y, p = rz(str, p); z, p = rz(str, p)
			it.key = { x = x / 1000, y = y / 1000, z = z / 1000 }
			if has(f, Format.K_ROT) then p = skipVars(str, p, 9) end
			if has(f, Format.K_LV) then p = skipVars(str, p, 3) end
			if has(f, Format.K_AV) then p = skipVars(str, p, 3) end
			if has(f, Format.K_TR) then p = skipVars(str, p, 1) end
			if has(f, Format.K_COL) then p = p + 3 end
			if has(f, Format.K_SZ) then p = skipVars(str, p, 3) end
			if has(f, Format.K_MAT) then p = skipVars(str, p, 1) end
		else
			p = Format.skipPayload(true, f, str, p)
		end
		out.items[#out.items + 1] = it
	end
	return out
end

-- ------------------------------------------------------------------------------------------------ pose model
-- v2 records (older files): the keyframe pose moved on by its velocity for dt seconds, in a straight line
-- (one CFrame when it doesn't turn)
function Format.buildPose(x, y, z, r1, r2, r3, r4, r5, r6, r7, r8, r9, lx, ly, lz, wx, wy, wz, dt)
	if dt and dt > 0 then
		if dt > Format.MAX_EXTRAP then dt = Format.MAX_EXTRAP end
		local px, py, pz = x + lx * dt, y + ly * dt, z + lz * dt
		local mag = sqrt(wx * wx + wy * wy + wz * wz)
		if mag > 1e-5 then
			local rot = CF(0, 0, 0, r1, r2, r3, r4, r5, r6, r7, r8, r9)
			return CFrame.fromAxisAngle(V3(wx / mag, wy / mag, wz / mag), mag * dt) * rot + V3(px, py, pz)
		end
		return CF(px, py, pz, r1, r2, r3, r4, r5, r6, r7, r8, r9)
	end
	return CF(x, y, z, r1, r2, r3, r4, r5, r6, r7, r8, r9)
end

-- v3 records: the keyframe pose moved on by a constant twist (a screw motion). l = the velocity at the
-- part's position, w = the angular velocity (world space). The part turns by w around the axis through
-- the point where its velocity is only along w, so a part going round a spinner's centre stays on its
-- circle, a part spinning in place stays in place and a slider (w = 0) moves in a straight line
function Format.buildPose3(x, y, z, r1, r2, r3, r4, r5, r6, r7, r8, r9, lx, ly, lz, wx, wy, wz, dt)
	if dt and dt > 0 then
		if dt > Format.MAX_EXTRAP then dt = Format.MAX_EXTRAP end
		local w2 = wx * wx + wy * wy + wz * wz
		if w2 > 1e-10 then
			local mag = sqrt(w2)
			local turn = CFrame.fromAxisAngle(V3(wx / mag, wy / mag, wz / mag), mag * dt)
			-- the part's offset from the screw axis: (l x w) / |w|^2; its speed along the axis: (l . w) / |w|^2
			local ox, oy, oz = (ly * wz - lz * wy) / w2, (lz * wx - lx * wz) / w2, (lx * wy - ly * wx) / w2
			local along = (lx * wx + ly * wy + lz * wz) / w2 * dt
			local q = turn * V3(ox, oy, oz)
			return turn * CF(0, 0, 0, r1, r2, r3, r4, r5, r6, r7, r8, r9)
				+ V3(x - ox + q.X + wx * along, y - oy + q.Y + wy * along, z - oz + q.Z + wz * along)
		end
		return CF(x + lx * dt, y + ly * dt, z + lz * dt, r1, r2, r3, r4, r5, r6, r7, r8, r9)
	end
	return CF(x, y, z, r1, r2, r3, r4, r5, r6, r7, r8, r9)
end

-- the constant twist that turns pose c0 into pose c1 in dt seconds: the velocity at c1's position and the
-- angular velocity (screw motion: turning around an axis while moving along it)
function Format.twistFrom(c0, c1, dt)
	if not dt or dt <= 1e-5 then return ZV, ZV end
	local d = c1 * c0:Inverse()
	local tr = d.Position
	local axis, ang = d:ToAxisAngle()
	if ang == ang and ang > 1e-6 and axis.X == axis.X and axis.Magnitude > 0.5 then
		local n = axis.Unit
		local w = n * (ang / dt)
		local tpar = n * tr:Dot(n)
		local tperp = tr - tpar
		-- a point on the screw axis: (t + cot(ang / 2) n x t) / 2 (t = the move across the axis)
		local ctr = (tperp + n:Cross(tperp) / math.tan(ang * 0.5)) * 0.5
		return tpar / dt + w:Cross(c1.Position - ctr), w
	end
	return tr / dt, ZV
end

return Format
