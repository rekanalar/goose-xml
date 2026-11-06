// The builder for the xml package.
//
// build writes a subtree of the tree as XML text into the buffer of the
// caller. The walk follows the child and sibling links with an explicit
// stack, so no recursion runs. Text escapes '<', '>' and '&'. Attribute
// values escape '<', '>', '&' and '"'. Comments and CDATA write
// verbatim.
namespace xml;

import std;
import tree;

fn encode_text(out: u8[>..]&, s: const u8[:]) {
    for c in s {
        if c == '<' {
            out.append("&lt;");
        } else if c == '>' {
            out.append("&gt;");
        } else if c == '&' {
            out.append("&amp;");
        } else {
            out.push(c);
        }
    }
}

fn encode_attr(out: u8[>..]&, s: const u8[:]) {
    for c in s {
        if c == '<' {
            out.append("&lt;");
        } else if c == '>' {
            out.append("&gt;");
        } else if c == '&' {
            out.append("&amp;");
        } else if c == '"' {
            out.append("&quot;");
        } else {
            out.push(c);
        }
    }
}

// build writes the node and its subtree into out. The root node writes a
// whole document.
fn build(out: u8[>..]&, doc: Doc&, root_id: i32) {
    if root_id < 0 || root_id >= doc.nodes.len { return; }
    // The stack holds work items. A positive number is a node to open. A
    // negative number is a close tag of the node with the index that the
    // number holds.
    var stack: i32[>..] = [];
    // The scratch buffer holds the decoded text of one node.
    var scratch: u8[>..] = [];
    stack.push(root_id);
    while stack.len > 0 {
        let item = stack[stack.len - 1];
        stack.pop();
        if item < 0 {
            let close_id = (-item - 2);
            out.append("</");
            out.append(doc.nodes[close_id].name);
            out.append(">");
            continue;
        }
        let id = item;
        let n = doc.nodes[id];
        if n.kind == KIND_TEXT {
            // The text of the node holds the source form. The writer
            // decodes it and escapes it again, so the text stays
            // well-formed.
            scratch.clear();
            decode_entities(scratch, n.content);
            encode_text(out, scratch[..]);
        } else if n.kind == KIND_COMMENT {
            out.append("<!--");
            out.append(n.content);
            out.append("-->");
        } else if n.kind == KIND_CDATA {
            out.append("<![CDATA[");
            out.append(n.content);
            out.append("]]>");
        } else if n.kind == KIND_PI {
            out.append("<?");
            out.append(n.name);
            if n.content.len > 0 {
                out.append(" ");
                out.append(n.content);
            }
            out.append("?>");
        } else {
            out.append("<");
            out.append(n.name);
            var a = 0;
            while a < n.attr_count {
                let attr = doc.attrs[n.attr_start + a];
                out.append(" ");
                out.append(attr.name);
                out.append("=\"");
                scratch.clear();
                decode_entities(scratch, attr.value);
                encode_attr(out, scratch[..]);
                out.append("\"");
                a += 1;
            }
            if n.first_child < 0 {
                out.append("/>");
                continue;
            }
            out.append(">");
            // The close tag comes first on the stack, so it runs last. The
            // children go in reverse, so the walk gives document order.
            stack.push(-(id + 2));
            var child_ids: i32[>..] = [];
            var child_id = n.first_child;
            while child_id >= 0 {
                child_ids.push(child_id);
                child_id = doc.nodes[child_id].next_sibling;
            }
            var k = child_ids.len - 1;
            while k >= 0 {
                stack.push(child_ids[k]);
                k -= 1;
            }
        }
    }
}
