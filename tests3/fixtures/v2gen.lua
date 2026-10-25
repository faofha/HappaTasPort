-- ================================================================================================
-- V2 fixture generator (run by tools/make_v2_fixtures3.sh inside the reference V2.38.16 build in the
-- mock): synthetic runs with every field V2's codec has, saved with V2's own encoder, and what V2's own
-- decoder (or Store.LoadSlot, for the legacy formats) makes of each file. Prints
--   FILE <name> <hex of the bytes>
--   EXPECTED <name> <hex of a Lua source: return { frames, objects, buttons, kit, kitVersion, error }>
-- ================================================================================================
check(boot(3), "boots")
local Codec, Store = __T.Codec, __T.Store
local HttpService = game:GetService("HttpService")

local function hex(s) return (s:gsub(".", function(c) return string.format("%02x", string.byte(c)) end)) end

-- a Lua literal for any plain value (numbers exact, strings byte-safe, keys sorted)
local function lit(v, out)
	local t = type(v)
	if t == "number" then
		if v ~= v then out[#out + 1] = "0/0"
		elseif v == math.huge then out[#out + 1] = "math.huge"
		elseif v == -math.huge then out[#out + 1] = "-math.huge"
		elseif v == math.floor(v) and math.abs(v) < 2 ^ 53 then out[#out + 1] = string.format("%d", v)
		else
			-- (the shortest text that reads back as the same number)
			local short = tostring(v)
			out[#out + 1] = (tonumber(short) == v) and short or string.format("%.17g", v)
		end
	elseif t == "string" then
		out[#out + 1] = '"' .. v:gsub('[%c"\\\128-\255]', function(c) return string.format("\\%03d", string.byte(c)) end) .. '"'
	elseif t == "boolean" or t == "nil" then
		out[#out + 1] = tostring(v)
	elseif t == "table" then
		-- (a sequence as a plain list)
		local n, count = #v, 0
		for _ in pairs(v) do count = count + 1 end
		if count == n and n > 0 then
			out[#out + 1] = "{"
			for i = 1, n do
				lit(v[i], out)
				out[#out + 1] = ","
			end
			out[#out + 1] = "}"
			return out
		end
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b)
			if type(a) ~= type(b) then return type(a) < type(b) end
			return a < b
		end)
		out[#out + 1] = "{"
		for _, k in ipairs(keys) do
			out[#out + 1] = "["
			lit(k, out)
			out[#out + 1] = "]="
			lit(v[k], out)
			out[#out + 1] = ","
		end
		out[#out + 1] = "}"
	else
		error("can't write a " .. t)
	end
	return out
end

local function emit(name, data, expected)
	M.realPrint("FILE " .. name .. " " .. hex(data))
	M.realPrint("EXPECTED " .. name .. " " .. hex("return " .. table.concat(lit(expected, {}))))
end

-- what V2's decoder makes of the bytes (its error text when it refuses them)
local function decoded(data)
	local ok, frames, objects, buttons, kit = pcall(Codec.Decode, data)
	if not ok then return { error = tostring(frames) } end
	return { frames = frames, objects = objects, buttons = buttons, kit = kit }
end

-- what V2's Store.LoadSlot makes of a slot file (legacy JSON, the V2.34 wrap)
local function loaded(name, data)
	writefile(Store.PlacePath .. "/" .. name, data)
	local base = name:match("^(.+)%.[^.]+$")
	-- (V2's JSON loader waits between batches: on a thread of its own, the mock stepped until it ends)
	local ok, frames
	local co = coroutine.create(function() ok, frames = Store.LoadSlot(base) end)
	coroutine.resume(co)
	local guard = 0
	while coroutine.status(co) ~= "dead" and guard < 10000 do M.step(1 / 60); guard = guard + 1 end
	delfile(Store.PlacePath .. "/" .. name)
	if not ok then return { error = tostring(frames) } end
	local arr = {}
	for i, f in ipairs(frames) do arr[i] = f end
	return { frames = arr, kitVersion = frames.KitVersion }
end

local rnd = Random.new(11)
local function r(n, d) return math.floor(n * d + 0.5) / d end

-- a V2 frame table with the fields `with` asks for
local function frame(i, with)
	local x, z = i * 0.071, -i * 0.043
	local f = {
		FrameTime = r(1 / 240 + (i % 3) * 0.001, 1e6),
		TotalTime = r(i / 240, 1e6),
		Cframe = { r(x, 1000), 3, r(z, 1000), 1, 0, 0, 0, 1, 0, 0, 0, 1 },
		Velocity = { Linear = { r(rnd:NextNumber() * 16, 1000), (i % 40 < 5) and 20 or 0, 0 }, Angular = { 0, (i % 9) * 0.5, 0 } },
		State = (i % 40 < 5) and 3 or 8,
		CamCframe = { r(x - 5, 1000), 6, r(z + 8, 1000), 1, 0, 0, 0, 0.966, 0.259, 0, -0.259, 0.966 },
		Zoom = (i % 60 < 30) and 12.5 or 8,
		ShiftLock = (i % 100 > 90) and 1 or 0,
		Anim = { Pose = (i % 40 < 5) and 3 or 2, JumpTime = (i % 40) / 100, Speed = 1.1,
			Anims = (i % 10 == 0) and { { 1, 0.5 }, { 4, 1 } } or {} },
		MX = 400 + i % 50, MY = 300 - i % 20,
	}
	if i % 7 == 0 then f.Input = { 26, -26, 87 } end
	if i % 33 == 0 then f.Input = { Codec.ScrollBase + 1, 32 } end
	if with.mobile and i % 11 == 0 then
		f.Mobile = { Jumping = 1, JoystickX = 12, JoystickY = -7,
			Dynamic = { Start = { 100, 200, 0.5 }, End = { 140, 230, 1 }, Middles = { { 110, 210, 0.7, 3, 4 } } } }
	end
	if with.v3 then
		f.VX, f.VY = 1920, 1009
		if i % 50 == 1 then f.Tools = { { Name = "Heal", Action = "Equip" }, { Name = "Heal", Action = "Activate" } } end
		if i == 200 then f.Died = true end
	end
	if with.co then
		f.CO = string.char(with.co, 1, 2, 3, i % 256)
	end
	if with.buttons and i % 25 == 0 then f.BT = { { 1, 1, 2.5 }, { 2, 0, 0 } } end
	if with.kit then
		if i % 30 == 0 then
			f.KE = { { 1, 3, i, 1.5, 2.5, 3.5, 0.1, 0.2, 0.3, 10, 0, -10, 4 }, { 2, i, 15 }, { 3, 2, 1 }, { 4, 7, 2 } }
		end
		f.SK = (i % 2 == 0) and 0.5 or nil
	end
	return f
end

local function run(n, with)
	local frames = {}
	for i = 1, n do frames[i] = frame(i, with) end
	return frames
end

local OBJECTS = { { id = 1, key = "Workspace.ClientParts.Spinner" }, { id = 2, key = "Workspace.ClientParts.Vanisher" } }
local BUTTONS = { { id = 1, key = "Workspace.Buttons.Red" }, { id = 2, key = "Workspace.Buttons.Blue" } }
local KIT = { version = 1, keys = { { id = 3, key = "Workspace.ClientParts.Turret" }, { id = 7, key = "Workspace.ClientParts.BouncePad" } } }

local files = {}
local function save(name, frames, objects, buttons, kit)
	local data, info = Codec.Encode(frames, nil, objects, buttons, kit)
	files[name] = data
	emit(name .. ".tas", data, decoded(data))
	M.realPrint("INFO " .. name .. " version " .. info.version .. " bytes " .. #data)
	return data
end

save("plain", run(300, {}))
save("mobile_v3", run(300, { mobile = true, v3 = true }))
save("objects", run(300, { co = 2 }), OBJECTS)
save("objbuttons", run(300, { co = 4, v3 = true, buttons = true }), OBJECTS, BUTTONS)
local kitData = save("kitspeed", run(400, { co = 5, v3 = true, buttons = true, kit = true, mobile = true }), OBJECTS, BUTTONS, KIT)

-- older versions from the v5 file: its first columns, the version byte, the body packed again
do
	local rd = { s = kitData, p = 7 }
	local function getVar()
		local v, mul = 0, 1
		while true do
			local b = string.byte(rd.s, rd.p)
			rd.p = rd.p + 1
			if b < 128 then return v + b * mul end
			v, mul = v + (b - 128) * mul, mul * 128
		end
	end
	local flags = string.byte(kitData, 6)
	local total = getVar()
	local rawLen = getVar()
	local headEnd = rd.p
	getVar(); getVar() -- (mouse start)
	local head = kitData:sub(7, rd.p - 1)
	local payload = kitData:sub(rd.p)
	local raw = (flags % 2 == 1) and M.LZ4.decompress(payload, rawLen) or payload
	-- the column boundaries
	local bounds, p = {}, 1
	local rr = { s = raw, p = 1 }
	while rr.p <= #raw do
		local v, mul = 0, 1
		while true do
			local b = string.byte(raw, rr.p)
			rr.p = rr.p + 1
			if b < 128 then v = v + b * mul break end
			v, mul = v + (b - 128) * mul, mul * 128
		end
		rr.p = rr.p + v
		bounds[#bounds + 1] = rr.p - 1
	end
	local function varint(n)
		local out = {}
		while n >= 128 do out[#out + 1] = string.char(n % 128 + 128); n = n // 128 end
		out[#out + 1] = string.char(n)
		return table.concat(out)
	end
	local _ = headEnd
	for _, v in ipairs({ { 1, 21 }, { 2, 23 }, { 3, 29 }, { 4, 29 } }) do
		local cut = raw:sub(1, bounds[v[2]])
		local packed = M.LZ4.compress(cut)
		-- (header: frames, rawLen, mouse start as in the v5 file)
		local restHead = head:sub(#varint(total) + #varint(rawLen) + 1)
		local data = "HTAS" .. string.char(v[1], 3) .. varint(total) .. varint(#cut) .. restHead .. packed
		emit("kitspeed_as_v" .. v[1] .. ".tas", data, decoded(data))
	end
end

-- the V2.34 wrap around a whole file, and a legacy JSON slot (batches layout)
do
	local inner = files.plain
	local n = #inner
	local wrapped = "\0LZ4\1" .. string.char(n % 256, (n // 256) % 256, (n // 65536) % 256, (n // 16777216) % 256) .. M.LZ4.compress(inner)
	emit("wrapped.tas", wrapped, loaded("wrapped.tas", wrapped))
	local packedFrames = {}
	for i = 1, 120 do
		local f = frame(i, {})
		packedFrames[i] = { f.Cframe, { f.Velocity.Linear, f.Velocity.Angular }, f.State, f.CamCframe, f.ShiftLock,
			(i % 10 == 0) and { 1, 5, -5 } or 0, { f.Anim.Pose, f.Anim.JumpTime, f.Anim.Speed, f.Anim.Anims }, f.Zoom,
			f.FrameTime, f.TotalTime }
	end
	local lines = { '{"batches":[' }
	for b = 0, 2 do
		local batch = {}
		for i = b * 40 + 1, b * 40 + 40 do batch[#batch + 1] = packedFrames[i] end
		lines[#lines + 1] = HttpService:JSONEncode(batch) .. ((b < 2) and "," or "")
	end
	lines[#lines + 1] = "]}"
	local json = table.concat(lines, "\n")
	emit("legacy.json", json, loaded("legacy.json", json))
	local single = HttpService:JSONEncode({ frames = { packedFrames[1], packedFrames[2] } })
	emit("legacy_single.json", single, loaded("legacy_single.json", single))
end
finish()
