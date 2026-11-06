// xml - XML parsing and building for Goose.
//
// The package parses XML 1.0 core into a tree, gives a walk API over the
// tree, and builds XML text back from the tree. Comments, CDATA,
// processing instructions and the five predefined entities are in.
// Namespaces, DTDs and validation are out.
//
// The repository is goose-xml. The import name is "xml".
namespace xml;

import std;
import tree;
import parse;
import build;
