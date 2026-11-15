-- ================================================================================================
--  DEFLATE  (HappaTAS 3 persist): raw DEFLATE streams (RFC 1951) in pure Luau, for .tas bodies. The
--  executor only offers LZ4; deflate's Huffman stage makes a TAS about a third smaller than LZ4 does.
--  compress: greedy LZ77 over a 32 KiB window (hash chains, at most MAX_CHAIN tries), one dynamic Huffman
--  block per BLOCK tokens (code lengths limited to 15 / 7, always complete codes).
--  decompress: stored, fixed and dynamic blocks, into a buffer of the expected size; anything that doesn't
--  give exactly that size is a damaged file. Both yield every 64 KiB when they may.
-- ================================================================================================
local Deflate = {}

local band, bor, bxor, lshift, rshift = bit32.band, bit32.bor, bit32.bxor, bit32.lshift, bit32.rshift
local readu8, writeu8 = buffer.readu8, buffer.writeu8
local readi32, writei32 = buffer.readi32, buffer.writei32

local MAX_CHAIN = 24 -- hash chain tries per position
local NICE = 64 -- a match this long is taken at once
local BLOCK = 32768 -- tokens per Huffman block
local YIELD = 65536 -- bytes between yields

local LEN_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEN_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DIST_BASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
	4097, 6145, 8193, 12289, 16385, 24577 }
local DIST_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CL_ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

local function damaged(what) error("file is damaged: " .. what, 0) end

local function pace()
	if coroutine.isyieldable() then task.wait() end
end

-- length 3..258 -> its code (1..29); distance 1..32768 -> its code (1..30) (built on first use)
local lenIdx, distIdx = nil, nil
local function lookups()
	if lenIdx then return end
	lenIdx, distIdx = {}, buffer.create(32769)
	for i = 1, 29 do
		local hi = (i < 29) and (LEN_BASE[i + 1] - 1) or 258
		for l = LEN_BASE[i], hi do lenIdx[l] = i end
	end
	for i = 1, 30 do
		local hi = (i < 30) and (DIST_BASE[i + 1] - 1) or 32768
		for d = DIST_BASE[i], hi do writeu8(distIdx, d, i) end
	end
end

local function reverse(c, l)
	local r = 0
	for _ = 1, l do
		r = r * 2 + c % 2
		c = c // 2
	end
	return r
end

-- Huffman code lengths (1-based symbols) for the frequencies, at most `limit` bits, always a complete code
local function buildLengths(freq, nsym, limit)
	local lens = table.create(nsym, 0)
	local syms = {}
	for s = 1, nsym do
		if freq[s] > 0 then syms[#syms + 1] = s end
	end
	local m = #syms
	if m == 0 then return lens end
	if m == 1 then
		lens[syms[1]] = 1
		lens[(syms[1] == 1) and 2 or 1] = 1 -- (a second code of length 1 keeps the code complete)
		return lens
	end
	table.sort(syms, function(a, b)
		if freq[a] ~= freq[b] then return freq[a] < freq[b] end
		return a < b
	end)
	-- two queues: the sorted leaves 1..m and the inner nodes in the order they are made
	local wt, parent = {}, {}
	for i = 1, m do wt[i] = freq[syms[i]] end
	local li, ii, nextNode = 1, m + 1, m + 1
	local function pick()
		if li <= m and (ii >= nextNode or wt[li] <= wt[ii]) then
			li = li + 1
			return li - 1
		end
		ii = ii + 1
		return ii - 1
	end
	for _ = 1, m - 1 do
		local a = pick()
		local b = pick()
		wt[nextNode] = wt[a] + wt[b]
		parent[a], parent[b] = nextNode, nextNode
		nextNode = nextNode + 1
	end
	local root = nextNode - 1
	local depth = { [root] = 0 }
	for k = root - 1, m + 1, -1 do depth[k] = depth[parent[k]] + 1 end
	local maxl = 0
	for i = 1, m do
		local d = depth[parent[i]] + 1
		lens[syms[i]] = d
		if d > maxl then maxl = d end
	end
	if maxl <= limit then return lens end
	-- too long: cut to the limit, then lengthen the rarest short codes until the code fits, then shorten the
	-- longest codes while there is room (the code ends complete: every step is a multiple of the smallest one)
	local cap = 2 ^ limit
	local K = 0
	for i = 1, m do
		local s = syms[i]
		if lens[s] > limit then lens[s] = limit end
		K = K + 2 ^ (limit - lens[s])
	end
	while K > cap do
		local best = nil
		for i = 1, m do
			local s = syms[i]
			if lens[s] < limit and (best == nil or lens[s] > lens[best]) then best = s end
		end
		K = K - 2 ^ (limit - lens[best] - 1)
		lens[best] = lens[best] + 1
	end
	while K < cap do
		local best = nil
		for i = m, 1, -1 do
			local s = syms[i]
			if lens[s] > 1 and K + 2 ^ (limit - lens[s]) <= cap and (best == nil or lens[s] > lens[best]) then best = s end
		end
		if not best then break end
		K = K + 2 ^ (limit - lens[best])
		lens[best] = lens[best] - 1
	end
	return lens
end

-- canonical codes for the lengths, bit-reversed (deflate sends Huffman codes from their top bit)
local function buildCodes(lens, nsym)
	local count = table.create(16, 0)
	for s = 1, nsym do
		local l = lens[s]
		if l > 0 then count[l] = count[l] + 1 end
	end
	local nextCode, code, prev = {}, 0, 0
	for bits = 1, 15 do
		code = (code + prev) * 2
		nextCode[bits] = code
		prev = count[bits]
	end
	local out = table.create(nsym, 0)
	for s = 1, nsym do
		local l = lens[s]
		if l > 0 then
			out[s] = reverse(nextCode[l], l)
			nextCode[l] = nextCode[l] + 1
		end
	end
	return out
end

-- ------------------------------------------------------------------------------------------------ compress
-- the raw deflate stream of the string s
function Deflate.compress(s)
	lookups()
	local n = #s
	local b = buffer.fromstring(s)
	local cap = math.max(64, n // 2)
	local ob, on, acc, nb = buffer.create(cap), 0, 0, 0
	local function putbits(v, k)
		acc = bor(acc, lshift(v, nb))
		nb = nb + k
		while nb >= 8 do
			if on >= cap then
				cap = cap * 2
				local nb2 = buffer.create(cap)
				buffer.copy(nb2, 0, ob, 0, on)
				ob = nb2
			end
			writeu8(ob, on, band(acc, 255))
			on = on + 1
			acc = rshift(acc, 8)
			nb = nb - 8
		end
	end
	local tl, tv = table.create(BLOCK, 0), table.create(BLOCK, 0) -- per token: match length (0 = literal), byte or distance
	local ntok = 0

	local function writeBlock(final)
		local lf, df = table.create(286, 0), table.create(30, 0)
		for i = 1, ntok do
			local L = tl[i]
			if L == 0 then
				local x = tv[i] + 1
				lf[x] = lf[x] + 1
			else
				local x = 257 + lenIdx[L]
				lf[x] = lf[x] + 1
				local d = readu8(distIdx, tv[i])
				df[d] = df[d] + 1
			end
		end
		lf[257] = 1 -- end of block
		local llen = buildLengths(lf, 286, 15)
		local dlen = buildLengths(df, 30, 15)
		local nlit, ndist = 257, 1
		for s = 286, 258, -1 do
			if llen[s] > 0 then
				nlit = s
				break
			end
		end
		local anyDist = false
		for s = 30, 1, -1 do
			if dlen[s] > 0 then
				ndist = s
				anyDist = true
				break
			end
		end
		if not anyDist then
			dlen[1], dlen[2], ndist = 1, 1, 2 -- (no matches: a complete two-code distance set)
		end
		-- the code lengths, run-length coded (16 repeats the last length 3-6 times, 17 / 18 zeros 3-10 / 11-138)
		local all = {}
		for s = 1, nlit do all[#all + 1] = llen[s] end
		for s = 1, ndist do all[#all + 1] = dlen[s] end
		local seq, sx = {}, {}
		local function emit(sym, extra)
			seq[#seq + 1] = sym
			sx[#sx + 1] = extra or 0
		end
		local i, total = 1, #all
		while i <= total do
			local l = all[i]
			local run = 1
			while i + run <= total and all[i + run] == l do run = run + 1 end
			local r = run
			if l == 0 then
				while r >= 11 do
					local k = math.min(r, 138)
					emit(18, k - 11)
					r = r - k
				end
				if r >= 3 then
					emit(17, r - 3)
					r = 0
				end
				for _ = 1, r do emit(0) end
			else
				emit(l)
				r = r - 1
				while r >= 3 do
					local k = math.min(r, 6)
					emit(16, k - 3)
					r = r - k
				end
				for _ = 1, r do emit(l) end
			end
			i = i + run
		end
		local cf = table.create(19, 0)
		for k = 1, #seq do cf[seq[k] + 1] = cf[seq[k] + 1] + 1 end
		local clen = buildLengths(cf, 19, 7)
		local ccode = buildCodes(clen, 19)
		local nclen = 4
		for k = 19, 4, -1 do
			if clen[CL_ORDER[k] + 1] > 0 then
				nclen = k
				break
			end
		end
		putbits(final and 1 or 0, 1)
		putbits(2, 2) -- dynamic Huffman
		putbits(nlit - 257, 5)
		putbits(ndist - 1, 5)
		putbits(nclen - 4, 4)
		for k = 1, nclen do putbits(clen[CL_ORDER[k] + 1], 3) end
		for k = 1, #seq do
			local sym = seq[k] + 1
			putbits(ccode[sym], clen[sym])
			if sym == 17 then
				putbits(sx[k], 2)
			elseif sym == 18 then
				putbits(sx[k], 3)
			elseif sym == 19 then
				putbits(sx[k], 7)
			end
		end
		local lcode, dcode = buildCodes(llen, 286), buildCodes(dlen, 30)
		for t = 1, ntok do
			local L = tl[t]
			if L == 0 then
				local x = tv[t] + 1
				putbits(lcode[x], llen[x])
			else
				local li = lenIdx[L]
				local x = 257 + li
				putbits(lcode[x], llen[x])
				local e = LEN_EXTRA[li]
				if e > 0 then putbits(L - LEN_BASE[li], e) end
				local d = tv[t]
				local di = readu8(distIdx, d)
				putbits(dcode[di], dlen[di])
				e = DIST_EXTRA[di]
				if e > 0 then putbits(d - DIST_BASE[di], e) end
			end
		end
		putbits(lcode[257], llen[257])
		ntok = 0
	end

	-- LZ77: head[hash] = the latest position + 1, prev[pos % 32768] = the one before it with that hash
	local head, prev = buffer.create(65536 * 4), buffer.create(32768 * 4)
	local function insert(p)
		local k = readu8(b, p) * 65536 + readu8(b, p + 1) * 256 + readu8(b, p + 2)
		local h = band(k * 40503 // 64, 0xFFFF) * 4
		writei32(prev, band(p, 32767) * 4, readi32(head, h))
		writei32(head, h, p + 1)
	end
	local pos, nextYield = 0, YIELD
	while pos < n do
		local bestLen, bestDist = 0, 0
		if pos + 2 < n then
			local k = readu8(b, pos) * 65536 + readu8(b, pos + 1) * 256 + readu8(b, pos + 2)
			local h = band(k * 40503 // 64, 0xFFFF) * 4
			local cand = readi32(head, h)
			writei32(prev, band(pos, 32767) * 4, cand)
			writei32(head, h, pos + 1)
			local maxLen = n - pos
			if maxLen > 258 then maxLen = 258 end
			local chain = MAX_CHAIN
			while cand > 0 and chain > 0 do
				local c = cand - 1
				local dist = pos - c
				if dist > 32768 then break end
				if readu8(b, c + bestLen) == readu8(b, pos + bestLen) then
					local l = 0
					while l < maxLen and readu8(b, c + l) == readu8(b, pos + l) do l = l + 1 end
					if l > bestLen then
						bestLen, bestDist = l, dist
						if l >= NICE or l >= maxLen then break end
					end
				end
				cand = readi32(prev, band(c, 32767) * 4)
				chain = chain - 1
			end
		end
		ntok = ntok + 1
		if bestLen >= 3 then
			tl[ntok], tv[ntok] = bestLen, bestDist
			local stop = pos + bestLen
			local last = math.min(stop, n - 2) - 1
			for p = pos + 1, last do insert(p) end
			pos = stop
		else
			tl[ntok], tv[ntok] = 0, readu8(b, pos)
			pos = pos + 1
		end
		if ntok >= BLOCK then writeBlock(false) end
		if pos >= nextYield then
			nextYield = pos + YIELD
			pace()
		end
	end
	writeBlock(true)
	if nb > 0 then putbits(0, 8 - nb) end
	return buffer.readstring(ob, 0, on)
end

-- ------------------------------------------------------------------------------------------------ decompress
-- a decoding table for the lengths: entry = (symbol - 1) x 16 + length at every index whose low bits are the
-- symbol's (reversed) code; 0 = no code there
local function decodeTable(lens, nsym)
	local maxl = 0
	for s = 1, nsym do
		if lens[s] > maxl then maxl = lens[s] end
	end
	if maxl == 0 then return nil, 0 end
	local codes = buildCodes(lens, nsym)
	local size = 2 ^ maxl
	local tbl = table.create(size, 0)
	for s = 1, nsym do
		local l = lens[s]
		if l > 0 then
			local entry = (s - 1) * 16 + l
			for i = codes[s], size - 1, 2 ^ l do tbl[i + 1] = entry end
		end
	end
	return tbl, maxl
end

local fixedL, fixedLMax, fixedD, fixedDMax = nil, 0, nil, 0

-- the `size` bytes of the raw deflate stream s
function Deflate.decompress(s, size)
	local src = buffer.fromstring(s)
	local n = #s
	local out = buffer.create(size)
	local on, pos, acc, nb = 0, 0, 0, 0
	local nextYield = YIELD
	local function bits(k)
		while nb < k do
			if pos >= n then damaged("deflate stream ends early") end
			acc = bor(acc, lshift(readu8(src, pos), nb))
			pos = pos + 1
			nb = nb + 8
		end
		local v = band(acc, lshift(1, k) - 1)
		acc = rshift(acc, k)
		nb = nb - k
		return v
	end
	local function decodeSym(tbl, maxl)
		while nb < maxl and pos < n do
			acc = bor(acc, lshift(readu8(src, pos), nb))
			pos = pos + 1
			nb = nb + 8
		end
		local e = tbl[band(acc, lshift(1, maxl) - 1) + 1]
		local l = e % 16
		if l == 0 or l > nb then damaged("bad deflate code") end
		acc = rshift(acc, l)
		nb = nb - l
		return e // 16
	end
	repeat
		local final = bits(1)
		local typ = bits(2)
		if typ == 0 then
			local drop = nb % 8
			acc = rshift(acc, drop)
			nb = nb - drop
			local len = bits(16)
			local nlen = bits(16)
			if band(bxor(len, nlen), 0xFFFF) ~= 0xFFFF then damaged("stored block length") end
			if on + len > size then damaged("output too big") end
			while len > 0 and nb >= 8 do
				writeu8(out, on, bits(8))
				on = on + 1
				len = len - 1
			end
			if pos + len > n then damaged("deflate stream ends early") end
			buffer.copy(out, on, src, pos, len)
			on = on + len
			pos = pos + len
		elseif typ == 1 or typ == 2 then
			local ltbl, lmax, dtbl, dmax
			if typ == 1 then
				if not fixedL then
					local ll = table.create(288, 0)
					for sym = 1, 288 do
						ll[sym] = (sym <= 144) and 8 or (sym <= 256) and 9 or (sym <= 280) and 7 or 8
					end
					fixedL, fixedLMax = decodeTable(ll, 288)
					fixedD, fixedDMax = decodeTable(table.create(30, 5), 30)
				end
				ltbl, lmax, dtbl, dmax = fixedL, fixedLMax, fixedD, fixedDMax
			else
				local nlit = bits(5) + 257
				local ndist = bits(5) + 1
				local nclen = bits(4) + 4
				if nlit > 286 or ndist > 30 then damaged("deflate code counts") end
				local clen = table.create(19, 0)
				for k = 1, nclen do clen[CL_ORDER[k] + 1] = bits(3) end
				local ctbl, cmax = decodeTable(clen, 19)
				if not ctbl then damaged("no code length codes") end
				local all = table.create(nlit + ndist, 0)
				local i = 1
				while i <= nlit + ndist do
					local sym = decodeSym(ctbl, cmax)
					if sym < 16 then
						all[i] = sym
						i = i + 1
					else
						local val, rep = 0, 0
						if sym == 16 then
							if i == 1 then damaged("repeat with nothing before") end
							val, rep = all[i - 1], 3 + bits(2)
						elseif sym == 17 then
							rep = 3 + bits(3)
						else
							rep = 11 + bits(7)
						end
						if i + rep - 1 > nlit + ndist then damaged("code lengths overflow") end
						for _ = 1, rep do
							all[i] = val
							i = i + 1
						end
					end
				end
				local ll, dl = table.create(nlit, 0), table.create(ndist, 0)
				for k = 1, nlit do ll[k] = all[k] end
				for k = 1, ndist do dl[k] = all[nlit + k] end
				if ll[257] == 0 then damaged("no end of block code") end
				ltbl, lmax = decodeTable(ll, nlit)
				dtbl, dmax = decodeTable(dl, ndist)
			end
			while true do
				local sym = decodeSym(ltbl, lmax)
				if sym < 256 then
					if on >= size then damaged("output too big") end
					writeu8(out, on, sym)
					on = on + 1
				elseif sym == 256 then
					break
				else
					local li = sym - 256
					if li > 29 then damaged("bad length code") end
					local L = LEN_BASE[li]
					local e = LEN_EXTRA[li]
					if e > 0 then L = L + bits(e) end
					if not dtbl then damaged("no distance codes") end
					local di = decodeSym(dtbl, dmax) + 1
					if di > 30 then damaged("bad distance code") end
					local d = DIST_BASE[di]
					e = DIST_EXTRA[di]
					if e > 0 then d = d + bits(e) end
					if d > on then damaged("distance too far back") end
					if on + L > size then damaged("output too big") end
					local start = on - d
					if d >= L then
						buffer.copy(out, on, out, start, L)
					else
						for k = 0, L - 1 do writeu8(out, on + k, readu8(out, start + k)) end
					end
					on = on + L
				end
				if on >= nextYield then
					nextYield = on + YIELD
					pace()
				end
			end
		else
			damaged("deflate block type")
		end
	until final == 1
	if on ~= size then damaged("size") end
	-- (whole bytes read ahead into the bit buffer are not used: nothing may follow the stream)
	if pos - nb // 8 ~= n then damaged("bytes after the end") end
	return buffer.tostring(out)
end

return Deflate
