-- ================================================================================================
--  CLIENT OBJECTS  (HappaTAS 3 world plugin, order 45, "Sync Client Objects"): parts that only exist or
--  move on this client (the EToH kit's spinners, platforms, morphs...) recorded and played back with the
--  run (V2.38.17 p13_clientobjects.lua). The registry knows the parts, the recorder writes each frame's
--  record (column v2CO, V2's bytes, so V2 files play as recorded), the player puts the parts where the
--  run had them. Ids in a saved run come with their workspace paths (tl.meta.v2objects) and are translated
--  to this session's ids on load.
-- ================================================================================================
local Format = import("world/co/format")
local Registry = import("world/co/registry")
local Recorder = import("world/co/recorder")
local Player = import("world/co/player")

local byte, sub = string.byte, string.sub
local ClientObjects = { name = "clientobjects", order = 45 }
ClientObjects.__index = ClientObjects

local noop = function() end

function ClientObjects.new(E)
	local self = setmetatable({ E = E, settings = E.settings, dataVersion = 0, stampN = 0, onStartsAdded = nil }, ClientObjects)
	self.reg = Registry.new(function(text) if E.modes then E.modes:status(text) end end)
	self.rec = Recorder.new(self.reg, self)
	self.player = Player.new(self.reg, self)
	self.onStartsAdded = function() self.player:resetCheckpoints() end
	E.tl:addColumn("v2CO", "list", 1, { key = "CO", keep = true })
	-- (which recorded frame a timeline frame is: the recorder's start states and its "go on from here" check;
	-- in memory only, moved with the frames by cuts and optimize, absent from loaded frames)
	E.tl:addColumn("coStamp", "list", 1, { save = false, toV2 = noop, fromV2 = noop })
	E.life:own(function() self:disable() end)
	E.life:own(E.settings:changed("syncClientObjects", function(v)
		if v ~= 0 then self:enable() else self:disable() end
	end))
	if E.settings:on("syncClientObjects") then self:enable() end
	return self
end

function ClientObjects:enable()
	if self.reg.enabled then return end
	self.rec.forceFull = true
	self.reg:enable()
end

function ClientObjects:disable()
	if not self.reg.enabled then return end
	if self.player then self.player:release(); self.player:reset() end
	self.reg:disable()
	self.rec:reset()
end

-- the stamp of a recorded frame (start states check them against the frames they were added to)
function ClientObjects:stampOf(i)
	local tl = self.E.tl
	if i < 1 or i > tl:count() then return nil end
	return tl:getList("coStamp", i)
end

-- ------------------------------------------------------------------------------------------------ recording
function ClientObjects:fill(tl, n)
	self.stampN = self.stampN + 1
	tl:setList("coStamp", n, self.stampN)
	if not self.reg:isReady() then return end
	local E = self.E
	local hrp = E.char.hrp
	local rec = self.rec:record(hrp and hrp.Position or Vector3.zero, tl:get("TotalTime", n, 1), E.recSim, E.recWall,
		tl, n, self.stampN)
	tl:setList("v2CO", n, rec)
end

function ClientObjects:onBeginRecording(tl, n)
	self.rec:beginRecording(self:stampOf(n))
end

function ClientObjects:onDataChanged()
	self.dataVersion = self.dataVersion + 1
	if self.player then self.player:invalidate() end
end

-- ------------------------------------------------------------------------------------------------ playback
function ClientObjects:onPlaybackBegin(tl, f) self.player:playbackBegin(tl, f) end
function ClientObjects:onPlayTo(tl, f, t) self.player:playbackTo(tl, f, t) end
function ClientObjects:onPausedTick() self.player:tick() end
function ClientObjects:lateRender() self.player:renderStep() end
function ClientObjects:onEndPlayback() self.player:endPlayback() end
function ClientObjects:onShowFrame(tl, i) self.player:showFrame(tl, i) end
function ClientObjects:onRestoreUnpause(tl, i) self.player:restoreUnpause(tl, i) end
-- (V2 p18_core 1281-1282: playback ends outside Test, Idle lets every part go)
function ClientObjects:onHeartbeatStart(mode)
	local pl = self.player
	if mode ~= 3 and pl:isTesting() then pl:endPlayback() end
	if mode == 1 and pl:isHolding() then pl:release() end
end
function ClientObjects:isHolding() return self.player:isHolding() end
function ClientObjects:isTesting() return self.player:isTesting() end

-- ------------------------------------------------------------------------------------------------ for other plugins
function ClientObjects:keyOf(inst) return self.reg:keyOf(inst) end
function ClientObjects:eachPart(fn) self.reg:eachPart(fn) end
function ClientObjects:isReady() return self.reg:isReady() end
function ClientObjects:skipSim(dt) self.rec:skipSim(dt) end
function ClientObjects:ids(str, set) return Format.idsOf(str, set) end
function ClientObjects:counts() return self.reg:counts() end

-- ------------------------------------------------------------------------------------------------ saving
-- the ids a run's records use, with their workspace paths (V2 CO.ExportObjects)
function ClientObjects:exportObjects(tl)
	local set = {}
	for i = 1, tl:count() do
		local str = tl:getList("v2CO", i)
		if type(str) == "string" then Format.idsOf(str, set) end
	end
	local list = {}
	local idToKey = self.reg.reg.idToKey
	for id in pairs(set) do
		local key = idToKey[id]
		if key then list[#list + 1] = { id = id, key = key } end
	end
	table.sort(list, function(a, b) return a.id < b.id end)
	return list
end

local function remapString(str, map)
	local isV2 = byte(str, 1) >= 2
	local p, n = Format.bodyStart(str), #str
	local out = { sub(str, 1, p - 1) }
	while p <= n do
		local id
		id, p = Format.rv(str, p)
		local after = p
		local flags
		flags, p = Format.rv(str, p)
		p = Format.skipPayload(isV2, flags, str, p)
		local h = {}
		Format.putVar(h, map[id] or id)
		out[#out + 1] = Format.bufToString(h)
		out[#out + 1] = sub(str, after, p - 1)
	end
	return table.concat(out)
end

-- ids inside a file belong to the session that saved it: translate them to this session (V2 CO.ImportObjects)
function ClientObjects:importObjects(tl, objects)
	local map, changed = {}, false
	local reg = self.reg
	for _, o in ipairs(objects) do
		if type(o) == "table" and type(o.key) == "string" and type(o.id) == "number" then
			local sid = reg:idForKey(o.key)
			map[o.id] = sid
			reg.reg.used[sid] = true
			if sid ~= o.id then changed = true end
		end
	end
	if changed then
		for i = 1, tl:count() do
			local str = tl:getList("v2CO", i)
			if type(str) == "string" then tl:setList("v2CO", i, remapString(str, map)) end
			if i % 1500 == 0 and coroutine.isyieldable() then task.wait() end
		end
	end
	self:onDataChanged()
end

function ClientObjects:onSave(tl)
	tl.meta = tl.meta or {}
	tl.meta.v2objects = self:exportObjects(tl)
end

function ClientObjects:onLoaded(tl)
	local objects = tl.meta and tl.meta.v2objects
	if type(objects) == "table" then self:importObjects(tl, objects) end
end

return ClientObjects
