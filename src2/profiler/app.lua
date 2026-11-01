-- ================================================================================================
--  PROFILER APP  (HappaTAS 3 phase 6): V2.38.17's MicroProfiler (profiler/profiler) on HappaTAS 3.
--  * The names V2's profiler took from V2's script come from here: settings by V2 name, status messages,
--    dumps into the place's folder, the MicroProfiler key, the client object / button counts, its
--    ScreenGui straight in CoreGui (gethui otherwise), the profiler's own lifecycle.
--  * While it's open the kernel feeds it: each pipeline stage is the HappaTAS scope (PreRender also the
--    frame's start and the end of HappaTAS's PreRender work, V2's FrameBegin / FrameEnd), the engine's
--    handlers are Record (recording) / Playback (Test), the interface's are Stats UI, the client objects,
--    buttons and cursor (plugin hooks and guarded calls) are V2's scopes of those names. Closed, nothing is
--    fed (the kernel's hooks are nil).
--  * Its config and presets live in the settings file's `profiler` table; the TAS timeline reads the run in
--    use and seeks with Modes:seek (V2's OnScrub).
-- ================================================================================================
local CONFIG = import("config")
local Env = import("platform/env")
local Files = import("platform/files")
local Settings = import("engine/settings")
local Plugins = import("engine/plugins")
local MicroProfiler = import("profiler/profiler")

local ProfilerApp = {}

local NAME, DISPLAY_ORDER = "HappaProfiler", 2147482000
local TEXT_EXT = { txt = true, csv = true, html = true } -- (V2's Store.WriteText types)
-- V2's scope names for HappaTAS 3's plugins (by plugin name) and guarded objects (by guard name)
local SCOPE = { cursor = "Cursor", clientobjects = "Client Objects", clientObjects = "Client Objects", buttons = "Buttons" }

local function keyOf(name)
	local r = Settings.byV2[name]
	return r and r.key
end

local function hui()
	if not Env.gethui then return nil end
	local ok, h = pcall(Env.gethui)
	return ok and h or nil
end

local function tryParent(gui, parent)
	if not parent then return false end
	local ok = pcall(function() gui.Parent = parent end)
	return ok and gui.Parent == parent
end

function ProfilerApp.start(E)
	local life = E.life:scope("profiler")
	local s = E.settings
	local ctx = {}
	ctx.Settings = {
		Get = function(name) return s:get(keyOf(name)) end,
		Set = function(name, v) s:set(keyOf(name), v) end,
		On = function(name) return s:on(keyOf(name)) end,
		Changed = function(name, f) life:own(s:changed(keyOf(name), f)) end,
	}
	ctx.Core = { SetStatus = function(text) E.bus:emit("status", text) end }
	ctx.Store = {
		-- (V2's Store.WriteText: <place folder>/<name>.<txt | csv | html>; true, path or false, why)
		WriteText = function(fileName, text, ext)
			if not E.files.available then return false, "Saving is unavailable" end
			local clean = Files.cleanName(fileName)
			if not clean then return false, "Invalid name" end
			ext = ext or "txt"
			if not TEXT_EXT[ext] then return false, "Invalid file type" end
			local root = E.library.root
			if not E.files:makeFolder(root) then return false, "The folder could not be made" end
			local path = root .. "/" .. clean .. "." .. ext
			local ok, err = E.files:write(path, text)
			if not ok then return false, tostring(err) end
			return true, path
		end,
	}
	ctx.Controls = { Get = function() return E.controls:get("microProfiler") end }
	ctx.ClientObjects = { Counts = function() return E.co:counts() end }
	ctx.Buttons = { Count = function() return E.buttons:count() end }
	ctx.UI = {
		-- (V2's UI.Overlay: a ScreenGui above Roblox's top bar, straight in CoreGui, gethui otherwise)
		Overlay = function(name, order)
			local sg = Instance.new("ScreenGui")
			sg.Name = name
			sg.ResetOnSpawn = false
			sg.IgnoreGuiInset = true
			pcall(function() sg.AutoLocalize = false end)
			pcall(function() sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling end)
			pcall(function() sg.DisplayOrder = order end)
			if Env.protectgui then pcall(Env.protectgui, sg) end
			if not tryParent(sg, Env.svc("CoreGui")) and not tryParent(sg, hui()) then
				sg:Destroy()
				return nil
			end
			life:own(sg)
			return sg
		end,
	}
	ctx.Janitor = { add = function(x) life:own(x) end }
	ctx.on = function(signal, fn) return life:connect(signal, fn) end
	ctx.reportError = function(where, err) E.pipe.errs:report("profiler " .. tostring(where), err) end
	ctx.VERSION = CONFIG.VERSION

	-- (a re-run: the old copy's profiler goes before this one is built)
	for _, root in ipairs({ Env.svc("CoreGui"), hui() }) do
		local old = root and root:FindFirstChild(NAME)
		if old and old:IsA("ScreenGui") then pcall(function() old:Destroy() end) end
	end

	local P = MicroProfiler.new(ctx)
	E.profiler, E.profilerCtx = P, ctx

	-- the TAS timeline: the run in use as V2's frames table (#data, data[i].FrameTime / TotalTime) and V2's OnScrub
	local tl = E.tl
	local view = setmetatable({}, {
		__len = function() return tl:count() end,
		__index = function(_, i)
			if type(i) ~= "number" or i < 1 or i > tl:count() or i % 1 ~= 0 then return nil end
			return { FrameTime = tl:get("FrameTime", i, 1), TotalTime = tl:get("TotalTime", i, 1) }
		end,
	})
	P.GetTAS = function() return view, E.frame, tl.version end
	P.OnScrub = function(target) E.modes:seek(target) end
	P.SaveConfig = function() E.settingsFile:setProfiler(P.SerializeConfig()) end

	-- the kernel's feed, only while the profiler is open (V2's Begin / End sites, see the header)
	local depth = {}
	local function scopeBegin(name)
		local d = (depth[name] or 0) + 1
		depth[name] = d
		if d == 1 then P.Begin(name) end
	end
	local function scopeEnd(name)
		local d = (depth[name] or 1) - 1
		depth[name] = d
		if d == 0 then P.End(name) end
	end
	local entries = {} -- (the scope each running handler began: a mode change inside it ends the same one)
	local pipeHook = {
		stageBegin = function(stage, dt)
			if stage == "PreRender" then P.FrameBegin(dt) end
			P.Begin("HappaTAS")
		end,
		stageEnd = function(stage)
			P.End("HappaTAS")
			if stage == "PreRender" then P.FrameEnd() end
		end,
		entryBegin = function(e)
			local name = false
			if e.module == "engine" then
				if E.mode == 3 then name = "Playback" elseif E.mode == 2 and not E.paused then name = "Record" end
			elseif e.module == "ui" then
				name = "Stats UI"
			end
			entries[#entries + 1] = name
			if name then scopeBegin(name) end
		end,
		entryEnd = function()
			local name = entries[#entries]
			entries[#entries] = nil
			if name then scopeEnd(name) end
		end,
	}
	local plugHook = {
		begin = function(name)
			local scope = SCOPE[name]
			if scope then scopeBegin(scope) end
		end,
		finish = function(name)
			local scope = SCOPE[name]
			if scope then scopeEnd(scope) end
		end,
	}
	local function feed(on)
		table.clear(depth)
		table.clear(entries)
		E.pipe.profiler = on and pipeHook or nil
		Plugins.prof = on and plugHook or nil
	end
	local setVisible = P.SetVisible
	P.SetVisible = function(v)
		setVisible(v)
		feed(P.active == true)
	end

	-- the MicroProfiler key (even when the game processed it) and Ctrl+P (V2 p18_core)
	local uis = Env.svc("UserInputService")
	life:connect(uis.InputBegan, function(inp)
		if E.typing:active(inp) then return end
		if E.controls:matches(inp, "microProfiler") then
			s:set("showMicroProfiler", s:on("showMicroProfiler") and 0 or 1)
			return
		end
		if inp.KeyCode == Enum.KeyCode.P and P.active
			and (uis:IsKeyDown(Enum.KeyCode.LeftControl) or uis:IsKeyDown(Enum.KeyCode.RightControl)) then
			P.TogglePause()
		end
	end)

	life:own(function()
		feed(false)
		if P.active then pcall(setVisible, false) end
	end)
	local saved = E.settingsFile and E.settingsFile.profiler
	if type(saved) == "table" then pcall(P.LoadConfig, saved) end
	P.Start()
	return P
end

return ProfilerApp
