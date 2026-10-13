-- ================================================================================================
-- MicroProfiler tests (V2.36): look, menus, Time / Avg / Max / Aggregate semantics, modes, dumps
-- ================================================================================================
local function rgb(c) local r, g, b = M.rgb255(c); return r .. "," .. g .. "," .. b end
local function seqEnds(seq) return rgb(seq.Keypoints[1].Value), rgb(seq.Keypoints[#seq.Keypoints].Value) end
local function stepMs(ms, n) for _ = 1, (n or 1) do M.step(ms / 1000) end end
-- the mouse moves through UserInputService.InputChanged like in Roblox (screen pixels in, InputObject.Position
-- = screen - top bar inset); M.mouse alone (no event) tests the GetMouseLocation fallback
local function mouse(x, y) M.moveMouse(x, y) end
local function away() mouse(960, 700) end

section("boot")
check(boot(5), "script boots")
local P, S = __T.Profiler, __T.Settings
check(type(P) == "table" and type(P.FrameBegin) == "function", "profiler module exposed")
check(P.active == false, "closed by default")
away()
S.Set("Show MicroProfiler", 1)
M.step(1 / 60)
check(P.active == true, "Show MicroProfiler opens it")
local U, I = P.Internals()
check(U.root ~= nil and U.root.Visible, "profiler root visible")
check(U.root:IsDescendantOf(M.hui), "parented under gethui()")

section("font: Roboto Mono Bold, 6 px grid, 1 px black drop shadow")
local ff = U.title.sh.FontFace
eq(ff and ff.Family, "rbxasset://fonts/families/RobotoMono.json", "font family Roboto Mono")
check(ff and ff.Weight == Enum.FontWeight.Bold, "font weight Bold")
near(U.title.sh.TextSize, 10, 0.01, "TextSize 10 = 6 px per character")
eq(rgb(U.title.lb.TextColor3), "255,255,255", "text white")
eq(rgb(U.title.sh.TextColor3), "0,0,0", "shadow black")
check(U.title.lb.Position == UDim2.fromOffset(-1, -1), "shadow sits 1 px right and down")
eq(U.title.sh.Text, "MicroProfiler", "title is MicroProfiler")
check(U.title.sh.TextXAlignment == Enum.TextXAlignment.Left and U.title.sh.TextYAlignment == Enum.TextYAlignment.Top, "text aligned top-left")
local tb = U.title.sh.TextBounds
near(tb.X, 13 * 6, 0.5, "13 characters are 78 px wide")
-- the mock's default text model: a line is one em (TextSize) tall -> baseline 8.88 px under the top,
-- so the labels move up 1 px to put it at 7.5 (Roblox's MicroProfiler: capitals on rows 0-7)
local dy, auto, nudge = P.TextOffset()
eq(auto, -1, "automatic text offset for an em-high line")
eq(dy, -1, "no manual correction")
check(U.title.sh.Position == UDim2.fromOffset(1, 0), "title shadow at (x+1, y+1-1)")

section("menu bar layout (MicroProfileDrawMenu)")
local names = { "Mode", "Groups", "Aggregate[60]", "Timers", "Options", "Preset", "Custom", "[Dump]", "Flamegraphs", "Pause", "Help", "Network" }
local x = (14 + 2) * 6
for i, n in ipairs(names) do
	eq(U.items[i].t.s, n, "menu item " .. i)
	eq(I.menuX[i], x, "menu x of " .. n)
	x = x + (#n + 1) * 6
end
check(U.menu.Size == UDim2.new(1, 0, 0, 10), "menu bar is 10 px tall")
eq(rgb(U.menu.BackgroundColor3), "49,49,49", "menu bar 0x313131")
check(U.graph.f.Position == UDim2.fromOffset(0, 10) and U.graph.f.Size == UDim2.new(1, -50, 0, 50), "graph 50 px under the menu, room for the close box")
eq(rgb(U.graph.f.BackgroundColor3), "71,71,71", "graph 0x474747")
eq(#U.bars, 508, "508 frame bars (512 - GPU delay - 1)")
check(U.close.f.Size == UDim2.fromOffset(50, 50) and U.close.f.Position == UDim2.new(1, -50, 0, 10), "50x50 close box at the right")
local xLines = 0
for _, c in ipairs(U.close.f:GetChildren()) do if c:IsA("Frame") and (c.Rotation == 45 or c.Rotation == -45) then xLines = xLines + 1 end end
eq(xLines, 2, "close box draws an X")
local ap, as = U.graph.f.AbsolutePosition, U.graph.f.AbsoluteSize
-- AbsolutePosition is measured from the bottom of the top bar (GuiBase2d.AbsolutePosition docs)
check(ap.Y == 10 - M.inset and as.X == 1870 and as.Y == 50, "graph absolute 0,10-inset 1870x50 on 1920x1080")

section("readout format")
local s = U.readout.s
check(s:match("^Time%[%s*%d+%.%d%d%] Avg%[%s*%d+%.%d%d%] Max%[%s*%d+%.%d%d%]$") ~= nil and #s:match("Avg%[(.-)%]") == 6, "Time[%6.2f] Avg[%6.2f] Max[%6.2f]: " .. s)
eq(U.readout.x + #s * 6, 1920, "readout is right-aligned")

section("Avg = the frames on the bar, Max = the biggest frame (any Aggregate)")
local MENUS = P.Menus
eq(P.Config().aggregate, 60, "default aggregate is 60")
local s0 = P.Snapshot()
check(s0.onBar > 0 and s0.onBar < 508, "only a few frames on the bar so far (" .. s0.onBar .. ")")
near(s0.avg, 1000 / 60, 1e-6, "before the bar is full, Avg = the frames recorded so far")
stepMs(10, 600)
eq(P.Snapshot().onBar, 508, "the bar holds 508 frames")
check(U.readout.s:find("^Time%[ 10%.00%] Avg%[ 10%.00%]") ~= nil, "600 frames of 10 ms -> Avg 10.00: " .. U.readout.s)
near(P.Snapshot().max, 1000 / 60, 1e-6, "Max still holds the 16.67 ms frames from before")
stepMs(50)
eq(U.readout.s, "Time[ 50.00] Avg[ 10.08] Max[ 50.00]", "spike: Avg = (507*10+50)/508")
stepMs(10, 507)
eq(U.readout.s, "Time[ 10.00] Avg[ 10.08] Max[ 50.00]", "507 frames later the spike is the oldest bar, still averaged")
stepMs(10)
eq(U.readout.s, "Time[ 10.00] Avg[ 10.00] Max[ 50.00]", "the spike left the bar: Avg drops, Max stays")
stepMs(10, 700)
eq(U.readout.s, "Time[ 10.00] Avg[ 10.00] Max[ 50.00]", "Max stays indefinitely")
eq(U.items[3].t.s, "Aggregate[60]", "label shows Aggregate[60]")

section("the Aggregate setting does not change Time / Avg / Max")
local r1 = U.readout.s
MENUS[3].click(5) -- 120
stepMs(10)
eq(U.readout.s, r1, "Aggregate 120: same readout")
MENUS[3].click(1) -- 10
stepMs(10)
eq(U.readout.s, r1, "Aggregate 10: same readout")
eq(U.items[3].t.s, "Aggregate[10]", "label shows the window size")
MENUS[3].click(4) -- 60
stepMs(10)
eq(U.readout.s, r1, "Aggregate 60: same readout")

section("Infinite: the label counts every frame, picking it resets Max")
MENUS[3].click(0) -- Infinite
eq(P.Config().aggregate, 0, "Infinite selected")
stepMs(10)
eq(U.readout.s, "Time[ 10.00] Avg[ 10.00] Max[ 10.00]", "picking Infinite resets Max to the biggest frame on the bar")
eq(P.Snapshot().count, 0, "the count restarts (nAggregateClear)")
eq(U.items[3].t.s, "Aggregate[0]", "label after the restart")
stepMs(10)
eq(U.items[3].t.s, "Aggregate[1]", "Aggregate[1]")
stepMs(10)
eq(U.items[3].t.s, "Aggregate[2]", "Aggregate[2]")
stepMs(10, 3)
eq(U.items[3].t.s, "Aggregate[5]", "Aggregate[5]")
stepMs(120)
eq(U.readout.s, "Time[120.00] Avg[ 10.22] Max[120.00]", "spike: Avg = (507*10+120)/508")
stepMs(10, 100)
eq(U.readout.s, "Time[ 10.00] Avg[ 10.22] Max[120.00]", "Infinite gives the same Avg / Max as 60")
eq(U.items[3].t.s, "Aggregate[106]", "label counts every frame")
check(I.menuX[4] == I.menuX[3] + (#"Aggregate[106]" + 1) * 6, "menu items after Aggregate move with the label")
stepMs(200)
eq(U.readout.s:match("Max%[(.-)%]"), "200.00", "only a bigger frame replaces Max")
stepMs(10, 520)
eq(U.readout.s, "Time[ 10.00] Avg[ 10.00] Max[200.00]", "spikes gone from the bar, Max still 200")
MENUS[3].click(0) -- Infinite again = reset
stepMs(10)
eq(U.readout.s, "Time[ 10.00] Avg[ 10.00] Max[ 10.00]", "picking Infinite again resets Max")

section("Hidden mode works the same, the bar is just invisible")
check(P.SetMode("Hidden"), "Hidden mode")
check(not U.graph.f.Visible and not U.close.f.Visible, "graph and close box hidden")
check(U.menu.Visible ~= false and U.root.Visible, "menu bar still shown")
local c0 = P.Snapshot().count
stepMs(20, 10)
eq(P.Snapshot().count, c0 + 10, "frames still counted in Hidden")
eq(U.items[3].t.s, "Aggregate[" .. (c0 + 10) .. "]", "label still counts in Hidden")
eq(U.readout.s, "Time[ 20.00] Avg[ 10.20] Max[ 20.00]", "Avg = the 508 frames that would be on the bar (498*10+10*20)/508")
stepMs(20, 600)
eq(U.readout.s, "Time[ 20.00] Avg[ 20.00] Max[ 20.00]", "the hidden bar keeps scrolling")
P.SetMode("Frame")
check(U.graph.f.Visible, "graph back in Frame mode")

section("Pause / Unpause / Force Enable")
local snap = P.Snapshot()
P.TogglePause()
stepMs(30, 5)
local s2 = P.Snapshot()
eq(s2.recorded, snap.recorded, "paused: no frames recorded")
eq(s2.count, snap.count, "paused: aggregate frozen")
eq(s2.time, snap.time, "paused: Time frozen")
eq(U.items[10].t.s, "Unpause", "menu shows Unpause")
eq(I.menuX[11], I.menuX[10] + (#"Unpause" + 1) * 6, "Help moves after Unpause")
MENUS[1].click(7)     -- Force Enable
check(P.Config().force == true, "Force Enable on")
stepMs(30, 3)
eq(P.Snapshot().recorded, snap.recorded + 3, "Force Enable records while paused")
eq(P.Snapshot().count, snap.count, "...but does not aggregate")
check(U.readout.s:find("^Time%[ 30%.00%]") ~= nil, "forced frames are on the bar and in the readout: " .. U.readout.s)
MENUS[1].click(7)
P.TogglePause()
stepMs(16)
eq(U.items[10].t.s, "Pause", "Pause again")
check(P.Snapshot().recorded == snap.recorded + 4, "recording resumed")

section("Avg stays exact over a long session (running sum is recounted)")
local vals = {}
local seed2 = 11
for i = 1, 5000 do
	seed2 = (seed2 * 1103515245 + 12345) % 2147483648
	local v = 5 + (seed2 % 1000) / 37
	vals[i] = v
	M.step(v / 1000)
end
local sum = 0
for i = 5000 - 507, 5000 do sum = sum + vals[i] end
near(P.Snapshot().avg, sum / 508, 1e-9, "Avg = exact average of the last 508 frames after 5000 frames")
local big = 0
for i = 1, 5000 do if vals[i] > big then big = vals[i] end end
check(P.Snapshot().max >= big, "Max is at least the biggest of these frames")

section("frame bars: height, colour (Jobs vs Render), strip position")
local function newestBar()
	local K = P.Snapshot().recorded
	return U.bars[(K - 1) % 508 + 1], K
end
M.stats.HeartbeatTime, M.stats.RenderCPUFrameTime = 0.004, 0.001
stepMs(33.33 / 2)
local b = newestBar()
eq(b.f.Size.Y.Offset, 25, "half the reference = 25 px")
local top, bottom = seqEnds(b.g.Color)
eq(top, "255,191,147", "orange top colour ((c+max)/2)")
eq(bottom, "147,83,39", "orange bottom colour ((c+min)/2)")
eq(b.g.Rotation, 90, "gradient runs top to bottom")
M.stats.HeartbeatTime, M.stats.RenderCPUFrameTime = 0.001, 0.004
stepMs(100)
b = newestBar()
eq(b.f.Size.Y.Offset, 50, "longer than the reference = full height")
top, bottom = seqEnds(b.g.Color)
eq(top, "146,199,238", "blue top colour")
eq(bottom, "55,107,146", "blue bottom colour")
local K = P.Snapshot().recorded
near(b.f.Position.X.Scale + 1 / 508 + U.strip.Position.X.Scale, 1, 1e-6, "newest bar ends at the right edge")
local prev = U.bars[(K - 2) % 508 + 1]
near(prev.f.Position.X.Scale + 1 / 508, b.f.Position.X.Scale, 1e-9, "bars are contiguous")
stepMs(5)
eq(newestBar().f.Size.Y.Offset, 8, "5 ms = ceil(5/33.33*50) = 8 px")
M.stats.HeartbeatTime, M.stats.RenderCPUFrameTime = 0.0012, 0.0021

section("Options: reference time")
MENUS[5].click(6)     -- 66.66ms (Reference header is line 0)
eq(P.Config().ref, 66.66, "reference 66.66 ms")
stepMs(33.33)
eq(newestBar().f.Size.Y.Offset, 25, "33.33 ms is half of 66.66")
MENUS[5].click(5)
eq(P.Config().ref, 33.33, "reference back to 33.33")

section("green selection = detailed view window")
stepMs(16, 40)
local hl = U.hl.f
check(hl.Visible, "selection visible")
K = P.Snapshot().recorded
near(hl.Position.X.Scale + U.strip.Position.X.Scale, 504 / 508, 1e-6, "default window starts at nFrameCurrent (3 frames behind)")
near(hl.Size.X.Scale, 4 / 508, 1e-9, "50 ms = the last 4 frames at 16 ms")
eq(rgb(hl.BackgroundColor3), "51,187,68", "0x33bb44")
near(hl.BackgroundTransparency, 1 - 0x77 / 255, 1e-6, "alpha 0x77")
-- click a bar 20 frames back: the 50 ms window is centred on it
local gw = 1870
local function barX(back) return gw - (back + 0.5) * gw / 508 end
mouse(barX(20), 30)
M.step(16 / 1000)
M.mouseDown(1)
M.step(16 / 1000)   -- the held left button centres the view during this frame
M.mouseUp(1)
local v = P.Snapshot()
near(v.offset, -(20 - 3) * 16 + 8 - 25, 0.01, "left click centres the 50 ms window on that frame")
near(v.range, 50, 1e-9, "range stays 50 ms")
local clickedK = P.Snapshot().recorded - 20
local cbar = U.bars[(clickedK - 1) % 508 + 1].f.Position.X.Scale
check(hl.Position.X.Scale <= cbar + 1e-9 and cbar < hl.Position.X.Scale + hl.Size.X.Scale, "the clicked frame is inside the green selection")
near(hl.Size.X.Scale, 5 / 508, 1e-9, "50 ms window centred on a 16 ms frame touches 5 frames")
M.click(2)
M.step(16 / 1000)
near(P.Snapshot().range, 16, 0.6, "right click zooms to exactly that frame")

section("hover tooltip on a frame")
away()
M.step(16 / 1000)
M.stats.RenderGPUFrameTime = 0.00173
stepMs(4.37, 5)
mouse(barX(0), 40)
M.step(4.37 / 1000)
local tip = U.tip
check(tip.outer.f.Visible, "tooltip visible over a bar")
local labels, values = {}, {}
for i = 1, tip.n do labels[i] = tip.rows[i].l.s; values[i] = tip.rows[i].v.s end
check(labels[1]:match("^Frame %d+$") ~= nil, "row 1 'Frame N'")
eq(labels[2], "CPU Time", "row 2 CPU Time")
eq(values[2], "  4.37ms", "CPU Time = that frame's time")
eq(labels[3], "GPU Time (device)", "row 3 GPU Time (device)")
eq(values[3], "  1.73ms", "GPU from Stats.RenderGPUFrameTime")
eq(labels[5], "Render Wall Time", "Render Wall Time")
eq(labels[6], "Jobs Wall Time", "Jobs Wall Time")
check(tip.rows[6].sq.f.Visible and rgb(tip.rows[6].sq.f.BackgroundColor3) == "215,40,20", "red square next to Jobs Wall Time")
eq(labels[8], "Mem Used", "Mem Used")
eq(values[8], "1234.5MB", "memory from Stats:GetTotalMemoryUsageMb")
eq(rgb(tip.outer.f.BackgroundColor3), "255,255,255", "white border")
eq(rgb(tip.inner.f.BackgroundColor3), "0,0,0", "black box")
local hov = P.Snapshot().hover
check(hov ~= nil, "a frame is hovered")
local hb = U.bars[(hov - 1) % 508 + 1]
top = seqEnds(hb.g.Color)
eq(top, "255,255,255", "hovered bar drawn white")
check(tip.outer.f.Position.Y.Offset == 40 + 20 - 1 or tip.outer.f.Position.Y.Offset <= 1080, "tooltip 20 px under the mouse")
away()
M.step(16 / 1000)
check(not tip.outer.f.Visible, "tooltip hidden when the mouse leaves")
top = seqEnds(hb.g.Color)
check(top ~= "255,255,255", "hovered colour restored")

section("menus open on hover, stay open inside, close outside")
local function ddTexts()
	local out = {}
	local dd = I.dd
	for n = 1, dd.count do out[n] = dd.lines[n].t.s end
	return out
end
local function hoverMenu(i)
	mouse(I.menuX[i] + 3, 4)
	M.step(16 / 1000)
end
hoverMenu(1)
check(U.dd.f.Visible, "Mode menu opens on hover")
eq(table.concat(ddTexts(), "|"), "  Detailed|  Timers|  Counters|* Frame|  Hidden|  Off|  ------|  Force Enable", "Mode menu lines")
eq(I.dd.width, (2 + 12) * 6, "dropdown width (2 + longest) characters")
check(U.dd.f.Position == UDim2.fromOffset(I.menuX[1], 9), "dropdown at the item, y = 9")
check(U.items[1].hl.f.Visible and rgb(U.items[1].hl.f.BackgroundColor3) == "136,136,136", "hovered item highlighted 0x888888")
mouse(I.menuX[1] + 20, 9 + 9 * 1 + 4)  -- line 2 (Timers)
M.step(16 / 1000)
check(U.dd.f.Visible, "stays open with the mouse inside")
check(I.dd.lines[2].hl.f.Visible and not I.dd.lines[1].hl.f.Visible, "hovered line highlighted")
mouse(960, 700)
M.step(16 / 1000)
M.step(16 / 1000)
check(not U.dd.f.Visible, "closes when the mouse leaves")
hoverMenu(2)
eq(table.concat(ddTexts(), "|"), "* [ALL]|* [default]|*    Engine|*    HappaTAS", "Groups menu lines")
hoverMenu(3)
eq(table.concat(ddTexts(), "|"), "* Infinite|       10|       20|       30|       60|      120", "Aggregate menu lines")
hoverMenu(4)
eq(table.concat(ddTexts(), "|"), "  Time|* Average|* Max|  Min|* Call Count|  Exclusive Timers|  Exclusive Average|  Exclusive Max|  ------", "Timers menu lines")
hoverMenu(5)
local opt = ddTexts()
eq(opt[1], "  Reference", "Options: Reference")
eq(opt[2], "      5.00ms", "Options: 5.00ms")
eq(opt[6], "*    33.33ms", "Options: 33.33ms selected")
eq(opt[11], "    1000.00ms", "Options: 1000.00ms")
eq(opt[12], "  BG Opacity", "Options: BG Opacity")
eq(opt[13], "*        25%", "Options: BG 25% selected")
eq(opt[17], "  FG Opacity", "Options: FG Opacity")
eq(opt[21], "*       100%", "Options: FG 100% selected")
eq(opt[22], "  Spike Display", "Options: Spike Display")
eq(opt[23], "    Enable", "Options: Enable")
hoverMenu(6)
local pr = ddTexts()
eq(pr[1], "  Load 'Default'", "Preset: Load 'Default'")
eq(pr[7], "  Load 'Sound'", "Preset: Load 'Sound'")
eq(pr[8], "  --", "Preset: --")
eq(pr[9], "  Save 'Default'", "Preset: Save 'Default'")
eq(#pr, 15, "Preset: 15 lines")
hoverMenu(7)
eq(table.concat(ddTexts(), "|"), "* Disable|  --|  TAS Timeline", "Custom menu lines")
hoverMenu(8)
local dumpLines = ddTexts()
eq(dumpLines[1], "  32 frames", "Dump: 32 frames")
eq(dumpLines[4], "  256 frames", "Dump: 256 frames")
check(dumpLines[5]:match("^  512 frames %(%d+ complete%)$") ~= nil, "Dump: 512 frames (N complete): " .. dumpLines[5])
eq(dumpLines[6], "  Include incomplete", "Dump: Include incomplete")
eq(dumpLines[7], "  Legacy HTML format", "Dump: Legacy HTML format")
eq(dumpLines[8], "  Dump in binary format (LibMP)", "Dump: binary")
hoverMenu(9)
eq(table.concat(ddTexts(), "|"), "* Disable|  --|  HappaTAS", "Flamegraphs menu lines")
hoverMenu(12)
eq(table.concat(ddTexts(), "|"), "  Verbosity Level|  Off|* Low|  High", "Network menu lines")
hoverMenu(10)
check(not U.dd.f.Visible, "Pause has no dropdown")
hoverMenu(11)
check(not U.dd.f.Visible, "Help has no dropdown")
check(U.help[1].outer.f.Visible and U.help[2].outer.f.Visible and U.help[3].outer.f.Visible, "Help hover shows the help windows")
eq(U.help[1].rows[1].l.s, "Left-Click", "help: Left-Click")
eq(U.help[1].rows[1].v.s, "Center View", "help: Center View")
away()
M.step(16 / 1000)
M.step(16 / 1000)
check(not U.help[1].outer.f.Visible, "help windows close")

section("clicking a dropdown line")
hoverMenu(1)
mouse(I.menuX[1] + 20, 9 + 9 * 1 + 4)
M.step(16 / 1000)
M.click(1)   -- Timers
M.step(16 / 1000)
eq(P.Config().mode, "Timers", "clicked line switches the mode")
eq(I.dd.lines[2].t.s, "* Timers", "the '*' moves right away")
check(U.dd.f.Visible, "menu stays open after a click")
away()
M.step(16 / 1000)

section("Timers mode (MicroProfileDrawBarView)")
check(U.tim.f.Visible and not U.graph.f.Visible, "Timers table shown, graph hidden")
stepMs(16, 12)
local tim = I.tim
local heads = {}
for c = 1, #tim.layout.cols do heads[c] = tim.heads[c].t.s end
eq(table.concat(heads, "|"), "Average|Max Time|Call Average|Count", "default columns (Average, Max, Call Count)")
eq(tim.group.s, "Group", "Group header")
eq(tim.timer.s, "Timer", "Timer header")
local nameW = tim.layout.nameW
eq(nameW, 2 + (4 + #"Client Objects") * 6, "name column width")
local foundHappa = false
for _, r in pairs(tim.rows) do if r.t.s == "HappaTAS" and r.t.vis then foundHappa = true end end
check(foundHappa, "HappaTAS timer row")
local cellText = nil
for _, cell in pairs(tim.cells) do if cell.t.vis then cellText = cell.t.s; break end end
check(cellText ~= nil and cellText:match("^ *%d+%.%d%d$") ~= nil or (cellText and cellText:match("^ *%d+$")), "cells use %5.2f / %5d: " .. tostring(cellText))
MENUS[4].click(0) -- + Time
M.step(16 / 1000)
stepMs(16, 6)
eq(tim.heads[1].t.s, "Time", "Time column added first")
MENUS[5].click(22) -- Spike Display
stepMs(16, 6)
local hasSpike = false
for c = 1, #tim.layout.cols do if tim.heads[c].t.s == "Max Time, Spike" then hasSpike = true end end
check(hasSpike, "Spike Display renames Max Time")
MENUS[5].click(22)
MENUS[4].click(0)

section("Counters mode")
P.SetMode("Counters")
stepMs(16, 16)
local cnt = I.cnt
local cn = {}
for n = 1, cnt.n do cn[#cn + 1] = cnt.rows[n].name.s end
local joined = table.concat(cn, "|")
check(joined:find("^frame|    fps|    frames|memory|    total %(MB%)") ~= nil, "counter rows: " .. joined:sub(1, 80))
check(joined:find("network") ~= nil, "network rows with verbosity Low")
eq(cnt.heads[1].t.s, "Name", "Name header")
MENUS[12].click(1) -- Network Off
stepMs(16, 16)
cn = {}
for n = 1, cnt.n do cn[#cn + 1] = cnt.rows[n].name.s end
check(table.concat(cn, "|"):find("network") == nil, "Network Off removes network rows")
MENUS[12].click(2)

section("Detailed mode: HappaTAS scopes on a timeline")
P.SetMode("Detailed")
P.SetView(0, 50)
check(U.det.f.Visible and U.graph.f.Visible, "detailed panel under the graph")
MENUS[3].click(4) -- 60
stepMs(16, 8)
local det = I.det
check(det.nStripes > 3, "time stripes drawn (" .. det.nStripes .. ")")
eq(det.stripes[1].t.s, "3.16ms", "50 ms range uses 3.16 ms steps (10^(floor(2*(log10(50)-1))/2))")
check(det.nLines >= 2, "frame start lines drawn (" .. det.nLines .. ")")
check(det.nBars >= 1, "HappaTAS scopes drawn (" .. det.nBars .. ")")
eq(det.thread.s, "HappaTAS (Lua)", "thread name")
local r0 = P.Snapshot().range
mouse(960, 60 + 30)
M.step(16 / 1000)
M.wheel(-1)
M.step(16 / 1000)
eq(P.Snapshot().range, r0 * 1.05, "mouse wheel zooms out by 1.05")
M.wheel(1)
M.step(16 / 1000)
near(P.Snapshot().range, r0, 1e-9, "mouse wheel zooms back in")
M.wheel(1)
M.wheel(1)
M.step(16 / 1000)
near(P.Snapshot().range, r0 / 1.05 / 1.05, 1e-9, "two notches in one frame zoom twice")
local off0 = P.Snapshot().offset
M.mouseDown(1)
M.step(16 / 1000)
mouse(960 - 192, 60 + 30)
M.step(16 / 1000)
M.mouseUp(1)
near(P.Snapshot().offset - off0, 192 * P.Snapshot().range / 1920, 1e-6, "dragging 192 px pans by a tenth of the range")
mouse(960, 400)
M.step(16 / 1000)
local r1 = P.Snapshot().range
M.wheel(1)
M.step(16 / 1000)
eq(P.Snapshot().range, r1, "the wheel outside the panel leaves the view alone")
P.SetView(0, 50)
r0 = 50
away()

section("Flamegraphs")
MENUS[9].click(2)
stepMs(16, 16)
local flm = I.flm
check(U.flm.f.Visible, "flame graph panel shown")
check(flm.n >= 3, "root, HappaTAS and Profiler boxes (" .. flm.n .. ")")
check(flm.boxes[1].t.s:find("^All HappaTAS code") ~= nil, "root box label: " .. flm.boxes[1].t.s)
MENUS[9].click(0)
M.step(16 / 1000)
check(not U.flm.f.Visible, "flame graph hidden again")
P.SetMode("Frame")

section("Custom > TAS Timeline")
local data = {}
for k = 1, 700 do data[k] = { FrameTime = (k % 50 == 25) and 0.05 or 0.016, TotalTime = k * 0.016 } end
local curF, ver = 600, 1
local scrubbed = nil
local oldGet, oldScrub = P.GetTAS, P.OnScrub
P.GetTAS = function() return data, curF, ver end
P.OnScrub = function(k) scrubbed = k end
MENUS[7].click(2)
M.step(16 / 1000)
check(P.Config().custom == true, "TAS Timeline on")
local tas = I.tas
check(tas.a ~= nil and curF >= tas.a and curF <= tas.a + 507, "current TAS frame inside the window")
local cb = U.bars[(curF - 1) % 508 + 1]
eq(cb.f.Size.Y.Offset, 25, "TAS bar height from FrameTime (16 ms = ceil(24.0) = 25 px, like (int)(base + (1-f)*50))")
local sb = U.bars[(575 - 1) % 508 + 1]
eq(sb.f.Size.Y.Offset, 50, "TAS spike frame (50 ms) full height")
near(U.hl.f.Position.X.Scale - (curF - (curF - 1) % 508 - 1) * 0, U.bars[(curF - 1) % 508 + 1].f.Position.X.Scale, 1e-9, "selection on the current TAS frame")
MENUS[3].click(0) -- Infinite
M.step(16 / 1000)
eq(U.items[3].t.s, "Aggregate[600]", "Infinite in TAS view counts TAS frames")
eq(I.tas.a, 245, "the TAS bar starts at frame 245 (current frame at 70%)")
eq(U.readout.s, string.format("Time[%6.2f] Avg[%6.2f] Max[%6.2f]", 16, (447 * 16 + 9 * 50) / 456, 50),
	"TAS view: Time = current frame, Avg = the TAS frames on the bar (245-700), Max = the whole TAS")
curF = 601
M.step(16 / 1000)
eq(U.items[3].t.s, "Aggregate[601]", "advances with the TAS frame")
mouse(barX(60), 30)
M.step(16 / 1000)
M.click(1)
M.step(16 / 1000)
eq(scrubbed, I.tas.a + 507 - 60, "click scrubs the TAS to the frame under the mouse")
scrubbed = nil
M.click(2)
M.step(16 / 1000)
eq(scrubbed, I.tas.a + 507 - 60, "right click scrubs too")
mouse(barX(3), 30)                   -- right of the TAS's last frame (frame 749 > 700)
M.step(16 / 1000)
M.click(1)
M.step(16 / 1000)
eq(scrubbed, 700, "a click after the end of the TAS scrubs to its last frame")
away()
M.step(16 / 1000)
MENUS[7].click(0)
MENUS[3].click(4)
P.GetTAS, P.OnScrub = oldGet, oldScrub
M.step(16 / 1000)
check(P.Config().custom == false, "TAS Timeline off")

section("Dump")
local function countFiles(ext)
	local n, last = 0, nil
	for p, c in pairs(M.fs) do
		if p:find("^HappaTasPort/1234567/microprofile%-%d+%-%d+%." .. ext .. "$") then n = n + 1; last = c end
	end
	return n, last
end
MENUS[8].click(0) -- 32 frames, HTML
local nH, html = countFiles("html")
eq(nH, 1, "HTML dump written to HappaTasPort/<PlaceId>/microprofile-<date>-<time>.html")
check(html and html:find("<svg") and html:find("<table>"), "HTML dump has a chart and a table")
local trs = 0
for _ in (html or ""):gmatch("<tr><td>") do trs = trs + 1 end
eq(trs, 32, "HTML dump has 32 frames")
MENUS[8].click(6) -- legacy
MENUS[8].click(1) -- 64 frames
local nT, txt = countFiles("txt")
eq(nT, 1, "legacy dump is a text table")
local lines = 0
for _ in (txt or ""):gmatch("\n") do lines = lines + 1 end
eq(lines, 4 + 64, "64 frame rows + header")
MENUS[8].click(6)
MENUS[8].click(7) -- binary -> csv
MENUS[8].click(5) -- include incomplete
MENUS[8].click(2) -- 128
local nC, csv = countFiles("csv")
eq(nC, 1, "binary option writes CSV")
check(csv and csv:find("^frame,cpu_ms,gpu_ms,render_ms,jobs_ms,physics_ms,happatas_ms\n"), "CSV header")
check(csv and csv:find("incomplete\n$") ~= nil, "Include incomplete adds the frame in progress")
MENUS[8].click(7)
MENUS[8].click(5)
local okBad = __T.Store.WriteText("x", "y", "exe")
check(okBad == false, "Store.WriteText refuses other file types")

section("Presets")
MENUS[3].click(0)
P.SetMode("Timers")
MENUS[5].click(13) -- BG 50%
MENUS[6].click(9)  -- Save 'Render'
P.SetMode("Frame")
MENUS[3].click(4)
MENUS[5].click(12) -- BG 25%
MENUS[6].click(1)  -- Load 'Render'
eq(P.Config().mode, "Timers", "preset restores the mode")
eq(P.Config().aggregate, 0, "preset restores Infinite")
eq(P.Config().bg, 0x80, "preset restores BG opacity")
local cfgBefore = P.Config().mode
MENUS[6].click(2)  -- Load 'GPU' (never saved)
eq(P.Config().mode, cfgBefore, "an empty preset changes nothing")
MENUS[6].click(0)  -- Load 'Default' (never saved) = factory defaults
eq(P.Config().mode, "Frame", "Default preset = Frame")
eq(P.Config().aggregate, 60, "Default preset = 60")
eq(P.Config().bg, 0x40, "Default preset = BG 25%")

section("config: save / load / old V2.35 settings")
MENUS[3].click(0)
MENUS[5].click(7) -- 100ms
local ser = P.SerializeConfig()
local js = M.JSON.encode(ser)
P.LoadConfig({})
eq(P.Config().aggregate, 60, "empty config = defaults")
P.LoadConfig(M.JSON.decode(js))
eq(P.Config().aggregate, 0, "Infinite survives JSON")
eq(P.Config().ref, 100, "reference survives JSON")
check(P.SerializeConfig().presets and P.SerializeConfig().presets.Render ~= nil, "saved presets survive")
P.LoadConfig({ mode = "TAS Timeline", aggregate = 1e9, scale = 66.66, group = "Frame", barWidth = 2 })
eq(P.Config().mode, "Frame", "old 'TAS Timeline' mode -> Frame")
eq(P.Config().custom, true, "old 'TAS Timeline' mode -> Custom TAS Timeline")
eq(P.Config().aggregate, 0, "old 1e9 aggregate -> Infinite")
eq(P.Config().ref, 66.66, "old scale -> reference")
P.LoadConfig({ mode = "Nope", aggregate = 77, ref = 3, bg = 5, bars = 999, network = 7, groups = { Engine = "x" } })
eq(P.Config().mode, "Frame", "invalid mode ignored")
eq(P.Config().aggregate, 60, "77 -> nearest preset 60")
eq(P.Config().ref, 33.33, "invalid reference ignored")
eq(P.Config().bg, 0x40, "invalid opacity ignored")
eq(P.Config().bars, 22, "invalid columns ignored")
eq(P.Config().network, 1, "invalid network ignored")
P.LoadConfig({})
M.step(16 / 1000)

section("settings file")
MENUS[3].click(0)
P.SaveConfig()
stepMs(16, 90)
local sj = M.fs["HappaTasPort/Settings.json"]
check(sj ~= nil and sj:find("\"profiler\"") ~= nil, "Settings.json has the profiler section")
local dec = sj and M.JSON.decode(sj)
check(dec and dec.profiler and dec.profiler.aggregate == 0, "aggregate saved")
MENUS[3].click(4)
P.SaveConfig()

section("cost per frame")
P.SetMode("Frame")
away()
stepMs(16, 30)
M.propWrites = 0
stepMs(16, 60)
local perFrame = M.propWrites / 60
check(perFrame <= 12, string.format("steady Frame mode: %.1f property writes per frame (<= 12)", perFrame))
mouse(barX(100), 30)
stepMs(16, 5)
M.propWrites = 0
stepMs(16, 30)
perFrame = M.propWrites / 30
check(perFrame <= 70, string.format("while hovering a frame: %.1f writes per frame (<= 70)", perFrame))
away()
stepMs(16, 2)
P.SetMode("Hidden")
stepMs(16, 5)
M.propWrites = 0
stepMs(16, 60)
perFrame = M.propWrites / 60
check(perFrame <= 6, string.format("Hidden mode: %.1f writes per frame (<= 6)", perFrame))
P.SetMode("Frame")

section("timers fed by the core")
MENUS[3].click(3) -- 30
stepMs(16, 40)
-- the HappaTAS scope runs in PreRender, the late render step, PreSimulation and Heartbeat
local ht = P.TimerStats("HappaTAS")
eq(ht.calls, 4, "HappaTAS scope ran 4 times in the last frame")
check(ht.time > 0, "HappaTAS time measured with os.clock")
local ft = P.TimerStats("Frame")
near(ft.time, 16, 1e-9, "Frame timer = frame time")
near(ft.avg, 16, 1e-9, "Frame average over the window")
local rc = P.TimerStats("Render CPU")
near(rc.time, M.stats.RenderCPUFrameTime * 1000, 1e-9, "Render CPU timer = Stats.RenderCPUFrameTime")
local hb = P.TimerStats("Heartbeat")
near(hb.time, M.stats.HeartbeatTime * 1000, 1e-9, "Heartbeat timer = Stats.HeartbeatTime")
local cu = P.TimerStats("Cursor")
eq(cu.calls, 1, "Cursor scope once per frame")
check(ht.exclusive <= ht.time + 1e-12, "exclusive <= inclusive")
check(P.TimerStats("Nope") == nil, "unknown timer")
MENUS[3].click(4)

section("mouse: Roblox's coordinate spaces")
-- GuiBase2d.AbsolutePosition docs: measured from the bottom-left corner of the top bar, so a ScreenGui
-- that ignores the inset starts at -inset. UIS:GetMouseLocation() is measured from the top of the screen.
eq(U.root.AbsolutePosition.Y, -M.inset, "profiler root AbsolutePosition.Y = -inset (it covers the top bar)")
P.SetMode("Frame")
away()
stepMs(16, 2)
-- only GetMouseLocation changes (no input event): GetMouseLocation - GetGuiInset is used
M.mouse = Vector2.new(I.menuX[1] + 3, 4)
M.step(16 / 1000)
check(U.dd.f.Visible and I.dd.menu == 1, "hover from GetMouseLocation() - GetGuiInset()")
M.mouse = Vector2.new(960, 700)
stepMs(16, 2)
check(not U.dd.f.Visible, "closed again")
-- GetGuiInset reporting nonsense: the input events (InputObject.Position) decide
local GSM = M.Classes.GuiService.Methods
local realInset = GSM.GetGuiInset
GSM.GetGuiInset = function() return Vector2.new(0, 0), Vector2.new(0, 0) end
mouse(I.menuX[1] + 3, 4)
M.step(16 / 1000)
check(U.dd.f.Visible and I.dd.menu == 1, "hover from the MouseMovement event")
M.step(16 / 1000)
check(U.dd.f.Visible, "still open next frame (no event, GetMouseLocation unchanged)")
mouse(I.menuX[1] + 20, 9 + 9 * 2 + 4)  -- line 3, Counters
M.step(16 / 1000)
M.click(1)
M.step(16 / 1000)
eq(P.Config().mode, "Counters", "a click on a dropdown line picks it")
GSM.GetGuiInset = realInset
P.SetMode("Frame")
away()
stepMs(16, 2)

section("mouse: clicks (microprofile's MicroProfileMouseButton)")
local pauseX = I.menuX[10] + 6
mouse(pauseX, 4)
M.step(16 / 1000)
M.click(1)
M.step(16 / 1000)
check(P.IsPaused(), "a click on Pause pauses")
M.step(16 / 1000)
eq(U.items[10].t.s, "Unpause", "label Unpause (next frame, like S.nToggleRunning)")
M.mouseDown(1)
M.step(16 / 1000)
check(P.IsPaused(), "pressing alone does nothing (a click is the release)")
M.mouseUp(1)
M.step(16 / 1000)
check(not P.IsPaused(), "releasing on the item unpauses")
mouse(I.menuX[10] + 6, 4)
M.step(16 / 1000)
M.mouseDown(1)
mouse(I.menuX[10] + 12, 4)   -- 6 px away, still on the item
M.mouseUp(1)
M.step(16 / 1000)
check(not P.IsPaused(), "a release 6 px from the press is a drag, not a click")
M.click(2)
M.step(16 / 1000)
check(P.IsPaused(), "a right click works too (UI.nMouseLeft || UI.nMouseRight)")
M.click(1, false)
M.step(16 / 1000)
check(not P.IsPaused(), "gameProcessedEvent false or true makes no difference")
-- a click in the game is not the profiler's
local before = P.Snapshot()
mouse(500, 600)
M.step(16 / 1000)
M.click(1, false)
M.click(2, false)
M.step(16 / 1000)
local after = P.Snapshot()
check(after.offset == before.offset and after.range == before.range and not P.IsPaused(), "clicks in the game view change nothing")
check(P.active and U.root.Visible, "profiler still open")
-- holding the left button on the graph keeps centring while the mouse moves (UI.nMouseDownLeft)
mouse(barX(30), 30)
M.step(16 / 1000)
M.mouseDown(1)
M.step(16 / 1000)
local o1 = P.Snapshot().offset
mouse(barX(10), 30)
M.step(16 / 1000)
local o2 = P.Snapshot().offset
M.mouseUp(1)
near(o2 - o1, 20 * 16, 0.6, "dragging along the graph re-centres 20 frames later")
mouse(barX(40), 30)
M.step(16 / 1000)
near(P.Snapshot().offset, o2, 1e-9, "after the release the view stays")
-- a release Roblox never delivered (focus lost): the held state ends with the button
M.mouseDown(1)
M.step(16 / 1000)
M.buttonsDown[Enum.UserInputType.MouseButton1] = nil
M.step(16 / 1000)
local o3 = P.Snapshot().offset
mouse(barX(5), 30)
M.step(16 / 1000)
near(P.Snapshot().offset, o3, 1e-9, "no centring once the button is up")
away()
M.step(16 / 1000)

section("mouse: the new 58 px top bar and touch")
M.inset = 58
mouse(I.menuX[3] + 3, 4)
M.step(16 / 1000)
check(U.dd.f.Visible and I.dd.menu == 3, "menu opens with a 58 px inset")
eq(U.root.AbsolutePosition.Y, -58, "root starts 58 px above the AbsolutePosition origin")
mouse(I.menuX[3] + 20, 9 + 9 * 2 + 4)  -- 20
M.step(16 / 1000)
M.click(1)
M.step(16 / 1000)
eq(P.Config().aggregate, 20, "click picks Aggregate 20 with a 58 px inset")
check(P.IsMouseOver(M.mouse), "IsMouseOver(current mouse) uses the profiler's pointer")
check(P.IsMouseOver(Vector2.new(500, 5)), "IsMouseOver(screen point) on the menu bar")
check(not P.IsMouseOver(Vector2.new(500, 400)), "IsMouseOver(screen point) in the game")
away()
stepMs(16, 2)
-- one finger: a tap opens the menu (the touch is the pointer), a tap on a line picks it.
-- A phone has no mouse (UIS.MouseEnabled false): GetMouseLocation is undefined there and is ignored.
local UISvc = M.services.UserInputService
UISvc.MouseEnabled = false
M.mouse = Vector2.new(I.menuX[1] + 3, 4)
stepMs(16, 2)
check(not U.dd.f.Visible, "without a mouse, GetMouseLocation alone opens nothing")
M.touch("begin", I.menuX[3] + 3, 4)
M.step(16 / 1000)
check(U.dd.f.Visible and I.dd.menu == 3, "touching the label opens the menu")
M.touch("end", I.menuX[3] + 3, 4)
M.step(16 / 1000)
check(U.dd.f.Visible, "the menu stays open after the tap")
M.touch("begin", I.menuX[3] + 20, 9 + 9 * 4 + 4)  -- 60
M.touch("end", I.menuX[3] + 22, 9 + 9 * 4 + 5)    -- a finger wobbles a little
M.step(16 / 1000)
eq(P.Config().aggregate, 60, "tapping a line picks it (Aggregate 60)")
M.touch("begin", 500, 500)
M.touch("end", 500, 500)
M.step(16 / 1000)
check(P.Config().aggregate == 60 and P.active, "a tap in the game view is ignored")
stepMs(16, 2)
check(not U.dd.f.Visible, "the menu closes once the pointer is elsewhere")
UISvc.MouseEnabled = true
M.inset = 36
away()
stepMs(16, 2)

section("text offset setting")
local titleY = U.title.sh.Position.Y.Offset
S.Set("MicroProfiler Text Offset", -2)
M.step(16 / 1000)
eq(select(1, P.TextOffset()), -3, "auto -1 plus -2")
eq(U.title.sh.Position.Y.Offset, titleY - 2, "the title moved up 2 px")
eq(U.readout.sh.Position.Y.Offset, 1 + (-3), "the readout moved too")
S.Set("MicroProfiler Text Offset", 9)
eq(S.Get("MicroProfiler Text Offset"), 6, "limited to 6 px")
S.Set("MicroProfiler Text Offset", 0)
M.step(16 / 1000)
eq(U.title.sh.Position.Y.Offset, titleY, "back to the automatic position")

section("mouse-over test for the recorder")
check(P.IsMouseOver(Vector2.new(500, 5)), "over the menu bar")
check(P.IsMouseOver(Vector2.new(500, 40)), "over the graph")
check(not P.IsMouseOver(Vector2.new(500, 400)), "not over the game view")

section("close box")
mouse(1920 - 25, 35)
M.step(16 / 1000)
M.click(1)
M.step(16 / 1000)
check(P.active == false and not U.root.Visible, "X closes the profiler")
eq(S.Get("Show MicroProfiler"), 0, "setting turned off")
local recordedClosed = P.Snapshot().recorded
stepMs(16, 10)
eq(P.Snapshot().recorded, recordedClosed, "nothing recorded while closed")
S.Set("Show MicroProfiler", 1)
M.step(16 / 1000)
check(P.active and U.root.Visible, "opens again")
MENUS[1].click(5) -- Off
M.step(16 / 1000)
check(P.active == false, "Mode > Off closes it")

section("unload")
S.Set("Show MicroProfiler", 1)
M.step(16 / 1000)
M.genv.__HappaTAS.Unload()
M.step(16 / 1000)
check(M.hui:FindFirstChild("HappaProfiler") == nil, "profiler GUI removed on unload")
finish()
