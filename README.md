# goose-xml

[![ci](https://github.com/rekanalar/goose-xml/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-xml/actions/workflows/ci.yml)

XML parsing and building for the [Goose](https://github.com/aardappel/goose) programming language. The rules
are the XML 1.0 well-formedness core.

The package parses a document into a tree and gives a walk API over the
tree. It builds XML text back from the tree. 

A pull reader gives events
and builds no tree. Comments, CDATA, processing instructions, the five
predefined entities and numeric character references are in. Element and
attribute names resolve into a namespace URI and a local name. DTDs and
validation are out. Pure Goose, no C.

## Install

Add this to the root file of the program that uses it:

```goose
import xml from "rekanalar/goose-xml@v0.2.0";
```

## API

| Function | What it does |
|---|---|
| `parse(s, nodes, attrs)` | parses one document into the arrays of the caller; gives `Doc, bool` |
| `build(out, doc, root_id)` | writes the subtree as XML text |
| `attr_lookup(doc, node, key)` | gives the attribute value; gives `value, bool` |
| `child_at(doc, node, at)` | gives one child in document order; gives `Node&, bool` |
| `children_count(doc, node)` | gives the number of the direct children |
| `text_of(out, doc, node)` | writes the joined text of the direct text children |
| `decode_entities(out, s)` | decodes the five entities and the numeric references |
| `find(doc, node, tag)` | gives the first direct child element with the tag |
| `findall(doc, node, tag, out)` | writes the places of the matching direct children |
| `findall_deep(doc, node, tag, out)` | writes the places of the matching descendants |
| `attr_lookup_ns(doc, node, uri, local)` | gives an attribute by its resolved name |
| `reader(s)`, `next(r, open, attrs)` | pull reader: one event per call, no tree |
| `ns_split(name)` | cuts a raw name into prefix and local name |

Each `Node` and `Attr` has `uri` and `local` fields. The tag of `find`
is a local name for an element with no namespace, or `{uri}local`, as in
Python `ElementTree`. The writer keeps the prefixes and the `xmlns`
attributes as they are, so a namespaced document round trips.

The nodes and the attributes hold spans over the input text, so the
input text must outlive the arrays. The parse holds no recursion; the
depth limit is 256. An unknown entity, a duplicate attribute and a
mismatched tag are parse faults.

```goose
var nodes: xml::Node[>..] = [];
var attrs: xml::Attr[>..] = [];
let doc, ok = xml::parse("<a x=\"1\">hi</a>", nodes, attrs);
if ok {
    let v, found = xml::attr_lookup(doc, doc.nodes[doc.root], "x");
    print(v);  // 1
}
```

## Limits

- The pull reader does not resolve namespaces. It gives raw names.
- `find` and `findall` match direct children by tag. There is no path
  language and no XPath. `findall_deep` matches all descendants.
- A prefix with no declaration is a parse fault. Python `ElementTree`
  also faults.
- The writer makes no new prefixes. Write each prefix with its `xmlns`
  attribute.
- A DOCTYPE is skipped. Entities that a DTD declares are a fault.
- A comment or PI before or after the root is dropped by the tree.
- The input is not checked for valid UTF-8.

## Test

```bash
goose run test/run.goose
goose run examples/read.goose
goose run examples/stream.goose
```

## License

MIT
