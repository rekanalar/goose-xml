// An example for the xml package: build a tree and write it.
//
// It builds a small tree, indents it, writes it as text and as the
// canonical form of the written text, and reads the events of the text.
//
// Run with: goose run examples/build_tree.goose
import std;
import xml from "..";

fn main() {
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    var text: u8[>..] = [];
    let root = xml::element(nodes, text, "{urn:shop}order");
    xml::set(nodes, attrs, text, root, "id", "7");
    let item = xml::sub_element(nodes, text, root, "{urn:shop}item");
    xml::set_text(nodes, text, item, "Goose & duck");
    xml::set(nodes, attrs, text, item, "qty", "2");
    xml::sub_element(nodes, text, root, "{urn:shop}note");
    xml::indent(nodes, attrs, text, root, "  ", 0);

    let doc = xml::make_doc(nodes, attrs, root);
    var out: u8[>..] = [];
    assert(xml::tostring(out, doc, root, xml::write_opts()));
    print(out[..]);

    // The canonical form reads the declarations of a parsed document.
    var pn: xml::Node[>..] = [];
    var pa: xml::Attr[>..] = [];
    let parsed, pok = xml::parse(out[..], pn, pa);
    assert(pok);
    var canon: u8[>..] = [];
    let none: const u8[:][] = [""];
    assert(xml::canonicalize(canon, parsed, xml::c14n_opts(), none, none, none, none));
    print(canon[..]);

    // The events of the written text.
    var n2: xml::Node[>..] = [];
    var a2: xml::Attr[>..] = [];
    var t2: u8[>..] = [];
    let d2, ok = xml::iterparse(out[..], false, n2, a2, t2) { kind, id, a, b =>
        if kind == xml::TEV_START { print("start ", a); }
    };
    assert(ok);
}
