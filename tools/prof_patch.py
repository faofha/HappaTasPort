#!/usr/bin/env python3
"""Instrument a HappaTAS build with os.clock section timers (live profiling only, never released).

    python3 tools/prof_patch.py IN.lua OUT.lua

Every line listed in SECTIONS (exact text, indentation included) is timed as one statement:
    do local __t = __clk(); <statement>; __HP[name] = __HP[name] + (__clk() - __t) end
A 'local a, b = expr' line keeps its locals visible (declared first, assigned inside the timer).
Totals (seconds) and a frame counter are in getgenv().__HPROF.
"""
import re
import sys

src = open(sys.argv[1], encoding="utf-8").read()

# globals, not locals: the main chunk is close to Luau's 200 register limit
HEADER = (
    "__HP = setmetatable({}, { __index = function() return 0 end })\n"
    "__clk = os.clock\n"
    "rawset((type(getgenv) == 'function' and getgenv()) or _G, '__HPROF', __HP)\n"
)

T3, T4, T5 = "\t\t\t", "\t\t\t\t", "\t\t\t\t\t"
# (exact line, name, which match: 1-based index or 0 = every match)
SECTIONS = [
    # MicroProfiler
    (T3 + "local recorded = flip(dt, t0)", "prof.flip", 1),
    (T3 + "readMouse()", "prof.readMouse", 1),
    (T3 + "updateMenus()", "prof.updateMenus", 1),
    (T3 + "readoutUpdate()", "prof.readoutUpdate", 1),
    (T3 + "helpUpdate()", "prof.helpUpdate", 1),
    (T4 + "local ok, err = pcall(frameUI, recorded)", "prof.frameUI", 1),
    # core, recording
    (T4 + "local mx, my, uvx, uvy, vx, vy = InputSys.Mouse()", "rec.mouse", 1),
    (T4 + "fd.Cframe = C.CFrameToTable(HRP.CFrame)", "rec.cframe", 1),
    (T4 + "fd.Anim = Bridge.GetAnimation(#data == 2)", "rec.anim", 1),
    (T4 + "fd.CO = ClientObjects.Record(HRP.Position, fd.TotalTime)", "rec.clientObjects", 1),
    (T4 + "fd.Tools = ToolSync.Take()", "rec.tools", 1),
    (T4 + "fd.BT = Buttons.RecordFrame(fd.TotalTime, #data == 1)", "rec.buttons", 1),
    # core, paused
    (T4 + "C.UpdateCamera(data[C.frame], true)", "paused.camera", 1),
    (T5 + "ClientObjects.Tick()", "paused.coTick", 1),
    (T5 + "Buttons.Step(data[C.frame] and data[C.frame].TotalTime or 0)", "paused.buttons", 1),
    (T4 + 'C.SetStats("Create", data[C.frame], dt, C.frame)', "create.stats", 1),
    (T4 + 'C.SetStats("Idle", nil, dt)', "idle.stats", 1),
    # core, playback (preRender = 1st match, Heartbeat = 2nd)
    (T3 + "local p = C.PlaybackPose()", "play.pose", 0),
    (T3 + "C.SyncCharacter(p.root, p.lin, p.ang)", "play.sync", 0),
    (T3 + "C.UpdateCamera(p)", "play.camera", 0),
    (T4 + "Bridge.UpdateGhost(p.Zoom, dt)", "play.ghost", 1),
    (T3 + "InputSys.ReplayMouse(data[frame])", "play.mouse", 1),
    (T3 + "ClientObjects.PlaybackTo(data, frame, C.TestingTimer)", "play.clientObjects", 1),
    (T3 + "ToolSync.Step(C.Char, C.Humanoid)", "play.tools", 1),
    (T3 + 'C.SetStats("Test")', "play.stats", 1),
    # end of the render step
    ("\t\tClientObjects.RenderStep()", "late.coRender", 1),
    ("\t\tupdateMouseMode()", "late.mouseMode", 1),
    # client objects, inside the module
    ("\t\tupdateVisibility(playerPos, false)", "co.visibility", 1),
    ("\t\t\t\trecordObject(out, id, part, s, now, dtT)", "co.recordObject", 1),
    ("\t\t\tinstL, instA = part.AssemblyLinearVelocity, part.AssemblyAngularVelocity", "co.velRead", 1),
    ("\t\tadvanceTo(data, frame, {})", "co.advance", 1),
    ("\t\twriteAll(play.t, false)", "co.writeAll", 2),
    ("\t\twriteAll(play.t, true)", "co.writeRender", 1),
    ("\t\tsweepAnchors()", "co.sweep", 1),
]


def wrap(line, name):
    indent = re.match(r"\t*", line).group(0)
    body = line.strip()
    m = re.match(r"local ([\w, ]+) = (.*)", body)
    if m:
        names, expr = m.group(1), m.group(2)
        return "%slocal %s\n%sdo local __t = __clk(); %s = %s; __HP[%r] = __HP[%r] + (__clk() - __t) end" % (
            indent, names, indent, names, expr, name, name)
    return "%sdo local __t = __clk(); %s; __HP[%r] = __HP[%r] + (__clk() - __t) end" % (indent, body, name, name)


lines = src.split("\n")
# layoutMenuBar() is also called once in build(): only the call right before updateMenus() is timed
for i in range(len(lines) - 1):
    if lines[i] == T3 + "layoutMenuBar()" and lines[i + 1] == T3 + "updateMenus()":
        lines[i] = wrap(lines[i], "prof.layoutMenuBar")
        break
else:
    sys.exit("layoutMenuBar call not found")

for text, name, which in SECTIONS:
    idx = [i for i, l in enumerate(lines) if l == text]
    if not idx:
        sys.exit("section %r not found" % name)
    if which:
        if len(idx) < which:
            sys.exit("section %r: only %d matches" % (name, len(idx)))
        idx = [idx[which - 1]]
    for i in idx:
        lines[i] = wrap(lines[i], name)

out = "\n".join(lines)
marker = "\t\tfunction P.FrameBegin(dt)\n"
assert out.count(marker) == 1
out = out.replace(marker, marker + "\t\t\t__HP.frames = __HP.frames + 1\n")
i = out.index("local VERSION")
out = out[:i] + HEADER + out[i:]
open(sys.argv[2], "w", encoding="utf-8").write(out)
print("instrumented", len(SECTIONS) + 1, "sections")
