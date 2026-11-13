// The matcher of the path language of the xml package.
//
namespace xml;

import std;
import tree;

// path_attr_match says whether the attribute matches the key of a
// predicate. The key is a local name or a name of the form {uri}local.
// A namespace declaration is not an attribute, as in Python.
fn path_attr_match(a: Attr&, key: const u8[:]) -> bool {
    if a.name == "xmlns" { return false; }
    if a.name.len > 6 && a.name[0..6] == "xmlns:" { return false; }
    if key.len > 0 && key[0] == '{' {
        var e: i64 = 1;
        while e < key.len && key[e] != '}' { e += 1; }
        if e < key.len { return a.uri == key[1..e] && a.local == key[e + 1..]; }
    }
    return a.uri.len == 0 && a.local == key;
}

// path_same_tag says whether the element has the same name as the
// other element.
fn path_same_tag(doc: Doc&, a: i32, b: i32) -> bool {
    return doc.nodes[a].uri == doc.nodes[b].uri && doc.nodes[a].local == doc.nodes[b].local;
}

// path_index_step says whether the element is the element at the place
// among the siblings with the same name. The place counts from the
// start when it is not negative, and from the end when it is.
fn path_index_step(doc: Doc&, root: i32, id: i32, index: i64) -> bool {
    // The parent map of Python starts at the search element.
    if id == root { return false; }
    let parent = doc.nodes[id].parent;
    if parent < 0 { return false; }
    var count: i64 = 0;
    var place: i64 = -1;
    var c = doc.nodes[parent].first_child;
    while c >= 0 {
        if doc.nodes[c].kind == KIND_ELEMENT && path_same_tag(doc, c, id) {
            if c == id { place = count; }
            count += 1;
        }
        c = doc.nodes[c].next_sibling;
    }
    if place < 0 { return false; }
    if index >= 0 { return place == index; }
    // A negative place counts from the end.
    return count + index == place;
}

// path_has_child says whether the element has a child element with the
// name.
fn path_has_child(doc: Doc&, id: i32, tag: const u8[:]) -> bool {
    var c = doc.nodes[id].first_child;
    while c >= 0 {
        let n = doc.nodes[c];
        if n.kind == KIND_ELEMENT && path_tag_match(n.uri, n.local, tag) { return true; }
        c = n.next_sibling;
    }
    return false;
}

// path_child_text says whether a child element with the name has the
// text. When same is true, it looks for a child with that text. When
// same is false, it looks for a child with another text.
fn path_child_text(doc: Doc&, id: i32, tag: const u8[:], want: const u8[:], same: bool) -> bool {
    var c = doc.nodes[id].first_child;
    while c >= 0 {
        let n = doc.nodes[c];
        if n.kind == KIND_ELEMENT && path_tag_match(n.uri, n.local, tag) {
            var text: u8[>..] = [];
            if !iter_text(text, doc, c) { return false; }
            if (text[..] == want) == same { return true; }
        }
        c = n.next_sibling;
    }
    return false;
}

// path_desc_walk writes the descendants of the element with the name
// into out. The descendants come in document order.
recursive fn path_desc_walk(doc: Doc&, id: i32, tag: const u8[:], out: i32[>..]&) {
    var c = doc.nodes[id].first_child;
    while c >= 0 {
        let n = doc.nodes[c];
        if n.kind == KIND_ELEMENT && path_tag_match(n.uri, n.local, tag) { out.push(c); }
        path_desc_walk(doc, c, tag, out);
        c = n.next_sibling;
    }
}

// path_step runs one step over the nodes and writes the result into out.
// The root is the element where the search began.
fn path_step(doc: Doc&, root: i32, cur: i32[>..]&, s: Step, out: i32[>..]&) -> bool {
    var seen: u8[>..] = [];
    if s.kind == S_PARENT {
        var z = 0;
        while z < doc.nodes.len { seen.push(0 as u8); z += 1; }
    }
    var k = 0;
    while k < cur.len {
        let id = cur[k];
        k += 1;
        if s.kind == S_CHILD || s.kind == S_STAR {
            var c = doc.nodes[id].first_child;
            while c >= 0 {
                let n = doc.nodes[c];
                if n.kind == KIND_ELEMENT
                    && (s.kind == S_STAR || path_tag_match(n.uri, n.local, s.tag)) {
                    out.push(c);
                }
                c = n.next_sibling;
            }
        } else if s.kind == S_SELF {
            out.push(id);
        } else if s.kind == S_PARENT {
            let parent = doc.nodes[id].parent;
            if id != root && parent >= 0 && seen[parent as i64] == 0 {
                seen[parent as i64] = 1;
                out.push(parent);
            }
        } else if s.kind == S_DESC {
            path_desc_walk(doc, id, s.tag, out);
        } else if s.kind == S_HAS_ATTR {
            var a = 0;
            while a < doc.nodes[id].attr_count {
                let at = doc.attrs[doc.nodes[id].attr_start + a];
                if path_attr_match(at, s.key) { out.push(id); break; }
                a += 1;
            }
        } else if s.kind == S_ATTR_EQ || s.kind == S_ATTR_NE {
            var buf: u8[>..] = [];
            var a = 0;
            var found = false;
            while a < doc.nodes[id].attr_count {
                let at = doc.attrs[doc.nodes[id].attr_start + a];
                if path_attr_match(at, s.key) {
                    if !decode_attr(buf, at.value) { return false; }
                    found = true;
                    break;
                }
                a += 1;
            }
            if found && ((buf[..] == s.value) == (s.kind == S_ATTR_EQ)) { out.push(id); }
        } else if s.kind == S_HAS_CHILD {
            if path_has_child(doc, id, s.tag) { out.push(id); }
        } else if s.kind == S_CHILD_EQ || s.kind == S_CHILD_NE {
            if path_child_text(doc, id, s.tag, s.value, s.kind == S_CHILD_EQ) { out.push(id); }
        } else if s.kind == S_TEXT_EQ || s.kind == S_TEXT_NE {
            var text: u8[>..] = [];
            if !iter_text(text, doc, id) { return false; }
            if (text[..] == s.value) == (s.kind == S_TEXT_EQ) { out.push(id); }
        } else if s.kind == S_INDEX || s.kind == S_LAST {
            if path_index_step(doc, root, id, s.index) { out.push(id); }
        }
    }
    return true;
}

// path_sig writes the signature of a predicate. The signature holds
// one sign for each token of the predicate. A name gives a dash, a
// quoted text gives a quote, and every other token gives its own text.
fn path_sig(ptoks: Tok[>..]&, out: u8[>..]&) {
    var i = 0;
    while i < ptoks.len {
        let t = ptoks[i];
        i += 1;
        if t.ttype == "" && t.tag == "" { continue; }
        if t.ttype == "" {
            out.push('-');
        } else {
            out.append(t.ttype);
        }
    }
}

// path_pred_at gives the n-th part of a predicate. The parts are the
// texts of the tokens of the predicate.
fn path_pred_at(ptoks: Tok[>..]&, n: i64) -> const u8[:] {
    var i = 0;
    var count: i64 = 0;
    while i < ptoks.len {
        let t = ptoks[i];
        i += 1;
        if t.ttype == "" && t.tag == "" { continue; }
        if count == n {
            return t.tag;
        }
        count += 1;
    }
    return "";
}

// path_pred_count gives the number of the parts of a predicate.
fn path_pred_count(ptoks: Tok[>..]&) -> i64 {
    var i = 0;
    var count: i64 = 0;
    while i < ptoks.len {
        let t = ptoks[i];
        i += 1;
        if t.ttype == "" && t.tag == "" { continue; }
        count += 1;
    }
    return count;
}

// path_predicate reads the tokens of a predicate and writes the step of
// the predicate. It gives false where Python raises a SyntaxError.
fn path_predicate(steps: Step[>..]&, ptoks: Tok[>..]&) -> bool {
    var sig: u8[>..] = [];
    path_sig(ptoks, sig);
    let parts = path_pred_count(ptoks);
    if sig == "@-" {
        // [@attribute]
        if parts < 2 { return false; }
        steps.push(Step { kind: S_HAS_ATTR, tag: "", key: path_pred_at(ptoks, 1),
            value: "", index: 0 });
        return true;
    }
    if sig == "@-='" || sig == "@-!='" {
        // [@attribute='value'] or [@attribute!='value']
        if parts < 4 { return false; }
        let kind: i32 = if sig == "@-='" { S_ATTR_EQ as i32 } else { S_ATTR_NE as i32 };
        steps.push(Step { kind: kind, tag: "", key: path_pred_at(ptoks, 1),
            value: path_pred_at(ptoks, parts - 1), index: 0 });
        return true;
    }
    if sig == "-" && parts >= 1 {
        let first = path_pred_at(ptoks, 0);
        if !path_is_number(first) {
            // [tag]
            steps.push(Step { kind: S_HAS_CHILD, tag: first, key: "", value: "", index: 0 });
            return true;
        }
    }
    if sig == ".='" || sig == ".!='" || sig == "-='" || sig == "-!='" {
        if parts < 3 { return false; }
        let first = path_pred_at(ptoks, 0);
        if sig == "-='" || sig == "-!='" {
            if path_is_number(first) { return false; }
        }
        var kind: i32 = 0;
        if sig == ".='" { kind = S_TEXT_EQ as i32; }
        else if sig == ".!='" { kind = S_TEXT_NE as i32; }
        else if sig == "-='" { kind = S_CHILD_EQ as i32; }
        else { kind = S_CHILD_NE as i32; }
        steps.push(Step { kind: kind, tag: first, key: "",
            value: path_pred_at(ptoks, parts - 1), index: 0 });
        return true;
    }
    if sig == "-" {
        // [index]
        if parts < 1 { return false; }
        let n = path_number(path_pred_at(ptoks, 0));
        if n < 1 { return false; }
        steps.push(Step { kind: S_INDEX, tag: "", key: "", value: "", index: n - 1 });
        return true;
    }
    if sig == "-()" {
        // [last()]
        if parts < 2 { return false; }
        if path_pred_at(ptoks, 0) != "last" { return false; }
        steps.push(Step { kind: S_LAST, tag: "", key: "", value: "", index: -1 });
        return true;
    }
    if sig == "-()-" {
        // [last()-index]
        if parts < 3 { return false; }
        if path_pred_at(ptoks, 0) != "last" { return false; }
        let text = path_pred_at(ptoks, 2);
        if !path_is_number(text) { return false; }
        let n = path_number(text) - 1;
        if n > -2 { return false; }
        steps.push(Step { kind: S_LAST, tag: "", key: "", value: "", index: n });
        return true;
    }
    return false;
}

// path_build reads the tokens and writes the steps of the path. It
// gives false where Python raises a SyntaxError.
fn path_build(steps: Step[>..]&, toks: Tok[>..]&, ptoks: Tok[>..]&) -> bool {
    var i: i64 = 0;
    if toks.len == 0 { return false; }
    while i < toks.len {
        let t = toks[i];
        i += 1;
        if t.ttype == "" {
            // A space gives a child step with an empty name, as in Python.
            // The step matches nothing.
            steps.push(Step { kind: S_CHILD, tag: t.tag, key: "", value: "", index: 0 });
        } else if t.ttype == "*" {
            steps.push(Step { kind: S_STAR, tag: "", key: "", value: "", index: 0 });
        } else if t.ttype == "." {
            steps.push(Step { kind: S_SELF, tag: "", key: "", value: "", index: 0 });
        } else if t.ttype == ".." {
            steps.push(Step { kind: S_PARENT, tag: "", key: "", value: "", index: 0 });
        } else if t.ttype == "//" {
            // The descendant step reads the next token.
            if i >= toks.len { return false; }
            let nt = toks[i];
            i += 1;
            if nt.ttype == "*" {
                steps.push(Step { kind: S_DESC, tag: "*", key: "", value: "", index: 0 });
            } else if nt.ttype == "" {
                steps.push(Step { kind: S_DESC, tag: nt.tag, key: "", value: "", index: 0 });
            } else {
                return false;
            }
        } else if t.ttype == "[" {
            // The predicate reads the tokens up to the closing bracket.
            ptoks.clear();
            var closed = false;
            while i < toks.len {
                let p = toks[i];
                i += 1;
                if p.ttype == "]" { closed = true; break; }
                ptoks.push(p);
            }
            if !closed { return false; }
            if !path_predicate(steps, ptoks) { return false; }
        } else {
            // A token that has no step.
            return false;
        }
        // A slash between the steps.
        if i < toks.len && toks[i].ttype == "/" { i += 1; }
    }
    return true;
}

// path_ids writes the places of the nodes that match the path into out.
// It gives false where Python raises a SyntaxError.
fn path_ids(doc: Doc&, id: i32, path: const u8[:], pn: const u8[:][:], pu: const u8[:][:], out: i32[>..]&) -> bool {
    if path.len == 0 { return false; }
    // A path that starts with a slash is an absolute path. Python refuses
    // it on an element.
    if path[0] == '/' { return false; }
    // A path that ends with a slash takes every child.
    var buf: u8[>..] = [];
    buf.append(path);
    if path[path.len - 1] == '/' { buf.push('*'); }
    let text = buf[..];
    var toks: Tok[>..] = [];
    var kbuf: u8[>..] = [];
    if !path_tokenize(toks, text, kbuf, pn, pu) { return false; }
    var steps: Step[>..] = [];
    var ptoks: Tok[>..] = [];
    if !path_build(steps, toks, ptoks) { return false; }
    var cur: i32[>..] = [];
    cur.push(id);
    var next: i32[>..] = [];
    var k = 0;
    while k < steps.len {
        next.clear();
        if !path_step(doc, id, cur, steps[k], next) { return false; }
        cur.clear();
        var j = 0;
        while j < next.len {
            cur.push(next[j]);
            j += 1;
        }
        k += 1;
    }
    var m = 0;
    while m < cur.len {
        out.push(cur[m]);
        m += 1;
    }
    return true;
}

// find_path gives the first node that matches the path. The path may
// hold the whole language of ElementPath. It gives false when no node
// matches and when the path is wrong.
fn find_path(doc: Doc&, id: i32, path: const u8[:]) -> i32, bool {
    return find_path_ns(doc, id, path, NO_PREFIXES, NO_PREFIXES);
}

// find_path_ns is find_path with a map of prefixes: the names and the
// uris are two lists of the same length. The prefix "" gives the default
// namespace for a name with no prefix, as the namespaces argument of
// ElementTree does.
fn find_path_ns(doc: Doc&, id: i32, path: const u8[:], prefixes: const u8[:][:], uris: const u8[:][:]) -> i32, bool {
    var out: i32[>..] = [];
    if !path_ids(doc, id, path, prefixes, uris, out) { return -1, false; }
    if out.len == 0 { return -1, false; }
    return out[0], true;
}

// findall_path writes the places of the nodes that match the path into
// out. It gives the count of the matches. It gives -1 where Python
// raises a SyntaxError.
fn findall_path(doc: Doc&, id: i32, path: const u8[:], out: i32[>..]&) -> i64 {
    return findall_path_ns(doc, id, path, NO_PREFIXES, NO_PREFIXES, out);
}

// findall_path_ns is findall_path with a map of prefixes.
fn findall_path_ns(doc: Doc&, id: i32, path: const u8[:], prefixes: const u8[:][:], uris: const u8[:][:], out: i32[>..]&) -> i64 {
    var ids: i32[>..] = [];
    if !path_ids(doc, id, path, prefixes, uris, ids) { return -1; }
    var i = 0;
    while i < ids.len {
        out.push(ids[i]);
        i += 1;
    }
    return ids.len;
}
