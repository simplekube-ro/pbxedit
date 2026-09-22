# Spec Delta

## Purpose

Answer, without reading the project file by hand, which targets build a given file and how, and which files a given target builds — in a form a script or agent can consume directly.

## ADDED Requirements

### Requirement: Membership of a path
`pbxedit query <path>` SHALL report, for the file reference resolving to that path: its ID, its resolved path, the path of group names leading to it, every group that lists it, and its memberships — one entry per build file for each build phase listing it and each target owning that phase, giving the target (ID and name), the phase (ID and name), the build file ID and its `platformFilters` (the array, or the single `platformFilter` as a one-element array, or empty). Facts SHALL be reported as found, including a reference with no group or a build file with no phase (rule M3 and rule M1 inputs, reported without judgement). When several references resolve to the path (rule M4's input), the first in object order is reported. Memberships SHALL be ordered by target name, then phase name, then build file ID.

#### Scenario: Ordinary member
- **WHEN** `App/Views/Foo.swift` is built by target `App` in its Sources phase (fixture `model/app.pbxproj`)
- **THEN** the report shows `member: true`, the reference ID `AA0000000000000000000120`, group path `App/Views`, groups `[AA0000000000000000000003]`, and one membership with target `App`, phase `Sources`, build file `BB0000000000000000000020` and `platformFilters` `[]`

#### Scenario: Shared source with platform filters
- **WHEN** `App/Shared.swift` has build files in the Sources phases of `App` and of `AppExtension`, the latter with `platformFilters = (ios, maccatalyst, )` (fixture `model/app.pbxproj`)
- **THEN** the report lists two memberships, `App` first then `AppExtension`, the second with `platformFilters` `[ios, maccatalyst]`

#### Scenario: Build file in no phase
- **WHEN** `AppTests/FooTests.swift` has a build file `BF01` that no phase lists (fixture `rules/m1-no-phase.pbxproj`)
- **THEN** the report shows `member: true` and one membership with build file `BF01` and target and phase given as absent

#### Scenario: Reference with no group
- **WHEN** `AppTests/Views/FooTests.swift` resolves to reference `AB12`, which is a child of no group (fixture `rules/m3-orphan.pbxproj`)
- **THEN** the report shows `member: true`, an absent group path, no groups, and its membership in `App`

### Requirement: Paths outside the project
A path that no file reference resolves to SHALL be reported as not a member, with no reference, group or membership. When a synchronized root group covers the path, the report SHALL also name that group's ID, its resolved path and the targets that list it.

#### Scenario: Unknown path
- **WHEN** `App/Nope.swift` is queried and nothing references it
- **THEN** the report shows `member: false` with no memberships and no synchronized group

#### Scenario: Synchronized folder
- **WHEN** `App/Generated/User.swift` is queried and `App/Generated` is the synchronized root group `AA0000000000000000000301` listed by target `App` (fixture `model/app.pbxproj`)
- **THEN** the report shows `member: false` and a `synchronized` entry with that group's ID, path `App/Generated` and target `App`

### Requirement: Path arguments
A path argument SHALL be interpreted relative to the current directory when relative, SHALL be normalized lexically without touching the disk, and SHALL be matched against paths relative to the source root, which is the directory containing the `.xcodeproj`. A path outside the source root, or the source root itself, SHALL be a usage error. Every command that takes paths SHALL use this one interpretation.

#### Scenario: Run from a subdirectory
- **WHEN** the current directory is `<root>/App/Views` and `pbxedit query Foo.swift --project ../../App.xcodeproj` runs
- **THEN** the path queried is `App/Views/Foo.swift`

#### Scenario: Outside the source root
- **WHEN** the argument resolves to a location above the source root
- **THEN** the command exits `2` naming the path and the source root, and prints nothing on standard output

### Requirement: Members of a target
`pbxedit query --target <name>` SHALL list every entry of the target's build phases, one per entry, with the build file ID, the file reference ID, the resolved path, the phase (ID and name) and `platformFilters`, ordered by phase name then path. An entry whose file has no project-relative path SHALL carry that reference's `path` prefixed with `$(<sourceTree>)/`; an entry that resolves to no file SHALL carry an absent path and sort last within its phase. `--target` SHALL NOT be combined with path arguments, and a run with neither is a usage error. An unknown target name SHALL exit `2` and list the project's target names.

#### Scenario: Target listing
- **WHEN** `pbxedit query --target AppTests` runs (fixture `model/app.pbxproj`)
- **THEN** the listing has `AppTests/Foo/Bar.swift` then `AppTests/Views/FooTests.swift`, both in phase `Sources`, with build files `BB0000000000000000000070` and `BB0000000000000000000060`, and exits `0`

#### Scenario: Unknown target
- **WHEN** `pbxedit query --target Apptests` runs and the project has `App`, `AppExtension` and `AppTests`
- **THEN** the command exits `2` with a message listing `App`, `AppExtension` and `AppTests`

### Requirement: Output and exit codes
Without `--json` the command SHALL print one block per path, or the target listing, and SHALL end a block with the hint `run pbxedit lint` when the report has no group, several groups, or a membership with no phase or no target. With `--json` the command SHALL print a single JSON object and nothing else on standard output: for paths `schemaVersion` and a `results` array in argument order, each result carrying the keys `path`, `member`, `fileReference`, `groupPath`, `groups`, `memberships` (each `target`, `phase`, `buildFile`, `platformFilters`) and `synchronized` (`group`, `path`, `targets`), absent values as `null`, never omitted; for a target `schemaVersion`, `target` and `members` (each `buildFile`, `fileReference`, `path`, `phase`, `platformFilters`). The exit code SHALL be `0` when every queried path is a member or is covered by a synchronized group, `1` when any is neither, and `2` on a usage error or when the project file cannot be parsed or loaded.

#### Scenario: Mixed results
- **WHEN** `pbxedit query --json App/Views/Foo.swift App/Nope.swift` runs and only the first is a member
- **THEN** `results` has two entries in that order with `member` `true` then `false`, every key present, and the exit code is `1`

#### Scenario: Synchronized path exits zero
- **WHEN** `pbxedit query App/Generated/User.swift` runs
- **THEN** the output names the synchronized group and the exit code is `0`

### Requirement: Read-only
`pbxedit query` SHALL NOT modify the project file or read any file other than the project file.

#### Scenario: Bytes unchanged
- **WHEN** any `query` invocation completes — paths, `--json`, `--target`, or a usage error
- **THEN** the project file's bytes and modification time are unchanged
