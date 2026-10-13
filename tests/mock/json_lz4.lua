-- ================================================================================================
-- Headless Roblox mock: JSON (HttpService) and LZ4 block format (executor lz4compress/lz4decompress)
-- ================================================================================================
do
	local JSON = {}
	local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
	local function encStr(s)
		return '"' .. s:gsub('[%c"\\]', function(c)
			return escapes[c] or string.format("\\u%04x", c:byte())
		end) .. '"'
	end
	local function isArray(t)
		local n = 0
		for k in pairs(t) do
			if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
			n = n + 1
		end
		for i = 1, n do if t[i] == nil then return false end end
		return true, n
	end
	local function enc(v, out, seen)
		local t = type(v)
		if v == nil then out[#out + 1] = "null"
		elseif t == "boolean" then out[#out + 1] = v and "true" or "false"
		elseif t == "number" then
			if v ~= v or v == math.huge or v == -math.huge then error("JSONEncode: cannot encode " .. tostring(v)) end
			if v % 1 == 0 and math.abs(v) < 1e15 then out[#out + 1] = string.format("%d", v)
			else out[#out + 1] = string.format("%.17g", v) end
		elseif t == "string" then out[#out + 1] = encStr(v)
		elseif t == "table" then
			if seen[v] then error("JSONEncode: cycle") end
			seen[v] = true
			local arr, n = isArray(v)
			if arr and n > 0 then
				out[#out + 1] = "["
				for i = 1, n do
					if i > 1 then out[#out + 1] = "," end
					enc(v[i], out, seen)
				end
				out[#out + 1] = "]"
			else
				out[#out + 1] = "{"
				local first = true
				local keys = {}
				for k in pairs(v) do keys[#keys + 1] = k end
				table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
				for _, k in ipairs(keys) do
					if not first then out[#out + 1] = "," end
					first = false
					out[#out + 1] = encStr(tostring(k))
					out[#out + 1] = ":"
					enc(v[k], out, seen)
				end
				out[#out + 1] = "}"
			end
			seen[v] = nil
		else
			error("JSONEncode: unsupported type " .. t)
		end
	end
	function JSON.encode(v)
		local out = {}
		enc(v, out, {})
		return table.concat(out)
	end
	function JSON.decode(s)
		local pos = 1
		local function ws() pos = s:find("[^ \t\r\n]", pos) or (#s + 1) end
		local val
		local function str()
			pos = pos + 1
			local buf = {}
			while true do
				local c = s:sub(pos, pos)
				if c == "" then error("JSONDecode: unterminated string") end
				if c == '"' then pos = pos + 1; break end
				if c == "\\" then
					local e = s:sub(pos + 1, pos + 1)
					local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
					if e == "u" then
						buf[#buf + 1] = utf8.char(tonumber(s:sub(pos + 2, pos + 5), 16))
						pos = pos + 6
					else
						buf[#buf + 1] = map[e] or e
						pos = pos + 2
					end
				else
					buf[#buf + 1] = c
					pos = pos + 1
				end
			end
			return table.concat(buf)
		end
		function val()
			ws()
			local c = s:sub(pos, pos)
			if c == "{" then
				pos = pos + 1
				local t = {}
				ws()
				if s:sub(pos, pos) == "}" then pos = pos + 1; return t end
				while true do
					ws()
					local k = str()
					ws()
					if s:sub(pos, pos) ~= ":" then error("JSONDecode: expected :") end
					pos = pos + 1
					t[k] = val()
					ws()
					local d = s:sub(pos, pos)
					pos = pos + 1
					if d == "}" then break end
					if d ~= "," then error("JSONDecode: expected ,") end
				end
				return t
			elseif c == "[" then
				pos = pos + 1
				local t = {}
				ws()
				if s:sub(pos, pos) == "]" then pos = pos + 1; return t end
				while true do
					t[#t + 1] = val()
					ws()
					local d = s:sub(pos, pos)
					pos = pos + 1
					if d == "]" then break end
					if d ~= "," then error("JSONDecode: expected , in array") end
				end
				return t
			elseif c == '"' then
				return str()
			elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
			elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
			elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
			else
				local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
				if not num or num == "" then error("JSONDecode: bad value at " .. pos) end
				pos = pos + #num
				return tonumber(num)
			end
		end
		local ok, r = pcall(val)
		if not ok then error("Can't parse JSON", 2) end
		return r
	end
	M.JSON = JSON
end

do
	-- LZ4 block format (no frame header), the format executors return from lz4compress
	local LZ4 = {}
	local byte, char, concat = string.byte, string.char, table.concat
	function LZ4.compress(src)
		local n = #src
		local out = {}
		local function putLen(len)
			while len >= 255 do out[#out + 1] = char(255); len = len - 255 end
			out[#out + 1] = char(len)
		end
		local hash = {}
		local anchor, i = 1, 1
		local limit = n - 12 -- last 12 bytes are literals (LZ4 end-of-block rules)
		while i <= limit do
			local key = src:sub(i, i + 3)
			local ref = hash[key]
			hash[key] = i
			if ref and i - ref <= 65535 and i - ref > 0 then
				-- extend the match (must stop 5 bytes before the end)
				local mlen = 4
				while i + mlen <= n - 5 and byte(src, ref + mlen) == byte(src, i + mlen) do mlen = mlen + 1 end
				local lit = i - anchor
				local token = (math.min(lit, 15) * 16) + math.min(mlen - 4, 15)
				out[#out + 1] = char(token)
				if lit >= 15 then putLen(lit - 15) end
				out[#out + 1] = src:sub(anchor, i - 1)
				local off = i - ref
				out[#out + 1] = char(off % 256, math.floor(off / 256))
				if mlen - 4 >= 15 then putLen(mlen - 4 - 15) end
				i = i + mlen
				anchor = i
			else
				i = i + 1
			end
		end
		local lit = n - anchor + 1
		out[#out + 1] = char(math.min(lit, 15) * 16)
		if lit >= 15 then putLen(lit - 15) end
		out[#out + 1] = src:sub(anchor)
		return concat(out)
	end
	function LZ4.decompress(src, size)
		local out = {}
		local olen = 0
		local buf = {} -- byte buffer for back references
		local i, n = 1, #src
		while i <= n do
			local token = byte(src, i); i = i + 1
			local lit = math.floor(token / 16)
			if lit == 15 then
				repeat local b = byte(src, i); i = i + 1; lit = lit + b until b ~= 255
			end
			for j = 0, lit - 1 do
				olen = olen + 1
				buf[olen] = byte(src, i + j)
			end
			i = i + lit
			if i > n then break end
			local off = byte(src, i) + byte(src, i + 1) * 256
			i = i + 2
			local mlen = token % 16
			if mlen == 15 then
				repeat local b = byte(src, i); i = i + 1; mlen = mlen + b until b ~= 255
			end
			mlen = mlen + 4
			if off == 0 or off > olen then error("lz4: bad offset") end
			local from = olen - off
			for j = 1, mlen do
				olen = olen + 1
				buf[olen] = buf[from + j]
			end
		end
		for k = 1, olen, 4096 do
			out[#out + 1] = char(table.unpack(buf, k, math.min(olen, k + 4095)))
		end
		local s = concat(out)
		if size and #s ~= size then
			-- executors are given the size; a mismatch would mean corruption
			error("lz4: size mismatch " .. #s .. " vs " .. tostring(size))
		end
		return s
	end
	M.LZ4 = LZ4
end
