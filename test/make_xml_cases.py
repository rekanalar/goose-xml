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


# ---- the path language and the reading calls ----
import xml.etree.ElementPath as EP
prng = random.Random(20261108)

PDOCS = [
 '<r><a/><a x="1"/><b><a/><c>t</c></b><a y="2"/></r>',
 '<r xmlns="urn:d" xmlns:p="urn:p"><a/><p:a/><p:b p:k="1" k="2"><a/></p:b></r>',
 '<r><a>t1<!--c-->t2<b>u</b>t3</a><a>t1t2</a><a><b>x</b><b>y</b></a><c/></r>',
 '<r><a x="1" y="2"><b x="1"/><b x="2"/><b/></a><a x="3"/></r>',
 '<r xmlns:p="urn:p"><p:a xmlns="urn:q" p:x="1" z="2"><c/></p:a><a/><b><b><b/></b></b></r>',
 '<r><item id="1">one</item><item id="2">two</item><item id="3">three</item><other/></r>',
 '<r>lead<a>in</a>mid<a/>tail<![CDATA[<cd>]]></r>',
 '<r><a><b><c><d/></c></b></a><a><b/></a><a/></r>',
 '<r><a>1</a><a>2</a><a>3</a><a>4</a><a>5</a></r>',
]
PATHS = [
 'a', 'b', '*', '.', '..', './a', './/a', './/*', 'a/b', 'a/*', '*/a', '*/*', './/a/b', './/b/..', 'a/..',
 'a/../b', './/*/..', '..', '../a', './/.', 'a/.', 'a/./b', './/a//b', './/a/.//b', 'a//b', '//a', '/a', 'a/', '*/', './/',
 '{urn:d}a', '{urn:p}a', '{urn:p}b', '{*}a', '{*}b', '{urn:p}*', '{}a', '{}*', '{*}*', '{urn:d}*', './/{*}a', './/{urn:p}a', './/{}a', './/{urn:p}*',
 './/{*}*', '{urn:q}c', 'p:a', 'a:b', '{', '{a', '}a', '{}', '{x}',
 'a[@x]', 'a[@y]', '*[@x]', 'a[@x="1"]', "a[@x='1']", "a[@x='2']", "a[@x!='1']", "a[@x!='9']", 'a[@z]', 'b[@x]', './/*[@x]',
 "*[@id='2']", "item[@id!='2']", "*[@{urn:p}k]", "*[@k]", "*[@{urn:p}x]", "*[@k='2']", "*[@{urn:p}k='1']", "*[@p:k]", "*[@xmlns]",
 'a[b]', 'a[c]', 'a[*]', 'a[b/c]', 'a[.]', "a[b='x']", "a[b='y']", "a[b!='x']", "a[b!='z']", "a[.='t1t2']", "a[.!='t1t2']", "a[.='']",
 "item[.='two']", "item[.!='two']", "*[.='in']", "a[b='x'][b='y']", 'a[b][@x]', "a[c='t']", "a[ b = 'x' ]", "a[. = 'in']",
 'a[1]', 'a[2]', 'a[3]', 'a[last()]', 'a[last()-1]', 'a[last()-2]', 'a[last()-9]', 'a[0]', 'a[-1]', 'a[last()+1]', 'a[last()-0]',
 'a[1][1]', 'a[2][@x]', 'a[@x][1]', 'a[@x][2]', '*[1]', '*[last()]', '*[2]', 'b[1]', 'b[2]', './/a[1]', './/a[2]', './/b[1]', './/b[last()]',
 '.[1]', '.[last()]', './/*[1]', '..[1]', 'a/..[1]', 'a/b[1]', '*/b[1]', '*/b[last()]',
 'a[first()]', 'a[position()=1]', 'a[@x=1]', "a[@x='1'", "a[@x='1]", 'a[', 'a]', 'a[]', 'a[@]', 'a[@=]', "a[='1']", 'a[@x@y]',
 "a[@x=\"1\"]", 'a[1.5]', 'a[01]', 'a[+1]', 'a[ 1 ]', 'a[1 2]', 'a[b c]', 'a[b/]', 'a[../b]', 'a[b!c]',
 '', ' ', 'a b', 'a /b', 'a/ b', 'a!', '!a', 'a!b', '@x', 'a/@x', 'a::b', 'a(', 'a()', '()', '(', ')', '=', '!=', "'a'", '"a"', 'a/"b"',
 './/', '..//a', './/..', '*[@x]/b', 'a/b/c', 'a/b/c/d', 'a//d', '*//d', './/c/d', './/d/..', './/d/../..', './/d/../../..',
 '*/*/*', '*/*/*/*', './/*[@x]/..', './/*/..[@x]', 'a[1]/b', 'a[2]/b', 'a[1]/b[2]', 'a[last()]/b[last()]',
 'a/b[@x]', 'a/b[@x="1"]', 'a/b[@x!="1"]', 'a[@x="1"]/b', './/a[b]', './/a[b]/..', './/*[b]', './/*[b="x"]',
 './/a[@x="1"]', './/a[@x]', './/b[@x="2"]', 'a.b', 'a*b', '.a', 'a.', '*a', 'a*', '{urn:d}', '{urn:d}a/b', '{urn:d}a[1]', '{urn:p}*[1]', '{*}a[1]', '{*}a[2]', '{*}*[1]',
]

pathlines = []
okp = badp = 0
for pi, doc in enumerate(PDOCS):
    root = ET.fromstring(doc)
    for pa in PATHS:
        try:
            got = EP.findall(root, pa)
            want = '|'.join(e.tag for e in got)
        except Exception:
            want = None
        d = esc(doc.encode())
        if want is None:
            pathlines.append('    expect_path_bad(%d, %s, %s);' % (len(pathlines), d, esc(pa.encode())))
            badp += 1
        else:
            pathlines.append('    expect_path(%d, %s, %s, %s);' % (len(pathlines), d, esc(pa.encode()), esc(want.encode())))
            okp += 1
    # findtext
    for pa in PATHS:
        try:
            r = EP.findtext(root, pa)
        except Exception:
            continue
        d = esc(doc.encode())
        if r is None:
            pathlines.append('    expect_findtext_none(%d, %s, %s);' % (len(pathlines), d, esc(pa.encode())))
        else:
            pathlines.append('    expect_findtext(%d, %s, %s, %s);' % (len(pathlines), d, esc(pa.encode()), esc(r.encode())))
    # iter and itertext
    for tg in ['*', 'a', 'b', 'c', 'd', 'item', '{urn:p}a', '{urn:d}a', '{urn:p}b', '{urn:q}c', '{*}a', '{}a', 'r', 'zz']:
        want = '|'.join(e.tag for e in root.iter(tg))
        pathlines.append('    expect_iter(%d, %s, %s, %s);' % (len(pathlines), esc(doc.encode()), esc(tg.encode()), esc(want.encode())))
    pathlines.append('    expect_itertext(%d, %s, %s);' % (len(pathlines), esc(doc.encode()), esc(''.join(root.itertext()).encode())))
    # attributes of the root and of the first child that has attributes
    pathlines.append('    expect_attrs(%d, %s, %s, %s);' % (len(pathlines), esc(doc.encode()),
        esc('|'.join(root.keys()).encode()), esc('|'.join('%s=%s' % kv for kv in root.items()).encode())))
for doc in ['<r xmlns:p="urn:p" a="1" p:b="2"/>', '<r xmlns="urn:d" a="1&amp;2" b=""/>', '<r b="2" a="1" xmlns:q="u" q:c="3"/>', '<r/>', '<r x="a&#10;b"/>']:
    root = ET.fromstring(doc)
    pathlines.append('    expect_attrs(%d, %s, %s, %s);' % (len(pathlines), esc(doc.encode()),
        esc('|'.join(root.keys()).encode()), esc('|'.join('%s=%s' % kv for kv in root.items()).encode())))

WDOCS = PDOCS + [
 '<r a="x&quot;&lt;&#10;&#9;&gt;&amp;"><b>t&amp;&lt;&gt;</b>tail&amp;&lt;</r>',
 '<r xmlns:p="urn:p" xmlns:q="urn:q"><q:a p:x="1"/><p:b q:y="2"/></r>',
 '<r xmlns="urn:d"><a/><b xmlns="urn:e"><c/></b></r>',
 '<r xml:lang="en" xmlns:x="http://www.w3.org/2001/XMLSchema-instance" x:t="1"/>',
 '<r xmlns:a="urn:1" xmlns:b="urn:2" xmlns:c="urn:3" xmlns:d="urn:4" xmlns:e="urn:5" xmlns:f="urn:6" xmlns:g="urn:7" xmlns:h="urn:8" xmlns:i="urn:9" xmlns:j="urn:10" xmlns:k="urn:11"><a:x/><b:x/><c:x/><d:x/><e:x/><f:x/><g:x/><h:x/><i:x/><j:x/><k:x/></r>',
 '<r>\n  <a>\n    <b/>\n  </a>\n  <c> </c>\n</r>',
 '<r><a>text</a><b/><c><d/>tail</c></r>',
 '<r>\n<a/></r>',
 '<r><?pi x?><!--c--><a/></r>',
 '<r>\u00e9\u6c34<a b="\u00fc"/></r>',
]
for wi, doc in enumerate(WDOCS):
    root = ET.fromstring(doc)
    d = esc(doc.encode())
    for short in (True, False):
        want = ET.tostring(root, encoding='unicode', short_empty_elements=short)
        pathlines.append('    expect_tostring(%d, %s, %s, false, %s);' % (len(pathlines), d, 'true' if short else 'false', esc(want.encode())))
    want = ET.tostring(root, encoding='utf-8', xml_declaration=True).decode()
    pathlines.append('    expect_tostring(%d, %s, true, true, %s);' % (len(pathlines), d, esc(want.encode())))
    for space, level in (('  ', 0), ('\t', 0), ('', 0), ('  ', 2)):
        r2 = ET.fromstring(doc)
        ET.indent(r2, space=space, level=level)
        want = ET.tostring(r2, encoding='unicode')
        pathlines.append('    expect_indent(%d, %s, %s, %d, %s);' % (len(pathlines), d, esc(space.encode()), level, esc(want.encode())))

CDOCS = WDOCS + [
 '<!--pre--><?p d?><r xmlns:a="urn:a"><a:x a:k="1" b="2"/><!--c--><y>t </y></r><!--post--><?q?>',
 '<r xml:space="preserve"> a <b xml:space="default"> c </b> d </r>',
 '<r xmlns:p="urn:p" xmlns:q="urn:q" t="p:v" u="q:w"><e>p:name</e><e>plain</e><e> q:x </e><p:f q:a="1"/></r>',
 '<r xmlns="urn:d" xmlns:p="urn:p"><a p:z="1" y="2" x="3"/><b xmlns=""><c/></b></r>',
 '<r><a  >&lt;&amp;&gt;\r</a><b x="a&#9;b&#10;c&#13;d&quot;&lt;&amp;"/></r>',
 '<r>  lead <a>  in  </a>  mid  <![CDATA[ cd ]]>  </r>',
 '<?p   spaced   data ?><r/>',
 '<r xmlns:a="urn:1" xmlns:b="urn:1"><a:x/><b:x/></r>',
 '<r><a xmlns:p="urn:p"><p:b/></a><c xmlns:p="urn:q"><p:d/></c></r>',
]
def pylist(v):
    return '[' + ', '.join(esc(x.encode()) for x in v) + ']' if v else '[""]'
OPTS = [
 {}, {'with_comments': True}, {'strip_text': True}, {'rewrite_prefixes': True},
 {'with_comments': True, 'strip_text': True, 'rewrite_prefixes': True},
 {'exclude_tags': ['a']}, {'exclude_tags': ['b', '{urn:p}b']}, {'exclude_attrs': ['x', '{urn:p}z']},
 {'qname_aware_tags': ['e'], 'qname_aware_attrs': ['t', 'u']}, {'qname_aware_attrs': ['t']},
 {'qname_aware_tags': ['e'], 'rewrite_prefixes': True, 'qname_aware_attrs': ['t']},
]
for doc in CDOCS:
    for o in OPTS:
        try:
            want = ET.canonicalize(doc, **o)
            cok = True
        except Exception:
            want = ''
            cok = False
        pathlines.append('    expect_c14n(%d, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s);' % (
            len(pathlines), esc(doc.encode()),
            *['true' if o.get(k) else 'false' for k in ('with_comments', 'strip_text', 'rewrite_prefixes')],
            pylist(o.get('exclude_tags')), pylist(o.get('exclude_attrs')),
            pylist(o.get('qname_aware_tags')), pylist(o.get('qname_aware_attrs')),
            'true' if cok else 'false', esc(want.encode())))

import codecs
encl = []
def enc_case(b):
    try:
        r = merge(render_et(ET.fromstring(b)))
        encl.append('    expect_enc_ok(%d, %s, "%s");' % (len(pathlines) + len(encl), esc(b), r))
    except (ET.ParseError, LookupError, UnicodeError, ValueError):
        encl.append('    expect_enc_bad(%d, %s);' % (len(pathlines) + len(encl), esc(b)))

def high_text(codec):
    out = ''
    for b in range(0xC0, 0x100, 7):
        try:
            ch = bytes([b]).decode(codec)
            if ch.isalpha():
                out += ch
        except UnicodeDecodeError:
            pass
    return out or 'x'

PAGES = ['iso-8859-%d' % i for i in range(1, 17) if i != 12] + ['windows-125%d' % i for i in range(9)] + \
        ['koi8-r', 'koi8-u', 'cp437', 'cp850', 'cp852', 'cp855', 'cp866', 'mac-roman', 'cp874']
ALIASES = ['latin1', 'LATIN-1', 'l1', 'ISO_8859-1', 'iso8859_1', 'cp1252', '1252', 'latin-2', 'iso-ir-100', 'ascii', 'US-ASCII', 'macintosh', 'cyrillic', 'greek', 'ibm866', 'ISO-8859-1']
for name in PAGES + ALIASES:
    try:
        codec = codecs.lookup(name).name
    except LookupError:
        continue
    txt = high_text(codec) if codec != 'ascii' else 'abc'
    for body in ('<a b="%s">%s</a>' % (txt, txt), '<%s/>' % ('r' if codec != 'ascii' else 'a'), '<a>%s&#233;</a>' % txt):
        d = '<?xml version="1.0" encoding="%s"?>%s' % (name, body)
        try:
            enc_case(d.encode(codec))
        except UnicodeEncodeError:
            pass
    enc_case(('<?xml version="1.0" encoding="%s"?><a>x</a>' % name).encode('ascii') + b'')
# the high bytes that a page leaves undefined
for name in ('cp1252', 'iso-8859-3', 'cp874', 'ascii', 'cp1255'):
    for b in (0x81, 0x8d, 0xa5, 0xdb, 0xfe, 0xe9):
        enc_case(b'<?xml version="1.0" encoding="%s"?><a>' % name.encode() + bytes([b]) + b'</a>')
dec = lambda e: '<?xml version="1.0" encoding="%s"?><a b="\u00e9">\u00e9\u6c34\U0001f600</a>' % e
for e in ('UTF-16', 'utf-16', 'UTF-16LE', 'UTF-16BE', 'UTF-8', 'ISO-8859-1', 'utf-16-le', 'U16'):
    for codec in ('utf-16', 'utf-16-le', 'utf-16-be'):
        enc_case(dec(e).encode(codec))
        enc_case(('\ufeff' + dec(e)).encode(codec))
    enc_case(dec(e).encode('utf-8'))
    enc_case(('\ufeff' + dec(e)).encode('utf-8'))
for body in ('<a>\u00e9</a>', '<a/>', '<a b="\U0001f600"/>', '<a>\ud7ff\ue000\uffff</a>'):
    for codec in ('utf-16', 'utf-16-le', 'utf-16-be'):
        try:
            enc_case(body.encode(codec, 'surrogatepass'))
        except UnicodeError:
            pass
for raw in (b'\xff\xfe<\x00a\x00/\x00>', b'\xff\xfe<\x00a\x00>\x00\x00\xd8<\x00/\x00a\x00>\x00',
            b'\xff\xfe<\x00a\x00>\x00\x00\xdc<\x00/\x00a\x00>\x00', b'\xfe\xff', b'\xff\xfe', b'<\x00', b'\x00<',
            '<a/>'.encode('utf-32'), b'<?xml version="1.0" encoding="bogus"?><a/>', b'<?xml version="1.0" encoding="utf-32"?><a/>',
            b'<?xml version="1.0" encoding="UTF-16"?><a/>', b'<?xml version="1.0" encoding="utf-8"?><a>\xe9</a>',
            b'<?xml version="1.0" encoding="us-ascii"?><a>\xc3\xa9</a>', b'\xef\xbb\xbf<?xml version="1.0" encoding="bogus"?><a/>'):
    enc_case(raw)
# the bytes that encode makes
for txt in ('abc', 'caf\u00e9', '\u00e9\u6c34\U0001f600', '\u20ac', '\u0434\u0105'):
    for name in ['utf-8', 'utf-16', 'utf-16le', 'utf-16be', 'utf-32', 'utf-32le', 'utf-32be', 'ascii', 'latin-1', 'cp1252', 'iso-8859-2',
                 'koi8-r', 'cp437', 'windows-1251', 'bogus', 'UTF8', 'macintosh']:
        try:
            want = txt.encode(name, 'xmlcharrefreplace')
            eok = True
        except LookupError:
            want = b''
            eok = False
        encl.append('    expect_encode(%d, %s, %s, %s, %s);' % (len(pathlines) + len(encl), esc(txt.encode()), esc(name.encode()), 'true' if eok else 'false', esc(want)))
for doc in ['<r a="\u00e9">\u00e9\u6c34<b/></r>', '<r xmlns:p="urn:p"><p:a>\U0001f600</p:a></r>', '<r>abc</r>']:
    root = ET.fromstring(doc)
    for name in ['us-ascii', 'utf-8', 'UTF-8', 'utf-16', 'utf-16le', 'latin-1', 'iso-8859-2', 'cp1252', 'unicode_not', 'koi8-r']:
        for decl, code in ((None, 0), (True, 1), (False, 2)):
            try:
                want = ET.tostring(root, encoding=name, xml_declaration=decl)
                eok = True
            except LookupError:
                want = b''
                eok = False
            encl.append('    expect_tostring_enc(%d, %s, %s, %d, %s, %s);' % (len(pathlines) + len(encl), esc(doc.encode()), esc(name.encode()), code, 'true' if eok else 'false', esc(want)))

import io
EDOCS = CDOCS + [
 '<r xmlns="urn:d" xmlns:p="urn:p"><p:a p:k="1" k="2"/><b xmlns=""/></r>',
 '<r><a>x<!--c-->y<?pi data?>z</a><![CDATA[<cd>]]></r>',
 '<p:r xmlns:p="urn:p" xmlns:q="urn:q"/>',
 '<r xml:lang="en"><a xml:space="preserve"/></r>',
 '<r><a/><a/><a>t</a></r>',
]
def hx(t):
    return t.encode().hex()
for doc in EDOCS:
    if re.search(r'^\s*(<!--|<\?(?!xml))', doc) or re.search(r'-->\s*(<\?[a-z]+[^>]*\?>)?\s*$', doc) or re.search(r'\?>\s*$', doc) and not doc.endswith('</r>'):
        continue
    try:
        evs = []
        it = ET.iterparse(io.BytesIO(doc.encode()), events=('start', 'end', 'start-ns', 'end-ns', 'comment', 'pi'))
        for ev, el in it:
            if ev == 'start':
                evs.append('S ' + hx(el.tag))
                for k, v in el.attrib.items():
                    evs.append('A %s %s' % (hx(k), hx(v)))
            elif ev == 'end':
                evs.append('E ' + hx(el.tag))
            elif ev == 'start-ns':
                evs.append('N %s %s' % (hx(el[0]), hx(el[1])))
            elif ev == 'end-ns':
                evs.append('n ' + hx(''))
            elif ev == 'comment':
                evs.append('C ' + hx(el.text))
            elif ev == 'pi':
                evs.append('P %s %s' % (hx(el.target), hx(el.text or '')))
        tree = merge(render_et(ET.fromstring(doc.encode())))
    except Exception:
        continue
    pathlines.append('    expect_events(%d, %s, %s, "%s");' % (len(pathlines), esc(doc.encode()), esc(' '.join(evs).encode()), tree))
NSDOCS = [
 '<r xmlns="urn:d" xmlns:p="urn:p"><a/><p:a p:k="1" k="2"><a/></p:a><b/></r>',
 '<r xmlns:p="urn:p"><p:a/><a/><x><p:a/></x></r>',
]
NSMAPS = [{}, {'p': 'urn:p'}, {'': 'urn:d'}, {'': 'urn:d', 'p': 'urn:p'}, {'q': 'urn:p'}, {'p': 'urn:p', 'd': 'urn:d'}]
NSPATHS = ['a', 'p:a', 'q:a', 'd:a', 'p:a/a', './/p:a', './/a', '*/p:a', 'p:*', '{urn:p}a', 'p:a[@p:k]', 'p:a[@k]', 'p:a[@p:k="1"]',
           'a[@k]', 'p:a/..', 'p:a[1]', 'p:a[last()]', 'a[p:a]', 'a[d:a]', ':a', 'p:', 'x:y:z']
for doc in NSDOCS:
    root = ET.fromstring(doc)
    for m in NSMAPS:
        for pa in NSPATHS:
            try:
                got = EP.findall(root, pa, m or None)
                want = '|'.join(e.tag for e in got)
                good = True
            except Exception:
                want = ''
                good = False
            pathlines.append('    expect_path_ns(%d, %s, %s, %s, %s, %s, %s);' % (len(pathlines), esc(doc.encode()), esc(pa.encode()),
                pylist(list(m.keys())) if m else '[""]', pylist(list(m.values())) if m else '[""]', 'true' if good else 'false', esc(want.encode())))
HDOCS = WDOCS + [
 '<html><head><meta charset="u"/><style>a>b{}&amp;</style><script>if(a&lt;b&amp;&amp;c){}</script></head><body><br/><p class="x&amp;&gt;&quot;">t<img src="i"/>u</p><INPUT/><Hr></Hr></body></html>',
 '<r xmlns="urn:d" xmlns:p="urn:p"><a p:x="1" y="2"/><p:b/></r>',
 '<r xmlns:p="urn:p"><p:a p:x="1"/></r>',
 '<r>a<b>c</b>d<e/>f</r>',
]
for hi, doc in enumerate(HDOCS):
    root = ET.fromstring(doc)
    d = esc(doc.encode())
    for method in ('html', 'text'):
        for dflt in (None, 'urn:d', 'urn:p'):
            if method == 'text' and dflt: continue
            for short in (True, False):
                try:
                    want = ET.tostring(root, encoding='unicode', method=method, default_namespace=dflt, short_empty_elements=short)
                    okw = 'true'
                except ValueError:
                    want = ''; okw = 'false'
                pathlines.append('    expect_tostring_m(%d, %s, %d, %s, %s, %s, %s);' % (len(pathlines), d, 1 if method == 'html' else 2, esc((dflt or '').encode()), 'true' if short else 'false', okw, esc(want.encode())))
    for dflt in ('urn:d', 'urn:p', 'urn:zzz'):
        try:
            want = ET.tostring(root, encoding='unicode', default_namespace=dflt); okw = 'true'
        except ValueError:
            want = ''; okw = 'false'
        pathlines.append('    expect_tostring_m(%d, %s, 0, %s, true, %s, %s);' % (len(pathlines), d, esc(dflt.encode()), okw, esc(want.encode())))
pathlines.extend(encl)
sys.stderr.write('%d path cases, ok %d, bad %d\n' % (len(pathlines), okp, badp))

out = []
out.append('// Cases made by test/make_xml_cases.py with xml.etree.ElementTree, seed 20261107.')
out.append('// Do not edit by hand. Make the file again with the script.')
out.append('// Count: %d cases (ok %d, bad %d), %d left out as stated limits.' % (ok + bad, ok, bad, skipped))
out.append('')
out.append(open(__file__.replace('make_xml_cases.py', 'xml_cases_head.txt')).read())
out.append('fn check_xml_cases() {')
out.extend(lines)
out.append('}')
out.append('')
out.append('fn check_path_cases() {')
out.extend(pathlines)
out.append('}')
sys.stdout.write('\n'.join(out) + '\n')
sys.stderr.write('%d cases, ok %d, bad %d, left out %d\n' % (ok + bad, ok, bad, skipped))
