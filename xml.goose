// xml - XML parsing and building for Goose.
//
// The package parses XML 1.0 core into a tree, gives a walk API over the
// tree, and builds XML text back from the tree. Comments, CDATA,
// processing instructions and the five predefined entities are in.
// Namespaces resolve into a URI and a local name. A pull reader gives
// events with no tree. DTDs and validation are out.
//
// The repository is goose-xml. The import name is "xml".
namespace xml;

import std;
import tree;
import parse;
import build;
import pull;
import path;
import read;
import build_tree;
import write;
import canon;
import encoding_data;
import encoding;
import target;
