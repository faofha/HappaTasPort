-- ================================================================================================
-- HappaTAS 3, phase 5c: the touch thumbstick recorded and replayed (V2.38.17's ReadMobile / ReplayMobile):
-- the static stick, the dynamic thumbstick's images, the jump button; only on touch devices; kept by save /
-- load; V2 runs' Mobile data in the same column (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local tl = E.tl
local Run = __T3("persist/run")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local uis = M.services.UserInputService

-- Roblox's touch controls as V2 found them: PlayerGui.TouchGui.TouchControlFrame
local pg = M.player:FindFirstChildOfClass("PlayerGui")
local tg = Instance.new("ScreenGui"); tg.Name = "TouchGui"; tg.Parent = pg
local tcf = Instance.new("Frame"); tcf.Name = "TouchControlFrame"; tcf.Parent = tg
local jb = Instance.new("ImageButton"); jb.Name = "JumpButton"; jb.ImageRectOffset = Vector2.new(1, 146); jb.Parent = tcf
local tf = Instance.new("Frame"); tf.Name = "ThumbstickFrame"; tf.Visible = true; tf.Parent = tcf
local stick = Instance.new("ImageLabel"); stick.Name = "StickImage"; stick.Parent = tf
local dtf = Instance.new("Frame"); dtf.Name = "DynamicThumbstickFrame"; dtf.Visible = true; dtf.Parent = tcf
local sImg = Instance.new("ImageLabel"); sImg.Name = "ThumbstickStart"; sImg.Visible = true; sImg.Parent = dtf
local eImg = Instance.new("ImageLabel"); eImg.Name = "ThumbstickEnd"; eImg.Visible = true; eImg.Parent = dtf
local mids = {}
for i = 1, 3 do
	local m = Instance.new("ImageLabel"); m.Name = "ThumbstickMiddle"; m.Visible = true; m.Size = UDim2.new(0, 10, 0, 10); m.Parent = dtf
	mids[i] = m
end
local function move(k)
	stick.Position = UDim2.new(0, k, 0, 2 * k)
	sImg.Position = UDim2.new(0, 100, 0, 200)
	eImg.Position = UDim2.new(0, 100 + k, 0, 200 - k)
	sImg.ImageTransparency, eImg.ImageTransparency = 0.25, 0.5
	for i, m in ipairs(mids) do m.Position = UDim2.new(0, 100 + k * i / 4, 0, 200 - k * i / 4) end
	jb.ImageRectOffset = Vector2.new((k % 2 == 0) and 146 or 1, 146)
end
local function record(n)
	E.modes:request("create")
	M.steps(3)
	E.modes:request("unpause")
	for k = 1, n do
		move(k)
		M.step(1 / 60)
	end
	E.modes:request("pause")
	M.steps(2)
end

section("the column: V2's Mobile key, no carry column")
check(tl.cols.Mobile ~= nil, "a Mobile column")
eq(tl.cols.v2Mobile, nil, "no v2Mobile carry column any more")

section("not a touch device: nothing recorded")
uis.TouchEnabled = false
record(10)
local any = false
for i = 1, tl:count() do if tl:getList("Mobile", i) ~= nil then any = true end end
eq(any, false, "no thumbstick data")

section("a touch device: every frame")
E.modes:request("idle")
M.steps(2)
E.modes:setRun({})
M.steps(2)
uis.TouchEnabled = true
record(30)
local none = true
for i = 1, tl:count() do if tl:getList("Mobile", i) ~= nil then none = false end end
check(none, "a touch screen found after the start isn't recorded (V2 decided once)")
E.modes:request("idle")
M.steps(2)
check(boot(30), "runs again on a touch screen")
T = getgenv().__HappaTAS3_T
E = T.engine
tl = E.tl
guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
record(30)
local n = tl:count()
local bad = 0
for i = 2, n do
	local mob = tl:getList("Mobile", i)
	if type(mob) ~= "table" or mob.Dynamic == nil or #mob.Dynamic.Middles ~= 3 then bad = bad + 1 end
end
eq(bad, 0, "every frame has the stick and 3 middles")
local mob = tl:getList("Mobile", n)
eq(mob.JoystickX, stick.Position.X.Offset, "the stick's x")
eq(mob.JoystickY, stick.Position.Y.Offset, "the stick's y")
eq(mob.Dynamic.Start[3], 0.25, "the start image's transparency")
eq(mob.Dynamic.End[1], eImg.Position.X.Offset, "the end image's x")

section("save / load keep it")
local data
local co = coroutine.create(function() data = Run.build(tl, "thumb") end)
coroutine.resume(co)
while coroutine.status(co) ~= "dead" do M.step(1 / 60) end
local fresh = __T3("engine/timeline").newLike(tl)
co = coroutine.create(function() Run.load(fresh, data) end)
coroutine.resume(co)
while coroutine.status(co) ~= "dead" do M.step(1 / 60) end
local same = true
for i = 1, n do
	local a, b = tl:getList("Mobile", i), fresh:getList("Mobile", i)
	if (a == nil) ~= (b == nil) or (a and (a.JoystickX ~= b.JoystickX or a.Jumping ~= b.Jumping)) then same = false end
end
check(same, "the loaded run has the same thumbstick")

section("Test puts it back")
move(999)
E.modes:request("test")
local seen = 0
for _ = 1, 20 do
	M.step(1 / 60)
	local f = E.frame
	local want = tl:getList("Mobile", f)
	if want and stick.Position.X.Offset == want.JoystickX and eImg.Position.X.Offset == want.Dynamic.End[1] then seen = seen + 1 end
end
check(seen >= 15, "the stick and the dynamic images follow the recording (" .. seen .. " of 20 frames)")
E.modes:request("idle")
M.steps(2)

section("a V2 run's Mobile data plays")
local v2 = tl:toV2All()
for i, fr in ipairs(v2) do fr.Mobile = { Jumping = 0, JoystickX = 500 + i, JoystickY = 7 } end
E.modes:setRun(v2)
M.steps(2)
eq(tl:getList("Mobile", 3).JoystickX, 503, "in the Mobile column")
E.modes:request("test")
M.steps(3, 1 / 60)
eq(stick.Position.X.Offset, 500 + E.frame, "played")
E.modes:request("idle")
M.steps(2)
uis.TouchEnabled = false
finish()
