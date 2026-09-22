// PBXSyntax — a lossless syntax tree for old-style ASCII property lists.
//
// This module knows nothing about Xcode. It reads bytes into a tree that
// remembers every byte, allows surgical edits, and writes the tree back so
// that only the edited parts differ from the input.
