#!/usr/bin/env python3
"""The README describes HappaTAS 3 as it is: every tools/ command it names exists, its controls table is
src2/engine/controls.lua's defaults row for row, and it names the files and messages people meet when they
switch over (Settings3.json, V2's "unsupported file version 6", tools/release3.sh).

    python3 tools/check_readme3.py        (exit 0 = all true, 1 = the first miss)
"""
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
readme = open(os.path.join(ROOT, "README.md"), encoding="utf-8").read()


def fail(why):
    print("check_readme3: " + why)
    sys.exit(1)


for tool in sorted(set(re.findall(r"(?:bash|python3) (tools/[\w./-]+)", readme))):
    if not os.path.isfile(os.path.join(ROOT, tool)):
        fail("README names %s, which doesn't exist" % tool)

controls = open(os.path.join(ROOT, "src2", "engine", "controls.lua"), encoding="utf-8").read()
rows = re.findall(r'v2 = "([^"]+)", default = "([^"]+)"', controls)
if not rows:
    fail("no controls found in src2/engine/controls.lua")
for name, key in rows:
    shown = "none" if key == "None" else key
    if not re.search(r"\|\s*%s\s*\|\s*%s\s*\|" % (re.escape(name), re.escape(shown)), readme):
        fail("the controls table has no row | %s | %s |" % (name, shown))

for needed in ("Settings3.json", "unsupported file version 6", "release3.sh",
               "unload HappaTAS first", "Help > Unload HappaTAS"):
    if needed not in readme:
        fail("README doesn't mention %s" % needed)

# (spec 13: live, HappaTAS 3's frames cost a little more than V2's; saving is what got faster)
for claim in ("faster engine", "faster frames"):
    if claim in readme.lower():
        fail("README claims a %s, which spec 13's live numbers contradict" % claim)

print("check_readme3: OK (%d controls)" % len(rows))
