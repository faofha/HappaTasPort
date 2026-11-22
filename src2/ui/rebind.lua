-- ================================================================================================
--  REBIND  (HappaTAS 3 ui, V3.1): waiting for a key to bind to a control, shared by the New interface's Controls
--  window and the Tasability KEYS list. start(controlKey, onDone) waits: the engine's keys are off meanwhile
--  (Typing.rebinding); the next key or mouse button that engine/keys knows (Backspace and Delete included) is bound
--  through E.controls and reported as onDone(name); that press never runs a control (Typing.boundInput: Roblox
--  doesn't promise the order of InputBegan handlers, V2.37.2); a mouse button's release is swallowed (rb.swallow)
--  so it doesn't click what is under it. Esc or stop() cancel: onDone(nil).
-- ================================================================================================
local Env = import("platform/env")
local Keys = import("engine/keys")

local Rebind = {}
Rebind.__index = Rebind

function Rebind.new(E, life)
	local self = setmetatable({ E = E, waiting = nil, onDone = nil, swallow = nil, conns = {} }, Rebind)
	local uis = Env.svc("UserInputService")
	self.conns[#self.conns + 1] = life:connect(uis.InputBegan, function(inp) self:began(inp) end)
	self.conns[#self.conns + 1] = life:connect(uis.InputEnded, function(inp)
		if self.swallow and inp.UserInputType == self.swallow then
			task.defer(function() self.swallow = nil end) -- (after the pointer has had this release)
		end
	end)
	self.life = life
	return self
end

-- waits for a key for controlKey; onDone(name | nil) when it is bound or cancelled
function Rebind:start(controlKey, onDone)
	if self.waiting then self:stop() end
	self.waiting, self.onDone = controlKey, onDone
	self.E.typing.rebinding = true
end

-- cancels a wait (onDone(nil))
function Rebind:stop()
	if not self.waiting then return end
	local f = self.onDone
	self.waiting, self.onDone = nil, nil
	self.E.typing.rebinding = false
	if f then f(nil) end
end

function Rebind:began(inp)
	if not self.waiting then return end
	local E = self.E
	if inp.KeyCode == Enum.KeyCode.Escape then
		E.typing.boundInput = inp
		self:stop()
		return
	end
	local name = Keys.fromKey[inp.KeyCode] or Keys.fromKey[inp.UserInputType]
	if not name then return end
	E.typing.boundInput = inp
	local key, f = self.waiting, self.onDone
	self.waiting, self.onDone = nil, nil
	E.typing.rebinding = false
	if inp.UserInputType ~= Enum.UserInputType.Keyboard then self.swallow = inp.UserInputType end
	E.controls:set(key, name)
	if f then f(name) end
end

function Rebind:destroy()
	self:stop()
	for _, c in ipairs(self.conns) do self.life:drop(c) end
	self.conns = {}
end

return Rebind
