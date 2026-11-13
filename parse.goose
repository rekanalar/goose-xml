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

// utf8_at decodes the UTF-8 sequence at pos. It gives the code point and
// the length, or length 0 for a bad sequence: a lead byte out of range,
// a missing continuation byte, an overlong form, a surrogate, or a value
// above U+10FFFF.
fn utf8_at(s: const u8[:], pos: i64) -> i64, i64 {
    let b = s[pos] as i64;
    if b < 128 { return b, 1; }
    var n: i64 = 0;
    var cp: i64 = 0;
    var low: i64 = 0;
    if b >= 194 && b <= 223 {
        n = 2; cp = b & 31; low = 128;
    } else if b >= 224 && b <= 239 {
        n = 3; cp = b & 15; low = 2048;
    } else if b >= 240 && b <= 244 {
        n = 4; cp = b & 7; low = 65536;
    } else {
        return 0, 0;
    }
    if pos + n > s.len { return 0, 0; }
    var k: i64 = 1;
    while k < n {
        let c = s[pos + k] as i64;
        if (c & 192) != 128 { return 0, 0; }
        cp = (cp << 6) | (c & 63);
        k += 1;
    }
    if cp < low || cp > 1114111 || (cp >= 55296 && cp <= 57343) { return 0, 0; }
    return cp, n;
}

// check_chars tests every character of the text from start on. Each one
// must be a character of XML 1.0 in valid UTF-8. U+FFFE and U+FFFF are
// refused. One pass, no allocation.
fn check_chars(s: const u8[:], start: i64) -> bool {
    var i = start;
    while i < s.len {
        let c = s[i];
        if c < 128 {
            if c < 32 && c != '\t' && c != '\n' && c != '\r' { return false; }
            i += 1;
        } else {
            let cp, n = utf8_at(s, i);
            if n == 0 || cp == 65534 || cp == 65535 { return false; }
            i += n;
        }
    }
    return true;
}

// name_start_cp tells whether a non-ASCII code point may start a name
// (NameStartChar of XML 1.0, fifth edition).
fn name_start_cp(cp: i64) -> bool {
    return (cp >= 192 && cp <= 214) || (cp >= 216 && cp <= 246) || (cp >= 248 && cp <= 767)
        || (cp >= 880 && cp <= 893) || (cp >= 895 && cp <= 8191) || (cp >= 8204 && cp <= 8205)
        || (cp >= 8304 && cp <= 8591) || (cp >= 11264 && cp <= 12271) || (cp >= 12289 && cp <= 55295)
        || (cp >= 63744 && cp <= 64975) || (cp >= 65008 && cp <= 65533) || (cp >= 65536 && cp <= 983039);
}

// name_cp tells whether a non-ASCII code point may continue a name
// (NameChar of XML 1.0, fifth edition).
fn name_cp(cp: i64) -> bool {
    return name_start_cp(cp) || cp == 183 || (cp >= 768 && cp <= 879) || (cp >= 8255 && cp <= 8256);
}

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
    var i = pos;
    while i < s.len {
        let c = s[i];
        if c < 128 {
            let ok = if i == pos { is_name_start(c) } else { is_name_char(c) };
            if !ok { break; }
            i += 1;
        } else {
            let cp, n = utf8_at(s, i);
            if n == 0 { break; }
            let ok = if i == pos { name_start_cp(cp) } else { name_cp(cp) };
            if !ok { break; }
            i += n;
        }
    }
    if i == pos { return -1; }
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
    nodes.push(Node { kind: kind, name: name, uri: "", local: name, content: content, parent: parent, first_child: -1, last_child: -1, next_sibling: -1, attr_start: 0, attr_count: 0 });
    if parent >= 0 {
        // Link the node after the last child of the parent.
        let last = nodes[parent].last_child;
        if last < 0 {
            nodes[parent].first_child = id;
        } else {
            nodes[last].next_sibling = id;
        }
        nodes[parent].last_child = id;
    }
    return id;
}

// starts_at tells whether the text holds the literal at pos.
fn starts_at(s: const u8[:], pos: i64, lit: const u8[:]) -> bool {
    return pos + lit.len <= s.len && s[pos..pos + lit.len] == lit;
}

// find_lit gives the place of the first literal at or after from, or -1.
fn find_lit(s: const u8[:], from: i64, lit: const u8[:]) -> i64 {
    var j = from;
    while j + lit.len <= s.len {
        if s[j] == lit[0] && s[j..j + lit.len] == lit { return j; }
        j += 1;
    }
    return -1;
}

// has_cdata_end tells whether the span holds "]]>".
fn has_cdata_end(s: const u8[:]) -> bool {
    return find_lit(s, 0, "]]>") >= 0;
}

// lower_eq tells whether the span equals the lower case literal, with
// letter case ignored.
fn lower_eq(s: const u8[:], lit: const u8[:]) -> bool {
    if s.len != lit.len { return false; }
    var i = 0;
    while i < s.len {
        var c = s[i];
        if c >= 'A' && c <= 'Z' { c = c + 32; }
        if c != lit[i] { return false; }
        i += 1;
    }
    return true;
}

// decl_value reads one pseudo attribute of the declaration at pos. The
// name must equal key. It needs the quotes. It gives the value span and
// the place after the closing quote, or -1.
fn decl_value(s: const u8[:], pos: i64, key: const u8[:]) -> const u8[:], i64 {
    let bad = s[0..0];
    if !starts_at(s, pos, key) { return bad, -1; }
    var k = pos + key.len;
    while k < s.len && is_space(s[k]) { k += 1; }
    if k >= s.len || s[k] != '=' { return bad, -1; }
    k += 1;
    while k < s.len && is_space(s[k]) { k += 1; }
    if k >= s.len || (s[k] != '"' && s[k] != '\'') { return bad, -1; }
    let quote = s[k];
    k += 1;
    var e = k;
    while e < s.len && s[e] != quote { e += 1; }
    if e >= s.len { return bad, -1; }
    return s[k..e], e + 1;
}

// check_decl tests the body of the XML declaration, the text after the
// target. The version comes first, with letters, digits and . _ - only. The encoding, if present, names UTF-8
// or US-ASCII. The standalone value, if present, is yes or no. White
// space separates the items.
fn check_decl(b: const u8[:]) -> bool {
    var i: i64 = 0;
    if b.len == 0 || !is_space(b[0]) { return false; }
    while i < b.len && is_space(b[i]) { i += 1; }
    let ver, after = decl_value(b, i, "version");
    if after < 0 { return false; }
    for vc in ver {
        let ok = (vc >= 'a' && vc <= 'z') || (vc >= 'A' && vc <= 'Z') || (vc >= '0' && vc <= '9') || vc == '.' || vc == '_' || vc == '-';
        if !ok { return false; }
    }
    i = after;
    var sp = i;
    while i < b.len && is_space(b[i]) { i += 1; }
    if i == b.len { return true; }
    if i == sp { return false; }
    if starts_at(b, i, "encoding") {
        let enc, after2 = decl_value(b, i, "encoding");
        if after2 < 0 { return false; }
        if !lower_eq(enc, "utf-8") && !lower_eq(enc, "us-ascii") { return false; }
        i = after2;
        sp = i;
        while i < b.len && is_space(b[i]) { i += 1; }
        if i == b.len { return true; }
        if i == sp { return false; }
    }
    let sa, after3 = decl_value(b, i, "standalone");
    if after3 < 0 { return false; }
    if sa != "yes" && sa != "no" { return false; }
    i = after3;
    while i < b.len && is_space(b[i]) { i += 1; }
    return i == b.len;
}

// literal_end gives the place after a quoted literal at pos, or -1.
fn literal_end(s: const u8[:], pos: i64) -> i64 {
    if pos >= s.len || (s[pos] != '"' && s[pos] != '\'') { return -1; }
    var e = pos + 1;
    while e < s.len && s[e] != s[pos] { e += 1; }
    if e >= s.len { return -1; }
    return e + 1;
}

// skip_doctype gives the place after a DOCTYPE that starts at pos, or -1.
// After the keyword come the name of the root, an optional SYSTEM or
// PUBLIC identifier, and an optional internal subset in [ ]. The subset is
// checked for its declaration keywords, quotes, comments and PIs, and
// not checked further.
fn skip_doctype(s: const u8[:], pos: i64) -> i64 {
    var j = pos + 9;
    if j >= s.len || !is_space(s[j]) { return -1; }
    while j < s.len && is_space(s[j]) { j += 1; }
    let name_end = read_name(s, j);
    if name_end < 0 || !split_ok(s[j..name_end]) { return -1; }
    j = name_end;
    var gap = j;
    while j < s.len && is_space(s[j]) { j += 1; }
    gap = j - gap;
    if starts_at(s, j, "SYSTEM") {
        if gap == 0 { return -1; }
        j += 6;
        if j >= s.len || !is_space(s[j]) { return -1; }
        while j < s.len && is_space(s[j]) { j += 1; }
        j = literal_end(s, j);
        if j < 0 { return -1; }
    } else if starts_at(s, j, "PUBLIC") {
        if gap == 0 { return -1; }
        j += 6;
        if j >= s.len || !is_space(s[j]) { return -1; }
        while j < s.len && is_space(s[j]) { j += 1; }
        j = literal_end(s, j);
        if j < 0 || j >= s.len || !is_space(s[j]) { return -1; }
        while j < s.len && is_space(s[j]) { j += 1; }
        j = literal_end(s, j);
        if j < 0 { return -1; }
    }
    while j < s.len && is_space(s[j]) { j += 1; }
    if j < s.len && s[j] == '[' {
        j += 1;
        while j < s.len && s[j] != ']' {
            if starts_at(s, j, "<!--") {
                let e = find_lit(s, j + 4, "-->");
                if e < 0 { return -1; }
                j = e + 3;
            } else if starts_at(s, j, "<?") {
                let e = find_lit(s, j + 2, "?>");
                if e < 0 { return -1; }
                j = e + 2;
            } else if starts_at(s, j, "<!ELEMENT") || starts_at(s, j, "<!ATTLIST") || starts_at(s, j, "<!ENTITY") || starts_at(s, j, "<!NOTATION") {
                // A declaration runs to its '>' outside the quotes.
                j += 2;
                while j < s.len && s[j] != '>' {
                    if s[j] == '"' || s[j] == '\'' {
                        j = literal_end(s, j);
                        if j < 0 { return -1; }
                    } else {
                        j += 1;
                    }
                }
                if j >= s.len { return -1; }
                j += 1;
            } else if s[j] == '%' {
                // A parameter entity reference.
                let e = read_name(s, j + 1);
                if e < 0 || e >= s.len || s[e] != ';' { return -1; }
                j = e + 1;
            } else if is_space(s[j]) {
                j += 1;
            } else {
                return -1;
            }
        }
        if j >= s.len { return -1; }
        j += 1;
        while j < s.len && is_space(s[j]) { j += 1; }
    }
    if j < s.len && s[j] == '>' { return j + 1; }
    return -1;
}

// parse reads one document. It returns an empty Doc and false when the
// text is not well-formed. The spans in the tree point into the text, so
// the text must outlive the Doc.
fn parse(s: const u8[:], nodes: Node[>..]&, attrs: Attr[>..]&) -> Doc, bool {
    let fail = Doc { nodes: nodes[..], attrs: attrs[..], root: -1 };
    var stack: i32[>..] = [];
    var pos: i64 = 0;
    // A leading UTF-8 byte order mark is not part of the text.
    if starts_at(s, 0, "\xef\xbb\xbf") { pos = 3; }
    let start = pos;
    if !check_chars(s, start) { return fail, false; }
    // True when the root element closed.
    var root_done = false;
    var seen_doctype = false;
    var root_id: i32 = -1;

    while pos < s.len {
        if s[pos] == '<' {
            if pos + 1 >= s.len { return fail, false; }
            let c = s[pos + 1];
            if c == '/' {
                // A close tag: match the top of the stack.
                let name_end = read_name(s, pos + 2);
                if name_end < 0 { return fail, false; }
                var j = name_end;
                while j < s.len && is_space(s[j]) { j += 1; }
                if j >= s.len || s[j] != '>' { return fail, false; }
                if stack.len == 0 { return fail, false; }
                let open_id = stack[stack.len - 1];
                if nodes[open_id].name != s[pos + 2..name_end] { return fail, false; }
                stack.pop();
                if stack.len == 0 { root_done = true; }
                pos = j + 1;
            } else if c == '!' {
                let parent = if stack.len > 0 { stack[stack.len - 1] } else { -1 };
                if starts_at(s, pos, "<!--") {
                    // A comment. The first "--" must close it.
                    let j = find_lit(s, pos + 4, "--");
                    if j < 0 || j + 2 >= s.len || s[j + 2] != '>' { return fail, false; }
                    // Outside the root the node stays unlinked. canonicalize
                    // reads these nodes in the order of the array.
                    append_node(nodes, KIND_COMMENT, s[0..0], s[pos + 4..j], parent);
                    pos = j + 3;
                } else if starts_at(s, pos, "<![CDATA[") {
                    let j = find_lit(s, pos + 9, "]]>");
                    if j < 0 || stack.len == 0 { return fail, false; }
                    append_node(nodes, KIND_CDATA, s[0..0], s[pos + 9..j], parent);
                    pos = j + 3;
                } else if starts_at(s, pos, "<!DOCTYPE") {
                    // One DOCTYPE, before the root.
                    if seen_doctype || root_id >= 0 { return fail, false; }
                    seen_doctype = true;
                    let e = skip_doctype(s, pos);
                    if e < 0 { return fail, false; }
                    pos = e;
                } else {
                    return fail, false;
                }
            } else if c == '?' {
                // A processing instruction, or the declaration.
                let j = find_lit(s, pos + 2, "?>");
                if j < 0 { return fail, false; }
                let name_end = read_name(s, pos + 2);
                if name_end < 0 || name_end > j { return fail, false; }
                if name_end < j && !is_space(s[name_end]) { return fail, false; }
                let target = s[pos + 2..name_end];
                // A PI target holds no colon, as in a namespace aware parser.
                if find_colon(target) >= 0 { return fail, false; }
                if lower_eq(target, "xml") {
                    // Only the declaration may use the target xml, and
                    // only at the start of the text.
                    if pos != start || target != "xml" { return fail, false; }
                    if !check_decl(s[name_end..j]) { return fail, false; }
                } else {
                    var from = name_end;
                    if from < j { from += 1; }
                    let owner = if stack.len > 0 { stack[stack.len - 1] } else { -1 };
                    append_node(nodes, KIND_PI, target, s[from..j], owner);
                }
                pos = j + 2;
            } else {
                // An open tag.
                if stack.len >= MAX_DEPTH { return fail, false; }
                let name_end = read_name(s, pos + 1);
                if name_end < 0 { return fail, false; }
                let parent = if stack.len > 0 { stack[stack.len - 1] } else { -1 };
                // A second root is a fault.
                if parent < 0 && root_id >= 0 { return fail, false; }
                let id = append_node(nodes, KIND_ELEMENT, s[pos + 1..name_end], s[0..0], parent);
                if parent < 0 { root_id = id; }
                var attr_start: i32 = attrs.len as i32;
                let after, self_closing, aok = scan_attrs(s, name_end, attrs);
                if !aok { return fail, false; }
                nodes[id].attr_start = attr_start;
                nodes[id].attr_count = attrs.len as i32 - attr_start;
                if self_closing {
                    if stack.len == 0 { root_done = true; }
                } else {
                    stack.push(id);
                }
                pos = after;
            }
        } else {
            // Text up to the next '<'.
            var end = pos;
            while end < s.len && s[end] != '<' { end += 1; }
            let text = s[pos..end];
            if stack.len > 0 {
                if has_cdata_end(text) || !valid_entities(text) { return fail, false; }
                append_node(nodes, KIND_TEXT, s[0..0], text, stack[stack.len - 1]);
            } else {
                // Outside the root only white space may stand.
                for ch in text {
                    if !is_space(ch) { return fail, false; }
                }
            }
            pos = end;
        }
    }
    if root_id < 0 || stack.len > 0 || !root_done { return fail, false; }
    if !resolve_names(nodes, attrs) { return fail, false; }
    return Doc { nodes: nodes[..], attrs: attrs[..], root: root_id }, true;
}
