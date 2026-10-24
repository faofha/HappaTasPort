-- ================================================================================================
-- HappaTAS 3, phase 2: the character plugin (pose, velocities, state, death and respawn, 240 FPS
-- frames without a physics step, coyote jump, ladder jump)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local UIS = M.services.UserInputService
local tl = E.tl
local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
local function click()
	UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	UIS.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
local function record(n, dt, perFrame)
	for f = 1, n do
		local hrp = E.char.hrp
		hrp.AssemblyLinearVelocity = Vector3.new(3.3333, -0.00001, 1)
		if perFrame then perFrame(f) end
		M.step(dt or 1 / 60)
	end
end

section("values are rounded like V2")
key(Enum.KeyCode.Two)
M.steps(2)
E.char.hrp.CFrame = CFrame.new(1.23456, -0.0001, 7)
click()
record(3)
local x, y, z = tl:getN("Cframe", 1)
eq(x, math.round(x * 1000) / 1000, "x at 1/1000 (" .. x .. ")")
eq(y, 0, "-0.0001 -> 0")
check(1 / y > 0, "not -0")
local lx, ly = tl:getN("Lin", 1)
eq(lx, 3.333, "velocity at 1/1000")
eq(ly, 0, "tiny negative velocity -> 0")
eq(tl:get("FrameTime", 2, 1), math.round((1 / 60) * 1e6) / 1e6, "FrameTime at 1/1000000")
eq(tl:get("State", 1, 1), E.char.hum:GetState().Value, "state value")

section("240 FPS: a frame without a physics step is filled in Heartbeat")
local n0 = tl:count()
local phys = 0
M.simDt = function(dt) phys = phys + 1; return (phys % 5 == 0) and 0 or dt end
record(20, 1 / 240)
M.simDt = nil
eq(tl:count(), n0 + 20, "no frame lost")
local ok = true
for i = n0 + 1, tl:count() do if not tl:isFilled(i) then ok = false end end
check(ok, "every frame filled")
-- (a frame's time is the step before it: the first of them still has the 1/60 of the frame before)
near(tl:get("TotalTime", tl:count(), 1) - tl:get("TotalTime", n0, 1), 1 / 60 + 19 / 240, 1e-5, "their times add up")

section("death with Record Death & Respawn on: the run goes on with the new character")
local hum = E.char.hum
hum.Health = 0
hum:ChangeState(Enum.HumanoidStateType.Dead)
hum.Died:Fire()
record(2)
eq(tl:getList("Died", tl:count()), true, "Died on the frame")
eq(E.mode, 2, "still recording")
local old = M.player.Character
old:Destroy()
local ch = M.makeCharacter(Vector3.new(5, 3, 0))
M.player.CharacterAdded:Fire(ch)
M.steps(2)
eq(E.char.hrp, ch:FindFirstChild("HumanoidRootPart"), "the new root")
local before = tl:count()
record(3)
check(tl:count() > before, "recording on the new character")
local px = tl:getN("Cframe", tl:count())
check(px > 4, "frames from the new character's position (" .. px .. ")")
click()
M.steps(2)

section("death with Record Death & Respawn off: the last frame is dropped and HappaTAS goes Idle")
E.settings:set("recordDeath", 0)
click()
record(4)
local count = tl:count()
hum = E.char.hum
hum:ChangeState(Enum.HumanoidStateType.Dead)
hum.Died:Fire()
eq(tl:count(), count - 1, "the last frame dropped")
eq(E.mode, 1, "Idle")
E.settings:set("recordDeath", 1)
hum:ChangeState(Enum.HumanoidStateType.Running)

section("coyote jump: allowed after two Running frames")
key(Enum.KeyCode.Two)
M.steps(2)
local h = E.char.hum
local f = E.frame
tl:set("State", f, 1, Enum.HumanoidStateType.Running.Value)
tl:set("State", f - 1, 1, Enum.HumanoidStateType.Running.Value)
h:ChangeState(Enum.HumanoidStateType.Running)
UIS.JumpRequest:Fire()
eq(h:GetState(), Enum.HumanoidStateType.Jumping, "jump after two Running frames")
h:ChangeState(Enum.HumanoidStateType.Running)
tl:set("State", f - 1, 1, Enum.HumanoidStateType.Freefall.Value)
UIS.JumpRequest:Fire()
eq(h:GetState(), Enum.HumanoidStateType.Running, "no jump when the frame before wasn't Running")

section("a jump off a ladder: unpausing goes back one frame")
tl:set("State", f, 1, Enum.HumanoidStateType.Jumping.Value)
tl:set("State", f - 1, 1, Enum.HumanoidStateType.Climbing.Value)
click()
M.steps(3)
-- (cut to frame f - 1, then two new frames)
eq(tl:count(), f - 1 + 2, "unpaused from the frame before the jump")
finish()
