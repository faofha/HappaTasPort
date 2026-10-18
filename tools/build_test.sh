#!/bin/bash
# Build tests/run_NAME.lua = mock + script (wrapped, Debug on) + test_util + test_NAME
set -e
cd "$(dirname "$0")/.."
NAME="$1"
SCRIPT="${2:-src/HappaTAS_Executor.lua}"
OUT="tests/run_${NAME}.lua"
{
  cat tests/mock/dt.lua tests/mock/json_lz4.lua tests/mock/inst.lua tests/mock/svc.lua
  echo 'local os = setmetatable({ clock = function() return M.clock() end }, { __index = os })'
  echo 'local function __SCRIPT__()'
  sed -e 's/^\(\s*\)Debug           = false,/\1Debug           = true,/' ${SEDX:+-e "$SEDX"} "$SCRIPT"
  echo ''
  echo '__T = { Profiler = Profiler, Settings = Settings, Store = Store, Core = Core, CONFIG = CONFIG, UI = UI, Controls = Controls, InputSys = InputSys, ClientObjects = ClientObjects, Buttons = Buttons, Cursor = Cursor, Bridge = Bridge, Menu = Menu, VERSION = VERSION, SpeedHack = SpeedHack, AnimEngine = AnimEngine }'
  echo 'end'
  cat tests/test_util.lua
  [ -n "$PRE" ] && echo "$PRE"   # optional Lua line(s) run before the test (e.g. PRE='BENCH_PROFILE = true')
  cat "tests/test_${NAME}.lua"
} > "$OUT"
echo "$OUT"
