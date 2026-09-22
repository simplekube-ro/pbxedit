# Proposal

## Why

Adding a file is the operation agents perform most and the one the predecessor script got wrong in four distinct ways: a build file with no phase entry, a reused reference with no group child, the wrong file compiled because of a shared basename, and "NOT modified" printed after writing. Each came from performing an add as independent text inserts with nothing checking the result. This change makes an add one plan, checked against the rule set before and after it is written.

## What Changes

- Add `pbxedit add <path>…`: create whatever is missing — file reference, group chain, build file, phase entry — for each path, as one all-or-nothing plan.
- Infer targets and `platformFilters` from sibling files; derive `sourceTree` and `path` structurally; choose the build phase from the file type. `--target`, `--platform` and `--phase` override.
- Re-adding is a no-op; partial membership is completed using existing IDs.
- A path inside a synchronized folder is reported as already a member.
- Introduce the shared operation machinery in `PBXOps`: `Plan`, the scoped pre-write rule check, the atomic writer with post-write verification, `--dry-run`, and a result whose "modified" field is derived from whether bytes were replaced.

## Capabilities

### New Capabilities
- `add`: adding existing files on disk to the project with inferred, overridable membership, atomically and verifiably.

### Modified Capabilities

None.

## Non-goals

- Creating files or file templates; the file must already exist (pbxproj-only scope, `docs/design.md`).
- A config file. `conventions-config` adds it; until then flags are the only override.
- Adding folders as folder references, localized variants, frameworks, or package products.
- Editing synchronized-group exception sets.
- A `--group` flag to place a file in an arbitrary group; the group always follows the disk path.

## Impact

- New: `Sources/PBXOps/Plan/` (`Plan`, `Step`, `PlanBuilder`, the in-memory executor, `OperationRunner`, the unified diff), `Sources/PBXOps/Inference/` (`FileTypes`, `Conventions`, `Decision`), `Sources/PBXOps/Add/` (the add planner and group resolution), `Sources/pbxedit/Add.swift`; fixtures under `Tests/Fixtures/add/` (each with build configuration lists, because `xcodebuild -list` refuses a project without them, and the oracle lane reads every post-add fixture).
- `docs/design.md`: `--phase` added to the `add` row of the Commands table; the write pipeline is recorded as living in `PBXOps` (`OperationRunner`), called by the CLI, rather than in the CLI itself, so tests can drive it with hand-built plans; the status line names this change.
- `PBXModel`: a `Project` copy now gets its own index cache on first mutation (copy-on-write), so executing a plan on a copy cannot leave the caller's original with a patched section map or path index. Found by task 1.1's "a failing step leaves the original unchanged" test.
- Reuses `PathArgument` and `MembershipReport` from `query-command`; depends on `integrity-rules-lint` for the scoped check.
