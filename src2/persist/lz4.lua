-- ================================================================================================
--  LZ4  (HappaTAS 3 persist): LZ4 blocks through the executor's lz4compress / lz4decompress. Without
--  lz4compress a file is saved uncompressed; without lz4decompress (or when it fails) a block is read by
--  a Lua decoder (V2.38.16's lz4Fallback, p07_codec.lua:123-162, writing into a buffer). A block that
--  doesn't give exactly the expected size is a damaged file.
-- ================================================================================================
local Env = import("platform/env")

local Lz4 = {}

local function damaged(what) error("file is damaged: " .. what, 0) end

-- a compressed block, or nil (no lz4compress, or it failed)
function Lz4.compress(s)
	if not Env.lz4compress then return nil end
	local ok, c = pcall(Env.lz4compress, s)
	if ok and type(c) == "string" then return c end
	return nil
end

-- the pure Lua block decoder
function Lz4.fallback(src, usize)
	local out = buffer.create(usize)
	local on = 0
	local i, n = 1, #src
	local byte = string.byte
	while i <= n do
		local token = byte(src, i)
		i = i + 1
		local lit = token // 16
		if lit == 15 then
			repeat
				local b = byte(src, i)
				i = i + 1
				if not b then damaged("bad literal length") end
				lit = lit + b
			until b ~= 255
		end
		if i + lit - 1 > n or on + lit > usize then damaged("literals out of range") end
		if lit > 0 then
			buffer.writestring(out, on, string.sub(src, i, i + lit - 1))
			on = on + lit
			i = i + lit
		end
		if i > n then break end
		local b1, b2 = byte(src, i, i + 1)
		if not b2 then damaged("bad offset") end
		local off = b1 + b2 * 256
		i = i + 2
		if off == 0 or off > on then damaged("bad offset") end
		local ml = token % 16
		if ml == 15 then
			repeat
				local b = byte(src, i)
				i = i + 1
				if not b then damaged("bad match length") end
				ml = ml + b
			until b ~= 255
		end
		ml = ml + 4
		if on + ml > usize then damaged("output too big") end
		local start = on - off
		if off >= ml then
			buffer.copy(out, on, out, start, ml)
		else
			for k = 0, ml - 1 do buffer.writeu8(out, on + k, buffer.readu8(out, start + k)) end
		end
		on = on + ml
		if on % 65536 < ml and coroutine.isyieldable() then task.wait() end
	end
	if on ~= usize then damaged("size") end
	return buffer.tostring(out)
end

-- the block's `size` bytes (the executor's decoder first)
function Lz4.decompress(s, size)
	if Env.lz4decompress then
		local ok, res = pcall(Env.lz4decompress, s, size)
		if ok and type(res) == "string" and #res == size then return res end
	end
	return Lz4.fallback(s, size)
end

return Lz4
