# Spec Delta

## Purpose

Make a file that exists on disk a correctly grouped, correctly targeted member of the project in one atomic step, deciding as much as possible from how neighbouring files are already set up, and reporting truthfully what was decided and what was written.

## ADDED Requirements

### Requirement: Complete membership in one step
For each path, `pbxedit add` SHALL ensure there is exactly one file reference resolving to it, that the reference is a child of the group representing its directory, and that each chosen target has one build file for it listed in the appropriate build phase. After a successful add the rule set, scoped to the objects touched, SHALL report no errors.

#### Scenario: New test file
- **WHEN** `AppTests/Views/FooTests.swift` exists on disk, is not in the project, and `pbxedit add AppTests/Views/FooTests.swift` runs
- **THEN** the project gains one file reference, one child entry in the `Views` group, one build file and one entry in `AppTests`' Sources phase, and `pbxedit query` on the path reports one membership in `AppTests`

#### Scenario: Groups are created as needed
- **WHEN** `App/Features/New/Thing.swift` is added and the project has a group for `App/Features` but none for `New`
- **THEN** a group for `New` is created under `Features` and the reference is its child

### Requirement: The file must exist
A path that does not exist on disk, or is a directory, SHALL cause the command to exit `1` without writing.

#### Scenario: Typo
- **WHEN** `pbxedit add App/Fooo.swift` runs and no such file exists
- **THEN** the command exits `1` naming the path, and the project file is unchanged

### Requirement: Idempotence and completion
Adding a path that is already a complete member of the chosen targets SHALL change nothing and exit `0`. When membership is partial, the command SHALL add only what is missing and SHALL reuse every existing object; it SHALL NOT create a second file reference for a path or a second build file for a reference within one target.

#### Scenario: Re-add
- **WHEN** `pbxedit add` runs twice for the same path
- **THEN** the second run reports `modified: false`, exits `0`, and the project file's bytes are unchanged

#### Scenario: Reference exists without a group or phase entry
- **WHEN** the path has a file reference and a build file, but the reference is in no group and the build file is in no phase
- **THEN** the command adds the group child and the phase entry using the existing IDs, and creates no new reference or build file

#### Scenario: Add to a second target
- **WHEN** `App/Services/Rate.swift` is a member of `App` and `pbxedit add App/Services/Rate.swift --target AppTopShelf` runs
- **THEN** one build file and one phase entry are created for `AppTopShelf`, and the file reference and group are untouched

### Requirement: Files are identified by path
An existing file reference SHALL be reused only when it resolves to the same path.

#### Scenario: Same basename elsewhere
- **WHEN** the project references `AppTests/Foo/Bar.swift` and `AppSlowTests/Foo/Bar.swift` is added
- **THEN** a new file reference is created for `AppSlowTests/Foo/Bar.swift`, and the build file created for `AppSlowTests` refers to it

### Requirement: Targets are inferred from siblings
When `--target` is not given, the targets SHALL be those to which every sibling belongs, where siblings are the project's files of the same kind in the same directory, or, when there are none, in the nearest ancestor directory that has some. Targets to which only some siblings belong SHALL be reported in a note and SHALL NOT be joined. When no target is common to all siblings, or no sibling exists in any ancestor, the command SHALL exit `1` asking for `--target` and listing what it found.

#### Scenario: Unanimous siblings
- **WHEN** the 94 Swift files already in `AppTests/Views` are all members of `AppTests` only
- **THEN** the new file joins `AppTests`, and the output says the target was inferred from 94 siblings

#### Scenario: Some siblings are shared
- **WHEN** every file in `App/Services` is a member of `App` and 3 of 120 are also members of `AppTopShelf`
- **THEN** the new file joins `App` only, and a note says 3 of 120 siblings are also in `AppTopShelf` and how to join it

#### Scenario: Empty directory
- **WHEN** `App/Features/New/Thing.swift` is added, `App/Features/New` has no siblings, and the files in `App/Features` are all members of `App`
- **THEN** the new file joins `App`, and the output says it was inferred from the ancestor `App/Features`

#### Scenario: No common target
- **WHEN** half the siblings are members of `A` only and half of `B` only
- **THEN** the command exits `1`, lists both variants with their counts, and asks for `--target`

### Requirement: Platform filters are inferred only when unanimous
When `--platform` is not given, the new build files SHALL carry the `platformFilters` that all siblings' build files in the same target carry, including none. When siblings disagree, the command SHALL exit `1` asking for `--platform`.

#### Scenario: Platform directory
- **WHEN** every sibling in `App/tvOS` has `platformFilters = (tvos, )`
- **THEN** the new build file has `platformFilters = (tvos, )`

#### Scenario: Disagreement
- **WHEN** some siblings have `(ios, )` and others have no filter
- **THEN** the command exits `1`, lists the variants with counts, and asks for `--platform`

### Requirement: Explicit options override inference
`--target` (repeatable) SHALL replace the inferred target set, `--platform` (comma-separated, or `none`) SHALL replace the inferred filters, and `--phase sources|resources|headers|none` SHALL replace the phase chosen from the file type. An unknown target or platform name SHALL exit `2` listing the valid names.

#### Scenario: Override the target
- **WHEN** inference would choose `App` and `--target AppSlowTests` is given
- **THEN** the file joins `AppSlowTests` only, and the output attributes the target to the flag

### Requirement: Build phase follows the file type
Without `--phase`, source files SHALL go to the target's Sources phase, resources to its Resources phase, headers to its Headers phase, and project-only files such as `.plist`, `.entitlements`, `.xcconfig` and `.md` SHALL receive a file reference and group child with no build file. A file whose extension is not known SHALL exit `1` asking for `--phase`. The file reference SHALL carry the `lastKnownFileType` Xcode assigns to that extension.

#### Scenario: Resource
- **WHEN** `App/Resources/Localizable.xcstrings` is added
- **THEN** its build file is listed in `App`'s Resources phase and its reference has `lastKnownFileType = text.json.xcstrings`

#### Scenario: Project-only file
- **WHEN** `App/App.entitlements` is added
- **THEN** a file reference and a group child are created, and no build file

#### Scenario: Target has no such phase
- **WHEN** a resource is added to a target that has no Resources phase
- **THEN** the command exits `1` saying the target has no Resources phase

### Requirement: Path and source tree are derived from the group chain
When the group representing the file's directory resolves to that directory, the file reference SHALL be written with `sourceTree = "<group>"` and `path` equal to the basename. Otherwise it SHALL be written with `sourceTree = SOURCE_ROOT` and the full source-root-relative path. A created group SHALL follow the same rule relative to its parent.

#### Scenario: Pathful groups
- **WHEN** the `Views` group resolves to `App/Views` and `App/Views/Foo.swift` is added
- **THEN** the reference is `path = Foo.swift; sourceTree = "<group>";`

#### Scenario: Pathless groups
- **WHEN** the `Views` group under `AppTests` has a name and no path, and `AppTests/Views/FooTests.swift` is added
- **THEN** the reference is `path = AppTests/Views/FooTests.swift; sourceTree = SOURCE_ROOT;`

### Requirement: Group children keep their order
A new child SHALL be inserted in name order when the group's existing children are in name order, and last otherwise.

#### Scenario: Sorted group
- **WHEN** a group's children are `Alpha.swift`, `Gamma.swift` and `Beta.swift` is added
- **THEN** `Beta.swift` is inserted between them

### Requirement: Synchronized folders need no entry
A path covered by a synchronized root group SHALL NOT be added. The command SHALL report that it is already a member through that group and exit `0`.

#### Scenario: File in a synchronized folder
- **WHEN** `App/Generated/User.swift` is added and `App/Generated` is a synchronized root group
- **THEN** the output names the group, `modified` is `false`, and the project file is unchanged

### Requirement: Nothing is written unless the whole plan is sound
All paths in one invocation SHALL succeed or none SHALL be written. Before writing, the rule set SHALL be evaluated on the planned result, scoped to the objects the plan touches, and any error SHALL abort with exit `1`. After writing, the file SHALL be re-read and the same check repeated; a failure SHALL restore the original bytes and exit `1`.

#### Scenario: One bad path among three
- **WHEN** three paths are given and the second does not exist
- **THEN** the command exits `1` and the project file is unchanged

#### Scenario: Unrelated damage does not block
- **WHEN** the project already has hundreds of `M3` errors on other files
- **THEN** an otherwise valid add succeeds

#### Scenario: Collision with existing damage
- **WHEN** adding a path would create a second file reference resolving to a path that an existing, differently spelled reference already resolves to
- **THEN** the command exits `1` with the `M4` finding and writes nothing

### Requirement: The write is atomic
The project file SHALL be replaced by writing a temporary file in the same directory and renaming it over the original. An interrupted run SHALL leave either the original or the complete new file.

#### Scenario: Temporary file is cleaned up
- **WHEN** an add succeeds or fails
- **THEN** no temporary file remains beside `project.pbxproj`

### Requirement: Output states what was decided and what was written
The output SHALL list each decision with its source — flag, inference with the sibling count and directory, file type, or structure — and each object created or reused with its ID. The `modified` field SHALL be `true` if and only if the project file's bytes were replaced. With `--json` the output SHALL be one JSON object containing `schemaVersion`, `modified`, `decisions`, `changes`, `notes` and the membership report for each path.

#### Scenario: Message matches reality
- **WHEN** any `add` invocation finishes, whether it succeeded, was a no-op, or failed
- **THEN** `modified` is `true` exactly when the bytes of `project.pbxproj` differ from before the run

### Requirement: Dry run
With `--dry-run` the command SHALL print the same output as a real run plus a unified diff of the project file, SHALL write nothing, and SHALL exit with the code the real run would have.

#### Scenario: Preview
- **WHEN** `pbxedit add --dry-run AppTests/Views/FooTests.swift` runs
- **THEN** the diff shows the added lines, `modified` is `false`, and the project file is unchanged
