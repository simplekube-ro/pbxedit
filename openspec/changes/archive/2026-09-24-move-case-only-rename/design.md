# Design

## Context

See proposal.md (Why) and issue #36. Move design D4 checks the disk with two questions per file, `exists(to)` and `exists(from)`, and maps the four answers to a move or one of three refusals. `FileSystemDiskReader.exists` is `FileManager.fileExists`. On a case-insensitive volume that call resolves a path by case-folded lookup, so both spellings of one name answer yes. A case-only rename therefore always lands in the "both present" row.

Measured on `1.4.1-dev` (APFS, case-insensitive; the directory lists only `foo.swift`):

| question | answer |
|---|---|
| `exists("App/Views/Foo.swift")` | yes |
| `exists("App/Views/foo.swift")` | yes |
| outcome | `looksLikeACopy`, exit `1` |

## Goals / Non-Goals

Goals: a case-only rename performed on disk is a move, for a file and for a directory. The same command before the rename is `notMovedOnDisk`. A real copy is still `looksLikeACopy`. Nothing changes on a case-sensitive volume or for any move whose two paths do not both resolve.

Non-goals: see proposal.md.

## Decisions

### D1. A third question, asked only when both paths resolve

`DiskReader` gains `existsAsSpelled(_ path: String) -> Bool`: whether an entry exists at `path` with every component below the source root spelled exactly as its directory lists it. `checkDisk` keeps its two questions. When both answer yes, it asks `existsAsSpelled` of each path and maps those two answers through the same table:

| `from` as spelled | `to` as spelled | outcome |
|---|---|---|
| no | yes | a move: the rename happened on disk |
| yes | no | `notMovedOnDisk`: the directory still holds the old spelling |
| yes | yes | `looksLikeACopy`: two entries, as on a case-sensitive volume |
| no | no | `destinationMissing`: the disk holds a third spelling, so neither path exists as given |

Every move whose paths differ in more than case, on any volume, still costs two questions. The call count in `MovePlannerTests` stays `2`, and D4's "nothing else is read from the disk" holds except in the one row where the answers are ambiguous.

*Alternative considered:* comparing the two paths' file IDs (device and inode), as the issue suggests. Rejected because it answers the wrong question. Equal IDs show that both spellings name one file. They do not show which spelling the directory holds, so the command could not tell a rename performed on disk from one not yet performed, and would record a rename the disk does not have. The directory listing answers both.

*Alternative considered:* `realpath(3)`, which on macOS returns the stored case. Rejected because it also resolves symbolic links, so a path through a linked directory would never compare equal to its own spelling. Listing the parents asks about the name alone.

### D2. `FileSystemDiskReader.existsAsSpelled` lists the parents

For a source-root-relative path, the reader walks the components from the source root. Each one must appear in `contentsOfDirectory` of the directory reached so far, compared as Swift strings, which are equal under canonical Unicode equivalence. A `.` or `..` component is followed without a check. Normalized move paths do not carry one, but a `SOURCE_ROOT` reference may start with `..`. An absolute path is walked the same way from `/`. The source root's own spelling is not checked, because the project's paths are relative to it and cannot change its case.

The default `existsAsSpelled` in a protocol extension returns `exists(path)`. That is exact for readers that are not case-insensitive file systems: `MemoryDisk` in its default mode, merge's `ReplayDisk`, and the tests' `MovedDisk`. None of them needs changing.

### D3. The project side is unchanged

`resolveMoves` and `validate` look references up by exact resolved path, so `Foo.swift` finds the reference and `foo.swift` is not "taken". The rename then runs the ordinary in-directory path. The destination group resolves to the same group, the listing stays in place, and `setAttribute` rewrites `path` (or `name`) and every comment naming the file. A directory renamed by case is an ordinary directory move (move design D5): `App/views` is a new group path, members are re-parented into it, and the old `Views` group is pruned. On disk each member resolves under both spellings, and D1 decides each one.

## Risks / Trade-offs

- [A case-insensitive volume where a directory component on the path has also changed case] → D2 checks every component below the source root, so a member of a directory renamed by case is judged by its directory's new spelling.
- [Cost: one directory listing per component, for each file whose two paths both resolve] → Only a case-only rename reaches this, and for a directory rename the cost is members × depth small listings. Release `PerformanceTests` do not exercise `move`. The directory case in `MovePlannerTests` runs in memory.
- [A reader other than the file system that is case-insensitive] → None exists. A new one would implement `existsAsSpelled` itself.

## Migration

None. A command that exited `0` still does. The only change in exit code is for a case-only rename performed on disk, which exits `0` instead of `1`, on a case-insensitive volume.
