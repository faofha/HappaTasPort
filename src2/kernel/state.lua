-- ================================================================================================
--  STATE  (HappaTAS 3 kernel): one store for what the rest of HappaTAS shows or decides on (mode,
--  frame, paused, speed...). A value that really changed calls that key's watchers in the order they
--  were added; the interface only listens to it, it never asks.
-- ================================================================================================
local State = {}
State.__index = State

function State.new(initial, errs)
	local values = {}
	for k, v in pairs(initial or {}) do values[k] = v end
	return setmetatable({ values = values, watchers = {}, errs = errs }, State)
end

function State:get(key)
	return self.values[key]
end

function State:set(key, value)
	local old = self.values[key]
	if old == value then return end
	self.values[key] = value
	local list = self.watchers[key]
	if not list then return end
	for _, w in ipairs(table.clone(list)) do
		if w.on then
			local ok, err = pcall(w.fn, value, old)
			if not ok and self.errs then self.errs:report("state:" .. tostring(key), err) end
		end
	end
end

function State:watch(key, fn)
	local list = self.watchers[key]
	if not list then
		list = {}
		self.watchers[key] = list
	end
	local w = { fn = fn, on = true }
	list[#list + 1] = w
	return function()
		w.on = false
		local i = table.find(list, w)
		if i then table.remove(list, i) end
	end
end

function State:snapshot()
	local out = {}
	for k, v in pairs(self.values) do out[k] = v end
	return out
end

return State
