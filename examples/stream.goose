// An example for the xml package: namespaces and the pull reader.
//
// It resolves a namespaced name in the tree, then streams the events of
// the same text with no tree.
//
// Run with: goose run examples/stream.goose
import std;
import xml from "..";

fn main() {
    let text = "<f:feed xmlns:f=\"urn:feed\"><f:item>a&#38;b</f:item></f:feed>";
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse(text, nodes, attrs);
    assert(ok);
    let item, found = xml::find(doc, doc.nodes[doc.root], "{urn:feed}item");
    assert(found);
    print("uri: ", item.uri, " local: ", item.local);

    var r = xml::reader(text);
    var open: xml::Open[>..] = [];
    var pattrs: xml::Attr[>..] = [];
    while true {
        let ev, more = xml::next(r, open, pattrs);
        assert(more);
        if ev.kind == xml::EV_EOF { break; }
        if ev.kind == xml::EV_START { print("start ", ev.name); }
        if ev.kind == xml::EV_TEXT {
            var t: u8[>..] = [];
            assert(xml::decode_entities(t, ev.content));
            print("text ", t);
        }
    }
    return 0;
}
