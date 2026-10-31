-- ================================================================================================
--  WRITE  (HappaTAS 3 ui): every property the interface sets goes through W.set, which writes only a
--  value that changed. Roblox redraws a ScreenGui when anything in it changes and a Text write costs
--  far more than a read (V2.37.2 / V2.38 live measurements), so an unchanged value is never written.
--  The last value written is remembered per instance (weakly): only the interface writes its objects.
--  W.version goes up whenever something that moves, sizes, shows or hides a GuiObject is written (or
--  W.bump() says so): the pointer keeps the rects' bounds until then.
-- ================================================================================================
local W = { version = 0 }
local last = setmetatable({}, { __mode = "k" })
local LAYOUT = { Position = true, Size = true, AnchorPoint = true, Visible = true, Parent = true }

function W.bump() W.version = W.version + 1 end

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
	if LAYOUT[prop] then W.version = W.version + 1 end
	return true
end

-- forgets what was written to inst (when something else may have changed it)
function W.forget(inst) last[inst] = nil end

return W
