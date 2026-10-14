-- ================================================================================================
-- Headless Roblox mock: datatypes, Enum, typeof
-- (test harness only, runs under the luau CLI)
-- ================================================================================================
M = M or {}
M.realClock = os.clock
local realTypeof = typeof
local rawtype = type

function typeof(v)
	local t = rawtype(v)
	if t == "table" then
		local mt = getmetatable(v)
		if rawtype(mt) == "table" and rawget(mt, "__type") then return rawget(mt, "__type") end
	end
	if t == "userdata" and realTypeof then return realTypeof(v) end
	return t
end
M.typeof = typeof

local function round(n) return math.floor(n + 0.5) end

-- ------------------------------------------------------------------------------------------------ Vector2
do
	local V2 = {}
	local mt = { __type = "Vector2" }
	local function new(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, mt) end
	mt.__index = function(t, k)
		if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y) end
		if k == "Unit" then local m = math.sqrt(t.X * t.X + t.Y * t.Y); if m == 0 then return new(0, 0) end return new(t.X / m, t.Y / m) end
		if k == "x" then return t.X end
		if k == "y" then return t.Y end
		return V2[k]
	end
	mt.__add = function(a, b) return new(a.X + b.X, a.Y + b.Y) end
	mt.__sub = function(a, b) return new(a.X - b.X, a.Y - b.Y) end
	mt.__mul = function(a, b)
		if rawtype(a) == "number" then return new(a * b.X, a * b.Y) end
		if rawtype(b) == "number" then return new(a.X * b, a.Y * b) end
		return new(a.X * b.X, a.Y * b.Y)
	end
	mt.__div = function(a, b)
		if rawtype(b) == "number" then return new(a.X / b, a.Y / b) end
		return new(a.X / b.X, a.Y / b.Y)
	end
	mt.__unm = function(a) return new(-a.X, -a.Y) end
	mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
	mt.__tostring = function(a) return a.X .. ", " .. a.Y end
	function V2.Dot(a, b) return a.X * b.X + a.Y * b.Y end
	function V2.Lerp(a, b, t) return new(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t) end
	function V2.Abs(a) return new(math.abs(a.X), math.abs(a.Y)) end
	function V2.Min(a, b) return new(math.min(a.X, b.X), math.min(a.Y, b.Y)) end
	function V2.Max(a, b) return new(math.max(a.X, b.X), math.max(a.Y, b.Y)) end
	function V2.FuzzyEq(a, b, eps) eps = eps or 1e-5; return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps end
	Vector2 = { new = new, zero = new(0, 0), one = new(1, 1), xAxis = new(1, 0), yAxis = new(0, 1) }
end

-- ------------------------------------------------------------------------------------------------ Vector3
do
	local V3 = {}
	local mt = { __type = "Vector3" }
	local function new(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, mt) end
	mt.__index = function(t, k)
		if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
		if k == "Unit" then
			local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z)
			if m == 0 then return new(0 / 0, 0 / 0, 0 / 0) end
			return new(t.X / m, t.Y / m, t.Z / m)
		end
		if k == "x" then return t.X end
		if k == "y" then return t.Y end
		if k == "z" then return t.Z end
		return V3[k]
	end
	mt.__add = function(a, b) return new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
	mt.__sub = function(a, b) return new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
	mt.__mul = function(a, b)
		if rawtype(a) == "number" then return new(a * b.X, a * b.Y, a * b.Z) end
		if rawtype(b) == "number" then return new(a.X * b, a.Y * b, a.Z * b) end
		return new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
	end
	mt.__div = function(a, b)
		if rawtype(b) == "number" then return new(a.X / b, a.Y / b, a.Z / b) end
		return new(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
	end
	mt.__unm = function(a) return new(-a.X, -a.Y, -a.Z) end
	mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
	mt.__tostring = function(a) return a.X .. ", " .. a.Y .. ", " .. a.Z end
	function V3.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
	function V3.Cross(a, b) return new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
	function V3.Lerp(a, b, t) return new(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end
	function V3.Abs(a) return new(math.abs(a.X), math.abs(a.Y), math.abs(a.Z)) end
	function V3.Floor(a) return new(math.floor(a.X), math.floor(a.Y), math.floor(a.Z)) end
	function V3.Ceil(a) return new(math.ceil(a.X), math.ceil(a.Y), math.ceil(a.Z)) end
	function V3.Min(a, b) return new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z)) end
	function V3.Max(a, b) return new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z)) end
	function V3.FuzzyEq(a, b, eps) eps = eps or 1e-5; return (a - b).Magnitude <= eps end
	function V3.Angle(a, b)
		local d = V3.Dot(a.Unit, b.Unit)
		return math.acos(math.clamp(d, -1, 1))
	end
	Vector3 = { new = new, zero = new(0, 0, 0), one = new(1, 1, 1), xAxis = new(1, 0, 0), yAxis = new(0, 1, 0), zAxis = new(0, 0, 1) }
	function Vector3.FromNormalId() return new(0, 1, 0) end
end

-- ------------------------------------------------------------------------------------------------ CFrame
do
	local CF = {}
	local mt = { __type = "CFrame" }
	-- rotation stored row-major: r00 r01 r02 / r10 r11 r12 / r20 r21 r22 ; columns are Right, Up, Back
	local function raw(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
		return setmetatable({ x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 }, mt)
	end
	local function new(a, b, c, ...)
		if a == nil then return raw(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1) end
		if typeof(a) == "Vector3" then
			if b == nil then return raw(a.X, a.Y, a.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1) end
			-- new(pos, lookAt)
			return CFrame.lookAt(a, b)
		end
		local n = select("#", ...)
		if n == 9 then
			local r = { ... }
			return raw(a, b, c, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
		elseif n == 4 then
			local qx, qy, qz, qw = ...
			local m = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
			qx, qy, qz, qw = qx / m, qy / m, qz / m, qw / m
			return raw(a, b, c,
				1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw),
				2 * (qx * qy + qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz - qx * qw),
				2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (qx * qx + qy * qy))
		end
		return raw(a or 0, b or 0, c or 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	local function mulRot(A, B)
		local a00, a01, a02, a10, a11, a12, a20, a21, a22 = A[4], A[5], A[6], A[7], A[8], A[9], A[10], A[11], A[12]
		local b00, b01, b02, b10, b11, b12, b20, b21, b22 = B[4], B[5], B[6], B[7], B[8], B[9], B[10], B[11], B[12]
		return a00 * b00 + a01 * b10 + a02 * b20, a00 * b01 + a01 * b11 + a02 * b21, a00 * b02 + a01 * b12 + a02 * b22,
			a10 * b00 + a11 * b10 + a12 * b20, a10 * b01 + a11 * b11 + a12 * b21, a10 * b02 + a11 * b12 + a12 * b22,
			a20 * b00 + a21 * b10 + a22 * b20, a20 * b01 + a21 * b11 + a22 * b21, a20 * b02 + a21 * b12 + a22 * b22
	end
	local function xform(A, x, y, z)
		return A[1] + A[4] * x + A[5] * y + A[6] * z, A[2] + A[7] * x + A[8] * y + A[9] * z, A[3] + A[10] * x + A[11] * y + A[12] * z
	end
	local function rot(A, x, y, z)
		return A[4] * x + A[5] * y + A[6] * z, A[7] * x + A[8] * y + A[9] * z, A[10] * x + A[11] * y + A[12] * z
	end
	local function inverse(A)
		-- orthonormal inverse
		local r00, r01, r02, r10, r11, r12, r20, r21, r22 = A[4], A[7], A[10], A[5], A[8], A[11], A[6], A[9], A[12]
		local x, y, z = -A[1], -A[2], -A[3]
		return raw(r00 * x + r01 * y + r02 * z, r10 * x + r11 * y + r12 * z, r20 * x + r21 * y + r22 * z,
			r00, r01, r02, r10, r11, r12, r20, r21, r22)
	end
	mt.__mul = function(a, b)
		if typeof(b) == "Vector3" then
			local x, y, z = xform(a, b.X, b.Y, b.Z)
			return Vector3.new(x, y, z)
		end
		local x, y, z = xform(a, b[1], b[2], b[3])
		return raw(x, y, z, mulRot(a, b))
	end
	mt.__add = function(a, v) return raw(a[1] + v.X, a[2] + v.Y, a[3] + v.Z, a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12]) end
	mt.__sub = function(a, v) return raw(a[1] - v.X, a[2] - v.Y, a[3] - v.Z, a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12]) end
	mt.__eq = function(a, b)
		for i = 1, 12 do if a[i] ~= b[i] then return false end end
		return true
	end
	mt.__tostring = function(a) return table.concat({ a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12] }, ", ") end
	mt.__index = function(t, k)
		if k == "Position" or k == "p" then return Vector3.new(t[1], t[2], t[3]) end
		if k == "X" or k == "x" then return t[1] end
		if k == "Y" or k == "y" then return t[2] end
		if k == "Z" or k == "z" then return t[3] end
		if k == "LookVector" or k == "lookVector" then return Vector3.new(-t[6], -t[9], -t[12]) end
		if k == "RightVector" or k == "XVector" then return Vector3.new(t[4], t[7], t[10]) end
		if k == "UpVector" or k == "YVector" then return Vector3.new(t[5], t[8], t[11]) end
		if k == "ZVector" then return Vector3.new(t[6], t[9], t[12]) end
		if k == "Rotation" then return raw(0, 0, 0, t[4], t[5], t[6], t[7], t[8], t[9], t[10], t[11], t[12]) end
		return CF[k]
	end
	function CF.Inverse(a) return inverse(a) end
	function CF.GetComponents(a) return a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12] end
	CF.components = CF.GetComponents
	function CF.ToWorldSpace(a, b) return a * b end
	function CF.ToObjectSpace(a, b) return inverse(a) * b end
	function CF.PointToWorldSpace(a, v) return a * v end
	function CF.PointToObjectSpace(a, v) return inverse(a) * v end
	function CF.VectorToWorldSpace(a, v) local x, y, z = rot(a, v.X, v.Y, v.Z); return Vector3.new(x, y, z) end
	function CF.VectorToObjectSpace(a, v) local x, y, z = rot(inverse(a), v.X, v.Y, v.Z); return Vector3.new(x, y, z) end
	function CF.ToEulerAnglesXYZ(a)
		local r02 = a[6]
		local y = math.asin(math.clamp(r02, -1, 1))
		local x, z
		if math.abs(r02) < 0.9999999 then
			x = math.atan2(-a[9], a[12])
			z = math.atan2(-a[5], a[4])
		else
			x = math.atan2(a[11], a[8])
			z = 0
		end
		return x, y, z
	end
	CF.toEulerAnglesXYZ = CF.ToEulerAnglesXYZ
	function CF.ToEulerAnglesYXZ(a)
		-- R = Ry * Rx * Rz
		local r12 = a[9]
		local x = math.asin(math.clamp(-r12, -1, 1))
		local y, z
		if math.abs(r12) < 0.9999999 then
			y = math.atan2(a[6], a[12])
			z = math.atan2(a[7], a[8])
		else
			y = math.atan2(-a[10], a[4])
			z = 0
		end
		return x, y, z
	end
	CF.toEulerAnglesYXZ = CF.ToEulerAnglesYXZ
	CF.ToOrientation = CF.ToEulerAnglesYXZ
	function CF.ToAxisAngle(a)
		local tr = a[4] + a[8] + a[12]
		local ang = math.acos(math.clamp((tr - 1) / 2, -1, 1))
		local ax = Vector3.new(a[11] - a[9], a[6] - a[10], a[7] - a[5])
		if ax.Magnitude < 1e-9 then return Vector3.new(0, 1, 0), 0 end
		return ax.Unit, ang
	end
	local function toQuat(a)
		local m00, m01, m02, m10, m11, m12, m20, m21, m22 = a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12]
		local tr = m00 + m11 + m22
		local qw, qx, qy, qz
		if tr > 0 then
			local s = math.sqrt(tr + 1) * 2
			qw = 0.25 * s; qx = (m21 - m12) / s; qy = (m02 - m20) / s; qz = (m10 - m01) / s
		elseif m00 > m11 and m00 > m22 then
			local s = math.sqrt(1 + m00 - m11 - m22) * 2
			qw = (m21 - m12) / s; qx = 0.25 * s; qy = (m01 + m10) / s; qz = (m02 + m20) / s
		elseif m11 > m22 then
			local s = math.sqrt(1 + m11 - m00 - m22) * 2
			qw = (m02 - m20) / s; qx = (m01 + m10) / s; qy = 0.25 * s; qz = (m12 + m21) / s
		else
			local s = math.sqrt(1 + m22 - m00 - m11) * 2
			qw = (m10 - m01) / s; qx = (m02 + m20) / s; qy = (m12 + m21) / s; qz = 0.25 * s
		end
		return qx, qy, qz, qw
	end
	function CF.Lerp(a, b, t)
		local ax, ay, az, aw = toQuat(a)
		local bx, by, bz, bw = toQuat(b)
		local d = ax * bx + ay * by + az * bz + aw * bw
		if d < 0 then bx, by, bz, bw = -bx, -by, -bz, -bw; d = -d end
		local qx, qy, qz, qw
		if d > 0.9995 then
			qx, qy, qz, qw = ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t, aw + (bw - aw) * t
		else
			local th = math.acos(d)
			local s = math.sin(th)
			local wa, wb = math.sin((1 - t) * th) / s, math.sin(t * th) / s
			qx, qy, qz, qw = ax * wa + bx * wb, ay * wa + by * wb, az * wa + bz * wb, aw * wa + bw * wb
		end
		return new(a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, qx, qy, qz, qw)
	end
	function CF.Orthonormalize(a) return a end
	function CF.FuzzyEq(a, b, eps)
		eps = eps or 1e-5
		for i = 1, 12 do if math.abs(a[i] - b[i]) > eps then return false end end
		return true
	end
	local function angles(rx, ry, rz)
		-- Roblox CFrame.Angles = Rx * Ry * Rz
		local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
		local X = raw(0, 0, 0, 1, 0, 0, 0, cx, -sx, 0, sx, cx)
		local Y = raw(0, 0, 0, cy, 0, sy, 0, 1, 0, -sy, 0, cy)
		local Z = raw(0, 0, 0, cz, -sz, 0, sz, cz, 0, 0, 0, 1)
		return X, Y, Z
	end
	CFrame = { new = new, identity = raw(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1) }
	function CFrame.Angles(rx, ry, rz) local X, Y, Z = angles(rx, ry, rz); return X * Y * Z end
	CFrame.fromEulerAnglesXYZ = CFrame.Angles
	function CFrame.fromEulerAnglesYXZ(rx, ry, rz) local X, Y, Z = angles(rx, ry, rz); return Y * X * Z end
	CFrame.fromOrientation = CFrame.fromEulerAnglesYXZ
	function CFrame.fromEulerAngles(rx, ry, rz) return CFrame.Angles(rx, ry, rz) end
	function CFrame.fromAxisAngle(axis, ang)
		local u = axis.Unit
		local s = math.sin(ang / 2)
		return new(0, 0, 0, u.X * s, u.Y * s, u.Z * s, math.cos(ang / 2))
	end
	function CFrame.fromMatrix(pos, vx, vy, vz)
		vz = vz or vx:Cross(vy)
		return raw(pos.X, pos.Y, pos.Z, vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z)
	end
	function CFrame.lookAt(at, target, up)
		up = up or Vector3.new(0, 1, 0)
		local look = (target - at)
		if look.Magnitude < 1e-9 then return raw(at.X, at.Y, at.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1) end
		look = look.Unit
		local zb = -look
		local right = up:Cross(zb)
		if right.Magnitude < 1e-9 then right = Vector3.new(1, 0, 0) else right = right.Unit end
		local up2 = zb:Cross(right)
		return CFrame.fromMatrix(at, right, up2, zb)
	end
	CFrame.lookAlong = function(at, dir, up) return CFrame.lookAt(at, at + dir, up) end
end

-- ------------------------------------------------------------------------------------------------ Color3
do
	local mt = { __type = "Color3" }
	local C = {}
	mt.__index = function(t, k)
		if k == "r" then return t.R end
		if k == "g" then return t.G end
		if k == "b" then return t.B end
		return C[k]
	end
	mt.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
	mt.__tostring = function(a) return a.R .. ", " .. a.G .. ", " .. a.B end
	local function new(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, mt) end
	function C.Lerp(a, b, t) return new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end
	function C.ToHex(a) return string.format("%02X%02X%02X", round(a.R * 255), round(a.G * 255), round(a.B * 255)) end
	function C.ToHSV(a)
		local r, g, b = a.R, a.G, a.B
		local mx, mn = math.max(r, g, b), math.min(r, g, b)
		local h, s, v = 0, 0, mx
		local d = mx - mn
		if mx > 0 then s = d / mx end
		if d > 0 then
			if mx == r then h = (g - b) / d % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
			h = h / 6
		end
		return h, s, v
	end
	Color3 = { new = new }
	function Color3.fromRGB(r, g, b) return new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end
	function Color3.fromHSV(h, s, v)
		local i = math.floor(h * 6)
		local f = h * 6 - i
		local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
		i = i % 6
		if i == 0 then return new(v, t, p) elseif i == 1 then return new(q, v, p) elseif i == 2 then return new(p, v, t)
		elseif i == 3 then return new(p, q, v) elseif i == 4 then return new(t, p, v) else return new(v, p, q) end
	end
	function Color3.fromHex(h)
		h = h:gsub("#", "")
		return Color3.fromRGB(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16))
	end
	Color3.toHSV = function(c) return c:ToHSV() end
	M.rgb255 = function(c) return round(c.R * 255), round(c.G * 255), round(c.B * 255) end
end

-- ------------------------------------------------------------------------------------------------ UDim / UDim2
do
	local umt = { __type = "UDim" }
	local function udim(s, o) return setmetatable({ Scale = s or 0, Offset = o or 0 }, umt) end
	umt.__eq = function(a, b) return a.Scale == b.Scale and a.Offset == b.Offset end
	umt.__add = function(a, b) return udim(a.Scale + b.Scale, a.Offset + b.Offset) end
	umt.__sub = function(a, b) return udim(a.Scale - b.Scale, a.Offset - b.Offset) end
	umt.__tostring = function(a) return a.Scale .. ", " .. a.Offset end
	UDim = { new = udim }

	local mt = { __type = "UDim2" }
	local U2 = {}
	-- Roblox stores UDim offsets as int32: fractional offsets are truncated
	local function trunc(o)
		o = o or 0
		if o >= 0 then return math.floor(o) end
		return -math.floor(-o)
	end
	local function new(xs, xo, ys, yo)
		return setmetatable({ X = udim(xs or 0, trunc(xo)), Y = udim(ys or 0, trunc(yo)) }, mt)
	end
	mt.__index = function(t, k)
		if k == "Width" then return t.X end
		if k == "Height" then return t.Y end
		return U2[k]
	end
	mt.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
	mt.__add = function(a, b) return new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset) end
	mt.__sub = function(a, b) return new(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset) end
	mt.__tostring = function(a) return "{" .. tostring(a.X) .. "}, {" .. tostring(a.Y) .. "}" end
	function U2.Lerp(a, b, t)
		return new(a.X.Scale + (b.X.Scale - a.X.Scale) * t, a.X.Offset + (b.X.Offset - a.X.Offset) * t,
			a.Y.Scale + (b.Y.Scale - a.Y.Scale) * t, a.Y.Offset + (b.Y.Offset - a.Y.Offset) * t)
	end
	UDim2 = { new = function(a, b, c, d)
		if typeof(a) == "UDim" then return new(a.Scale, a.Offset, b.Scale, b.Offset) end
		return new(a, b, c, d)
	end }
	function UDim2.fromOffset(x, y) return new(0, x, 0, y) end
	function UDim2.fromScale(x, y) return new(x, 0, y, 0) end
end

-- ------------------------------------------------------------------------------------------------ sequences, Rect, misc
do
	local kmt = { __type = "ColorSequenceKeypoint" }
	ColorSequenceKeypoint = { new = function(t, c) return setmetatable({ Time = t, Value = c }, kmt) end }
	local smt = { __type = "ColorSequence" }
	smt.__eq = function(a, b)
		if #a.Keypoints ~= #b.Keypoints then return false end
		for i, k in ipairs(a.Keypoints) do
			local o = b.Keypoints[i]
			if k.Time ~= o.Time or k.Value ~= o.Value then return false end
		end
		return true
	end
	ColorSequence = { new = function(a, b)
		if typeof(a) == "Color3" then
			b = b or a
			return setmetatable({ Keypoints = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b) } }, smt)
		end
		return setmetatable({ Keypoints = a }, smt)
	end }
	local nkmt = { __type = "NumberSequenceKeypoint" }
	NumberSequenceKeypoint = { new = function(t, v, e) return setmetatable({ Time = t, Value = v, Envelope = e or 0 }, nkmt) end }
	local nsmt = { __type = "NumberSequence" }
	NumberSequence = { new = function(a, b)
		if rawtype(a) == "number" then
			b = b or a
			return setmetatable({ Keypoints = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) } }, nsmt)
		end
		return setmetatable({ Keypoints = a }, nsmt)
	end }
	local nrmt = { __type = "NumberRange" }
	NumberRange = { new = function(a, b) return setmetatable({ Min = a, Max = b or a }, nrmt) end }
	local rmt = { __type = "Rect" }
	rmt.__eq = function(a, b) return a.Min == b.Min and a.Max == b.Max end
	Rect = { new = function(a, b, c, d)
		if typeof(a) == "Vector2" then return setmetatable({ Min = a, Max = b, Width = b.X - a.X, Height = b.Y - a.Y }, rmt) end
		return setmetatable({ Min = Vector2.new(a, b), Max = Vector2.new(c, d), Width = c - a, Height = d - b }, rmt)
	end }
	local tmt = { __type = "TweenInfo" }
	TweenInfo = { new = function(t, s, d, rc, rev, del)
		return setmetatable({ Time = t or 1, EasingStyle = s, EasingDirection = d, RepeatCount = rc or 0, Reverses = rev or false, DelayTime = del or 0 }, tmt)
	end }
	local rpmt = { __type = "RaycastParams" }
	RaycastParams = { new = function() return setmetatable({ FilterDescendantsInstances = {}, IgnoreWater = false, RespectCanCollide = false }, rpmt) end }
	local opmt = { __type = "OverlapParams" }
	OverlapParams = { new = function() return setmetatable({ FilterDescendantsInstances = {} }, opmt) end }
	local raymt = { __type = "Ray" }
	Ray = { new = function(o, d) return setmetatable({ Origin = o, Direction = d, Unit = { Origin = o, Direction = d.Unit } }, raymt) end }
	local bcmt = { __type = "BrickColor" }
	BrickColor = { new = function(n) return setmetatable({ Name = tostring(n), Color = Color3.new(0.6, 0.6, 0.6) }, bcmt) end }
	BrickColor.Gray = function() return BrickColor.new("Medium stone grey") end
	local ppmt = { __type = "PhysicalProperties" }
	PhysicalProperties = { new = function(a, b, c, d, e) return setmetatable({ Density = a, Friction = b, Elasticity = c, FrictionWeight = d, ElasticityWeight = e }, ppmt) end }
	local dtmt = { __type = "DateTime" }
	DateTime = { now = function() return setmetatable({ UnixTimestamp = os.time(), UnixTimestampMillis = os.time() * 1000 }, dtmt) end }
end

-- ------------------------------------------------------------------------------------------------ Enum
do
	local known = {
		KeyCode = { Unknown = 0, Backspace = 8, Tab = 9, Return = 13, Escape = 27, Space = 32, Quote = 39, Comma = 44, Minus = 45,
			Period = 46, Slash = 47, Zero = 48, One = 49, Two = 50, Three = 51, Four = 52, Five = 53, Six = 54, Seven = 55,
			Eight = 56, Nine = 57, Semicolon = 59, Equals = 61, LeftBracket = 91, BackSlash = 92, RightBracket = 93,
			Backquote = 96, A = 97, B = 98, C = 99, D = 100, E = 101, F = 102, G = 103, H = 104, I = 105, J = 106, K = 107,
			L = 108, M = 109, N = 110, O = 111, P = 112, Q = 113, R = 114, S = 115, T = 116, U = 117, V = 118, W = 119,
			X = 120, Y = 121, Z = 122, Delete = 127, KeypadZero = 256, KeypadOne = 257, KeypadTwo = 258, KeypadThree = 259,
			KeypadFour = 260, KeypadFive = 261, KeypadSix = 262, KeypadSeven = 263, KeypadEight = 264, KeypadNine = 265,
			Up = 273, Down = 274, Right = 275, Left = 276, Insert = 277, Home = 278, End = 279, PageUp = 280, PageDown = 281,
			F1 = 282, F2 = 283, F3 = 284, F4 = 285, F5 = 286, F6 = 287, F7 = 288, F8 = 289, F9 = 290, F10 = 291, F11 = 292,
			F12 = 293, CapsLock = 301, RightShift = 303, LeftShift = 304, RightControl = 305, LeftControl = 306,
			RightAlt = 307, LeftAlt = 308 },
		UserInputType = { MouseButton1 = 0, MouseButton2 = 1, MouseButton3 = 2, MouseWheel = 3, MouseMovement = 4, Touch = 7,
			Keyboard = 8, Focus = 9, Accelerometer = 10, Gyro = 11, Gamepad1 = 12, TextInput = 20, None = 21 },
		UserInputState = { Begin = 0, Change = 1, End = 2, Cancel = 3, None = 4 },
		HumanoidStateType = { FallingDown = 0, Ragdoll = 1, GettingUp = 2, Jumping = 3, Swimming = 4, Freefall = 5, Flying = 6,
			Landed = 7, Running = 8, RunningNoPhysics = 10, StrafingNoPhysics = 11, Climbing = 12, Seated = 13,
			PlatformStanding = 14, Dead = 15, Physics = 16, None = 18 },
		RenderPriority = { First = 0, Input = 100, Camera = 200, Character = 300, Last = 2000 },
		FontWeight = { Thin = 100, ExtraLight = 200, Light = 300, Regular = 400, Medium = 500, SemiBold = 600, Bold = 700,
			ExtraBold = 800, Heavy = 900 },
		FontStyle = { Normal = 0, Italic = 1 },
		TextXAlignment = { Left = 0, Right = 1, Center = 2 },
		TextYAlignment = { Top = 0, Center = 1, Bottom = 2 },
		MouseBehavior = { Default = 0, LockCenter = 1, LockCurrentPosition = 2 },
		CameraType = { Fixed = 0, Attach = 1, Watch = 2, Track = 3, Follow = 4, Custom = 5, Scriptable = 6, Orbital = 7 },
		ZIndexBehavior = { Global = 0, Sibling = 1 },
		RotationType = { MovementRelative = 0, CameraRelative = 1 },
		HumanoidRigType = { R6 = 0, R15 = 1 },
		EasingStyle = { Linear = 0, Sine = 1, Back = 2, Quad = 3, Quart = 4, Quint = 5, Bounce = 6, Elastic = 7, Exponential = 8, Circular = 9, Cubic = 10 },
		EasingDirection = { In = 0, Out = 1, InOut = 2 },
		AnimationPriority = { Idle = 0, Movement = 1, Action = 2, Action2 = 3, Action3 = 4, Action4 = 5, Core = 1000 },
		ContextActionResult = { Sink = 0, Pass = 1 },
		CoreGuiType = { PlayerList = 0, Health = 1, Backpack = 2, Chat = 3, All = 4, EmotesMenu = 5, SelfView = 6, Captures = 7 },
		SurfaceType = { Smooth = 0, Glue = 1, Weld = 2, Studs = 3, Inlet = 4, Universal = 5, Hinge = 6, Motor = 7, SteppingMotor = 8, SmoothNoOutlines = 10 },
		Font = { Legacy = 0, Arial = 1, ArialBold = 2, SourceSans = 3, SourceSansBold = 4, SourceSansLight = 5, SourceSansItalic = 6,
			Bodoni = 7, Garamond = 8, Cartoon = 9, Code = 10, Highway = 11, SciFi = 12, Arcade = 13, Fantasy = 14, Antique = 15,
			SourceSansSemibold = 16, Gotham = 17, GothamMedium = 18, GothamBold = 19, GothamBlack = 20, RobotoMono = 41, Roboto = 37, Unknown = 100 },
		Material = { Plastic = 256, SmoothPlastic = 272, Neon = 288, Wood = 512, Glass = 1568, ForceField = 1584, Metal = 1088 },
		FillDirection = { Horizontal = 0, Vertical = 1 },
		SortOrder = { Name = 0, Custom = 1, LayoutOrder = 2 },
		HorizontalAlignment = { Center = 0, Left = 1, Right = 2 },
		VerticalAlignment = { Center = 0, Top = 1, Bottom = 2 },
		AutomaticSize = { None = 0, X = 1, Y = 2, XY = 3 },
		ScrollingDirection = { X = 1, Y = 2, XY = 4 },
		ApplyStrokeMode = { Contextual = 0, Border = 1 },
		ScaleType = { Stretch = 0, Slice = 1, Tile = 2, Fit = 3, Crop = 4 },
		ResampleMode = { Default = 0, Pixelated = 1 },
		ResamplerMode = { Default = 0, Pixelated = 1 },
		TextTruncate = { None = 0, AtEnd = 1, SplitWord = 2 },
		SizeConstraint = { RelativeXY = 0, RelativeXX = 1, RelativeYY = 2 },
		BorderMode = { Outline = 0, Middle = 1, Inset = 2 },
		ScreenInsets = { None = 0, DeviceSafeInsets = 1, CoreUISafeInsets = 2, TopbarSafeInsets = 3 },
		PartType = { Ball = 0, Block = 1, Cylinder = 2, Wedge = 3, CornerWedge = 4 },
		DeveloperMemoryTag = { Internal = 0, HttpCache = 1, Instances = 2, Signals = 3, LuaHeap = 4, Script = 5 },
		CameraMode = { Classic = 0, LockFirstPerson = 1 },
		DevComputerCameraMovementMode = { UserChoice = 0, Classic = 1, Follow = 2, Orbital = 3, CameraToggle = 4 },
		ComputerCameraMovementMode = { Default = 0, Follow = 1, Classic = 2, Orbital = 3, CameraToggle = 4 },
		LineJoinMode = { Round = 0, Bevel = 1, Miter = 2 },
		ThumbnailType = { HeadShot = 0, AvatarBust = 1, AvatarThumbnail = 2 },
		ThumbnailSize = { Size48x48 = 0, Size60x60 = 1, Size100x100 = 2, Size150x150 = 3, Size180x180 = 4, Size352x352 = 5, Size420x420 = 6 },
	}
	local itemMt = { __type = "EnumItem" }
	itemMt.__tostring = function(i) return "Enum." .. i.EnumType.Name .. "." .. i.Name end
	local enumMt = { __type = "Enum" }
	local enums = {}
	local function makeEnum(name)
		local e = setmetatable({ Name = name, _items = {}, _byValue = {}, _next = 0 }, enumMt)
		local function add(iname, v)
			local it = setmetatable({ Name = iname, Value = v, EnumType = e }, itemMt)
			e._items[iname] = it
			e._byValue[v] = e._byValue[v] or it
			if v >= e._next then e._next = v + 1 end
			return it
		end
		e._add = add
		if known[name] then
			local names = {}
			for k in pairs(known[name]) do names[#names + 1] = k end
			table.sort(names, function(a, b) return known[name][a] < known[name][b] end)
			for _, k in ipairs(names) do add(k, known[name][k]) end
		end
		return e
	end
	enumMt.__index = function(e, k)
		if k == "GetEnumItems" then
			return function(self)
				local out = {}
				for _, it in pairs(self._items) do out[#out + 1] = it end
				table.sort(out, function(a, b) return a.Value < b.Value end)
				return out
			end
		elseif k == "FromValue" then
			return function(self, v) return self._byValue[v] end
		elseif k == "FromName" then
			return function(self, n) return self._items[n] end
		end
		local it = rawget(e, "_items")[k]
		if it then return it end
		if known[rawget(e, "Name")] then
			error(tostring(k) .. " is not a valid member of \"Enum." .. rawget(e, "Name") .. "\"", 2)
		end
		return e._add(k, e._next) -- unknown enum: invent items on demand
	end
	Enum = setmetatable({}, { __type = "Enums", __index = function(t, k)
		local e = enums[k]
		if not e then e = makeEnum(k); enums[k] = e end
		return e
	end })
end

-- ------------------------------------------------------------------------------------------------ Font
do
	local fmt = { __type = "Font" }
	local function new(family, weight, style)
		local f = setmetatable({ Family = family, Weight = weight or Enum.FontWeight.Regular, Style = style or Enum.FontStyle.Normal }, fmt)
		return f
	end
	fmt.__index = function(t, k)
		if k == "Bold" then return rawget(t, "Weight").Value >= 600 end
		return nil
	end
	fmt.__eq = function(a, b) return a.Family == b.Family and a.Weight == b.Weight and a.Style == b.Style end
	local fam = { Code = "Inconsolata", RobotoMono = "RobotoMono", SourceSans = "SourceSansPro", Gotham = "GothamSSm", Arial = "Arimo",
		Roboto = "Roboto", Arcade = "PressStart2P", Legacy = "LegacyArial", Antique = "RomanAntique" }
	Font = { new = new }
	function Font.fromEnum(e)
		if e == Enum.Font.Unknown then error("Font.fromEnum: Unknown") end
		local n = fam[e.Name] or e.Name
		local w = Enum.FontWeight.Regular
		if e.Name:find("Bold") then w = Enum.FontWeight.Bold end
		return new("rbxasset://fonts/families/" .. n .. ".json", w, Enum.FontStyle.Normal)
	end
	function Font.fromName(n, w, s) return new("rbxasset://fonts/families/" .. n .. ".json", w, s) end
	function Font.fromId(id, w, s) return new("rbxassetid://" .. tostring(id), w, s) end
	M.fontFamilyAdvance = { Inconsolata = 0.5, RobotoMono = 0.6001, PressStart2P = 1.0 }
end
