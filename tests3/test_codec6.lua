-- ================================================================================================
-- HappaTAS 3, phase 3: file format v6 (header, columns, meta), LZ4 with and without the executor's
-- functions (run once per line of tests3/codec6.variants)
-- ================================================================================================
check(boot(3), "boots")
local Timeline = __T3("engine/timeline")
local Codec6 = __T3("persist/codec6")
local Lz4 = __T3("persist/lz4")
VARIANT = VARIANT or "plain"

local function deepEqual(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) == "number" then
		if a ~= a then return b ~= b end
		if a == 0 and b == 0 then return 1 / a == 1 / b end
		return a == b
	end
	if type(a) ~= "table" then return a == b end
	for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

local function r1000(x) return math.floor(x * 1000 + 0.5) / 1000 end

-- a timeline like a recorded one: rounded positions (random walk), constant stretches, rare list data,
-- a few special numbers
local function makeTimeline(n, seed)
	local tl = Timeline.new()
	tl:addColumn("FrameTime", "f64", 1, { key = "FrameTime" })
	tl:addColumn("Cframe", "f64", 12, { key = "Cframe" })
	tl:addColumn("Lin", "f64", 3, { key = "Velocity", sub = "Linear" })
	tl:addColumn("State", "u8", 1, { key = "State" })
	tl:addColumn("Odd", "f64", 1, nil)
	tl:addColumn("Input", "list", 1, { key = "Input" })
	tl:addColumn("Died", "list", 1, { key = "Died" })
	local rnd = Random.new(seed or 7)
	local px, py, pz = 0, 3, 0
	for i = 1, n do
		tl:append()
		tl:set("FrameTime", i, 1, math.floor(1 / 240 * 1e6 + 0.5) / 1e6)
		if i % 50 < 30 then
			px, pz = px + rnd:NextNumber() * 0.07, pz - rnd:NextNumber() * 0.05
		end
		tl:setN("Cframe", i, r1000(px), r1000(py), r1000(pz), 1, 0, 0, 0, 1, 0, 0, 0, 1)
		tl:setN("Lin", i, r1000(rnd:NextNumber() * 16), 0, -0.0)
		tl:set("State", i, 1, (i % 97 == 0) and 3 or 8)
		local odd = ({ 0 / 0, -0.0, 1e300, math.huge, 1 / 3 })[i % 5 + 1]
		tl:set("Odd", i, 1, odd)
		if i % 7 == 0 then tl:setList("Input", i, { { "W", 1 }, { "Space", i % 2 } }) end
		if i == n - 3 then tl:setList("Died", i, true) end
		tl:setFilled(i)
	end
	return tl
end

local function rawBytesPerFrame(tl)
	local b = 0
	for _, col in ipairs(tl.order) do
		if col.buf and col.name ~= "_filled" then b = b + col.stride end
	end
	return b
end

-- every column of a in b, byte for byte (lists equal)
local function sameBits(a, b)
	if a:count() ~= b:count() then return false, "count " .. b:count() end
	for _, col in ipairs(a.order) do
		if col.name ~= "_filled" then
			local other = b.cols[col.name]
			if not other then return false, "no column " .. col.name end
			if col.buf then
				local n = a:count() * col.stride
				if buffer.readstring(col.buf, 0, n) ~= buffer.readstring(other.buf, 0, n) then return false, "bytes of " .. col.name end
			else
				for i = 1, a:count() do
					if not deepEqual(col.list[i], other.list[i]) then return false, "list " .. col.name .. " frame " .. i end
				end
			end
		end
	end
	for i = 1, b:count() do
		if not b:isFilled(i) then return false, "frame " .. i .. " not filled" end
	end
	return true
end

-- runs f(...) on a thread of its own (the codec yields every 2000 frames, like a save in the game) and
-- steps the mock until it ends; returns pcall's results
local function inThread(f, ...)
	local args, n = { ... }, select("#", ...)
	local res
	local co = coroutine.create(function() res = table.pack(pcall(f, table.unpack(args, 1, n))) end)
	coroutine.resume(co)
	local guard = 0
	while coroutine.status(co) ~= "dead" and guard < 100000 do
		M.step(1 / 60)
		guard = guard + 1
	end
	return table.unpack(res, 1, res.n)
end
local function encode(...) local ok, v = inThread(Codec6.encode, ...); assert(ok, v); return v end
local function decode(...) local ok, v = inThread(Codec6.decode, ...); assert(ok, v); return v end
local function tryDecode(...) return inThread(Codec6.decode, ...) end

local N = 5000
local tl = makeTimeline(N)
tl.meta = { created = 1761400000, v2kit = { version = 1, keys = { { 1, "a" } } } }
local hdr = { frames = N, length = 20.8, created = 1, saved = 2, script = "3.0.0-dev", place = 72164126024589, kit = 1,
	speedHack = 0, name = "x" }

section("round trip [" .. VARIANT .. "]")
local data = encode(tl, hdr)
eq(data:sub(1, 5), "HTAS\6", "magic and version 6")
local compressed = string.byte(data, 6) % 2 == 1
if VARIANT == "nocompress" then
	check(not compressed, "without lz4compress the body is stored as it is")
else
	check(compressed, "the body is LZ4")
end
local back = Timeline.newLike(tl)
local h2 = decode(data, back)
local same, why = sameBits(tl, back)
check(same, "every column bit for bit (NaN, -0, inf too) " .. tostring(why))
check(deepEqual(back.meta, tl.meta), "meta")
check(deepEqual(h2, hdr), "decode returns the header")
if VARIANT ~= "nocompress" then
	check(#data < 0.25 * N * rawBytesPerFrame(tl), "smaller than a quarter of the raw columns (" .. #data .. " bytes, raw " .. N * rawBytesPerFrame(tl) .. ")")
end

section("rounded values that change every frame take a few bytes [" .. VARIANT .. "]")
do
	local walk = Timeline.new()
	walk:addColumn("P", "f64", 3, nil)
	local rnd = Random.new(3)
	local x, y, z = 0, 0, 0
	for i = 1, N do
		walk:append()
		x, y, z = x + rnd:NextNumber() * 0.2 - 0.1, y + rnd:NextNumber() * 0.1, z - rnd:NextNumber() * 0.3
		walk:setN("P", i, r1000(x), r1000(y), r1000(z))
	end
	local d = encode(walk, {})
	check(#d < 3 * 3 * N, "under 3 bytes a value (" .. string.format("%.2f", #d / (3 * N)) .. ")")
	local wb = Timeline.newLike(walk)
	decode(d, wb)
	check((sameBits(walk, wb)), "and exact")
end

section("the header alone [" .. VARIANT .. "]")
check(deepEqual(Codec6.readHeader(data .. "garbage-after"), hdr), "header with anything after it")
check(deepEqual(Codec6.readHeader(data:sub(1, 256)), hdr), "header from the first 256 bytes")
local hNil, hErr = Codec6.readHeader(data:sub(1, 10))
check(hNil == nil and type(hErr) == "string", "10 bytes: nil and a message")
local hNil2 = Codec6.readHeader("HTAS\5\1abc")
eq(hNil2, nil, "a V2 file has no v6 header")

section("damaged files [" .. VARIANT .. "]")
do
	local allFail = true
	for cut = 7, #data - 1, 97 do
		local ok = tryDecode( data:sub(1, cut), Timeline.newLike(tl))
		if ok then allFail = false; check(false, "cut at " .. cut .. " decoded") break end
	end
	check(allFail, "every cut file errors")
	check(not tryDecode("HTAS" .. data:sub(6), Timeline.newLike(tl)), "a version 5 label is not read as v6")
	local ok7, err7 = tryDecode( "HTAS\7" .. data:sub(6), Timeline.newLike(tl))
	check(not ok7 and tostring(err7):find("unsupported") ~= nil, "version 7: " .. tostring(err7))
	check(not tryDecode( "NOPE" .. data:sub(5), Timeline.newLike(tl)), "wrong magic")
	check(not tryDecode( data .. "x", Timeline.newLike(tl)), "bytes after the end")
	-- a header claiming more frames than allowed
	local big = encode(Timeline.new(), { frames = 0 })
	check(tryDecode( big, Timeline.new()), "an empty run decodes")
end

section("columns the timeline doesn't have, columns with another shape [" .. VARIANT .. "]")
do
	local plain = Timeline.new()
	plain:addColumn("FrameTime", "f64", 1, { key = "FrameTime" })
	decode(data, plain)
	check(plain.cols.Cframe ~= nil and plain.cols.Cframe.width == 12, "a column only the file has is added")
	local again = encode(plain, hdr)
	local back2 = Timeline.newLike(tl)
	decode(again, back2)
	check((sameBits(tl, back2)), "and saved again, it round-trips")
	local wrong = Timeline.new()
	wrong:addColumn("Cframe", "f64", 3, nil)
	local okW, errW = tryDecode( data, wrong)
	check(not okW and tostring(errW):find("different shape") ~= nil, "a column with another width errors")
	local missing = Timeline.newLike(tl)
	missing:addColumn("Later", "f64", 2, nil)
	decode(data, missing)
	eq(missing:get("Later", N, 2), 0, "a timeline column the file lacks stays zero")
end

section("yielding and progress [" .. VARIANT .. "]")
do
	local calls, last = 0, nil
	local yields = 0
	local co = coroutine.create(function()
		return Codec6.encode(tl, hdr, function(done, total) calls = calls + 1; last = { done, total } end)
	end)
	local ok, res = coroutine.resume(co)
	local guard = 0
	while coroutine.status(co) ~= "dead" and guard < 10000 do
		yields = yields + 1
		M.step(1 / 60)
		guard = guard + 1
	end
	check(yields >= 2, "encoding 5000 frames yields at least twice (" .. yields .. ")")
	check(last and last[1] == N and last[2] == N, "progress ends at (5000, 5000)")
	check(calls >= 3, "progress called every 2000 frames (" .. calls .. ")")
end

section("LZ4 [" .. VARIANT .. "]")
do
	local s = string.rep("abcdefgh", 1000) .. "xyz"
	local c = Lz4.compress(s)
	if VARIANT == "nocompress" then
		eq(c, nil, "no lz4compress: nil")
	else
		check(type(c) == "string" and #c < #s, "compresses")
		eq(Lz4.decompress(c, #s), s, "decompresses")
		check(not pcall(Lz4.decompress, c, #s + 1), "another size errors")
	end
	-- the Lua fallback on its own (a block from the mock's compressor)
	local block = M.LZ4.compress(s)
	eq(Lz4.fallback(block, #s), s, "fallback decoder")
	check(not pcall(Lz4.fallback, block:sub(1, #block - 3), #s), "fallback: a cut block errors")
end
finish()
