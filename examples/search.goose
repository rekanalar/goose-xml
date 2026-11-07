// An example for the xml package: the path language of ElementTree.
//
// It finds elements with a path, reads a text with findtext and reads
// the attributes of an element.
//
// Run with: goose run examples/search.goose
import std;
import xml from "..";

fn main() {
    let text = "<lib><book id=\"1\" lang=\"en\"><t>Goose</t></book><book id=\"2\"><t>Ducks</t></book></lib>";
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse(text, nodes, attrs);
    assert(ok);

    // Every title, at any depth.
    var found: i32[>..] = [];
    xml::findall_path(doc, doc.root, ".//t", found);
    for id in found {
        var t: u8[>..] = [];
        xml::elem_text(t, doc, id);
        print("title: ", t[..]);
    }

    // The second book, and the book with an attribute value.
    let second, has2 = xml::find_path(doc, doc.root, "book[2]");
    assert(has2);
    let by_id, has_id = xml::find_path(doc, doc.root, "book[@id='1']");
    assert(has_id);
    print("second is book ", second, ", id 1 is book ", by_id);

    // findtext gives the text of the first match.
    var out: u8[>..] = [];
    xml::findtext(out, doc, doc.root, "book[@lang]/t", "none");
    print("english title: ", out[..]);

    // The attributes of an element, with a default for an absent one.
    var lang: u8[>..] = [];
    xml::get(lang, doc, second, "lang", "unknown");
    print("lang of book 2: ", lang[..]);
}
