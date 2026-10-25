-- ================================================================================================
--  BYTES  (HappaTAS 3 persist): a growing byte writer and a reader that checks every read against the
--  end of its data. A read past the end, a varint over 2^53 or a string longer than what is left errors
--  "file is damaged: ...", so a damaged file can never be read as something else.
--    varint: 7 bits a byte, low first (0 .. 2^53)    zigzag: varint of 2n (n >= 0) / -2n - 1 (n < 0)
--    f64: 8 bytes little endian    str: varint length, then the bytes
-- ================================================================================================
local Bytes = {}

local MAX_VARINT = 2 ^ 53

local Writer = {}
Writer.__index = Writer

function Bytes.writer(capacity)
	local cap = capacity or 256
	return setmetatable({ buf = buffer.create(cap), cap = cap, n = 0 }, Writer)
end

local function ensure(self, more)
	local need = self.n + more
	if need <= self.cap then return end
	local cap = self.cap
	while cap < need do cap = cap * 2 end
	local nb = buffer.create(cap)
	buffer.copy(nb, 0, self.buf, 0, self.n)
	self.buf, self.cap = nb, cap
end

function Writer:u8(v)
	ensure(self, 1)
	buffer.writeu8(self.buf, self.n, v)
	self.n = self.n + 1
end

function Writer:varint(v)
	if v < 0 or v > MAX_VARINT or v ~= math.floor(v) then error("varint out of range: " .. tostring(v), 2) end
	ensure(self, 8)
	local buf, n = self.buf, self.n
	while v >= 128 do
		buffer.writeu8(buf, n, v % 128 + 128)
		n = n + 1
		v = math.floor(v / 128)
	end
	buffer.writeu8(buf, n, v)
	self.n = n + 1
end

function Writer:zigzag(v)
	if v >= 0 then self:varint(v * 2) else self:varint(-v * 2 - 1) end
end

function Writer:f64(v)
	ensure(self, 8)
	buffer.writef64(self.buf, self.n, v)
	self.n = self.n + 8
end

function Writer:raw(s)
	local len = #s
	ensure(self, len)
	buffer.writestring(self.buf, self.n, s)
	self.n = self.n + len
end

function Writer:str(s)
	self:varint(#s)
	self:raw(s)
end

function Writer:rawBuffer(b, offset, len)
	ensure(self, len)
	buffer.copy(self.buf, self.n, b, offset, len)
	self.n = self.n + len
end

function Writer:len() return self.n end
function Writer:tostring() return buffer.readstring(self.buf, 0, self.n) end

local Reader = {}
Reader.__index = Reader

-- reads s from pos (default 1) up to last (default #s), both inclusive
function Bytes.reader(s, pos, last)
	return setmetatable({ s = s, p = pos or 1, last = last or #s }, Reader)
end

local function damaged(what) error("file is damaged: " .. what, 0) end

function Reader:u8()
	local p = self.p
	if p > self.last then damaged("ends early") end
	self.p = p + 1
	return string.byte(self.s, p)
end

function Reader:varint()
	local s, p, last = self.s, self.p, self.last
	local v, mul = 0, 1
	while true do
		if p > last then damaged("ends inside a number") end
		local b = string.byte(s, p)
		p = p + 1
		if b < 128 then
			v = v + b * mul
			break
		end
		v = v + (b - 128) * mul
		mul = mul * 128
		if mul > MAX_VARINT * 128 then damaged("number too long") end
	end
	if v > MAX_VARINT then damaged("number too big") end
	self.p = p
	return v
end

function Reader:zigzag()
	local v = self:varint()
	if v % 2 == 0 then return v / 2 end
	return -(v + 1) / 2
end

function Reader:f64()
	local p = self.p
	if p + 7 > self.last then damaged("ends inside a number") end
	self.p = p + 8
	return (string.unpack("<d", self.s, p))
end

function Reader:raw(n)
	local p = self.p
	if n < 0 or p + n - 1 > self.last then damaged("ends early") end
	self.p = p + n
	return string.sub(self.s, p, p + n - 1)
end

function Reader:str()
	local n = self:varint()
	if n > self.last - self.p + 1 then damaged("text longer than the file") end
	return self:raw(n)
end

function Reader:pos() return self.p end
function Reader:left() return self.last - self.p + 1 end

return Bytes
