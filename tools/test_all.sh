#!/bin/bash
# Build the script and run every offline test suite (headless Roblox mock, not a real game).
#   bash tools/test_all.sh [REFERENCE.lua]
#   REF=1 bash tools/test_all.sh   runs the suites on V2.38.16 (src/parts at commit b1569bd, built into
#                                  tests3/trace/ref/ like tools/trace3.sh) instead of the working tree's parts
# With a reference build, the differential traces (tests/test_diff.lua, tests/test_diffco.lua) are
# compared against it too (IGNORE='regex' skips trace lines, see tools/diff_builds.sh).
cd "$(dirname "$0")/.."
LUAU="${LUAU:-$(command -v luau || echo /home/claude/tools/luau/luau)}"
SCRIPT=""
if [ -n "$REF" ]; then
  R=tests3/trace/ref
  if [ ! -f "$R/src/HappaTAS_Executor.lua" ]; then
    rm -rf "$R"; mkdir -p "$R"
    git archive b1569bd src/parts tools/assemble.sh tools/order.txt | tar -x -C "$R"
    bash "$R/tools/assemble.sh" >/dev/null || exit 1
  fi
  SCRIPT="$R/src/HappaTAS_Executor.lua"
else
  bash tools/assemble.sh >/dev/null || exit 1
fi
fail=0
for s in smoke profiler graphimg core scale perf textline typing live realinput security coclock speedhack kit cobase; do
  bash tools/build_test.sh "$s" $SCRIPT >/dev/null
  out=$(cd tests && "$LUAU" "run_$s.lua" 2>&1)
  res=$(echo "$out" | grep -E "^RESULT" | tail -1)
  echo "$s: ${res:-no result}"
  echo "$out" | grep -q "RESULT .* 0 failed" || { fail=1; echo "$out" | grep -E "FAIL|ERROR" | head -10; }
done
if [ -n "$1" ]; then
  TEST=diff bash tools/diff_builds.sh "$1" || fail=1
  TEST=diffco bash tools/diff_builds.sh "$1" || fail=1
fi
[ $fail -eq 0 ] && echo "ALL PASSED" || { echo "SOMETHING FAILED"; exit 1; }
