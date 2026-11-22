-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1 Compact (Task 1): the third value of Interface; the New-only Appearance rows (newOnly)
-- (headless mock)
-- ================================================================================================
check(boot(30), "boots")
local T = getgenv().__HappaTAS3_T
local E = T.engine
local ui = E.ui
local Settings = __T3("engine/settings")
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end

section("the setting")
eq(table.concat(Settings.byKey.interface.options, ","), "New,Classic,Tasability", "three interfaces")
local HIDDEN = { "glass", "glassColor", "glassTransparency", "blurStrength", "edgeLight", "font", "numberFont",
	"windowCorners", "buttonShape", "shadows", "animations", "animationLength", "easing", "easingDirection",
	"bezierX1", "bezierY1", "bezierX2", "bezierY2" }
local SHOWN = { "theme", "accentColor", "textColor", "secondaryTextColor", "recordingColor", "textSize",
	"interfaceScale", "uiSounds", "uiSoundVolume" }
for _, k in ipairs(HIDDEN) do eq(Settings.byKey[k].newOnly, true, k .. " is New only") end
for _, k in ipairs(SHOWN) do check(not Settings.byKey[k].newOnly, k .. " is used by Compact too") end

section("switching")
E.settings:set("interface", "Tasability")
M.steps(2)
eq(ui.live, "Tasability", "Compact is live")
eq(ui:isCompact(), true, "isCompact")
eq(ui:newActive(), true, "the shared machinery is active (bar, Inspector, pointer)")
check(ui.compact ~= nil, "the Compact interface exists")
eq(ui.dock.gui.Visible, false, "no Dock in Compact")
ui.wm:open("settings")
M.steps(1)
eq(ui.wm.windows.settings.holder.Visible, false, "the New windows stay hidden in Compact")
ui.wm:open("merge")
M.steps(1)
eq(ui.wm.windows.merge.holder.Visible, true, "but the Merge window shows")
ui.wm:close("merge")
ui.wm:close("settings")
ui.sounds.last = nil
ui.sounds:play("click")
check(ui.sounds.last ~= nil or ui.sounds.sounds.click == nil, "interface sounds play in Compact")
eq(E.settings:set("interface", "Bogus"), false, "the setting refuses an unknown value")
ui:setInterface("Bogus")
M.steps(2)
eq(ui.live, "New", "an unknown value is New")
eq(ui.dock.gui.Visible, true, "the Dock is back")
eq(ui:isCompact(), false, "not Compact")
E.settings:set("interface", "Tasability")
M.steps(2)
E.settings:set("interface", "Classic")
M.steps(2)
eq(ui.live, "Classic", "Compact -> Classic")
eq(ui:newActive(), false, "Classic: the shared machinery idle")
ui.classicOnly = true
E.settings:set("interface", "Tasability")
M.steps(2)
eq(ui.live, "Classic", "a phone stays Classic")
ui.classicOnly = false
E.settings:set("interface", "New")
M.steps(2)
eq(ui.live, "New", "back to New")
finish()
