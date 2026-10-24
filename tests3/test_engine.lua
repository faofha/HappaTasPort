-- ================================================================================================
-- HappaTAS 3, phase 2: Unload leaves nothing behind, in every mode (recording, paused, Test), and a second
-- copy started while the first records takes over cleanly
-- ================================================================================================
-- a camera script to patch (it must be unpatched on Unload)
local BaseCamera = {}
function BaseCamera.UpdateMouseBehavior(self) return "base" end
local origUMB = BaseCamera.UpdateMouseBehavior
do
	local pm = Instance.new("ModuleScript"); pm.Name = "PlayerModule"; pm.Parent = M.player:FindFirstChild("PlayerScripts")
	local cm = Instance.new("ModuleScript"); cm.Name = "CameraModule"; cm.Parent = pm
	local bc = Instance.new("ModuleScript"); bc.Name = "BaseCamera"; bc.Parent = cm
	local mods = { [pm] = { GetCameras = function() return nil end }, [bc] = BaseCamera }
	local realRequire = require
	require = function(x)
		if mods[x] then return mods[x] end
		return realRequire(x)
	end
end
local RS, UIS = M.services.RunService, M.services.UserInputService
local genv = getgenv()
local function counts() return { RS.PreRender:Count(), RS.PreSimulation:Count(), RS.PostSimulation:Count(), RS.Heartbeat:Count() } end
local before = counts()
local mbBefore = UIS.MouseBehavior
local autoJumpBefore = M.player.AutoJumpEnabled

check(boot(30), "boots")
local function engine()
	local T = genv.__HappaTAS3_T
	return T and T.engine
end
local function waitLoaded()
	local g = 0
	while not (engine() and engine().char:loaded()) and g < 200 do M.step(1 / 60); g = g + 1 end
	M.steps(80) -- (the camera script is looked for once os.clock() passes 1 s, then every 0.5 s)
	return engine()
end
local function key(kc) M.pressKey(kc); M.releaseKey(kc) end
local function click()
	UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	UIS.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
local function restart()
	M.resume(coroutine.create(function() __SCRIPT__() end))
	return waitLoaded()
end
local function heldByReplay()
	local held = {}
	for _, e in ipairs(M.inputLog) do
		if e[1] == "keypress" then held[e[2]] = true elseif e[1] == "keyrelease" then held[e[2]] = nil end
	end
	return next(held) ~= nil
end
local function nothingLeft(tag)
	local c = counts()
	eq(c[1], before[1], tag .. ": PreRender connections back")
	eq(c[2], before[2], tag .. ": PreSimulation connections back")
	eq(c[3], before[3], tag .. ": PostSimulation connections back")
	eq(c[4], before[4], tag .. ": Heartbeat connections back")
	local hrp = M.player.Character:FindFirstChild("HumanoidRootPart")
	local hum = M.player.Character:FindFirstChildOfClass("Humanoid")
	eq(hrp.Anchored, false, tag .. ": root not anchored")
	eq(hum.AutoRotate, true, tag .. ": AutoRotate on")
	eq(hum:GetStateEnabled(Enum.HumanoidStateType.Jumping), true, tag .. ": jumping on")
	eq(workspace.CurrentCamera.CameraType, Enum.CameraType.Custom, tag .. ": camera Custom")
	eq(UIS.MouseBehavior, mbBefore, tag .. ": mouse behaviour as before")
	eq(M.hooks[origUMB], nil, tag .. ": camera script unpatched")
	eq(BaseCamera.UpdateMouseBehavior, origUMB, tag .. ": its function is the original")
	check(not heldByReplay(), tag .. ": no key left down by the replay")
	local head = M.player.Character:FindFirstChild("Head")
	eq(head.LocalTransparencyModifier, 0, tag .. ": character not see-through")
	eq(M.player.AutoJumpEnabled, autoJumpBefore, tag .. ": AutoJumpEnabled back")
	eq(genv.__HappaTAS3, nil, tag .. ": handle removed")
	local animate = M.player.Character:FindFirstChild("Animate")
	eq(animate and animate.Disabled, false, tag .. ": the game's Animate back")
end

section("loaded: the camera script is patched")
local E = waitLoaded()
check(M.hooks[origUMB] ~= nil, "patched while loaded")

section("Unload while recording")
key(Enum.KeyCode.Two)
M.steps(2)
click()
M.steps(5)
eq(E.state:get("mode"), "Recording", "recording")
genv.__HappaTAS3.Unload()
M.steps(2)
nothingLeft("recording")

section("Unload while paused")
E = restart()
key(Enum.KeyCode.Two)
M.steps(2)
click()
M.steps(5)
click()
M.steps(2)
eq(E.state:get("mode"), "Paused", "paused")
E.char.hrp.Anchored = true
genv.__HappaTAS3.Unload()
M.steps(2)
nothingLeft("paused")

section("Unload while testing (a key held by the replay)")
E = restart()
key(Enum.KeyCode.Two)
M.steps(2)
click()
M.pressKey(Enum.KeyCode.W)
M.steps(8)
click()
M.steps(2)
M.releaseKey(Enum.KeyCode.W)
M.inputLog = {}
key(Enum.KeyCode.Three)
M.steps(4)
eq(E.state:get("mode"), "Testing", "testing")
check(heldByReplay(), "the replay holds W")
genv.__HappaTAS3.Unload()
M.steps(2)
nothingLeft("testing")

section("a second copy started while the first records")
E = restart()
key(Enum.KeyCode.Two)
M.steps(2)
click()
M.steps(5)
local E2 = restart()
check(E2 ~= E, "a new engine")
eq(E2.state:get("mode"), "Idle", "the new copy starts in Idle")
local c = counts()
eq(c[1], before[1] + 1, "one PreRender connection (the old copy's is gone)")
eq(E2.char.hrp.Anchored, false, "the character is free")
key(Enum.KeyCode.Two)
M.steps(2)
click()
M.steps(4)
check(E2.tl:count() > 0, "the new copy records")
genv.__HappaTAS3.Unload()
M.steps(2)
nothingLeft("after a re-run")
finish()
