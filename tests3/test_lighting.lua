-- ================================================================================================
-- HappaTAS 3, phase 4: lighting ("Sync Lighting", V2.38.17 p14_buttons.lua 1812-2052): a snapshot when
-- the lighting changes, the frame's lighting while paused / scrubbing / testing, Idle leaves it alone,
-- Sync Lighting off puts back the lighting from before the TAS, never saved in files (like V2)
-- ================================================================================================
M.clockStep = 0
-- (the game's lighting, there before HappaTAS starts)
local lighting = game:GetService("Lighting")
lighting.ClockTime = 14
lighting.FogColor = Color3.fromRGB(100, 100, 100)
local cc = Instance.new("ColorCorrectionEffect"); cc.Name = "CC"; cc.Parent = lighting
cc.Saturation = 0
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local tl = E.tl

local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
local function click()
	local UIS = M.services.UserInputService
	UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	UIS.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
local function snaps()
	local n = 0
	for i = 1, tl:count() do if tl:getList("LT", i) then n = n + 1 end end
	return n
end

E.settings:set("syncLighting", 1)
M.steps(2)

section("a snapshot only when the lighting changes")
key(Enum.KeyCode.Two)
M.steps(3)
click()
M.steps(10)
local changeAt
for i = 1, 60 do
	if i == 20 then lighting.ClockTime = 20; cc.Saturation = -1; changeAt = tl:count() end
	M.step(1 / 60)
end
click()
M.steps(3)
eq(snaps(), 2, "two snapshots: the start and the change")
check(tl:getList("LT", 1) ~= nil, "frame 1 has the start")

section("scrubbing shows the frame's lighting")
local function backTo(f)
	local g = 0
	while E.frame > f and g < 200 do key(Enum.KeyCode.F); M.steps(4); g = g + 1 end
end
backTo(changeAt - 5)
check(E.frame < changeAt, "before the change (frame " .. E.frame .. ")")
near(lighting.ClockTime, 14, 1e-6, "ClockTime 14 again")
near(cc.Saturation, 0, 1e-6, "the effect too")
local gf = 0
while E.frame < tl:count() and gf < 200 do key(Enum.KeyCode.G); M.steps(4); gf = gf + 1 end
near(lighting.ClockTime, 20, 1e-6, "ClockTime 20 after the change")

section("cut frames trim the snapshots")
backTo(changeAt - 5)
click()
M.steps(10)
click()
M.steps(3)
eq(snaps(), 1, "the change was in the cut frames")
near(lighting.ClockTime, 14, 1e-6, "the lighting of the frame shown")
lighting.ClockTime = 9
click()
M.steps(5)
click()
M.steps(3)
eq(snaps(), 2, "a new change recorded")

section("Test plays the frames' lighting")
lighting.ClockTime = 3
key(Enum.KeyCode.Three)
M.steps(2)
near(lighting.ClockTime, 14, 1e-6, "the first frame's lighting")
local g = 0
while E.mode == 3 and g < 400 do M.step(1 / 60); g = g + 1 end
near(lighting.ClockTime, 9, 1e-6, "the last change by the end")

section("Idle leaves the lighting as it is")
eq(E.mode, 1, "idle")
M.steps(5)
near(lighting.ClockTime, 9, 1e-6, "still the TAS's lighting")

section("not saved in files")
local Codec6 = __T3("persist/codec6")
check(tl.cols.LT and tl.cols.LT.v2 and tl.cols.LT.v2.save == false, "LT is marked save = false")

section("Sync Lighting off puts back the lighting from before the TAS")
E.settings:set("syncLighting", 0)
M.steps(2)
near(lighting.ClockTime, 14, 1e-6, "the lighting from before")
near(cc.Saturation, 0, 1e-6, "the effect from before")
cc:Destroy()
finish()
