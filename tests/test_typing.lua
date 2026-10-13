-- HappaTAS keys and typing:
--   * the Menu key works whatever Ignore Game Processed says (also when the game processed the key)
--   * no HappaTAS key does anything while the player types: in chat (TextChatService), in a game text
--     box, or in HappaTAS's own slot name / settings boxes (which GetFocusedTextBox() doesn't report),
--     or while the Roblox menu is open; typed keys are not recorded into the TAS
check(boot(30), "boots")
local S, Core = __T.Settings, __T.Core
local C = Core.State
local guard = 0
while not (C.HRP and C.Humanoid) and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local UIS = M.services.UserInputService
local menu = C.Gui.MainMenu
local function press(kc, proc)
	M.pressKey(kc, proc)
	M.releaseKey(kc, proc)
	M.steps(2)
end

section("Menu key ignores game processed input")
S.Set("Ignore Game Processed", 0)
eq(menu.Visible, false, "menu starts closed")
press(Enum.KeyCode.M, false)
eq(menu.Visible, true, "M opens the menu")
press(Enum.KeyCode.M, true)
eq(menu.Visible, false, "M closes it even when the game processed the key (setting off)")
press(Enum.KeyCode.M, true)
eq(menu.Visible, true, "and opens it again")
press(Enum.KeyCode.M, false)
press(Enum.KeyCode.Two, true)
eq(Core.GetMode(), 1, "other controls still follow Ignore Game Processed (off: a processed key is ignored)")

section("typing in HappaTAS's own boxes (Ignore Game Processed on)")
S.Set("Ignore Game Processed", 1)
local box = menu.SettingsFrame.List["Playback Speed"].Input
M.focus(box)
eq(UIS:GetFocusedTextBox(), nil, "GetFocusedTextBox() doesn't see a box under gethui (like Roblox)")
press(Enum.KeyCode.Two, true)
eq(Core.GetMode(), 1, "2 typed in a settings box doesn't switch to Create")
press(Enum.KeyCode.M, true)
eq(menu.Visible, false, "M typed in a settings box doesn't toggle the menu")
press(Enum.KeyCode.F6, true)
eq(S.Get("Show MicroProfiler"), 0, "F6 typed in a box doesn't open the MicroProfiler")
M.focus(nil)
-- a save slot's name box (slots are added after the interface is built)
menu.SavesFrame.YourSlots.Top.AddSlot.MouseButton1Click:Fire()
M.steps(2)
local slot
for _, ch in ipairs(menu.SavesFrame.YourSlots:GetChildren()) do
	if tostring(ch.Name):sub(1, 5) == "Slot_" then slot = ch end
end
check(slot ~= nil, "a slot was added")
if slot then
	M.focus(slot.N)
	press(Enum.KeyCode.Two, true)
	press(Enum.KeyCode.Three, true)
	eq(Core.GetMode(), 1, "typing a slot name doesn't trigger Create / Test")
	press(Enum.KeyCode.M, true)
	eq(menu.Visible, false, "M typed in a slot name doesn't toggle the menu")
	M.focus(nil)
end
press(Enum.KeyCode.Two, false)
eq(Core.GetMode(), 2, "after the box lost focus, 2 works again")
press(Enum.KeyCode.One, false)
eq(Core.GetMode(), 1, "and 1")

section("typing in a game text box")
local pg = M.player:FindFirstChildOfClass("PlayerGui")
local sg = Instance.new("ScreenGui"); sg.Parent = pg
local gameBox = Instance.new("TextBox"); gameBox.Parent = sg
M.focus(gameBox)
check(UIS:GetFocusedTextBox() == gameBox, "a game box is reported")
press(Enum.KeyCode.Two, true)
eq(Core.GetMode(), 1, "2 typed in a game box doesn't switch to Create")
press(Enum.KeyCode.M, true)
eq(menu.Visible, false, "M typed in a game box doesn't toggle the menu")
M.focus(nil)

section("chatting (TextChatService)")
M.chatBar.IsFocused = true
press(Enum.KeyCode.Two, true)
eq(Core.GetMode(), 1, "2 typed in chat doesn't switch to Create")
press(Enum.KeyCode.M, true)
eq(menu.Visible, false, "M typed in chat doesn't toggle the menu")
press(Enum.KeyCode.F6, true)
eq(S.Get("Show MicroProfiler"), 0, "F6 typed in chat doesn't open the MicroProfiler")
S.Set("Ignore Game Processed", 0)
press(Enum.KeyCode.M, true)
eq(menu.Visible, false, "M typed in chat doesn't toggle the menu with the setting off either")
S.Set("Ignore Game Processed", 1)
M.chatBar.IsFocused = false

section("Roblox menu open")
M.services.GuiService.MenuIsOpen = true
press(Enum.KeyCode.Two, false)
eq(Core.GetMode(), 1, "2 does nothing while the Roblox menu is open")
press(Enum.KeyCode.M, false)
eq(menu.Visible, false, "M does nothing while the Roblox menu is open")
M.services.GuiService.MenuIsOpen = false

section("clicks on HappaTAS windows never pause / unpause (Ignore Game Processed on)")
S.Set("Ignore Game Processed", 1)
press(Enum.KeyCode.Two, false)
eq(Core.GetMode(), 2, "Create")
check(Core.IsPaused(), "paused")
if not menu.Visible then press(Enum.KeyCode.M, false) end
eq(menu.Visible, true, "menu open")
M.moveMouse(960, 540 + M.inset) -- the middle of the menu
M.mouseDown(1, true); M.mouseUp(1, true); M.steps(3)
check(Core.IsPaused(), "a click on a menu button doesn't unpause")
M.mouseDown(1, false); M.mouseUp(1, false); M.steps(3)
check(Core.IsPaused(), "a click on the menu background doesn't unpause either")
press(Enum.KeyCode.M, false)
eq(menu.Visible, false, "menu closed")
M.mouseDown(1, false); M.mouseUp(1, false); M.steps(3)
check(not Core.IsPaused(), "with the menu closed the same click unpauses")
M.mouseDown(1, false); M.mouseUp(1, false); M.steps(3)
check(Core.IsPaused(), "and pauses again")
M.moveMouse(300, 900)
press(Enum.KeyCode.One, false)
eq(Core.GetMode(), 1, "back to Idle")

section("keys typed in chat are not recorded")
press(Enum.KeyCode.Two, false)
eq(Core.GetMode(), 2, "Create")
M.services.UserInputService.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
M.steps(3)
check(not Core.IsPaused(), "recording")
M.chatBar.IsFocused = true
press(Enum.KeyCode.H, true)
press(Enum.KeyCode.I, true)
M.chatBar.IsFocused = false
press(Enum.KeyCode.W, false)
M.steps(3)
M.services.UserInputService.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
M.steps(3)
local seen = {}
for _, fr in ipairs(Core.GetTAS()) do
	for _, e in ipairs(fr.Input or {}) do seen[e] = true end
end
check(not seen[8] and not seen[9], "H and I typed in chat were not recorded")
check(seen[23] == true, "W pressed afterwards was recorded")
finish()
