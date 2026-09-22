# Proposal

## Why

After `git mv`, the project still points at the old path. The predecessor's answer was four manual edits per file — delete the old build file, delete its phase entry, fix the group or rewrite the path, verify — with a one-off script recommended for more than two files. Doing it as `remove` plus `add` works but throws away the file reference's ID, producing a larger diff and losing the link between the old and new entry in review.

## What Changes

- Add `pbxedit move <from> <to>`: keep the file reference, re-parent it to the group for its new directory, rewrite its `path`, `sourceTree` and `name` where they change, refresh every comment that names it, and prune groups left empty.
- When the destination's conventions imply different targets or `platformFilters`, swap membership accordingly and say so; `--keep-membership` leaves membership as it was; `--target` and `--platform` override as for `add`.
- Accept a directory as `<from>`: every member under it moves to the corresponding path under `<to>`, as one plan.
- Require the disk to already reflect the move: destination present, source absent. The tool moves nothing on disk — the user (or `git mv`) does.

## Capabilities

### New Capabilities
- `move`: updating the project after a file or directory has been moved or renamed on disk, preserving object identity.

### Modified Capabilities

None.

## Non-goals

- Moving files on disk or invoking `git mv` (pbxproj-only scope, `docs/design.md` § Out of scope for v1: "moving and deleting files on disk").
- Moving into or out of a localized variant group or a versioned model group.
- Renaming or moving groups as objects independent of disk paths.
- Moving between two project files.
- Editing synchronized groups or their exception sets (`docs/design.md` § Out of scope for v1).

## Impact

- New: `Sources/PBXOps/Move/MovePlanner.swift`, `Sources/pbxedit/Move.swift`, `Tests/PBXOpsTests/MovePlannerTests.swift`, `Tests/CLITests/MoveCommandTests.swift`, the fixture `Tests/Fixtures/move/app.pbxproj`.
- Reuses the add planner's group resolution and reference spelling (`PlanBuilder`), `Conventions`, the remove planner's detach and pruning (made internal rather than private, behaviour unchanged), the model's annotation refresh (through `setAttribute`), `OperationRunner` and `OperationReport`.
- `PlanError` gains the move refusals and a helper that appends `--keep-membership` to the inference remedies; `OperationReport` gains a per-path label and an optional `moves` array in its JSON (present only for `move`); `DiskReader` is taken by a planner for the first time (design D4).
- `docs/design.md`: the `move` row of the Commands table gains directory arguments, `--keep-membership`, the disk preconditions and the refusals; § Architecture 3 lists `MovePlanner`.
- Depends on `remove-command`.
