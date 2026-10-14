-- ================================================================================================
-- Keeping HappaTAS out of game scripts' sight (V2.38.3):
--  * without a working hookfunction the camera script's functions are swapped in their tables (old way)
--  * the interface never goes to PlayerGui (visible to game scripts) unless the player allows it
-- ================================================================================================
M.hookFail = true
local BaseCamera = {}
function BaseCamera.UpdateMouseBehavior(self) return "base" end
local ZoomController = {}
function ZoomController.Update(dt) return dt end
local origUMB, origZU = BaseCamera.UpdateMouseBehavior, ZoomController.Update
do
	local pm = Instance.new("ModuleScript"); pm.Name = "PlayerModule"; pm.Parent = M.player:FindFirstChild("PlayerScripts")
	local cm = Instance.new("ModuleScript"); cm.Name = "CameraModule"; cm.Parent = pm
	local bc = Instance.new("ModuleScript"); bc.Name = "BaseCamera"; bc.Parent = cm
	local zc = Instance.new("ModuleScript"); zc.Name = "ZoomController"; zc.Parent = cm
	local ctrl = { currentSubjectDistance = 12.5 }
	function ctrl:GetCameraToSubjectDistance() return self.currentSubjectDistance end
	function ctrl:SetCameraToSubjectDistance(d) self.currentSubjectDistance = d end
	local cams = { activeCameraController = ctrl }
	local mods = { [pm] = { GetCameras = function() return cams end }, [bc] = BaseCamera, [zc] = ZoomController }
	local realRequire = require
	require = function(x)
		if mods[x] then return mods[x] end
		return realRequire(x)
	end
end
check(boot(5), "boots")
local UI, S = __T.UI, __T.Settings
M.steps(70)

section("hookfunction fails: the functions are swapped in their tables")
check(BaseCamera.UpdateMouseBehavior ~= origUMB, "BaseCamera.UpdateMouseBehavior swapped")
check(ZoomController.Update ~= origZU, "ZoomController.Update swapped")
eq(next(M.hooks), nil, "no hook left behind")

section("the interface goes to PlayerGui only when allowed")
do
	M.noHui, M.coreGuiLocked = true, true
	local pg = M.player:FindFirstChildOfClass("PlayerGui")
	eq(S.Get("Allow PlayerGui Interface"), 0, "off by default")
	local sg = Instance.new("ScreenGui")
	eq(UI.Attach(sg), false, "no hidden place and PlayerGui not allowed: not attached")
	eq(sg.Parent, nil, "not in PlayerGui")
	check(UI.Refused == true, "HappaTAS knows why (it tells the player how to allow it)")
	S.Set("Allow PlayerGui Interface", 1)
	local sg2 = Instance.new("ScreenGui")
	eq(UI.Attach(sg2), true, "allowed: attached")
	eq(sg2.Parent, pg, "in PlayerGui")
	check(sg2.Name ~= "ScreenGui" and #sg2.Name == 12, "with a random name")
	sg2:Destroy()
	S.Set("Allow PlayerGui Interface", 0)
	M.noHui, M.coreGuiLocked = false, false
	local sg3 = Instance.new("ScreenGui")
	eq(UI.Attach(sg3), true, "gethui works again: attached")
	eq(UI.ParentName, "gethui", "under gethui()")
	sg3:Destroy()
end

section("Unload puts the camera script's functions back")
rawget(getgenv(), "__HappaTAS").Unload()
M.steps(2)
eq(BaseCamera.UpdateMouseBehavior, origUMB, "BaseCamera.UpdateMouseBehavior back")
eq(ZoomController.Update, origZU, "ZoomController.Update back")

finish()
