// The reading calls of the xml package.
//
// The calls give the text of an element, the text of a subtree, the
// attributes of an element and the elements of a subtree. The rules
// follow xml.etree.ElementTree of Python 3.14.
namespace xml;

import std;
import tree;

// A Pair holds one attribute name and its value.
struct Pair {
    name: const u8[:],
    value: const u8[:],
}

// elem_text writes the text of the element before its first child
// element into out. The text of the comments and the processing
// instructions does not count.
fn elem_text(out: u8[>..]&, doc: Doc&, id: i32) -> bool {
    var c = doc.nodes[id].first_child;
    while c >= 0 {
        let n = doc.nodes[c];
        if n.kind == KIND_ELEMENT { return true; }
        if n.kind == KIND_TEXT {
            if !decode_entities(out, n.content) { return false; }
        } else if n.kind == KIND_CDATA {
            var k = 0;
            while k < n.content.len { k = put_literal(out, n.content, k, false); }
        }
        c = n.next_sibling;
    }
    return true;
}

// elem_tail writes the text after the element and before its next
// sibling element into out.
fn elem_tail(out: u8[>..]&, doc: Doc&, id: i32) -> bool {
    var c = doc.nodes[id].next_sibling;
    while c >= 0 {
        let n = doc.nodes[c];
        if n.kind == KIND_ELEMENT { return true; }
        if n.kind == KIND_TEXT {
            if !decode_entities(out, n.content) { return false; }
        } else if n.kind == KIND_CDATA {
            var k = 0;
            while k < n.content.len { k = put_literal(out, n.content, k, false); }
        }
        c = n.next_sibling;
    }
    return true;
}

// iter_text writes the text of the element and of its descendants into
// out. The text of every child element comes before the text that
// follows it.
recursive fn iter_text(out: u8[>..]&, doc: Doc&, id: i32) -> bool {
    if !elem_text(out, doc, id) { return false; }
    var c = doc.nodes[id].first_child;
    while c >= 0 {
        let n = doc.nodes[c];
        if n.kind == KIND_ELEMENT {
            if !iter_text(out, doc, c) { return false; }
            if !elem_tail(out, doc, c) { return false; }
        }
        c = n.next_sibling;
    }
    return true;
}

// iter_walk writes the elements of the subtree in document order.
recursive fn iter_walk(doc: Doc&, id: i32, name: const u8[:], out: i32[>..]&) {
    let n = doc.nodes[id];
    if n.kind != KIND_ELEMENT { return; }
    if name == "*" || (n.uri.len == 0 && n.local == name) { out.push(id); }
    else if name.len > 0 && name[0] == '{' {
        var e: i64 = 1;
        while e < name.len && name[e] != '}' { e += 1; }
        if e > 1 && e < name.len && n.uri == name[1..e] && n.local == name[e + 1..] { out.push(id); }
    }
    var c = n.first_child;
    while c >= 0 {
        iter_walk(doc, c, name, out);
        c = doc.nodes[c].next_sibling;
    }
}

// iter writes the places of the elements of the subtree of the element
// into out, in document order. The element comes first. The name "*" or
// an empty name gives every element. Other names match literally, as in
// Python: a plain name has no namespace, and {uri}local has one.
// It gives the count of the elements.
fn iter(doc: Doc&, id: i32, name: const u8[:], out: i32[>..]&) -> i64 {
    let start = out.len;
    iter_walk(doc, id, if name.len == 0 { "*" } else { name }, out);
    return out.len - start;
}

// findtext writes the text of the first element that matches the path
// into out. It writes the default when no element matches, and gives
// false in that case.
fn findtext(out: u8[>..]&, doc: Doc&, id: i32, path: const u8[:], default: const u8[:]) -> bool {
    return findtext_ns(out, doc, id, path, default, NO_PREFIXES, NO_PREFIXES);
}

// findtext_ns is findtext with a map of prefixes, as in find_path_ns.
fn findtext_ns(out: u8[>..]&, doc: Doc&, id: i32, path: const u8[:], default: const u8[:], prefixes: const u8[:][:], uris: const u8[:][:]) -> bool {
    let found, ok = find_path_ns(doc, id, path, prefixes, uris);
    if !ok {
        out.append(default);
        return false;
    }
    return elem_text(out, doc, found);
}

// get writes the value of the attribute of the element into out. The
// key is a local name or a name of the form {uri}local. It writes the
// default when the attribute is absent, and gives false in that case.
fn get(out: u8[>..]&, doc: Doc&, id: i32, key: const u8[:], default: const u8[:]) -> bool {
    var i = 0;
    while i < doc.nodes[id].attr_count {
        let a = doc.attrs[doc.nodes[id].attr_start + i];
        i += 1;
        if path_attr_match(a, key) { return decode_attr(out, a.value); }
    }
    out.append(default);
    return false;
}

// attr_key writes the name of the attribute as ElementTree writes it:
// the local name, or {uri}local when the attribute has a namespace.
fn attr_key(buf: u8[>..]&, a: Attr&) -> const u8[:] {
    let start = buf.len;
    if a.uri.len > 0 {
        buf.push('{');
        buf.append(a.uri);
        buf.push('}');
    }
    buf.append(a.local);
    return buf[start..buf.len];
}

// is_ns_decl says whether the attribute is a namespace declaration.
fn is_ns_decl(a: Attr&) -> bool {
    return a.name == "xmlns" || (a.name.len > 6 && a.name[0..6] == "xmlns:");
}

// keys writes the names of the attributes of the element into out. The
// names go into the buffer of the caller in the form ElementTree uses.
// A namespace declaration is not an attribute. The names keep the order
// of the document.
fn keys(doc: Doc&, id: i32, buf: u8[>..]&, out: const u8[:][>..]&) -> i64 {
    var i = 0;
    var count: i64 = 0;
    while i < doc.nodes[id].attr_count {
        let a = doc.attrs[doc.nodes[id].attr_start + i];
        i += 1;
        if is_ns_decl(a) { continue; }
        out.push(attr_key(buf, a));
        count += 1;
    }
    return count;
}

// items writes the names and the values of the attributes of the
// element into out. The names and the values go into the buffer of the
// caller, with the entities decoded. The names keep the order of the
// document, and a namespace declaration is not an attribute.
fn items(doc: Doc&, id: i32, buf: u8[>..]&, out: Pair[>..]&) -> i64 {
    var i = 0;
    var count: i64 = 0;
    while i < doc.nodes[id].attr_count {
        let a = doc.attrs[doc.nodes[id].attr_start + i];
        i += 1;
        if is_ns_decl(a) { continue; }
        let name = attr_key(buf, a);
        let start = buf.len;
        if !decode_attr(buf, a.value) { return -1; }
        out.push(Pair { name: name, value: buf[start..buf.len] });
        count += 1;
    }
    return count;
}
