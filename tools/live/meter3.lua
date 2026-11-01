-- ================================================================================================
--  LIVE METER (test tool, never shipped): how much each script costs the client per frame, measured the same
--  way for V2.38.17 and HappaTAS 3. Load it through Real with
--      local Meter = loadfile("HappaTasTest/meter3.lua")()
--  Meter.compare(opts): V2 and HappaTAS 3 in alternating rounds. Every frame handler a script connects while
--      it loads (RunService signals' Connect / Once, BindToRenderStep) is wrapped and timed; the result is
--      us per frame by stage, median over the rounds, for recording, paused and Test.
--  Meter.sections(path, specsOf, seconds): exclusive time (a wrapper takes its children's time off its own)
--      of the functions specsOf(env) names, in the same three modes, for one script.
--  Both match V2's Settings.json to HappaTAS 3's choices for the run (the same world features, stats panels
--  on, no MicroProfiler; HappaTAS 3 in its Classic interface) and put both files back at the end, errors
--  included. The character goes back to the same spot before each run and walks the same way.
--  Keys go through VirtualInputManager with dzr's controls: 2 Create, E pause / unpause, 3 Test, 1 Idle.
-- ================================================================================================
local Meter = {}
local RS = game:GetService("RunService")
local http = game:GetService("HttpService")
local vim = game:GetService("VirtualInputManager")
local clock = os.clock
local SETTINGS2, SETTINGS3 = "HappaTasPort/Settings.json", "HappaTasPort/Settings3.json"

local function key(kc)
	vim:SendKeyEvent(true, kc, false, game)
	task.wait(0.05)
	vim:SendKeyEvent(false, kc, false, game)
	task.wait(0.3)
end

-- V2's file follows HappaTAS 3's settings for the run; returns a function that puts both files back
local function matchSettings()
	local orig2, orig3 = readfile(SETTINGS2), readfile(SETTINGS3)
	local t3 = http:JSONDecode(orig3)
	local s3 = t3.settings or {}
	local t2 = http:JSONDecode(orig2)
	local s2 = t2.settings or {}
	s2["Sync Client Objects"] = (s3.syncClientObjects == nil) and 1 or s3.syncClientObjects
	s2["Record Tool Actions"] = (s3.recordTools == nil) and 1 or s3.recordTools
	s2["Show Stats (Idle)"], s2["Show Stats (Create)"], s2["Show Stats (Test)"] = 1, 1, 1
	s2["Show MicroProfiler"] = 0
	s3.showStatsIdle, s3.showStatsCreate, s3.showStatsTest = 1, 1, 1
	s3.showMicroProfiler = 0
	s3.interface = "Classic"
	t2.settings, t3.settings = s2, s3
	writefile(SETTINGS2, http:JSONEncode(t2))
	writefile(SETTINGS3, http:JSONEncode(t3))
	return function()
		writefile(SETTINGS2, orig2)
		writefile(SETTINGS3, orig3)
	end
end

local function unloadAll()
	local g = getgenv()
	if g.__HappaTAS3 then pcall(g.__HappaTAS3.Unload) end
	if g.__HappaTAS then pcall(g.__HappaTAS.Unload) end
	g.__HappaTAS3_T, g.__V2T = nil, nil
	task.wait(1.5)
end

-- the character back on its start spot, standing
local function homeOf()
	local ch = game.Players.LocalPlayer.Character
	local hrp, hum = ch.HumanoidRootPart, ch.Humanoid
	local start = hrp.CFrame
	return function()
		hum:Move(Vector3.zero)
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.CFrame = start
		task.wait(0.5)
	end, hum
end

local function walk(hum, on)
	getgenv().__meterWalk = on
	if not on then return end
	task.spawn(function()
		while getgenv().__meterWalk do
			hum:Move(Vector3.new(0, 0, -1), true)
			RS.RenderStepped:Wait()
		end
		hum:Move(Vector3.zero)
	end)
end

local function median(list)
	table.sort(list)
	local n = #list
	if n == 0 then return 0 end
	if n % 2 == 1 then return list[(n + 1) / 2] end
	return (list[n / 2] + list[n / 2 + 1]) / 2
end

-- a script loaded, then recording / paused / Test, each measured by window(seconds) -> result
local function runModes(path, window, seconds, hum, onLoaded)
	assert(loadfile(path, "=Under test"))()
	task.wait(2)
	if onLoaded then onLoaded() end
	local out = {}
	key(Enum.KeyCode.Two)
	walk(hum, true)
	key(Enum.KeyCode.E)
	out.rec = window(seconds)
	key(Enum.KeyCode.E)
	walk(hum, false)
	task.wait(0.3)
	out.paused = window(seconds)
	key(Enum.KeyCode.Three)
	out.test = window(math.min(seconds, 2.5))
	task.wait(1)
	key(Enum.KeyCode.One)
	return out
end

-- ------------------------------------------------------------------------------------------------ compare
function Meter.compare(opts)
	opts = opts or {}
	local paths = { v2 = opts.v2 or "HappaTasTest/v2.lua", h3 = opts.h3 or "HappaTasTest/r.lua" }
	local rounds, seconds = opts.rounds or 3, opts.seconds or 3
	local acc, frames, on = {}, 0, false
	local function wrap(f, label)
		if type(f) ~= "function" then return f end
		return function(...)
			local t = clock()
			local r = table.pack(f(...))
			acc[label] = (acc[label] or 0) + clock() - t
			return table.unpack(r, 1, r.n)
		end
	end
	local idxOld, gameOld
	idxOld = hookmetamethod(RS.Heartbeat, "__index", function(self, k)
		local v = idxOld(self, k)
		if on and (k == "Connect" or k == "Once") and type(v) == "function" and checkcaller() then
			local name = tostring(self):gsub("^Signal ", "")
			return function(sg, f, ...) return v(sg, wrap(f, name), ...) end
		end
		return v
	end)
	gameOld = hookmetamethod(game, "__namecall", function(self, ...)
		if on and checkcaller() and getnamecallmethod() == "BindToRenderStep" then
			local a = table.pack(...)
			a[3] = wrap(a[3], "Late")
			return gameOld(self, table.unpack(a, 1, a.n))
		end
		return gameOld(self, ...)
	end)
	local hb = RS.Heartbeat:Connect(function() frames = frames + 1 end)
	local function window(sec)
		for k in pairs(acc) do acc[k] = nil end
		frames = 0
		task.wait(sec)
		local r, total = {}, 0
		for k, v in pairs(acc) do
			local us = v / math.max(1, frames) * 1e6
			r[k] = us
			total = total + us
		end
		r.total = total
		return r
	end
	local restore = matchSettings()
	local home, hum = homeOf()
	local runs = { v2 = {}, h3 = {} }
	local ok, err = pcall(function()
		unloadAll()
		for i = 1, rounds do
			for _, who in ipairs({ "v2", "h3" }) do
				home()
				on = true
				runs[who][i] = runModes(paths[who], window, seconds, hum)
				on = false
				unloadAll()
				if opts.progress then opts.progress(who .. " " .. i) end
			end
		end
	end)
	on = false
	walk(hum, false)
	hookmetamethod(RS.Heartbeat, "__index", idxOld)
	hookmetamethod(game, "__namecall", gameOld)
	hb:Disconnect()
	restore()
	home()
	if not ok then error(err, 0) end
	-- medians per script, mode and stage
	local out = {}
	for who, list in pairs(runs) do
		out[who] = {}
		for _, mode in ipairs({ "rec", "paused", "test" }) do
			local keys = {}
			for _, run in ipairs(list) do for k in pairs(run[mode]) do keys[k] = true end end
			local m = {}
			for k in pairs(keys) do
				local vals = {}
				for _, run in ipairs(list) do vals[#vals + 1] = run[mode][k] or 0 end
				local v = median(vals)
				if v >= 0.5 then m[k] = math.floor(v * 10 + 0.5) / 10 end
			end
			out[who][mode] = m
		end
	end
	return out
end

-- ------------------------------------------------------------------------------------------------ sections
-- specsOf(env) -> { { table, key, label }, ... }; env = { engine = HappaTAS 3's engine (debug build), v2 = V2's
-- exposed modules (tools/live/v2expose.sh) }
function Meter.sections(path, specsOf, seconds)
	local excl, stack, depth, frames = {}, {}, 0, 0
	local function wrapFn(fn, label)
		return function(...)
			depth = depth + 1
			stack[depth] = 0
			local t0 = clock()
			local r = table.pack(fn(...))
			local dt = clock() - t0
			local child = stack[depth]
			depth = depth - 1
			if depth > 0 then stack[depth] = stack[depth] + dt end
			excl[label] = (excl[label] or 0) + dt - child
			return table.unpack(r, 1, r.n)
		end
	end
	local hb = RS.Heartbeat:Connect(function() frames = frames + 1 end)
	local function window(sec)
		for k in pairs(excl) do excl[k] = nil end
		frames = 0
		task.wait(sec)
		local r = {}
		for k, v in pairs(excl) do
			local us = v / math.max(1, frames) * 1e6
			if us >= 1 then r[k] = math.floor(us * 10 + 0.5) / 10 end
		end
		return r
	end
	local restore = matchSettings()
	local home, hum = homeOf()
	local ok, res = pcall(function()
		unloadAll()
		home()
		return runModes(path, window, seconds or 3, hum, function()
			local g = getgenv()
			local env = { engine = g.__HappaTAS3_T and g.__HappaTAS3_T.engine, v2 = g.__V2T }
			for _, s in ipairs(specsOf(env)) do
				local t, k, label = s[1], s[2], s[3]
				if type(t) == "table" and type(rawget(t, k) or t[k]) == "function" then rawset(t, k, wrapFn(t[k], label)) end
			end
			if env.engine then env.engine.plugins.byHook = {} end
		end)
	end)
	walk(hum, false)
	hb:Disconnect()
	unloadAll()
	restore()
	home()
	if not ok then error(res, 0) end
	return res
end

-- every method of HappaTAS 3's engine objects (through their guards), its plugins' hooks, the pipeline's
-- entries and the kit objects' module table
function Meter.engineSpecs(env)
	local E = env.engine
	local specs, done = {}, {}
	local function rawOf(v)
		local mt = getmetatable(v)
		if mt and type(mt.__index) == "function" then
			for _, u in pairs(debug.getupvalues(mt.__index)) do if type(u) == "table" and u ~= v then return u end end
		end
		return v
	end
	for name, v in pairs(E) do
		if type(v) == "table" and not tostring(name):find("^ui") and name ~= "settings" and name ~= "bus" and name ~= "state" then
			local raw = rawOf(v)
			local cls = getmetatable(raw) and getmetatable(raw).__index
			if type(cls) == "table" and not done[cls] then
				done[cls] = true
				for k, f in pairs(cls) do
					if type(f) == "function" and k ~= "new" then specs[#specs + 1] = { raw, k, name .. ":" .. k } end
				end
			end
		end
	end
	for _, p in ipairs(E.plugins.list) do
		local cls = getmetatable(p) and getmetatable(p).__index
		if type(cls) == "table" and not done[cls] then
			done[cls] = true
			for k, f in pairs(cls) do
				if type(f) == "function" and k ~= "new" then specs[#specs + 1] = { p, k, p.name .. "." .. k } end
			end
		end
	end
	local pipe = getgenv().__HappaTAS3_T.pipe
	for stage, list in pairs(pipe.stages) do
		for _, e in ipairs(list) do specs[#specs + 1] = { e, "fn", "[" .. stage .. "] " .. tostring(e.name) } end
	end
	pipe.snaps = {}
	return specs
end

-- every function in V2's exposed module tables
function Meter.v2Specs(env)
	local specs = {}
	for name, t in pairs(env.v2) do
		for k, f in pairs(t) do
			if type(f) == "function" and type(k) == "string" then specs[#specs + 1] = { t, k, name .. "." .. k } end
		end
	end
	return specs
end

return Meter
