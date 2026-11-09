-- needs: ui
-- ================================================================================================
-- HappaTAS 3: interface sounds (New interface only): HappaTAS writes its built-in click / open / close / status
-- sounds as .wav files into HappaTasPort/Sounds once (a file already there is kept: yours), loads them with
-- getcustomasset and plays them on a click of a button / switch / choice / dropdown pick, a window opening or
-- closing and a status message; Interface sounds off, Sound volume, the Classic interface: silent (headless mock)
-- ================================================================================================
local mine = "my own sound"
if not isfolder("HappaTasPort") then makefolder("HappaTasPort") end
if not isfolder("HappaTasPort/Sounds") then makefolder("HappaTasPort/Sounds") end
writefile("HappaTasPort/Sounds/status.wav", mine) -- (a file you put there before: never overwritten)
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local s = E.settings
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end

section("the files and the assets")
for _, name in ipairs({ "click", "open", "close" }) do
	local path = "HappaTasPort/Sounds/" .. name .. ".wav"
	check(isfile(path), name .. ".wav written")
	local data = isfile(path) and readfile(path) or ""
	eq(data:sub(1, 4), "RIFF", name .. ": a RIFF file")
	eq(data:sub(9, 12), "WAVE", name .. ": WAVE")
	check(#data > 400 and #data < 20000, name .. ": a short sound (" .. #data .. " bytes)")
end
eq(readfile("HappaTasPort/Sounds/status.wav"), mine, "a file already there is kept")
local snd = ui.sounds
check(snd ~= nil, "ui.sounds")
eq(snd and snd.sounds.click and snd.sounds.click.SoundId, "rbxasset://custom/HappaTasPort/Sounds/click.wav", "loaded with getcustomasset")
eq(s:get("uiSounds"), 1, "Interface sounds on by default")
eq(s:get("uiSoundVolume"), 50, "Sound volume 50 by default")

local function plays(f)
	local before = M.soundPlays or 0
	local last = snd.last
	snd.last = nil
	f()
	M.steps(1)
	local got = snd.last
	snd.last = got or last
	return (M.soundPlays or 0) - before, got
end

section("what plays")
local n, which = plays(function() ui.wm:open("settings") end)
eq(n, 1, "a window opening: one sound")
eq(which, "open", "the open sound")
M.steps(2)
local row = ui.settingsWin.rows.shadows
ui.settingsWin.list.CanvasPosition = Vector2.new(0, math.max(0, row.row.gui.Position.Y.Offset - 40))
M.steps(1)
n, which = plays(function() UIH.click(row.ctl.gui) end)
eq(which, "click", "a switch: the click sound")
n, which = plays(function() ui.wm:close("settings") end)
eq(which, "close", "a window closing: the close sound")
n, which = plays(function() E.bus:emit("status", "Saved", false) end)
eq(which, "status", "a status message: the status sound")
near(snd.sounds.status.Volume, 0.5, 1e-9, "at the volume (50 -> 0.5)")
s:set("uiSoundVolume", 20)
plays(function() E.bus:emit("status", "Again", false) end)
near(snd.sounds.status.Volume, 0.2, 1e-9, "Sound volume 20 -> 0.2")
s:set("shadows", 1)

section("silent")
s:set("uiSounds", 0)
n = plays(function() ui.wm:open("settings"); ui.wm:close("settings"); E.bus:emit("status", "x", false) end)
eq(n, 0, "Interface sounds off: nothing")
s:set("uiSounds", 1)
s:set("interface", "Classic")
M.steps(2)
n = plays(function() E.bus:emit("status", "x", false) end)
eq(n, 0, "the Classic interface: nothing")
s:set("interface", "New")
M.steps(2)
n = plays(function() E.bus:emit("status", "y", false) end)
eq(n, 1, "the New interface again: it plays")

section("Unload")
local gui = snd.sounds.click
getgenv().__HappaTAS3.Unload()
M.steps(2)
eq(gui.Parent, nil, "the sounds are gone")
finish()
