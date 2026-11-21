-- needs: ui
-- ================================================================================================
-- HappaTAS 3: the speed hack slider
-- Before: dragging it showed "Speed Hack: 0.37x ..." on every mouse move (one notification per change), and
-- at the low end the knob (centred on the track's end) covered the number beside it.
-- Now: the speed changes live while dragging, the notification comes once you let the value settle; the knob
-- stays inside the track.
-- ================================================================================================
check(boot(30), "boots")
local E = getgenv().__HappaTAS3_T.engine
local ui = E.ui
local s = E.settings
local guard = 0
while not E.char:loaded() and guard < 200 do M.step(1 / 60); guard = guard + 1 end
UIH.click(ui.dock.buttons.settings.gui)
local sw = ui.settingsWin
local function reveal(key)
	local r = sw.rows[key]
	local y = r.row.gui.Position.Y.Offset
	sw.list.CanvasPosition = Vector2.new(0, math.max(0, y - 40))
	M.steps(1)
	return r
end
local statuses = {}
E.bus:on("status", function(text) statuses[#statuses + 1] = text end)
local function speedNotes()
	local n = 0
	for _, t in ipairs(statuses) do if t:find("^Speed Hack: ") then n = n + 1 end end
	return n
end

s:set("speedHack", 1)
s:set("speedHackSpeed", 0.5)
M.steps(60)
local row = reveal("speedHackSpeed")
local sl = row.ctl
local track = sl.track
local function at(a)
	local x0, w = track.AbsolutePosition.X, track.AbsoluteSize.X
	return Vector2.new(x0 + a * w, track.AbsolutePosition.Y + track.AbsoluteSize.Y / 2)
end

section("dragging: the speed follows the knob, one notification")
statuses = {}
UIH.press(at(0.5))
M.steps(1)
local seen = {}
for i = 1, 30 do
	local a = 0.5 + 0.45 * math.sin(i / 3)
	UIH.move(at(a))
	M.steps(1)
	seen[s:get("speedHackSpeed")] = true
end
local distinct = 0
for _ in pairs(seen) do distinct = distinct + 1 end
check(distinct > 10, "the speed changed live while dragging (" .. distinct .. " values)")
UIH.release(at(0.2))
M.steps(60)
eq(speedNotes(), 1, "one notification for the whole drag")
check(statuses[#statuses]:find(tostring(s:get("speedHackSpeed")), 1, true) ~= nil, "it says the final speed (" .. tostring(statuses[#statuses]) .. ")")

section("typing a value: one notification")
statuses = {}
UIH.click(sl.label)
M.steps(1)
UIH.typeInto(sl.box, "0.3", true)
M.steps(60)
eq(s:get("speedHackSpeed"), 0.3, "typed 0.3")
eq(speedNotes(), 1, "one notification")

section("the knob stays inside the track, clear of the number")
s:set("speedHackSpeed", 0.1)
M.steps(2)
local knob, label = sl.knob, sl.label
check(knob.AbsolutePosition.X >= track.AbsolutePosition.X - 0.01,
	"at the minimum the knob starts at the track's start (" .. knob.AbsolutePosition.X .. " vs " .. track.AbsolutePosition.X .. ")")
check(knob.AbsolutePosition.X >= label.AbsolutePosition.X + label.AbsoluteSize.X, "and doesn't cover the number")
s:set("speedHackSpeed", 1)
M.steps(2)
check(knob.AbsolutePosition.X + knob.AbsoluteSize.X <= track.AbsolutePosition.X + track.AbsoluteSize.X + 0.01, "at the maximum it ends at the track's end")
-- (a press at the track's ends gives the ends: the knob's centre travels a shorter way)
UIH.click(at(0))
M.steps(1)
eq(s:get("speedHackSpeed"), 0.1, "a press at the start: the minimum")
UIH.click(at(1))
M.steps(1)
eq(s:get("speedHackSpeed"), 1, "a press at the end: the maximum")
do
	-- (a press under where the knob's centre sits for 0.3 gives 0.3)
	local k = sl.knob.AbsoluteSize.X
	local x = track.AbsolutePosition.X + k / 2 + (0.3 - 0.1) / 0.9 * (track.AbsoluteSize.X - k)
	UIH.click(Vector2.new(x, track.AbsolutePosition.Y + 2))
	M.steps(1)
	check(math.abs(s:get("speedHackSpeed") - 0.3) < 0.006, "a press where the knob's centre would be for 0.3: 0.3 (" .. s:get("speedHackSpeed") .. ")")
end
s:set("speedHackSpeed", 0.55)
M.steps(2)
local kc = knob.AbsolutePosition.X + knob.AbsoluteSize.X / 2
local fillEnd = sl.fill.AbsolutePosition.X + sl.fill.AbsoluteSize.X
check(math.abs(kc - fillEnd) < 0.6, "the fill ends under the knob's centre (" .. kc .. " / " .. fillEnd .. ")")

s:set("speedHack", 0)
finish()
