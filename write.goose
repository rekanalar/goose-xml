// The writer of the xml package.
//
// tostring writes a subtree as XML text in the form of ElementTree of
// Python 3.14. A name in a namespace gets a prefix: a well-known prefix
// for a well-known uri, and ns0, ns1 and so on for the others, in the
// order of the first use. The declarations stand on the first element.
// The comments and the processing instructions are not written, as the
// tree of ElementTree holds none. indent adds the whitespace of a
// pretty print. write puts the text into a file.
namespace xml;

import std;
import os;
import tree;
import read;
import build_tree;
import encoding;
import encoding_data;

// WriteOpts holds the options of tostring.
struct WriteOpts {
    xml_declaration: i32,
    short_empty_elements: bool,
    method: i32,
    default_namespace: const u8[:],
}

// The values of method: xml, html and text, as in ElementTree.
const METHOD_XML = 0;
const METHOD_HTML = 1;
const METHOD_TEXT = 2;

// The values of xml_declaration. DECL_AUTO writes a declaration when the
// encoding is not UTF-8 and not US-ASCII, as tostring of Python does.
const DECL_AUTO = 0;
const DECL_YES = 1;
const DECL_NO = 2;

// write_opts gives the defaults of ElementTree: no declaration and the
// short form for an empty element.
fn write_opts() -> WriteOpts {
    return WriteOpts { xml_declaration: DECL_AUTO as i32, short_empty_elements: true, method: METHOD_XML as i32, default_namespace: "" };
}

// ns_known gives the well-known prefix of a uri, or an empty text.
fn ns_known(uri: const u8[:]) -> const u8[:] {
    if uri == XML_NS { return "xml"; }
    if uri == "http://www.w3.org/1999/xhtml" { return "html"; }
    if uri == "http://www.w3.org/1999/02/22-rdf-syntax-ns#" { return "rdf"; }
    if uri == "http://schemas.xmlsoap.org/wsdl/" { return "wsdl"; }
    if uri == "http://www.w3.org/2001/XMLSchema" { return "xs"; }
    if uri == "http://www.w3.org/2001/XMLSchema-instance" { return "xsi"; }
    if uri == "http://purl.org/dc/elements/1.1/" { return "dc"; }
    return "";
}

// ns_find gives the place of the uri in the list, or -1.
fn ns_find(uris: const u8[:][>..]&, uri: const u8[:]) -> i64 {
    var i: i64 = 0;
    while i < uris.len {
        if uris[i] == uri { return i; }
        i += 1;
    }
    return -1;
}

// ns_add registers the uri when it is new and not the uri of the xml
// prefix. The prefix goes into the buffer.
fn ns_add(uris: const u8[:][>..]&, pfxs: const u8[:][>..]&, pbuf: u8[>..]&, uri: const u8[:]) {
    if uri.len == 0 || uri == XML_NS || ns_find(uris, uri) >= 0 { return; }
    var known = ns_known(uri);
    let start = pbuf.len;
    if known.len > 0 {
        pbuf.append(known);
    } else {
        pbuf.append("ns");
        // The number is the count of the registered uris.
        var digits: u8[>..] = [];
        var v = uris.len;
        if v == 0 { digits.push('0'); }
        while v > 0 {
            digits.push(('0' as i64 + v % 10) as u8);
            v = v / 10;
        }
        var d = digits.len;
        while d > 0 {
            d -= 1;
            pbuf.push(digits[d]);
        }
    }
    uris.push(uri);
    pfxs.push(pbuf[start..pbuf.len]);
}

// ns_collect registers the uris of the subtree in the order of use: the
// tag of an element, then its attributes, then its children.
recursive fn ns_collect(doc: Doc&, id: i32, uris: const u8[:][>..]&, pfxs: const u8[:][>..]&, pbuf: u8[>..]&, plain_ok: bool) -> bool {
    let n = doc.nodes[id];
    // With a default namespace, a name without a namespace has no form.
    if !plain_ok && n.uri.len == 0 { return false; }
    ns_add(uris, pfxs, pbuf, n.uri);
    var i = 0;
    while i < n.attr_count {
        let a = doc.attrs[n.attr_start + i];
        i += 1;
        if is_ns_decl(a) { continue; }
        if !plain_ok && a.uri.len == 0 { return false; }
        ns_add(uris, pfxs, pbuf, a.uri);
    }
    var c = n.first_child;
    while c >= 0 {
        if doc.nodes[c].kind == KIND_ELEMENT {
            if !ns_collect(doc, c, uris, pfxs, pbuf, plain_ok) { return false; }
        }
        c = doc.nodes[c].next_sibling;
    }
    return true;
}

// ts_qname writes the name with its prefix.
fn ts_qname(out: u8[>..]&, uris: const u8[:][>..]&, pfxs: const u8[:][>..]&, uri: const u8[:], local: const u8[:]) {
    if uri.len > 0 {
        if uri == XML_NS {
            out.append("xml:");
        } else if pfxs[ns_find(uris, uri)].len > 0 {
            // The default namespace has an empty prefix and needs no colon.
            out.append(pfxs[ns_find(uris, uri)]);
            out.push(':');
        }
    }
    out.append(local);
}

// ts_cdata writes the text with the escapes of ElementTree.
fn ts_cdata(out: u8[>..]&, s: const u8[:]) {
    for c in s {
        if c == '&' { out.append("&amp;"); }
        else if c == '<' { out.append("&lt;"); }
        else if c == '>' { out.append("&gt;"); }
        else { out.push(c); }
    }
}

// ts_attrib writes the value of an attribute with the escapes of
// ElementTree.
fn ts_attrib(out: u8[>..]&, s: const u8[:]) {
    for c in s {
        if c == '&' { out.append("&amp;"); }
        else if c == '<' { out.append("&lt;"); }
        else if c == '>' { out.append("&gt;"); }
        else if c == '"' { out.append("&quot;"); }
        else if c == '\r' { out.append("&#13;"); }
        else if c == '\n' { out.append("&#10;"); }
        else if c == '\t' { out.append("&#09;"); }
        else { out.push(c); }
    }
}

// ts_attrib_html writes an attribute value with the escapes of the html
// method: only & > and the double quote.
fn ts_attrib_html(out: u8[>..]&, s: const u8[:]) {
    for c in s {
        if c == '&' { out.append("&amp;"); }
        else if c == '>' { out.append("&gt;"); }
        else if c == '"' { out.append("&quot;"); }
        else { out.push(c); }
    }
}

// ts_open writes the start of the open tag: the name, the declarations
// of the prefixes when top is true, and the attributes.
fn ts_open(out: u8[>..]&, doc: Doc&, id: i32, uris: const u8[:][>..]&, pfxs: const u8[:][>..]&, top: bool, html: bool) -> bool {
    let n = doc.nodes[id];
    out.push('<');
    ts_qname(out, uris, pfxs, n.uri, n.local);
    if top {
        // The declarations come in the order of the prefix.
        var done: u8[>..] = [];
        var z: i64 = 0;
        while z < uris.len { done.push(0 as u8); z += 1; }
        var round: i64 = 0;
        while round < uris.len {
            var best: i64 = -1;
            var k: i64 = 0;
            while k < uris.len {
                if done[k] == 0 && (best < 0 || ts_less(pfxs[k], pfxs[best])) { best = k; }
                k += 1;
            }
            done[best] = 1;
            out.append(" xmlns");
            if pfxs[best].len > 0 { out.push(':'); }
            out.append(pfxs[best]);
            out.append("=\"");
            ts_attrib(out, uris[best]);
            out.push('"');
            round += 1;
        }
    }
    var i = 0;
    while i < n.attr_count {
        let a = doc.attrs[n.attr_start + i];
        i += 1;
        if is_ns_decl(a) { continue; }
        out.push(' ');
        ts_qname(out, uris, pfxs, a.uri, a.local);
        out.append("=\"");
        var dec: u8[>..] = [];
        if !decode_attr(dec, a.value) { return false; }
        if html { ts_attrib_html(out, dec[..]); } else { ts_attrib(out, dec[..]); }
        out.push('"');
    }
    return true;
}

// ts_has_text says whether the text of the element is not empty.
fn ts_has_text(doc: Doc&, id: i32) -> bool {
    var text: u8[>..] = [];
    elem_text(text, doc, id);
    return text.len > 0;
}

// ts_text writes the text of the element, escaped.
fn ts_text(out: u8[>..]&, doc: Doc&, id: i32) -> bool {
    var text: u8[>..] = [];
    if !elem_text(text, doc, id) { return false; }
    ts_cdata(out, text[..]);
    return true;
}

// ts_tail writes the tail of the element, escaped.
fn ts_tail(out: u8[>..]&, doc: Doc&, id: i32) -> bool {
    var tail: u8[>..] = [];
    if !elem_tail(tail, doc, id) { return false; }
    ts_cdata(out, tail[..]);
    return true;
}

// ts_node writes the element, its children and its tail. The flag top
// says that the declarations of the prefixes stand on this element.
recursive fn ts_node(out: u8[>..]&, doc: Doc&, id: i32, uris: const u8[:][>..]&, pfxs: const u8[:][>..]&, top: bool, short_empty: bool, html: bool) -> bool {
    if !ts_open(out, doc, id, uris, pfxs, top, html) { return false; }
    if html { return ts_html_body(out, doc, id, uris, pfxs); }
    if ts_has_text(doc, id) || ind_has_children_doc(doc, id) || !short_empty {
        out.push('>');
        if !ts_text(out, doc, id) { return false; }
        var c = doc.nodes[id].first_child;
        while c >= 0 {
            if doc.nodes[c].kind == KIND_ELEMENT {
                if !ts_node(out, doc, c, uris, pfxs, false, short_empty, false) { return false; }
            }
            c = doc.nodes[c].next_sibling;
        }
        out.append("</");
        ts_qname(out, uris, pfxs, doc.nodes[id].uri, doc.nodes[id].local);
        out.push('>');
    } else {
        out.append(" />");
    }
    return ts_tail(out, doc, id);
}

// ts_void says whether the tag is an html element without an end tag.
fn ts_void(tag: const u8[:]) -> bool {
    var low: u8[>..] = [];
    for c in tag { low.push(if c >= 'A' && c <= 'Z' { c + 32 } else { c }); }
    let names: const u8[:][] = ["area", "base", "basefont", "br", "col", "frame", "hr", "img", "input", "isindex", "link", "meta", "param"];
    for v in names {
        if low[..] == v { return true; }
    }
    return false;
}

// ts_html_text writes the text of an element in the html method. The
// text of script and style stays unescaped.
fn ts_html_text(out: u8[>..]&, doc: Doc&, id: i32, uris: const u8[:][>..]&, pfxs: const u8[:][>..]&) -> bool {
    var tag: u8[>..] = [];
    ts_qname(tag, uris, pfxs, doc.nodes[id].uri, doc.nodes[id].local);
    var low: u8[>..] = [];
    for c in tag[..] { low.push(if c >= 'A' && c <= 'Z' { c + 32 } else { c }); }
    if low[..] == "script" || low[..] == "style" { return elem_text(out, doc, id); }
    return ts_text(out, doc, id);
}

// ts_html_close writes the end tag unless the element is a void element.
fn ts_html_close(out: u8[>..]&, doc: Doc&, id: i32, uris: const u8[:][>..]&, pfxs: const u8[:][>..]&) {
    var tag: u8[>..] = [];
    ts_qname(tag, uris, pfxs, doc.nodes[id].uri, doc.nodes[id].local);
    if ts_void(tag[..]) { return; }
    out.append("</");
    out.append(tag[..]);
    out.push('>');
}

// ts_html_body writes the rest of an element in the html method: the
// text, the children, the end tag and the tail. It follows the open tag.
recursive fn ts_html_body(out: u8[>..]&, doc: Doc&, id: i32, uris: const u8[:][>..]&, pfxs: const u8[:][>..]&) -> bool {
    out.push('>');
    if !ts_html_text(out, doc, id, uris, pfxs) { return false; }
    var c = doc.nodes[id].first_child;
    while c >= 0 {
        if doc.nodes[c].kind == KIND_ELEMENT {
            if !ts_html_child(out, doc, c, uris, pfxs) { return false; }
        }
        c = doc.nodes[c].next_sibling;
    }
    ts_html_close(out, doc, id, uris, pfxs);
    return ts_tail(out, doc, id);
}

// ts_html_child writes a child element in the html method.
recursive fn ts_html_child(out: u8[>..]&, doc: Doc&, id: i32, uris: const u8[:][>..]&, pfxs: const u8[:][>..]&) -> bool {
    if !ts_open(out, doc, id, uris, pfxs, false, true) { return false; }
    return ts_html_body(out, doc, id, uris, pfxs);
}

// ind_has_children_doc says whether the element has a child element.
fn ind_has_children_doc(doc: Doc&, id: i32) -> bool {
    var c = doc.nodes[id].first_child;
    while c >= 0 {
        if doc.nodes[c].kind == KIND_ELEMENT { return true; }
        c = doc.nodes[c].next_sibling;
    }
    return false;
}

// ts_less says whether the text a sorts before the text b by bytes.
fn ts_less(a: const u8[:], b: const u8[:]) -> bool {
    var i: i64 = 0;
    while i < a.len && i < b.len {
        if a[i] != b[i] { return a[i] < b[i]; }
        i += 1;
    }
    return a.len < b.len;
}

// tostring writes the element and its subtree as XML text into out. It
// gives false when a text holds an entity that cannot be decoded.
fn tostring(out: u8[>..]&, doc: Doc&, id: i32, opts: WriteOpts) -> bool {
    if id < 0 || id >= doc.nodes.len || doc.nodes[id].kind != KIND_ELEMENT { return false; }
    if opts.method == METHOD_TEXT {
        if !iter_text(out, doc, id) { return false; }
        return elem_tail(out, doc, id);
    }
    var uris: const u8[:][>..] = [];
    var pfxs: const u8[:][>..] = [];
    var pbuf: u8[>..] = [];
    // The default namespace takes the first place with an empty prefix.
    if opts.default_namespace.len > 0 {
        uris.push(opts.default_namespace);
        pfxs.push("");
    }
    if !ns_collect(doc, id, uris, pfxs, pbuf, opts.default_namespace.len == 0) { return false; }
    if opts.xml_declaration == DECL_YES && opts.method == METHOD_XML { out.append("<?xml version='1.0' encoding='utf-8'?>\n"); }
    return ts_node(out, doc, id, uris, pfxs, true, opts.short_empty_elements, opts.method == METHOD_HTML);
}

// tostring_encoded writes the element as bytes in the encoding. The
// default encoding of Python is us-ascii. A character that the encoding
// cannot hold becomes a character reference. With DECL_AUTO a declaration
// stands first when the encoding is not utf-8 and not us-ascii. It gives
// false for an unknown encoding.
fn tostring_encoded(out: u8[>..]&, doc: Doc&, id: i32, opts: WriteOpts, encoding: const u8[:]) -> bool {
    var text: u8[>..] = [];
    var plain = opts;
    plain.xml_declaration = DECL_NO as i32;
    if !tostring(text, doc, id, plain) { return false; }
    var low: u8[>..] = [];
    for c in encoding { low.push(if c >= 'A' && c <= 'Z' { c + 32 } else { c }); }
    let utf8_like = low[..] == "utf-8" || low[..] == "us-ascii" || low[..] == "unicode";
    var head: u8[>..] = [];
    if opts.method == METHOD_XML && (opts.xml_declaration == DECL_YES || (opts.xml_declaration == DECL_AUTO && !utf8_like)) {
        head.append("<?xml version='1.0' encoding='");
        head.append(encoding);
        head.append("'?>\n");
    }
    head.append(text[..]);
    return encode(out, head[..], encoding);
}

// write writes the subtree as XML text into the file. It gives false
// when the text cannot be made or the file cannot be written.
fn write(path: const u8[:], doc: Doc&, id: i32, opts: WriteOpts) -> bool {
    var out: u8[>..] = [];
    if !tostring(out, doc, id, opts) { return false; }
    return write_file(path, out[..]);
}

// ind_blank says whether the text holds only whitespace.
fn ind_blank(s: const u8[:]) -> bool {
    for c in s {
        if !is_space(c) { return false; }
    }
    return true;
}

// ind_has_children says whether the element has a child element.
fn ind_has_children(nodes: Node[>..]&, id: i32) -> bool {
    var c = nodes[id].first_child;
    while c >= 0 {
        if nodes[c].kind == KIND_ELEMENT { return true; }
        c = nodes[c].next_sibling;
    }
    return false;
}

// ind_text makes the indentation: a newline and the space, depth times.
fn ind_text(out: u8[>..]&, space: const u8[:], depth: i64) {
    out.push('\n');
    var k: i64 = 0;
    while k < depth {
        out.append(space);
        k += 1;
    }
}

// ind_first replaces the text of the element with the indentation when
// the text holds only whitespace.
fn ind_first(nodes: Node[>..]&, attrs: Attr[>..]&, text: u8[>..]&, id: i32, depth: i64, space: const u8[:]) -> bool {
    let doc = Doc { nodes: nodes[..], attrs: attrs[..], root: id };
    var t: u8[>..] = [];
    if !elem_text(t, doc, id) { return false; }
    if ind_blank(t[..]) {
        var ind: u8[>..] = [];
        ind_text(ind, space, depth);
        set_text(nodes, text, id, ind[..]);
    }
    return true;
}

// ind_tail replaces the tail of the element with the indentation when
// the tail holds only whitespace.
fn ind_tail(nodes: Node[>..]&, attrs: Attr[>..]&, text: u8[>..]&, id: i32, depth: i64, space: const u8[:]) -> bool {
    let doc = Doc { nodes: nodes[..], attrs: attrs[..], root: id };
    var t: u8[>..] = [];
    if !elem_tail(t, doc, id) { return false; }
    if ind_blank(t[..]) {
        var ind: u8[>..] = [];
        ind_text(ind, space, depth);
        set_tail(nodes, text, id, ind[..]);
    }
    return true;
}

// ind_children sets the indentation of the children of the element, as
// indent of ElementTree does. The depth is the depth of the element.
recursive fn ind_children(nodes: Node[>..]&, attrs: Attr[>..]&, text: u8[>..]&, id: i32, depth: i64, space: const u8[:]) -> bool {
    if !ind_first(nodes, attrs, text, id, depth + 1, space) { return false; }
    var last: i32 = -1;
    var c = nodes[id].first_child;
    while c >= 0 {
        if nodes[c].kind == KIND_ELEMENT {
            if ind_has_children(nodes, c) {
                if !ind_children(nodes, attrs, text, c, depth + 1, space) { return false; }
            }
            if !ind_tail(nodes, attrs, text, c, depth + 1, space) { return false; }
            last = c;
        }
        // The links of c can change in this pass, so read them now.
        c = nodes[c].next_sibling;
    }
    if last >= 0 { return ind_tail(nodes, attrs, text, last, depth, space); }
    return true;
}

// indent adds whitespace to the subtree so that tostring gives a pretty
// print. The text and the tail that hold only whitespace are replaced.
// The space is the text of one level, and level is the level of the
// element. It gives false when a text cannot be decoded.
fn indent(nodes: Node[>..]&, attrs: Attr[>..]&, text: u8[>..]&, id: i32, space: const u8[:], level: i64) -> bool {
    if level < 0 || !ind_has_children(nodes, id) { return level >= 0; }
    return ind_children(nodes, attrs, text, id, level, space);
}
