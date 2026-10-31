-- Trace adapter for HappaTAS 3: the scenario's view of the script, through the debug handle.
A = {}
local E
local Settings
function A.boot()
	local ok = boot(30)
	E = getgenv().__HappaTAS3_T.engine
	Settings = __T3("engine/settings")
	local guard = 0
	while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
	return ok and E.char.hrp ~= nil
end
function A.mode() return E.mode end
-- (phase 5a bench) the Settings window, and transitions without a click (the window is under the mouse)
function A.openMenu() E.ui.wm:open("settings") end
function A.closeMenu() E.ui.wm:close("settings") end
function A.request(action) E.modes:request(action) end
function A.frame() return E.frame end
function A.paused() return E.paused end
function A.count() return E.tl:count() end
function A.frameV2(i) return E.tl:toV2(i) end
function A.frames() return E.tl:toV2All() end
function A.setSetting(name, v) E.settings:set(Settings.byV2[name].key, v) end
function A.char() return E.char.hrp, E.char.hum end
function A.coReady() return E.co:isReady() end
function A.coCount() return (E.co:counts()) end
function A.optimizeTwice()
	E.modes:optimize()
	M.steps(2)
	E.modes:optimize()
	M.steps(120)
end
function A.merge(frames, where) E.mergeRun:startMerge(frames, where) end
function A.mergeClick() E.mergeRun:finishMerge() end
-- saving and loading (HappaTAS 3's persist; the work runs on its thread over the next frames, which the
-- scenario steps on both sides); part C loads the file the V2 side saved (V2FILE_DATA, tools/trace3.sh)
function A.save(name) assert(E.persist:save(name)) end
function A.clearRun() E.modes:setRun({}) end
function A.load(name) assert(E.persist:load(name .. ".tas")) end
function A.loadV2File()
	if V2FILE_DATA then
		writefile(E.library.root .. "/tracedV2.tas", V2FILE_DATA)
		A.load("tracedV2")
	else
		A.load("traced")
	end
end
-- the save bench (tests3/bench/save.lua): the run into the timeline first (not timed), then build + safe save,
-- read + load into a fresh timeline
function A.setFrames(frames) E.modes:setRun(frames) end
function A.saveWork(name)
	local data = __T3("persist/run").build(E.tl, name)
	assert(E.library:save(name, "", data))
	return #data
end
function A.loadWork(name)
	local data = assert(E.library:read(name .. ".tas"))
	local fresh = __T3("engine/timeline").newLike(E.tl)
	__T3("persist/run").load(fresh, data)
	return fresh:count()
end
