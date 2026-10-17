#!/bin/bash
# Test build for a live Roblox client (not for release):
#   - debug logging on, so errors inside the frame handlers are printed to the console
#   - the internal modules are exported as getgenv().__HappaTAS_T, so a test script can inspect state
#   bash tools/live_build.sh [OUT]        (OUT defaults to build/HappaTAS_live.lua)
set -e
cd "$(dirname "$0")/.."
OUT="${1:-build/HappaTAS_live.lua}"
bash tools/assemble.sh >/dev/null
mkdir -p "$(dirname "$OUT")"
sed -E 's/^(\tDebug +)= false,/\1= true,/' src/HappaTAS_Executor.lua > "$OUT"
grep -q 'Debug           = true' "$OUT" || { echo "could not switch Debug on"; exit 1; }
# test access to the client object tables (parts by id, ids by part, recorder states)
python3 - "$OUT" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
m = "\tfunction CO.Start()\n"
assert s.count(m) == 1, "CO.Start not found"
s = s.replace(m, "\tCO.Tables = function() return parts, ids, S, orig end\n" + m)
open(p, "w", encoding="utf-8").write(s)
PY
cat >> "$OUT" <<'EOF'

rawset(genv, "__HappaTAS_T", { Core = Core, C = C, Settings = Settings, Controls = Controls, Store = Store,
	Codec = Codec, Bridge = Bridge, InputSys = InputSys, Cursor = Cursor, AnimEngine = AnimEngine,
	ClientObjects = ClientObjects, Buttons = Buttons, ToolSync = ToolSync, Sounds = Sounds, Profiler = Profiler,
	Menu = Menu, Typing = Typing, Env = Env, Gui = Gui, CONFIG = CONFIG, Janitor = Janitor, UI = UI,
	Lighting = Lighting, SpeedHack = SpeedHack })
EOF
wc -lc "$OUT"
