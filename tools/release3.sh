#!/bin/bash
# HappaTAS 3's release: wow (the file to run in the executor) built from src2/ without comments and blank lines,
# and wow1, the same file. bash tools/check_release3.sh checks the result.
#   bash tools/release3.sh
set -e
cd "$(dirname "$0")/.."
bash tools/build3.sh --release wow >/dev/null
cp wow wow1
echo "wow, wow1: HappaTAS $(grep -m1 -oE 'VERSION = "[^"]+"' src2/config.lua | cut -d'"' -f2)"
