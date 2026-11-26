#!/usr/bin/env python3
"""Delete source directories blossom does not need - but only when nothing else
in the tree refers to them.

Soong fails on an undefined module even if it is unused, so blindly deleting a
repo breaks the build. Instead this computes a fixed point:

  1. Start with every path in trim.list as "removed".
  2. Index what the REMAINING tree references: quoted strings in Android.bp
     (module names, ":name", "//pkg:name"), tokens in *.mk files (PRODUCT_PACKAGES
     and friends) and any mention of a candidate's path.
  3. A candidate that defines a module (or whose path) is referenced from the
     remaining tree is put back; repeat until nothing changes.

Only the final removable set is deleted. A report is written either way.

Usage: trim.py <src_root> <trim.list> [--apply] [--report FILE]
"""
import os, re, sys, shutil

SKIP_DIRS = {'.repo', '.git', 'out'}
NAME_BP = re.compile(r'\bname\s*:\s*"([^"]+)"')
MK_DEF = re.compile(r'\bLOCAL_(?:MODULE|PACKAGE_NAME)\s*[:+]?=\s*([^\s\\#]+)')
QUOTED = re.compile(r'"([^"\n]+)"')
TOKEN = re.compile(r'[A-Za-z0-9_.@+\-]+')


def read(path):
    try:
        with open(path, 'r', errors='ignore') as f:
            return f.read()
    except OSError:
        return ''


def is_build_file(n):
    return n == 'Android.bp' or n == 'Android.mk' or n.endswith('.mk') or n.endswith('.bp')


def walk(root, rel_roots):
    """Yield (relpath, abspath) of build files, pruning SKIP_DIRS."""
    for base in rel_roots:
        top = os.path.join(root, base) if base else root
        if not os.path.isdir(top):
            continue
        for d, dirs, files in os.walk(top):
            dirs[:] = [x for x in dirs if x not in SKIP_DIRS]
            for n in files:
                if is_build_file(n):
                    p = os.path.join(d, n)
                    yield os.path.relpath(p, root), p


def under(rel, cand):
    return rel == cand or rel.startswith(cand + '/')


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    apply = '--apply' in sys.argv
    report = None
    if '--report' in sys.argv:
        report = sys.argv[sys.argv.index('--report') + 1]
        args = [a for a in args if a != report]
    root, listfile = args[0], args[1]

    cands = []
    for line in open(listfile):
        line = line.split('#', 1)[0].strip().rstrip('/')
        if line and os.path.isdir(os.path.join(root, line)):
            cands.append(line)
    cands = sorted(set(cands))

    # Collect every build file once: (rel, text)
    files = []
    for rel, p in walk(root, ['']):
        files.append((rel, read(p)))

    def owner(rel):
        best = None
        for c in cands:
            if under(rel, c) and (best is None or len(c) > len(best)):
                best = c
        return best

    defined = {c: set() for c in cands}   # module names defined by each candidate
    for rel, text in files:
        o = owner(rel)
        if o is None:
            continue
        if rel.endswith('.bp'):
            defined[o].update(NAME_BP.findall(text))
        else:
            defined[o].update(MK_DEF.findall(text))

    removed = set(cands)
    why = {}
    path_re = re.compile('|'.join(re.escape(c) + r'(?:/|\b)' for c in cands)) if cands else None

    while True:
        refs = {}   # token -> first referencing file
        path_refs = {}
        for rel, text in files:
            o = owner(rel)
            if o is not None and o in removed:
                continue
            if rel.endswith('.bp'):
                for s in QUOTED.findall(text):
                    s = s.split('{', 1)[0]
                    s = s.rsplit(':', 1)[-1] if (s.startswith(':') or s.startswith('//')) else s
                    refs.setdefault(s, rel)
            else:
                for t in TOKEN.findall(text):
                    refs.setdefault(t, rel)
            if path_re:
                for m in path_re.finditer(text):
                    path_refs.setdefault(m.group(0).rstrip('/'), rel)
        back = []
        for c in sorted(removed):
            hit = None
            for name in sorted(defined[c]):
                if name in refs and not under(refs[name], c):
                    hit = ('module "%s"' % name, refs[name]); break
            if not hit:
                for pc, who in path_refs.items():
                    if (pc == c or pc.startswith(c + '/')) and not under(who, c):
                        hit = ('path "%s"' % pc, who); break
            if hit:
                back.append(c); why[c] = hit
        if not back:
            break
        removed.difference_update(back)

    lines = ['# trim report (%s)' % ('applied' if apply else 'dry run')]
    lines.append('## removed (%d)' % len(removed))
    for c in sorted(removed):
        lines.append('  - %s  (%d modules)' % (c, len(defined[c])))
    lines.append('## kept because still referenced (%d)' % len(why))
    for c in sorted(why):
        if c not in removed:
            lines.append('  - %s  <- %s in %s' % (c, why[c][0], why[c][1]))
    text = '\n'.join(lines)
    print(text)
    if report:
        os.makedirs(os.path.dirname(report), exist_ok=True)
        open(report, 'w').write(text + '\n')
    if apply:
        for c in sorted(removed):
            shutil.rmtree(os.path.join(root, c), ignore_errors=True)


if __name__ == '__main__':
    main()
