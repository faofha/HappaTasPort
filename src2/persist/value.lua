-- ================================================================================================
--  VALUE  (HappaTAS 3 persist): plain Lua values to bytes and back (a run's rare per-frame data and its
--  tables). Tags: 0 nil, 1 false, 2 true, 3 integer >= 0 (varint), 4 integer < 0 (zigzag), 5 f64,
--  6 string, 7 table (varint n, the values 1..n, varint hash count, key / value pairs). Anything else
--  (an Instance, a function, a Vector3) can't be saved and errors; so does a table nested deeper than
--  64 (a cycle too).
-- ================================================================================================
local Value = {}

local MAX_DEPTH = 64
local MAX_INT = 2 ^ 53
local typeOf = typeof or type

local write
local function writeTable(w, t, depth)
	if depth > MAX_DEPTH then error("table nested too deep", 0) end
	local n = 0
	while t[n + 1] ~= nil do n = n + 1 end
	w:u8(7)
	w:varint(n)
	for i = 1, n do write(w, t[i], depth + 1) end
	local count = 0
	for k in pairs(t) do
		if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then count = count + 1 end
	end
	w:varint(count)
	for k, v in pairs(t) do
		if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then
			write(w, k, depth + 1)
			write(w, v, depth + 1)
		end
	end
end

write = function(w, v, depth)
	local t = typeOf(v)
	if v == nil then
		w:u8(0)
	elseif v == false then
		w:u8(1)
	elseif v == true then
		w:u8(2)
	elseif t == "number" then
		if v == math.floor(v) and v >= -MAX_INT and v <= MAX_INT and not (v == 0 and 1 / v < 0) then
			if v >= 0 then
				w:u8(3)
				w:varint(v)
			else
				w:u8(4)
				w:zigzag(v)
			end
		else
			w:u8(5)
			w:f64(v)
		end
	elseif t == "string" then
		w:u8(6)
		w:str(v)
	elseif t == "table" then
		writeTable(w, v, depth)
	else
		error("can't save a " .. tostring(t), 0)
	end
end

function Value.write(w, v) write(w, v, 0) end

local read
read = function(r, depth)
	if depth > MAX_DEPTH then error("file is damaged: table nested too deep", 0) end
	local tag = r:u8()
	if tag == 0 then return nil end
	if tag == 1 then return false end
	if tag == 2 then return true end
	if tag == 3 then return r:varint() end
	if tag == 4 then return r:zigzag() end
	if tag == 5 then return r:f64() end
	if tag == 6 then return r:str() end
	if tag == 7 then
		local n = r:varint()
		if n > r:left() then error("file is damaged: table longer than the file", 0) end
		local t = table.create(n)
		for i = 1, n do t[i] = read(r, depth + 1) end
		local count = r:varint()
		if count > r:left() then error("file is damaged: table longer than the file", 0) end
		for _ = 1, count do
			local k = read(r, depth + 1)
			local v = read(r, depth + 1)
			if k == nil or k ~= k then error("file is damaged: bad table key", 0) end
			t[k] = v
		end
		return t
	end
	error("file is damaged: unknown value tag " .. tostring(tag), 0)
end

function Value.read(r) return read(r, 0) end

return Value
