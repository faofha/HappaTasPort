-- ================================================================================================
--  LIGHTING  (HappaTAS 3 world plugin, order 56, "Sync Lighting"): the game's Lighting and its effects as
--  the run had them (V2.38.17 p14_buttons.lua 1812-2052, function by function).
--  While recording, a snapshot (Lighting's numbers / colours, each effect's properties) is kept on the frame
--  where the lighting changed (column LT, in memory only: V2 never saved it either). Paused, scrubbing and
--  Test show the lighting of the frame shown. Idle (and the end of a Test) leaves the lighting as it is; turning
--  Sync Lighting off or unloading puts back the lighting from before the TAS.
-- ================================================================================================
local Env = import("platform/env")

local L_NUM = { "Brightness", "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "ExposureCompensation", "FogStart", "FogEnd", "GeographicLatitude", "ShadowSoftness", "ClockTime" }
local L_COL = { "Ambient", "OutdoorAmbient", "ColorShift_Bottom", "ColorShift_Top", "FogColor" }
local EFF_DEF = {
	ColorCorrectionEffect = { n = { "Brightness", "Contrast", "Saturation" }, c = { "TintColor" }, b = { "Enabled" } },
	BloomEffect = { n = { "Intensity", "Size", "Threshold" }, b = { "Enabled" } },
	BlurEffect = { n = { "Size" }, b = { "Enabled" } },
	SunRaysEffect = { n = { "Intensity", "Spread" }, b = { "Enabled" } },
	DepthOfFieldEffect = { n = { "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity" }, b = { "Enabled" } },
	Atmosphere = { n = { "Density", "Offset", "Glare", "Haze" }, c = { "Color", "Decay" } },
	Sky = { n = { "MoonAngularSize", "StarCount", "SunAngularSize" }, s = { "MoonTextureId", "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp", "SunTextureId" } },
}

local Lighting = { name = "lighting", order = 56 }
Lighting.__index = Lighting

local function numEq(n1, n2, tol)
	if n1 == n2 then return true end
	if not n1 or not n2 then return false end
	return math.abs(n1 - n2) < (tol or 0.001)
end
local function colorEq(c1, c2)
	if c1 == c2 then return true end
	if not c1 or not c2 then return false end
	return math.abs(c1.R - c2.R) < 0.002 and math.abs(c1.G - c2.G) < 0.002 and math.abs(c1.B - c2.B) < 0.002
end

function Lighting.new(E)
	local self = setmetatable({ E = E, lighting = Env.svc("Lighting"),
		enabled = false, dirty = true, applying = false,
		initialSnap = nil, lastSnap = nil, curSnap = nil,
		timeline = {}, lConns = {}, effConns = setmetatable({}, { __mode = "k" }),
		control = "none", curFrame = 0 }, Lighting)
	E.tl:addColumn("LT", "list", 1, { key = "LT", save = false })
	E.life:own(function() self:disable() end)
	E.life:own(E.settings:changed("syncLighting", function(v)
		if v ~= 0 then self:enable() else self:disable() end
	end))
	if E.settings:on("syncLighting") then self:enable() end
	return self
end

-- ------------------------------------------------------------------------------------------------ snapshots
function Lighting:markDirty()
	if not self.applying then self.dirty = true end
end

function Lighting:watchEffect(ch)
	if self.effConns[ch] or not EFF_DEF[ch.ClassName] then return end
	self.effConns[ch] = ch.Changed:Connect(function() self:markDirty() end)
end

function Lighting:capture()
	local lighting = self.lighting
	local snap = { GlobalShadows = lighting.GlobalShadows }
	for _, k in ipairs(L_NUM) do snap[k] = lighting[k] end
	for _, k in ipairs(L_COL) do snap[k] = lighting[k] end
	local effs = {}
	for _, ch in ipairs(lighting:GetChildren()) do
		local def = EFF_DEF[ch.ClassName]
		if def then
			self:watchEffect(ch)
			local e = { type = ch.ClassName, name = ch.Name }
			if def.b then for _, k in ipairs(def.b) do e[k] = ch[k] end end
			if def.n then for _, k in ipairs(def.n) do e[k] = ch[k] end end
			if def.c then for _, k in ipairs(def.c) do e[k] = ch[k] end end
			if def.s then for _, k in ipairs(def.s) do e[k] = ch[k] end end
			effs[#effs + 1] = e
		end
	end
	snap.effs = effs
	self.dirty = false
	return snap
end

function Lighting:apply(snap)
	if not snap then return end
	local lighting = self.lighting
	self.applying = true
	pcall(function()
		if snap.GlobalShadows ~= nil and lighting.GlobalShadows ~= snap.GlobalShadows then lighting.GlobalShadows = snap.GlobalShadows end
		for _, k in ipairs(L_NUM) do
			local v = snap[k]
			if v ~= nil and not numEq(lighting[k], v, 0.0005) then lighting[k] = v end
		end
		for _, k in ipairs(L_COL) do
			local v = snap[k]
			if v ~= nil and not colorEq(lighting[k], v) then lighting[k] = v end
		end
	end)
	if snap.effs then
		for _, e in ipairs(snap.effs) do
			local inst = lighting:FindFirstChild(e.name)
			local def = EFF_DEF[e.type]
			if inst and def and inst.ClassName == e.type then
				pcall(function()
					if def.b then for _, k in ipairs(def.b) do if e[k] ~= nil and inst[k] ~= e[k] then inst[k] = e[k] end end end
					if def.n then for _, k in ipairs(def.n) do if e[k] ~= nil and not numEq(inst[k], e[k], 0.0005) then inst[k] = e[k] end end end
					if def.c then for _, k in ipairs(def.c) do if e[k] ~= nil and not colorEq(inst[k], e[k]) then inst[k] = e[k] end end end
					if def.s then for _, k in ipairs(def.s) do if e[k] ~= nil and inst[k] ~= e[k] then inst[k] = e[k] end end end
				end)
			end
		end
	end
	self.applying = false
	self.dirty = false
end

local function diff(a, b)
	if not a or not b or a.GlobalShadows ~= b.GlobalShadows then return true end
	for _, k in ipairs(L_NUM) do
		local tol = (k == "FogStart" or k == "FogEnd") and 0.1 or ((k == "ClockTime") and 0.005 or 0.001)
		if not numEq(a[k], b[k], tol) then return true end
	end
	for _, k in ipairs(L_COL) do if not colorEq(a[k], b[k]) then return true end end
	local ea, eb = a.effs or {}, b.effs or {}
	if #ea ~= #eb then return true end
	for i = 1, #ea do
		local x, y = ea[i], eb[i]
		local def = EFF_DEF[x.type]
		if not def or x.name ~= y.name or x.type ~= y.type then return true end
		if def.b then for _, k in ipairs(def.b) do if x[k] ~= y[k] then return true end end end
		if def.n then for _, k in ipairs(def.n) do if not numEq(x[k], y[k]) then return true end end end
		if def.c then for _, k in ipairs(def.c) do if not colorEq(x[k], y[k]) then return true end end end
		if def.s then for _, k in ipairs(def.s) do if x[k] ~= y[k] then return true end end end
	end
	return false
end

-- the lighting of frame f (nil before the TAS has any: then the lighting is left as it is)
function Lighting:findSnap(f)
	local timeline = self.timeline
	if #timeline == 0 then return nil end
	local lo, hi, best = 1, #timeline, nil
	while lo <= hi do
		local mid = math.floor((lo + hi) / 2)
		if timeline[mid].f <= f then best = timeline[mid]; lo = mid + 1 else hi = mid - 1 end
	end
	return best and best.snap or nil
end

-- ------------------------------------------------------------------------------------------------ on / off
function Lighting:enable()
	if self.enabled then return end
	self.enabled = true
	local lighting = self.lighting
	local lc = self.lConns
	lc[#lc + 1] = lighting.Changed:Connect(function() self:markDirty() end)
	lc[#lc + 1] = lighting.ChildAdded:Connect(function(ch) self:watchEffect(ch); self:markDirty() end)
	lc[#lc + 1] = lighting.ChildRemoved:Connect(function() self:markDirty() end)
	for _, ch in ipairs(lighting:GetChildren()) do self:watchEffect(ch) end
	if not self.initialSnap then self.initialSnap = self:capture() end
	self.lastSnap = self.initialSnap
end

function Lighting:disable()
	if not self.enabled then return end
	self.enabled = false
	for _, cn in ipairs(self.lConns) do pcall(function() cn:Disconnect() end) end
	self.lConns = {}
	for ch, cn in pairs(self.effConns) do pcall(function() cn:Disconnect() end); self.effConns[ch] = nil end
	if self.initialSnap then self:apply(self.initialSnap) end
	self.timeline = {}
	self.control = "none"
	self.curSnap = nil
end

-- ------------------------------------------------------------------------------------------------ the run
-- frames after f were cut
function Lighting:trim(f)
	if not f then return end
	local timeline = self.timeline
	while #timeline > 0 and timeline[#timeline].f > f do timeline[#timeline] = nil end
	self.lastSnap = self:findSnap(f)
	if self.curFrame > f then self.curFrame = f end
	if self.control == "paused" or self.control == "test" then
		self.curSnap = self:findSnap(self.curFrame)
		if self.curSnap then self:apply(self.curSnap) end
	end
end

function Lighting:clear()
	self.timeline = {}
	self.curFrame = 0
	self.curSnap = nil
	self.lastSnap = self.initialSnap
end

function Lighting:loadFrom(tl)
	self.timeline = {}
	if not tl then return end
	local timeline = self.timeline
	for f = 1, tl:count() do
		local snap = tl:getList("LT", f)
		if snap then timeline[#timeline + 1] = { f = f, t = tl:get("TotalTime", f, 1), snap = snap } end
	end
	if #timeline > 0 then self.lastSnap = timeline[#timeline].snap end
end

function Lighting:recordFrame(frame, tNow, first)
	if not self.enabled or self.control ~= "record" then return nil end
	if first or #self.timeline == 0 then
		self.initialSnap = self.initialSnap or self:capture()
		self.lastSnap = self:capture()
		self.timeline = { { f = 1, t = tNow, snap = self.lastSnap } }
		return self.lastSnap
	end
	local timeline = self.timeline
	while #timeline > 0 and timeline[#timeline].f >= frame do timeline[#timeline] = nil end
	if not self.dirty then return nil end
	local cur = self:capture()
	if diff(cur, self.lastSnap) then
		self.lastSnap = cur
		timeline[#timeline + 1] = { f = frame, t = tNow, snap = cur }
		return cur
	end
	return nil
end

-- ------------------------------------------------------------------------------------------------ hooks
function Lighting:fill(tl, n)
	tl:setList("LT", n, self:recordFrame(n, tl:get("TotalTime", n, 1), n == 1))
end

function Lighting:onShowFrame(tl, f)
	if not self.enabled then return end
	self.control = "paused"
	self.curFrame = f
	self.curSnap = self:findSnap(f)
	if self.curSnap then self:apply(self.curSnap) end
end

function Lighting:onPlaybackBeginAlways(tl, f)
	if not self.enabled then return end
	self.control = "test"
	self.curFrame = f
	if #self.timeline == 0 and tl then self:loadFrom(tl) end
	self.curSnap = self:findSnap(f)
	if self.curSnap then self:apply(self.curSnap) end
end

function Lighting:onPlayTo(tl, f)
	if not self.enabled or self.control ~= "test" then return end
	if f ~= self.curFrame then
		self.curFrame = f
		local s = self:findSnap(f)
		if s ~= self.curSnap or self.dirty then
			self.curSnap = s
			if self.curSnap then self:apply(self.curSnap) end
		end
	end
end

function Lighting:lateRender()
	if not self.enabled or not self.dirty then return end
	if (self.control == "paused" or self.control == "test") and self.curSnap then self:apply(self.curSnap) end
end

function Lighting:onPause()
	if not self.enabled then return end
	self.control = "paused"
	self.curSnap = self:findSnap(self.curFrame)
	if self.curSnap then self:apply(self.curSnap) end
end

-- recording continues from frame f
function Lighting:onBeginRecording(tl, f)
	if not self.enabled then return end
	self.control = "record"
	self.curFrame = f or self.curFrame
	self.curSnap = nil
	self.dirty = true
	if f and f > 0 then self:trim(f) end
end

function Lighting:onCut(tl, n) self:trim(n) end
function Lighting:onReset() self:clear() end
function Lighting:onLoaded(tl)
	self:clear()
	self:loadFrom(tl)
end

-- Idle (key 1) and the end of a test: HappaTAS stops controlling the lighting and leaves it exactly as it is
-- (V2.38.14). Turning Sync Lighting off / unloading still puts the lighting from before the TAS back
function Lighting:onRelease()
	self.control = "none"
	self.curSnap = nil
end

return Lighting
