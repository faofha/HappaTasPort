#!/bin/bash
# Runs tests3/test_NAME.lua once per line of tests3/NAME.variants (each line is the PRE code)
#   bash tests3/run_variants.sh NAME
cd "$(dirname "$0")/.."
LUAU="${LUAU:-$(command -v luau || echo /home/claude/tools/luau/luau)}"
fail=0
while IFS= read -r pre; do
  [ -z "$pre" ] && continue
  PRE="$pre" bash tools/build_test3.sh "$1" >/dev/null || { fail=1; continue; }
  res=$(cd tests3 && "$LUAU" "run_$1.lua" 2>&1 | grep -E "^RESULT" | tail -1)
  echo "$1 [${pre%%;*}]: ${res:-no result}"
  echo "$res" | grep -q " 0 failed" || fail=1
done < "tests3/$1.variants"
exit $fail
