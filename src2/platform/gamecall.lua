-- ================================================================================================
--  GAME CALLS  (HappaTAS 3 platform): game code (the camera module, the EToH kit's functions) only
--  ever runs on a thread of its own. Measured in the Roblox client (V2.37.2 and later): calling the
--  game's code from HappaTAS's own thread can take that thread's access to CoreGui away until it
--  yields ("lacking capability Plugin"), so HappaTAS's interface would stop working.
-- ================================================================================================
local GameCall = {}

-- runs f(...) on its own thread; true when it finished (did not yield) without an error
function GameCall.call(f, ...)
	local done, ok = false, false
	task.spawn(function(...)
		ok = pcall(f, ...)
		done = true
	end, ...)
	return done and ok
end

-- runs f(...) on its own thread; (true, first result) when it finished without an error
function GameCall.get(f, ...)
	local done, ok, value = false, false, nil
	task.spawn(function(...)
		ok, value = pcall(f, ...)
		done = true
	end, ...)
	if done and ok then return true, value end
	return false, nil
end

return GameCall
