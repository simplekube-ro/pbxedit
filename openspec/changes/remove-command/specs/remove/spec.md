# Spec Delta

## Purpose

Take a file out of one target, or out of the project altogether, in one atomic step that leaves no dangling reference, no orphaned build file and no empty group behind.

## ADDED Requirements

### Requirement: Complete removal
For a file that belongs to at most one target, `pbxedit remove <path>` SHALL delete every build file referring to its file reference, remove each from every build phase listing it, remove the reference from every group listing it, and delete the reference. Afterwards no object in the project SHALL mention any deleted ID.

#### Scenario: Ordinary file
- **WHEN** `AppTests/Views/FooTests.swift` is a member of `AppTests` and `pbxedit remove AppTests/Views/FooTests.swift` runs
- **THEN** the file reference, its build file, the Sources entry and the group child are gone, `pbxedit query` reports `member: false`, and a search of the project file for either deleted ID finds nothing

#### Scenario: Damaged membership is removed too
- **WHEN** the file has a reference and a build file but the build file is in no phase and the reference is in no group
- **THEN** the reference and the build file are deleted and the command succeeds

#### Scenario: Project-only file
- **WHEN** `App/App.entitlements` has a reference and a group child and no build file
- **THEN** the reference and the group child are removed

### Requirement: Shared files need an explicit choice
When a file belongs to more than one target, the command SHALL exit `1` without writing unless `--target` or `--all` is given, and SHALL list the targets.

#### Scenario: Shared source without a choice
- **WHEN** `App/Services/Rate.swift` belongs to `App` and `AppTopShelf` and `pbxedit remove App/Services/Rate.swift` runs
- **THEN** the command exits `1`, names both targets, mentions `--target` and `--all`, and the project file is unchanged

#### Scenario: Remove from everything
- **WHEN** the same command runs with `--all`
- **THEN** both build files, both phase entries, the group child and the reference are removed

### Requirement: Detaching from one target
With `--target <name>`, the command SHALL remove only that target's build files for the reference and their phase entries. The file reference and its group child SHALL remain, even when no target builds the file afterwards. A file that is not a member of the named target SHALL exit `1`.

#### Scenario: Detach a shared source
- **WHEN** `pbxedit remove App/Services/Rate.swift --target AppTopShelf` runs
- **THEN** `AppTopShelf`'s build file and phase entry are removed, and `pbxedit query` reports one membership, in `App`

#### Scenario: Not a member of that target
- **WHEN** `--target AppTests` is given and the file belongs only to `App`
- **THEN** the command exits `1` saying the file is not a member of `AppTests` and listing the targets it does belong to

### Requirement: Unknown paths are an error
A path that no file reference resolves to SHALL exit `1` without writing. The file SHALL NOT be required to exist on disk.

#### Scenario: Typo
- **WHEN** `pbxedit remove App/Fooo.swift` runs and nothing references that path
- **THEN** the command exits `1` naming the path, and the project file is unchanged

#### Scenario: File already deleted from disk
- **WHEN** `App/Old.swift` has been deleted from disk and is still a member
- **THEN** the removal succeeds

### Requirement: Empty groups are removed
A group left with no children by the removal SHALL be deleted and removed from its parent, repeatedly up the chain. The main group and the products group SHALL never be deleted. Groups that were already empty before the operation SHALL be left alone.

#### Scenario: Last file in a directory
- **WHEN** `App/Features/New/Thing.swift` is the only child of group `New`, and `New` is the only child of `Features`
- **THEN** the reference, `New` and `Features` are all removed, and the output lists both groups as removed

#### Scenario: Siblings remain
- **WHEN** the group has other children
- **THEN** the group is kept

### Requirement: Unsupported cases are refused
The command SHALL exit `1` without writing when the path's file reference is a child of a `PBXVariantGroup`, saying localized variants are not supported, and when the path is a member only through a synchronized root group, saying membership comes from the folder and naming the group.

#### Scenario: Localized resource
- **WHEN** `App/en.lproj/Main.strings` is a child of a variant group
- **THEN** the command exits `1` with the variant-group message and the project file is unchanged

#### Scenario: Synchronized folder
- **WHEN** `App/Generated/User.swift` lies in a synchronized root group and has no file reference
- **THEN** the command exits `1` naming the synchronized group

### Requirement: Safety, output and dry run
All paths in one invocation SHALL succeed or none SHALL be written. The rule set, scoped to the objects touched and to every object that referred to a deleted object, SHALL report no errors before and after the write. The output SHALL list every object removed with its ID and kind, and `modified` SHALL be `true` if and only if the project file's bytes were replaced. `--dry-run` and `--json` SHALL behave as they do for `add`.

#### Scenario: No dangling references
- **WHEN** any successful removal completes
- **THEN** `pbxedit lint` reports no `S2` or `M2` finding that was not present before

#### Scenario: One unknown path among three
- **WHEN** three paths are given and the second is not in the project
- **THEN** the command exits `1` and the project file is unchanged
