// PBXOps — operations over a project model.
//
// This layer turns the model's observations into judgements (the rule set)
// and into plans (pure functions from a model, a request and conventions).
// Planners never touch the disk; the one thing here that does is
// `OperationRunner`, which executes a plan, checks it, writes the project
// file atomically and verifies what it wrote, on behalf of the command line.
