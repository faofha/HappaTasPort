# Prints a Lua table of every fixture file in a folder, for tests3 suites that say "-- needs: v2fixtures":
#   FIXTURES = { [name] = { data = "<the bytes>", expected = (function() <name>.expected.lua end)() } }
#   python3 tools/fixtures3_lua.py tests3/fixtures/v2
import os, sys

def lua_bytes(b):
    out = []
    for c in b:
        if 32 <= c < 127 and c not in (34, 92):
            out.append(chr(c))
        else:
            out.append('\\%03d' % c)
    return '"' + ''.join(out) + '"'

folder = sys.argv[1]
names = sorted(n for n in os.listdir(folder) if not n.endswith('.expected.lua'))
print('FIXTURES = {}')
for n in names:
    data = open(os.path.join(folder, n), 'rb').read()
    exp = open(os.path.join(folder, n + '.expected.lua'), encoding='utf-8').read()
    print('FIXTURES[%s] = { data = %s, expected = (function() %s end)() }' % (lua_bytes(n.encode()), lua_bytes(data), exp))
