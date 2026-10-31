#!/bin/bash
# Build tests3/run_NAME.lua = mock + HappaTAS 3 (Debug on, `import` exposed as __T3) + test_util + test_NAME
#   bash tools/build_test3.sh NAME [BUILD]     (BUILD defaults to src2/HappaTAS3.lua, built first)
#   PRE='lua' runs code before the script boots (e.g. to fake an executor without getgenv)
#   SEDX='sed expr' changes the script first (mutation checks: the suite must fail)
set -e
cd "$(dirname "$0")/.."
NAME="$1"
if [ -n "$2" ]; then
  SCRIPT="$2"
else
  bash tools/build3.sh >/dev/null
  SCRIPT=src2/HappaTAS3.lua
fi
OUT="tests3/run_${NAME}.lua"
{
  cat tests/mock/dt.lua tests/mock/json_lz4.lua tests/mock/inst.lua tests/mock/svc.lua
  echo 'local os = setmetatable({ clock = function() return M.clock() end }, { __index = os })'
  [ -n "$PRE" ] && echo "$PRE"
  # (a suite whose first line says "-- needs: v2fixtures" gets FIXTURES: tests3/fixtures/v2, tools/make_v2_fixtures3.sh)
  if head -1 "tests3/test_${NAME}.lua" | grep -q "needs:.*v2fixtures"; then python3 tools/fixtures3_lua.py tests3/fixtures/v2; fi
  echo 'local function __SCRIPT__()'
  sed -e '0,/Debug = false,/s//Debug = true,/' ${SEDX:+-e "$SEDX"} "$SCRIPT"   # (config's first Debug line: the release has no comments)
  echo ''
  echo '__T3 = import'
  echo 'end'
  cat tests/test_util.lua
  # (a suite whose first line says "-- needs: ui" gets the UI helpers: tests3/ui_helpers.lua)
  if head -1 "tests3/test_${NAME}.lua" | grep -qE "needs:.*(^| )ui( |$)"; then cat tests3/ui_helpers.lua; fi
  cat "tests3/test_${NAME}.lua"
} > "$OUT"
echo "$OUT"
