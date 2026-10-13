#!/bin/bash
# Release build: join the parts, then write the script without comments and blank lines.
#   bash tools/release.sh [OUT]        (OUT defaults to ./wow, the file to run in the executor)
set -e
cd "$(dirname "$0")/.."
OUT="${1:-wow}"
bash tools/assemble.sh >/dev/null
VERSION=$(grep -m1 -oE 'local VERSION = "[^"]+"' src/parts/p00_header.lua | cut -d'"' -f2)
python3 tools/strip.py src/HappaTAS_Executor.lua "$OUT" \
  "HappaTAS Executor Port $VERSION - records and replays TAS runs on the client (executor script)." \
  "Saves to <executor workspace>/HappaTasPort/<PlaceId>/. Press M for the menu (controls, settings, saves, help)." \
  "Release build: comments and blank lines removed. The commented source is src/parts/ (HappaTasPort repository)."
