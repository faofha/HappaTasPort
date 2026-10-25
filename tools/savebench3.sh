#!/bin/bash
# Save / load time and file size of a 10-minute run, V2.38.16 against HappaTAS 3 (tests3/bench/save.lua,
# run through tools/trace3.sh in the headless mock). Gate (spec criterion 4): HappaTAS 3 saves faster.
#   bash tools/savebench3.sh        (BENCH_FRAMES=n for a shorter run)
set -e
cd "$(dirname "$0")/.."
T=tests3/trace
PRE_FRAMES=""
[ -n "$BENCH_FRAMES" ] && PRE_FRAMES="BENCH_FRAMES = $BENCH_FRAMES"
# (trace3 compares the T| lines; this scenario prints none)
SCENARIO=../bench/save SCENARIO_PRE="$PRE_FRAMES" bash tools/trace3.sh >/dev/null
python3 - "$T/raw_a.txt" "$T/raw_b.txt" <<'PY'
import sys
def rows(p):
    out = {}
    for l in open(p, encoding="utf-8", errors="replace"):
        if l.startswith("SAVEBENCH|"):
            _, what, ms, n = l.strip().split("|")
            out[what] = (float(ms), int(n))
    return out
a, b = rows(sys.argv[1]), rows(sys.argv[2])
for what in ("save", "load"):
    print("%-5s V2.38.16 %9.1f ms %10d    HappaTAS 3 %9.1f ms %10d" % (what, a[what][0], a[what][1], b[what][0], b[what][1]))
print("size: HappaTAS 3 file is %.0f %% of V2's" % (100.0 * b["save"][1] / a["save"][1]))
ok = b["save"][0] < a["save"][0]
print("SAVEBENCH OK" if ok else "SAVEBENCH SLOWER")
sys.exit(0 if ok else 2)
PY
