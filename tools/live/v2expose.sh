#!/usr/bin/env bash
# A copy of a V2 build that also shares its module tables as getgenv().__V2T, for tools/live/meter3.lua's
# Meter.sections (test tool, never shipped).
#   bash tools/live/v2expose.sh IN.lua OUT.lua
set -euo pipefail
IN="$1"; OUT="$2"
sed 's/^genv\["__HappaTAS"\] = handle -- only.*$/genv["__HappaTAS"] = handle\ngenv.__V2T = { C = C, Core = Core, Store = Store, Bridge = Bridge, InputSys = InputSys, Cursor = Cursor, AnimEngine = AnimEngine, ClientObjects = ClientObjects, Buttons = Buttons, Lighting = Lighting, ToolSync = ToolSync, SpeedHack = SpeedHack, KitClock = KitClock, KitObjects = KitObjects }/' "$IN" > "$OUT"
grep -q "__V2T" "$OUT" || { echo "v2expose: the handle line wasn't found in $IN" >&2; exit 1; }
