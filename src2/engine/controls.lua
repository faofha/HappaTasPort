-- ================================================================================================
--  CONTROLS  (HappaTAS 3 engine): every action with its key. Defaults are V2.38.16's; each row keeps
--  its V2 name for the Settings.json conversion (phase 3). "None" = no key.
-- ================================================================================================
local Keys = import("engine/keys")

local Controls = {}
Controls.__index = Controls

Controls.LIST = {
	{ key = "idle", v2 = "Idle", default = "1" },
	{ key = "create", v2 = "Create", default = "2" },
	{ key = "test", v2 = "Test", default = "3" },
	{ key = "pause", v2 = "Pause", default = "Left Click" },
	{ key = "unpause", v2 = "Unpause", default = "Left Click" },
	{ key = "forward", v2 = "Forward", default = "T" },
	{ key = "back", v2 = "Back", default = "R" },
	{ key = "forward1", v2 = "Forward 1 Frame", default = "G" },
	{ key = "back1", v2 = "Back 1 Frame", default = "F" },
	{ key = "unpause1", v2 = "Unpause 1 Frame", default = "V" },
	{ key = "return", v2 = "Return", default = "E" },
	{ key = "lookAround", v2 = "Look Around", default = "L" },
	{ key = "optimize", v2 = "Optimize TAS", default = "Q" },
	{ key = "deleteTas", v2 = "Delete TAS", default = "Backspace" },
	{ key = "menu", v2 = "Menu", default = "M" },
	{ key = "microProfiler", v2 = "MicroProfiler", default = "F6" },
	{ key = "toggleSpeedHack", v2 = "Toggle Speed Hack", default = "None" },
}
Controls.byKey, Controls.byV2 = {}, {}
for _, c in ipairs(Controls.LIST) do
	Controls.byKey[c.key] = c
	Controls.byV2[c.v2] = c
end

function Controls.new()
	local values = {}
	for _, c in ipairs(Controls.LIST) do values[c.key] = c.default end
	return setmetatable({ values = values, listeners = {} }, Controls)
end

function Controls:get(control) return self.values[control] end

-- false for an unknown control or key name
function Controls:set(control, keyName)
	if self.values[control] == nil then return false end
	if keyName ~= "None" and not Keys.isValid(keyName) then return false end
	if self.values[control] == keyName then return true end
	self.values[control] = keyName
	for _, f in ipairs(table.clone(self.listeners)) do pcall(f, control, keyName) end
	return true
end

-- f(control, keyName) after a key changed (the settings file saves on it); returns a remover
function Controls:changed(f)
	local list = self.listeners
	list[#list + 1] = f
	return function()
		local i = table.find(list, f)
		if i then table.remove(list, i) end
	end
end

-- true when the input is the key bound to the control (V2 CheckInput)
function Controls:matches(inp, control)
	local item = Keys.toKey[self.values[control] or ""]
	if item == nil then return false end
	return inp.KeyCode == item or inp.UserInputType == item
end

return Controls
