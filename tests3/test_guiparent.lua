-- needs: ui
-- ================================================================================================
-- HappaTAS 3: where the ScreenGuis go with Real's cloneref (a second reference to a service, never == to the
-- instance Parent gives back): the MicroProfiler straight in CoreGui, the interface in gethui() or, without it,
-- CoreGui. Found live in phase 6: a "gui.Parent == parent" check failed on the cloneref'd CoreGui and moved the
-- profiler under Roblox's top bar (headless mock, M.clonerefDistinct)
-- ================================================================================================
M.clonerefDistinct = true

section("the MicroProfiler in CoreGui")
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
E.settings:set("showMicroProfiler", 1)
M.steps(3)
local core = M.services.CoreGui
local sg = core:FindFirstChild("HappaProfiler")
check(sg ~= nil and sg.Parent == core, "straight in CoreGui (above Roblox's top bar)")
eq(M.hui and M.hui:FindFirstChild("HappaProfiler", true) or nil, nil, "not inside gethui()'s ScreenGui")
E.settings:set("showMicroProfiler", 0)
M.steps(3)

section("the interface without gethui: CoreGui")
M.noHui = true
check(boot(30), "runs again without gethui")
local ui = getgenv().__HappaTAS3_T.engine.ui
check(ui.root.refused ~= true, "not refused")
local root = core:FindFirstChild("TASUserInterface")
check(root ~= nil and root.Parent == core, "the interface in CoreGui")
eq(ui.root.parentName, "CoreGui", "parentName")
M.noHui = false
getgenv().__HappaTAS3.Unload()
M.steps(3)
finish()
