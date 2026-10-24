#!/bin/bash
# Trace parity: runs one scripted session (tests3/trace/scenario.lua) on V2.38.16 and on HappaTAS 3 in the
# headless mock, and diffs what each one recorded and did.
#   bash tools/trace3.sh
#   TGROUPS="mode F W.char"      trace groups compared (default: every group)
#   FIELDS="Cframe State"       V2 frame fields compared in the F group (default: all)
#   SIDES="v2 v2"               which builds run as side a and side b (default: "v2 v3")
#   UPTO="tag"                  compare only the lines before the first one with this step tag
#   SCENARIO=bench              another session in tests3/trace/ (tools/bench3.sh uses this)
# Prints "SAME (N lines)" or "DIFFERENT:" and the first differing lines (exit 2).
# Full traces: tests3/trace/out_a.txt, out_b.txt. The reference is src/parts at commit b1569bd (V2.38.16),
# never the working tree's src/parts.
set -e
cd "$(dirname "$0")/.."
LUAU="${LUAU:-$(command -v luau || echo /home/claude/tools/luau/luau)}"
REF_COMMIT=b1569bd
T=tests3/trace
REF=$T/ref
TGROUPS="${TGROUPS:-mode F W.char W.cam W.input W.anim W.tool}"
FIELDS="${FIELDS:-all}"
read -r SIDE_A SIDE_B <<< "${SIDES:-v2 v3}"

# the reference build (once)
if [ ! -f "$REF/src/HappaTAS_Executor.lua" ]; then
  rm -rf "$REF"; mkdir -p "$REF"
  git archive "$REF_COMMIT" src/parts tools/assemble.sh tools/order.txt | tar -x -C "$REF"
  bash "$REF/tools/assemble.sh" >/dev/null
fi

build_side() { # SIDE OUT
  local side="$1" out="$2"
  {
    cat tests/mock/dt.lua tests/mock/json_lz4.lua tests/mock/inst.lua tests/mock/svc.lua
    echo 'local os = setmetatable({ clock = function() return M.clock() end }, { __index = os })'
    echo 'local function __SCRIPT__()'
    if [ "$side" = v2 ]; then
      sed -e 's/^\(\s*\)Debug           = false,/\1Debug           = true,/' "$REF/src/HappaTAS_Executor.lua"
      echo ''
      echo '__T = { Settings = Settings, Core = Core, Controls = Controls, InputSys = InputSys, Bridge = Bridge, AnimEngine = AnimEngine, Codec = Codec }'
    else
      bash tools/build3.sh >/dev/null
      sed -e '0,/Debug = false,/s//Debug = true,/' src2/HappaTAS3.lua
      echo ''
      echo '__T3 = import'
    fi
    echo 'end'
    cat tests/test_util.lua "$T/adapter_$side.lua" "$T/${SCENARIO:-scenario}.lua"
  } > "$out"
}

run_side() { # SIDE NAME
  build_side "$1" "$T/run_$2.lua"
  (cd "$T" && "$LUAU" "run_$2.lua" > "raw_$2.txt" 2>&1) || true
  if ! grep -q "^RESULT .* 0 failed" "$T/raw_$2.txt"; then
    echo "side $2 ($1) failed:"; grep -E "FAIL|ERROR|error" "$T/raw_$2.txt" | head -10; tail -3 "$T/raw_$2.txt"; exit 1
  fi
  # keep the compared groups, and in F lines (T|F|tag|i|Field|value) only the compared fields
  awk -F'|' -v groups=" $TGROUPS " -v fields=" $FIELDS " -v upto="$UPTO" '
    $1 != "T" { next }
    upto != "" && $3 == upto { exit }
    index(groups, " " $2 " ") == 0 { next }
    $2 == "F" && fields != " all " && index(fields, " " $5 " ") == 0 { next }
    { print }' "$T/raw_$2.txt" > "$T/out_$2.txt"
}

run_side "$SIDE_A" a
run_side "$SIDE_B" b
if cmp -s "$T/out_a.txt" "$T/out_b.txt"; then
  echo "SAME ($(wc -l < "$T/out_b.txt") lines)"
else
  echo "DIFFERENT:"
  diff "$T/out_a.txt" "$T/out_b.txt" | head -${DIFF_LINES:-40}
  exit 2
fi
