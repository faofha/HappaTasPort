#!/bin/bash
# Concatenate the part files (in tools/order.txt order) into src/HappaTAS_Executor.lua
cd "$(dirname "$0")/.."
out=src/HappaTAS_Executor.lua
: > "$out"
while read -r name; do
  [ -z "$name" ] && continue
  cat "src/parts/$name.lua" >> "$out"
done < tools/order.txt
# drop the single trailing newline added by the last part so the output matches byte for byte
python3 -c "
import sys
p='$out'
d=open(p,'rb').read()
if d.endswith(b'\n\n'): d=d[:-1]
open(p,'wb').write(d)
"
wc -lc "$out"
