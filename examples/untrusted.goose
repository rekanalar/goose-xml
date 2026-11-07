// An example for the xml package.
//
// It parses text from an untrusted source. A hostile document gives a
// refusal. A document with a non-ASCII name and an attribute with
// entities gives a tree, and the decoded value shows the normalization.
//
// Run with: goose run examples/untrusted.goose
import std;
import xml from "..";

fn show(text: const u8[:]) {
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse(text, nodes, attrs);
    if !ok {
        print("refused");
        return;
    }
    let root = doc.nodes[doc.root];
    var v: u8[>..] = [];
    xml::attr_value(v, doc, root, "note");
    print(root.name, " note=[", v[..], "]");
}

fn main() {
    // A control byte, invalid UTF-8 and a PI with no data are all safe.
    show("<a>\x01</a>");
    show("<a>\xff</a>");
    show("<a><?p?></a>");
    show("<caf\xc3\xa9 note=\"a&amp;b\tc\"/>");
}
