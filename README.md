# goose-xml

[![ci](https://github.com/rekanalar/goose-xml/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-xml/actions/workflows/ci.yml)

XML parsing and building for the [Goose](https://github.com/aardappel/goose) programming language. The rules
are the XML 1.0 well-formedness core.

The package parses a document into a tree and gives a walk API over the
tree. It builds XML text back from the tree.

A pull reader gives events
and builds no tree. The parser checks well-formedness as Python
`ElementTree` does, and the tests compare the two. Comments, CDATA, processing instructions, the five
predefined entities and numeric character references are in. Element and
attribute names resolve into a namespace URI and a local name. DTDs and
validation are out. Pure Goose, no C.

## Install

Add this to the root file of the program that uses it:

```goose
import xml from "rekanalar/goose-xml@v0.3.0";
```

## API

| Function | What it does |
|---|---|
| `parse(s, nodes, attrs)` | parses one document into the arrays of the caller; gives `Doc, bool` |
| `build(out, doc, root_id)` | writes the subtree as XML text |
| `attr_lookup(doc, node, key)` | gives the attribute value; gives `value, bool` |
| `child_at(doc, node, at)` | gives one child in document order; gives `Node&, bool` |
| `children_count(doc, node)` | gives the number of the direct children |
| `text_of(out, doc, node)` | writes the joined text and CDATA of the direct children, entities decoded |
| `attr_value(out, doc, node, key)` | writes the decoded, normalized attribute value; gives `bool` |
| `decode_entities(out, s)` | decodes the five entities and the numeric references; a literal CR or CRLF gives LF |
| `decode_attr(out, s)` | the same, and each literal tab, LF and CR gives one space |
| `find(doc, node, tag)` | gives the first direct child element with the tag |
| `findall(doc, node, tag, out)` | writes the places of the matching direct children |
| `findall_deep(doc, node, tag, out)` | writes the places of the matching descendants |
| `attr_lookup_ns(doc, node, uri, local)` | gives an attribute by its resolved name |
| `reader(s)`, `next(r, open, attrs)` | pull reader: one event per call, no tree |
| `ns_split(name)` | cuts a raw name into prefix and local name |

`attr_lookup` gives the raw span of the value, with the entities as written.
Use `attr_value` for the value that `ElementTree.get` gives.
Each `Node` and `Attr` has `uri` and `local` fields. The tag of `find`
is a local name for an element with no namespace, or `{uri}local`, as in
Python `ElementTree`. The writer keeps the prefixes and the `xmlns`
attributes as they are, so a namespaced document round trips.

The nodes and the attributes hold spans over the input text, so the
input text must outlive the arrays. The parse holds no recursion and
takes linear time; the depth limit is 256. An unknown entity, a
duplicate attribute and a mismatched tag are parse faults.

```goose
var nodes: xml::Node[>..] = [];
var attrs: xml::Attr[>..] = [];
let doc, ok = xml::parse("<a x=\"1\">hi</a>", nodes, attrs);
if ok {
    let v, found = xml::attr_lookup(doc, doc.nodes[doc.root], "x");
    print(v);  // 1
}
```

## Changes in v0.3.0

The parser now follows `ElementTree` on well-formedness. These inputs
gave a tree before and give a fault now:

- a control byte other than tab, LF and CR, invalid UTF-8, U+FFFE and U+FFFF
- `]]>` in text, `--` in a comment, a comment that ends in `--->`
- `<![cdata[` and other `<!` markup that is not a comment, CDATA or DOCTYPE
- two attributes with no space between them
- an XML declaration that is late, has no version, or names an encoding other than UTF-8 or US-ASCII
- the target `xml` in any case in a PI after the declaration, and a colon in a PI target
- a DOCTYPE inside the root, a second DOCTYPE, and a DOCTYPE with a bad name or identifier
- `&#X41;` with a capital X
- `xmlns:p=""`, `xmlns:xml` with another URI, `xmlns:xmlns`, a binding to the `xmlns` URI
- a name with two colons or an empty part, and two attributes with one expanded name

These inputs gave a fault before and give a tree now:

- `<a><?p?></a>`, which aborted the program
- non-ASCII names such as `<é/>`, and a leading byte order mark
- a comment or PI after the root; the tree drops it

These results changed:

- `text_of` includes CDATA. A literal CR or CRLF in text gives LF.
- `build` writes CR in text, and tab, LF and CR in attributes, as character references. The output parses back to the same tree.
- A document of 100000 siblings parsed in 41 s before. It parses in under 0.1 s.

## Limits

- The pull reader does not resolve namespaces. It gives raw names.
  It checks characters, names and attributes as the parser does.
  It keeps the older rules for the prolog, DOCTYPE, comments and PIs.
  It refuses a comment or PI after the root.
- `find` and `findall` match direct children by tag. There is no path
  language and no XPath. `findall_deep` matches all descendants.
- A prefix with no declaration is a parse fault. Python `ElementTree`
  also faults.
- The writer makes no new prefixes. Write each prefix with its `xmlns`
  attribute.
- A DOCTYPE is skipped. Entities that a DTD declares are a fault, and
  attribute defaults from an `ATTLIST` do not apply. The declarations in an
  internal subset are not checked beyond their keyword and quotes.
- The input is UTF-8 only. A declared encoding other than UTF-8 or
  US-ASCII is a fault. `ElementTree` decodes other encodings.
- Names follow the fifth edition of XML 1.0. Python expat follows the fourth edition, so the two differ on some code points. Astral names are one case.
- The depth limit is 256. `ElementTree` accepts deeper documents.
- The duplicate attribute check takes time in proportion to the square of the attributes of one element.
  The namespace lookup walks the declarations in scope.
  5000 attributes take 0.1 s.
- There is no tree builder, `iter`, `itertext`, `findtext`, `indent`,
  `tostring` or `canonicalize`. The gaps are in `packages/PROPOSAL.md`.

## Test

```bash
goose run test/run.goose
goose run examples/read.goose
goose run examples/stream.goose
goose run examples/untrusted.goose
```

The suite holds the hand cases and the hostile cases. Each hostile case has a time bound of one second.
It also holds 1470 cases from `test/make_xml_cases.py`.
The script uses `ElementTree` with seed 20261107.
There are 690 valid documents and 780 faults. 30 documents are left out as limits.

## License

MIT
