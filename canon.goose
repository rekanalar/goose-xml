// The canonical form of the xml package.
//
// canonicalize writes a document in the C14N 2.0 form of
// xml.etree.ElementTree.canonicalize of Python 3.14. The rules follow
// the C14NWriterTarget class of that module, read from its source:
// the namespace declarations that an element needs, the sort order of the
// attributes, the escapes, the options with_comments, strip_text and
// rewrite_prefixes, and the lists exclude_tags, exclude_attrs,
// qname_aware_tags and qname_aware_attrs. A name in a list has the
// form {uri}local, or only local when it has no namespace.
namespace xml;

import std;
import tree;
import read;
import write;

// C14nOpts holds the options of canonicalize.
struct C14nOpts {
    with_comments: bool,
    strip_text: bool,
    rewrite_prefixes: bool,
}

// c14n_opts gives the defaults: no comments, no strip and no rewrite.
fn c14n_opts() -> C14nOpts {
    return C14nOpts { with_comments: false, strip_text: false, rewrite_prefixes: false };
}

// c14_cdata writes the text with the escapes of the canonical form.
fn c14_cdata(out: u8[>..]&, s: const u8[:]) {
    for c in s {
        if c == '&' { out.append("&amp;"); }
        else if c == '<' { out.append("&lt;"); }
        else if c == '>' { out.append("&gt;"); }
        else if c == '\r' { out.append("&#xD;"); }
        else { out.push(c); }
    }
}

// c14_attrib writes an attribute value with the escapes of the canonical
// form.
fn c14_attrib(out: u8[>..]&, s: const u8[:]) {
    for c in s {
        if c == '&' { out.append("&amp;"); }
        else if c == '<' { out.append("&lt;"); }
        else if c == '"' { out.append("&quot;"); }
        else if c == '\t' { out.append("&#x9;"); }
        else if c == '\n' { out.append("&#xA;"); }
        else if c == '\r' { out.append("&#xD;"); }
        else { out.push(c); }
    }
}

// c14_in says whether the list holds the key.
fn c14_in(list: const u8[:][:], key: const u8[:]) -> bool {
    var i: i64 = 0;
    while i < list.len {
        if list[i] == key { return true; }
        i += 1;
    }
    return false;
}

// c14_word says whether the byte can stand in a word of a QName text.
fn c14_word(c: u8) -> bool {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
        || c == '_' || c >= 128;
}

// c14_prefix_name says whether the text has the form word:word.
fn c14_prefix_name(s: const u8[:]) -> bool {
    var colon: i64 = -1;
    var i: i64 = 0;
    while i < s.len {
        if s[i] == ':' {
            if colon >= 0 { return false; }
            colon = i;
        } else if !c14_word(s[i]) {
            return false;
        }
        i += 1;
    }
    return colon > 0 && colon < s.len - 1;
}

// c14_key writes the key of a name: {uri}local, or local when the name
// has no namespace.
fn c14_key(buf: u8[>..]&, uri: const u8[:], local: const u8[:]) -> const u8[:] {
    let start = buf.len;
    if uri.len > 0 {
        buf.push('{');
        buf.append(uri);
        buf.push('}');
    }
    buf.append(local);
    return buf[start..buf.len];
}

// c14_split gives the uri and the local name of a key.
fn c14_split(key: const u8[:]) -> const u8[:], const u8[:] {
    return bt_split(key);
}

// c14_before says whether key a sorts before key b in the order of
// Python: the key is cut at the first closing brace and the parts compare
// as a list.
fn c14_before(a: const u8[:], b: const u8[:]) -> bool {
    var ia: i64 = -1;
    var ib: i64 = -1;
    var i: i64 = 0;
    while i < a.len { if a[i] == '}' { ia = i; break; } i += 1; }
    i = 0;
    while i < b.len { if b[i] == '}' { ib = i; break; } i += 1; }
    let a1 = if ia >= 0 { a[0..ia] } else { a };
    let b1 = if ib >= 0 { b[0..ib] } else { b };
    if a1 != b1 { return ts_less(a1, b1); }
    if ia < 0 { return ib >= 0; }
    if ib < 0 { return false; }
    return ts_less(a[ia + 1..], b[ib + 1..]);
}

// A scope stack holds the entries (uri, prefix) in frames. The frames
// start at the places that the frames array holds.

// c14_pop_frame removes the last frame.
fn c14_pop_frame(uris: const u8[:][>..]&, pfxs: const u8[:][>..]&, frames: i64[>..]&) {
    if frames.len == 0 { return; }
    let start = frames[frames.len - 1];
    frames.pop();
    while uris.len > start {
        uris.pop();
        pfxs.pop();
    }
}

// c14_first_prefix gives the prefix of the first entry for the uri, from
// the last frame to the first, as the namespace stack of Python.
fn c14_first_prefix(uris: const u8[:][>..]&, pfxs: const u8[:][>..]&, frames: i64[>..]&, uri: const u8[:]) -> const u8[:], bool {
    var f = frames.len;
    while f > 0 {
        f -= 1;
        let start = frames[f];
        let end = if f + 1 < frames.len { frames[f + 1] } else { uris.len };
        var i = start;
        while i < end {
            if uris[i] == uri { return pfxs[i], true; }
            i += 1;
        }
    }
    return "", false;
}

// c14_resolve gives the key {uri}name for the text prefix:name, or false
// when the prefix is not declared in scope.
fn c14_resolve(buf: u8[>..]&, uris: const u8[:][>..]&, pfxs: const u8[:][>..]&, frames: i64[>..]&, text: const u8[:]) -> const u8[:], bool {
    var c: i64 = 0;
    while c < text.len && text[c] != ':' { c += 1; }
    let prefix = text[0..c];
    let name = text[c + 1..];
    var f = frames.len;
    while f > 0 {
        f -= 1;
        let start = frames[f];
        let end = if f + 1 < frames.len { frames[f + 1] } else { uris.len };
        var i = start;
        while i < end {
            if pfxs[i] == prefix { return c14_key(buf, uris[i], name), true; }
            i += 1;
        }
    }
    return "", false;
}

// c14_qname gives the written name of a name, and records a new
// declaration when the name needs one. It is the _qname method of the
// target of Python. It gives false where Python raises an error.
fn c14_qname(qbuf: u8[>..]&, d_uris: const u8[:][>..]&, d_pfxs: const u8[:][>..]&, d_frames: i64[>..]&,
        n_uris: const u8[:][>..]&, n_pfxs: const u8[:][>..]&, n_frames: i64[>..]&,
        rewrite: bool, pm_uris: const u8[:][>..]&, pm_pfxs: const u8[:][>..]&, pbuf: u8[>..]&,
        uri: const u8[:], tag: const u8[:]) -> const u8[:], bool {
    // The prefixes of the declared stack, from the last frame.
    var seen: const u8[:][>..] = [];
    var seen_empty = false;
    var f = d_frames.len;
    while f > 0 {
        f -= 1;
        let start = d_frames[f];
        let end = if f + 1 < d_frames.len { d_frames[f + 1] } else { d_uris.len };
        var i = start;
        while i < end {
            let p = d_pfxs[i];
            var dup = false;
            var s: i64 = 0;
            while s < seen.len { if seen[s] == p { dup = true; break; } s += 1; }
            if d_uris[i] == uri && !dup {
                let at = qbuf.len;
                if p.len > 0 { qbuf.append(p); qbuf.push(':'); }
                qbuf.append(tag);
                return qbuf[at..qbuf.len], true;
            }
            if p.len == 0 { seen_empty = true; }
            seen.push(p);
            i += 1;
        }
    }
    // The uri goes into the buffer, so the scope stacks can hold it.
    let ustart = pbuf.len;
    pbuf.append(uri);
    let uri_kept = pbuf[ustart..pbuf.len];
    if rewrite {
        var idx: i64 = -1;
        var m: i64 = 0;
        while m < pm_uris.len { if pm_uris[m] == uri { idx = m; break; } m += 1; }
        if idx < 0 {
            idx = pm_uris.len;
            pm_uris.push(uri_kept);
            let pstart = pbuf.len;
            pbuf.append("n");
            var digits: u8[>..] = [];
            var v = idx;
            if v == 0 { digits.push('0'); }
            while v > 0 { digits.push(('0' as i64 + v % 10) as u8); v = v / 10; }
            var d = digits.len;
            while d > 0 { d -= 1; pbuf.push(digits[d]); }
            pm_pfxs.push(pbuf[pstart..pbuf.len]);
        }
        let prefix = pm_pfxs[idx];
        d_uris.push(uri_kept);
        d_pfxs.push(prefix);
        let at = qbuf.len;
        qbuf.append(prefix);
        qbuf.push(':');
        qbuf.append(tag);
        return qbuf[at..qbuf.len], true;
    }
    if uri.len == 0 && !seen_empty { return tag, true; }
    let p, found = c14_first_prefix(n_uris, n_pfxs, n_frames, uri);
    if found {
        d_uris.push(uri_kept);
        d_pfxs.push(p);
        if p.len == 0 { return tag, true; }
        let at = qbuf.len;
        qbuf.append(p);
        qbuf.push(':');
        qbuf.append(tag);
        return qbuf[at..qbuf.len], true;
    }
    if uri.len == 0 { return tag, true; }
    return "", false;
}

// c14_strip cuts the white space at both ends of the text.
fn c14_strip(s: const u8[:]) -> const u8[:] {
    var a: i64 = 0;
    var b = s.len;
    while a < b && is_space(s[a]) { a += 1; }
    while b > a && is_space(s[b - 1]) { b -= 1; }
    return s[a..b];
}

// c14_start writes an open tag with the declarations that it needs. It
// is the _start method of the target of Python. The text qname_text is
// empty, or it is the QName text of a qname aware element.
fn c14_start(out: u8[>..]&, doc: Doc&, id: i32, qname_text: const u8[:], opts: C14nOpts,
        exclude_attrs: const u8[:][:], qname_attrs: const u8[:][:],
        d_uris: const u8[:][>..]&, d_pfxs: const u8[:][>..]&, d_frames: i64[>..]&,
        n_uris: const u8[:][>..]&, n_pfxs: const u8[:][>..]&, n_frames: i64[>..]&,
        pm_uris: const u8[:][>..]&, pm_pfxs: const u8[:][>..]&, pbuf: u8[>..]&,
        preserve: u8[>..]&) -> bool {
    let n = doc.nodes[id];
    var kbuf: u8[>..] = [];
    var vbuf: u8[>..] = [];
    var qbuf: u8[>..] = [];
    var a_keys: const u8[:][>..] = [];
    var a_vals: const u8[:][>..] = [];
    var i = 0;
    while i < n.attr_count {
        let a = doc.attrs[n.attr_start + i];
        i += 1;
        if is_ns_decl(a) { continue; }
        let key = c14_key(kbuf, a.uri, a.local);
        if c14_in(exclude_attrs, key) { continue; }
        let vs = vbuf.len;
        if !decode_attr(vbuf, a.value) { return false; }
        a_keys.push(key);
        a_vals.push(vbuf[vs..vbuf.len]);
    }
    let tag_key = c14_key(kbuf, n.uri, n.local);
    // The names that need a written form.
    var names: const u8[:][>..] = [];
    names.push(tag_key);
    var k: i64 = 0;
    while k < a_keys.len {
        var dup = false;
        var m: i64 = 0;
        while m < names.len { if names[m] == a_keys[k] { dup = true; break; } m += 1; }
        if !dup { names.push(a_keys[k]); }
        k += 1;
    }
    // The QName texts that resolve to names.
    var r_from: const u8[:][>..] = [];
    var r_to: const u8[:][>..] = [];
    var rbuf: u8[>..] = [];
    if qname_text.len > 0 {
        let key, ok = c14_resolve(rbuf, n_uris, n_pfxs, n_frames, qname_text);
        if !ok { return false; }
        r_from.push(qname_text);
        r_to.push(key);
    }
    var qflag: u8[>..] = [];
    k = 0;
    while k < a_keys.len {
        var flag = 0;
        if c14_in(qname_attrs, a_keys[k]) {
            flag = 1;
            if c14_prefix_name(a_vals[k]) {
                let key, ok = c14_resolve(rbuf, n_uris, n_pfxs, n_frames, a_vals[k]);
                if !ok { return false; }
                r_from.push(a_vals[k]);
                r_to.push(key);
            }
        }
        qflag.push(flag as u8);
        k += 1;
    }
    var r: i64 = 0;
    while r < r_to.len {
        var dup = false;
        var m: i64 = 0;
        while m < names.len { if names[m] == r_to[r] { dup = true; break; } m += 1; }
        if !dup { names.push(r_to[r]); }
        r += 1;
    }
    // Assign the prefixes in the order of the used uris.
    var x: i64 = 1;
    while x < names.len {
        var y = x;
        while y > 0 && c14_before(names[y], names[y - 1]) {
            let t = names[y];
            names[y] = names[y - 1];
            names[y - 1] = t;
            y -= 1;
        }
        x += 1;
    }
    var p_text: const u8[:][>..] = [];
    var p_tag: const u8[:][>..] = [];
    var p_uri: const u8[:][>..] = [];
    var q: i64 = 0;
    while q < names.len {
        let uri, tag = c14_split(names[q]);
        let text, ok = c14_qname(qbuf, d_uris, d_pfxs, d_frames, n_uris, n_pfxs, n_frames,
            opts.rewrite_prefixes, pm_uris, pm_pfxs, pbuf, uri, tag);
        if !ok { return false; }
        p_text.push(text);
        p_tag.push(tag);
        p_uri.push(uri);
        q += 1;
    }
    // The declarations that this element made, in the order of the name.
    var dnames: const u8[:][>..] = [];
    var dvals: const u8[:][>..] = [];
    var dbuf: u8[>..] = [];
    var e = d_frames[d_frames.len - 1];
    while e < d_uris.len {
        let s = dbuf.len;
        if d_pfxs[e].len > 0 {
            dbuf.append("xmlns:");
            dbuf.append(d_pfxs[e]);
        } else {
            dbuf.append("xmlns");
        }
        dnames.push(dbuf[s..dbuf.len]);
        dvals.push(d_uris[e]);
        e += 1;
    }
    x = 1;
    while x < dnames.len {
        var y = x;
        while y > 0 && (ts_less(dnames[y], dnames[y - 1])
            || (dnames[y] == dnames[y - 1] && ts_less(dvals[y], dvals[y - 1]))) {
            let t = dnames[y];
            dnames[y] = dnames[y - 1];
            dnames[y - 1] = t;
            let tv = dvals[y];
            dvals[y] = dvals[y - 1];
            dvals[y - 1] = tv;
            y -= 1;
        }
        x += 1;
    }
    // The attributes in the order of the key and then the value.
    var order: i64[>..] = [];
    k = 0;
    while k < a_keys.len { order.push(k); k += 1; }
    x = 1;
    while x < order.len {
        var y = x;
        while y > 0 {
            let l = order[y];
            let rr = order[y - 1];
            let less = ts_less(a_keys[l], a_keys[rr])
                || (a_keys[l] == a_keys[rr] && ts_less(a_vals[l], a_vals[rr]));
            if !less { break; }
            order[y] = rr;
            order[y - 1] = l;
            y -= 1;
        }
        x += 1;
    }
    // Honour xml:space.
    var space_at: i64 = -1;
    k = 0;
    while k < a_keys.len {
        if a_keys[k] == "{http://www.w3.org/XML/1998/namespace}space" { space_at = k; }
        k += 1;
    }
    var keep = preserve[preserve.len - 1] != 0;
    if space_at >= 0 && a_vals[space_at].len > 0 { keep = a_vals[space_at] == "preserve"; }
    preserve.push(if keep { 1 } else { 0 });
    // Write the tag.
    out.push('<');
    var ti: i64 = 0;
    while ti < names.len { if names[ti] == tag_key { break; } ti += 1; }
    out.append(p_text[ti]);
    var d: i64 = 0;
    while d < dnames.len {
        out.push(' ');
        out.append(dnames[d]);
        out.append("=\"");
        c14_attrib(out, dvals[d]);
        out.push('"');
        d += 1;
    }
    var o: i64 = 0;
    while o < order.len {
        let ai = order[o];
        o += 1;
        var v = a_vals[ai];
        if qflag[ai] != 0 {
            var rf: i64 = 0;
            while rf < r_from.len {
                if r_from[rf] == v {
                    var nn: i64 = 0;
                    while nn < names.len { if names[nn] == r_to[rf] { break; } nn += 1; }
                    v = p_text[nn];
                    break;
                }
                rf += 1;
            }
        }
        var ni: i64 = 0;
        while ni < names.len { if names[ni] == a_keys[ai] { break; } ni += 1; }
        out.push(' ');
        out.append(if p_uri[ni].len > 0 { p_text[ni] } else { p_tag[ni] });
        out.append("=\"");
        c14_attrib(out, v);
        out.push('"');
    }
    out.push('>');
    if qname_text.len > 0 {
        var nn: i64 = 0;
        while nn < names.len { if names[nn] == r_to[0] { break; } nn += 1; }
        c14_cdata(out, p_text[nn]);
    }
    return true;
}

// c14_item says what the walk does with the node.
// The result of c14_decls writes the namespace declarations of the
// element into the scope stack. It gives false for a bad entity.
fn c14_decls(doc: Doc&, id: i32, ubuf: u8[>..]&, n_uris: const u8[:][>..]&, n_pfxs: const u8[:][>..]&) -> bool {
    let n = doc.nodes[id];
    var i = 0;
    while i < n.attr_count {
        let a = doc.attrs[n.attr_start + i];
        i += 1;
        if !is_ns_decl(a) { continue; }
        let s = ubuf.len;
        if !decode_attr(ubuf, a.value) { return false; }
        n_uris.push(ubuf[s..ubuf.len]);
        n_pfxs.push(if a.name == "xmlns" { a.name[0..0] } else { a.name[6..] });
    }
    return true;
}

// c14_has_decl says whether the element declares a namespace.
fn c14_has_decl(doc: Doc&, id: i32) -> bool {
    let n = doc.nodes[id];
    var i = 0;
    while i < n.attr_count {
        if is_ns_decl(doc.attrs[n.attr_start + i]) { return true; }
        i += 1;
    }
    return false;
}

// canonicalize writes the document in the canonical form of
// xml.etree.ElementTree.canonicalize. The lists hold names of the form
// {uri}local. A list that holds only the empty name is an empty list.
// It gives false where Python raises an error: a prefix that is not
// declared, or a bad entity.
fn canonicalize(out: u8[>..]&, doc: Doc&, opts: C14nOpts,
        exclude_tags: const u8[:][:], exclude_attrs: const u8[:][:],
        qname_tags: const u8[:][:], qname_attrs: const u8[:][:]) -> bool {
    if doc.root < 0 { return false; }
    var d_uris: const u8[:][>..] = [];
    var d_pfxs: const u8[:][>..] = [];
    var d_frames: i64[>..] = [];
    var n_uris: const u8[:][>..] = [];
    var n_pfxs: const u8[:][>..] = [];
    var n_frames: i64[>..] = [];
    var pm_uris: const u8[:][>..] = [];
    var pm_pfxs: const u8[:][>..] = [];
    var pbuf: u8[>..] = [];
    var ubuf: u8[>..] = [];
    var preserve: u8[>..] = [];
    preserve.push(0 as u8);
    d_frames.push(0);
    d_uris.push(XML_NS);
    d_pfxs.push("xml");
    if !opts.rewrite_prefixes {
        n_frames.push(0);
        n_uris.push(XML_NS);
        n_pfxs.push("xml");
        n_uris.push("http://www.w3.org/1999/xhtml");
        n_pfxs.push("html");
        n_uris.push("http://www.w3.org/1999/02/22-rdf-syntax-ns#");
        n_pfxs.push("rdf");
        n_uris.push("http://schemas.xmlsoap.org/wsdl/");
        n_pfxs.push("wsdl");
        n_uris.push("http://www.w3.org/2001/XMLSchema");
        n_pfxs.push("xs");
        n_uris.push("http://www.w3.org/2001/XMLSchema-instance");
        n_pfxs.push("xsi");
        n_uris.push("http://purl.org/dc/elements/1.1/");
        n_pfxs.push("dc");
    }
    n_frames.push(n_uris.len);
    var data: u8[>..] = [];
    var pending: i32 = -1;
    var ignored: i64 = 0;
    var root_seen = false;
    var root_done = false;
    // The order of the top level nodes: the ones before the root, the
    // root, and the ones after it.
    var stack: i32[>..] = [];
    var top: i32[>..] = [];
    var t: i32 = 0;
    while t < doc.nodes.len {
        let tn = doc.nodes[t];
        if t == doc.root || (tn.parent < 0 && (tn.kind == KIND_COMMENT || tn.kind == KIND_PI)) {
            top.push(t);
        }
        t += 1;
    }
    var ti = top.len;
    while ti > 0 {
        ti -= 1;
        stack.push(top[ti]);
    }
    while stack.len > 0 {
        let item = stack[stack.len - 1];
        stack.pop();
        var kind = KIND_ELEMENT as i32;
        var id = item;
        let closing = item < 0;
        if closing { id = -item - 2; } else { kind = doc.nodes[id].kind; }
        // The text before the event goes out first.
        var want = false;
        if data.len > 0 {
            if closing {
                want = ignored == 0;
            } else if kind == KIND_ELEMENT {
                let nd = doc.nodes[id];
                var key_buf: u8[>..] = [];
                let key = c14_key(key_buf, nd.uri, nd.local);
                let excluded = exclude_tags.len > 0 && (ignored > 0 || c14_in(exclude_tags, key));
                want = (ignored == 0 && c14_has_decl(doc, id)) || !excluded;
            } else if kind == KIND_COMMENT || kind == KIND_PI {
                want = ignored == 0 && root_seen && !root_done
                    && (kind == KIND_PI || opts.with_comments);
            }
        }
        if want {
            var chunk: const u8[:] = data[..];
            if opts.strip_text && preserve[preserve.len - 1] == 0 { chunk = c14_strip(chunk); }
            if pending >= 0 {
                let id_p = pending;
                pending = -1;
                let use_q = chunk.len > 0 && c14_prefix_name(chunk);
                if !c14_start(out, doc, id_p, if use_q { chunk } else { "" }, opts, exclude_attrs, qname_attrs,
                    d_uris, d_pfxs, d_frames, n_uris, n_pfxs, n_frames,
                    pm_uris, pm_pfxs, pbuf, preserve) { return false; }
                root_seen = true;
                n_frames.push(n_uris.len);
                if !use_q && chunk.len > 0 { c14_cdata(out, chunk); }
            } else if chunk.len > 0 && root_seen {
                c14_cdata(out, chunk);
            }
            data.clear();
        }
        if closing {
            if ignored > 0 {
                ignored -= 1;
                continue;
            }
            let nd = doc.nodes[id];
            var qbuf: u8[>..] = [];
            let text, ok = c14_qname(qbuf, d_uris, d_pfxs, d_frames, n_uris, n_pfxs, n_frames,
                opts.rewrite_prefixes, pm_uris, pm_pfxs, pbuf, nd.uri, nd.local);
            if !ok { return false; }
            out.append("</");
            out.append(text);
            out.push('>');
            preserve.pop();
            root_done = preserve.len == 1;
            c14_pop_frame(d_uris, d_pfxs, d_frames);
            c14_pop_frame(n_uris, n_pfxs, n_frames);
            continue;
        }
        let n = doc.nodes[id];
        if kind == KIND_TEXT {
            if ignored == 0 { if !decode_entities(data, n.content) { return false; } }
        } else if kind == KIND_CDATA {
            if ignored == 0 {
                var k = 0;
                while k < n.content.len { k = put_literal(data, n.content, k, false); }
            }
        } else if kind == KIND_COMMENT {
            if opts.with_comments && ignored == 0 {
                if root_done { out.push('\n'); }
                out.append("<!--");
                c14_cdata(out, n.content);
                out.append("-->");
                if !root_seen { out.push('\n'); }
            }
        } else if kind == KIND_PI {
            if ignored == 0 {
                if root_done { out.push('\n'); }
                var from: i64 = 0;
                while from < n.content.len && is_space(n.content[from]) { from += 1; }
                out.append("<?");
                out.append(n.name);
                if from < n.content.len {
                    out.push(' ');
                    c14_cdata(out, n.content[from..]);
                }
                out.append("?>");
                if !root_seen { out.push('\n'); }
            }
        } else if kind == KIND_ELEMENT {
            if ignored == 0 {
                if !c14_decls(doc, id, ubuf, n_uris, n_pfxs) { return false; }
            }
            var key_buf: u8[>..] = [];
            let key = c14_key(key_buf, n.uri, n.local);
            if exclude_tags.len > 0 && (ignored > 0 || c14_in(exclude_tags, key)) {
                ignored += 1;
            } else {
                d_frames.push(d_uris.len);
                if qname_tags.len > 0 && c14_in(qname_tags, key) {
                    pending = id;
                } else {
                    if !c14_start(out, doc, id, "", opts, exclude_attrs, qname_attrs,
                        d_uris, d_pfxs, d_frames, n_uris, n_pfxs, n_frames,
                        pm_uris, pm_pfxs, pbuf, preserve) { return false; }
                    root_seen = true;
                    n_frames.push(n_uris.len);
                }
            }
            // The children go on the stack after the close marker.
            {
                stack.push(-id - 2);
                var kids: i32[>..] = [];
                var c = n.first_child;
                while c >= 0 {
                    kids.push(c);
                    c = doc.nodes[c].next_sibling;
                }
                var q = kids.len;
                while q > 0 {
                    q -= 1;
                    stack.push(kids[q]);
                }
            }
        }
    }
    return true;
}
