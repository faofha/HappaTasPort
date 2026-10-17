#!/usr/bin/env python3
"""Bring changes made to a release build (comment-free, like `wow`) back into the commented parts.

    python3 tools/port_release.py OLD_RELEASE NEW_RELEASE [--apply] [--report]

OLD_RELEASE must be what tools/release.sh makes from the current src/parts (the parts it was built from).
Every line of a release build comes from one line of the joined source (tools/strip.py only removes
comments, blank lines and trailing spaces), so the differences between OLD_RELEASE and NEW_RELEASE can
be applied to the commented source at the lines they came from: comments stay where they were. New
lines go after the code line before them (in that line's part). With --apply the parts are rewritten;
the result is checked: its release build must be NEW_RELEASE line for line.
"""
import difflib
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LONG_OPEN = re.compile(r'\[(=*)\[')


def strip_lines(src):
    """strip.py's rules, line by line: returns [(original line index, stripped text)] for code lines"""
    out_lines = []
    cur = []
    line_no = 0
    i, n = 0, len(src)
    in_long_comment = None
    while i < n:
        c = src[i]
        if c == '\n':
            out_lines.append((line_no, ''.join(cur)))
            cur = []
            line_no += 1
            i += 1
            continue
        if c == '-' and src.startswith('--', i):
            m = LONG_OPEN.match(src, i + 2)
            if m:
                close = ']' + m.group(1) + ']'
                k = src.find(close, m.end())
                if k < 0:
                    raise SystemExit('unterminated long comment')
                # newlines inside the comment end lines (strip.py drops them with the comment, which only
                # ever leaves blank lines in these sources)
                for ch in src[i:k + len(close)]:
                    if ch == '\n':
                        out_lines.append((line_no, ''.join(cur)))
                        cur = []
                        line_no += 1
                i = k + len(close)
            else:
                k = src.find('\n', i)
                i = n if k < 0 else k
            continue
        if c == '"' or c == "'":
            j = i + 1
            while True:
                if src[j] == '\\':
                    j += 2
                    continue
                if src[j] == c:
                    break
                j += 1
            cur.append(src[i:j + 1])
            i = j + 1
            continue
        if c == '[':
            m = LONG_OPEN.match(src, i)
            if m:
                close = ']' + m.group(1) + ']'
                k = src.find(close, m.end())
                cur.append(src[i:k + len(close)])
                i = k + len(close)
                continue
        cur.append(c)
        i += 1
    out_lines.append((line_no, ''.join(cur)))
    return [(ln, t.rstrip()) for ln, t in out_lines if t.strip()]


def read_parts():
    order = [l.strip() for l in open(os.path.join(ROOT, 'tools', 'order.txt')) if l.strip()]
    lines, owner = [], []
    for name in order:
        txt = open(os.path.join(ROOT, 'src', 'parts', name + '.lua'), encoding='utf-8').read()
        pl = txt.split('\n')
        if pl and pl[-1] == '':
            pl = pl[:-1]
        for l in pl:
            lines.append(l)
            owner.append(name)
    return order, lines, owner


def code_of(release_path):
    rl = open(release_path, encoding='utf-8').read().split('\n')
    if rl and rl[-1] == '':
        rl = rl[:-1]
    # the release header: comment lines at the top
    k = 0
    while k < len(rl) and rl[k].startswith('-- '):
        k += 1
    return rl[k:]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    apply = '--apply' in sys.argv
    report = '--report' in sys.argv
    old_code, new_code = code_of(args[0]), code_of(args[1])
    order, lines, owner = read_parts()
    src = '\n'.join(lines) + '\n'
    mapped = strip_lines(src)
    stripped = [t for _, t in mapped]
    if stripped != old_code:
        for idx, (a, b) in enumerate(zip(stripped, old_code)):
            if a != b:
                raise SystemExit('the parts do not match OLD_RELEASE at code line %d:\n  parts:   %r\n  release: %r' % (idx + 1, a, b))
        raise SystemExit('the parts do not match OLD_RELEASE (length %d vs %d)' % (len(stripped), len(old_code)))
    lineof = [ln for ln, _ in mapped]
    sm = difflib.SequenceMatcher(None, old_code, new_code, autojunk=False)
    ops = [op for op in sm.get_opcodes() if op[0] != 'equal']
    per_part = {}
    for tag, i1, i2, j1, j2 in ops:
        at = lineof[i1] if i1 < len(lineof) else lineof[-1]
        if tag == 'insert' and i1 > 0:
            at = lineof[i1 - 1]
        p = owner[at]
        st = per_part.setdefault(p, [0, 0, 0])
        st[0] += 1
        st[1] += i2 - i1
        st[2] += j2 - j1
    for p in order:
        if p in per_part:
            h, d, a = per_part[p]
            print('%-20s %4d changes, %5d lines out, %5d lines in' % (p, h, d, a))
    if report:
        for tag, i1, i2, j1, j2 in ops:
            at = lineof[i1] if i1 < len(lineof) else lineof[-1]
            if tag == 'insert' and i1 > 0:
                at = lineof[i1 - 1]
            print('=== %s %s source line %d (code %d-%d -> %d-%d)' % (owner[at], tag, at + 1, i1 + 1, i2, j1 + 1, j2))
            for l in old_code[i1:i2]:
                print('- ' + l)
            for l in new_code[j1:j2]:
                print('+ ' + l)
    if not apply:
        return
    # new source lines: per original line, what replaces it (None = keep, list = these lines instead);
    # insertions after an original line
    replace = {}
    after = {}
    for tag, i1, i2, j1, j2 in ops:
        new = new_code[j1:j2]
        if tag == 'insert':
            if i1 == 0:
                after.setdefault(-1, []).extend(new)
            else:
                after.setdefault(lineof[i1 - 1], []).extend(new)
            continue
        olds = lineof[i1:i2]
        if tag == 'delete':
            for ln in olds:
                replace[ln] = []
            continue
        # replace: the same number of lines -> line by line (keeps the comments between them);
        # otherwise the new block goes where the first old line was
        if len(olds) == len(new):
            for ln, nl in zip(olds, new):
                replace[ln] = [nl]
        else:
            replace[olds[0]] = list(new)
            for ln in olds[1:]:
                replace[ln] = []
    out_lines, out_owner = [], []
    for ln in after.get(-1, []):
        out_lines.append(ln)
        out_owner.append(owner[0])
    for idx, l in enumerate(lines):
        if idx in replace:
            for nl in replace[idx]:
                out_lines.append(nl)
                out_owner.append(owner[idx])
        else:
            out_lines.append(l)
            out_owner.append(owner[idx])
        for nl in after.get(idx, []):
            out_lines.append(nl)
            out_owner.append(owner[idx])
    check = [t for _, t in strip_lines('\n'.join(out_lines) + '\n')]
    if check != new_code:
        for idx, (a, b) in enumerate(zip(check, new_code)):
            if a != b:
                raise SystemExit('the result does not match NEW_RELEASE at code line %d:\n  got:  %r\n  want: %r' % (idx + 1, a, b))
        raise SystemExit('the result does not match NEW_RELEASE (length %d vs %d)' % (len(check), len(new_code)))
    for p in order:
        body = [l for l, o in zip(out_lines, out_owner) if o == p]
        with open(os.path.join(ROOT, 'src', 'parts', p + '.lua'), 'w', encoding='utf-8', newline='\n') as f:
            f.write('\n'.join(body) + '\n')
    print('parts rewritten; their release build is NEW_RELEASE line for line')


if __name__ == '__main__':
    main()
