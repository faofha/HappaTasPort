#!/bin/bash
# The committed release is HappaTAS 3: wow is the release build of src2/ byte for byte, wow1 is the same file,
# its first line names the version, and V2's tools/release.sh (run out of habit) leaves wow alone.
#   bash tools/check_release3.sh        (exit 0 = all true, 1 = the first thing that isn't)
set -e
cd "$(dirname "$0")/.."
TMP=$(mktemp)
KEEP=$(mktemp)
trap 'rm -f "$TMP" "$KEEP"' EXIT
bash tools/build3.sh --release "$TMP" >/dev/null
VERSION=$(grep -m1 -oE 'VERSION = "[^"]+"' src2/config.lua | cut -d'"' -f2)
fail() { echo "check_release3: $1"; exit 1; }
cmp -s "$TMP" wow || fail "wow is not the release build of src2 (bash tools/release3.sh)"
cmp -s wow wow1 || fail "wow1 is not the same file as wow"
[ "$(head -1 wow)" = "-- HappaTAS $VERSION - records and replays TAS runs on the client (executor script)." ] \
  || fail "wow's first line doesn't name HappaTAS $VERSION"
before=$(sha1sum wow | cut -d' ' -f1)
cp wow "$KEEP"
bash tools/release.sh >/dev/null
after=$(sha1sum wow | cut -d' ' -f1)
rm -f build/wow_v2
[ "$before" = "$after" ] || { cp "$KEEP" wow; fail "V2's tools/release.sh wrote wow (put back)"; }
echo "check_release3: OK (wow = wow1 = HappaTAS $VERSION)"
