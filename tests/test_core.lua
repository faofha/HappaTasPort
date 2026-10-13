-- record -> pause -> playback through the real input handlers, with the MicroProfiler open
check(boot(30), "boots")
local P, S, Core = __T.Profiler, __T.Settings, __T.Core
local C = Core.State
local guard = 0
while not (C.HRP and C.Humanoid) and guard < 200 do M.step(1 / 60); guard = guard + 1 end
check(C.HRP ~= nil, "character loaded by the core")
S.Set("Show MicroProfiler", 1)
M.step(1 / 60)
local function click()
	local inp = M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin)
	M.services.UserInputService.InputBegan:Fire(inp, false)
end
section("create + record")
M.pressKey(Enum.KeyCode.Two); M.releaseKey(Enum.KeyCode.Two)
M.steps(5)
eq(Core.GetMode(), 2, "Create mode")
check(Core.IsPaused(), "starts paused")
click()
M.steps(3)
check(not Core.IsPaused(), "left click unpauses")
local hrp = C.HRP
hrp.AssemblyLinearVelocity = Vector3.new(16, 0, 0)
local x0 = hrp.Position.X
M.steps(120)
check(hrp.Position.X > x0 + 20, "character moved while recording")
click()
M.steps(3)
check(Core.IsPaused(), "left click pauses")
local n = Core.GetTAS(true)
check(n >= 110, "frames recorded (" .. n .. ")")
local U, I = P.Internals()
section("profiler timers saw the recording")
P.SetMode("Timers")
M.steps(8)
check(I.tim.layout ~= nil, "timers table built")
section("TAS Timeline with the real TAS while paused")
P.SetMode("Frame")
P.Menus[7].click(2)
M.steps(2)
check(I.tas.a ~= nil, "TAS timeline drawn")
local f0 = Core.GetFrame()
P.OnScrub(20)
M.steps(2)
eq(Core.GetFrame(), 20, "scrubbing the TAS timeline jumps to frame 20 while paused")
P.OnScrub(f0)
M.steps(2)
P.Menus[7].click(0)
section("playback")
hrp.AssemblyLinearVelocity = Vector3.zero
M.pressKey(Enum.KeyCode.Three); M.releaseKey(Enum.KeyCode.Three)
M.steps(3)
eq(Core.GetMode(), 3, "Test mode")
local guard2 = 0
while Core.GetMode() == 3 and guard2 < 400 do M.step(1 / 60); guard2 = guard2 + 1 end
check(Core.GetMode() ~= 3, "playback finished (" .. guard2 .. " frames)")
check(hrp.Position.X > x0 + 20, "playback moved the character along the recording")
section("dump while the TAS is loaded")
P.Menus[8].click(0)
local html = 0
for p in pairs(M.fs) do if p:find("microprofile%-.-%.html$") then html = html + 1 end end
eq(html, 1, "dump written")
finish()
