-- needs: ui
-- ================================================================================================
-- HappaTAS 3, V3.1: an open window (New interface) or the Tasability window doesn't unlock the mouse while the
-- game wants it locked (shift lock, first person); holding Ctrl frees it to use the windows (headless mock)
-- ================================================================================================
local mlc = { isMouseLocked = false }
function mlc:GetIsMouseLocked() return self.isMouseLocked end
function mlc:OnMouseLockToggled() self.isMouseLocked = not self.isMouseLocked end
M.gcTables = { { activeMouseLockController = mlc }, mlc }

check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local ui = E.ui
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local UIS = M.services.UserInputService
local LOCK, FREE = Enum.MouseBehavior.LockCenter, Enum.MouseBehavior.Default
local function click()
	UIS.InputBegan:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.Begin), false)
	UIS.InputEnded:Fire(M.input(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, Enum.UserInputState.End), false)
end
ui.wm:close("inspector")

section("New interface, a window open, shift lock on")
ui.wm:open("settings")
M.steps(2)
eq(E.modal, true, "(a modal window is open)")
mlc.isMouseLocked = true
M.steps(2)
eq(E.cs:isMouseFree(), false, "Idle: the window doesn't free the mouse in shift lock")
E.modes:request("create")
M.steps(3)
E.modes:request("unpause")
M.steps(5)
eq(UIS.MouseBehavior, LOCK, "recording: the mouse stays locked (LockCenter)")
M.pressKey(Enum.KeyCode.LeftControl)
M.steps(2)
eq(UIS.MouseBehavior, FREE, "Ctrl held: free, to use the window")
M.releaseKey(Enum.KeyCode.LeftControl)
M.steps(2)
eq(UIS.MouseBehavior, LOCK, "Ctrl let go: locked again")
mlc.isMouseLocked = false
M.steps(2)
eq(UIS.MouseBehavior, FREE, "shift lock off: the window frees the mouse as before")
E.modes:request("pause")
M.steps(2)
E.modes:request("idle")
M.steps(2)
ui.wm:close("settings")

section("Tasability: its window is open, shift lock on")
E.settings:set("interface", "Tasability")
M.steps(2)
eq(E.modal, true, "(the Tasability window counts as open)")
E.modes:request("create")
M.steps(3)
E.modes:request("unpause")
mlc.isMouseLocked = true
M.steps(5)
eq(UIS.MouseBehavior, LOCK, "recording in shift lock: locked")
E.modes:request("pause")
M.steps(2)
E.modes:request("idle")
mlc.isMouseLocked = false
M.steps(2)
E.settings:set("interface", "New")
M.steps(2)
finish()
