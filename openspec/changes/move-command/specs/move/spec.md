# Spec Delta

## Purpose

Bring the project back in line with the disk after a file or directory has been moved or renamed, in one atomic step that keeps each file's identity in the project and changes its target membership only when the new location calls for it.

## ADDED Requirements

### Requirement: Identity is preserved
`pbxedit move <from> <to>` SHALL keep the file reference's ID. A build file SHALL keep its ID when its target still builds the file after the move.

#### Scenario: Move within a target
- **WHEN** `App/Views/Foo.swift` is moved to `App/Features/Foo.swift` and both directories belong to target `App`
- **THEN** the file reference ID and the build file ID are unchanged, and the Sources phase is not modified

### Requirement: The reference follows the file
After a move the file reference SHALL resolve to `<to>`, SHALL be a child of the group representing the destination directory and of no other group, and SHALL have `path` and `sourceTree` derived from that group chain by the rule `add` uses. Missing destination groups SHALL be created, and groups left empty by the move SHALL be removed as `remove` does.

#### Scenario: Re-parent between pathful groups
- **WHEN** `App/Views/Foo.swift` moves to `App/Features/New/Foo.swift` and no group exists for `New`
- **THEN** a group `New` is created under `Features`, the reference becomes its child with `path = Foo.swift; sourceTree = "<group>";`, and it is no longer a child of `Views`

#### Scenario: Source-root reference
- **WHEN** a reference written as `path = AppTests/Views/FooTests.swift; sourceTree = SOURCE_ROOT;` moves to `AppTests/State/FooTests.swift`, whose group has no path
- **THEN** its `path` becomes `AppTests/State/FooTests.swift` and `sourceTree` stays `SOURCE_ROOT`

#### Scenario: Reference that had no group
- **WHEN** the moved file's reference was a child of no group
- **THEN** after the move it is a child of the destination directory's group

### Requirement: Renames update every comment
When the basename changes, every annotation comment naming the file — on the reference's definition, its group entry, each build file's definition and each phase entry — SHALL carry the new name, and the reference's `name` attribute, when present, SHALL be updated.

#### Scenario: Rename in place
- **WHEN** `App/Old.swift` moves to `App/New.swift`
- **THEN** the project file no longer contains the text `Old.swift`, and contains `New.swift in Sources` on the build file's definition and its phase entry

### Requirement: Membership follows the destination
The targets and `platformFilters` for `<to>` SHALL be determined as `add` determines them — flags, then configuration, then sibling inference at the destination. Where they differ from the file's current membership, the command SHALL detach the file from targets no longer chosen, attach it to newly chosen targets, update `platformFilters` on retained build files, and list each such change in the output. With `--keep-membership`, membership and filters SHALL be left exactly as they were and the destination's conventions SHALL NOT be consulted.

#### Scenario: Cross-target move
- **WHEN** `AppTests/Services/FooTests.swift` moves to `AppSlowTests/Services/FooTests.swift`, whose siblings all belong to `AppSlowTests`
- **THEN** the file reference ID is kept, the `AppTests` build file and its phase entry are removed, a build file is created in `AppSlowTests`' Sources phase, and the output lists the detach and the attach

#### Scenario: Platform directory change
- **WHEN** `App/iOS/Panel.swift` with `platformFilters = (ios, )` moves to `App/Shared/Panel.swift`, whose siblings carry no filter
- **THEN** the build file keeps its ID, loses `platformFilters`, and the output says so

#### Scenario: Keep membership
- **WHEN** the cross-target move above runs with `--keep-membership`
- **THEN** the file is still built only by `AppTests`, and the output notes that the destination's siblings belong to `AppSlowTests`

#### Scenario: Destination is ambiguous
- **WHEN** the destination's siblings share no common target and neither a flag nor the configuration decides
- **THEN** the command exits `1` asking for `--target` or `--keep-membership`, and writes nothing

### Requirement: The disk must already reflect the move
The command SHALL exit `1` without writing when `<to>` does not exist on disk, or when `<from>` still exists on disk.

#### Scenario: Move not yet performed
- **WHEN** `App/Views/Foo.swift` still exists on disk and `App/Features/Foo.swift` does not
- **THEN** the command exits `1` saying the file must be moved on disk first

#### Scenario: Both exist
- **WHEN** both paths exist on disk
- **THEN** the command exits `1` saying this looks like a copy, and suggests `add` for the new file

### Requirement: Source and destination are validated against the project
The command SHALL exit `1` without writing when no file reference resolves to `<from>`, when a file reference already resolves to `<to>`, or when either path's reference is a child of a `PBXVariantGroup`.

#### Scenario: Destination already a member
- **WHEN** a file reference already resolves to `<to>`
- **THEN** the command exits `1` naming that reference's ID

### Requirement: Moving into a synchronized folder drops explicit membership
When `<to>` is covered by a synchronized root group, the command SHALL remove the file's reference, build files, phase entries and group child, and SHALL report that membership now comes from the folder.

#### Scenario: Into a synchronized folder
- **WHEN** `App/Models/User.swift` moves to `App/Generated/User.swift` and `App/Generated` is a synchronized root group
- **THEN** the explicit entries are removed, and the output names the synchronized group

### Requirement: Directory moves
When no file reference resolves to `<from>` and one or more resolve to paths beneath it, the command SHALL treat `<from>` and `<to>` as directories and move every such member to the corresponding path under `<to>`, as a single all-or-nothing plan. Each file SHALL be subject to every requirement above.

#### Scenario: Directory rename
- **WHEN** the directory `App/Views/Old` has been renamed on disk to `App/Views/New`, with five member files in two subdirectories
- **THEN** all five references resolve under `App/Views/New`, the groups for `Old` and its subdirectories are gone, groups for `New` and its subdirectories exist, and every reference and build file keeps its ID

#### Scenario: One file missing at the destination
- **WHEN** one of the five files does not exist under `App/Views/New`
- **THEN** the command exits `1` naming that file, and the project file is unchanged

### Requirement: Safety, output and dry run
The rule set, scoped to the objects touched, SHALL report no errors before and after the write. The output SHALL list, per file, the old and new path, each decision with its source, and each object created, changed or removed; `modified` SHALL be `true` if and only if the project file's bytes were replaced. `--dry-run` and `--json` SHALL behave as they do for `add`.

#### Scenario: Minimal diff
- **WHEN** a file moves within one target between two pathful groups without a rename
- **THEN** the diff consists of one line removed from the old group's children and one line added to the new group's children
