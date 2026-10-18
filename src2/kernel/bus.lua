-- ================================================================================================
--  BUS  (HappaTAS 3 kernel): named events between modules ("moduleDisabled", "saved"...). Listeners
--  run in the order they were added; one that errors is reported and the next still runs; one removed
--  during an emit isn't called later in that emit.
-- ================================================================================================
local Bus = {}
Bus.__index = Bus

function Bus.new(errs)
	return setmetatable({ listeners = {}, errs = errs }, Bus)
end

function Bus:on(name, fn)
	local list = self.listeners[name]
	if not list then
		list = {}
		self.listeners[name] = list
	end
	local l = { fn = fn, on = true }
	list[#list + 1] = l
	return function()
		l.on = false
		local i = table.find(list, l)
		if i then table.remove(list, i) end
	end
end

function Bus:emit(name, ...)
	local list = self.listeners[name]
	if not list then return end
	for _, l in ipairs(table.clone(list)) do
		if l.on then
			local ok, err = pcall(l.fn, ...)
			if not ok and self.errs then self.errs:report("bus:" .. tostring(name), err) end
		end
	end
end

return Bus
