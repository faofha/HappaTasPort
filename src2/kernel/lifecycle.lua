-- ================================================================================================
--  LIFECYCLE  (HappaTAS 3 kernel): everything a module creates or changes is owned here and undone on
--  Unload, newest first: connections are disconnected, instances destroyed, cleanup functions called,
--  and properties HappaTAS wrote get their old value back (unless the game wrote its own since).
-- ================================================================================================
local Lifecycle = {}
Lifecycle.__index = Lifecycle

function Lifecycle.new()
	return setmetatable({ items = {}, props = {}, unloading = false }, Lifecycle)
end

function Lifecycle:own(x)
	self.items[#self.items + 1] = x
	return x
end

function Lifecycle:connect(signal, fn)
	return self:own(signal:Connect(fn))
end

-- writes inst[prop] = value; the value from before HappaTAS's first write is put back on cleanup if the
-- property still holds what HappaTAS wrote last
function Lifecycle:setProp(inst, prop, value)
	local byInst = self.props[inst]
	if not byInst then
		byInst = {}
		self.props[inst] = byInst
	end
	local entry = byInst[prop]
	if not entry then
		entry = { orig = inst[prop] }
		byInst[prop] = entry
		self:own(function()
			if inst[prop] == entry.last then inst[prop] = entry.orig end
		end)
	end
	inst[prop] = value
	entry.last = inst[prop]
end

local function undo(x)
	local t = typeof(x)
	if t == "function" then
		x()
	elseif t == "RBXScriptConnection" then
		x:Disconnect()
	elseif t == "Instance" then
		x:Destroy()
	elseif (t == "table" or t == "userdata") and x.Disconnect then
		x:Disconnect()
	end
end

function Lifecycle:cleanup()
	self.unloading = true
	local items = self.items
	self.items = {}
	self.props = {}
	for i = #items, 1, -1 do
		pcall(undo, items[i])
	end
end

return Lifecycle
