#!/bin/bash
# Per-frame cost of HappaTAS 3 against V2.38.16 in each mode (headless mock, tests3/trace/bench.lua).
#   bash tools/bench3.sh
# HappaTAS 3 must not read or write more Instance properties per frame than V2.38.16 in any mode, and its
# Lua time per frame must stay within 10 % of V2's (timing in the mock is noisy; the fastest of 3 runs).
set -e
cd "$(dirname "$0")/.."
SCENARIO=bench bash tools/trace3.sh >/dev/null
T=tests3/trace
python3 - "$T/raw_a.txt" "$T/raw_b.txt" <<'PY'
import sys
def rows(p):
    out = {}
    for l in open(p, encoding="utf-8", errors="replace"):
        if l.startswith("BENCH|"):
            _, name, us, rd, wr = l.strip().split("|")
            out[name] = (float(us), float(rd), float(wr))
    return out
a, b = rows(sys.argv[1]), rows(sys.argv[2])
ok = True
print("%-18s %22s %22s" % ("mode", "V2.38.16 us/rd/wr", "HappaTAS 3 us/rd/wr"))
for name in a:
    va, vb = a[name], b.get(name)
    if vb is None:
        print(name, "missing on HappaTAS 3"); ok = False; continue
    bad = vb[1] > va[1] or vb[2] > va[2] or vb[0] > va[0] * 1.10
    print("%-18s %8.1f %6.1f %6.1f %8.1f %6.1f %6.1f %s" % (name, va[0], va[1], va[2], vb[0], vb[1], vb[2], "SLOWER" if bad else "ok"))
    ok = ok and not bad
print("BENCH OK" if ok else "BENCH SLOWER")
sys.exit(0 if ok else 2)
PY
