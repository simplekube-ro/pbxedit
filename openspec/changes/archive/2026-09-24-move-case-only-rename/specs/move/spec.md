# Spec Delta

## MODIFIED Requirements

### Requirement: The disk must already reflect the move
The command SHALL read the disk only to check, for each moved file, that `<to>` exists and `<from>` does not, and SHALL exit `1` without writing otherwise — before anything is planned, also under `--dry-run`. When both paths resolve to an entry on disk, as both spellings of one name do on a case-insensitive volume, the command SHALL judge each path by the spelling its directories hold: a path exists as spelled when every component below the source root appears, spelled exactly so, in its directory's listing. Only a path that exists as spelled counts as existing. `<to>` alone existing as spelled is a move, `<from>` alone is a move not yet performed, both is a copy, and neither is a missing destination.

#### Scenario: Move not yet performed
- **WHEN** `App/Views/Foo.swift` still exists on disk and `App/Features/Foo.swift` does not
- **THEN** the command exits `1` saying the file must be moved on disk first

#### Scenario: Both exist
- **WHEN** both paths exist on disk
- **THEN** the command exits `1` saying this looks like a copy, and suggests `add` for the new file

#### Scenario: Neither exists
- **WHEN** neither path exists on disk
- **THEN** the command exits `1` saying the destination does not exist

#### Scenario: A case-only rename performed on disk
- **WHEN** on a case-insensitive volume `App/Views/Foo.swift` has been renamed on disk to `App/Views/foo.swift`, so the directory lists only `foo.swift`, and `pbxedit move --keep-membership App/Views/Foo.swift App/Views/foo.swift` runs
- **THEN** the command exits `0`, `AA0000000000000000000120` keeps its ID and its listing in group `AA0000000000000000000003` and is spelled `path = foo.swift;`, build file `BB0000000000000000000020` keeps its ID in `App`'s Sources `CC0000000000000000000001`, and every comment naming the file reads `foo.swift`; the same holds without `--keep-membership`

#### Scenario: A directory renamed by case
- **WHEN** on a case-insensitive volume `App/Views/Legacy` has been renamed on disk to `App/Views/legacy` and `pbxedit move App/Views/Legacy App/Views/legacy` runs
- **THEN** the command exits `0`, the five references `AA0000000000000000000350`–`354` keep their IDs and resolve under `App/Views/legacy`, and the groups for `App/Views/Legacy` are pruned

#### Scenario: A case-only rename not yet performed
- **WHEN** on a case-insensitive volume the directory still lists `App/Views/Foo.swift`, and `pbxedit move App/Views/Foo.swift App/Views/foo.swift` runs
- **THEN** the command exits `1` saying the file must be moved on disk first, and writes nothing
