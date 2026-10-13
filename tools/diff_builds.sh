#!/bin/bash
# Run the differential trace (tests/test_diff.lua) on two builds and compare.
#   bash tools/diff_builds.sh OLD.lua [NEW.lua]      (NEW defaults to src/HappaTAS_Executor.lua)
# Prints "SAME" or the first differing trace lines. Full traces: tests/diff_old.txt, tests/diff_new.txt
set -e
cd "$(dirname "$0")/.."
OLD="$1"
NEW="${2:-src/HappaTAS_Executor.lua}"
LUAU="${LUAU:-/home/claude/tools/luau/luau}"
bash tools/build_test.sh diff "$OLD" >/dev/null
(cd tests && "$LUAU" run_diff.lua > diff_old.txt 2>&1) || { echo "old build failed:"; tail -5 tests/diff_old.txt; exit 1; }
bash tools/build_test.sh diff "$NEW" >/dev/null
(cd tests && "$LUAU" run_diff.lua > diff_new.txt 2>&1) || { echo "new build failed:"; tail -5 tests/diff_new.txt; exit 1; }
# the version string is allowed to differ
sed -i -E 's/V2\.[0-9]+/V2.xx/g' tests/diff_old.txt tests/diff_new.txt
if cmp -s tests/diff_old.txt tests/diff_new.txt; then
  echo "SAME ($(grep -c '^T|' tests/diff_new.txt) trace lines)"
else
  echo "DIFFERENT:"
  diff tests/diff_old.txt tests/diff_new.txt | head -${DIFF_LINES:-40}
  exit 2
fi
