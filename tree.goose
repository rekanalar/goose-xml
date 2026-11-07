// The tree for the xml package.
//
// A Doc holds the input text and the node array. A Node holds spans over
// the input text, so nothing in the tree is a copy. The text the caller
// asks for comes back through the buffer of the caller, with the
// entities decoded.
namespace xml;

import std;

// The namespaces that XML reserves.
const XML_NS: const u8[:] = "http://www.w3.org/XML/1998/namespace";
const XMLNS_NS: const u8[:] = "http://www.w3.org/2000/xmlns/";

// The kinds of a node.
const KIND_ELEMENT = 0;
const KIND_TEXT = 1;
const KIND_COMMENT = 2;
const KIND_CDATA = 3;
const KIND_PI = 4;

// Attr holds one attribute as two spans over the input. The uri and the
// local name hold the resolved name of the attribute. An attribute
// without a prefix has no namespace.
struct Attr {
    name: const u8[:],
    value: const u8[:],
    uri: const u8[:],
    local: const u8[:],
}

// Node holds one node of the tree. The links are indexes into the node
// array of the Doc, and -1 when absent. An element holds the range of
// its attributes through attr_start and attr_count. The other kinds hold
// their bytes in content.
struct Node {
    kind: i32,
    name: const u8[:],
    uri: const u8[:],
    local: const u8[:],
    content: const u8[:],
    parent: i32,
    first_child: i32,
    next_sibling: i32,
    attr_start: i32,
    attr_count: i32,
}

// Doc holds one parsed document.
struct Doc {
    nodes: Node[],
    attrs: Attr[],
    root: i32,
}

// name_of gives the name of an element or a PI.
fn name_of(n: Node&) -> const u8[:] {
    return n.name;
}

// kind_of gives the kind constant of a node.
fn kind_of(n: Node&) -> i32 {
    return n.kind;
}

// attr_lookup gives the value of the attribute of the element. An absent
// name gives false.
fn attr_lookup(doc: Doc&, n: Node&, key: const u8[:]) -> const u8[:], bool {
    var i = 0;
    while i < n.attr_count {
        let a = doc.attrs[n.attr_start + i];
        if a.name == key { return a.value, true; }
        i += 1;
    }
    return "", false;
}

// child_at gives the child of the element at the place at, in document
// order. A place outside gives false.
fn child_at(doc: Doc&, n: Node&, at: i32) -> Node&, bool {
    var child_id = n.first_child;
    var i: i32 = 0;
    while child_id >= 0 {
        if i == at { return doc.nodes[child_id], true; }
        child_id = doc.nodes[child_id].next_sibling;
        i += 1;
    }
    return doc.nodes[0], false;
}

// children_count gives the number of the direct children of the element.
fn children_count(doc: Doc&, n: Node&) -> i32 {
    var child_id = n.first_child;
    var count: i32 = 0;
    while child_id >= 0 {
        child_id = doc.nodes[child_id].next_sibling;
        count += 1;
    }
    return count;
}

// decode_entities writes s with the entities decoded into out. The five
// predefined names and the numeric character references decode. An
// unknown name returns false and writes nothing more.
fn decode_entities(out: u8[>..]&, s: const u8[:]) -> bool {
    var i = 0;
    while i < s.len {
        if s[i] == '&' {
            var end = i + 1;
            while end < s.len && s[end] != ';' { end += 1; }
            if end >= s.len { return false; }
            let ent = s[i + 1..end];
            if ent == "lt" {
                out.push('<');
            } else if ent == "gt" {
                out.push('>');
            } else if ent == "amp" {
                out.push('&');
            } else if ent == "apos" {
                out.push('\'');
            } else if ent == "quot" {
                out.push('"');
            } else if ent.len > 1 && ent[0] == '#' {
                let cp, ok = char_ref(ent[1..]);
                if !ok { return false; }
                write_utf8(out, cp);
            } else {
                return false;
            }
            i = end + 1;
        } else {
            out.push(s[i]);
            i += 1;
        }
    }
    return true;
}

// char_ref reads the number of a character reference. The text holds
// the digits, in decimal or in hexadecimal after an 'x'. A number that
// is not a character of XML gives false.
fn char_ref(digits: const u8[:]) -> i64, bool {
    if digits.len == 0 { return 0, false; }
    var cp: i64 = 0;
    if digits[0] == 'x' || digits[0] == 'X' {
        if digits.len == 1 { return 0, false; }
        var i: i64 = 1;
        while i < digits.len {
            let d = hex_value(digits[i]);
            if d < 0 { return 0, false; }
            cp = cp * 16 + d;
            if cp > 1114111 { return 0, false; }
            i += 1;
        }
    } else {
        var i: i64 = 0;
        while i < digits.len {
            if digits[i] < '0' || digits[i] > '9' { return 0, false; }
            cp = cp * 10 + (digits[i] - '0') as i64;
            if cp > 1114111 { return 0, false; }
            i += 1;
        }
    }
    if !valid_xml_char(cp) { return 0, false; }
    return cp, true;
}

// hex_value gives the value of one hexadecimal digit, or -1.
fn hex_value(c: u8) -> i64 {
    if c >= '0' && c <= '9' { return (c - '0') as i64; }
    if c >= 'a' && c <= 'f' { return (c - 'a' + 10) as i64; }
    if c >= 'A' && c <= 'F' { return (c - 'A' + 10) as i64; }
    return -1;
}

// valid_xml_char tells whether a code point is a character of XML 1.0.
fn valid_xml_char(cp: i64) -> bool {
    if cp == 9 || cp == 10 || cp == 13 { return true; }
    if cp >= 32 && cp <= 55295 { return true; }
    if cp >= 57344 && cp <= 65533 { return true; }
    if cp >= 65536 && cp <= 1114111 { return true; }
    return false;
}

// write_utf8 writes one code point as UTF-8 bytes.
fn write_utf8(out: u8[>..]&, cp: i64) {
    if cp < 128 {
        out.push(cp as u8);
    } else if cp < 2048 {
        out.push((0xc0 | (cp >> 6)) as u8);
        out.push((0x80 | (cp & 63)) as u8);
    } else if cp < 65536 {
        out.push((0xe0 | (cp >> 12)) as u8);
        out.push((0x80 | ((cp >> 6) & 63)) as u8);
        out.push((0x80 | (cp & 63)) as u8);
    } else {
        out.push((0xf0 | (cp >> 18)) as u8);
        out.push((0x80 | ((cp >> 12) & 63)) as u8);
        out.push((0x80 | ((cp >> 6) & 63)) as u8);
        out.push((0x80 | (cp & 63)) as u8);
    }
}

// text_of writes the direct text children of the element, joined, with
// the entities decoded, into out.
fn text_of(out: u8[>..]&, doc: Doc&, n: Node&) -> bool {
    var child_id = n.first_child;
    while child_id >= 0 {
        let child = doc.nodes[child_id];
        if child.kind == KIND_TEXT {
            if !decode_entities(out, child.content) { return false; }
        }
        child_id = child.next_sibling;
    }
    return true;
}

// find_colon gives the place of the colon in a qualified name, or -1.
fn find_colon(s: const u8[:]) -> i64 {
    var i: i64 = 0;
    while i < s.len {
        if s[i] == ':' { return i; }
        i += 1;
    }
    return -1;
}

// tag_matches tells whether an element with the resolved name matches the
// tag of the caller. The tag is a local name, which matches only an
// element without a namespace, or a name of the form {uri}local, which
// matches the namespace and the local name.
fn tag_matches(uri: const u8[:], local: const u8[:], tag: const u8[:]) -> bool {
    if tag.len > 0 && tag[0] == '{' {
        var i: i64 = 1;
        while i < tag.len && tag[i] != '}' { i += 1; }
        if i >= tag.len { return false; }
        return uri == tag[1..i] && local == tag[i + 1..];
    }
    return uri.len == 0 && local == tag;
}

// find gives the first direct child element of n with the tag. The tag
// holds a local name or a name of the form {uri}local. A child without
// a match gives false.
fn find(doc: Doc&, n: Node&, tag: const u8[:]) -> Node&, bool {
    var child_id = n.first_child;
    while child_id >= 0 {
        let child = doc.nodes[child_id];
        if child.kind == KIND_ELEMENT && tag_matches(child.uri, child.local, tag) {
            return doc.nodes[child_id], true;
        }
        child_id = child.next_sibling;
    }
    return doc.nodes[0], false;
}

// findall writes the places of the direct child elements of n with the
// tag into out. It gives the count of the matches.
fn findall(doc: Doc&, n: Node&, tag: const u8[:], out: i32[>..]&) -> i64 {
    var count: i64 = 0;
    var child_id = n.first_child;
    while child_id >= 0 {
        let child = doc.nodes[child_id];
        if child.kind == KIND_ELEMENT && tag_matches(child.uri, child.local, tag) {
            out.push(child_id);
            count += 1;
        }
        child_id = child.next_sibling;
    }
    return count;
}

// findall_deep writes the places of all the descendant elements of n
// with the tag into out. It gives the count of the matches. The walk
// uses an explicit stack, so no recursion runs.
fn findall_deep(doc: Doc&, n: Node&, tag: const u8[:], out: i32[>..]&) -> i64 {
    var count: i64 = 0;
    var stack: i32[>..] = [];
    var child_id = n.first_child;
    while child_id >= 0 {
        stack.push(child_id);
        child_id = doc.nodes[child_id].next_sibling;
    }
    while stack.len > 0 {
        let id = stack[stack.len - 1];
        stack.pop();
        let node = doc.nodes[id];
        if node.kind == KIND_ELEMENT && tag_matches(node.uri, node.local, tag) {
            out.push(id);
            count += 1;
        }
        var sub = node.first_child;
        while sub >= 0 {
            stack.push(sub);
            sub = doc.nodes[sub].next_sibling;
        }
    }
    return count;
}

// attr_lookup_ns gives the value of the attribute of the element with
// the resolved name. The uri and the local name hold the namespace and
// the local name of the attribute. An absent name gives false.
fn attr_lookup_ns(doc: Doc&, n: Node&, uri: const u8[:], local: const u8[:]) -> const u8[:], bool {
    var i = 0;
    while i < n.attr_count {
        let a = doc.attrs[n.attr_start + i];
        if a.uri == uri && a.local == local { return a.value, true; }
        i += 1;
    }
    return "", false;
}
