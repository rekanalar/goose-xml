// The tree builder of the xml package.
//
// The calls make elements, add children and attributes, and set text.
// The caller owns three buffers: the node array, the attribute array and
// a text buffer. The builder copies every name and every text into the
// text buffer, so the tree needs no other memory. The text buffer holds
// the text in the escaped form, as the parser leaves it in the input.
// The calls follow Element, SubElement, set, append, remove and the
// text and tail fields of ElementTree.
namespace xml;

import std;
import tree;

// Builder keeps no state. The three buffers go with each call.

// bt_copy copies the text into the buffer and gives the span.
fn bt_copy(text: u8[>..]&, s: const u8[:]) -> const u8[:] {
    let start = text.len;
    text.append(s);
    return text[start..text.len];
}

// bt_new makes a detached node of the kind.
fn bt_new(nodes: Node[>..]&, kind: i32) -> i32 {
    nodes.push(Node {
        kind: kind, name: "", uri: "", local: "", content: "",
        parent: -1, first_child: -1, last_child: -1, next_sibling: -1,
        attr_start: 0, attr_count: 0,
    });
    return (nodes.len - 1) as i32;
}

// bt_split splits the tag into the uri and the local name. The tag is
// a local name or a name of the form {uri}local.
fn bt_split(tag: const u8[:]) -> const u8[:], const u8[:] {
    if tag.len > 1 && tag[0] == '{' {
        var e: i64 = 1;
        while e < tag.len && tag[e] != '}' { e += 1; }
        if e < tag.len { return tag[1..e], tag[e + 1..]; }
    }
    return "", tag;
}

// name_ok tells whether s is a valid XML Name. It uses read_name, the
// function that the parser uses, so the builder and the parser share one
// rule. A name with a space, a quote, < or > is not valid. The writer
// copies a name as it is, so the builder must refuse these. The rule
// checks the form of a name, not whether a prefix is declared.
fn name_ok(s: const u8[:]) -> bool {
    return s.len > 0 && read_name(s, 0) == s.len;
}

// bt_name_ok tells whether the local name of the tag or the key is valid.
// The part {uri} is free text and the writer escapes it.
fn bt_name_ok(tag: const u8[:]) -> bool {
    let _, local = bt_split(tag);
    return name_ok(local);
}

// element makes a detached element with the tag. It gives the place of
// the element, or -1 when the tag is empty or its local name is not a
// valid XML Name.
fn element(nodes: Node[>..]&, text: u8[>..]&, tag: const u8[:]) -> i32 {
    if tag.len == 0 { return -1; }
    if !bt_name_ok(tag) { return -1; }
    let copy = bt_copy(text, tag);
    let uri, local = bt_split(copy);
    let id = bt_new(nodes, KIND_ELEMENT as i32);
    nodes[id].name = local;
    nodes[id].uri = uri;
    nodes[id].local = local;
    return id;
}

// append adds the node at the end of the children of the parent. The
// node must have no parent. It gives false when the node has a parent
// already, or when the node is an ancestor of the parent.
fn append(nodes: Node[>..]&, parent: i32, child: i32) -> bool {
    if parent == child || nodes[child].parent >= 0 { return false; }
    var up = parent;
    while up >= 0 {
        if up == child { return false; }
        up = nodes[up].parent;
    }
    nodes[child].parent = parent;
    nodes[child].next_sibling = -1;
    if nodes[parent].last_child >= 0 {
        let last = nodes[parent].last_child;
        nodes[last].next_sibling = child;
    } else {
        nodes[parent].first_child = child;
    }
    nodes[parent].last_child = child;
    return true;
}

// insert adds the node as child number index of the parent, counting only
// the child elements, as Element.insert does. An index past the end adds at
// the end.
// It gives false on the same faults as append.
fn insert(nodes: Node[>..]&, parent: i32, index: i64, child: i32) -> bool {
    if parent == child || nodes[child].parent >= 0 { return false; }
    var up = parent;
    while up >= 0 {
        if up == child { return false; }
        up = nodes[up].parent;
    }
    // Find the element at the place. The child goes right before it, so the
    // tail text of the element in front stays with that element.
    var seen: i64 = 0;
    var prev: i32 = -1;
    var at = nodes[parent].first_child;
    var i = index;
    if i < 0 { i = 0; }
    while at >= 0 {
        if nodes[at].kind == KIND_ELEMENT {
            if seen == i { break; }
            seen += 1;
        }
        prev = at;
        at = nodes[at].next_sibling;
    }
    if at < 0 { return append(nodes, parent, child); }
    nodes[child].parent = parent;
    if prev >= 0 {
        nodes[child].next_sibling = nodes[prev].next_sibling;
        nodes[prev].next_sibling = child;
    } else {
        nodes[child].next_sibling = nodes[parent].first_child;
        nodes[parent].first_child = child;
    }
    return true;
}

// clear takes away the children, the text and the attributes of the
// element and its tail, as Element.clear does.
fn clear(nodes: Node[>..]&, text: u8[>..]&, id: i32) -> bool {
    if nodes[id].kind != KIND_ELEMENT { return false; }
    if nodes[id].parent >= 0 { set_tail(nodes, text, id, ""); }
    var c = nodes[id].first_child;
    while c >= 0 {
        let next = nodes[c].next_sibling;
        nodes[c].parent = -1;
        nodes[c].next_sibling = -1;
        c = next;
    }
    nodes[id].first_child = -1;
    nodes[id].last_child = -1;
    nodes[id].attr_count = 0;
    return true;
}

// sub_element makes an element with the tag at the end of the children
// of the parent. It gives the place of the new element, or -1.
fn sub_element(nodes: Node[>..]&, text: u8[>..]&, parent: i32, tag: const u8[:]) -> i32 {
    let id = element(nodes, text, tag);
    if id < 0 { return -1; }
    append(nodes, parent, id);
    return id;
}

// remove takes the child out of the children of the parent. It gives
// false when the child is not a child of the parent.
fn remove(nodes: Node[>..]&, parent: i32, child: i32) -> bool {
    if nodes[child].parent != parent { return false; }
    var prev: i32 = -1;
    var c = nodes[parent].first_child;
    while c >= 0 && c != child {
        prev = c;
        c = nodes[c].next_sibling;
    }
    if c < 0 { return false; }
    let next = nodes[child].next_sibling;
    if prev >= 0 { nodes[prev].next_sibling = next; } else { nodes[parent].first_child = next; }
    if nodes[parent].last_child == child { nodes[parent].last_child = prev; }
    nodes[child].parent = -1;
    nodes[child].next_sibling = -1;
    return true;
}

// set sets the attribute of the element. The key is a local name or a
// name of the form {uri}local. An attribute with the key is replaced.
// The value is plain text. It gives false when the key is empty, the
// local name of the key is not a valid XML Name, or the node is not an
// element.
fn set(nodes: Node[>..]&, attrs: Attr[>..]&, text: u8[>..]&, id: i32, key: const u8[:], value: const u8[:]) -> bool {
    if key.len == 0 || nodes[id].kind != KIND_ELEMENT { return false; }
    if !bt_name_ok(key) { return false; }
    let kcopy = bt_copy(text, key);
    let uri, local = bt_split(kcopy);
    let vstart = text.len;
    encode_attr(text, value);
    let escaped = text[vstart..text.len];
    let start = nodes[id].attr_start;
    var i = 0;
    while i < nodes[id].attr_count {
        if attrs[start + i].uri == uri && attrs[start + i].local == local {
            attrs[start + i].value = escaped;
            return true;
        }
        i += 1;
    }
    // The attributes of an element are one range. A range that does not end
    // the array moves to the end first.
    if nodes[id].attr_count > 0 && start + nodes[id].attr_count != attrs.len {
        let count = nodes[id].attr_count;
        nodes[id].attr_start = attrs.len as i32;
        var k = 0;
        while k < count {
            attrs.push(attrs[start + k]);
            k += 1;
        }
    } else if nodes[id].attr_count == 0 {
        nodes[id].attr_start = attrs.len as i32;
    }
    attrs.push(Attr { name: local, value: escaped, uri: uri, local: local });
    nodes[id].attr_count += 1;
    return true;
}

// bt_drop_text takes the text nodes that start at the node out of the
// siblings of the list, up to the next element. It works on the list of
// the parent, after the node prev (-1 for the first child).
fn bt_drop_text(nodes: Node[>..]&, parent: i32, from: i32) {
    var prev = from;
    var c = if prev >= 0 { nodes[prev].next_sibling } else { nodes[parent].first_child };
    while c >= 0 && nodes[c].kind != KIND_ELEMENT {
        let next = nodes[c].next_sibling;
        if nodes[c].kind == KIND_TEXT || nodes[c].kind == KIND_CDATA {
            if prev >= 0 { nodes[prev].next_sibling = next; } else { nodes[parent].first_child = next; }
            if nodes[parent].last_child == c { nodes[parent].last_child = prev; }
            nodes[c].parent = -1;
            nodes[c].next_sibling = -1;
        } else {
            prev = c;
        }
        c = next;
    }
}

// bt_put_text puts a new text node after the node prev in the list of
// the parent (-1 for the first place).
fn bt_put_text(nodes: Node[>..]&, text: u8[>..]&, parent: i32, prev: i32, value: const u8[:]) {
    if value.len == 0 { return; }
    let start = text.len;
    encode_text(text, value);
    let id = bt_new(nodes, KIND_TEXT as i32);
    nodes[id].content = text[start..text.len];
    nodes[id].parent = parent;
    if prev >= 0 {
        nodes[id].next_sibling = nodes[prev].next_sibling;
        nodes[prev].next_sibling = id;
    } else {
        nodes[id].next_sibling = nodes[parent].first_child;
        nodes[parent].first_child = id;
    }
    if nodes[id].next_sibling < 0 { nodes[parent].last_child = id; }
}

// set_text sets the text of the element, the text before its first
// child element. An empty value takes the text away.
fn set_text(nodes: Node[>..]&, text: u8[>..]&, id: i32, value: const u8[:]) -> bool {
    if nodes[id].kind != KIND_ELEMENT { return false; }
    bt_drop_text(nodes, id, -1);
    bt_put_text(nodes, text, id, -1, value);
    return true;
}

// set_tail sets the tail of the element, the text after it and before
// the next sibling element. The element needs a parent.
fn set_tail(nodes: Node[>..]&, text: u8[>..]&, id: i32, value: const u8[:]) -> bool {
    let parent = nodes[id].parent;
    if parent < 0 || nodes[id].kind != KIND_ELEMENT { return false; }
    bt_drop_text(nodes, parent, id);
    bt_put_text(nodes, text, parent, id, value);
    return true;
}

// make_doc makes a Doc over the three arrays with the element as root.
fn make_doc(nodes: Node[>..]&, attrs: Attr[>..]&, root: i32) -> Doc {
    return Doc { nodes: nodes[..], attrs: attrs[..], root: root };
}
