-- ================================================================================================
--  CLASSIC STATS  (HappaTAS 3 ui, spec 8.5): V2.38.17's Idle / Create / Test stats panels (p18_core.lua SS)
--  in the classic interface, with the Inspector's values (ui/win/inspectorvalues: the same numbers) in V2's
--  lines (" Root Position: x, y, z"). One panel by mode while its Show Stats setting is on; Test at another
--  playback speed always shows (V2's rule); Create's panel is darker while paused. Stats Text Size sizes the
--  panels as V2's SetStatsSize did. Updated as the Inspector is: 5 times a second while the character can
--  move (skipped when nothing moved), on a change while paused; only while Classic is live. A text is
--  written only when it changes.
-- ================================================================================================
local IV = import("ui/win/inspectorvalues")

local ClassicStats = {}
ClassicStats.__index = ClassicStats

local FAST_EVERY, PERF_EVERY = 12, 1
local SHOW = { "showStatsIdle", "showStatsCreate", "showStatsTest" }
local PANEL = { "IdleStats", "CreateStats", "TestStats" }
-- V2's rows: { panel row name, label, IV key }
local ROWS = {
	IdleStats = { { "1", " Frame Time: ", "frameTime" }, { "2", " Root Position: ", "position" }, { "3", " Root Rotation: ", "rotation" },
		{ "4", " Root Linear Velocity: ", "velocity" }, { "5", " Root Angular Velocity: ", "angular" },
		{ "6", " Camera Rotation: ", "cameraRotation" }, { "7", " Humanoid State: ", "state" }, { "8", " Zoom: ", "zoom" } },
	CreateStats = { { "2", " Frame Time: ", "frameTime" }, { "3", " Total Time: ", "totalTime" }, { "4", " Root Position: ", "position" },
		{ "5", " Root Rotation: ", "rotation" }, { "6", " Root Linear Velocity: ", "velocity" }, { "7", " Root Angular Velocity: ", "angular" },
		{ "8", " Camera Rotation: ", "cameraRotation" }, { "9", " Humanoid State: ", "state" }, { "91", " Zoom: ", "zoom" },
		{ "92", " Keys: ", "keys" }, { "93", " Mouse: ", "mouse" } },
	TestStats = { { "1", " Time: ", "totalTime" }, { "2", " Playback Speed: ", "speed" }, { "3", " Keys: ", "keys" }, { "4", " Mouse: ", "mouse" } },
}

function ClassicStats.new(classic)
	local E = classic.E
	local self = setmetatable({ classic = classic, E = E, b = classic.byPath, last = {}, lastVis = {}, memo = {}, values = {},
		want = {}, perf = { dt = 0, fps = 0, ms = 0 }, tick = 0, still = {}, perfT = 0, perfFrames = 0 }, ClassicStats)
	for _, list in pairs(ROWS) do
		for _, r in ipairs(list) do self.want[r[3]] = true end
	end
	local s = E.settings
	for _, key in ipairs({ "showStatsIdle", "showStatsCreate", "showStatsTest", "playbackSpeed" }) do
		classic.offs[#classic.offs + 1] = s:changed(key, function() self:update(true) end)
	end
	classic.offs[#classic.offs + 1] = s:changed("statsTextSize", function(v) self:size(v) end)
	classic.offs[#classic.offs + 1] = E.state:watch("mode", function() self:update(true) end)
	classic.offs[#classic.offs + 1] = E.bus:on("uiShown", function() self:follow() end)
	local uis = classic.uis
	for _, sig in ipairs({ uis.InputBegan, uis.InputEnded }) do
		local conn = classic.ui.life:connect(sig, function() self.keyed = true end)
		classic.offs[#classic.offs + 1] = function() classic.ui.life:drop(conn) end
	end
	classic.offs[#classic.offs + 1] = function() if self.off then self.off(); self.off = nil end end
	self:size(s:get("statsTextSize"))
	self:follow()
	return self
end

local function setText(self, label, text)
	if self.last[label] ~= text then
		self.last[label] = text
		label.Text = text
	end
end
local function setVisible(self, f, on)
	if self.lastVis[f] ~= on then
		self.lastVis[f] = on
		f.Visible = on
	end
end

-- V2's SetStatsSize (the Merge Stats panel too)
function ClassicStats:size(textSize)
	local b = self.b
	for _, f in ipairs({ b.IdleStats, b.CreateStats, b.TestStats, b.MergeStats }) do
		local rows = 0
		for _, x in ipairs(f:GetChildren()) do
			if x:IsA("TextLabel") then
				rows = rows + 1
				x.Size = UDim2.new(1, 0, 0, 18 * textSize / 11)
				x.TextSize = textSize
			end
		end
		f.Size = UDim2.new(0, 240 * textSize / 11, 0, rows * 18 * textSize / 11)
		if f.Name == "MergeStats" then f.Position = UDim2.new(1, -10, 1, -180 * textSize / 11 - 20) end
	end
end

-- the per-frame handler only while Classic is live
function ClassicStats:follow()
	local live = self.classic.ui.live == "Classic"
	if live and not self.off then
		self.off = self.E.pipe:add("PreRender", 235, "ui.classic.stats", function(dt) self:step(dt) end, "ui")
		self:update(true)
	elseif not live and self.off then
		self.off()
		self.off = nil
	end
end

-- whether anything a row shows can have changed (the Inspector's rule)
function ClassicStats:moved()
	local E, s = self.E, self.still
	local hrp = E.char and E.char.hrp
	local pos = hrp and hrp.Position
	local cam = workspace.CurrentCamera
	local cf = cam and cam.CFrame
	local m = E.inputs.uis:GetMouseLocation()
	local n = E.tl:count()
	local same = not self.keyed and s.pos == pos and s.cf == cf and s.m == m and s.mode == E.mode and s.frame == E.frame and s.n == n
	s.pos, s.cf, s.m, s.mode, s.frame, s.n = pos, cf, m, E.mode, E.frame, n
	self.keyed = false
	return not same
end

function ClassicStats:step(dt)
	local E = self.E
	self.perfT = self.perfT + (dt or 0)
	self.perfFrames = self.perfFrames + 1
	self.perf.dt = dt or 0
	if self.perfT >= PERF_EVERY then
		self.perf.fps = self.perfFrames / self.perfT
		self.perfT, self.perfFrames = 0, 0
	end
	if E.mode == 2 and E.paused then
		local tl = E.tl
		local key = E.frame .. ":" .. tl:count() .. ":" .. tl.version .. ":" .. (tl.edits or 0)
		if key == self.pausedKey then return end
		self.pausedKey = key
	else
		self.pausedKey = nil
		self.tick = self.tick + 1
		if self.tick % FAST_EVERY ~= 0 or not self:moved() then return end
	end
	self:update(false)
end

-- which panel shows, and its rows (force: every text checked again)
function ClassicStats:update(force)
	local E, b = self.E, self.b
	if self.classic.ui.live ~= "Classic" then return end
	local mode = E.mode or 1
	local s = E.settings
	local shown = s:on(SHOW[mode] or "showStatsIdle") or (mode == 3 and s:get("playbackSpeed") ~= 1)
	for i, name in ipairs(PANEL) do setVisible(self, b[name], shown and i == mode) end
	if not shown then return end
	if force then self.pausedKey = nil end
	local ok, v = pcall(IV.values, E, self.perf, self.want, self.memo, self.values)
	if not ok then return end
	local panel = PANEL[mode]
	for _, r in ipairs(ROWS[panel]) do
		setText(self, b[panel .. "." .. r[1]], r[2] .. tostring(v[r[3]] or "-"))
	end
	if mode == 2 then
		local f = E.paused and E.frame or E.tl:count()
		local sh = s:on("speedHack") and s:get("speedHackSpeed") or 1
		setText(self, b["CreateStats.1"], " Frame: " .. f .. ((sh ~= 1) and ("   (Speed Hack " .. sh .. "x)") or ""))
		local bt = E.paused and 0.1 or 0.2
		if b.CreateStats.BackgroundTransparency ~= bt then b.CreateStats.BackgroundTransparency = bt end
	end
end

return ClassicStats
