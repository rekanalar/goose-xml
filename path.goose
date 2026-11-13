// The path language of ElementPath for the xml package.
//
// A path holds steps. A step is a child step, a star step, the self
// step, the parent step, a descendant step or a predicate. The rules
// follow the ElementPath module of Python 3.14, read from its source.
namespace xml;

import std;
import tree;

// NO_PREFIXES stands for an empty map of prefixes. One empty name maps
// to an empty uri, which no path uses.
const NO_PREFIXES: const u8[:][] = [""];

// The kinds of a step.
const S_CHILD = 0;
const S_STAR = 1;
const S_SELF = 2;
const S_PARENT = 3;
const S_DESC = 4;
const S_HAS_ATTR = 5;
const S_ATTR_EQ = 6;
const S_ATTR_NE = 7;
const S_HAS_CHILD = 8;
const S_CHILD_EQ = 9;
const S_CHILD_NE = 10;
const S_TEXT_EQ = 11;
const S_TEXT_NE = 12;
const S_INDEX = 13;
const S_LAST = 14;

// A step of a path.
struct Step {
    kind: i32,
    tag: const u8[:],
    key: const u8[:],
    value: const u8[:],
    index: i64,
}

// A token of a path.
struct Tok {
    ttype: const u8[:],
    tag: const u8[:],
}

// path_name_stop says whether the byte ends a name. The name of
// ElementPath holds no slash, no bracket, no parenthesis, no at sign,
// no equal sign, no exclamation mark and no space.
fn path_name_stop(c: u8) -> bool {
    if c == '/' || c == '[' || c == ']' || c == '(' || c == ')' { return true; }
    if c == '@' || c == '=' || c == '!' { return true; }
    return is_space(c);
}

// path_has_colon says whether the name holds a prefix. The package has
// no map of prefixes, so Python raises a SyntaxError for such a name.
fn path_has_colon(t: const u8[:]) -> bool {
    if t.len > 0 && t[0] == '{' { return false; }
    var i: i64 = 0;
    while i < t.len {
        if t[i] == ':' { return true; }
        i += 1;
    }
    return false;
}

// path_key writes {uri}local into the buffer.
fn path_key(buf: u8[>..]&, uri: const u8[:], local: const u8[:]) -> const u8[:] {
    let start = buf.len;
    buf.push('{');
    buf.append(uri);
    buf.push('}');
    buf.append(local);
    return buf[start..buf.len];
}

// path_name_end gives the end of the name that starts at i. A name may
// start with a namespace in braces, and that part may hold slashes.
fn path_name_end(path: const u8[:], i: i64) -> i64 {
    var e = i;
    if path[i] == '{' {
        var j = i + 1;
        while j < path.len && path[j] != '}' { j += 1; }
        if j < path.len && j > i + 1 {
            e = j + 1;
            while e < path.len && !path_name_stop(path[e]) { e += 1; }
            if e > j + 1 { return e; }
            e = i;
        }
    }
    while e < path.len && !path_name_stop(path[e]) { e += 1; }
    return e;
}

// path_tokenize splits the path into the tokens of ElementPath. It
// follows the regular expression of Python. It gives false where Python
// raises a SyntaxError for a prefix.
fn path_tokenize(out: Tok[>..]&, path: const u8[:], kbuf: u8[>..]&, pn: const u8[:][:], pu: const u8[:][:]) -> bool {
    var i: i64 = 0;
    var after_at = false;
    var dflt_at: i64 = -1;
    var d: i64 = 0;
    while d < pn.len { if pn[d].len == 0 { dflt_at = d; } d += 1; }
    let has_dflt = dflt_at >= 0 && pu[dflt_at].len > 0;
    while i < path.len {
        let c = path[i];
        let two = if i + 1 < path.len { path[i + 1] } else { 0 as u8 };
        if c == '\'' || c == '"' {
            var e = i + 1;
            while e < path.len && path[e] != c { e += 1; }
            if e < path.len {
                out.push(Tok { ttype: "'", tag: path[i + 1..e] });
                i = e + 1;
                continue;
            }
        }
        if c == ':' && two == ':' {
            out.push(Tok { ttype: "::", tag: "" });
            i += 2;
        } else if c == '/' && two == '/' {
            out.push(Tok { ttype: "//", tag: "" });
            i += 2;
        } else if c == '.' && two == '.' {
            out.push(Tok { ttype: "..", tag: "" });
            i += 2;
        } else if c == '(' && two == ')' {
            out.push(Tok { ttype: "()", tag: "" });
            i += 2;
        } else if c == '!' && two == '=' {
            out.push(Tok { ttype: "!=", tag: "" });
            i += 2;
        } else if c == '/' || c == '.' || c == '*' || c == ':' || c == '[' || c == ']'
            || c == '(' || c == ')' || c == '@' || c == '=' {
            out.push(Tok { ttype: path[i..i + 1], tag: "" });
            i += 1;
            if c == '@' { after_at = true; continue; }
        } else if is_space(c) {
            while i < path.len && is_space(path[i]) { i += 1; }
            out.push(Tok { ttype: "", tag: "" });
        } else if c == '!' {
            // A lone exclamation mark matches no token. Python skips it.
            i += 1;
        } else {
            let e = path_name_end(path, i);
            let name = path[i..e];
            var tag = name;
            if name[0] != '{' {
                var colon: i64 = -1;
                var q: i64 = 0;
                while q < name.len { if name[q] == ':' { colon = q; break; } q += 1; }
                if colon >= 0 {
                    // A prefix needs the map of the caller.
                    var uri_at: i64 = -1;
                    var m: i64 = 0;
                    while m < pn.len { if pn[m] == name[0..colon] { uri_at = m; break; } m += 1; }
                    if uri_at < 0 || pu[uri_at].len == 0 { return false; }
                    tag = path_key(kbuf, pu[uri_at], name[colon + 1..]);
                } else if has_dflt && !after_at {
                    tag = path_key(kbuf, pu[dflt_at], name);
                }
            }
            out.push(Tok { ttype: "", tag: tag });
            i = e;
        }
        after_at = false;
    }
    return true;
}

// path_is_number says whether the text holds a number. The position of
// a predicate is a number.
fn path_is_number(t: const u8[:]) -> bool {
    if t.len == 0 { return false; }
    var i: i64 = 0;
    if t[0] == '-' { i = 1; }
    if i >= t.len { return false; }
    while i < t.len {
        if t[i] < '0' || t[i] > '9' { return false; }
        i += 1;
    }
    return true;
}

// path_number reads the number of the text. The text holds a number.
fn path_number(t: const u8[:]) -> i64 {
    var v: i64 = 0;
    var i: i64 = 0;
    if t[0] == '-' { i = 1; }
    while i < t.len {
        v = v * 10 + (t[i] - '0') as i64;
        i += 1;
    }
    if t[0] == '-' { return -v; }
    return v;
}

// path_tag_match tells whether the element with the uri and the local
// name matches the name of a path. The name is a local name, a name of
// the form {uri}local, or one of the wildcards: *, {*}local, {uri}* and
// {}*. A plain name matches an element that has no namespace.
fn path_tag_match(uri: const u8[:], local: const u8[:], tag: const u8[:]) -> bool {
    if tag.len == 0 { return false; }
    if tag == "*" { return true; }
    if tag[0] != '{' { return uri.len == 0 && local == tag; }
    var e: i64 = 1;
    while e < tag.len && tag[e] != '}' { e += 1; }
    if e >= tag.len { return uri.len == 0 && local == tag; }
    let ns = tag[1..e];
    let rest = tag[e + 1..];
    if ns != "*" && uri != ns { return false; }
    return rest == "*" || local == rest;
}
