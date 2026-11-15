-- ================================================================================================
-- HappaTAS 3: the speed hack is slow motion only: Speed Hack Speed 0.1 - 1 (no fast motion above 1x).
-- (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local s = E.settings
local Settings = __T3("engine/settings")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end

section("the setting stops at 1")
local def = Settings.byKey.speedHackSpeed
eq(def.max, 1, "the highest speed is 1")
eq(def.min, 0.1, "the lowest 0.1")
check(not def.desc:find("4"), "the description doesn't offer 4x (" .. def.desc .. ")")
s:set("speedHackSpeed", 2)
eq(s:get("speedHackSpeed"), 1, "2 becomes 1")
s:set("speedHackSpeed", 4)
eq(s:get("speedHackSpeed"), 1, "4 becomes 1")

section("on at 1: nothing changes")
s:set("speedHack", 1)
s:set("speedHackSpeed", 1)
eq(E.time.SH.Wanted(), 1, "1x: off")
s:set("speedHackSpeed", 0.5)
eq(E.time.SH.Wanted(), 0.5, "0.5x: slow motion")
s:set("speedHackSpeed", 0.5)
s:set("speedHack", 0)

section("an old settings file with 2 loads as 1")
eq(Settings.sanitize(def, 3), 1, "3 -> 1")

finish()
