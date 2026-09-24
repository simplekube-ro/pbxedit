# Tasks

## 1. Spelled existence

- [x] 1.1 `DiskReaderTests` (new), on a real temporary directory: `existsAsSpelled` is true for a file and a nested directory spelled as listed, false for a different case of the file or of a directory component, false for a missing path, and follows a leading `..`; on a case-insensitive volume `exists` is true for the other case, which the test records instead of assuming. Fails to compile before 1.2
- [x] 1.2 `DiskReader.existsAsSpelled(_:)` with the default `exists(_:)` in a protocol extension, and `FileSystemDiskReader`'s listing walk; verify 1.1 passes

## 2. The planner

- [x] 2.1 `MemoryDisk(_:caseInsensitive:)`: `exists` and `files(in:)` fold case and `existsAsSpelled` does not. `MovePlannerTests`: a case-only file rename performed on disk plans as an in-place rename (the `path` step alone, both with and without `keepMembership`), applies with the rule set clean and `plutil -lint` passing, and costs four disk questions; before the rename it is `notMovedOnDisk`; with both spellings listed it is `looksLikeACopy`; a third spelling is `destinationMissing`; `App/Views/Legacy` → `App/Views/legacy` moves all five members and prunes the old groups; a case-sensitive disk still costs two questions. Red on `main`: `looksLikeACopy`
- [x] 2.2 `checkDisk` asks `existsAsSpelled` of both paths when both exist (design D1); verify 2.1 passes and the existing `MovePlannerTests` are unchanged

## 3. The command

- [x] 3.1 `MoveCommandTests`: the issue's repro through the binary. `App/Views/Foo.swift` is created and renamed to `foo.swift` on disk, then `move --keep-membership` exits `0` and the written project spells `path = foo.swift;` with `AA0000000000000000000120` and `BB0000000000000000000020` unchanged, with `lint` and `plutil -lint` clean; before the rename it exits `1`, "move the file on disk first", and writes nothing. Red on `main` on a case-insensitive volume (the default for macOS runners)

## 4. Verification and reconciliation

- [x] 4.1 `swift build` and the whole `swift test` suite green with `ORACLE_REQUIRED=1`. Read the summary: counts, and none skipped
- [x] 4.2 Release `PerformanceTests` green
- [x] 4.3 `docs/design.md` reconciled: status line, the `move` Commands row, a Motivation-table row for issue #36, and a dated note at D4 of the archived `move-command` design
- [x] 4.4 `openspec validate move-case-only-rename --strict` green and `TODO.md` § 21 filled in with the evidence for each box
