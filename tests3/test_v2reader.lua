-- needs: v2fixtures
-- ================================================================================================
-- HappaTAS 3, phase 3: the V2 reader (v1-v5, the V2.34 LZ4 wrap, legacy JSON slots), compared with what
-- V2.38.16's own decoder makes of the same files (tests3/fixtures/v2, tools/make_v2_fixtures3.sh)
-- ================================================================================================
check(boot(3), "boots")
local V2Reader = __T3("persist/v2reader")

local function deepEqual(a, b, path)
	path = path or "value"
	if type(a) ~= type(b) then return false, path .. ": " .. type(a) .. " / " .. type(b) end
	if type(a) == "number" then
		if a ~= a then return b ~= b, path end
		return a == b, path .. ": " .. tostring(a) .. " / " .. tostring(b)
	end
	if type(a) ~= "table" then return a == b, path .. ": " .. tostring(a) .. " / " .. tostring(b) end
	for k, v in pairs(a) do
		local ok, why = deepEqual(v, b[k], path .. "." .. tostring(k))
		if not ok then return false, why end
	end
	for k in pairs(b) do
		if a[k] == nil then return false, path .. "." .. tostring(k) .. " only on one side" end
	end
	return true
end

-- runs f on a thread of its own, the mock stepped until it ends (the reader waits on long files)
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

section("every fixture: the same as V2's decoder")
local names = {}
for name in pairs(FIXTURES) do names[#names + 1] = name end
table.sort(names)
check(#names >= 12, "fixtures there (" .. #names .. ")")
for _, name in ipairs(names) do
	local fx = FIXTURES[name]
	local exp = fx.expected
	local ok, got = inThread(V2Reader.read, fx.data)
	if exp.error then
		check(not ok, name .. ": refused, like V2 (" .. exp.error .. ")")
	else
		check(ok, name .. ": read (" .. tostring(not ok and got or "") .. ")")
		if ok then
			local same, why = deepEqual(got.frames, exp.frames, "frames")
			check(same, name .. ": frames " .. tostring(why))
			if exp.kitVersion ~= nil then eq(got.kitVersion, exp.kitVersion, name .. ": kit version") end
			if not name:find("%.json$") and name ~= "wrapped.tas" then
				check((deepEqual(got.objects, exp.objects)), name .. ": objects")
				check((deepEqual(got.buttons, exp.buttons)), name .. ": buttons")
				check((deepEqual(got.kit, exp.kit)), name .. ": kit table")
				local v = string.byte(fx.data, 5)
				eq(got.version, v, name .. ": version")
			end
			if name:find("%.json$") then eq(got.version, 0, name .. ": legacy JSON is version 0") end
		end
	end
end

section("anything that isn't a V2 file is refused")
check(not inThread(V2Reader.read, "hello"), "text")
check(not inThread(V2Reader.read, "HTAS\6\0\0\0"), "a v6 file is not V2's")
check(not inThread(V2Reader.read, ""), "empty")

section("300 damaged copies: each one read or refused, none hangs")
do
	local data = FIXTURES["kitspeed.tas"].data
	local rnd = Random.new(5)
	local read, refused = 0, 0
	for _ = 1, 300 do
		local pos = rnd:NextInteger(5, #data)
		local flipped = data:sub(1, pos - 1) .. string.char((string.byte(data, pos) + rnd:NextInteger(1, 255)) % 256) .. data:sub(pos + 1)
		local ok = inThread(V2Reader.read, flipped)
		if ok then read = read + 1 else refused = refused + 1 end
	end
	eq(read + refused, 300, "every copy finished (" .. read .. " read, " .. refused .. " refused)")
end
finish()
