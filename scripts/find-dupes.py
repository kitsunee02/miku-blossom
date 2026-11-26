#!/usr/bin/env python3
"""List every module that more than one directory defines in Soong's generated
Android-<product>.mk.

Kati aborts on the FIRST duplicate (base_rules.mk "already defined by"), which
means one 25-minute CI run per conflict. This reads the same generated makefile
and reports all of them at once.

A key is (LOCAL_MODULE, class, host/target, recovery/vendor/... flags). Variants
of one module (arm/arm64, shared/static) share a LOCAL_PATH, so only keys seen
under two or more DIFFERENT LOCAL_PATHs are reported.

Usage: find-dupes.py <Android-product.mk> [--max N]
"""
import re, sys, collections

SET = re.compile(r'^(LOCAL_[A-Z0-9_]+)\s*[:+]?=\s*(.*?)\s*$')
FLAGS = ('LOCAL_IS_HOST_MODULE', 'LOCAL_IN_RECOVERY', 'LOCAL_IN_VENDOR', 'LOCAL_IN_VENDOR_RAMDISK',
         'LOCAL_IN_RAMDISK', 'LOCAL_PROPRIETARY_MODULE', 'LOCAL_VENDOR_MODULE', 'LOCAL_PRODUCT_MODULE',
         'LOCAL_SYSTEM_EXT_MODULE', 'LOCAL_ODM_MODULE')


def main():
    path = sys.argv[1]
    limit = int(sys.argv[sys.argv.index('--max') + 1]) if '--max' in sys.argv else 200
    seen = collections.defaultdict(lambda: collections.defaultdict(int))
    cur = {}

    def flush():
        name = cur.get('LOCAL_MODULE')
        lp = cur.get('LOCAL_PATH')
        if name and lp:
            key = (name, cur.get('LOCAL_MODULE_CLASS', ''),) + tuple(
                (f.replace('LOCAL_', ''), cur[f]) for f in FLAGS if cur.get(f) not in (None, '', 'false'))
            seen[key][lp] += 1

    with open(path, errors='ignore') as f:
        for line in f:
            if line.startswith('include $(CLEAR_VARS)'):
                flush()
                cur = {}
                continue
            m = SET.match(line)
            if m:
                cur[m.group(1)] = m.group(2)
        flush()

    dups = {k: v for k, v in seen.items() if len(v) > 1}
    print('# modules defined by more than one directory: %d' % len(dups))
    for key in sorted(dups, key=lambda k: (k[0], k[1]))[:limit]:
        flags = ','.join('%s' % a for a, _ in key[2:]) or '-'
        print('%s  [%s %s]' % (key[0], key[1] or '-', flags))
        for lp in sorted(dups[key]):
            print('    %s' % lp)


if __name__ == '__main__':
    main()
