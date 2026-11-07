-- ================================================================================================
--  ERRORS  (HappaTAS 3 kernel): an error is printed once per distinct message (a frame handler failing
--  every frame would flood the console otherwise), at most 25 messages per session; every report is
--  still counted per source.
-- ================================================================================================
local Errors = {}
Errors.__index = Errors
local MAX_PRINTED = 25
local MAX_LAST = 10 -- (the latest distinct messages, for the diagnostics report)

function Errors.new(printFn)
	return setmetatable({ print = printFn or warn, seen = {}, printed = 0, counts = {}, last = {} }, Errors)
end

function Errors:report(source, err)
	source = tostring(source)
	self.counts[source] = (self.counts[source] or 0) + 1
	local msg = "[HappaTAS3] " .. source .. ": " .. tostring(err)
	if self.seen[msg] then return end
	self.seen[msg] = true
	if #self.last >= MAX_LAST then table.remove(self.last, 1) end
	self.last[#self.last + 1] = msg
	if self.printed >= MAX_PRINTED then return end
	self.printed = self.printed + 1
	pcall(self.print, msg)
end

function Errors:count(source)
	return self.counts[tostring(source)] or 0
end

return Errors
