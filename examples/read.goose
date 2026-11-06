// An example for the xml package.
//
// It parses a feed-like document, walks the entries, and prints one
// attribute and the text of each entry title.
//
// Run with: goose run examples/read.goose
import std;
import xml from "..";

fn main() {
    let doc_text = "<?xml version=\"1.0\"?><feed><entry><title>First</title><link href=\"/a\"/></entry><entry><title>Second</title><link href=\"/b\"/></entry></feed>";
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse(doc_text, nodes, attrs);
    assert(ok);

    let root = doc.nodes[doc.root];
    var at: i32 = 0;
    while true {
        let entry, found = xml::child_at(doc, root, at);
        if !found { break; }
        let title, tfound = xml::child_at(doc, entry, 0);
        if tfound && title.name == "title" {
            var text: u8[>..] = [];
            xml::text_of(text, doc, title);
            print("title: ", text);
        }
        let link, lfound = xml::child_at(doc, entry, 1);
        if lfound {
            let href, hfound = xml::attr_lookup(doc, link, "href");
            if hfound { print("  href: ", href); }
        }
        at += 1;
    }
    return 0;
}
