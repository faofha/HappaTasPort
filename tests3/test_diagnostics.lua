-- needs: ui
-- ================================================================================================
-- HappaTAS 3: the diagnostics report (Settings > Copy diagnostics): what it says, the clipboard or the file
-- when there is no clipboard, and that it reads only (headless mock)
-- ================================================================================================
local copied = nil
setclipboard = function(text) copied = text end
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local Diag = __T3("engine/diagnostics")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
for _ = 1, 120 do M.step(1 / 60) end

section("the report")
local text = Diag.report(E)
check(text:find("Version: 3.0.0", 1, true) ~= nil, "the version")
check(text:find("Executor functions present: ", 1, true) ~= nil, "the executor functions present")
check(text:find("setclipboard", 1, true) ~= nil, "the clipboard function is listed")
check(text:find("Frames %(last 10 s%): %d+, FPS 60") ~= nil, "frames and FPS: " .. (text:match("Frames[^\n]*") or "none"))
check(text:find("Physics (last 10 s):", 1, true) ~= nil, "the physics steps")
check(text:find("whole 1/240 s steps", 1, true) ~= nil, "how many are whole 1/240 s steps")
check(text:find("  speedHack = ", 1, true) ~= nil, "every setting")
check(text:find("Coyote now: enforcing false", 1, true) ~= nil, "the coyote state")
check(text:find("Speed hack now: wanted ", 1, true) ~= nil, "the speed hack state")
E.errs:report("test source", "boom 1")
text = Diag.report(E)
check(text:find("test source x1", 1, true) ~= nil, "errors per source")
check(text:find("[HappaTAS3] test source: boom 1", 1, true) ~= nil, "the last errors")
local guiN = #getgenv().__HappaTAS3.Diagnostics() > 100
check(guiN, "the handle's Diagnostics()")

section("read-only")
local hrp = E.char.hrp
local cf, v = hrp.CFrame, hrp.AssemblyLinearVelocity
local hum = E.char.hum
local ws, jp = hum.WalkSpeed, hum.JumpPower
local g = workspace.Gravity
Diag.report(E)
eq(hrp.CFrame, cf, "the root's CFrame")
eq(hrp.AssemblyLinearVelocity, v, "its velocity")
eq(hum.WalkSpeed, ws, "WalkSpeed")
eq(hum.JumpPower, jp, "JumpPower")
eq(workspace.Gravity, g, "gravity")

section("the button")
local ui = E.ui
ui.wm:close("inspector")
ui.wm:open("settings")
M.steps(2)
local sw = ui.settingsWin
check(sw and sw.diag ~= nil, "Settings has Copy diagnostics")
copied = nil
UIH.click(sw.diag.gui)
check(copied ~= nil and copied:find("HappaTAS diagnostics", 1, true) == 1, "copied to the clipboard")

section("no clipboard: a file in the HappaTasPort folder")
local Env = __T3("platform/env")
local saved = Env.setclipboard
Env.setclipboard = nil
local msg = Diag.share(E)
Env.setclipboard = saved
local path = msg:match("saved to (.+)$")
check(path ~= nil and path:find("^HappaTasPort/diagnostics%-") ~= nil, "saved: " .. tostring(msg))
check(path ~= nil and isfile(path) and readfile(path):find("HappaTAS diagnostics", 1, true) == 1, "the file has the report")

finish()
