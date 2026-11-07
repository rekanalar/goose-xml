// The encodings of the xml package.
//
// decode turns the bytes of a document into UTF-8 text. It reads a byte
// order mark, the layout of UTF-16 without a mark, and the encoding of the
// declaration. It knows UTF-8, US-ASCII, UTF-16 and the 8-bit code pages
// of Python in encoding_data.goose. encode turns UTF-8 text into the
// bytes of an encoding. A character that the encoding cannot hold
// becomes a character reference, as xmlcharrefreplace does in Python.
namespace xml;

import std;
import tree;

// The kinds of an encoding name.
const ENC_UNKNOWN = -1;
const ENC_UTF8 = -2;
const ENC_UTF16 = -3;
const ENC_UTF16LE = -4;
const ENC_UTF16BE = -5;
const ENC_UTF32 = -6;
const ENC_UTF32LE = -7;
const ENC_UTF32BE = -8;

// enc_norm writes the name in the form of the alias table: lower case,
// with a hyphen or a space as an underscore.
fn enc_norm(buf: u8[>..]&, name: const u8[:]) -> const u8[:] {
    let start = buf.len;
    for c in name {
        if c >= 'A' && c <= 'Z' { buf.push(c + 32); }
        else if c == '-' || c == ' ' { buf.push('_'); }
        else { buf.push(c); }
    }
    return buf[start..buf.len];
}

// enc_name_ok says whether the text is an encoding name of the XML
// grammar: a letter, then letters, digits, dots, underscores and hyphens.
fn enc_name_ok(name: const u8[:]) -> bool {
    if name.len == 0 { return false; }
    var i: i64 = 0;
    while i < name.len {
        let c = name[i];
        let letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
        let other = (c >= '0' && c <= '9') || c == '.' || c == '_' || c == '-';
        if !(letter || (i > 0 && other)) { return false; }
        i += 1;
    }
    return true;
}

// enc_kind gives the kind of an encoding name: a code page number from
// 0, or one of the negative kinds.
fn enc_kind(name: const u8[:]) -> i64 {
    var buf: u8[>..] = [];
    let n = enc_norm(buf, name);
    if n == "utf_8" || n == "utf8" || n == "u8" || n == "utf" || n == "cp65001"
        || n == "utf8_ucs2" || n == "utf8_ucs4" { return ENC_UTF8; }
    if n == "utf_16" || n == "utf16" || n == "u16" { return ENC_UTF16; }
    if n == "utf_16le" || n == "utf_16_le" { return ENC_UTF16LE; }
    if n == "utf_16be" || n == "utf_16_be" { return ENC_UTF16BE; }
    if n == "utf_32" || n == "utf32" || n == "u32" { return ENC_UTF32; }
    if n == "utf_32le" || n == "utf_32_le" { return ENC_UTF32LE; }
    if n == "utf_32be" || n == "utf_32_be" { return ENC_UTF32BE; }
    var i: i64 = 0;
    while i < ENC_ALIAS_COUNT {
        if ENC_ALIAS_NAMES[i] == n { return ENC_ALIAS_PAGES[i] as i64; }
        i += 1;
    }
    return ENC_UNKNOWN;
}

// enc_put writes the code point as UTF-8.
fn enc_put(out: u8[>..]&, cp: i64) {
    if cp < 0x80 {
        out.push(cp as u8);
    } else if cp < 0x800 {
        out.push((0xC0 | (cp >> 6)) as u8);
        out.push((0x80 | (cp & 0x3F)) as u8);
    } else if cp < 0x10000 {
        out.push((0xE0 | (cp >> 12)) as u8);
        out.push((0x80 | ((cp >> 6) & 0x3F)) as u8);
        out.push((0x80 | (cp & 0x3F)) as u8);
    } else {
        out.push((0xF0 | (cp >> 18)) as u8);
        out.push((0x80 | ((cp >> 12) & 0x3F)) as u8);
        out.push((0x80 | ((cp >> 6) & 0x3F)) as u8);
        out.push((0x80 | (cp & 0x3F)) as u8);
    }
}

// enc_decl_value gives the places of the encoding name in the XML
// declaration at the start of the text. It gives -1 and -1 when there is
// none.
fn enc_decl_value(s: const u8[:]) -> i64, i64 {
    if s.len < 6 || s[0..5] != "<?xml" || !is_space(s[5]) { return -1, -1; }
    var i: i64 = 5;
    while i + 1 < s.len && !(s[i] == '?' && s[i + 1] == '>') {
        if s[i] == 'e' && i + 8 <= s.len && s[i..i + 8] == "encoding" && is_space(s[i - 1]) {
            var j = i + 8;
            while j < s.len && is_space(s[j]) { j += 1; }
            if j >= s.len || s[j] != '=' { return -1, -1; }
            j += 1;
            while j < s.len && is_space(s[j]) { j += 1; }
            if j >= s.len || (s[j] != '"' && s[j] != '\'') { return -1, -1; }
            let q = s[j];
            var e = j + 1;
            while e < s.len && s[e] != q { e += 1; }
            if e >= s.len { return -1, -1; }
            return j + 1, e;
        }
        i += 1;
    }
    return -1, -1;
}

// enc_emit appends the text to out, with UTF-8 as the encoding name of
// its XML declaration.
fn enc_emit(out: u8[>..]&, text: const u8[:]) {
    let at, end = enc_decl_value(text);
    if at < 0 {
        out.append(text);
        return;
    }
    out.append(text[0..at]);
    out.append("UTF-8");
    out.append(text[end..]);
}

// enc_from16 turns UTF-16 bytes into UTF-8. It gives false for an odd
// length and for a surrogate that has no partner.
fn enc_from16(out: u8[>..]&, data: const u8[:], big: bool) -> bool {
    if data.len % 2 != 0 { return false; }
    var i: i64 = 0;
    while i < data.len {
        let a = data[i] as i64;
        let b = data[i + 1] as i64;
        var u = if big { a * 256 + b } else { b * 256 + a };
        i += 2;
        if u >= 0xD800 && u < 0xDC00 {
            if i >= data.len { return false; }
            let a2 = data[i] as i64;
            let b2 = data[i + 1] as i64;
            let u2 = if big { a2 * 256 + b2 } else { b2 * 256 + a2 };
            if u2 < 0xDC00 || u2 > 0xDFFF { return false; }
            i += 2;
            u = 0x10000 + ((u - 0xD800) << 10) + (u2 - 0xDC00);
        } else if u >= 0xDC00 && u <= 0xDFFF {
            return false;
        }
        enc_put(out, u);
    }
    return true;
}

// decode turns the bytes of a document into UTF-8 text. It gives the
// text, which is the input itself when no change is needed, or a slice of
// the buffer of the caller. It gives false for an encoding that it does
// not know, a byte that the encoding does not define, and a declaration
// that does not fit the bytes.
fn decode(buf: u8[>..]&, input: const u8[:]) -> const u8[:], bool {
    let base = buf.len;
    // A UTF-8 mark is only dropped: the declaration decides, as in expat.
    var data = input;
    if input.len >= 3 && input[0] == 0xEF && input[1] == 0xBB && input[2] == 0xBF { data = input[3..]; }
    // A byte order mark, or the layout of UTF-16 without one.
    var skip: i64 = 0;
    var wide = 0;
    if data.len >= 2 && data[0] == 0xFF && data[1] == 0xFE { wide = 1; skip = 2; }
    else if data.len >= 2 && data[0] == 0xFE && data[1] == 0xFF { wide = 2; skip = 2; }
    else if data.len >= 2 && data[0] == '<' && data[1] == 0 { wide = 1; }
    else if data.len >= 2 && data[0] == 0 && data[1] == '<' { wide = 2; }
    if wide > 0 {
        var tmp: u8[>..] = [];
        if !enc_from16(tmp, data[skip..], wide == 2) { return "", false; }
        // A second mark is a character that may not start a document.
        if tmp.len >= 3 && tmp[0] == 0xEF && tmp[1] == 0xBB && tmp[2] == 0xBF { return "", false; }
        let at, end = enc_decl_value(tmp[..]);
        if at >= 0 {
            if !enc_name_ok(tmp[at..end]) { return "", false; }
            // Expat knows only these three names for a 16 bit document.
            let name = tmp[at..end];
            let want = if wide == 2 { "utf-16be" } else { "utf-16le" };
            if !lower_eq(name, "utf-16") && !lower_eq(name, want) { return "", false; }
        }
        enc_emit(buf, tmp[..]);
        return buf[base..buf.len], true;
    }
    let at, end = enc_decl_value(data);
    if at < 0 { return data, true; }
    if !enc_name_ok(data[at..end]) { return "", false; }
    let kind = enc_kind(data[at..end]);
    if kind == ENC_UTF8 { return data, true; }
    if kind < 0 { return "", false; }
    var tmp: u8[>..] = [];
    var i: i64 = 0;
    while i < data.len {
        let b = data[i] as i64;
        i += 1;
        if b < 128 {
            tmp.push(b as u8);
        } else {
            let cp = ENC_TABLE[kind * 128 + b - 128];
            if cp == 0xFFFD { return "", false; }
            enc_put(tmp, cp as i64);
        }
    }
    enc_emit(buf, tmp[..]);
    return buf[base..buf.len], true;
}

// parse_bytes decodes the bytes of a document and parses the text. The
// buffer holds the UTF-8 text when a change was needed, and the Doc
// holds spans over it. The caller keeps the buffer as long as the Doc.
fn parse_bytes(data: const u8[:], buf: u8[>..]&, nodes: Node[>..]&, attrs: Attr[>..]&) -> Doc, bool {
    let text, ok = decode(buf, data);
    if !ok { return Doc { nodes: nodes[..], attrs: attrs[..], root: -1 }, false; }
    return parse(text, nodes, attrs);
}

// enc_put16 writes one unit of UTF-16.
fn enc_put16(out: u8[>..]&, u: i64, big: bool) {
    if big {
        out.push((u >> 8) as u8);
        out.push((u & 255) as u8);
    } else {
        out.push((u & 255) as u8);
        out.push((u >> 8) as u8);
    }
}

// enc_ref writes a character reference.
fn enc_ref(out: u8[>..]&, cp: i64) {
    out.append("&#");
    var digits: u8[>..] = [];
    var v = cp;
    while v > 0 {
        digits.push(('0' as i64 + v % 10) as u8);
        v = v / 10;
    }
    var d = digits.len;
    while d > 0 {
        d -= 1;
        out.push(digits[d]);
    }
    out.push(';');
}

// encode turns UTF-8 text into the bytes of the encoding. UTF-16 and
// UTF-32 without an order write a mark and little endian. It gives false
// for an unknown encoding or a text that is not UTF-8.
fn encode(out: u8[>..]&, text: const u8[:], encoding: const u8[:]) -> bool {
    let kind = enc_kind(encoding);
    if kind == ENC_UNKNOWN { return false; }
    if kind == ENC_UTF16 { out.push(0xFF as u8); out.push(0xFE as u8); }
    if kind == ENC_UTF32 { out.push(0xFF as u8); out.push(0xFE as u8); out.push(0 as u8); out.push(0 as u8); }
    var i: i64 = 0;
    while i < text.len {
        let c = text[i] as i64;
        var cp = c;
        var len: i64 = 1;
        if c >= 0xF0 { len = 4; cp = c & 7; }
        else if c >= 0xE0 { len = 3; cp = c & 15; }
        else if c >= 0xC0 { len = 2; cp = c & 31; }
        else if c >= 0x80 { return false; }
        if i + len > text.len { return false; }
        var k: i64 = 1;
        while k < len {
            let cc = text[i + k] as i64;
            if (cc & 0xC0) != 0x80 { return false; }
            cp = (cp << 6) | (cc & 0x3F);
            k += 1;
        }
        i += len;
        if kind == ENC_UTF8 {
            enc_put(out, cp);
        } else if kind == ENC_UTF16 || kind == ENC_UTF16LE || kind == ENC_UTF16BE {
            let big = kind == ENC_UTF16BE;
            if cp >= 0x10000 {
                let v = cp - 0x10000;
                enc_put16(out, 0xD800 + (v >> 10), big);
                enc_put16(out, 0xDC00 + (v & 0x3FF), big);
            } else {
                enc_put16(out, cp, big);
            }
        } else if kind == ENC_UTF32 || kind == ENC_UTF32LE || kind == ENC_UTF32BE {
            if kind == ENC_UTF32BE {
                out.push((cp >> 24) as u8); out.push(((cp >> 16) & 255) as u8);
                out.push(((cp >> 8) & 255) as u8); out.push((cp & 255) as u8);
            } else {
                out.push((cp & 255) as u8); out.push(((cp >> 8) & 255) as u8);
                out.push(((cp >> 16) & 255) as u8); out.push((cp >> 24) as u8);
            }
        } else if cp < 128 {
            out.push(cp as u8);
        } else {
            var found: i64 = -1;
            var t: i64 = 0;
            while t < 128 {
                if ENC_TABLE[kind * 128 + t] as i64 == cp { found = t; break; }
                t += 1;
            }
            if found >= 0 { out.push((128 + found) as u8); } else { enc_ref(out, cp); }
        }
    }
    return true;
}
