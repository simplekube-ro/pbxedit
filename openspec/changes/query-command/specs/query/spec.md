# Spec Delta

## Purpose

Answer, without reading the project file by hand, which targets build a given file and how, and which files a given target builds — in a form a script or agent can consume directly.

## ADDED Requirements

### Requirement: Membership of a path
`pbxedit query <path>` SHALL report, for the file reference resolving to that path: its ID, its resolved path, the path of group names leading to it, every group that lists it, and one membership entry per build file giving the target name, phase name, build file ID and `platformFilters`. Facts SHALL be reported as found, including a reference with no group or a build file with no phase.

#### Scenario: Ordinary member
- **WHEN** `App/iOS/Foo.swift` is built by target `App` in its Sources phase with `platformFilters = (ios, )`
- **THEN** the report shows `member: true`, the reference ID, group path `App/iOS`, and one membership with target `App`, phase `Sources`, the build file ID and platforms `[ios]`

#### Scenario: Shared source
- **WHEN** `App/Services/Rate.swift` has build files in targets `App` and `AppTopShelf`
- **THEN** the report lists two memberships, ordered by target name

#### Scenario: Build file in no phase
- **WHEN** `AppTests/FooTests.swift` has a build file that no phase lists
- **THEN** the report lists that membership with the build file ID and with target and phase given as absent

### Requirement: Paths outside the project
A path that no file reference resolves to SHALL be reported as not a member. When a synchronized root group covers the path, the report SHALL say so and name the group and its targets.

#### Scenario: Unknown path
- **WHEN** `App/Nope.swift` is queried and nothing references it
- **THEN** the report shows `member: false` with no memberships

#### Scenario: Synchronized folder
- **WHEN** `App/Generated/User.swift` is queried and `App/Generated` is a synchronized root group belonging to target `App`
- **THEN** the report shows `member: false`, `synchronized: true`, the group's ID and target `App`

### Requirement: Path arguments
A path argument SHALL be interpreted relative to the current directory when relative, SHALL be normalized, and SHALL be matched against paths relative to the source root, which is the directory containing the `.xcodeproj`. A path outside the source root SHALL be a usage error.

#### Scenario: Run from a subdirectory
- **WHEN** the current directory is `<root>/App/Views` and `pbxedit query Foo.swift --project ../../App.xcodeproj` runs
- **THEN** the path queried is `App/Views/Foo.swift`

#### Scenario: Outside the source root
- **WHEN** the argument resolves to a location above the source root
- **THEN** the command exits `2` naming the path and the source root

### Requirement: Members of a target
`pbxedit query --target <name>` SHALL list every file the target builds, one entry per build file, with resolved path, phase name and `platformFilters`, ordered by phase name then path. An unknown target name SHALL exit `2` and list the project's target names.

#### Scenario: Target listing
- **WHEN** `pbxedit query --target AppTests` runs
- **THEN** each file in any of `AppTests`' build phases appears once, sorted by phase then path

#### Scenario: Unknown target
- **WHEN** `pbxedit query --target Apptests` runs and the project has `App` and `AppTests`
- **THEN** the command exits `2` with a message listing `App` and `AppTests`

### Requirement: Output and exit codes
With `--json` the command SHALL print a single JSON object with `schemaVersion` and a `results` array in argument order, and nothing else on standard output. The exit code SHALL be `0` when every queried path is a member or is covered by a synchronized group, `1` when any is neither, and `2` on a usage error.

#### Scenario: Mixed results
- **WHEN** `pbxedit query --json App/Foo.swift App/Nope.swift` runs and only the first is a member
- **THEN** `results` has two entries in that order with `member` `true` then `false`, and the exit code is `1`

### Requirement: Read-only
`pbxedit query` SHALL NOT modify the project file or read any file other than the project file.

#### Scenario: Bytes unchanged
- **WHEN** any `query` invocation completes
- **THEN** the project file's bytes and modification time are unchanged
