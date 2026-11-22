-- ================================================================================================
--  COMPACT  (HappaTAS 3 ui, V3.1): the third interface, one main window with tabs and docked side panels
--  (docs/superpowers/specs/2026-11-22-third-interface-design.md). Placeholder until the main window lands.
-- ================================================================================================
local Compact = {}
Compact.__index = Compact

function Compact.new(ui)
	return setmetatable({ ui = ui, live = false }, Compact)
end

function Compact:setLive(on) self.live = on == true end
function Compact:modal() return false end
function Compact:pointerOver() return false end
function Compact:destroy() end

return Compact
