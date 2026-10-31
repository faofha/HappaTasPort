-- needs: ui
-- ================================================================================================
-- HappaTAS 3, phase 5a: Frost glass (a trial): a Glass-material part in front of the camera behind each
-- open window plus one DepthOfField, only with high graphics quality (else Tint), removed when Frost is off,
-- the last window closes, or on Unload; no per-frame work otherwise (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local T = getgenv().__HappaTAS3_T
local ui = E.ui
local wm = ui.wm
local s = E.settings
local cam = workspace.CurrentCamera
local Lighting = game:GetService("Lighting")
local ugs = UserSettings():GetService("UserGameSettings")
local function parts()
	local f = cam:FindFirstChild("HappaTASFrost")
	return f and f:GetChildren() or {}
end
local function dof() return Lighting:FindFirstChild("HappaTASFrost") end
local function handlers()
	local n = 0
	for _, e in ipairs(T.pipe.stages.PreRender) do if e.name == "ui.frost" then n = n + 1 end end
	return n
end
cam.CFrame = CFrame.new(0, 10, 0)
wm:define("f1", { title = "One", w = 300, h = 200, build = function() end })
wm:define("f2", { title = "Two", w = 300, h = 200, build = function() end })

section("Frost with high graphics: a part per open window and one DepthOfField")
ugs.SavedQualityLevel = { Name = "QualityLevel10", Value = 10 }
s:set("glass", "Frost")
eq(#parts(), 0, "no window open: nothing")
eq(dof(), nil, "no effect")
eq(handlers(), 0, "no per-frame work")
wm:open("f1")
M.steps(2)
eq(#parts(), 1, "one part")
local d = dof()
check(d ~= nil and d:IsA("DepthOfFieldEffect"), "a DepthOfField in Lighting")
local p = parts()[1]
eq(p.Material, Enum.Material.Glass, "Glass material")
eq(p.Anchored, true, "anchored")
eq(p.CanCollide, false, "no collisions")
eq(p.CanTouch, false, "no touches")
eq(p.CanQuery, false, "no queries")
eq(p:GetAttribute("HappaTASIgnore"), true, "ignored by HappaTAS's own systems")
near(d.NearIntensity, 0.7, 1e-9, "blur strength 70 %")
wm:open("f2")
M.steps(2)
eq(#parts(), 2, "two windows: two parts")
eq(handlers(), 1, "one per-frame handler while it shows")

section("the part follows the window's screen rect")
wm:place("f1", 200, 150)
M.steps(2)
local win = wm.windows.f1
local center = win.holder.AbsolutePosition + win.holder.AbsoluteSize / 2 + Vector2.new(0, M.inset)
local part = nil
for _, q in ipairs(parts()) do if q.Name == "f1" then part = q end end
check(part ~= nil, "the part is named after its window")
local sp = cam:WorldToViewportPoint(part.Position)
near(sp.X, center.X, 1, "projects onto the window's centre (x)")
near(sp.Y, center.Y, 1, "projects onto the window's centre (y)")
local right = cam:WorldToViewportPoint((part.CFrame * CFrame.new(part.Size.X / 2, 0, 0)).Position)
near(right.X - sp.X, win.holder.AbsoluteSize.X / 2, 1, "as wide as the window")
local top = cam:WorldToViewportPoint((part.CFrame * CFrame.new(0, part.Size.Y / 2, 0)).Position)
near(sp.Y - top.Y, win.holder.AbsoluteSize.Y / 2, 1, "as high as the window")
cam.CFrame = CFrame.new(5, 20, 5) * CFrame.Angles(0, 1, 0)
M.steps(2)
sp = cam:WorldToViewportPoint(part.Position)
near(sp.X, center.X, 1, "still there after the camera moved")

section("closing the last window removes everything")
wm:close("f1")
M.steps(2)
eq(#parts(), 1, "one left")
wm:close("f2")
M.steps(2)
eq(#parts(), 0, "none")
eq(dof(), nil, "no effect")
eq(handlers(), 0, "no per-frame work")

section("low graphics: Tint instead")
ugs.SavedQualityLevel = { Name = "QualityLevel3", Value = 3 }
s:set("glass", "Tint")
s:set("glass", "Frost")
wm:open("f1")
M.steps(2)
eq(#parts(), 0, "no part")
eq(dof(), nil, "no effect")
eq(ui.frost:available(), false, "not available")
wm:open("settings")
local row = ui.settingsWin.rows.glass.row
check(row.desc.Text:find("high graphics", 1, true) ~= nil, "the Glass row says why (" .. row.desc.Text .. ")")
wm:close("settings")
ugs.SavedQualityLevel = { Name = "Automatic", Value = 0 }
M.renderQuality = { Name = "Level19", Value = 19 }
s:set("glass", "Tint")
s:set("glass", "Frost")
M.steps(2)
eq(#parts(), 1, "Automatic at a high level: Frost")

section("Frost off: removed")
s:set("glass", "Tint")
M.steps(2)
eq(#parts(), 0, "no part")
eq(dof(), nil, "no effect")
eq(handlers(), 0, "no per-frame work")
local w0 = M.propWrites
M.steps(30, 1 / 60)
eq(M.propWrites - w0, 0, "no writes with Frost off")

section("Unload removes everything")
s:set("glass", "Frost")
M.steps(2)
eq(#parts(), 1, "showing again")
getgenv().__HappaTAS3.Unload()
M.steps(2)
eq(cam:FindFirstChild("HappaTASFrost"), nil, "the folder gone")
eq(dof(), nil, "the effect gone")
finish()
