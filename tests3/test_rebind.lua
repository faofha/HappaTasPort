-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1 (Task 3): ui/rebind (waiting for a key to bind, shared by the Controls window and the
-- Tasability KEYS list) and the settings helpers ui/win/settings exports (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local Rebind = __T3("ui/rebind")
local SettingsWin = __T3("ui/win/settings")
local Settings = __T3("engine/settings")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local c = E.controls

section("waiting for a key")
local rb = Rebind.new(E, ui.life)
local got = "none"
rb:start("back", function(name) got = name end)
eq(rb.waiting, "back", "waiting for back")
eq(E.typing.rebinding, true, "keys are off while it waits")
UIH.key(Enum.KeyCode.Backspace)
M.steps(1)
eq(c:get("back"), "Backspace", "Backspace binds (it is a key like any other)")
eq(got, "Backspace", "reported")
eq(E.typing.rebinding, false, "keys back on")
eq(rb.waiting, nil, "not waiting")
rb:start("back", function(name) got = name end)
UIH.key(Enum.KeyCode.Escape)
M.steps(1)
eq(c:get("back"), "Backspace", "Esc: unchanged")
eq(got, nil, "Esc reports nil")
rb:start("back", function(name) got = name end)
rb:stop()
eq(E.typing.rebinding, false, "stop: keys on")
UIH.key(Enum.KeyCode.G)
M.steps(1)
eq(c:get("back"), "Backspace", "stop: the next key binds nothing")
rb:start("back", function(name) got = name end)
UIH.key(Enum.KeyCode.R)
M.steps(1)
eq(c:get("back"), "R", "back to R")

section("settings helpers")
eq(SettingsWin.num(0.5), "0.5", "0.5")
eq(SettingsWin.num(13), "13", "13")
eq(SettingsWin.isDefault(Settings.byKey.textSize, 13), true, "isDefault")
eq(SettingsWin.lookNames(E)[1], "Default", "Default first")
local ok = SettingsWin.saveLook(E, "Mine")
eq(ok, true, "saved a look")
local look = E.settingsFile:getUi().themes.Mine
check(look ~= nil and look.accentColor == E.settings:get("accentColor"), "with the Appearance values")
check(table.find(SettingsWin.lookNames(E), "Mine") ~= nil, "listed")
eq(E.settings:get("theme"), "Mine", "and picked")
local ok2, why = SettingsWin.saveLook(E, "default")
eq(ok2, false, "Default can't be overwritten")
eq(why, "\"Default\" can't be overwritten: pick another name", "with the reason")
finish()
