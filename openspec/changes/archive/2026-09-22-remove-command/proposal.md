# Proposal

## Why

There is no way to take a file out of the project except by hand: delete the build file, its phase entry, the group child and the file reference, in four places, without missing one. A missed one is a dangling ID (S2) or a build file in no phase (M1). Deleting a file on disk and forgetting the project is the commonest cause of the "missing file" build error.

## What Changes

- Add `pbxedit remove <path>…`: remove every trace of a file from the project — build files, phase entries, group child, file reference — as one all-or-nothing plan through the shared operation pipeline.
- `--target <name>` detaches the file from that target only and keeps it in the project.
- When a file belongs to several targets, require `--target` or `--all`, so a shared source is never removed from a target by accident.
- Remove groups the operation leaves empty.
- Refuse what v1 cannot do correctly: children of variant groups (localized variants) and version groups (versioned models), and paths that are members only through a synchronized folder.

## Capabilities

### New Capabilities
- `remove`: removing a file's membership from one target or from the project, atomically and without leaving dangling objects.

### Modified Capabilities

None.

## Non-goals

- Deleting the file on disk (pbxproj-only scope, `docs/design.md`).
- Removing targets, groups by name, or anything that is not a file.
- Removing a whole directory's members in one argument. `move-command` introduces directory arguments; `remove` takes files.
- Editing synchronized-group exception sets to exclude a file.

## Impact

- New: `Sources/PBXOps/Remove/RemovePlanner.swift`, `Sources/pbxedit/Remove.swift`, tests, fixtures under `Tests/Fixtures/remove/` (`app.pbxproj`, a superset of `add/app.pbxproj` with build configuration lists so the oracle lane can read it; `roots.pbxproj`).
- Reuses `OperationRunner`, `Plan`, `PlanBuilder`, `PlanError`, `PathArgument`, `MembershipReport`, and the `add` renderer, which moves from `Add.swift` to `Sources/pbxedit/OperationReport.swift` unchanged (`OperationReport`, formerly `AddReport`) so both commands print the same shape. No new `Step` kinds: `removeChild`, `removePhaseEntry` and `deleteObject` were defined with `add-command`. `PlanError` gains the refusal cases; `Plan` gains `deletedObjects` and the tokenized `deletedObjectsMentioned(in:)`; `OperationRunner` gains a debug-only assertion on them.
- `docs/design.md`: the `remove` row of the Commands table gains `--target`/`--all` semantics, "removes groups left empty", exit `1` on an unknown path and the refusals; the status line names this change.
- Depends on `add-command`.
