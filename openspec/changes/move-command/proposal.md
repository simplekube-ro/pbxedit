# Proposal

## Why

After `git mv`, the project still points at the old path. The predecessor's answer was four manual edits per file — delete the old build file, delete its phase entry, fix the group or rewrite the path, verify — with a one-off script recommended for more than two files. Doing it as `remove` plus `add` works but throws away the file reference's ID, producing a larger diff and losing the link between the old and new entry in review.

## What Changes

- Add `pbxedit move <from> <to>`: keep the file reference, re-parent it to the group for its new directory, rewrite its `path` and `sourceTree`, refresh every comment that names it, and prune groups left empty.
- When the destination's conventions imply different targets or `platformFilters`, swap membership accordingly and say so; `--keep-membership` leaves membership as it was.
- Accept a directory as `<from>`: every member under it moves to the corresponding path under `<to>`, as one plan.
- Require the disk to already reflect the move: destination present, source absent.

## Capabilities

### New Capabilities
- `move`: updating the project after a file or directory has been moved or renamed on disk, preserving object identity.

### Modified Capabilities

None.

## Non-goals

- Moving files on disk or invoking `git mv` (pbxproj-only scope, `docs/design.md`).
- Moving into or out of a localized variant group.
- Renaming or moving groups as objects independent of disk paths.
- Moving between two project files.

## Impact

- New: `Sources/PBXOps/Move/`, `Sources/pbxedit/Move.swift`, tests, fixtures.
- Reuses the add planner's group resolution and `Conventions`, the remove planner's pruning, and the model's `refreshAnnotations`.
- `docs/design.md`: the `move` row of the Commands table gains directory arguments and `--keep-membership`.
- Depends on `remove-command`.
