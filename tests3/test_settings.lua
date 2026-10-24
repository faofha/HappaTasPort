-- ================================================================================================
-- HappaTAS 3, phase 2: settings schema, controls, key names, the typing check
-- ================================================================================================
check(boot(3), "boots")
local Settings = __T3("engine/settings")
local Controls = __T3("engine/controls")
local Keys = __T3("engine/keys")
local Typing = __T3("platform/typing")
local Util = __T3("engine/util")
local Errors = __T3("kernel/errors")
local Lifecycle = __T3("kernel/lifecycle")

section("every V2 setting is in the schema")
local V2_NAMES = {
	"Lock Camera (Test)", "Interpolate Playback", "Playback Speed", "Restart When Testing", "Show Completion Message",
	"Lock Camera (Paused)", "Record Death & Respawn", "Record Tool Actions", "Ignore Game Processed",
	"Speed Hack", "Speed Hack Speed", "Speed Hack Frame Step",
	"Replay Keyboard", "Replay Mouse Clicks", "Replay Mouse Movement", "Normalize Mouse UV", "NohBoard Cursor",
	"Invisible Mouse Speed Multiplier", "Window Guarding",
	"Sync Client Objects", "Smooth Client Objects", "Frustum Culling CO", "Sync Button Timers", "Sync Lighting",
	"Kit Scripts On TAS Clock", "Sync Kit Objects",
	"Show Stats (Idle)", "Show Stats (Create)", "Show Stats (Test)", "Stats Text Size", "Show MicroProfiler",
	"MicroProfiler Scale", "MicroProfiler Text Offset", "Allow PlayerGui Interface",
	"Enable Keyboard Sounds", "Enable Click Sounds", "Sound Trigger Mode", "Sound Volume", "Dynamic Pitch Variation",
}
eq(#Settings.SCHEMA, 39, "39 rows")
local seenV2, seenKey = {}, {}
for _, row in ipairs(Settings.SCHEMA) do
	check(not seenKey[row.key], "unique key " .. tostring(row.key))
	seenKey[row.key] = true
	seenV2[row.v2] = (seenV2[row.v2] or 0) + 1
end
for _, n in ipairs(V2_NAMES) do eq(seenV2[n], 1, "V2 name in the schema once: " .. n) end
eq(Settings.byV2["Lock Camera (Test)"].key, "lockCameraTest", "byV2")
eq(Settings.byV2["Invisible Mouse Speed Multiplier"].key, "invisibleMouseSpeed", "byV2 (shortened key)")

section("defaults are V2's")
local errsPrinted = {}
local errs = Errors.new(function(m) errsPrinted[#errsPrinted + 1] = m end)
local s = Settings.new(errs)
eq(s:get("playbackSpeed"), 1, "playbackSpeed")
eq(s:get("ignoreGameProcessed"), 0, "ignoreGameProcessed")
eq(s:get("speedHackSpeed"), 0.5, "speedHackSpeed")
eq(s:get("statsTextSize"), 11, "statsTextSize")
eq(s:get("soundVolume"), 50, "soundVolume")
eq(s:get("syncClientObjects"), 0, "syncClientObjects")
eq(s:on("lockCameraTest"), true, "lockCameraTest on")
eq(s:on("speedHack"), false, "speedHack off")

section("sanitise")
check(s:set("speedHack", 5), "toggle set")
eq(s:get("speedHack"), 1, "toggle 5 -> 1")
s:set("speedHackSpeed", 9); eq(s:get("speedHackSpeed"), 4, "max 4")
s:set("speedHackSpeed", 0.01); eq(s:get("speedHackSpeed"), 0.1, "min 0.1")
s:set("statsTextSize", 11.6); eq(s:get("statsTextSize"), 12, "integer rounding")
eq(s:set("playbackSpeed", 0), false, "playbackSpeed 0 refused")
eq(s:get("playbackSpeed"), 1, "unchanged")
eq(s:set("playbackSpeed", 0 / 0), false, "NaN refused")
eq(s:set("playbackSpeed", math.huge), false, "inf refused")
eq(s:set("noSuchSetting", 1), false, "unknown key refused")

section("listeners")
local calls = 0
local off = s:changed("playbackSpeed", function(v) calls = calls + 1 end)
s:changed("playbackSpeed", function() error("listener broke") end)
local after = 0
s:changed("playbackSpeed", function() after = after + 1 end)
s:set("playbackSpeed", 2)
s:set("playbackSpeed", 2)
eq(calls, 1, "called once per change, not for an equal value")
eq(after, 1, "a listener after a failing one still runs")
s:set("playbackSpeed", 3)
local n = 0
for _, m in ipairs(errsPrinted) do if m:find("listener broke", 1, true) then n = n + 1 end end
eq(n, 1, "the failing listener is reported once")
off()
s:set("playbackSpeed", 4)
eq(calls, 2, "off() removes a listener")

section("controls")
local c = Controls.new()
eq(#Controls.LIST, 17, "17 controls")
local want = {
	idle = "1", create = "2", test = "3", pause = "Left Click", unpause = "Left Click", forward = "T", back = "R",
	forward1 = "G", back1 = "F", unpause1 = "V", ["return"] = "E", lookAround = "L", optimize = "Q",
	deleteTas = "Backspace", menu = "M", microProfiler = "F6", toggleSpeedHack = "None",
}
for k, v in pairs(want) do eq(c:get(k), v, "default key of " .. k) end
local function key(kc) return M.input(Enum.UserInputType.Keyboard, kc, Enum.UserInputState.Begin) end
check(c:matches(key(Enum.KeyCode.Two), "create"), "2 matches create")
check(not c:matches(key(Enum.KeyCode.Three), "create"), "3 doesn't match create")
check(c:matches(M.input(Enum.UserInputType.MouseButton1), "pause"), "Left Click matches pause")
check(not c:matches(key(Enum.KeyCode.Unknown), "toggleSpeedHack"), "None never matches")
c:set("create", "K")
check(c:matches(key(Enum.KeyCode.K), "create"), "rebound key matches")
eq(Keys.toKey["Num5"], Enum.KeyCode.KeypadFive, "key names: Num5")
eq(Keys.fromKey[Enum.KeyCode.Two], "2", "key names: Two -> 2")
eq(Controls.byV2["Unpause 1 Frame"].key, "unpause1", "controls byV2")

section("util")
eq(Util.round(-0.0001, 1000), 0, "round -0 -> 0")
check(1 / Util.round(-0.0001, 1000) > 0, "really +0")
eq(Util.round(1.23456, 1000), 1.235, "round to 1/1000")
eq(Util.toTime(65.5), "1:05.5", "toTime")
eq(Util.toTime(5), "0:05", "toTime whole seconds")

section("typing")
local life = Lifecycle.new()
local t = Typing.new(life)
local UIS = M.services.UserInputService
eq(t:active(nil), false, "nothing focused")
local hui = Instance.new("ScreenGui"); hui.Parent = M.hui -- (under gethui(), like our interface)
local ownBox = Instance.new("TextBox"); ownBox.Parent = hui
t:watch(hui)
M.focus(ownBox)
eq(UIS:GetFocusedTextBox(), nil, "GetFocusedTextBox doesn't see our box")
eq(t:active(nil), true, "our own box focused")
M.focus(nil)
eq(t:active(nil), false, "lost focus")
local later = Instance.new("TextBox"); later.Parent = hui
M.focus(later)
eq(t:active(nil), true, "a box added later counts too")
M.focus(nil)
local pg = M.player:FindFirstChildOfClass("PlayerGui")
local sg = Instance.new("ScreenGui"); sg.Parent = pg
local gameBox = Instance.new("TextBox"); gameBox.Parent = sg
M.focus(gameBox)
eq(t:active(nil), true, "a game text box")
M.focus(nil)
M.chatBar.IsFocused = true
eq(t:active(nil), true, "the chat bar")
M.chatBar.IsFocused = false
M.services.GuiService.MenuIsOpen = true
eq(t:active(nil), true, "the Roblox menu")
M.services.GuiService.MenuIsOpen = false
t.rebinding = true
eq(t:active(nil), true, "rebinding")
t.rebinding = false
local inp = key(Enum.KeyCode.Q)
t.boundInput = inp
eq(t:active(inp), true, "the input that set a new key")
eq(t:active(key(Enum.KeyCode.W)), false, "another input")
life:cleanup()
finish()
