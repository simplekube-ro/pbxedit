// PBXOps — operations over a project model.
//
// This layer turns the model's observations into judgements (the rule set)
// and, in later changes, into plans. It reads the model and never writes a
// file; the command-line layer owns the disk.
