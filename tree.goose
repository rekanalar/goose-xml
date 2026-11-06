// The tree for the xml package.
//
// A Doc holds the input text and the node array. A Node holds spans over
// the input text, so nothing in the tree is a copy. The text the caller
// asks for comes back through the buffer of the caller, with the
// entities decoded.
namespace xml;

import std;

// The kinds of a node.
const KIND_ELEMENT = 0;
const KIND_TEXT = 1;
const KIND_COMMENT = 2;
const KIND_CDATA = 3;
const KIND_PI = 4;

// Attr holds one attribute as two spans over the input.
struct Attr {
    name: const u8[:],
    value: const u8[:],
}

// Node holds one node of the tree. The links are indexes into the node
// array of the Doc, and -1 when absent. An element holds the range of
// its attributes through attr_start and attr_count. The other kinds hold
// their bytes in content.
struct Node {
    kind: i32,
    name: const u8[:],
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

// decode_entities writes s with the five predefined entities decoded
// into out. An unknown entity returns false and writes nothing more.
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
