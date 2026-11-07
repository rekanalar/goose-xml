#!/usr/bin/env python3
"""Makes encoding_data.goose: the 8-bit code pages that Python decodes in XML.

Usage, in the package directory:
  python3 test/make_encoding_data.py > encoding_data.goose

The tables come from the codecs of Python 3.14. The alias list comes from
encodings.aliases, for the codecs in the table.
"""
import codecs
import encodings.aliases as A
import sys

NAMES = ['iso8859-%d' % i for i in range(1, 17) if i != 12] + \
        ['cp125%d' % i for i in range(9)] + \
        ['koi8-r', 'koi8-u', 'cp437', 'cp850', 'cp852', 'cp855', 'cp866', 'mac-roman', 'cp874', 'ascii']
canon = []
tables = []
for n in NAMES:
    c = codecs.lookup(n).name
    if c in canon:
        continue
    canon.append(c)
    t = []
    for b in range(128, 256):
        try:
            t.append(ord(bytes([b]).decode(c)))
        except UnicodeDecodeError:
            t.append(0xFFFD)
    tables.append(t)
alias = {}
import encodings
import pkgutil
MODS = [m.name for m in pkgutil.iter_modules(encodings.__path__)]
for k in list(A.aliases) + MODS + [c.replace('-', '_') for c in canon]:
    try:
        n = codecs.lookup(k).name
    except LookupError:
        continue
    if n in canon:
        alias[k] = n

def q(s):
    return '"' + s + '"'

o = sys.stdout.write
o('// Made by test/make_encoding_data.py from the codecs of Python 3.14. Do not edit.\n')
o('// The tables hold the 128 code points of the bytes 128 to 255 of each page.\n')
o('namespace xml;\n\n')
o('const ENC_COUNT = %d;\n' % len(canon))
o('const ENC_PAGES: const u8[:][] = [%s];\n' % ', '.join(q(c) for c in canon))
items = sorted(alias.items())
o('const ENC_ALIAS_COUNT = %d;\n' % len(items))
o('const ENC_ALIAS_NAMES: const u8[:][] = [%s];\n' % ', '.join(q(k) for k, v in items))
o('const ENC_ALIAS_PAGES: i32[] = [%s];\n' % ', '.join(str(canon.index(v)) for k, v in items))
flat = [x for t in tables for x in t]
o('const ENC_TABLE: i32[] = [\n')
for i in range(0, len(flat), 16):
    o('    ' + ', '.join(str(x) for x in flat[i:i + 16]) + ',\n')
o('];\n')
sys.stderr.write('%d pages, %d aliases\n' % (len(canon), len(items)))
