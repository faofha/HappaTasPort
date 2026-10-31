-- ================================================================================================
--  BAR MODEL  (HappaTAS 3 ui): the run's events by kind, as ascending frame lists, for the timeline bar
--  and its lanes. Built once from the columns' sparse lists, then grown by the frames that were added;
--  rebuilt when the run changes under it (another timeline, tl.version, fewer frames). Only filled
--  frames are indexed: while recording, the newest frame is appended at PreRender and filled later.
--  Kinds: state (State differs from the frame before), death (Died), tool (Tools), input (a non-empty
--  Input), kit (v2KE), button (v2BT), marker (Marker). `version` moves whenever something changed.
-- ================================================================================================
local BarModel = {}
BarModel.__index = BarModel

-- kind -> list column (state is the u8 column, handled on its own)
local LISTS = { death = "Died", tool = "Tools", input = "Input", kit = "v2KE", button = "v2BT", marker = "Marker" }
local EMPTY = {}

local function present(kind, v)
	if v == nil then return false end
	if kind == "input" then return type(v) == "table" and #v > 0 end
	return true
end

function BarModel.new(E)
	local self = setmetatable({ E = E, tl = nil, tlVersion = -1, indexed = 0, ev = {}, version = 0 }, BarModel)
	return self
end

-- the last filled frame of the run (only the tail can be unfilled)
local function lastFilled(tl)
	local n = tl:count()
	while n > 0 and not tl:isFilled(n) do n = n - 1 end
	return n
end

function BarModel:rebuild(tl, upTo)
	local ev = {}
	for kind, colName in pairs(LISTS) do
		local col = tl.cols[colName]
		local out = {}
		if col and col.list then
			for i, v in pairs(col.list) do
				if i <= upTo and present(kind, v) then out[#out + 1] = i end
			end
			table.sort(out)
		end
		ev[kind] = out
	end
	local st = {}
	local col = tl.cols.State
	if col and col.buf then
		local buf, prev = col.buf, nil
		for i = 1, upTo do
			local s = buffer.readu8(buf, i - 1)
			if prev ~= nil and s ~= prev then st[#st + 1] = i end
			prev = s
		end
	end
	ev.state = st
	self.ev = ev
	self.tl, self.tlVersion, self.indexed = tl, tl.version, upTo
	self.version = self.version + 1
end

-- frames indexed+1 .. upTo added to the lists
function BarModel:grow(tl, upTo)
	local ev = self.ev
	for kind, colName in pairs(LISTS) do
		if tl.cols[colName] then
			local out = ev[kind]
			for i = self.indexed + 1, upTo do
				if present(kind, tl:getList(colName, i)) then out[#out + 1] = i end
			end
		end
	end
	if tl.cols.State then
		local st = ev.state
		local prev = (self.indexed > 0) and tl:get("State", self.indexed, 1) or nil
		for i = self.indexed + 1, upTo do
			local s = tl:get("State", i, 1)
			if prev ~= nil and s ~= prev then st[#st + 1] = i end
			prev = s
		end
	end
	self.indexed = upTo
	self.version = self.version + 1
end

-- brings the index up to the run; cheap when nothing changed
function BarModel:sync()
	local tl = self.E.tl
	local upTo = lastFilled(tl)
	if tl ~= self.tl or tl.version ~= self.tlVersion or upTo < self.indexed then
		self:rebuild(tl, upTo)
	elseif upTo > self.indexed then
		self:grow(tl, upTo)
	end
end

function BarModel:events(kind) return self.ev[kind] or EMPTY end

-- indexes i0..i1 into events(kind) of the events in frames f0..f1 (i0 > i1 when none)
function BarModel:range(kind, f0, f1)
	local list = self:events(kind)
	local lo, hi = 1, #list + 1
	while lo < hi do
		local mid = math.floor((lo + hi) / 2)
		if list[mid] < f0 then lo = mid + 1 else hi = mid end
	end
	local i0 = lo
	lo, hi = i0, #list + 1
	while lo < hi do
		local mid = math.floor((lo + hi) / 2)
		if list[mid] <= f1 then lo = mid + 1 else hi = mid end
	end
	return i0, lo - 1
end

function BarModel:markerAt(f)
	local tl = self.E.tl
	if not tl.cols.Marker or f < 1 or f > tl:count() then return nil end
	return tl:getList("Marker", f)
end

-- adds a marker on frame f (label or true), or removes the one there; true when added
function BarModel:toggleMarker(f, label)
	local tl = self.E.tl
	if not tl.cols.Marker or f < 1 or f > tl:count() then return false end
	self:sync()
	local list = self.ev.marker or {}
	self.ev.marker = list
	local i0, i1 = self:range("marker", f, f)
	if tl:getList("Marker", f) ~= nil then
		tl:setList("Marker", f, nil)
		tl.edits = (tl.edits or 0) + 1 -- (a change no tl.version follows: the unsaved dot sees it)
		if i0 <= i1 then table.remove(list, i0) end
		self.version = self.version + 1
		return false
	end
	tl:setList("Marker", f, label or true)
	tl.edits = (tl.edits or 0) + 1
	if f <= self.indexed then table.insert(list, i0, f) end
	self.version = self.version + 1
	return true
end

return BarModel
