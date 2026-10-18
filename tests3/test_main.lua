-- ================================================================================================
-- HappaTAS 3, phase 1: start, re-run over an older copy, Unload (nothing left behind)
-- ================================================================================================
local RS = M.services.RunService
local genv = getgenv()
local function counts() return { RS.PreRender:Count(), RS.PreSimulation:Count(), RS.PostSimulation:Count() } end
local function lateBound()
	for _, b in ipairs(M.binds) do if b.name == "HappaTAS3Late" then return true end end
	return false
end
local before = counts()

-- an older HappaTAS (V2.38.x) is still running
local oldUnloaded = false
genv.__HappaTAS = { Version = "V2.38.16", Unload = function() oldUnloaded = true end }

section("start")
check(boot(3), "boots")
check(oldUnloaded, "the older V2 copy was unloaded")
local h = genv.__HappaTAS3
check(type(h) == "table" and h.Version == "3.0.0-dev", "handle published with the version")
local T = genv.__HappaTAS3_T
check(type(T) == "table" and T.pipe ~= nil and T.state ~= nil, "debug tables published (test builds have Debug on)")
eq(T.state:get("mode"), "Idle", "initial mode Idle")
local ticks = 0
T.pipe:add("PreRender", 50, "ticker", function() ticks = ticks + 1 end)
M.steps(3)
eq(ticks, 3, "a pipeline handler runs once a frame")
eq(RS.PreRender:Count(), before[1] + 1, "exactly one PreRender connection")

section("running the script again unloads the first copy")
M.resume(coroutine.create(function() __SCRIPT__() end))
M.steps(2)
local ticksAfter = ticks
M.steps(3)
eq(ticks, ticksAfter, "the first copy's handlers stopped")
eq(RS.PreRender:Count(), before[1] + 1, "still exactly one PreRender connection")
local h2, T2 = genv.__HappaTAS3, genv.__HappaTAS3_T
check(h2 ~= h and T2 ~= T, "the new copy published its own handle")

section("Unload from inside a frame handler")
local afterUnload = 0
T2.pipe:add("PreRender", 1, "unloader", function() h2.Unload() end)
T2.pipe:add("PreRender", 2, "after", function() afterUnload = afterUnload + 1 end)
M.step(1 / 60)
eq(afterUnload, 0, "the rest of that frame is skipped")
local c = counts()
eq(c[1], before[1], "PreRender connections back to before")
eq(c[2], before[2], "PreSimulation connections back to before")
eq(c[3], before[3], "PostSimulation connections back to before")
check(not lateBound(), "no late render-step bind")
eq(genv.__HappaTAS3, nil, "handle removed")
eq(genv.__HappaTAS3_T, nil, "debug tables removed")
local ok = pcall(h2.Unload)
check(ok, "Unload twice is fine")
M.steps(3)
eq(afterUnload, 0, "nothing runs after Unload")
finish()
