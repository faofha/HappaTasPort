-- ================================================================================================
--  UTIL  (HappaTAS 3 engine): small number helpers shared by the engine and the plugins. Frame values
--  are rounded exactly like V2.38.16 (positions / velocities / zoom at 1/1000, times at 1/1000000).
-- ================================================================================================
local Util = {}

Util.ZERO3 = Vector3.zero

-- n rounded to 1 / d; -0 becomes 0 (V2 r())
function Util.round(n, d)
	local v = math.round(n * d) / d
	if v == 0 then v = 0 end
	return v
end

function Util.clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

-- seconds as "m:ss.sss" (V2 C.ToTime)
function Util.toTime(t)
	t = tonumber(t) or 0
	local mins = math.floor(t / 60)
	local secs = Util.round(t - mins * 60, 1000)
	local s = tostring(secs)
	local intPart = s:match("^%-?(%d+)") or "0"
	if #intPart < 2 then s = "0" .. s end
	return mins .. ":" .. s
end

return Util
