#!/bin/bash
# Per-frame cost of HappaTAS 3 against V2.38.17 in each mode (headless mock, tests3/trace/bench.lua).
#   bash tools/bench3.sh
# HappaTAS 3 must not read or write more Instance properties per frame than V2.38.17 in any mode, and its
# Lua time per frame must stay within 10 % of V2's (15 % in the "menu open" modes) (timing in the mock is noisy: each mode's fastest of 5 runs
# inside a scenario run, and the best of 5 scenario runs per side).
set -e
cd "$(dirname "$0")/.."
T=tests3/trace
for run in 1 2 3 4 5; do
  SCENARIO=bench bash tools/trace3.sh >/dev/null
  cp "$T/raw_a.txt" "$T/bench_a$run.txt"; cp "$T/raw_b.txt" "$T/bench_b$run.txt"
done
python3 - "$T" <<'PY'
import sys
def rows(paths):
    out = {}
    for p in paths:
        for l in open(p, encoding="utf-8", errors="replace"):
            if l.startswith("BENCH|"):
                _, name, us, rd, wr = l.strip().split("|")
                v = (float(us), float(rd), float(wr))
                if name not in out or v[0] < out[name][0]: out[name] = v
    return out
T = sys.argv[1]
a = rows(["%s/bench_a%d.txt" % (T, r) for r in (1, 2, 3, 4, 5)])
b = rows(["%s/bench_b%d.txt" % (T, r) for r in (1, 2, 3, 4, 5)])
ok = True
print("%-18s %22s %22s" % ("mode", "V2.38.17 us/rd/wr", "HappaTAS 3 us/rd/wr"))
for name in a:
    va, vb = a[name], b.get(name)
    if vb is None:
        print(name, "missing on HappaTAS 3"); ok = False; continue
    # (with a menu open V2 shows a static frame, HappaTAS 3 a live Settings window: 15 % there)
    allow = 1.15 if "menu open" in name else 1.10
    bad = vb[1] > va[1] or vb[2] > va[2] or vb[0] > va[0] * allow
    print("%-18s %8.1f %6.1f %6.1f %8.1f %6.1f %6.1f %s" % (name, va[0], va[1], va[2], vb[0], vb[1], vb[2], "SLOWER" if bad else "ok"))
    ok = ok and not bad
print("BENCH OK" if ok else "BENCH SLOWER")
sys.exit(0 if ok else 2)
PY
