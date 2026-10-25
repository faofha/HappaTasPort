-- ================================================================================================
--  CODEC6  (HappaTAS 3 persist): file format v6, the timeline's columns written directly.
--
--  "HTAS"  u8 6  u8 flags (bit 0: the body is LZ4)
--  varint headerLen, header (Value table: frames, length, created, saved, script, place, kit,
--      speedHack, name): readable without unpacking the body (the library only reads this)
--  varint rawLen, body (an LZ4 block of rawLen bytes, or the rawLen bytes as they are)
--  body = varint columnCount, per column: str name, u8 kind (1 f64, 2 u8, 3 list), u8 width,
--      varint byteLen, payload; then Value meta (the timeline's meta)
--    f64: per component, varint length + its values, lossless: a recorded value is rounded to 1/1000
--        (times to 1/1000000), so each is stored as the change of k = round(v x 1000) from the integer
--        before it (the previous value's own k when it was stored that way, else round(prev x 1000))
--        when k / 1000 gives v back bit for bit and |k| <= 2^47 (code = zigzag(change) x 4 + 0), the same
--        at 1000000 (+ 1), else the 8 bytes (code 2, then the f64: NaN, -0, unrounded values)
--    u8: the frames' bytes        list: varint entries, per entry varint frame step + Value
--  Columns are matched by name: one the timeline lacks is added (no V2 field) so it round-trips, one the
--  file lacks stays 0 / nil, another kind or width errors. "_filled" isn't saved (loaded frames are).
--  Encoding / decoding call progress(done, total) every 2000 frames and yield when they may.
-- ================================================================================================
local CONFIG = import("config")
local Bytes = import("persist/bytes")
local Value = import("persist/value")
local Lz4 = import("persist/lz4")

local Codec6 = {}

local VERSION = 6
local CHUNK = 2000
local MAX_COLUMNS = 512
local MAX_WIDTH = 64
local KIND = { f64 = 1, u8 = 2, list = 3 }
local KIND_NAME = { "f64", "u8", "list" }
local LIMIT = 2 ^ 47
local DELTA_LIMIT = 2 ^ 49

local function damaged(what) error("file is damaged: " .. what, 0) end

local function pace(progress, done, total)
	if progress then progress(done, total) end
	if coroutine.isyieldable() then task.wait() end
end

-- the integer the frame before stands for at this scale (both sides work it out the same way)
local function base(prev, scale)
	local k = prev * scale
	if k ~= k or k > LIMIT or k < -LIMIT then return 0 end
	return math.floor(k + 0.5)
end

-- one f64 component's frames lo..hi into its byte stream (st: ob, on, cap, prev, pmode, pk). The hot
-- loop of saving: bytes go straight into a buffer; an unchanged value is one byte.
local function encodeRange(st, buf, stride, off, lo, hi)
	local ob, on, cap = st.ob, st.on, st.cap
	local prev, pmode, pk = st.prev, st.pmode, st.pk
	for i = lo, hi do
		if on + 16 > cap then
			cap = cap * 2
			local nb = buffer.create(cap)
			buffer.copy(nb, 0, ob, 0, on)
			ob = nb
		end
		local v = buffer.readf64(buf, (i - 1) * stride + off)
		if v == prev and pmode == 0 and (v ~= 0 or 1 / v > 0) then
			buffer.writeu8(ob, on, 0)
			on = on + 1
		else
			local code = nil
			local k = math.floor(v * 1000 + 0.5)
			if k == k and k <= LIMIT and k >= -LIMIT and k / 1000 == v and (v ~= 0 or 1 / v > 0) then
				local d = k - ((pmode == 0) and pk or base(prev, 1000))
				if d < DELTA_LIMIT and d > -DELTA_LIMIT then
					code = ((d >= 0) and d * 2 or -d * 2 - 1) * 4
					pmode, pk = 0, k
				end
			end
			if not code then
				k = math.floor(v * 1000000 + 0.5)
				if k == k and k <= LIMIT and k >= -LIMIT and k / 1000000 == v and (v ~= 0 or 1 / v > 0) then
					local d = k - ((pmode == 1) and pk or base(prev, 1000000))
					if d < DELTA_LIMIT and d > -DELTA_LIMIT then
						code = ((d >= 0) and d * 2 or -d * 2 - 1) * 4 + 1
						pmode, pk = 1, k
					end
				end
			end
			if code then
				while code >= 128 do
					buffer.writeu8(ob, on, code % 128 + 128)
					on = on + 1
					code = code // 128
				end
				buffer.writeu8(ob, on, code)
				on = on + 1
			else
				buffer.writeu8(ob, on, 2)
				buffer.writef64(ob, on + 1, v)
				on = on + 9
				pmode = 2
			end
		end
		prev = v
	end
	st.ob, st.on, st.cap, st.prev, st.pmode, st.pk = ob, on, cap, prev, pmode, pk
end

-- frames lo..hi of one f64 component from its byte stream (c: p, last 0-based in rb, prev, pmode, pk)
local function decodeRange(c, rb, buf, stride, off, lo, hi)
	local p, last = c.p, c.last
	local prev, pmode, pk = c.prev, c.pmode, c.pk
	for i = lo, hi do
		if p > last then damaged("column ends early") end
		local b = buffer.readu8(rb, p)
		p = p + 1
		local code = b
		if b >= 128 then
			code = b - 128
			local mul = 128
			while true do
				if p > last then damaged("column ends inside a number") end
				b = buffer.readu8(rb, p)
				p = p + 1
				if b < 128 then
					code = code + b * mul
					break
				end
				code = code + (b - 128) * mul
				mul = mul * 128
				if mul > 2 ^ 56 then damaged("number too long") end
			end
		end
		local mode = code % 4
		local v
		if mode == 0 or mode == 1 then
			local z = (code - mode) / 4
			local d = (z % 2 == 0) and z / 2 or -(z + 1) / 2
			local scale = (mode == 0) and 1000 or 1000000
			local k = ((pmode == mode) and pk or base(prev, scale)) + d
			v = k / scale
			pmode, pk = mode, k
		elseif code == 2 then
			if p + 7 > last then damaged("column ends inside a number") end
			v = buffer.readf64(rb, p)
			p = p + 8
			pmode = 2
		else
			damaged("number code")
		end
		buffer.writef64(buf, (i - 1) * stride + off, v)
		prev = v
	end
	c.p, c.prev, c.pmode, c.pk = p, prev, pmode, pk
end

-- ------------------------------------------------------------------------------------------------ encode
function Codec6.encode(tl, header, progress)
	local n = tl:count()
	local cols = {}
	for _, col in ipairs(tl.order) do
		-- (a column marked save = false lives in memory only: lighting snapshots, the coyote state)
		if col.name ~= "_filled" and not (col.v2 and col.v2.save == false) then cols[#cols + 1] = col end
	end
	-- per f64 component a writer and the value before
	local state = {}
	for ci, col in ipairs(cols) do
		if col.kind == "f64" then
			local comps = {}
			for k = 1, col.width do
				comps[k] = { ob = buffer.create(n + 64), on = 0, cap = n + 64, prev = 0, pmode = -1, pk = 0 }
			end
			state[ci] = comps
		elseif col.kind == "list" then
			state[ci] = { writer = Bytes.writer(), count = 0, last = 0 }
		end
	end
	local lo = 1
	while lo <= n do
		local hi = math.min(n, lo + CHUNK - 1)
		for ci, col in ipairs(cols) do
			local st = state[ci]
			if col.kind == "f64" then
				for k = 1, col.width do encodeRange(st[k], col.buf, col.stride, (k - 1) * 8, lo, hi) end
			elseif col.kind == "list" then
				local list, w = col.list, st.writer
				for i = lo, hi do
					local v = list[i]
					if v ~= nil then
						w:varint(i - st.last)
						Value.write(w, v)
						st.last = i
						st.count = st.count + 1
					end
				end
			end
		end
		pace(progress, hi, n)
		lo = hi + 1
	end
	local body = Bytes.writer(n * 8 + 256)
	body:varint(#cols)
	for ci, col in ipairs(cols) do
		body:str(col.name)
		body:u8(KIND[col.kind])
		body:u8(col.width)
		local st = state[ci]
		if col.kind == "f64" then
			local p = Bytes.writer()
			for k = 1, col.width do
				p:varint(st[k].on)
				p:rawBuffer(st[k].ob, 0, st[k].on)
			end
			body:varint(p:len())
			body:raw(p:tostring())
		elseif col.kind == "u8" then
			body:varint(n)
			body:rawBuffer(col.buf, 0, n)
		else
			local p = Bytes.writer()
			p:varint(st.count)
			p:raw(st.writer:tostring())
			body:varint(p:len())
			body:raw(p:tostring())
		end
	end
	Value.write(body, tl.meta or {})
	local raw = body:tostring()
	local packed = Lz4.compress(raw)
	local hdr = table.clone(header or {})
	hdr.frames = n
	local hw = Bytes.writer()
	Value.write(hw, hdr)
	local out = Bytes.writer(#(packed or raw) + hw:len() + 32)
	out:raw("HTAS")
	out:u8(VERSION)
	out:u8(packed and 1 or 0)
	out:varint(hw:len())
	out:raw(hw:tostring())
	out:varint(#raw)
	out:raw(packed or raw)
	return out:tostring()
end

-- ------------------------------------------------------------------------------------------------ decode
-- the header and a reader at the body (errors on anything else)
local function prefix(data)
	if type(data) ~= "string" then error("not a HappaTAS file", 0) end
	if #data > CONFIG.MaxFileBytes then error("the file is too big", 0) end
	local r = Bytes.reader(data)
	if #data < 6 or r:raw(4) ~= "HTAS" then error("not a HappaTAS file", 0) end
	local version = r:u8()
	if version ~= VERSION then error("unsupported file version " .. tostring(version), 0) end
	local flags = r:u8()
	local hl = r:varint()
	if hl > r:left() then damaged("header longer than the file") end
	local hr = Bytes.reader(data, r:pos(), r:pos() + hl - 1)
	local header = Value.read(hr)
	if hr:left() ~= 0 or type(header) ~= "table" then damaged("header") end
	r:raw(hl)
	return header, flags, r
end

-- the header without unpacking the body; nil and a message when it isn't a readable v6 file
function Codec6.readHeader(data)
	local ok, header = pcall(prefix, data)
	if ok then return header end
	return nil, tostring(header)
end

-- replaces tl's frames (and meta) with the file's; returns the header
function Codec6.decode(data, tl, progress)
	local header, flags, r = prefix(data)
	local n = header.frames
	if type(n) ~= "number" or n ~= math.floor(n) or n < 0 or n > CONFIG.MaxFrames then damaged("frame count") end
	local rawLen = r:varint()
	if rawLen > CONFIG.MaxFileBytes then error("the file is too big", 0) end
	local rest = string.sub(data, r:pos())
	local raw
	if flags % 2 == 1 then
		raw = Lz4.decompress(rest, rawLen)
	else
		if #rest ~= rawLen then damaged("size") end
		raw = rest
	end
	local br = Bytes.reader(raw)
	local count = br:varint()
	if count > MAX_COLUMNS then damaged("too many columns") end
	local descs = {}
	for _ = 1, count do
		local name = br:str()
		local kind = KIND_NAME[br:u8()]
		local width = br:u8()
		local len = br:varint()
		if not kind or name == "" or name == "_filled" then damaged("column " .. name) end
		if width < 1 or width > MAX_WIDTH or (kind ~= "f64" and width ~= 1) then damaged("column width") end
		if kind == "u8" and len ~= n then damaged("column " .. name .. " size") end
		local start = br:pos()
		br:raw(len)
		descs[#descs + 1] = { name = name, kind = kind, width = width, start = start, last = start + len - 1 }
	end
	local meta = Value.read(br)
	if br:left() ~= 0 then damaged("bytes after the end") end
	for _, d in ipairs(descs) do
		local col = tl.cols[d.name]
		if not col then
			tl:addColumn(d.name, d.kind, d.width, nil)
		elseif col.kind ~= d.kind or col.width ~= d.width then
			error("column " .. d.name .. " has a different shape", 0)
		end
	end
	tl:resize(n)
	-- f64 components and lists: readers, decoded in steps of CHUNK frames
	local work = {}
	local rb = buffer.fromstring(raw)
	for _, d in ipairs(descs) do
		local col = tl.cols[d.name]
		local pr = Bytes.reader(raw, d.start, d.last)
		if d.kind == "f64" then
			local comps = {}
			for k = 1, d.width do
				local len = pr:varint()
				if len > pr:left() then damaged("column " .. d.name) end
				-- (0-based positions in rb)
				comps[k] = { p = pr:pos() - 1, last = pr:pos() + len - 2, prev = 0, pmode = -1, pk = 0 }
				pr:raw(len)
			end
			if pr:left() ~= 0 then damaged("column " .. d.name) end
			work[#work + 1] = { col = col, comps = comps }
		elseif d.kind == "u8" then
			buffer.writestring(col.buf, 0, string.sub(raw, d.start, d.last))
		else
			local entries = pr:varint()
			local frame = 0
			for _ = 1, entries do
				frame = frame + pr:varint()
				if frame < 1 or frame > n then damaged("list frame") end
				col.list[frame] = Value.read(pr)
			end
			if pr:left() ~= 0 then damaged("column " .. d.name) end
		end
	end
	local lo = 1
	while lo <= n do
		local hi = math.min(n, lo + CHUNK - 1)
		for _, wk in ipairs(work) do
			for k, c in ipairs(wk.comps) do decodeRange(c, rb, wk.col.buf, wk.col.stride, (k - 1) * 8, lo, hi) end
		end
		pace(progress, hi, n)
		lo = hi + 1
	end
	for _, wk in ipairs(work) do
		for _, c in ipairs(wk.comps) do
			if c.p ~= c.last + 1 then damaged("column " .. wk.col.name) end
		end
	end
	tl.meta = type(meta) == "table" and meta or {}
	return header
end

return Codec6
