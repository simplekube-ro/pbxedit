# Proposal

## Why

Issue #36, found by the RandomPlayer ship review: on a case-insensitive APFS volume, the macOS default, `pbxedit move` refuses a rename that changes only the case of a path.

```sh
git mv App/Views/Foo.swift App/Views/foo.swift
pbxedit move --keep-membership App/Views/Foo.swift App/Views/foo.swift
# error: both App/Views/Foo.swift and App/Views/foo.swift exist on disk, which looks like a copy, not a move
# exit 1
```

Measured on `1.4.1-dev` (`main` at `3c69566`) with the `move` fixture, on an APFS volume whose directory held only `foo.swift`. The disk precondition (move design D4) asks `FileManager.fileExists` for both paths. A case-insensitive volume answers yes for any spelling of an existing name, so after the rename `Foo.swift` still "exists" and the move looks like a copy. The workaround is two renames through a temporary name.

## What Changes

- The disk precondition asks whether a path exists **as spelled**, but only when both paths exist. A path exists as spelled when every component below the source root appears, spelled exactly so, in its directory's listing. On a case-insensitive volume that separates the name the directory holds from the other spellings that resolve to it. On a case-sensitive volume the two questions always agree.
- After a case-only rename on disk, `move Foo.swift foo.swift` is a move. The reference keeps its ID, its `path` (or `name`) gets the new spelling, the build files keep their IDs, and membership follows the destination as for any rename in one directory. This holds with or without `--keep-membership`. A directory whose name changes only in case (`App/Views` → `App/views`) moves the same way.
- Before the rename on disk, the same command is `notMovedOnDisk`, "move the file on disk first", as on a case-sensitive volume. It is no longer the misleading "looks like a copy".
- `DiskReader` gains `existsAsSpelled(_:)`. Its default answer is `exists(_:)`, which is correct for every reader that is not a case-insensitive file system. `FileSystemDiskReader` implements it by listing directories.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `move`: the requirement "The disk must already reflect the move" states that existence is judged by the spelling the directory holds whenever both paths resolve on disk. Two scenarios are added: a case-only rename performed on disk, and one not yet performed.

## Non-goals

- Case-insensitive lookup in the **project**. File lookup stays by exact resolved path (a non-negotiable). `move Foo.swift foo.swift` finds the reference spelled `Foo.swift`, and a reference already resolving to `foo.swift` is still `destinationTaken`.
- Case-folding in the D1/D2 disk rules of `lint`. A reference whose spelling differs from the disk only in case still passes D1 on a case-insensitive volume. That is a separate question, about what Xcode builds, and it is left to its own change.
- Unicode normalization differences (NFC against NFD). Swift string comparison already treats the two as equal, and APFS preserves the spelling it was given, so nothing new is decided here.
- Moving anything on disk. `pbxedit` still edits only `project.pbxproj` (§ Out of scope for v1, "moving and deleting files on disk").

Checked against `docs/design.md` § Out of scope for v1: nothing here touches it. The change is a correctness fix inside the shipped `move` capability.

## Impact

- `Sources/PBXOps/Rules/DiskReader.swift`: `existsAsSpelled(_:)` on the protocol, with a default implementation. `FileSystemDiskReader` implements it by checking each component against its parent directory's listing.
- `Sources/PBXOps/Move/MovePlanner.swift`: `checkDisk` asks the spelled question when both plain answers are yes.
- Tests: `MemoryDisk` gains a case-insensitive mode. There are new `MovePlannerTests` (a file and a directory renamed by case, performed and not performed, and the call count), `DiskReaderTests` for `FileSystemDiskReader` on a real temporary directory, and `MoveCommandTests` for the issue's repro through the binary.
- `docs/design.md`: the status line, the `move` Commands row, and a Motivation-table row for issue #36. A dated note goes at D4 of the archived `move-command` design.
- No new dependency.
