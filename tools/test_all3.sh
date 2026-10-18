#!/bin/bash
# HappaTAS 3: build and run every headless suite (tests3/), the executor variants, the import-cycle
# check, then the release build (wow3) through the start / unload suite.
#   bash tools/test_all3.sh
cd "$(dirname "$0")/.."
LUAU="${LUAU:-$(command -v luau || echo /home/claude/tools/luau/luau)}"
fail=0
bash tools/build3.sh --check >/dev/null || { echo "build3 --check failed"; fail=1; }
run() { # NAME [BUILD]
  bash tools/build_test3.sh "$1" "$2" >/dev/null || { fail=1; echo "$1: build failed"; return; }
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
bash tools/build3.sh --release wow3 >/dev/null || { echo "release build failed"; fail=1; }
run main wow3
[ $fail -eq 0 ] && echo "ALL PASSED" || { echo "SOMETHING FAILED"; exit 1; }
