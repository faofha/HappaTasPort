-- ================================================================================================
--  LIFECYCLE  (HappaTAS 3 kernel): everything a module creates or changes is owned here and undone on
--  Unload, newest first: connections are disconnected, instances destroyed, cleanup functions called,
--  and properties HappaTAS wrote get their old value back (unless the game wrote its own since).
--  Each module works in a scope of its own (life:scope(name)), so its things can be undone alone (a
--  module switched off after errors). Short-lived things are undone early with drop / forgetProps, so
--  nothing piles up over a session. Anything owned after cleanup (a late callback) is undone at once.
-- ================================================================================================
local Lifecycle = {}
Lifecycle.__index = Lifecycle

function Lifecycle.new(name)
	return setmetatable({ name = name, items = {}, props = {}, unloading = false, parent = nil }, Lifecycle)
end

local function undo(x)
	local t = typeof(x)
	if t == "function" then
		x()
	elseif t == "RBXScriptConnection" then
		x:Disconnect()
	elseif t == "Instance" then
		x:Destroy()
	elseif t == "table" and getmetatable(x) == Lifecycle then
		x:cleanup()
	elseif (t == "table" or t == "userdata") and x.Disconnect then
		x:Disconnect()
	end
end

function Lifecycle:own(x)
	if self.unloading then
		pcall(undo, x)
		return x
	end
	self.items[#self.items + 1] = x
	return x
end

function Lifecycle:connect(signal, fn)
	return self:own(signal:Connect(fn))
end

-- a child lifecycle for one module: undone with its parent, or on its own
function Lifecycle:scope(name)
	local child = Lifecycle.new(name)
	child.parent = self
	if self.unloading then child.unloading = true end
	self:own(child)
	return child
end

-- undo one owned thing now; false when it isn't owned here
function Lifecycle:drop(x)
	local i = table.find(self.items, x)
	if not i then return false end
	table.remove(self.items, i)
	pcall(undo, x)
	return true
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
		entry.restore = function()
			if inst[prop] == entry.last then inst[prop] = entry.orig end
		end
		byInst[prop] = entry
		self:own(entry.restore)
	end
	inst[prop] = value
	entry.last = inst[prop]
end

-- stop tracking an instance's property writes (a short-lived part): they won't be put back
function Lifecycle:forgetProps(inst)
	local byInst = self.props[inst]
	if not byInst then return end
	self.props[inst] = nil
	for _, entry in pairs(byInst) do
		local i = table.find(self.items, entry.restore)
		if i then table.remove(self.items, i) end
	end
end

function Lifecycle:cleanup()
	if self.unloading and #self.items == 0 then return end
	self.unloading = true
	local items = self.items
	self.items = {}
	self.props = {}
	for i = #items, 1, -1 do
		pcall(undo, items[i])
	end
	local parent = self.parent
	if parent then
		local i = table.find(parent.items, self)
		if i then table.remove(parent.items, i) end
	end
end

return Lifecycle
