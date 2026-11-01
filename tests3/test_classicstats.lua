-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5c: V2's stats panels in the classic interface: the Inspector's values in V2's lines,
-- one panel by mode, Show Stats, Test at another speed, Stats Text Size, no writes while nothing changes,
-- nothing while New is live (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local IV = __T3("ui/win/inspectorvalues")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
E.settings:set("interface", "Classic")
M.steps(2)
local c = ui.classic
local st = c.stats
check(st ~= nil, "the classic stats panels")
local b = c.byPath
local function row(panel, name) return b[panel .. "." .. name].Text end
local function vis() return (b.IdleStats.Visible and "I" or "") .. (b.CreateStats.Visible and "C" or "") .. (b.TestStats.Visible and "T" or "") end

section("Idle: the live character")
M.steps(30, 1 / 60)
st:update(true)
eq(vis(), "I", "the Idle panel only")
local v = IV.values(E, st.perf)
eq(row("IdleStats", "2"), " Root Position: " .. v.position, "position")
eq(row("IdleStats", "3"), " Root Rotation: " .. v.rotation, "rotation")
eq(row("IdleStats", "4"), " Root Linear Velocity: " .. v.velocity, "velocity")
eq(row("IdleStats", "6"), " Camera Rotation: " .. v.cameraRotation, "camera")
eq(row("IdleStats", "7"), " Humanoid State: " .. v.state, "state")
eq(row("IdleStats", "8"), " Zoom: " .. v.zoom, "zoom")

section("Create, paused on a frame")
E.modes:request("create")
M.steps(3)
E.modes:request("unpause")
for _ = 1, 40 do
	E.char.hrp.AssemblyLinearVelocity = Vector3.new(8, 0, 0)
	M.step(1 / 60)
end
st:update(true)
v = IV.values(E, st.perf)
eq(vis(), "C", "the Create panel only")
eq(row("CreateStats", "4"), " Root Position: " .. v.position, "recording: the newest recorded frame's position")
E.modes:request("pause")
M.steps(2)
local f = math.floor(E.tl:count() / 2)
E.modes:request("seek", { frame = f })
M.steps(2)
v = IV.values(E, st.perf)
eq(row("CreateStats", "1"), " Frame: " .. f, "the frame shown")
eq(row("CreateStats", "2"), " Frame Time: " .. v.frameTime, "frame time")
eq(row("CreateStats", "3"), " Total Time: " .. v.totalTime, "total time")
eq(row("CreateStats", "4"), " Root Position: " .. v.position, "position")
eq(row("CreateStats", "5"), " Root Rotation: " .. v.rotation, "rotation")
eq(row("CreateStats", "9"), " Humanoid State: " .. v.state, "state")
eq(row("CreateStats", "91"), " Zoom: " .. v.zoom, "zoom")
eq(row("CreateStats", "92"), " Keys: " .. v.keys, "keys")
eq(row("CreateStats", "93"), " Mouse: " .. v.mouse, "mouse")
eq(b.CreateStats.BackgroundTransparency, 0.1, "darker while paused (V2)")

section("paused, nothing changing: nothing written")
M.writeLog = {}
M.steps(30, 1 / 60)
local writes = 0
for _, e in ipairs(M.writeLog) do if e[1]:IsDescendantOf(c.gui) then writes = writes + 1 end end
M.writeLog = nil
eq(writes, 0, "no write under the classic interface")
st:update(false)
M.writeLog = {}
st:update(false)
writes = 0
for _, e in ipairs(M.writeLog) do if e[1]:IsDescendantOf(c.gui) then writes = writes + 1 end end
M.writeLog = nil
eq(writes, 0, "an update with the same values writes nothing")

section("Test")
E.settings:set("playbackSpeed", 0.5)
E.modes:request("test")
M.steps(5, 1 / 60)
st:update(true)
v = IV.values(E, st.perf)
eq(vis(), "T", "the Test panel only")
eq(row("TestStats", "1"), " Time: " .. v.totalTime, "the playback time")
eq(row("TestStats", "2"), " Playback Speed: 0.5", "the speed")
E.settings:set("showStatsTest", 0)
M.steps(1)
eq(vis(), "T", "at another speed it shows anyway (V2's rule)")
E.settings:set("playbackSpeed", 1)
M.steps(1)
eq(vis(), "", "at 1x with Show Stats (Test) off: hidden")
E.settings:set("showStatsTest", 1)
E.modes:request("idle")
M.steps(2)

section("Show Stats and Stats Text Size")
E.settings:set("showStatsIdle", 0)
M.steps(1)
eq(vis(), "", "Show Stats (Idle) off: hidden")
E.settings:set("showStatsIdle", 1)
E.settings:set("statsTextSize", 22)
M.steps(1)
eq(b["IdleStats.2"].TextSize, 22, "rows sized")
eq(b.IdleStats.Size.X.Offset, 480, "the panel 240 x 22 / 11 wide")
E.settings:set("statsTextSize", 11)

section("nothing while New is live")
E.settings:set("interface", "New")
M.steps(2)
E.char.hrp.AssemblyLinearVelocity = Vector3.new(8, 0, 0)
M.writeLog = {}
M.steps(30, 1 / 60)
writes = 0
for _, e in ipairs(M.writeLog) do if e[1]:IsDescendantOf(c.gui) then writes = writes + 1 end end
M.writeLog = nil
eq(writes, 0, "no classic write while New is live")
local handlers = 0
for _, list in pairs(T.pipe.stages) do
	for _, e in ipairs(list) do if e.on and e.name:find("^ui%.classic") then handlers = handlers + 1 end end
end
eq(handlers, 0, "no classic handler")
finish()
