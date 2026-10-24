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
function A.frame() return E.frame end
function A.paused() return E.paused end
function A.count() return E.tl:count() end
function A.frameV2(i) return E.tl:toV2(i) end
function A.frames() return E.tl:toV2All() end
function A.setSetting(name, v) E.settings:set(Settings.byV2[name].key, v) end
function A.char() return E.char.hrp, E.char.hum end
function A.optimizeTwice()
	E.modes:optimize()
	M.steps(2)
	E.modes:optimize()
	M.steps(120)
end
function A.merge(frames, where) if E.modes.merge then E.modes:merge(frames, where) end end
function A.mergeClick() if E.modes.mergeClick then E.modes:mergeClick() end end
