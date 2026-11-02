-- ================================================================================================
--  LIVE CRITERIA (test tool, never shipped): spec criterion 2 in a real client. Every run in the place folder
--  that V2.38.17 can open is opened and Tested by V2 and by HappaTAS 3. Load it through Real with
--      local Crit = loadfile("HappaTasTest/criteria3.lua")()
--  Crit.opened(kind, path, name): the run as the script opened it: { n, len, pos = { Vector3 per frame },
--      ft = { FrameTime per frame } }. kind "v2" needs a V2 build with getgenv().__V2T (tools/live/v2expose.sh,
--      Core and Store included); "h3" a HappaTAS 3 build with CONFIG.Debug on (getgenv().__HappaTAS3_T).
--  Crit.tested(kind, path, name): the same, then Test: { seconds, last = root position when it ended, frames
--      = the frames the script passed }.
--  Crit.compare(a, b): frame count, length, worst root distance and worst FrameTime difference of two opened runs.
--  The script is unloaded after each call; the Backpack hotbar is off while it runs and put back.
--  Test and Idle go through each script's own mode calls (V2: C.inputs.Test / Idle, HappaTAS 3:
--  E.modes:request), not keys: both scripts rightly ignore keys while the Roblox menu is open.
-- ================================================================================================
local Crit = {}
local RS = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local function unloadAll()
	local g = getgenv()
	if g.__HappaTAS3 then pcall(g.__HappaTAS3.Unload) end
	if g.__HappaTAS then pcall(g.__HappaTAS.Unload) end
	g.__HappaTAS3_T, g.__V2T = nil, nil
	task.wait(1.5)
end

local function hotbar(on) pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, on) end

-- loads the script and the run; returns the opened run, a function giving the frame being played and one
-- switching the mode ("test" / "idle")
local function open(kind, path, name)
	unloadAll()
	assert(loadfile(path, "=Under test"))()
	task.wait(2)
	local out = { pos = {}, ft = {} }
	if kind == "v2" then
		local T = assert(getgenv().__V2T, "no __V2T: build the V2 copy with tools/live/v2expose.sh")
		local ok, data = T.Store.LoadSlot(name)
		assert(ok, "V2 could not open " .. name .. ": " .. tostring(data))
		for i, fd in ipairs(data) do
			local c = fd.Cframe
			out.pos[i] = c and Vector3.new(c[1], c[2], c[3]) or false
			out.ft[i] = fd.FrameTime
		end
		out.n, out.len = #data, data[#data] and data[#data].TotalTime
		T.Core.SetTAS(data)
		task.wait(0.5)
		return out, function() return T.C.frame end, function(m)
			if m == "test" then T.C.inputs.Test() else T.C.inputs.Idle() end
		end
	end
	local E = assert(getgenv().__HappaTAS3_T, "no __HappaTAS3_T: the HappaTAS 3 copy needs CONFIG.Debug on").engine
	local ok, why = E.persist:load(name .. ".tas")
	assert(ok, "HappaTAS 3 could not open " .. name .. ": " .. tostring(why))
	local t0 = os.clock()
	while (E.busy or not E.loaded) and os.clock() - t0 < 30 do task.wait(0.1) end
	assert(E.loaded and E.loaded.path == name .. ".tas", "HappaTAS 3 did not finish loading " .. name)
	local tl = E.tl
	for i = 1, tl:count() do
		out.pos[i] = Vector3.new(tl:get("Cframe", i, 1), tl:get("Cframe", i, 2), tl:get("Cframe", i, 3))
		out.ft[i] = tl:get("FrameTime", i, 1)
	end
	out.n = tl:count()
	if out.n > 0 then out.len = tl:get("TotalTime", out.n, 1) end
	return out, function() return E.frame end, function(m) E.modes:request(m) end
end

function Crit.opened(kind, path, name)
	hotbar(false)
	local ok, res = pcall(open, kind, path, name)
	unloadAll()
	hotbar(true)
	if not ok then error(res, 0) end
	return res
end

function Crit.tested(kind, path, name)
	hotbar(false)
	local ok, res = pcall(function()
		local run, frameNow, setMode = open(kind, path, name)
		local hrp = game.Players.LocalPlayer.Character.HumanoidRootPart
		local seen, lastFrame = 0, -1
		local conn = RS.PreSimulation:Connect(function()
			local f = frameNow()
			if f ~= lastFrame then seen = seen + 1; lastFrame = f end
		end)
		local t0 = os.clock()
		setMode("test")
		local limit = (run.len or 0) + 5
		while os.clock() - t0 < limit and (frameNow() or 0) < run.n do task.wait() end
		task.wait(0.2)
		run.seconds = os.clock() - t0
		run.last = hrp.Position
		run.frames = seen
		run.endFrame = frameNow()
		conn:Disconnect()
		setMode("idle")
		task.wait(0.3)
		return run
	end)
	unloadAll()
	hotbar(true)
	if not ok then error(res, 0) end
	return res
end

function Crit.compare(a, b)
	local worstPos, worstFt = 0, 0
	for i = 1, math.min(a.n, b.n) do
		local pa, pb = a.pos[i], b.pos[i]
		if pa and pb then worstPos = math.max(worstPos, (pa - pb).Magnitude) end
		if a.ft[i] and b.ft[i] then worstFt = math.max(worstFt, math.abs(a.ft[i] - b.ft[i])) end
	end
	return { n = a.n .. " / " .. b.n, len = string.format("%.4f / %.4f", a.len or -1, b.len or -1),
		worstPos = worstPos, worstFt = worstFt }
end

return Crit
