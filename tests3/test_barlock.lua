-- needs: ui
-- ================================================================================================
-- HappaTAS 3: dragging the timeline across shift lock / first person frames
-- Paused with Lock Camera (Paused), a frame recorded in shift lock or first person locks the mouse in the
-- centre (LockCenter). Before: dragging the playhead onto such a frame grabbed the cursor mid-drag. Now the
-- mouse stays free while it is on HappaTAS's interface (or a press on it isn't released yet), or Ctrl is held.
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local ui = E.ui
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
local UIS = M.services.UserInputService
local LockCenter = Enum.MouseBehavior.LockCenter
local bar = ui.bar
local function trackY() return bar.track.AbsolutePosition.Y + bar.track.AbsoluteSize.Y / 2 end
local function tx(f) return bar.track.AbsolutePosition.X + bar:xOf(f) * ui.root.scale.Scale end
local function at(f) return Vector2.new(tx(f), trackY()) end

E.settings:set("lockCameraPaused", 1)
E.modes:request("create")
M.steps(3)
UIH.click(bar.buttons.rec.gui)
M.steps(60, 1 / 60)
UIH.click(bar.buttons.rec.gui)
M.steps(2)
local n = E.tl:count()
check(E.paused and n > 40, "paused with a run (" .. n .. " frames)")
-- (the second half recorded in shift lock)
local half = math.floor(n / 2)
for i = half, n do E.tl:set("ShiftLock", i, 1, 1) end

section("paused on a shift lock frame away from the interface: the mouse is locked, as before")
E.modes:seek(n)
UIH.move(Vector2.new(400, 60))
M.steps(3)
eq(UIS.MouseBehavior, LockCenter, "locked in the centre")

section("dragging the playhead from a normal frame onto shift lock frames: the mouse stays free")
E.modes:seek(5)
UIH.move(at(5))
M.steps(3)
check(UIS.MouseBehavior ~= LockCenter, "free on a normal frame")
UIH.press(at(5))
M.steps(1)
local locked = 0
for f = 10, n - 2, 4 do
	UIH.move(at(f))
	M.steps(1)
	if UIS.MouseBehavior == LockCenter then locked = locked + 1 end
end
check(E.frame >= half, "the playhead went onto the shift lock frames (" .. E.frame .. ")")
eq(locked, 0, "never locked while dragging")
UIH.release(at(n - 2))
M.steps(3)
check(UIS.MouseBehavior ~= LockCenter, "let go over the bar: still free")

section("leaving the interface: the frame's lock comes back")
UIH.move(Vector2.new(400, 60))
M.steps(3)
eq(UIS.MouseBehavior, LockCenter, "off the interface: locked")

section("Ctrl held: free anywhere while paused")
M.pressKey(Enum.KeyCode.LeftControl)
M.steps(3)
check(UIS.MouseBehavior ~= LockCenter, "Ctrl held: free")
M.releaseKey(Enum.KeyCode.LeftControl)
M.steps(3)
eq(UIS.MouseBehavior, LockCenter, "Ctrl let go: locked again")

E.modes:request("idle")
M.steps(3)
finish()
