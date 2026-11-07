// The parser with a target and the reader of the events of a document.
//
// iterparse reads a document event by event. The block that the caller
// gives after the call gets every event as it is read, so a fault after
// some events gives those events first and then false. The names of the
// events are resolved: a name with a namespace has the form {uri}local, as
// in ElementTree. The reader is the pull reader, so its prolog rules are
// the ones of the pull reader. With build set, the call also fills the
// tree of the caller with the elements, the attributes and the text, as
// iterparse and TreeBuilder of Python do.
namespace xml;

import std;
import tree;
import pull;
import build_tree;

// The kinds of an event of iterparse.
const TEV_START = 0;
const TEV_END = 1;
const TEV_ATTR = 2;
const TEV_START_NS = 3;
const TEV_END_NS = 4;
const TEV_COMMENT = 5;
const TEV_PI = 6;
const TEV_TEXT = 7;

// tg_lookup gives the uri of a prefix, from the innermost scope out.
fn tg_lookup(pfxs: const u8[:][>..]&, uris: const u8[:][>..]&, prefix: const u8[:]) -> const u8[:], bool {
    if prefix == "xml" { return XML_NS, true; }
    var i = pfxs.len;
    while i > 0 {
        i -= 1;
        if pfxs[i] == prefix { return uris[i], true; }
    }
    return "", false;
}

// iterparse reads the document and gives the events to the block. The
// block has the form { kind, id, a, b => ... } with these values:
//   TEV_START: id is the new element when build is set, else -1; a is the
//     tag. The attributes follow as TEV_ATTR events.
//   TEV_ATTR: a is the name, b is the decoded value.
//   TEV_END: id and a are the ones of the matching start event.
//   TEV_START_NS: a is the prefix and b is the uri. It comes before the
//     start event of the element. TEV_END_NS: a is the prefix. It comes
//     after the end event.
//   TEV_COMMENT: a is the text. TEV_PI: a is the target and b the data.
//   TEV_TEXT: a is the decoded text of one run, with CDATA in it.
// With build set, the tree goes into nodes, attrs and text. The result
// is the Doc of that tree. A fault gives false.
fn iterparse<F>(s: const u8[:], build: bool, nodes: Node[>..]&, attrs: Attr[>..]&, text: u8[>..]&) -> Doc, bool {
    let fail = Doc { nodes: nodes[..], attrs: attrs[..], root: -1 };
    var r = reader(s);
    var open: Open[>..] = [];
    var pattrs: Attr[>..] = [];
    var s_pfx: const u8[:][>..] = [];
    var s_uri: const u8[:][>..] = [];
    var kbuf: u8[>..] = [];
    var ubuf: u8[>..] = [];
    // The stacks of the open elements: the key, the node, and the count of
    // declarations of each.
    var o_key: const u8[:][>..] = [];
    var o_id: i32[>..] = [];
    var o_decl: i64[>..] = [];
    var root: i32 = -1;
    while true {
        let ev, ok = next(r, open, pattrs);
        if !ok { return fail, false; }
        if ev.kind == EV_EOF { break; }
        if ev.kind == EV_START {
            // The declarations of the element come first.
            var decls: i64 = 0;
            var i = 0;
            while i < pattrs.len {
                let a = pattrs[i];
                i += 1;
                let is_def = a.name == "xmlns";
                if !is_def && !(a.name.len > 6 && a.name[0..6] == "xmlns:") { continue; }
                let prefix = if is_def { a.name[0..0] } else { a.name[6..] };
                let us = ubuf.len;
                if !decode_attr(ubuf, a.value) { return fail, false; }
                let uri = ubuf[us..ubuf.len];
                s_pfx.push(prefix);
                s_uri.push(uri);
                decls += 1;
                F(TEV_START_NS, -1, prefix, uri);
            }
            // The tag.
            let eprefix, elocal = ns_split(ev.name);
            let eu, efound = tg_lookup(s_pfx, s_uri, eprefix);
            if eprefix.len > 0 && !efound { return fail, false; }
            let euri = if efound { eu } else { "" };
            let key = c14_like_key(kbuf, euri, elocal);
            var id: i32 = -1;
            if build {
                id = element(nodes, text, key);
                if o_id.len > 0 {
                    append(nodes, o_id[o_id.len - 1], id);
                } else {
                    root = id;
                }
            }
            o_key.push(key);
            o_id.push(id);
            o_decl.push(decls);
            F(TEV_START, id, key, "");
            i = 0;
            while i < pattrs.len {
                let a = pattrs[i];
                i += 1;
                if a.name == "xmlns" || (a.name.len > 6 && a.name[0..6] == "xmlns:") { continue; }
                let aprefix, alocal = ns_split(a.name);
                let au, afound = tg_lookup(s_pfx, s_uri, aprefix);
                if aprefix.len > 0 && !afound { return fail, false; }
                let auri = if afound && aprefix.len > 0 { au } else { "" };
                let akey = c14_like_key(kbuf, auri, alocal);
                let vs = ubuf.len;
                if !decode_attr(ubuf, a.value) { return fail, false; }
                let value = ubuf[vs..ubuf.len];
                if build { set(nodes, attrs, text, id, akey, value); }
                F(TEV_ATTR, id, akey, value);
            }
        } else if ev.kind == EV_END {
            let key = o_key[o_key.len - 1];
            let id = o_id[o_id.len - 1];
            let decls = o_decl[o_decl.len - 1];
            o_key.pop();
            o_id.pop();
            o_decl.pop();
            F(TEV_END, id, key, "");
            var d: i64 = 0;
            while d < decls {
                F(TEV_END_NS, -1, s_pfx[s_pfx.len - 1], "");
                s_pfx.pop();
                s_uri.pop();
                d += 1;
            }
        } else if ev.kind == EV_TEXT || ev.kind == EV_CDATA {
            let ts = ubuf.len;
            if ev.kind == EV_TEXT {
                if !decode_entities(ubuf, ev.content) { return fail, false; }
            } else {
                var k = 0;
                while k < ev.content.len { k = put_literal(ubuf, ev.content, k, false); }
            }
            let chunk = ubuf[ts..ubuf.len];
            if build && chunk.len > 0 {
                let parent = o_id[o_id.len - 1];
                bt_put_text(nodes, text, parent, nodes[parent].last_child, chunk);
            }
            if chunk.len > 0 { F(TEV_TEXT, -1, chunk, ""); }
        } else if ev.kind == EV_COMMENT {
            F(TEV_COMMENT, -1, ev.content, "");
        } else if ev.kind == EV_PI {
            var from: i64 = 0;
            while from < ev.content.len && is_space(ev.content[from]) { from += 1; }
            F(TEV_PI, -1, ev.name, ev.content[from..]);
        }
    }
    return Doc { nodes: nodes[..], attrs: attrs[..], root: root }, true;
}

// c14_like_key writes {uri}local, or local, into the buffer.
fn c14_like_key(buf: u8[>..]&, uri: const u8[:], local: const u8[:]) -> const u8[:] {
    let start = buf.len;
    if uri.len > 0 {
        buf.push('{');
        buf.append(uri);
        buf.push('}');
    }
    buf.append(local);
    return buf[start..buf.len];
}
