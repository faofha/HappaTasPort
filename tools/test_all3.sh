#!/bin/bash
# HappaTAS 3: build and run every headless suite (tests3/), the executor variants, the import-cycle
# check, the trace against V2.38.16 (every phase 2 frame field), the bench against V2.38.16, then the
# release build (wow3) through the start / unload suites.
#   bash tools/test_all3.sh
cd "$(dirname "$0")/.."
LUAU="${LUAU:-$(command -v luau || echo /home/claude/tools/luau/luau)}"
fail=0
bash tools/build3.sh --check >/dev/null || { echo "build3 --check failed"; fail=1; }
# (a suite whose first line says "-- needs: fsfail" gets tests3/fsfail.lua before the script boots)
pre_for() { head -1 "tests3/test_$1.lua" | grep -q "needs:.*fsfail" && cat tests3/fsfail.lua; }
run() { # NAME [BUILD]
  PRE="$(pre_for "$1")" bash tools/build_test3.sh "$1" "$2" >/dev/null || { fail=1; echo "$1: build failed"; return; }
  out=$(cd tests3 && "$LUAU" "run_$1.lua" 2>&1)
  res=$(echo "$out" | grep -E "^RESULT" | tail -1)
  echo "$1${2:+ ($2)}: ${res:-no result}"
  echo "$out" | grep -q "RESULT .* 0 failed" || { fail=1; echo "$out" | grep -E "FAIL|ERROR" | head -10; }
}
for t in tests3/test_*.lua; do
  n=$(basename "$t" .lua); n=${n#test_}
  if [ -f "tests3/$n.variants" ]; then
    bash tests3/run_variants.sh "$n" || fail=1
  else
    run "$n"
  fi
done
if bash tools/build3.sh --src tests3/fixtures/cycle --check >/dev/null 2>&1; then
  echo "cycle check: an import cycle was NOT caught"; fail=1
else
  echo "cycle check: caught"
fi
# (getfenv / setfenv switch Luau's fast paths off for the whole environment: about 5x slower math / table
# calls everywhere, measured in review; HappaTAS 3 must never call them)
if grep -nE "(getfenv|setfenv)\(" src2/HappaTAS3.lua; then
  echo "deopt guard: getfenv / setfenv found in the build"; fail=1
else
  echo "deopt guard: clean"
fi
P2FIELDS="FrameTime TotalTime Cframe Velocity State Died CamCframe Zoom ShiftLock Input MX MY UVX UVY VX VY Anim Tools"
tr=$(FIELDS="$P2FIELDS" bash tools/trace3.sh 2>&1 | head -12)
echo "trace: $(echo "$tr" | head -1)"
echo "$tr" | grep -q "^SAME" || { fail=1; echo "$tr"; }
# client objects: V2's diffco trace (records byte for byte, part states, Test, save / load)
tc=$(SCENARIO=diffco TGROUPS="mode F W.co" FIELDS="CO" bash tools/trace3.sh 2>&1 | head -12)
echo "diffco trace: $(echo "$tc" | head -1)"
echo "$tc" | grep -q "^SAME" || { fail=1; echo "$tc"; }
# the world plugins: buttons, lighting, time control, the kit (tests3/trace/world.lua, against V2.38.17)
WGROUPS="mode F W.char W.co W.bt W.lt W.time W.kit"
WFIELDS="FrameTime TotalTime Cframe Velocity State SK CO BT KE"
tw=$(SCENARIO=world TGROUPS="$WGROUPS" FIELDS="$WFIELDS" bash tools/trace3.sh 2>&1 | head -12)
echo "world trace: $(echo "$tw" | head -1)"
echo "$tw" | grep -q "^SAME" || { fail=1; echo "$tw"; }
bo=$(bash tools/bench3.sh 2>&1)
echo "bench: $(echo "$bo" | tail -1)"
echo "$bo" | grep -q "^BENCH OK" || { fail=1; echo "$bo"; }
# (the 10-minute save / load bench against V2 takes a while: BENCH=1 bash tools/test_all3.sh)
if [ "$BENCH" = 1 ]; then
  so=$(bash tools/savebench3.sh 2>&1)
  echo "save bench: $(echo "$so" | tail -1)"
  echo "$so" | grep -q "^SAVEBENCH OK" || { fail=1; echo "$so"; }
fi
bash tools/build3.sh --release wow3 >/dev/null || { echo "release build failed"; fail=1; }
run main wow3
run engine wow3
[ $fail -eq 0 ] && echo "ALL PASSED" || { echo "SOMETHING FAILED"; exit 1; }
