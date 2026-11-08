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
import xml from "rekanalar/goose-xml@v2.0.0";
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
- The version of the XML declaration. This package accepts any version, as `ElementTree` does. `lxml` accepts a version of the form 1.N and refuses any other. Go `encoding/xml` refuses any version but 1.0. `quick-xml` and `fast-xml-parser` accept any version.
- A duplicate attribute. This package refuses it, as `ElementTree` and `lxml` do. `quick-xml` refuses the second one. Go `encoding/xml` keeps both attributes. `fast-xml-parser` keeps the last one.
- An unbound prefix in an element name. This package refuses it, as `ElementTree` and `lxml` do. Go `encoding/xml` accepts it and puts the prefix in the namespace. `quick-xml` and `fast-xml-parser` accept it and keep the prefix in the name.
- An unbound prefix in an attribute name. This package refuses it, as `ElementTree` and `lxml` do. Go `encoding/xml`, `quick-xml` and `fast-xml-parser` accept it and keep the prefix in the name.
- The `xmlns` declaration. This package keeps it as an attribute, as Go `encoding/xml` and `quick-xml` do. `ElementTree` and `lxml` move it into the namespace map. `lxml` keeps the declaration in the text it writes back. `fast-xml-parser` keeps it as an attribute when the attributes are on, and ignores it in the default settings.
- The text of an element after a comment or a processing instruction. This package keeps the text, as `ElementTree` does. Go `encoding/xml`, `quick-xml` and `fast-xml-parser` keep it. `lxml` stops the text at the comment, because it keeps the comment as a child.
- A tab or a newline in an attribute value. This package turns it into a space, as `ElementTree` and `lxml` do. Go `encoding/xml` and `quick-xml` keep it. `fast-xml-parser` keeps it inside the value and trims the spaces at the ends.
- A name with U+00B7 as its first character. This package refuses it, as `ElementTree`, `lxml` and Go `encoding/xml` do. `quick-xml` and `fast-xml-parser` accept it.
- A picture deeper than 256 levels. This package refuses it, as `lxml` does. `lxml` refuses it at 257 levels. `ElementTree`, Go `encoding/xml` and `quick-xml` accept any depth. `fast-xml-parser` refuses it for its own reasons.
- The entities of an internal subset. This package refuses the document, as Go `encoding/xml` does. `ElementTree`, `lxml` and `fast-xml-parser` expand the entities. `quick-xml` leaves them.
- An unknown entity. This package refuses the document, as `ElementTree`, `lxml` and Go `encoding/xml` do. `quick-xml` gives the entity as its own event. `fast-xml-parser` leaves it as text.
- A document that is not well formed. This package refuses it, as `ElementTree`, `lxml`, Go `encoding/xml` and `quick-xml` do. `fast-xml-parser` accepts it.
- Name check. Before this change the builder wrote any tag and any attribute name that was not empty. Now `element` and `sub_element` give -1, and `set` gives false, when the local name is not an XML Name. The rule is the XML Name rule of the parser, not the rule of a namespace name. A colon is valid, as in the parser. A prefix needs an `xmlns:p` declaration, or the parser refuses the written text.

## Security

A tag or an attribute name that comes from a stranger can add markup. The writer copies a name as it is. The tag `a><evil/` wrote `<a><evil/ />`. The key `x="1" onload="y` wrote a forged attribute.

Python `ElementTree` 3.14.4 and Go 1.27.2 `encoding/xml` write the same output for such names. `lxml` 6.1.3.0 raises `ValueError`. Node `xmlbuilder` 15.1.1 throws an error. The author ran each of them. This package refuses the name, as `lxml` and `xmlbuilder` do.

Protections beyond `ElementTree`:

- `element`, `sub_element` and `set` check the local name with `name_ok`. It uses the name reader of the parser. A bad name gives -1 or false. The call adds no node, no attribute and no text.
- The part `{uri}` of a name is free text. The writer escapes it as an attribute value.

Text, attribute values and namespace URIs were escaped before this change. The builder has no call that makes a comment, a CDATA section or a processing instruction. A parsed tree drops comments and PIs and turns CDATA into text. So the writer has no path that copies their text.

The audit of the four other libraries added these protections.

- The package refuses a document with an internal subset. No entity of a document expands. `ElementTree`, `lxml` and `fast-xml-parser` expand the entities of a subset. A document with many entities takes the memory of those three libraries. It never reaches this package.
- The package refuses a document that is not well formed. `fast-xml-parser` accepts such a document. A program that trusts the structure of a tree gets a tree it cannot trust from that library.
- The package refuses a picture deeper than 256 levels. `ElementTree`, Go `encoding/xml` and `quick-xml` have no depth limit, so a small document can make a deep tree.

Risks that stay:

- The package accepts a document that declares another version of XML, as `ElementTree` does. `lxml` refuses a version that is not of the form 1.N. A program that needs one version must check the declaration itself.
- A caller who fills a `Node` or an `Attr` by hand skips the check. Use `element`, `sub_element` and `set`.
- A caller must not use the result -1 of `element` as a node id.
- A name with an undeclared prefix passes the check. The parser then refuses the written text.
- The writer recurses with the depth of the tree. A tree from a stranger needs a depth limit of its own.

## What the audit did not reach

The audit ran the four libraries on the corpus of the package. That corpus holds 1500 inputs. It comes from the generator of the package.

- The audit did not run the writers of `quick-xml` and `fast-xml-parser`. It compared the parse and the tree only.
- The audit did not run the XPath of `lxml`. The package has no XPath either.
- The corpus holds no document in an encoding other than UTF-8. The only exceptions are the documents with a declared encoding, which the package leaves out.
- The corpus holds no document with an external DTD.
- The audit did not compare the writer of the package with the writers of the four libraries. The writer follows `ElementTree`, and that is the oracle.
- The audit did not fuzz the four libraries. It ran the corpus once.
- The versions are the ones of the machine: `lxml` 6.1.3, `quick-xml` 0.42.0, `fast-xml-parser` 5.12.0 and Go 1.27.2.
- The audit names four reference libraries. It does not cover Java or the C++ expat.

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
