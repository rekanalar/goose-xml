# goose-xml

[![ci](https://github.com/rekanalar/goose-xml/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-xml/actions/workflows/ci.yml)

XML parsing and building for the [Goose](https://github.com/aardappel/goose) programming language. The rules
are the XML 1.0 well-formedness core.

The package parses a document into a tree and gives a walk API over the
tree. It builds XML text back from the tree. Comments, CDATA, processing
instructions and the five predefined entities are in. Namespaces, DTDs
and validation are out. Pure Goose, no C.

## Install

Add this to the root file of the program that uses it:

```goose
import xml from "rekanalar/goose-xml@v0.1.1";
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
| `decode_entities(out, s)` | decodes the five predefined entities |

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

## Test

```bash
goose run test/run.goose
goose run examples/read.goose
```

## License

MIT
