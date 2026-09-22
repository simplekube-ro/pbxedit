# Spec Delta

## Purpose

Define what it means for an Xcode project file to be internally consistent, as a fixed set of identified rules, and provide a read-only command that reports every violation in a form both people and programs can act on.

## ADDED Requirements

### Requirement: Findings are identified and addressable
Every finding SHALL carry the rule ID, a severity of `error` or `warning`, the ID of the offending object (absent only for a finding about something no object names, such as a D2 file on disk), the object's resolved path when it has one, the IDs of the related objects, and a message that states what is wrong and names the related objects by ID.

#### Scenario: Finding for an ungrouped file
- **WHEN** the file reference `AB12` for `AppTests/Views/FooTests.swift` is a child of no group
- **THEN** the finding has rule `M3`, severity `error`, object `AB12`, path `AppTests/Views/FooTests.swift`, and a message saying the reference has no parent group

### Requirement: Structural rules
The rule set SHALL report as errors: a file that does not parse, does not round-trip, or does not load as a project because it has no `objects` dictionary or no resolvable `rootObject` (S1); a reference to an ID that does not exist, in `fileRef`, `productRef`, `children`, `files`, `buildPhases`, `targets`, `mainGroup`, `productRefGroup`, `productReference`, `dependencies`, `target`, `targetProxy`, `containerPortal`, `buildConfigurationList`, `buildConfigurations`, `baseConfigurationReference`, `baseConfigurationReferenceAnchor`, `buildRules`, `currentVersion`, `package`, `packageProductDependencies`, `packageReferences`, `fileSystemSynchronizedGroups`, `exceptions`, `remoteRef`, `ProductGroup`, `ProjectRef`, `buildPhase` or `TestTargetID` (S2); an object ID defined twice, or an ID listed twice in one `children` or `files` array (S3); and a `platformFilters` value that is not a property-list array of known platform names (S4). It SHALL report as a warning a string whose quoting differs from the canonical form (S5).

#### Scenario: S1 on unparseable input
- **WHEN** the project file has an unterminated comment
- **THEN** exactly one finding is reported, rule `S1`, with the parser's line and column in its message, and no other rule is evaluated

#### Scenario: S1 on a file that is not a project
- **WHEN** the project file parses but its `rootObject` names an ID that is not in `objects`
- **THEN** exactly one finding is reported, rule `S1`, saying the root object cannot be found, and no other rule is evaluated

#### Scenario: S2 on a dangling child
- **WHEN** a group's `children` lists `DEAD0001` and no such object exists
- **THEN** an `S2` error is reported on the group, naming `DEAD0001` and the key `children`

#### Scenario: S3 on a repeated child
- **WHEN** a group's `children` lists `AB12` twice
- **THEN** an `S3` error is reported on the group, naming `AB12`

#### Scenario: S4 on JSON-style filters
- **WHEN** a build file has `platformFilters = ["ios"];` or `platformFilters = (iphone, );`
- **THEN** the first is reported as `S1` because it does not parse, and the second as an `S4` error naming `iphone` and listing the known platform names

#### Scenario: S5 on a bare hyphen
- **WHEN** a file reference has `path = My-File.swift;` unquoted
- **THEN** an `S5` warning is reported on that reference

### Requirement: Membership rules
The rule set SHALL report as errors: a build file listed in no build phase, or in more than one distinct phase (M1; the same phase listing it twice is S3); a build-phase entry that does not name a build file, or names one whose `fileRef` or `productRef` does not resolve (M2); a file reference that is a child of no group, or of more than one, excepting references that are a target's `productReference` (M3); two project-relative file references resolving to the same path (M4); two build files in one phase that share a `fileRef` or a `productRef` (M5). It SHALL report as a warning a build file in a target's Sources phase whose file resolves under a top-level directory that is the root of a different target and not of its own, a root being a directory at least 90% of whose Sources-phase files the target builds (M6).

#### Scenario: M1 on a build file that never builds
- **WHEN** a build file for `FooTests.swift` exists and no phase lists it
- **THEN** an `M1` error is reported on the build file, naming the file

#### Scenario: M3 exemption for products
- **WHEN** `App.app` is a target's `productReference` and is a child of the Products group only
- **THEN** no `M3` finding is reported for it

#### Scenario: M4 on a duplicate reference
- **WHEN** two file references both resolve to `App/Foo.swift`
- **THEN** one `M4` error is reported on the second in object order, naming the first

#### Scenario: M5 on a double add
- **WHEN** one Sources phase lists two build files that both point to `Foo.swift`
- **THEN** one `M5` error is reported on the second build file, naming the first

#### Scenario: M6 on a file in the wrong target
- **WHEN** every other file under `AppSlowTests/` is built by target `AppSlowTests`, and `AppSlowTests/Foo.swift` is in the Sources phase of target `App` only
- **THEN** an `M6` warning is reported on that build file, naming both targets

#### Scenario: Shared sources are not M6
- **WHEN** every file under `Shared/` is in the Sources phase of both `App` and `AppExtension`
- **THEN** no `M6` finding is reported

### Requirement: Disk rules are opt-in
When disk rules are enabled, the rule set SHALL report as warnings: a project-relative file reference, other than a target's `productReference`, whose resolved path does not exist (D1); and a file on disk with a source or resource extension, directly inside a directory some group resolves to, that no file reference resolves to and no synchronized root group covers (D2). A D2 finding has no object; it carries the file's path. When disk rules are not enabled, the file system SHALL NOT be read beyond the project file.

#### Scenario: D1 on a deleted file
- **WHEN** disk rules are enabled and `App/Gone.swift` is referenced but absent
- **THEN** a `D1` warning is reported on its file reference

#### Scenario: D2 respects synchronized folders
- **WHEN** disk rules are enabled and `App/Generated/User.swift` exists on disk, unreferenced, inside a synchronized root group
- **THEN** no `D2` finding is reported for it

### Requirement: Scoped evaluation
The rule set SHALL be evaluable against a given set of object IDs, reporting only findings whose object, or whose named related object, is in that set.

#### Scenario: Unrelated damage is ignored
- **WHEN** a project has 600 existing `M3` findings and the rules are evaluated scoped to one newly created, correctly grouped file reference and its build file
- **THEN** no findings are reported

### Requirement: The lint command reports and never edits
`pbxedit lint` SHALL evaluate the rule set over the whole project and print every finding, errors before warnings, each group ordered by rule ID then object ID. It SHALL NOT modify the project file.

#### Scenario: Human output
- **WHEN** `pbxedit lint` runs on a project with two `M3` errors and one `S5` warning
- **THEN** it prints three finding lines, each starting with the severity and rule ID, followed by a summary line `2 errors, 1 warning`, and the project file's bytes are unchanged

#### Scenario: JSON output
- **WHEN** `pbxedit lint --json` runs on the same project
- **THEN** it prints one JSON object with `schemaVersion`, `project`, `findings` (each with `rule`, `severity`, `object`, `path`, `related`, `message`; an absent object or path is `null`) and `summary` (`errors`, `warnings`, `baselined`, `resolved`), and nothing else on standard output

### Requirement: Exit codes
`pbxedit lint` SHALL exit `0` when no error-severity finding is reported, `1` when at least one is (an `S1` included), and `2` on a usage error or when the project cannot be located. Warnings alone SHALL NOT cause a non-zero exit unless `--strict` is given.

#### Scenario: Warnings only
- **WHEN** the only findings are `S5` and `M6` warnings
- **THEN** the exit code is `0`, and with `--strict` it is `1`

### Requirement: Project location
The project SHALL be the one named by `--project`, which accepts a `.xcodeproj` directory or a `project.pbxproj` file. Without it, the command SHALL use the single `.xcodeproj` in the current directory, and SHALL exit `2` listing the candidates when there are none or several.

#### Scenario: Two projects in the directory
- **WHEN** the current directory contains `App.xcodeproj` and `Tools.xcodeproj` and `--project` is not given
- **THEN** the command exits `2` with a message listing both and asking for `--project`

### Requirement: Baseline
`pbxedit lint --write-baseline <file>` SHALL record the current findings, keyed by rule ID and object ID, and exit `0`. `pbxedit lint --baseline <file>` SHALL report only findings not in the baseline, SHALL base its exit code on those alone, and SHALL list baseline entries that no longer occur as resolved.

#### Scenario: Adopting on a damaged project
- **WHEN** a baseline is written for a project with 655 `M3` errors and `lint --baseline` is then run unchanged
- **THEN** no findings are printed, the summary says 655 baselined, and the exit code is `0`

#### Scenario: New damage after adoption
- **WHEN** one more ungrouped file reference is then introduced
- **THEN** exactly that `M3` finding is printed and the exit code is `1`

#### Scenario: Missing baseline file
- **WHEN** `--baseline` names a file that does not exist
- **THEN** the command exits `2` saying so, and suggests `--write-baseline`
