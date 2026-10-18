#!/bin/bash
# HappaTAS 3 build: join the src2/ modules into one file (each module in a function of its own).
#   bash tools/build3.sh [--src DIR] [--check] [--release OUT]
#     --src DIR      module folder (default src2); writes DIR/HappaTAS3.lua
#     --check        load the built file in the headless mock (tests/mock): fails on errors such as
#                    an import cycle or an unknown module
#     --release OUT  also write OUT without comments and blank lines (tools/strip.py)
set -e
cd "$(dirname "$0")/.."
SRC=src2
CHECK=0
REL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --src) SRC="$2"; shift 2 ;;
    --check) CHECK=1; shift ;;
    --release) REL="$2"; shift 2 ;;
    *) echo "build3: unknown option $1"; exit 2 ;;
  esac
done
OUT="$SRC/HappaTAS3.lua"
python3 tools/bundle3.py "$SRC" "$OUT"
if [ "$CHECK" = 1 ]; then
  LUAU="${LUAU:-$(command -v luau || echo /home/claude/tools/luau/luau)}"
  TMP="$SRC/.check3.lua"
  {
    cat tests/mock/dt.lua tests/mock/json_lz4.lua tests/mock/inst.lua tests/mock/svc.lua
    echo 'local __ok, __err = pcall(function()'
    cat "$OUT"
    echo 'end)'
    echo 'if not __ok then M.realPrint(tostring(__err)); error("build3 check failed", 0) end'
  } > "$TMP"
  set +e
  "$LUAU" "$TMP"
  status=$?
  set -e
  rm -f "$TMP"
  [ $status -eq 0 ] || exit 1
fi
if [ -n "$REL" ]; then
  VERSION=$(grep -m1 -oE 'VERSION = "[^"]+"' "$SRC/config.lua" | cut -d'"' -f2)
  python3 tools/strip.py "$OUT" "$REL" \
    "HappaTAS $VERSION - records and replays TAS runs on the client (executor script)." \
    "Release build: comments and blank lines removed. The commented source is src2/ (HappaTasPort repository)."
fi
echo "$OUT"
