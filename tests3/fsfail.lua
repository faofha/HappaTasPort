-- ================================================================================================
-- HappaTAS 3 tests: file failures on demand (prepended with PRE before the script boots, so the
-- script's own file functions are these wrappers around the mock's)
--   FSFAIL.write = pattern   a write to a matching path errors
--   FSFAIL.read = pattern    a read of a matching path errors
--   FSFAIL.short = pattern   a read of a matching path returns all but its last byte
--   FSFAIL.shortWritten = pattern   the same, only for a file written after FSFAIL.mark() (a write that
--                                   reads back short; what was there before still reads fine)
--   FSFAIL.log               every call as { op, path } (op: "write", "read", "list", "delete")
-- Patterns are Lua patterns on the path with "/" separators.
-- ================================================================================================
FSFAIL = { log = {}, written = {} }
function FSFAIL.mark() FSFAIL.written = {} end
do
	local mockWrite, mockRead, mockList, mockDelete = writefile, readfile, listfiles, delfile
	local function norm(p) return (tostring(p):gsub("\\", "/")) end
	local function hit(pattern, p) return pattern ~= nil and norm(p):find(pattern) ~= nil end
	writefile = function(p, c)
		FSFAIL.log[#FSFAIL.log + 1] = { "write", norm(p) }
		if hit(FSFAIL.write, p) then error("writefile failed: " .. norm(p), 0) end
		FSFAIL.written[norm(p)] = true
		return mockWrite(p, c)
	end
	readfile = function(p)
		FSFAIL.log[#FSFAIL.log + 1] = { "read", norm(p) }
		if hit(FSFAIL.read, p) then error("readfile failed: " .. norm(p), 0) end
		local s = mockRead(p)
		local short = hit(FSFAIL.short, p) or (hit(FSFAIL.shortWritten, p) and FSFAIL.written[norm(p)])
		if short and type(s) == "string" and #s > 0 then return s:sub(1, -2) end
		return s
	end
	listfiles = function(p)
		FSFAIL.log[#FSFAIL.log + 1] = { "list", norm(p) }
		return mockList(p)
	end
	delfile = function(p)
		FSFAIL.log[#FSFAIL.log + 1] = { "delete", norm(p) }
		return mockDelete(p)
	end
	-- (how many of the logged calls match op and pattern)
	function FSFAIL.count(op, pattern)
		local n = 0
		for _, e in ipairs(FSFAIL.log) do
			if e[1] == op and (pattern == nil or e[2]:find(pattern)) then n = n + 1 end
		end
		return n
	end
end
