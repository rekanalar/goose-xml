// The pull reader for the xml package.
//
// The reader gives one event per call to next and builds no tree. The
// caller owns the buffers, so the memory use stays flat for a document of
// any size. The names in the events are raw: the pull reader does not
// resolve namespaces. Use ns_split on a name to cut the prefix off.
//
// The faults match parse: a mismatched or unclosed tag, a bad attribute,
// an unknown entity, text outside the root, a second root, and depth
// beyond the limit.
namespace xml;

import std;
import tree;
import parse;
import parse_attrs;

// The kinds of an event.
const EV_START = 0;
const EV_END = 1;
const EV_TEXT = 2;
const EV_COMMENT = 3;
const EV_CDATA = 4;
const EV_PI = 5;
const EV_EOF = 6;

// Event holds one event. For a start event the attributes are the
// attrs array of the caller, from the first entry. Text and CDATA
// events hold the source form in content, so call decode_entities on a
// text event.
struct Event {
    kind: i32,
    name: const u8[:],
    content: const u8[:],
}

// Open holds the name of one open element.
struct Open {
    name: const u8[:],
}

// Reader holds the place in the input. A self-closing tag gives a start
// event, and the next call gives its end event.
struct Reader {
    s: const u8[:],
    pos: i64,
    pending: bool,
    pending_name: const u8[:],
    root_seen: bool,
    done: bool,
    checked: bool,
}

// reader starts a reader over the text. The text must outlive it.
fn reader(s: const u8[:]) -> Reader {
    return Reader { s: s, pos: 0, pending: false, pending_name: s[0..0], root_seen: false, done: false, checked: false };
}

// next reads one event. The open array holds the names of the open
// elements, and the attrs array holds the attributes of a start event.
// Both belong to the caller and start empty. A fault gives false. After
// the end of the root, whitespace is skipped and the event is EV_EOF.
fn next(r: Reader&, open: Open[>..]&, attrs: Attr[>..]&) -> Event, bool {
    let s = r.s;
    let none = Event { kind: EV_EOF, name: s[0..0], content: s[0..0] };
    attrs.clear();
    if !r.checked {
        // The first call skips a byte order mark and checks every character.
        r.checked = true;
        if starts_at(s, 0, "\xef\xbb\xbf") { r.pos = 3; }
        if !check_chars(s, r.pos) { return none, false; }
    }
    if r.pending {
        r.pending = false;
        if open.len == 0 { r.done = true; }
        return Event { kind: EV_END, name: r.pending_name, content: s[0..0] }, true;
    }
    while r.pos < s.len {
        if r.done {
            if is_space(s[r.pos]) { r.pos += 1; continue; }
            return none, false;
        }
        let pos = r.pos;
        if s[pos] != '<' {
            var end = pos;
            while end < s.len && s[end] != '<' { end += 1; }
            let text = s[pos..end];
            if open.len > 0 {
                if !valid_entities(text) { return none, false; }
                r.pos = end;
                return Event { kind: EV_TEXT, name: s[0..0], content: text }, true;
            }
            for ch in text { if !is_space(ch) { return none, false; } }
            r.pos = end;
            continue;
        }
        if pos + 1 >= s.len { return none, false; }
        let c = s[pos + 1];
        if c == '/' {
            let name_end = read_name(s, pos + 2);
            if name_end < 0 { return none, false; }
            var j = name_end;
            while j < s.len && is_space(s[j]) { j += 1; }
            if j >= s.len || s[j] != '>' || open.len == 0 { return none, false; }
            let name = s[pos + 2..name_end];
            if open[open.len - 1].name != name { return none, false; }
            open.pop();
            if open.len == 0 { r.done = true; }
            r.pos = j + 1;
            return Event { kind: EV_END, name: name, content: s[0..0] }, true;
        }
        if c == '!' {
            if pos + 3 < s.len && s[pos + 2] == '-' && s[pos + 3] == '-' {
                var j = pos + 4;
                while j + 2 < s.len && !(s[j] == '-' && s[j + 1] == '-' && s[j + 2] == '>') { j += 1; }
                if j + 2 >= s.len { return none, false; }
                r.pos = j + 3;
                if open.len == 0 { continue; }
                return Event { kind: EV_COMMENT, name: s[0..0], content: s[pos + 4..j] }, true;
            }
            if pos + 8 < s.len && s[pos + 2..pos + 9] == "[CDATA[" {
                var j = pos + 9;
                while j + 2 < s.len && !(s[j] == ']' && s[j + 1] == ']' && s[j + 2] == '>') { j += 1; }
                if j + 2 >= s.len || open.len == 0 { return none, false; }
                r.pos = j + 3;
                return Event { kind: EV_CDATA, name: s[0..0], content: s[pos + 9..j] }, true;
            }
            // A DOCTYPE: skip to the closing '>' outside the subset.
            var j = pos + 2;
            var depth = 0;
            while j < s.len {
                if s[j] == '[' { depth += 1; }
                if s[j] == ']' { depth -= 1; }
                if s[j] == '>' && depth == 0 { break; }
                j += 1;
            }
            if j >= s.len { return none, false; }
            r.pos = j + 1;
            continue;
        }
        if c == '?' {
            var j = pos + 2;
            while j + 1 < s.len && !(s[j] == '?' && s[j + 1] == '>') { j += 1; }
            if j + 1 >= s.len { return none, false; }
            let name_end = read_name(s, pos + 2);
            if name_end < 0 || name_end > j { return none, false; }
            let target = s[pos + 2..name_end];
            if find_colon(target) >= 0 { return none, false; }
            r.pos = j + 2;
            if target == "xml" || target == "XML" || open.len == 0 { continue; }
            var from = name_end + 1;
            if from > j { from = j; }
            return Event { kind: EV_PI, name: target, content: s[from..j] }, true;
        }
        // A start tag.
        if open.len >= MAX_DEPTH { return none, false; }
        if open.len == 0 && r.root_seen { return none, false; }
        let name_end = read_name(s, pos + 1);
        if name_end < 0 { return none, false; }
        let name = s[pos + 1..name_end];
        let after, self_closing, ok = scan_attrs(s, name_end, attrs);
        if !ok { return none, false; }
        r.root_seen = true;
        r.pos = after;
        if self_closing {
            r.pending = true;
            r.pending_name = name;
        } else {
            open.push(Open { name: name });
        }
        return Event { kind: EV_START, name: name, content: s[0..0] }, true;
    }
    // The end of the input: only a closed root is whole.
    if open.len > 0 || !r.root_seen { return none, false; }
    return none, true;
}

// ns_split cuts a raw name at its colon. It gives the prefix, which is
// empty without a colon, and the local name.
fn ns_split(name: const u8[:]) -> const u8[:], const u8[:] {
    let colon = find_colon(name);
    if colon < 0 { return name[0..0], name; }
    return name[0..colon], name[colon + 1..];
}
