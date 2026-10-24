-- ================================================================================================
--  STUBS  (HappaTAS 3 engine): stand-ins for the camera script and the world plugins the engine calls
--  by name (camera, inputs, animation, tools) while one isn't there: every method does nothing, the few
--  getters give neutral values. The real ones replace them when they are added.
-- ================================================================================================
local Stubs = {}

local function noop() end
local function make(getters)
	return setmetatable(getters or {}, { __index = function() return noop end })
end

function Stubs.cameraScript()
	return make({
		timeRate = 1,
		getZoom = function() return 12.5 end,
		isShiftlocked = function() return false end,
		isFirstPerson = function() return false end,
		isMouseFree = function() return false end,
	})
end
function Stubs.camera()
	return make({
		averaged = function() return nil, 12.5 end,
		zoomAt = function() return 12.5 end,
		shiftAt = function() return 0 end,
	})
end
function Stubs.inputs()
	return make({
		isReplaying = function() return false end,
		isOverOwnUI = function() return false end,
		heldAt = function() return {} end,
	})
end
function Stubs.animation() return make() end
function Stubs.tools() return make() end

return Stubs
