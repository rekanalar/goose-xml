# goose-xml

[![ci](https://github.com/rekanalar/goose-xml/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-xml/actions/workflows/ci.yml)

XML for the [Goose](https://github.com/aardappel/goose) programming language. The package covers the
API of `xml.etree.ElementTree` of Python 3.14. It reads, searches, builds, writes and canonicalizes.

The parser checks well-formedness as Python `ElementTree` does. The tests compare the two.
Comments, CDATA, processing instructions, the five predefined entities and numeric character
references are in. Names resolve into a namespace URI and a local name. DTDs and validation are out.
Pure Goose, no C.

## Install

Add this to the root file of the program that uses it:

```goose
import xml from "rekanalar/goose-xml@v1.0.0";
```

## API

Read and walk:

| Function | What it does |
|---|---|
| `parse(s, nodes, attrs)` | parses one UTF-8 document into the arrays of the caller; gives `Doc, bool` |
| `parse_bytes(data, buf, nodes, attrs)` | the same for a document in any supported encoding |
| `decode(buf, input)` | turns bytes in a supported encoding into UTF-8; gives `text, bool` |
| `reader(s)`, `next(r, open, attrs)` | pull reader: one event per call, no tree |
| `iterparse(s, build, nodes, attrs, text) { kind, id, a, b => ... }` | calls the block for each event: start, end, attribute, namespace, comment, PI |
| `child_at`, `children_count`, `find`, `findall`, `findall_deep` | direct access to children by tag |
| `elem_text`, `elem_tail`, `iter_text` | the text, the tail and `itertext` |
| `iter(doc, id, name, out)` | the descendants with the name; `*` gives all |
| `get(out, doc, id, key, default)`, `keys`, `items` | attributes as `Element.get`, `keys` and `items`; keys are `{uri}local` |
| `attr_lookup`, `attr_value`, `attr_lookup_ns` | the raw and the decoded attribute value |
| `decode_entities`, `decode_attr` | entity and white space rules of text and attributes |

Search with the path language of `ElementPath`:

| Function | What it does |
|---|---|
| `find_path(doc, id, path)` | gives the first match; gives `id, bool` |
| `findall_path(doc, id, path, out)` | writes all matches, as `findall` and `iterfind`; gives the count, or -1 for a bad path |
| `findtext(out, doc, id, path, default)` | the text of the first match |
| `find_path_ns`, `findall_path_ns`, `findtext_ns` | the same with a map of prefixes and URIs |

The path language holds these words:

- Steps: `tag`, `*`, `.`, `..`, `//`, `{uri}tag`, `{*}tag`, `{uri}*`
- Tests on attributes: `[@a]`, `[@a='v']`, `[@a!='v']`
- Tests on children: `[tag]`, `[tag='v']`, `[.='v']`
- Positions: `[n]`, `[last()]`, `[last()-n]`

Build and write:

| Function | What it does |
|---|---|
| `element`, `sub_element`, `append`, `insert`, `remove`, `clear` | build a tree in arrays that the caller owns; `element` and `sub_element` give -1 for a tag that is not an XML Name |
| `set`, `set_text`, `set_tail`, `make_doc` | set attributes and text; make a `Doc` over the arrays; `set` gives false for a key that is not an XML Name |
| `tostring(out, doc, id, opts)` | writes XML text as `ET.tostring`; `WriteOpts` holds `xml_declaration`, `short_empty_elements`, `method` and `default_namespace` |
| `tostring_encoded(out, doc, id, opts, encoding)` | writes bytes in an encoding |
| `write(path, doc, id, opts)` | writes to a file |
| `indent(nodes, attrs, text, id, space, level)` | the pretty print of `ET.indent` |
| `canonicalize(out, doc, opts, ...)` | C14N 2.0 as `ET.canonicalize` |
| `encode(out, text, encoding)` | turns UTF-8 text into bytes; an unmappable character becomes a reference |
| `build(out, doc, id)` | writes the subtree with the prefixes as parsed |

The builder copies every name and text into a buffer of the caller. `method` is `METHOD_XML`,
`METHOD_HTML` or `METHOD_TEXT`. Prefixes follow `ElementTree`: well-known ones for well-known URIs,
`ns0`, `ns1` and so on for others. The encodings are UTF-8, UTF-16, UTF-32 and 34 single-byte pages
with 174 names.

The nodes and the attributes hold spans over the input text, so the input text must outlive the
arrays. The parse holds no recursion and takes linear time; the depth limit is 256. An unknown
entity, a duplicate attribute and a mismatched tag are parse faults.

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

- The path language is `ElementPath`. There is no XPath. `lxml` has XPath 1.0.
- A path with a prefix needs a map of prefixes. Without a map, a prefix is refused.
  The C accelerator of Python reads some such paths in other ways, and the pure `ElementPath` is the oracle.
- `[n]` and `[last()]` take time in proportion to the square of the siblings on wide documents, as in Python.
- The pull reader does not resolve namespaces. `iterparse` does. The reader keeps the older rules for
  the prolog, DOCTYPE, comments and PIs. It refuses a comment or PI after the root. `iterparse` gives no
  events for comments and PIs in the prolog.
- A DOCTYPE is skipped. Entities that a DTD declares are a fault. Attribute defaults from an `ATTLIST`
  do not apply.
- Encodings: UTF-8, UTF-16, UTF-32 and the single-byte pages of the table in `encoding_data.goose`.
  Multi-byte East Asian encodings (`gbk`, `shift_jis`, `euc-jp`, `big5`) are out. Expat itself
  reads only four encodings without help, and Python adds the rest through its codecs.
- Text mode `tostring` with a declaration writes `utf-8`. Python writes the name of the locale.
- `ET.register_namespace` is a global table in Python. `lxml` takes a map per element, and Go writes
  explicit `xmlns` attributes. The writer takes `default_namespace` and nothing else. Use `set` with an
  `xmlns` key in the tree, or the well-known prefixes.
- The writer writes no comments and no processing instructions inside the tree, as the tree of
  `ElementTree` holds none. `canonicalize` writes them when the tree holds them.
- `indent` and `strip_text` treat ASCII white space only.
- No `XMLPullParser` with an incremental `feed`. Pass the whole text to `iterparse`.
- A built tree has no depth limit, and the writer recurses with the depth.
- Names follow the fifth edition of XML 1.0. Python expat follows the fourth edition, so the two differ
  on some code points. Astral names are one case.
- The duplicate attribute check takes time in proportion to the square of the attributes of one element.
  5000 attributes take 0.1 s.
- Python gives an error for an empty `QName` in `qname_aware_tags`. This package does not replicate it.
- Name check. Before this change the builder wrote any tag and any attribute name that was not empty. Now `element` and `sub_element` give -1, and `set` gives false, when the local name is not an XML Name. The rule is the XML Name rule of the parser, not the rule of a namespace name. A colon is valid, as in the parser. A prefix needs an `xmlns:p` declaration, or the parser refuses the written text.

## Security

A tag or an attribute name that comes from a stranger can add markup. The writer copies a name as it is. The tag `a><evil/` wrote `<a><evil/ />`. The key `x="1" onload="y` wrote a forged attribute.

Python `ElementTree` 3.14.4 and Go 1.27.2 `encoding/xml` write the same output for such names. `lxml` 6.1.3.0 raises `ValueError`. Node `xmlbuilder` 15.1.1 throws an error. The author ran each of them. This package refuses the name, as `lxml` and `xmlbuilder` do.

Protections beyond `ElementTree`:

- `element`, `sub_element` and `set` check the local name with `name_ok`. It uses the name reader of the parser. A bad name gives -1 or false. The call adds no node, no attribute and no text.
- The part `{uri}` of a name is free text. The writer escapes it as an attribute value.

Text, attribute values and namespace URIs were escaped before this change. The builder has no call that makes a comment, a CDATA section or a processing instruction. A parsed tree drops comments and PIs and turns CDATA into text. So the writer has no path that copies their text.

Risks that stay:

- A caller who fills a `Node` or an `Attr` by hand skips the check. Use `element`, `sub_element` and `set`.
- A caller must not use the result -1 of `element` as a node id.
- A name with an undeclared prefix passes the check. The parser then refuses the written text.
- The writer recurses with the depth of the tree. A tree from a stranger needs a depth limit of its own.

## Test

```bash
goose run test/run.goose
goose run examples/read.goose
goose run examples/search.goose
goose run examples/build_tree.goose
goose run examples/stream.goose
goose run examples/untrusted.goose
```

The suite holds the hand cases and the hostile cases. Each hostile case has a time bound of one second.
`test/make_xml_cases.py` makes the generated cases with `ElementTree` of Python 3.14 and seed 20261107.
It holds 1470 parser cases, and path, `iter`, `findtext`, `tostring`, `indent`, `canonicalize`, encoding
and `iterparse` cases. `test/make_encoding_data.py` makes the tables of the encodings.

## License

MIT
