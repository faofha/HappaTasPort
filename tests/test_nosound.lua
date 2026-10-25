-- Keyboard / click sounds are removed: no sound objects, settings, help page or code paths, and an old
-- Settings.json that still has the sound keys loads without errors (the keys are dropped on the next save).
local OLD_SETTINGS = '{"settings":{"Enable Keyboard Sounds":1,"Enable Click Sounds":1,"Sound Trigger Mode":2,'
	.. '"Sound Volume":80,"Dynamic Pitch Variation":1,"Playback Speed":2},"controls":{"Create":"2"}}'
M.fs["HappaTasPort/Settings.json"] = OLD_SETTINGS
check(boot(30), "boots with an old Settings.json that has sound keys")
local S, Core = __T.Settings, __T.Core
local C = Core.State
local guard = 0
while not (C.HRP and C.Humanoid) and guard < 200 do M.step(1 / 60); guard = guard + 1 end

section("old sound keys are ignored, the rest of the file still loads")
eq(S.Get("Playback Speed"), 2, "a normal setting from the old file is loaded")
for _, name in ipairs({ "Enable Keyboard Sounds", "Enable Click Sounds", "Sound Trigger Mode", "Sound Volume", "Dynamic Pitch Variation" }) do
	eq(S.defs[name], nil, "no setting " .. name)
end
for _, l in ipairs(M.logs) do
	check(not l:lower():find("sound"), "no sound message in the log: " .. l)
end

section("saving drops the old sound keys")
S.Set("Playback Speed", 1)
M.steps(40) -- (saving waits 0.4 s for more changes)
local saved = M.fs["HappaTasPort/Settings.json"] or ""
check(saved ~= OLD_SETTINGS, "Settings.json was saved again")
check(not saved:find("Sound", 1, true), "no sound key left in Settings.json")

section("no sound objects, no sound settings rows, no sound help page")
local function count(root, pred)
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do if pred(d) then n = n + 1 end end
	return n
end
eq(C.Gui:FindFirstChild("Sounds"), nil, "no sound folder in the interface")
eq(count(C.Gui, function(d) return d:IsA("Sound") end), 0, "no Sound objects in the interface")
eq(count(C.Gui, function(d) return d.Name == "Section_Sounds" end), 0, "no Sounds section in Settings")
eq(count(C.Gui, function(d) return d:IsA("TextLabel") and tostring(d.Text):find("Keyboard & Click Sounds", 1, true) ~= nil end), 0,
	"no sound help page")

section("recording and replaying keys play nothing")
M.soundPlays = 0
M.pressKey(Enum.KeyCode.Two); M.releaseKey(Enum.KeyCode.Two); M.steps(2)
M.services.UserInputService.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
M.steps(3)
M.pressKey(Enum.KeyCode.W); M.steps(10); M.releaseKey(Enum.KeyCode.W); M.steps(5)
M.services.UserInputService.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
M.steps(3)
M.pressKey(Enum.KeyCode.Three); M.releaseKey(Enum.KeyCode.Three)
local g = 0
while C.mode == 3 and g < 300 do M.step(1 / 60); g = g + 1 end
eq(M.soundPlays or 0, 0, "no sound played while recording or replaying")
finish()
