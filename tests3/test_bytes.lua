-- needs: fsfail
-- ================================================================================================
-- HappaTAS 3, phase 3: files, the byte writer / reader and plain values (the pieces every save uses)
-- ================================================================================================
check(boot(3), "boots")
local Bytes, Value, Files = __T3("persist/bytes"), __T3("persist/value"), __T3("platform/files")
local Env = __T3("platform/env")

-- equal values; numbers exactly (NaN equal to NaN, -0 not equal to 0)
local function deepEqual(a, b, seen)
	if type(a) ~= type(b) then return false end
	if type(a) == "number" then
		if a ~= a then return b ~= b end
		if a == 0 and b == 0 then return 1 / a == 1 / b end
		return a == b
	end
	if type(a) ~= "table" then return a == b end
	seen = seen or {}
	if seen[a] then return seen[a] == b end
	seen[a] = b
	for k, v in pairs(a) do
		if not deepEqual(v, b[k], seen) then return false end
	end
	for k in pairs(b) do
		if a[k] == nil then return false end
	end
	return true
end

section("the writer and the reader")
do
	local w = Bytes.writer()
	w:u8(255); w:varint(0); w:varint(2 ^ 53); w:zigzag(-123456789); w:f64(-0.0); w:f64(1 / 3); w:str("héllo\0x")
	local r = Bytes.reader(w:tostring())
	eq(r:u8(), 255, "u8")
	eq(r:varint(), 0, "varint 0")
	eq(r:varint(), 2 ^ 53, "varint 2^53")
	eq(r:zigzag(), -123456789, "zigzag")
	eq(1 / r:f64(), -math.huge, "-0 kept")
	eq(r:f64(), 1 / 3, "f64 exact")
	eq(r:str(), "héllo\0x", "string with a zero byte")
	eq(r:left(), 0, "all read")
	check(not pcall(function() Bytes.reader("\255"):varint() end), "a cut varint errors")
	local okS, errS = pcall(function() Bytes.reader("\5ab"):str() end)
	check(not okS and tostring(errS):find("file is damaged") ~= nil, "a string longer than the file errors")
	check(not pcall(function() Bytes.reader(""):u8() end), "reading past the end errors")
	check(not pcall(function() Bytes.reader(""):f64() end), "an f64 past the end errors")
	-- (a reader over part of a string: pos / last)
	local r2 = Bytes.reader("xx\1\2yy", 3, 4)
	eq(r2:u8(), 1, "reader from pos")
	eq(r2:u8(), 2, "second byte")
	check(not pcall(function() r2:u8() end), "stops at last")
	-- a long writer grows (the buffer doubles)
	local w3 = Bytes.writer()
	for i = 1, 100000 do w3:varint(i) end
	local r3 = Bytes.reader(w3:tostring())
	local okAll = true
	for i = 1, 100000 do if r3:varint() ~= i then okAll = false break end end
	check(okAll, "100000 varints round-trip")
	-- raw bytes and a buffer slice
	local b = buffer.create(10)
	for i = 0, 9 do buffer.writeu8(b, i, i + 65) end
	local w4 = Bytes.writer()
	w4:raw("ab"); w4:rawBuffer(b, 2, 3)
	eq(w4:len(), 5, "len")
	eq(w4:tostring(), "abCDE", "raw + buffer slice")
	eq(Bytes.reader("abc"):raw(2), "ab", "raw read")
	check(not pcall(function() Bytes.reader("abc"):raw(4) end), "raw past the end errors")
end

section("plain values")
do
	local v = { 1, -2, 3.5, "x", true, false, { a = { b = { c = 1 } } }, [10] = "sparse", k = 2 ^ 40, nan = 0 / 0, neg0 = -0.0 }
	local w2 = Bytes.writer()
	Value.write(w2, v)
	check(deepEqual(Value.read(Bytes.reader(w2:tostring())), v), "a table round-trips")
	for _, x in ipairs({ 0, 1, 127, 128, -1, -2 ^ 52, 2 ^ 53, 1e300, -1e-300, math.huge, -math.huge }) do
		local w = Bytes.writer()
		Value.write(w, x)
		check(deepEqual(Value.read(Bytes.reader(w:tostring())), x), "number " .. tostring(x))
	end
	local wn = Bytes.writer()
	Value.write(wn, nil)
	eq(Value.read(Bytes.reader(wn:tostring())), nil, "nil")
	check(not pcall(Value.write, Bytes.writer(), { workspace }), "an Instance is refused")
	check(not pcall(Value.write, Bytes.writer(), { print }), "a function is refused")
	check(not pcall(Value.write, Bytes.writer(), { Vector3.new(1, 2, 3) }), "a Vector3 is refused (a Roblox type, not a plain table)")
	local cyc = {}
	cyc.self = cyc
	local okC, errC = pcall(Value.write, Bytes.writer(), cyc)
	check(not okC and tostring(errC):find("nested too deep") ~= nil, "a cycle is refused")
	check(not pcall(Value.read, Bytes.reader("\9")), "an unknown tag errors")
end

section("names and files")
do
	eq(Files.cleanName("  ../a<b>|c?.  "), "abc", "cleaned like V2 (characters removed, dots / spaces trimmed)")
	eq(Files.cleanName("CON"), "_CON", "reserved name")
	eq(Files.cleanName(string.rep("é", 70)), string.rep("é", 60), "60 characters")
	eq(Files.cleanName("   "), nil, "nothing left")
	eq(Files.join("HappaTasPort", "1", "a.tas"), "HappaTasPort/1/a.tas", "join")

	local F = Files.new(Env)
	check(F.available, "available in the mock")
	check(F:makeFolder("HappaTasPort/x/y"), "makeFolder with missing parents")
	check(F:isFolder("HappaTasPort/x/y"), "the folder exists")
	check(F:write("HappaTasPort/x/a.tas", "abc"), "write")
	eq(F:read("HappaTasPort/x/a.tas"), "abc", "read")
	check(F:exists("HappaTasPort/x/a.tas"), "exists")
	local files = F:listFiles("HappaTasPort/x")
	eq(#files, 1, "one file listed")
	eq(files[1], "a.tas", "by its name")
	local folders = F:listFolders("HappaTasPort/x")
	eq(#folders, 1, "one folder")
	eq(folders[1], "y", "the folder's name")
	check(F:delete("HappaTasPort/x/a.tas"), "delete")
	check(not F:exists("HappaTasPort/x/a.tas"), "gone")

	FSFAIL.write = "fail%.txt"
	local ok, err = F:write("HappaTasPort/fail.txt", "x")
	check(not ok and type(err) == "string", "a failing write returns false, message")
	FSFAIL.write = nil
	FSFAIL.read = "a%.tas$"
	F:write("HappaTasPort/x/a.tas", "abc")
	local s, errR = F:read("HappaTasPort/x/a.tas")
	check(s == nil and type(errR) == "string", "a failing read returns nil, message")
	FSFAIL.read = nil
	local s2 = F:read("HappaTasPort/x/missing.tas")
	eq(s2, nil, "a missing file reads as nil")
end
finish()
