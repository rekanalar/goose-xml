#!/usr/bin/env python3
"""Makes test/xml_cases.goose for goose-xml from xml.etree.ElementTree.

Usage, in the package directory:
  python3 test/make_xml_cases.py > test/xml_cases.goose

Two kinds of case. An ok case holds a document that ElementTree accepts and
the render of its tree. A bad case holds a document that ElementTree refuses.
The inputs are a fixed list, generated documents, and byte mutations of both.
A document that holds a stated limit of the package is left out: a declared
encoding, an internal DTD subset, a name that the fourth and fifth edition
tables judge differently, and a depth above 256. The seed
is fixed, so the output is stable. The count goes to standard error.
"""
import random
import re
import sys
import xml.etree.ElementTree as ET

sys.setrecursionlimit(20000)
rng = random.Random(20261107)

INPUTS = [
 # basics
 b'<a/>', b'<a></a>', b'<a>x</a>', b'<a x="1" y=\'2\'>t</a>', b'<a><b/><c>x</c></a>',
 # whitespace and newlines
 b'<a>x\r\ny</a>', b'<a>x\ry</a>', b'<a x="a\tb\nc\r\nd"/>', b'<a>  </a>', b'  <a/>', b'\n<a/>\n',
 b'<a x = "1" />', b'<a\n x="1"\n/>', b'<a ></a >',
 # declaration
 b'<?xml version="1.0"?><a/>', b'<?xml version="1.0" encoding="UTF-8"?><a/>', b' <?xml version="1.0"?><a/>',
 b'<?xml version="1.0" encoding="ISO-8859-1"?><a>\xe9</a>', b'<?xml version="2.0"?><a/>', b'<?xml?><a/>',
 b'<?xml version="1.0" standalone="yes"?><a/>', b'<a/><?xml version="1.0"?>',
 # BOM
 b'\xef\xbb\xbf<a/>', b'\xef\xbb\xbf<?xml version="1.0"?><a/>',
 # entities
 b'<a>&amp;&lt;&gt;&quot;&apos;</a>', b'<a>&#65;&#x41;&#x1F600;</a>', b'<a>&#0;</a>', b'<a>&#xD800;</a>',
 b'<a>&#x110000;</a>', b'<a>&#1;</a>', b'<a>&#xFFFE;</a>', b'<a>&foo;</a>', b'<a>&amp</a>', b'<a>&;</a>',
 b'<a>&#;</a>', b'<a>&#x;</a>', b'<a>&#xZ;</a>', b'<a>&#65</a>', b'<a>a & b</a>', b'<a>a < b</a>', b'<a>a > b</a>',
 b'<a x="&amp;&lt;&#65;"/>', b'<a x="a<b"/>', b'<a x="a>b"/>', b'<a x="a&b"/>', b'<a x="&foo;"/>',
 b'<a>]]></a>', b'<a>&#x00041;</a>', b'<a>&#X41;</a>',
 # cdata
 b'<a><![CDATA[x<y&z]]></a>', b'<a>p<![CDATA[q]]>r</a>', b'<a><![CDATA[]]></a>', b'<a><![CDATA[x]]]></a>',
 b'<a><![CDATA[x</a>', b'<![CDATA[x]]><a/>', b'<a><![CDATA[a]]]]><![CDATA[>b]]></a>', b'<a><![CDATA[x]]>]]></a>',
 b'<a><![cdata[x]]></a>',
 # comments
 b'<a><!--c--></a>', b'<!--c--><a/>', b'<a/><!--c-->', b'<a><!----></a>', b'<a><!-- a--b --></a>', b'<a><!--a---></a>',
 b'<a><!--x</a>', b'<a>t<!--c-->u</a>', b'<a><!-></a>',
 # PI
 b'<a><?p d?></a>', b'<a><?p?></a>', b'<?p d?><a/>', b'<a/><?p d?>', b'<a><?xml d?></a>', b'<a><?P d?></a>',
 b'<a><? d?></a>', b'<a><?p d</a>', b'<a><?p ?></a>',
 # doctype
 b'<!DOCTYPE a><a/>', b'<!DOCTYPE a SYSTEM "a.dtd"><a/>', b'<!DOCTYPE a [<!ELEMENT a ANY>]><a/>',
 b'<!DOCTYPE a [<!ENTITY e "v">]><a>&e;</a>', b'<!DOCTYPE a [<!ENTITY e "v">]><a x="&e;"/>',
 b'<!DOCTYPE a [<!ATTLIST a x CDATA "d">]><a/>', b'<a><!DOCTYPE a></a>', b'<!DOCTYPE a><!DOCTYPE b><a/>',
 b'<!DOCTYPE a [<!ENTITY % p "x">]><a/>', b'<!DOCTYPE a SYSTEM "x"><a>&foo;</a>',
 b'<!DOCTYPE a [<!ENTITY l1 "&l2;"><!ENTITY l2 "&l1;">]><a>&l1;</a>',
 b'<!DOCTYPE a [<!ENTITY x SYSTEM "file:///etc/passwd">]><a>&x;</a>',
 b'<!DOCTYPE a [<!ENTITY e "v">]><a>&e;&e;</a>',
 # names
 b'<a-b.c_d/>', b'<_a/>', b'<:a/>', b'<a:/>', b'<1a/>', b'<-a/>', b'<.a/>', b'<\xc3\xa9/>', b'<\xe6\xb0\xb4 x="1"/>',
 b'<a\xc2\xb7/>', b'<\xc2\xb7a/>', b'< a/>', b'<a b/>', b'<a b=c/>', b'<a b=/>', b'<a =1/>', b'<a b="1"c="2"/>',
 b'<a b="1" b="2"/>', b'<a b="1"b="2"/>',
 # structure
 b'', b' ', b'x', b'<a>', b'</a>', b'<a></b>', b'<a><b></a></b>', b'<a/><b/>', b'<a/>x', b'x<a/>', b'<a/> <b/>',
 b'<a', b'<a x', b'<a x=', b'<a x="1', b'<a x="1"', b'<a/', b'<', b'<>', b'</>', b'<a></a', b'<a></a x>', b'<a></ a>',
 b'<a>\x00</a>', b'<a>\x01</a>', b'<a>\x0b</a>', b'<a>\xff</a>', b'<a>\xc3\x28</a>', b'<a>\xed\xa0\x80</a>',
 b'<a>\xef\xbf\xbe</a>', b'<a>\xf4\x90\x80\x80</a>', b'<a>\xc0\x80</a>', b'<a x="\xff"/>', b'<\xff/>',
 b'<a>\xf0\x9f\x98\x80</a>', b'<a>\xe2\x80\xa8</a>',
 # namespaces
 b'<a xmlns="u"><b/></a>', b'<p:a xmlns:p="u"><p:b/></p:a>', b'<a xmlns:p="u" p:x="1"/>', b'<a xmlns="u" x="1"/>',
 b'<p:a/>', b'<a p:x="1"/>', b'<a xmlns:p="u" xmlns:q="u" p:x="1" q:x="2"/>', b'<a xmlns:p=""/>', b'<a xmlns=""/>',
 b'<a xmlns="u"><b xmlns=""/></a>', b'<xml:a/>', b'<a xml:lang="en"/>', b'<a xmlns:xml="http://www.w3.org/XML/1998/namespace"/>',
 b'<a xmlns:xml="u"/>', b'<a xmlns:xmlns="u"/>', b'<a xmlns="http://www.w3.org/2000/xmlns/"/>', b'<a:b:c xmlns:a="u"/>',
 b'<a xmlns:a="u" a:b:c="1"/>', b'<:a xmlns:b="u"/>', b'<a xmlns:p="u"><p:b/></a>', b'<a xmlns:p="u"/><p:b/>',
 b'<a xmlns:1="u"/>', b'<a xmlns:p="u" xmlns:p="v"/>', b'<a xmlns:p="a b"/>', b'<a xmlns:p="&amp;"/>',
 b'<a xmlns:p="u"><p:b p:x="1" x="2"/></a>',
 # depth
 b'<a>' * 200 + b'</a>' * 200, b'<a>' * 256 + b'</a>' * 256, b'<a>' * 257 + b'</a>' * 257, b'<a>' * 1000 + b'</a>' * 1000,
]


def render_et(e):
    attrs = ';'.join('%s=%s' % (k, v.encode().hex()) for k, v in e.attrib.items())
    out = 'E{%s;%s}' % (e.tag, attrs)
    if e.text:
        out += '|' + e.text.encode().hex()
    for c in e:
        out += render_et(c)
        if c.tail:
            out += '|' + c.tail.encode().hex()
    return out + '/'


def merge(s):
    def j(m):
        d = m.group(0).replace('|', '')
        return '|' + d if d else ''
    return re.sub(r'(?:\|[0-9a-f]*)+', j, s)


def answer(b):
    try:
        return merge(render_et(ET.fromstring(b)))
    except ET.ParseError:
        return None


R5 = [(192, 214), (216, 246), (248, 767), (880, 893), (895, 8191), (8204, 8205), (8304, 8591),
      (11264, 12271), (12289, 55295), (63744, 64975), (65008, 65533), (65536, 983039)]


def name5(c):
    return any(a <= c <= b for a, b in R5) or c == 183 or 768 <= c <= 879 or 8255 <= c <= 8256


_names = {}


def names_agree(c):
    """expat uses the name tables of XML 1.0, fourth edition. The package uses the fifth."""
    if c not in _names:
        try:
            ET.fromstring(('<a%s/>' % chr(c)).encode())
            got = True
        except ET.ParseError:
            got = False
        _names[c] = got == name5(c)
    return _names[c]


def limit(b):
    """Says whether b holds a stated limit of the package."""
    try:
        text = b.decode('utf-8')
    except UnicodeDecodeError:
        text = ''
    # Only names matter: the fourth and fifth edition tables differ there.
    names = re.findall(r'</?([^\s>/=!?"\'<]+)', text) + re.findall(r'\s([^\s=<>"\'/]+)\s*=', text)
    for nm in names:
        if not all(names_agree(ord(ch)) for ch in nm if ord(ch) > 127):
            return True
    if re.search(rb'encoding\s*=\s*["\'](?!utf-8["\']|us-ascii["\'])', b, re.I):
        return True
    if re.search(rb'<!DOCTYPE[^>\[]*\[', b):
        return True
    depth = best = 0
    for m in re.finditer(rb'<(/?)[^!?>]', b):
        depth += -1 if m.group(1) else 1
        best = max(best, depth)
    return best > 255


def esc(b):
    return '"' + ''.join('\\x%02x' % c for c in b) + '"'


NAMES = ['a', 'b', 'item', 'x-y', 'n.1', '_u', 'é', '水', 'ab\u00b7c', 'p:q']
TEXTS = ['', 'x', 'a b', 'ü', '\U0001f600', 'a&amp;b', '&lt;t&gt;', '&#65;&#x1F600;', 'x\r\ny', 'tab\there', ']]', '>']
ATTRS = ['', '1', 'a b', '&amp;&quot;', 'ü水', 'a\tb\nc', '&#10;&#9;', "it's", '>']


def gen(depth=0):
    n = rng.choice(NAMES[:9])
    attrs = ''
    seen = set()
    for _ in range(rng.randrange(3)):
        k = rng.choice(['x', 'y', 'id', 'é', 'z.1', 'q-r'])
        if k in seen:
            continue
        seen.add(k)
        q = rng.choice('"\'')
        v = rng.choice(ATTRS).replace(q, '&quot;' if q == '"' else '&apos;')
        attrs += ' %s=%s%s%s' % (k, q, v, q)
    if depth > 3 or rng.random() < 0.3:
        return '<%s%s/>' % (n, attrs) if rng.random() < 0.5 else '<%s%s></%s>' % (n, attrs, n)
    body = ''
    for _ in range(rng.randrange(5)):
        k = rng.randrange(6)
        if k == 0:
            body += gen(depth + 1)
        elif k == 1:
            body += rng.choice(TEXTS)
        elif k == 2:
            body += '<![CDATA[%s]]>' % rng.choice(['', 'x<y&z', 'a]]b', '\r\n'])
        elif k == 3:
            body += '<!--%s-->' % rng.choice(['', 'c', ' a-b ', 'x y'])
        elif k == 4:
            body += '<?%s %s?>' % (rng.choice(['p', 'pi', 'q.1']), rng.choice(['d', 'a b', '']))
        else:
            body += rng.choice(TEXTS)
    return '<%s%s>%s</%s>' % (n, attrs, body, n)


def gen_doc():
    pre = rng.choice(['', '', '<?xml version="1.0"?>', '<?xml version="1.0" encoding="UTF-8"?>\n', '\ufeff', '<!--c-->', '<!DOCTYPE a>', '<?p d?>\n'])
    post = rng.choice(['', '', '\n', '<!--e-->', '<?p d?>', ' <!--x--> '])
    return (pre + gen() + post).encode('utf-8')


def mutate(b):
    b = bytearray(b)
    kind = rng.randrange(5)
    if not b:
        return bytes(b)
    if kind == 0:
        b = b[:rng.randrange(len(b))]
    elif kind == 1:
        b[rng.randrange(len(b))] = rng.randrange(256)
    elif kind == 2:
        b.insert(rng.randrange(len(b) + 1), rng.choice(b'<>&;"\'-]?!/=: \x00\x01\x0b\xff\xc3'))
    elif kind == 3:
        del b[rng.randrange(len(b))]
    else:
        i = rng.randrange(len(b))
        b[i] ^= 1 << rng.randrange(8)
    return bytes(b)


pool = list(INPUTS)
seen = set(pool)
while len(pool) < 700:
    d = gen_doc()
    if d not in seen:
        seen.add(d)
        pool.append(d)
base = list(pool)
tries = 0
while len(pool) < 1500 and tries < 50000:
    tries += 1
    m = mutate(rng.choice(base))
    if m not in seen:
        seen.add(m)
        pool.append(m)

lines = []
ok = bad = skipped = 0
for b in pool:
    if limit(b):
        skipped += 1
        continue
    r = answer(b)
    if r is None:
        lines.append('    expect_bad(%d, %s);' % (len(lines), esc(b)))
        bad += 1
    else:
        lines.append('    expect_ok(%d, %s, "%s");' % (len(lines), esc(b), r))
        ok += 1

out = []
out.append('// Cases made by test/make_xml_cases.py with xml.etree.ElementTree, seed 20261107.')
out.append('// Do not edit by hand. Make the file again with the script.')
out.append('// Count: %d cases (ok %d, bad %d), %d left out as stated limits.' % (ok + bad, ok, bad, skipped))
out.append('')
out.append(open(__file__.replace('make_xml_cases.py', 'xml_cases_head.txt')).read())
out.append('fn check_xml_cases() {')
out.extend(lines)
out.append('}')
sys.stdout.write('\n'.join(out) + '\n')
sys.stderr.write('%d cases, ok %d, bad %d, left out %d\n' % (ok + bad, ok, bad, skipped))
