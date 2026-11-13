// The attributes and the names of the xml package.
//
namespace xml;

import std;
import tree;

// scan_attrs reads the attributes of a tag. It gives the place after the
// tag, the self-closing flag, and the fault flag. The attributes go
// into the array of the caller with the raw names. White space must
// stand before each attribute.
fn scan_attrs(s: const u8[:], pos: i64, attrs: Attr[>..]&) -> i64, bool, bool {
    var j = pos;
    var first = attrs.len;
    var self_closing = false;
    var need_space = false;
    while j < s.len {
        let before = j;
        while j < s.len && is_space(s[j]) { j += 1; }
        if j >= s.len { return j, self_closing, false; }
        if s[j] == '>' { j += 1; break; }
        if s[j] == '/' {
            if j + 1 >= s.len || s[j + 1] != '>' { return j, self_closing, false; }
            self_closing = true;
            j += 2;
            break;
        }
        if need_space && j == before { return j, self_closing, false; }
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
        need_space = true;
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

// split_ok tests a raw name: at most one colon, and each part is a
// whole non-empty name with no colon. A name without a colon passes when
// it holds no colon at all.
fn split_ok(name: const u8[:]) -> bool {
    let colon = find_colon(name);
    if colon < 0 { return true; }
    let prefix = name[0..colon];
    let local = name[colon + 1..];
    if prefix.len == 0 || local.len == 0 { return false; }
    if find_colon(local) >= 0 { return false; }
    // Each part must read as one name. A colon is a name character here,
    // and the checks above leave none.
    return read_name(prefix, 0) == prefix.len && read_name(local, 0) == local.len;
}

// decl_ok tests one namespace declaration: the name is xmlns or
// xmlns:prefix, and the value is its URI.
fn decl_ok(name: const u8[:], uri: const u8[:]) -> bool {
    if uri == XMLNS_NS { return false; }
    if name == "xmlns" { return uri != XML_NS; }
    let prefix = name[6..];
    if prefix == "xmlns" || uri.len == 0 { return false; }
    if prefix == "xml" { return uri == XML_NS; }
    return uri != XML_NS;
}

// resolve_names gives every element and attribute its namespace and its
// local name. It refuses a prefix without a declaration, a bad name, a bad
// declaration, and two attributes with one expanded name.
fn resolve_names(nodes: Node[>..]&, attrs: Attr[>..]&) -> bool {
    var i: i32 = 0;
    while i < nodes.len as i32 {
        let n = nodes[i];
        if n.kind == KIND_ELEMENT {
            if !split_ok(n.name) { return false; }
            let colon = find_colon(n.name);
            if colon < 0 {
                nodes[i].local = n.name;
                let uri, found = scope_lookup(nodes, attrs, i, "");
                if !found { nodes[i].uri = ""; } else { nodes[i].uri = uri; }
            } else {
                let prefix = n.name[0..colon];
                if prefix == "xmlns" { return false; }
                let uri, found = scope_lookup(nodes, attrs, i, prefix);
                if !found { return false; }
                nodes[i].uri = uri;
                nodes[i].local = n.name[colon + 1..];
            }
            var a = 0;
            while a < n.attr_count {
                let id = n.attr_start + a;
                let aname = attrs[id].name;
                if !split_ok(aname) { return false; }
                let colon = find_colon(aname);
                if aname == "xmlns" {
                    if !decl_ok(aname, attrs[id].value) { return false; }
                    attrs[id].local = aname;
                    attrs[id].uri = "";
                } else if colon < 0 {
                    // An attribute without a prefix has no namespace.
                    attrs[id].local = aname;
                    attrs[id].uri = "";
                } else if aname[0..colon] == "xmlns" {
                    if !decl_ok(aname, attrs[id].value) { return false; }
                    attrs[id].uri = XMLNS_NS;
                    attrs[id].local = aname[6..];
                } else {
                    let prefix = aname[0..colon];
                    let uri, found = scope_lookup(nodes, attrs, i, prefix);
                    if !found { return false; }
                    attrs[id].uri = uri;
                    attrs[id].local = aname[colon + 1..];
                    // Two attributes with one expanded name are a fault.
                    var e = 0;
                    while e < a {
                        let other = attrs[n.attr_start + e];
                        if other.uri == uri && other.local == attrs[id].local { return false; }
                        e += 1;
                    }
                }
                a += 1;
            }
        }
        i += 1;
    }
    return true;
}
