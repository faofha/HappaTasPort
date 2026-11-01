#!/bin/bash
# V2's release build (V2.38.17, src/parts): join the parts, then write the script without comments and blank
# lines. Since HappaTAS 3.0.0, wow / wow1 are HappaTAS 3 (bash tools/release3.sh): this writes build/wow_v2.
#   bash tools/release.sh [OUT]        (OUT defaults to build/wow_v2)
set -e
cd "$(dirname "$0")/.."
OUT="${1:-build/wow_v2}"
mkdir -p "$(dirname "$OUT")"
bash tools/assemble.sh >/dev/null
VERSION=$(grep -m1 -oE 'local VERSION = "[^"]+"' src/parts/p00_header.lua | cut -d'"' -f2)
python3 tools/strip.py src/HappaTAS_Executor.lua "$OUT" \
  "HappaTAS Executor Port $VERSION - records and replays TAS runs on the client (executor script)." \
  "Saves to <executor workspace>/HappaTasPort/<PlaceId>/. Press M for the menu (controls, settings, saves, help)." \
  "Release build: comments and blank lines removed. The commented source is src/parts/ (HappaTasPort repository)."
