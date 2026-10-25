-- ================================================================================================
--  SETTINGSFILE  (HappaTAS 3 persist): HappaTasPort/Settings3.json, HappaTAS 3's settings and keys
--    { format = "HappaTAS3 settings", version = 1, settings = { [key] = value }, controls = { [control] = key },
--      profiler = table? (the MicroProfiler's own data, kept for phase 6) }
--  The first start converts V2's HappaTasPort/Settings.json (V2 names -> keys; names HappaTAS 3 doesn't
--  have, the old sound settings too, are left out; values sanitised like V2) and writes Settings3.json.
--  Settings.json itself is never written: V2 (wow) still uses it until the switch-over.
--  A Settings3.json that can't be read is kept as Settings3.damaged.json. Changes are saved together 0.4 s
--  after the first one (like V2's queueSave), and at once on Unload when a save is waiting.
-- ================================================================================================
local Env = import("platform/env")
local Settings = import("engine/settings")
local Controls = import("engine/controls")
local Keys = import("engine/keys")

local SettingsFile = {}
SettingsFile.__index = SettingsFile

local ROOT = "HappaTasPort"
local V3_PATH = ROOT .. "/Settings3.json"
local V2_PATH = ROOT .. "/Settings.json"
local DAMAGED = ROOT .. "/Settings3.damaged.json"
local FORMAT = "HappaTAS3 settings"
local DELAY = 0.4

function SettingsFile.new(files, settings, controls, life)
	local self = setmetatable({ files = files, settings = settings, controls = controls, http = Env.svc("HttpService"),
		queued = false, loading = false, closed = false, profiler = nil }, SettingsFile)
	local offs = {
		settings:onAny(function() self:queue() end),
		controls:changed(function() self:queue() end),
	}
	if life then
		life:own(function()
			self:flush()
			self.closed = true
			for _, off in ipairs(offs) do off() end
		end)
	end
	return self
end

local function decode(self, raw)
	if not raw or not self.http then return nil end
	local ok, t = pcall(self.http.JSONDecode, self.http, raw)
	if ok and type(t) == "table" then return t end
	return nil
end

local function setKey(controls, control, keyName)
	if type(keyName) == "string" and (keyName == "None" or Keys.isValid(keyName)) then controls:set(control, keyName) end
end

-- which file the values came from: "v3", "v2" (converted, Settings3.json written) or "defaults"
function SettingsFile:load()
	local files, settings, controls = self.files, self.settings, self.controls
	self.loading = true
	local source = "defaults"
	local raw3 = files:read(V3_PATH)
	local t3 = decode(self, raw3)
	if t3 and t3.format == FORMAT then
		for key, v in pairs(type(t3.settings) == "table" and t3.settings or {}) do settings:set(key, v) end
		for control, keyName in pairs(type(t3.controls) == "table" and t3.controls or {}) do setKey(controls, control, keyName) end
		self.profiler = type(t3.profiler) == "table" and t3.profiler or nil
		source = "v3"
	else
		if raw3 then
			files:write(DAMAGED, raw3)
			files:delete(V3_PATH)
		end
		local t2 = decode(self, files:read(V2_PATH))
		if t2 then
			for name, v in pairs(type(t2.settings) == "table" and t2.settings or {}) do
				local def = Settings.byV2[name]
				if def then settings:set(def.key, v) end
			end
			for name, keyName in pairs(type(t2.controls) == "table" and t2.controls or {}) do
				local ctl = Controls.byV2[name]
				if ctl then setKey(controls, ctl.key, keyName) end
			end
			self.profiler = type(t2.profiler) == "table" and t2.profiler or nil
			source = "v2"
		end
	end
	self.loading = false
	if source == "v2" then self:write() end
	return source
end

function SettingsFile:write()
	if not self.files.available or not self.http then return false end
	local out = { format = FORMAT, version = 1, settings = table.clone(self.settings.values),
		controls = table.clone(self.controls.values), profiler = self.profiler }
	local ok, json = pcall(self.http.JSONEncode, self.http, out)
	if not ok then return false end
	self.files:makeFolder(ROOT)
	return (self.files:write(V3_PATH, json))
end

-- one save DELAY seconds after the first change (the ones after it ride along)
function SettingsFile:queue()
	if self.loading or self.closed or self.queued then return end
	self.queued = true
	task.delay(DELAY, function()
		if self.queued and not self.closed then
			self.queued = false
			self:write()
		end
	end)
end

-- the waiting save, now
function SettingsFile:flush()
	if self.queued then
		self.queued = false
		self:write()
	end
end

function SettingsFile:setProfiler(t)
	self.profiler = t
	self:queue()
end

return SettingsFile
