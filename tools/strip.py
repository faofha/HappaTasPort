#!/usr/bin/env python3
"""Release build: copy a Lua/Luau file without comments, blank lines and trailing spaces.

    python3 tools/strip.py IN.lua OUT.lua "header line" ["header line" ...]

Strings ("..", '..', [[..]], [=[..]=]) are copied exactly; '--' inside a string is not a comment.
The code itself is not changed (no renaming, no joined lines), so line structure and behaviour stay
the same. The header lines are written first, as comments.
"""
import re
import sys

LONG_OPEN = re.compile(r'\[(=*)\[')


def strip(src):
    out = []          # pieces of code (strings kept as they are)
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '-' and src.startswith('--', i):
            m = LONG_OPEN.match(src, i + 2)
            if m:  # --[[ long comment ]] / --[==[ ... ]==]
                close = ']' + m.group(1) + ']'
                k = src.find(close, m.end())
                if k < 0:
                    raise SystemExit('unterminated long comment at %d' % i)
                i = k + len(close)
            else:  # -- comment to the end of the line
                k = src.find('\n', i)
                i = n if k < 0 else k
            continue
        if c == '"' or c == "'":
            j = i + 1
            while True:
                if j >= n or src[j] == '\n':
                    raise SystemExit('unterminated string at %d' % i)
                if src[j] == '\\':
                    if src[j + 1] == '\n':
                        raise SystemExit('string continued over a line at %d (not supported)' % i)
                    j += 2
                    continue
                if src[j] == c:
                    break
                j += 1
            out.append(src[i:j + 1])
            i = j + 1
            continue
        if c == '[':
            m = LONG_OPEN.match(src, i)
            if m:
                close = ']' + m.group(1) + ']'
                k = src.find(close, m.end())
                if k < 0:
                    raise SystemExit('unterminated long string at %d' % i)
                s = src[i:k + len(close)]
                if '\n' in s:
                    raise SystemExit('multi-line long string at %d (not supported)' % i)
                out.append(s)
                i = k + len(close)
                continue
        out.append(c)
        i += 1
    lines = [l.rstrip() for l in ''.join(out).split('\n')]
    return [l for l in lines if l.strip()]


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    src = open(sys.argv[1], encoding='utf-8').read()
    lines = ['-- ' + h for h in sys.argv[3:]] + strip(src)
    with open(sys.argv[2], 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    print('%s: %d lines' % (sys.argv[2], len(lines)))


if __name__ == '__main__':
    main()
