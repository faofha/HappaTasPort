-- ================================================================================================
--  WRITE  (HappaTAS 3 ui): every property the interface sets goes through W.set, which writes only a
--  value that changed. Roblox redraws a ScreenGui when anything in it changes and a Text write costs
--  far more than a read (V2.37.2 / V2.38 live measurements), so an unchanged value is never written.
--  The last value written is remembered per instance (weakly): only the interface writes its objects.
-- ================================================================================================
local W = {}
local last = setmetatable({}, { __mode = "k" })

-- true when the value was written
function W.set(inst, prop, value)
	local c = last[inst]
	if not c then
		c = {}
		last[inst] = c
	elseif c[prop] == value and value ~= nil then
		return false
	end
	c[prop] = value
	inst[prop] = value
	return true
end

-- forgets what was written to inst (when something else may have changed it)
function W.forget(inst) last[inst] = nil end

return W
