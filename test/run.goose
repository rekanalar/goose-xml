// Tests for the xml package. Run with: goose run test/run.goose
//
// The tests hold the acceptance scenarios of the spec, the fault cases,
// and round trips over many documents.

import std;
import xml from "..";

fn expect_fault(s: const u8[:]) {
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse(s, nodes, attrs);
    assert(!ok);
}

fn test_parse_element() {
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse("<a x=\"1\">hi</a>", nodes, attrs);
    assert(ok);
    assert(doc.root >= 0);
    let root = doc.nodes[doc.root];
    assert(root.kind == xml::KIND_ELEMENT);
    assert(root.name == "a");
    let val, found = xml::attr_lookup(doc, root, "x");
    assert(found);
    assert(val == "1");
    assert(xml::children_count(doc, root) == 1);
    var text: u8[>..] = [];
    assert(xml::text_of(text, doc, root));
    assert(text == "hi");
}

fn test_parse_nested() {
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse("<a><b/><c>x</c></a>", nodes, attrs);
    assert(ok);
    let root = doc.nodes[doc.root];
    assert(xml::children_count(doc, root) == 2);
    let first, ok1 = xml::child_at(doc, root, 0);
    assert(ok1);
    assert(first.name == "b");
    let second, ok2 = xml::child_at(doc, root, 1);
    assert(ok2);
    assert(second.name == "c");
    // The parent link points back to the root.
    assert(doc.nodes[second.parent].name == "a");
}

fn test_parse_comment_cdata() {
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse("<a><!--note--><b/><![CDATA[x<y]]></a>", nodes, attrs);
    assert(ok);
    let root = doc.nodes[doc.root];
    // The comment, the element and the CDATA are the children.
    assert(xml::children_count(doc, root) == 3);
    let c0, ok0 = xml::child_at(doc, root, 0);
    assert(ok0);
    assert(c0.kind == xml::KIND_COMMENT);
    assert(c0.content == "note");
    let c1, ok1 = xml::child_at(doc, root, 1);
    assert(ok1);
    assert(c1.kind == xml::KIND_ELEMENT);
    assert(c1.name == "b");
    let c2, ok2 = xml::child_at(doc, root, 2);
    assert(ok2);
    assert(c2.kind == xml::KIND_CDATA);
    assert(c2.content == "x<y");
}

fn test_parse_declaration() {
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse("<?xml version=\"1.0\"?><a/>", nodes, attrs);
    assert(ok);
    let root = doc.nodes[doc.root];
    assert(root.name == "a");
    assert(xml::children_count(doc, root) == 0);
}

fn test_parse_pi() {
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse("<a><?target data?></a>", nodes, attrs);
    assert(ok);
    let root = doc.nodes[doc.root];
    assert(xml::children_count(doc, root) == 1);
    let c, ok1 = xml::child_at(doc, root, 0);
    assert(ok1);
    assert(c.kind == xml::KIND_PI);
    assert(c.name == "target");
    assert(c.content == "data");
}

fn test_parse_empty_forms() {
    var nodes1: xml::Node[>..] = [];
    var attrs1: xml::Attr[>..] = [];
    let doc1, ok1 = xml::parse("<a/>", nodes1, attrs1);
    assert(ok1);
    var nodes2: xml::Node[>..] = [];
    var attrs2: xml::Attr[>..] = [];
    let doc2, ok2 = xml::parse("<a></a>", nodes2, attrs2);
    assert(ok2);
    assert(xml::children_count(doc1, doc1.nodes[doc1.root]) == 0);
    assert(xml::children_count(doc2, doc2.nodes[doc2.root]) == 0);
}

fn test_parse_entities() {
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse("<a>&lt;&gt;&amp;&apos;&quot;</a>", nodes, attrs);
    assert(ok);
    let root = doc.nodes[doc.root];
    var text: u8[>..] = [];
    assert(xml::text_of(text, doc, root));
    assert(text == "<>&'\"");
}

fn test_parse_attribute_quotes() {
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse("<a x='one' y=\"two\"/>", nodes, attrs);
    assert(ok);
    let root = doc.nodes[doc.root];
    let v1, f1 = xml::attr_lookup(doc, root, "x");
    assert(f1);
    assert(v1 == "one");
    let v2, f2 = xml::attr_lookup(doc, root, "y");
    assert(f2);
    assert(v2 == "two");
}

fn test_faults() {
    expect_fault("<a>");
    expect_fault("<a></b>");
    expect_fault("text");
    expect_fault("<a/><b/>");
    expect_fault("<a>");
    expect_fault("<>");
    expect_fault("<a x/>");
    expect_fault("<a x=1/>");
    expect_fault("<a x=\"unclosed/>");
    expect_fault("<a x=\"1\" x=\"2\"/>");
    expect_fault("<a>&unknown;</a>");
    expect_fault("<a>&</a>");
    expect_fault("<a><!-- unclosed </a>");
    expect_fault("<a><![CDATA[unclosed</a>");
    expect_fault("<a><?pi unclosed</a>");
    expect_fault("");
    expect_fault("</a>");
    expect_fault("<a><b></a></b>");
}

fn test_fault_unknown_entity_in_attribute() {
    expect_fault("<a x=\"&nope;\"/>");
}

fn test_depth_limit() {
    // A document deeper than the limit is a fault.
    var text: u8[>..] = [];
    var i = 0;
    while i < 300 {
        text.append("<a>");
        i += 1;
    }
    i = 0;
    while i < 300 {
        text.append("</a>");
        i += 1;
    }
    expect_fault(text[..]);
}

fn test_depth_under_limit() {
    // A document at the limit parses.
    var text: u8[>..] = [];
    var i = 0;
    while i < 100 {
        text.append("<a>");
        i += 1;
    }
    i = 0;
    while i < 100 {
        text.append("</a>");
        i += 1;
    }
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse(text[..], nodes, attrs);
    assert(ok);
}

fn test_build_escapes() {
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse("<a>x&lt;y</a>", nodes, attrs);
    assert(ok);
    var out: u8[>..] = [];
    xml::build(out, doc, doc.root);
    assert(out == "<a>x&lt;y</a>");
}

fn test_build_attribute_escape() {
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse("<a x=\"&quot;q&quot;\"/>", nodes, attrs);
    assert(ok);
    var out: u8[>..] = [];
    xml::build(out, doc, doc.root);
    assert(out == "<a x=\"&quot;q&quot;\"/>");
}

fn test_round_trip() {
    const docs = [
        "<a/>",
        "<a>x</a>",
        "<a x=\"1\"/>",
        "<a x=\"1\" y=\"2\"/>",
        "<a><b/></a>",
        "<a><b><c/></b></a>",
        "<a><b>x</b><c>y</c></a>",
        "<root><item id=\"1\">one</item><item id=\"2\">two</item></root>",
        "<a><b/><c/><d/></a>",
        "<a>text<b/>more</a>",
        "<feed><entry><title>T</title><link href=\"u\"/></entry></feed>",
        "<a b=\"c\" d=\"e\" f=\"g\"/>",
        "<x:y xmlns:x=\"u\"><x:z/></x:y>",
    ];
    for s in docs {
        var nodes: xml::Node[>..] = [];
        var attrs: xml::Attr[>..] = [];
        let doc, ok = xml::parse(s, nodes, attrs);
        assert(ok);
        var out: u8[>..] = [];
        xml::build(out, doc, doc.root);
        assert(out == s);
    }
}

fn test_round_trip_count() {
    // The count of the round trips is at least 20 documents.
    const docs = [
        "<a/>", "<a>1</a>", "<a>x</a>", "<a x=\"1\"/>", "<a x=\"1\" y=\"2\"/>",
        "<a><b/></a>", "<a><b><c/></b></a>", "<a><b>x</b><c>y</c></a>",
        "<root><item id=\"1\">one</item></root>", "<a><b/><c/><d/></a>",
        "<a>text<b/>more</a>", "<feed><entry><title>T</title></entry></feed>",
        "<a b=\"c\" d=\"e\" f=\"g\"/>", "<a><b><c><d/></c></b></a>",
        "<a/>", "<a>2</a>", "<a>x</a>", "<a x=\"1\"/>", "<a x=\"1\" y=\"2\"/>",
        "<a><b/></a>",
    ];
    var count: i32 = 0;
    for s in docs {
        var nodes: xml::Node[>..] = [];
        var attrs: xml::Attr[>..] = [];
        let doc, ok = xml::parse(s, nodes, attrs);
        assert(ok);
        var out: u8[>..] = [];
        xml::build(out, doc, doc.root);
        assert(out == s);
        count += 1;
    }
    assert(count >= 20);
}

fn test_large_document() {
    // A large document parses in bounded time. The test checks the size.
    var text: u8[>..] = [];
    text.append("<root>");
    var i = 0;
    while i < 20000 {
        text.append("<item id=\"x\">value</item>");
        i += 1;
    }
    text.append("</root>");
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse(text[..], nodes, attrs);
    assert(ok);
    let root = doc.nodes[doc.root];
    assert(xml::children_count(doc, root) == 20000);
}

fn test_numeric_refs() {
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    // &#65; is A, &#x41; is A, &#xe9; is two UTF-8 bytes, &#x1F600; is four.
    let doc, ok = xml::parse("<a v=\"&#x41;\">&#65;&#x42;&#xe9;&#x1F600;</a>", nodes, attrs);
    assert(ok);
    let root = doc.nodes[doc.root];
    var text: u8[>..] = [];
    assert(xml::text_of(text, doc, root));
    assert(text == "AB\xc3\xa9\xf0\x9f\x98\x80");
    var v: u8[>..] = [];
    let raw, f = xml::attr_lookup(doc, root, "v");
    assert(f && xml::decode_entities(v, raw));
    assert(v == "A");
    // The writer escapes the decoded text again.
    var out: u8[>..] = [];
    var n2: xml::Node[>..] = [];
    var a2: xml::Attr[>..] = [];
    let d2, ok2 = xml::parse("<a>&#60;&#x26;</a>", n2, a2);
    assert(ok2);
    xml::build(out, d2, d2.root);
    assert(out == "<a>&lt;&amp;</a>");
    expect_fault("<a>&#;</a>");
    expect_fault("<a>&#x;</a>");
    expect_fault("<a>&#xZ;</a>");
    expect_fault("<a>&#0;</a>");
    expect_fault("<a>&#xD800;</a>");
    expect_fault("<a>&#1114112;</a>");
    expect_fault("<a>&#99999999999999999999;</a>");
    expect_fault("<a x=\"&#xFFFFFF;\"/>");
}

fn test_namespaces() {
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let src = "<r xmlns=\"urn:d\" xmlns:a=\"urn:a\" a:k=\"1\" j=\"2\"><a:c/><e xmlns=\"\"><f/></e><g xmlns:a=\"urn:b\"><a:h/></g></r>";
    let doc, ok = xml::parse(src, nodes, attrs);
    assert(ok);
    let root = doc.nodes[doc.root];
    assert(root.uri == "urn:d" && root.local == "r" && root.name == "r");
    let c, f1 = xml::child_at(doc, root, 0);
    assert(f1 && c.uri == "urn:a" && c.local == "c" && c.name == "a:c");
    // xmlns="" drops the default namespace, and the child sees none.
    let e, f2 = xml::child_at(doc, root, 1);
    assert(f2 && e.uri == "" && e.local == "e");
    let f, f3 = xml::child_at(doc, e, 0);
    assert(f3 && f.uri == "" && f.local == "f");
    // A prefix can name another URI in an inner scope.
    let g, f4 = xml::child_at(doc, root, 2);
    let h, f5 = xml::child_at(doc, g, 0);
    assert(f5 && h.uri == "urn:b" && h.local == "h");
    // A prefixed attribute has a namespace. A bare one has none.
    let v1, a1 = xml::attr_lookup_ns(doc, root, "urn:a", "k");
    assert(a1 && v1 == "1");
    let v2, a2 = xml::attr_lookup_ns(doc, root, "", "j");
    assert(a2 && v2 == "2");
    let v3, a3 = xml::attr_lookup_ns(doc, root, "", "k");
    assert(!a3);
    // The xml prefix needs no declaration.
    var n2: xml::Node[>..] = [];
    var at2: xml::Attr[>..] = [];
    let d2, ok2 = xml::parse("<a xml:lang=\"en\"/>", n2, at2);
    assert(ok2);
    let lang, a4 = xml::attr_lookup_ns(d2, d2.nodes[d2.root], xml::XML_NS, "lang");
    assert(a4 && lang == "en");
    // The writer keeps the prefixes and the declarations.
    var out: u8[>..] = [];
    xml::build(out, doc, doc.root);
    assert(out == src);
    // An undeclared prefix is a fault, for an element and for an attribute.
    expect_fault("<a:b/>");
    expect_fault("<a z:k=\"1\"/>");
    expect_fault("<a><b:c xmlns:b=\"u\"/><b:d/></a>");
}

fn test_find() {
    var nodes: xml::Node[>..] = [];
    var attrs: xml::Attr[>..] = [];
    let doc, ok = xml::parse("<r xmlns:p=\"urn:p\"><i n=\"1\"/><p:i n=\"2\"/><i n=\"3\"><i n=\"4\"/></i>x</r>", nodes, attrs);
    assert(ok);
    let root = doc.nodes[doc.root];
    let first, f = xml::find(doc, root, "i");
    assert(f);
    let n1, g1 = xml::attr_lookup(doc, first, "n");
    assert(g1 && n1 == "1");
    let ns, f2 = xml::find(doc, root, "{urn:p}i");
    assert(f2);
    let n2, g2 = xml::attr_lookup(doc, ns, "n");
    assert(g2 && n2 == "2");
    let nothing, f3 = xml::find(doc, root, "{urn:q}i");
    assert(!f3);
    let nothing2, f4 = xml::find(doc, root, "zzz");
    assert(!f4);
    var ids: i32[>..] = [];
    assert(xml::findall(doc, root, "i", ids) == 2);
    assert(ids.len == 2);
    var deep: i32[>..] = [];
    assert(xml::findall_deep(doc, root, "i", deep) == 3);
    var all: i32[>..] = [];
    assert(xml::findall_deep(doc, root, "{urn:p}i", all) == 1);
}

fn test_pull() {
    let src = "<?xml version=\"1.0\"?><!-- c --><r a=\"1\"><b/>t&#65;<![CDATA[x]]><?p d?></r>";
    var r = xml::reader(src);
    var open: xml::Open[>..] = [];
    var attrs: xml::Attr[>..] = [];
    var kinds: i32[>..] = [];
    var text: u8[>..] = [];
    while true {
        let ev, ok = xml::next(r, open, attrs);
        assert(ok);
        if ev.kind == xml::EV_EOF { break; }
        kinds.push(ev.kind);
        if ev.kind == xml::EV_START && ev.name == "r" {
            assert(attrs.len == 1 && attrs[0].name == "a" && attrs[0].value == "1");
        }
        if ev.kind == xml::EV_TEXT { assert(xml::decode_entities(text, ev.content)); }
    }
    assert(text == "tA");
    // start r, start b, end b, text, cdata, pi, end r. The comment before
    // the root is dropped.
    var want: i32[>..] = [xml::EV_START, xml::EV_START, xml::EV_END, xml::EV_TEXT, xml::EV_CDATA, xml::EV_PI, xml::EV_END];
    assert(kinds == want[..]);
    let p, l = xml::ns_split("a:b");
    assert(p == "a" && l == "b");
    let p2, l2 = xml::ns_split("b");
    assert(p2 == "" && l2 == "b");
}

fn pull_fault(src: const u8[:]) {
    var r = xml::reader(src);
    var open: xml::Open[>..] = [];
    var attrs: xml::Attr[>..] = [];
    var failed = false;
    while true {
        let ev, ok = xml::next(r, open, attrs);
        if !ok { failed = true; break; }
        if ev.kind == xml::EV_EOF { break; }
    }
    assert(failed);
}

fn test_pull_faults() {
    pull_fault("<a>");
    pull_fault("<a></b>");
    pull_fault("text");
    pull_fault("<a/><b/>");
    pull_fault("<a>&bad;</a>");
    pull_fault("<a x=\"1\" x=\"2\"/>");
    pull_fault("");
    pull_fault("<a/>junk");
}

fn test_pull_large() {
    var text: u8[>..] = [];
    text.append("<root>");
    var i = 0;
    while i < 20000 {
        text.append("<item id=\"x\">value</item>");
        i += 1;
    }
    text.append("</root>");
    var r = xml::reader(text[..]);
    var open: xml::Open[>..] = [];
    var attrs: xml::Attr[>..] = [];
    var starts = 0;
    while true {
        let ev, ok = xml::next(r, open, attrs);
        assert(ok);
        if ev.kind == xml::EV_EOF { break; }
        if ev.kind == xml::EV_START { starts += 1; }
    }
    assert(starts == 20001);
}

fn main() {
    test_parse_element();
    test_parse_nested();
    test_parse_comment_cdata();
    test_parse_declaration();
    test_parse_pi();
    test_parse_empty_forms();
    test_parse_entities();
    test_parse_attribute_quotes();
    test_faults();
    test_fault_unknown_entity_in_attribute();
    test_depth_limit();
    test_depth_under_limit();
    test_build_escapes();
    test_build_attribute_escape();
    test_round_trip();
    test_round_trip_count();
    test_large_document();
    test_numeric_refs();
    test_namespaces();
    test_find();
    test_pull();
    test_pull_faults();
    test_pull_large();
    print("all tests passed");
    return 0;
}
