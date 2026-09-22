# add Specification

## Purpose
Make a file that exists on disk a correctly grouped, correctly targeted member of the project in one atomic step, deciding as much as possible from how neighbouring files are already set up, and reporting truthfully what was decided and what was written.

Scenarios name the fixtures under `Tests/Fixtures/add/`: `app.pbxproj` (targets `App`, `AppExtension`, `AppTests`, `AppKit`; directories `App`, `App/Views`, `App/Services`, `App/tvOS`, `App/Mixed`, `App/Filtered`, `App/Resources`, `AppKit`, `AppTests/Foo`, `AppTests/Views`, and the synchronized folder `App/Generated`), `partial.pbxproj` (a reference and a build file for `AppTests/Views/FooTests.swift` in no group and no phase, beside two unrelated orphans) and `m4-collision.pbxproj` (two references resolving to `App/Foo.swift`).

## Requirements

### Requirement: Complete membership in one step
For each path, `pbxedit add` SHALL ensure there is exactly one file reference resolving to it, that the reference is a child of the group representing its directory, and that each chosen target has one build file for it listed in the appropriate build phase. After a successful add the rule set, scoped to the objects touched, SHALL report no errors (rules S2–S5, M1–M5).

#### Scenario: New file
- **WHEN** `App/Views/Bar.swift` exists on disk, is not in the project, and `pbxedit add App/Views/Bar.swift` runs against `app.pbxproj`
- **THEN** the project gains one file reference, one child entry in the `Views` group (`AA0000000000000000000003`), one build file and one entry in `App`'s Sources phase (`CC0000000000000000000001`), and `pbxedit query` on the path reports one membership in `App`

#### Scenario: Groups are created as needed
- **WHEN** `App/Features/New/Thing.swift` is added and the project has a group for `App` but none for `Features` or `New`
- **THEN** a group `Features` (`path = Features`) is created under `App` and a group `New` under `Features`, and the reference is a child of `New`

### Requirement: The file must exist
A path that does not exist on disk, or is a directory other than a bundle Xcode treats as one file (`.xcassets`, `.xcdatamodeld`, `.scnassets`, …), SHALL cause the command to exit `1` without writing.

#### Scenario: Typo
- **WHEN** `pbxedit add App/Fooo.swift` runs and no such file exists
- **THEN** the command exits `1` naming the path, and the project file is unchanged

### Requirement: Idempotence and completion
Adding a path that is already a complete member of the chosen targets SHALL change nothing and exit `0`. When membership is partial, the command SHALL add only what is missing and SHALL reuse every existing object; it SHALL NOT create a second file reference for a path or a second build file for a reference within one target (rules M4, M5).

#### Scenario: Re-add
- **WHEN** `pbxedit add App/Views/Foo.swift` runs against `app.pbxproj`, where the file is already a member of `App`
- **THEN** the run reports `modified: false`, exits `0`, and the project file's bytes are unchanged

#### Scenario: Reference exists without a group or phase entry
- **WHEN** `pbxedit add AppTests/Views/FooTests.swift --target App` runs against `partial.pbxproj`, where reference `AB12` is in no group and its build file `BF01` is in no phase
- **THEN** the command creates the groups `AppTests` and `Views` under the main group, adds `AB12` as a child of `Views`, adds `BF01` to the Sources phase `S001`, and creates no new reference or build file

#### Scenario: Add to a second target
- **WHEN** `App/Services/Rate.swift` is a member of `App` and `pbxedit add App/Services/Rate.swift --target AppExtension` runs
- **THEN** one build file and one phase entry are created for `AppExtension`'s Sources phase, and the file reference `AA0000000000000000000230` and the `Services` group are untouched

### Requirement: Files are identified by path
An existing file reference SHALL be reused only when it resolves to the same path (design: file lookup by resolved path, never basename).

#### Scenario: Same basename elsewhere
- **WHEN** the project references `AppTests/Foo/Bar.swift` (`AA0000000000000000000150`) and `App/Views/Bar.swift` is added
- **THEN** a new file reference is created for `App/Views/Bar.swift`, and the build file created for `App` refers to the new reference, not to `AA0000000000000000000150`

### Requirement: Targets are inferred from siblings
When `--target` is not given, the targets SHALL be those to which every sibling belongs, where siblings are the project's files of the same kind in the same directory that some target builds, or, when there are none, in the nearest ancestor directory that has some. Targets to which only some siblings belong SHALL be reported in a note and SHALL NOT be joined. When no target is common to all siblings, or no sibling exists in any ancestor, the command SHALL exit `1` asking for `--target` and listing what it found.

#### Scenario: Unanimous siblings
- **WHEN** `App/tvOS/TV3.swift` is added and the two Swift files in `App/tvOS` are members of `App` only
- **THEN** the new file joins `App`, and the output says the target was inferred from 2 siblings in `App/tvOS`

#### Scenario: Some siblings are shared
- **WHEN** `App/Services/New.swift` is added, every file in `App/Services` is a member of `App`, and 1 of the 3 is also a member of `AppExtension`
- **THEN** the new file joins `App` only, and a note says 1 of 3 siblings is also in `AppExtension` and how to join it

#### Scenario: Empty directory
- **WHEN** `App/Features/New/Thing.swift` is added, neither `App/Features/New` nor `App/Features` has any sibling, and the Swift files directly in `App` are all members of `App`
- **THEN** the new file joins `App`, and the output says it was inferred from the ancestor `App`

#### Scenario: No common target
- **WHEN** `App/Mixed/New.swift` is added and `App/Mixed` holds one file that is a member of `App` only and one of `AppExtension` only
- **THEN** the command exits `1`, lists both variants with their counts, and asks for `--target`

### Requirement: Platform filters are inferred only when unanimous
When `--platform` is not given, the new build files SHALL carry the `platformFilters` that all siblings' build files in the same target carry, including none. When siblings disagree, the command SHALL exit `1` asking for `--platform`. When no sibling is built by the target, the build file SHALL carry no filters (rule S4 names the values allowed).

#### Scenario: Platform directory
- **WHEN** `App/tvOS/TV3.swift` is added and every sibling in `App/tvOS` has `platformFilters = (tvos, )`
- **THEN** the new build file has `platformFilters = (tvos, )`

#### Scenario: Disagreement
- **WHEN** `App/Filtered/New.swift` is added and in `App/Filtered` one sibling has `(ios, )` and the other has no filter
- **THEN** the command exits `1`, lists the variants with counts, and asks for `--platform`

### Requirement: Explicit options override inference
`--target` (repeatable) SHALL replace the inferred target set, `--platform` (comma-separated, or `none`) SHALL replace the inferred filters, and `--phase sources|resources|headers|none` SHALL replace the phase chosen from the file type. An unknown target or platform name SHALL exit `2` listing the valid names.

#### Scenario: Override the target
- **WHEN** inference would choose `App` for `App/Views/Bar.swift` and `--target AppTests` is given
- **THEN** the file joins `AppTests` only, and the output attributes the target to the flag

### Requirement: Build phase follows the file type
Without `--phase`, source files SHALL go to the target's Sources phase, resources to its Resources phase, headers to its Headers phase, and project-only files such as `.plist`, `.entitlements`, `.xcconfig` and `.md` SHALL receive a file reference and group child with no build file. A file whose extension is not known SHALL exit `1` asking for `--phase`. The file reference SHALL carry the `lastKnownFileType` Xcode assigns to that extension.

#### Scenario: Resource
- **WHEN** `App/Resources/Localizable.xcstrings` is added, beside `Assets.xcassets` which is in `App`'s Resources phase
- **THEN** its build file is listed in `App`'s Resources phase (`CC0000000000000000000003`) and its reference has `lastKnownFileType = text.json.xcstrings`

#### Scenario: Header
- **WHEN** `AppKit/Extra.h` is added, beside `AppKit.h` which is in `AppKit`'s Headers phase
- **THEN** its build file is listed in `AppKit`'s Headers phase (`CC0000000000000000000008`) and its reference has `lastKnownFileType = sourcecode.c.h`

#### Scenario: Project-only file
- **WHEN** `App/App.entitlements` is added
- **THEN** a file reference and a group child are created, and no build file

#### Scenario: Target has no such phase
- **WHEN** `AppTests/Foo/fixture.json --target AppTests` is added and `AppTests` has no Resources phase
- **THEN** the command exits `1` saying the target has no Resources phase

### Requirement: Path and source tree are derived from the group chain
When the group representing the file's directory resolves to that directory, the file reference SHALL be written with `sourceTree = "<group>"` and `path` equal to the basename. Otherwise it SHALL be written with `sourceTree = SOURCE_ROOT`, the full source-root-relative path and `name` equal to the basename. A created group SHALL follow the same rule relative to its parent. A name-only group under the parent directory's group, named like the directory, SHALL be reused rather than duplicated.

#### Scenario: Pathful groups
- **WHEN** the `Views` group (`AA0000000000000000000003`) resolves to `App/Views` and `App/Views/Bar.swift` is added
- **THEN** the reference is `path = Bar.swift; sourceTree = "<group>";`

#### Scenario: Pathless groups
- **WHEN** the `Views` group under `AppTests` (`AA0000000000000000000011`) has a name and no path, and `AppTests/Views/BarTests.swift` is added
- **THEN** the reference is `name = BarTests.swift; path = AppTests/Views/BarTests.swift; sourceTree = SOURCE_ROOT;` and is a child of `AA0000000000000000000011`

### Requirement: Group children keep their order
A new child SHALL be inserted in name order when the group's existing children are in name order, and last otherwise.

#### Scenario: Sorted group
- **WHEN** the `Services` group's children are `Cache.swift`, `Fetch.swift`, `Rate.swift` and `App/Services/New.swift` is added
- **THEN** `New.swift` is inserted between `Fetch.swift` and `Rate.swift`

#### Scenario: Unsorted group
- **WHEN** the `App` group's children are not in name order and `App/App.entitlements` is added
- **THEN** `App.entitlements` is inserted last

### Requirement: Synchronized folders need no entry
A path covered by a synchronized root group SHALL NOT be added. The command SHALL report that it is already a member through that group and exit `0`.

#### Scenario: File in a synchronized folder
- **WHEN** `App/Generated/User.swift` is added and `App/Generated` is the synchronized root group `AA0000000000000000000301`
- **THEN** the output names the group, `modified` is `false`, and the project file is unchanged

### Requirement: Nothing is written unless the whole plan is sound
All paths in one invocation SHALL succeed or none SHALL be written. Before writing, the rule set SHALL be evaluated on the planned result, scoped to the objects the plan touches or reuses, and any error SHALL abort with exit `1`. After writing, the file SHALL be re-read and the same check repeated; a failure SHALL restore the original bytes and exit `1`.

#### Scenario: One bad path among three
- **WHEN** three paths are given and the second does not exist
- **THEN** the command exits `1` and the project file is unchanged

#### Scenario: Unrelated damage does not block
- **WHEN** `partial.pbxproj` has `M3` errors on `Old1.swift` and `Old2.swift`, which the add does not touch
- **THEN** `pbxedit add AppTests/Views/FooTests.swift --target App` succeeds and those findings remain

#### Scenario: Collision with existing damage
- **WHEN** `App/Foo.swift` is added against `m4-collision.pbxproj`, where `AB12` and the differently spelled `AB13` both resolve to `App/Foo.swift`, so the reused reference `AB12` gains a build file
- **THEN** the command exits `1` with the `M4` finding and writes nothing

### Requirement: The write is atomic
The project file SHALL be replaced by writing a temporary file in the same directory and renaming it over the original. An interrupted run SHALL leave either the original or the complete new file.

#### Scenario: Temporary file is cleaned up
- **WHEN** an add succeeds or fails
- **THEN** no temporary file remains beside `project.pbxproj`

### Requirement: Output states what was decided and what was written
The output SHALL list each decision with its source — flag, inference with the sibling count and directory, file type, or structure — and each object created or reused with its ID. The `modified` field SHALL be `true` if and only if the project file's bytes were replaced. With `--json` the output SHALL be one JSON object containing `schemaVersion`, `modified`, `dryRun`, `decisions`, `changes`, `notes`, `findings`, `error`, `diff` and `results` (the membership report for each path, in argument order), absent values as `null`, never omitted.

#### Scenario: Message matches reality
- **WHEN** any `add` invocation finishes, whether it succeeded, was a no-op, or failed
- **THEN** `modified` is `true` exactly when the bytes of `project.pbxproj` differ from before the run

### Requirement: Dry run
With `--dry-run` the command SHALL print the same output as a real run plus a unified diff of the project file, SHALL write nothing, and SHALL exit with the code the real run would have.

#### Scenario: Preview
- **WHEN** `pbxedit add --dry-run App/Views/Bar.swift` runs
- **THEN** the diff shows the added lines, `modified` is `false`, and the project file is unchanged
