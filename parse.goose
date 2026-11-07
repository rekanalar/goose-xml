// The parser for the xml package. XML 1.0 well-formedness core.
//
// parse reads the text once, left to right, with an explicit stack of
// open elements. No recursion. The depth limit is 256. The tree stores
// spans over the input text, so parse copies nothing.
//
// The faults: text or a second root outside the root element, an
// unclosed tag, a mismatched close tag, an attribute without a value or
// quote, a duplicate attribute, an unknown entity, '<' or an unquoted
// quote in an attribute value, a PI whose target holds a colon at the
// wrong place, and depth beyond the limit.
namespace xml;

import std;
import tree;

const MAX_DEPTH = 256;

fn is_name_start(c: u8) -> bool {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == ':';
}

fn is_name_char(c: u8) -> bool {
    return is_name_start(c) || (c >= '0' && c <= '9') || c == '-' || c == '.';
}

fn is_space(c: u8) -> bool {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

// read_name reads a name at pos and gives its end. A fault gives -1.
fn read_name(s: const u8[:], pos: i64) -> i64 {
    if pos >= s.len || !is_name_start(s[pos]) { return -1; }
    var i = pos + 1;
    while i < s.len && is_name_char(s[i]) { i += 1; }
    return i;
}

// find_entity_end gives the index of the ';' that ends the entity at
// pos ('&'). A fault gives -1: no ';' in reach, or an empty name.
fn find_entity_end(s: const u8[:], pos: i64) -> i64 {
    var i = pos + 1;
    while i < s.len && s[i] != ';' {
        if s[i] == '&' || s[i] == '<' { return -1; }
        i += 1;
    }
    if i >= s.len || i == pos + 1 { return -1; }
    return i;
}

// valid_entities checks every entity in the span. The five predefined
// names and the numeric character references pass; anything else is a
// fault. Raw '<' in text is a fault too.
fn valid_entities(s: const u8[:]) -> bool {
    var i = 0;
    while i < s.len {
        if s[i] == '<' { return false; }
        if s[i] == '&' {
            let end = find_entity_end(s, i);
            if end < 0 { return false; }
            let ent = s[i + 1..end];
            if ent.len > 0 && ent[0] == '#' {
                let cp, ok = char_ref(ent[1..]);
                if !ok { return false; }
            } else if ent != "lt" && ent != "gt" && ent != "amp" && ent != "apos" && ent != "quot" {
                return false;
            }
            i = end + 1;
        } else {
            i += 1;
        }
    }
    return true;
}

// append_node adds one node to the tree and gives its index.
fn append_node(nodes: Node[>..]&, kind: i32, name: const u8[:], content: const u8[:], parent: i32) -> i32 {
    let id = nodes.len as i32;
    nodes.push(Node { kind: kind, name: name, uri: "", local: name, content: content, parent: parent, first_child: -1, next_sibling: -1, attr_start: 0, attr_count: 0 });
    if parent >= 0 {
        // Link the node as the last child of the parent.
        var p = nodes[parent];
        if p.first_child < 0 {
            nodes[parent].first_child = id;
        } else {
            var last = p.first_child;
            while nodes[last].next_sibling >= 0 {
                last = nodes[last].next_sibling;
            }
            nodes[last].next_sibling = id;
        }
    }
    return id;
}

// parse reads one document. It returns an empty Doc and false when the
// text is not well-formed. The spans in the tree point into the text, so
// the text must outlive the Doc.
fn parse(s: const u8[:], nodes: Node[>..]&, attrs: Attr[>..]&) -> Doc, bool {
    var stack: i32[>..] = [];
    var pos: i64 = 0;
    // True when the root element closed. Any node after it is a fault.
    var root_done = false;
    var root_id: i32 = -1;

    while pos < s.len {
        if root_done {
            // Only whitespace may follow the root.
            if is_space(s[pos]) { pos += 1; continue; }
            return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false;
        }
        if s[pos] == '<' {
            if pos + 1 >= s.len { return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false; }
            let c = s[pos + 1];
            if c == '/' {
                // A close tag: match the top of the stack.
                let name_end = read_name(s, pos + 2);
                if name_end < 0 { return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false; }
                var j = name_end;
                while j < s.len && is_space(s[j]) { j += 1; }
                if j >= s.len || s[j] != '>' { return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false; }
                if stack.len == 0 { return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false; }
                let open_id = stack[stack.len - 1];
                if nodes[open_id].name != s[pos + 2..name_end] {
                    return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false;
                }
                stack.pop();
                if stack.len == 0 {
                    root_done = true;
                }
                pos = j + 1;
            } else if c == '!' {
                if pos + 3 < s.len && s[pos + 2] == '-' && s[pos + 3] == '-' {
                    // A comment: find "-->".
                    var j = pos + 4;
                    var closed = false;
                    while j + 2 < s.len {
                        if s[j] == '-' && s[j + 1] == '-' && s[j + 2] == '>' { closed = true; break; }
                        j += 1;
                    }
                    if !closed { return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false; }
                    let parent = if stack.len > 0 { stack[stack.len - 1] } else { -1 };
                    // The parent -1 case: a comment before the root is a fault
                    // only when it is not the declaration space; XML puts
                    // comments before the root in the prolog, so the tree
                    // drops them when the root is not open yet.
                    if parent >= 0 {
                        append_node(nodes, KIND_COMMENT, s[0..0], s[pos + 4..j], parent);
                    } else if root_id >= 0 {
                        return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false;
                    }
                    pos = j + 3;
                } else if pos + 8 < s.len && s[pos + 2] == '[' && s[pos + 3] == 'C' && s[pos + 4] == 'D' && s[pos + 5] == 'A' && s[pos + 6] == 'T' && s[pos + 7] == 'A' && s[pos + 8] == '[' {
                    // A CDATA section: find "]]>".
                    var j = pos + 9;
                    var closed = false;
                    while j + 2 < s.len {
                        if s[j] == ']' && s[j + 1] == ']' && s[j + 2] == '>' { closed = true; break; }
                        j += 1;
                    }
                    if !closed { return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false; }
                    if stack.len == 0 { return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false; }
                    append_node(nodes, KIND_CDATA, s[0..0], s[pos + 9..j], stack[stack.len - 1]);
                    pos = j + 3;
                } else {
                    // A DOCTYPE or another <!...> construct: skip to '>'.
                    // A nested internal subset in [ ] is skipped too.
                    var j = pos + 2;
                    var depth = 0;
                    var closed = false;
                    while j < s.len {
                        if s[j] == '[' { depth += 1; }
                        if s[j] == ']' { depth -= 1; }
                        if s[j] == '>' && depth == 0 { closed = true; break; }
                        j += 1;
                    }
                    if !closed { return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false; }
                    pos = j + 1;
                }
            } else if c == '?' {
                // A processing instruction: find "?>".
                var j = pos + 2;
                var closed = false;
                while j + 1 < s.len {
                    if s[j] == '?' && s[j + 1] == '>' { closed = true; break; }
                    j += 1;
                }
                if !closed { return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false; }
                let name_end = read_name(s, pos + 2);
                if name_end < 0 || name_end > j { return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false; }
                // The declaration is a PI whose target is xml. The tree
                // drops it.
                let target = s[pos + 2..name_end];
                let parent = if stack.len > 0 { stack[stack.len - 1] } else { -1 };
                if !(target.len == 3 && (target == "xml" || target == "XML")) {
                    if parent >= 0 {
                        append_node(nodes, KIND_PI, target, s[name_end + 1..j], parent);
                    } else if root_id >= 0 {
                        return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false;
                    }
                }
                pos = j + 2;
            } else {
                // An open tag.
                if stack.len >= MAX_DEPTH { return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false; }
                let name_end = read_name(s, pos + 1);
                if name_end < 0 { return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false; }
                let parent = if stack.len > 0 { stack[stack.len - 1] } else { -1 };
                let id = append_node(nodes, KIND_ELEMENT, s[pos + 1..name_end], s[0..0], parent);
                if parent < 0 {
                    // A second root, or a root after other content, is a fault.
                    if root_id >= 0 { return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false; }
                    root_id = id;
                }
                // The attributes.
                var attr_start: i32 = attrs.len as i32;
                let after, self_closing, aok = scan_attrs(s, name_end, attrs);
                if !aok { return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false; }
                var j = after;
                nodes[id].attr_start = attr_start;
                nodes[id].attr_count = attrs.len as i32 - attr_start;
                if self_closing {
                    if stack.len == 0 && root_id == id { root_done = true; }
                } else {
                    stack.push(id);
                }
                pos = j;
            }
        } else {
            // Text up to the next '<'.
            var end = pos;
            while end < s.len && s[end] != '<' { end += 1; }
            let text = s[pos..end];
            // Whitespace-only text outside the root is the prolog. In the
            // root it is a text node.
            if stack.len > 0 {
                if !valid_entities(text) { return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false; }
                append_node(nodes, KIND_TEXT, s[0..0], text, stack[stack.len - 1]);
            } else {
                var only_space = true;
                for ch in text {
                    if !is_space(ch) { only_space = false; break; }
                }
                if !only_space {
                    // Text before the root is a fault; after the root the
                    // root_done branch catches it first.
                    if root_id >= 0 { return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false; }
                    return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false;
                }
            }
            pos = end;
        }
    }
    if root_id < 0 || stack.len > 0 || !root_done {
        return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false;
    }
    if !resolve_names(nodes, attrs) {
        return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false;
    }
    return Doc { nodes: nodes[..], attrs: attrs[..], root: root_id }, true;
}

// scan_attrs reads the attributes of a tag. It gives the place after the
// tag, the self-closing flag, and the fault flag. The attributes go
// into the array of the caller with the raw names.
fn scan_attrs(s: const u8[:], pos: i64, attrs: Attr[>..]&) -> i64, bool, bool {
    var j = pos;
    var first = attrs.len;
    var self_closing = false;
    while j < s.len {
        while j < s.len && is_space(s[j]) { j += 1; }
        if j >= s.len { return j, self_closing, false; }
        if s[j] == '>' { j += 1; break; }
        if s[j] == '/' {
            if j + 1 >= s.len || s[j + 1] != '>' { return j, self_closing, false; }
            self_closing = true;
            j += 2;
            break;
        }
        let an_end = read_name(s, j);
        if an_end < 0 { return j, self_closing, false; }
        let aname = s[j..an_end];
        var k = an_end;
        while k < s.len && is_space(s[k]) { k += 1; }
        if k >= s.len || s[k] != '=' { return j, self_closing, false; }
        k += 1;
        while k < s.len && is_space(s[k]) { k += 1; }
        if k >= s.len || (s[k] != '"' && s[k] != '\'') { return j, self_closing, false; }
        let quote = s[k];
        k += 1;
        var vend = k;
        while vend < s.len && s[vend] != quote {
            if s[vend] == '<' { return j, self_closing, false; }
            vend += 1;
        }
        if vend >= s.len { return j, self_closing, false; }
        if !valid_entities(s[k..vend]) { return j, self_closing, false; }
        // A duplicate attribute name is a fault.
        var d = 0;
        while d < attrs.len - first {
            if attrs[first + d].name == aname { return j, self_closing, false; }
            d += 1;
        }
        attrs.push(Attr { name: aname, value: s[k..vend], uri: "", local: aname });
        j = vend + 1;
    }
    return j, self_closing, true;
}

// scope_lookup gives the namespace that a prefix names in the scope of
// the node. It walks the node and its ancestors. The default namespace
// has the empty prefix. The prefix "xml" always names the namespace of
// XML. A prefix without a declaration gives false.
fn scope_lookup(nodes: Node[>..]&, attrs: Attr[>..]&, node_id: i32, prefix: const u8[:]) -> const u8[:], bool {
    if prefix == "xml" { return XML_NS, true; }
    var cur = node_id;
    while cur >= 0 {
        let n = nodes[cur];
        var i = 0;
        while i < n.attr_count {
            let a = attrs[n.attr_start + i];
            if prefix.len == 0 {
                if a.name == "xmlns" { return a.value, true; }
            } else if a.name.len == prefix.len + 6 && a.name[0..6] == "xmlns:" && a.name[6..] == prefix {
                return a.value, true;
            }
            i += 1;
        }
        cur = n.parent;
    }
    return "", false;
}

// resolve_names gives every element and attribute its namespace and its
// local name. A prefix without a declaration is a fault.
fn resolve_names(nodes: Node[>..]&, attrs: Attr[>..]&) -> bool {
    var i: i32 = 0;
    while i < nodes.len as i32 {
        let n = nodes[i];
        if n.kind == KIND_ELEMENT {
            let colon = find_colon(n.name);
            if colon < 0 {
                nodes[i].local = n.name;
                let uri, found = scope_lookup(nodes, attrs, i, "");
                if !found { nodes[i].uri = ""; } else { nodes[i].uri = uri; }
            } else {
                let prefix = n.name[0..colon];
                let uri, found = scope_lookup(nodes, attrs, i, prefix);
                if !found { return false; }
                nodes[i].uri = uri;
                nodes[i].local = n.name[colon + 1..];
            }
            var a = 0;
            while a < n.attr_count {
                let id = n.attr_start + a;
                let aname = attrs[id].name;
                let colon = find_colon(aname);
                if colon < 0 {
                    // An attribute without a prefix has no namespace.
                    attrs[id].local = aname;
                    attrs[id].uri = "";
                } else if aname.len >= 6 && aname[0..6] == "xmlns:" {
                    attrs[id].uri = XMLNS_NS;
                    attrs[id].local = aname[6..];
                } else {
                    let prefix = aname[0..colon];
                    let uri, found = scope_lookup(nodes, attrs, i, prefix);
                    if !found { return false; }
                    attrs[id].uri = uri;
                    attrs[id].local = aname[colon + 1..];
                }
                a += 1;
            }
        }
        i += 1;
    }
    return true;
}
