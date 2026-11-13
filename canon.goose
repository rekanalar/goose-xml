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
