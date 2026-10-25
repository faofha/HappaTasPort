-- ================================================================================================
--  TIMELINE  (HappaTAS 3 engine): the frames of a run, stored as columns.
--    "f64"  numbers, `width` a frame, in one Luau buffer (8 bytes each)
--    "u8"   one small number a frame (0..255), in one buffer
--    "list" any Lua value or nil a frame, in a table keyed by frame (rare data: inputs, tool events...)
--  Plugins register their own columns. A V2.38.16 frame table converts to and from the columns through
--  each column's `v2` description:
--    { key = "Zoom" }                         frame.Zoom (width 1) or frame.Cframe = { ... } (width > 1)
--    { key = "Velocity", sub = "Linear" }     frame.Velocity.Linear = { ... }
--    { key = "Anim", field = "Pose" }         frame.Anim.Pose (lists: `default` when nil)
--    { keys = { "MX", "MY" } }                one field per component (lists: a { x, y } value)
--    { toV2 = f(tl, i, frame), fromV2 = f(tl, i, frame) }
--  Optimize flags: keep = true / f(value) (a frame with this value is kept), keepOnChange = true /
--  { components } (kept when these differ from the frame before).
--  Growth doubles the buffers; a cut only lowers the count (the values of frames reused later are
--  cleared by append). `version` changes whenever existing frames change or go (not on append / set).
-- ================================================================================================
local Util = import("engine/util")

local Timeline = {}
Timeline.__index = Timeline

local START_CAP = 1024
local BYTES = { f64 = 8, u8 = 1 }

function Timeline.new()
	-- (meta: the run's own data, kept through saving and loading: when it was made, V2 tables, ...)
	local tl = setmetatable({ n = 0, cap = START_CAP, cols = {}, order = {}, version = 0, meta = {} }, Timeline)
	tl:addColumn("_filled", "u8", 1, nil)
	return tl
end

function Timeline:addColumn(name, kind, width, v2)
	if self.cols[name] then error("HappaTAS3: timeline column " .. name .. " exists", 2) end
	width = (kind == "f64") and (width or 1) or 1
	local col = { name = name, kind = kind, width = width, v2 = v2 }
	if kind == "list" then
		col.list = {}
	elseif BYTES[kind] then
		col.stride = width * BYTES[kind]
		col.buf = buffer.create(self.cap * col.stride)
	else
		error("HappaTAS3: unknown column kind " .. tostring(kind), 2)
	end
	self.cols[name] = col
	self.order[#self.order + 1] = col
	return col
end

function Timeline:count() return self.n end

local function grow(self)
	local cap = self.cap * 2
	for _, col in ipairs(self.order) do
		if col.buf then
			local nb = buffer.create(cap * col.stride)
			buffer.copy(nb, 0, col.buf, 0, self.n * col.stride)
			col.buf = nb
		end
	end
	self.cap = cap
end

-- a new frame at the end: numbers 0, lists nil, not filled
function Timeline:append()
	if self.n >= self.cap then grow(self) end
	local i = self.n + 1
	self.n = i
	for _, col in ipairs(self.order) do
		if col.buf then
			buffer.fill(col.buf, (i - 1) * col.stride, 0, col.stride)
		else
			col.list[i] = nil
		end
	end
	return i
end

function Timeline:set(name, i, k, v)
	local col = self.cols[name]
	if col.kind == "f64" then
		buffer.writef64(col.buf, (i - 1) * col.stride + (k - 1) * 8, v)
	else
		buffer.writeu8(col.buf, i - 1, v)
	end
end

function Timeline:get(name, i, k)
	local col = self.cols[name]
	if col.kind == "f64" then return buffer.readf64(col.buf, (i - 1) * col.stride + (k - 1) * 8) end
	return buffer.readu8(col.buf, i - 1)
end

function Timeline:setN(name, i, ...)
	local col = self.cols[name]
	local base = (i - 1) * col.stride
	for k = 1, col.width do buffer.writef64(col.buf, base + (k - 1) * 8, (select(k, ...))) end
end

function Timeline:getN(name, i)
	local col = self.cols[name]
	local base, buf = (i - 1) * col.stride, col.buf
	if col.width == 3 then
		return buffer.readf64(buf, base), buffer.readf64(buf, base + 8), buffer.readf64(buf, base + 16)
	end
	local out = table.create(col.width)
	for k = 1, col.width do out[k] = buffer.readf64(buf, base + (k - 1) * 8) end
	return table.unpack(out, 1, col.width)
end

-- all `width` values of frame i as a new table
function Timeline:getArray(name, i)
	local col = self.cols[name]
	local base, buf = (i - 1) * col.stride, col.buf
	local out = table.create(col.width)
	for k = 1, col.width do out[k] = buffer.readf64(buf, base + (k - 1) * 8) end
	return out
end

function Timeline:setList(name, i, v) self.cols[name].list[i] = v end
function Timeline:getList(name, i) return self.cols[name].list[i] end
function Timeline:isFilled(i) return buffer.readu8(self.cols._filled.buf, i - 1) == 1 end
function Timeline:setFilled(i) buffer.writeu8(self.cols._filled.buf, i - 1, 1) end

local function dropListsAfter(self, n)
	for _, col in ipairs(self.order) do
		if col.list then
			for i in pairs(col.list) do
				if i > n then col.list[i] = nil end
			end
		end
	end
end

-- keep frames 1..n
function Timeline:cut(n)
	if n < 0 then n = 0 end
	if n >= self.n then return end
	self.n = n
	dropListsAfter(self, n)
	self.version = self.version + 1
end

function Timeline:removeLast()
	if self.n > 0 then self:cut(self.n - 1) end
end

-- ------------------------------------------------------------------------------------------------ loading
-- a timeline with the same columns (and V2 descriptions), no frames, an empty meta
function Timeline.newLike(tl)
	local out = Timeline.new()
	for _, col in ipairs(tl.order) do
		if col.name ~= "_filled" then out:addColumn(col.name, col.kind, col.width, col.v2) end
	end
	return out
end

-- capacity for at least n frames (buffers keep their first `keep` frames)
local function reserve(self, n, keep)
	if n <= self.cap then return end
	local cap = self.cap
	while cap < n do cap = cap * 2 end
	for _, col in ipairs(self.order) do
		if col.buf then
			local nb = buffer.create(cap * col.stride)
			buffer.copy(nb, 0, col.buf, 0, keep * col.stride)
			col.buf = nb
		end
	end
	self.cap = cap
end

-- n frames, all filled: numbers 0, lists empty (a file's frames are written in after this)
function Timeline:resize(n)
	reserve(self, n, 0)
	for _, col in ipairs(self.order) do
		if col.buf then
			buffer.fill(col.buf, 0, 0, n * col.stride)
		else
			col.list = {}
		end
	end
	self.n = n
	buffer.fill(self.cols._filled.buf, 0, 1, n)
	self.version = self.version + 1
end

-- takes the frames, columns and meta of `other` (a timeline a file was loaded into): the columns keep
-- their tables here, only their data changes; a column only `other` has is added
function Timeline:adopt(other)
	reserve(self, other.cap, 0)
	for _, oc in ipairs(other.order) do
		local col = self.cols[oc.name]
		if not col then
			col = self:addColumn(oc.name, oc.kind, oc.width, oc.v2)
		elseif col.kind ~= oc.kind or col.width ~= oc.width then
			error("HappaTAS3: column " .. oc.name .. " has a different shape", 2)
		end
		if oc.buf then
			local nb = buffer.create(self.cap * col.stride)
			buffer.copy(nb, 0, oc.buf, 0, other.n * col.stride)
			col.buf = nb
		else
			col.list = oc.list
		end
	end
	for _, col in ipairs(self.order) do
		if not other.cols[col.name] then
			if col.buf then buffer.fill(col.buf, 0, 0, other.n * col.stride) else col.list = {} end
		end
	end
	self.n = other.n
	self.meta = other.meta or {}
	self.version = self.version + 1
end

-- ------------------------------------------------------------------------------------------------ V2 frames
local function sub(frame, key)
	local t = frame[key]
	if t == nil then
		t = {}
		frame[key] = t
	end
	return t
end

local function colToV2(self, col, i, frame)
	local v2 = col.v2
	if v2.toV2 then return v2.toV2(self, i, frame) end
	if col.kind == "list" then
		local v = col.list[i]
		if v2.keys then
			if v ~= nil then
				for k, key in ipairs(v2.keys) do frame[key] = v[k] end
			end
			return
		end
		if v == nil then
			if v2.default == nil then return end
			v = table.clone(v2.default)
		end
		if v2.field then sub(frame, v2.key)[v2.field] = v else frame[v2.key] = v end
		return
	end
	local value
	if col.kind == "u8" then
		value = buffer.readu8(col.buf, i - 1)
	elseif col.width == 1 then
		value = buffer.readf64(col.buf, (i - 1) * col.stride)
	elseif v2.keys then
		local base = (i - 1) * col.stride
		for k, key in ipairs(v2.keys) do frame[key] = buffer.readf64(col.buf, base + (k - 1) * 8) end
		return
	else
		value = self:getArray(col.name, i)
	end
	if v2.sub then sub(frame, v2.key)[v2.sub] = value
	elseif v2.field then sub(frame, v2.key)[v2.field] = value
	else frame[v2.key] = value end
end

local function colFromV2(self, col, i, frame)
	local v2 = col.v2
	if v2.fromV2 then return v2.fromV2(self, i, frame) end
	local value
	if v2.keys then
		if col.kind == "list" then
			local first = frame[v2.keys[1]]
			if first ~= nil then
				local t = {}
				for k, key in ipairs(v2.keys) do t[k] = frame[key] end
				value = t
			end
			col.list[i] = value
			return
		end
		local base = (i - 1) * col.stride
		for k, key in ipairs(v2.keys) do buffer.writef64(col.buf, base + (k - 1) * 8, tonumber(frame[key]) or 0) end
		return
	end
	local holder = frame[v2.key]
	if v2.sub or v2.field then
		value = type(holder) == "table" and holder[v2.sub or v2.field] or nil
	else
		value = holder
	end
	if col.kind == "list" then
		if v2.default ~= nil and type(value) == "table" and #value == 0 and next(value) == nil then value = nil end
		col.list[i] = value
	elseif col.kind == "u8" then
		buffer.writeu8(col.buf, i - 1, tonumber(value) or 0)
	elseif col.width == 1 then
		buffer.writef64(col.buf, (i - 1) * col.stride, tonumber(value) or 0)
	else
		local base = (i - 1) * col.stride
		for k = 1, col.width do
			buffer.writef64(col.buf, base + (k - 1) * 8, type(value) == "table" and tonumber(value[k]) or 0)
		end
	end
end

-- frame i as a V2.38.16 frame table (only the registered columns)
function Timeline:toV2(i)
	local frame = {}
	for _, col in ipairs(self.order) do
		if col.v2 then colToV2(self, col, i, frame) end
	end
	return frame
end

function Timeline:toV2All()
	local out = table.create(self.n)
	for i = 1, self.n do out[i] = self:toV2(i) end
	return out
end

-- replaces every frame with V2 frame tables (loaded frames count as filled)
function Timeline:replaceFromV2(frames)
	self.n = 0
	dropListsAfter(self, 0)
	for _, frame in ipairs(frames) do
		local i = self:append()
		for _, col in ipairs(self.order) do
			if col.v2 then colFromV2(self, col, i, frame) end
		end
		self:setFilled(i)
	end
	self.version = self.version + 1
end

-- ------------------------------------------------------------------------------------------------ optimize
local function sameAs(col, a, b, comps)
	local buf, stride = col.buf, col.stride
	if comps == true then
		for k = 0, col.width - 1 do
			if buffer.readf64(buf, (a - 1) * stride + k * 8) ~= buffer.readf64(buf, (b - 1) * stride + k * 8) then return false end
		end
		return true
	end
	for _, k in ipairs(comps) do
		if buffer.readf64(buf, (a - 1) * stride + (k - 1) * 8) ~= buffer.readf64(buf, (b - 1) * stride + (k - 1) * 8) then return false end
	end
	return true
end

local function keepFrame(self, i)
	if i == 1 then return true end
	for _, col in ipairs(self.order) do
		local v2 = col.v2
		if v2 then
			if v2.keepOnChange and not sameAs(col, i, i - 1, v2.keepOnChange) then return true end
			local keep = v2.keep
			if keep and col.list then
				local v = col.list[i]
				if v ~= nil and (keep == true or keep(v)) then return true end
			end
		end
	end
	return false
end

-- drops frames that change nothing (V2.38.16 Optimize): frame 1 always stays; TotalTime is summed again
-- from FrameTime. Returns the new count.
function Timeline:optimize()
	local kept = {}
	for i = 1, self.n do
		if keepFrame(self, i) then kept[#kept + 1] = i end
	end
	for j, i in ipairs(kept) do
		if i ~= j then
			for _, col in ipairs(self.order) do
				if col.buf then
					buffer.copy(col.buf, (j - 1) * col.stride, col.buf, (i - 1) * col.stride, col.stride)
				else
					col.list[j] = col.list[i]
				end
			end
		end
	end
	local n = #kept
	self.n = n
	dropListsAfter(self, n)
	if self.cols.TotalTime and self.cols.FrameTime then
		local total = 0
		for j = 1, n do
			local ft = self:get("FrameTime", j, 1)
			total = (j == 1) and Util.round(ft, 1000000) or Util.round(total + ft, 1000000)
			self:set("TotalTime", j, 1, total)
		end
	end
	self.version = self.version + 1
	return n
end

return Timeline
