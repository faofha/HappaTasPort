#!/bin/bash
# TEMPORARY DIAGNOSTIC TOOL: copies the speed log and DEBUG copies of HappaTAS 3 (each commit's own `wow`, with
# CONFIG Debug = true so the speed log can see the engine) into Real's workspace folder HappaTasTest/.
# Nothing in the repository changes (git show reads each commit's file; no checkout).
#   bash tools/live/speedlog_builds.sh                  the commits to test first (see the report)
#   bash tools/live/speedlog_builds.sh a026bb8 HEAD     only these
set -e
cd "$(dirname "$0")/../.."
OUT="${HAPPATAS_TEST:-$LOCALAPPDATA/Real/workspace/HappaTasTest}"
mkdir -p "$OUT"
COMMITS="${*:-a026bb8 8ba135c 9635cce 500c515 HEAD}"
for c in $COMMITS; do
  short=$(git rev-parse --short "$c")
  git show "$c:wow" | sed '0,/Debug = false,/s//Debug = true,/' > "$OUT/h3_$c.lua"
  if grep -q "Debug = true," "$OUT/h3_$c.lua"; then echo "h3_$c.lua ($short)"; else echo "h3_$c.lua: Debug line not found" >&2; exit 1; fi
done
cp tools/live/speedlog.lua "$OUT/speedlog.lua"
echo "speedlog.lua"
echo "-> $OUT"
