-- Trace adapter for V2.38.16 (the reference build): the scenario's view of the script, through __T.
A = {}
local C
function A.boot()
	local ok = boot(30)
	C = __T.Core.State
	local guard = 0
	while not (C.HRP and C.Humanoid) and guard < 200 do M.step(1 / 60); guard = guard + 1 end
	return ok and C.HRP ~= nil
end
function A.mode() return C.mode end
function A.frame() return C.frame end
function A.paused() return C.paused end
function A.count() return #__T.Core.GetTAS() end
function A.frameV2(i) return __T.Core.GetTAS()[i] end
function A.frames() return __T.Core.GetTAS() end
function A.setSetting(name, v) __T.Settings.Set(name, v) end
function A.char() return C.HRP, C.Humanoid end
-- Optimize asks for a second press while its status text fades (the first call waits)
function A.optimizeTwice()
	M.resume(coroutine.create(function() C.inputs.Optimize() end))
	M.steps(2)
	M.resume(coroutine.create(function() C.inputs.Optimize() end))
	M.steps(120)
end
function A.merge(frames, where) __T.Core.SetTAS(frames, where) end
-- the merge stats button: completes when the root is close enough to the other run's start, else cancels
function A.mergeClick() C.MergeStats.MouseButton1Click:Fire() end
-- saving and loading (V2's Store and codec); the saved file is printed for the HappaTAS 3 side (part C)
local function hex(s) return (s:gsub(".", function(c) return string.format("%02x", string.byte(c)) end)) end
function A.save(name)
	assert(__T.Store.SaveSlot(name, __T.Core.GetTAS()))
	M.realPrint("V2FILE " .. hex(M.fs[__T.Store.SlotPath(name)]))
end
function A.clearRun() __T.Core.SetTAS({}) end
function A.load(name)
	local ok, frames = __T.Store.LoadSlot(name)
	assert(ok, frames)
	__T.Core.SetTAS(frames)
end
function A.loadV2File() A.load("traced") end
