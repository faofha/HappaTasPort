#!/usr/bin/env python3
"""HappaTAS 3 bundler: join the modules listed in SRC/modules.txt into one Luau file.

    python3 tools/bundle3.py SRC OUT

Each module (SRC/<name>.lua, a chunk that returns its table) becomes one function in the output,
so no function comes near Luau's 200-locals limit. `import(name)` loads a module once and caches it;
an unknown name or an import cycle errors with a clear message. The last line starts `main`.
"""
import os
import sys

LOADER = '''local __mods, __cache, __loading, __stack = {}, {}, {}, {}
local function import(name)
	local c = __cache[name]
	if c ~= nil then return c end
	if __loading[name] then
		local chain, from = {}, 1
		for i = 1, #__stack do
			if __stack[i] == name then from = i break end
		end
		for i = from, #__stack do chain[#chain + 1] = __stack[i] end
		chain[#chain + 1] = name
		error("HappaTAS3: import cycle: " .. table.concat(chain, " -> "), 2)
	end
	local f = __mods[name]
	if not f then error("HappaTAS3: no module " .. tostring(name), 2) end
	__loading[name] = true
	__stack[#__stack + 1] = name
	local ok, res = pcall(f, import)
	__stack[#__stack] = nil
	__loading[name] = nil
	if not ok then error(res, 0) end
	if res == nil then res = true end
	__cache[name] = res
	return res
end
'''


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    src, out = sys.argv[1], sys.argv[2]
    with open(os.path.join(src, 'modules.txt'), encoding='utf-8') as f:
        names = [ln.strip() for ln in f if ln.strip() and not ln.strip().startswith('#')]
    parts = ['-- HappaTAS 3 (built from ' + src.replace('\\', '/') + '/ by tools/bundle3.py: do not edit by hand)\n', LOADER]
    for name in names:
        path = os.path.join(src, *name.split('/')) + '.lua'
        with open(path, encoding='utf-8') as f:
            body = f.read().rstrip('\n')
        indented = '\n'.join(('\t' + ln) if ln.strip() else '' for ln in body.split('\n'))
        parts.append('__mods["%s"] = function(import)\n%s\nend\n' % (name, indented))
    parts.append('local __main = import("main")\n__main.Start()\n')
    with open(out, 'w', encoding='utf-8', newline='\n') as f:
        f.write(''.join(parts))


if __name__ == '__main__':
    main()
