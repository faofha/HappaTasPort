#!/bin/bash
# V2 fixtures for HappaTAS 3's V2 reader: runs tests3/fixtures/v2gen.lua inside the reference V2.38.16
# build (src/parts at commit b1569bd, never the working tree) in the headless mock, and writes
#   tests3/fixtures/v2/<name>          the file V2 saved (or a derived / legacy one)
#   tests3/fixtures/v2/<name>.expected.lua   what V2's own decoder makes of it
#   bash tools/make_v2_fixtures3.sh
set -e
cd "$(dirname "$0")/.."
LUAU="${LUAU:-$(command -v luau || echo /home/claude/tools/luau/luau)}"
REF=tests3/trace/ref
if [ ! -f "$REF/src/HappaTAS_Executor.lua" ]; then
  rm -rf "$REF"; mkdir -p "$REF"
  git archive b1569bd src/parts tools/assemble.sh tools/order.txt | tar -x -C "$REF"
  bash "$REF/tools/assemble.sh" >/dev/null
fi
RUN=tests3/fixtures/run_v2gen.lua
{
  cat tests/mock/dt.lua tests/mock/json_lz4.lua tests/mock/inst.lua tests/mock/svc.lua
  echo 'local os = setmetatable({ clock = function() return M.clock() end }, { __index = os })'
  echo 'local function __SCRIPT__()'
  sed -e 's/^\(\s*\)Debug           = false,/\1Debug           = true,/' "$REF/src/HappaTAS_Executor.lua"
  echo ''
  echo '__T = { Codec = Codec, Store = Store }'
  echo 'end'
  cat tests/test_util.lua tests3/fixtures/v2gen.lua
} > "$RUN"
OUT=tests3/fixtures/v2gen_out.txt
(cd tests3/fixtures && "$LUAU" run_v2gen.lua > v2gen_out.txt 2>&1) || { tail -5 "$OUT"; exit 1; }
rm -f "$RUN"
grep -q "^RESULT .* 0 failed" "$OUT" || { tail -5 "$OUT"; exit 1; }
rm -rf tests3/fixtures/v2
mkdir -p tests3/fixtures/v2
python3 - "$OUT" <<'EOF'
import sys, binascii
for line in open(sys.argv[1], encoding='utf-8', errors='replace'):
    parts = line.rstrip('\r\n').split(' ')
    if len(parts) == 3 and parts[0] in ('FILE', 'EXPECTED'):
        name = parts[2 - 1]
        data = binascii.unhexlify(parts[2])
        path = 'tests3/fixtures/v2/' + name + ('.expected.lua' if parts[0] == 'EXPECTED' else '')
        open(path, 'wb').write(data)
    elif parts and parts[0] == 'INFO':
        print(' '.join(parts[1:]))
EOF
rm -f "$OUT"
ls -l tests3/fixtures/v2 | awk 'NR > 1 { print $5, $9 }'
