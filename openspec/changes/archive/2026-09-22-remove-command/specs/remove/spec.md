# Spec Delta

## Purpose

Take a file out of one target, or out of the project altogether, in one atomic step that leaves no dangling reference, no orphaned build file and no empty group behind.

Scenarios name the fixtures under `Tests/Fixtures/remove/` and the ones they reuse: `remove/app.pbxproj` (the `add/app.pbxproj` project — targets `App`, `AppExtension`, `AppTests`, `AppKit`; `App/Services/Cache.swift` and `App/Shared.swift` built by both `App` and `AppExtension`; the variant group `AA0000000000000000000201` holding `App/Resources/en.lproj/Localizable.strings`; the synchronized folder `App/Generated` — plus the chain `Features` → `New` → `App/Features/New/Thing.swift`, the project-only `App/App.entitlements`, and an already-empty group `Empty`), `remove/roots.pbxproj` (a file directly under the main group and one under the products group), `add/partial.pbxproj` (reference `AB12` in no group, build file `BF01` in no phase) and `rules/m5-double-add.pbxproj` (two build files for `App/Foo.swift` in one Sources phase).

## ADDED Requirements

### Requirement: Complete removal
For a file that belongs to at most one target, `pbxedit remove <path>` SHALL delete every build file referring to its file reference, remove each from every build phase listing it, remove the reference from every group listing it, and delete the reference. Steps SHALL be ordered referrers first (phase entries, then build files, then group children, then the reference), so no intermediate state holds a dangling ID. Afterwards no object in the project SHALL mention any deleted ID (rules S2, M2).

#### Scenario: Ordinary file
- **WHEN** `App/Services/Rate.swift` (`AA0000000000000000000230`) is a member of `App` through build file `BB0000000000000000000110` and `pbxedit remove App/Services/Rate.swift` runs against `remove/app.pbxproj`
- **THEN** the file reference, its build file, the Sources entry and the `Services` group child are gone, `Services` keeps its other children, `pbxedit query` reports `member: false`, and no identifier token in the project file equals either deleted ID

#### Scenario: Damaged membership is removed too
- **WHEN** `pbxedit remove AppTests/Views/FooTests.swift` runs against `add/partial.pbxproj`, where reference `AB12` is in no group and its build file `BF01` is in no phase
- **THEN** the reference and the build file are deleted, no phase entry or group child step is planned, and the command succeeds

#### Scenario: Project-only file
- **WHEN** `App/App.entitlements` (`AA0000000000000000000290`) has a reference and a group child and no build file
- **THEN** the reference and the group child are removed and nothing else changes

### Requirement: Shared files need an explicit choice
When a file's build files are owned by more than one distinct target, the command SHALL exit `1` without writing unless `--target` or `--all` is given, and SHALL list the targets. The guard counts targets, not build files: two build files in one target are removed together without it (rule M5's defect).

#### Scenario: Shared source without a choice
- **WHEN** `App/Services/Cache.swift` belongs to `App` and `AppExtension` and `pbxedit remove App/Services/Cache.swift` runs
- **THEN** the command exits `1`, names both targets, mentions `--target` and `--all`, and the project file is unchanged

#### Scenario: Remove from everything
- **WHEN** the same command runs with `--all`
- **THEN** both build files (`BB0000000000000000000112`, `BB0000000000000000000113`), both phase entries, the group child and the reference are removed

#### Scenario: Two build files in one target
- **WHEN** `pbxedit remove App/Foo.swift` runs against `rules/m5-double-add.pbxproj`, where `BF01` and `BF02` both refer to `AB12` and both sit in `App`'s Sources phase
- **THEN** both build files, both entries and the reference are removed without `--all`, and the M5 finding is gone

### Requirement: Detaching from one target
With `--target <name>`, the command SHALL remove only the phase entries of the reference's build files in phases that target owns, and SHALL delete each build file that is thereby listed in no phase. A build file already listed in no phase belongs to no target and SHALL be left alone; as it is the touched file's own damage, the pre-write check then reports it (rule M1) and the detach is refused until the damage is repaired or the file is removed whole. The file reference and its group child SHALL remain, even when no target builds the file afterwards, and the output SHALL say so. A file that is not a member of the named target SHALL exit `1` listing the targets it does belong to. A name that is not a target of the project SHALL exit `2` listing the targets, as for `add`. `--target` and `--all` together SHALL be a usage error.

#### Scenario: Detach a shared source
- **WHEN** `pbxedit remove App/Services/Cache.swift --target AppExtension` runs
- **THEN** `AppExtension`'s build file `BB0000000000000000000113` and its entry in `CC0000000000000000000004` are removed, and `pbxedit query` reports one membership, in `App`, with the reference and group child intact

#### Scenario: Last membership detached
- **WHEN** `pbxedit remove App/Services/Rate.swift --target App` runs and `App` is its only target
- **THEN** the build file and entry are removed, the reference `AA0000000000000000000230` stays a child of `Services`, and the output notes the file is now built by no target

#### Scenario: Not a member of that target
- **WHEN** `--target AppTests` is given and `App/Views/Foo.swift` belongs only to `App`
- **THEN** the command exits `1` saying the file is not a member of `AppTests` and listing `App`, and the project file is unchanged

### Requirement: Unknown paths are an error
A path that no file reference resolves to SHALL exit `1` without writing. The file SHALL NOT be required to exist on disk.

#### Scenario: Typo
- **WHEN** `pbxedit remove App/Fooo.swift` runs and nothing references that path
- **THEN** the command exits `1` naming the path, and the project file is unchanged

#### Scenario: File already deleted from disk
- **WHEN** `App/Views/Foo.swift` is a member and does not exist on disk
- **THEN** the removal succeeds

### Requirement: Empty groups are removed
A `PBXGroup` left with no children by the removal SHALL be deleted and removed from each of its parents, repeatedly up the chain. The main group and the products group (`productRefGroup`) SHALL never be deleted. Groups that were already empty before the operation SHALL be left alone. With several paths in one invocation, pruning SHALL run once over the combined plan. Each removed group SHALL be listed in the output with its ID.

#### Scenario: Last file in a directory
- **WHEN** `App/Features/New/Thing.swift` is the only child of group `New` (`AA0000000000000000000018`), and `New` is the only child of `Features` (`AA0000000000000000000017`)
- **THEN** the reference, `New` and `Features` are all removed, the `App` group keeps its other children including the empty group `Empty` (`AA0000000000000000000019`), and the output lists both groups as removed

#### Scenario: Siblings remain
- **WHEN** `App/Services/Rate.swift` is removed and `Services` has other children
- **THEN** the group is kept

#### Scenario: Root groups are kept
- **WHEN** `Top.swift` and `Odd.swift` are removed from `remove/roots.pbxproj`, leaving the main group `G001` and the products group `G002` with no file children
- **THEN** neither group is deleted

#### Scenario: A directory's files in one command
- **WHEN** `pbxedit remove App/tvOS/TV1.swift App/tvOS/TV2.swift` runs
- **THEN** the `tvOS` group (`AA0000000000000000000014`) is removed once, after both references

### Requirement: Unsupported cases are refused
The command SHALL exit `1` without writing when the path's file reference is a child of a `PBXVariantGroup` (localized variants) or an `XCVersionGroup` (versioned models), naming the group and saying such files are not supported in v1, and when the path is a member only through a synchronized root group, saying membership comes from the folder and naming the group.

#### Scenario: Localized resource
- **WHEN** `App/Resources/en.lproj/Localizable.strings` (`AA0000000000000000000210`) is a child of the variant group `AA0000000000000000000201`
- **THEN** the command exits `1` with the variant-group message and the project file is unchanged

#### Scenario: Synchronized folder
- **WHEN** `App/Generated/User.swift` lies in the synchronized root group `AA0000000000000000000301` and has no file reference
- **THEN** the command exits `1` naming the synchronized group

### Requirement: Safety, output and dry run
All paths in one invocation SHALL succeed or none SHALL be written. The rule set, scoped to the objects touched and to every object that referred to a deleted object (its parent groups, the phases that listed its build files and the targets owning them), SHALL report no errors before and after the write. The output SHALL list every object removed with its ID and kind (file reference, build file, group), and `modified` SHALL be `true` if and only if the project file's bytes were replaced. `--dry-run` and `--json` SHALL behave as they do for `add`: the same JSON object (`schemaVersion`, `modified`, `dryRun`, `decisions`, `changes`, `notes`, `findings`, `error`, `diff`, `results`), with `results` the membership report of each path after the operation.

#### Scenario: No dangling references
- **WHEN** any successful removal completes
- **THEN** `pbxedit lint` reports exactly the `S2` and `M2` findings it reported before

#### Scenario: One unknown path among three
- **WHEN** three paths are given and the second is not in the project
- **THEN** the command exits `1` and the project file is unchanged

#### Scenario: Incomplete plan is caught
- **WHEN** a plan deletes a build file but leaves its phase entry behind
- **THEN** the scoped check reports an `M2` finding on that phase and nothing is written
