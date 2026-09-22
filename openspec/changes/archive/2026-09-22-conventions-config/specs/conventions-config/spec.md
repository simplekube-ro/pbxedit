# Spec Delta

## Purpose

Let a repository state, in one reviewed file, the project conventions that cannot be inferred from existing members, and the lint exemptions and baseline it has chosen, so that this knowledge lives with the project instead of in prompts and wrapper scripts.

Scenarios name the shipped fixtures: `Tests/Fixtures/add/app.pbxproj` (targets `App`, `AppExtension`, `AppTests`, `AppKit`; `App/Mixed` holds one file in `App` only and one in `AppExtension` only; `App/Filtered` holds one build file with `(ios, )` and one with no filter; nothing under `Tools/` and no source file at the source root), `Tests/Fixtures/rules/m3-orphan.pbxproj` (reference `AB12` for `AppTests/Views/FooTests.swift` has no parent group) and `Tests/Fixtures/model/app.pbxproj` (clean).

## ADDED Requirements

### Requirement: Discovery
The configuration SHALL be the file named by `--config`, or else the first `.pbxedit.yml` found in the current directory or its ancestors. Absence of a configuration file SHALL NOT be an error. A `--config` path that does not exist SHALL exit `2`. Every command SHALL accept `--config`.

#### Scenario: Found in an ancestor
- **WHEN** the command runs in `<root>/App/Views`, `<root>/.pbxedit.yml` exists and says `project: App.xcodeproj`
- **THEN** that file is used, `<root>/App.xcodeproj` is the project, and paths inside the file are interpreted relative to `<root>`

#### Scenario: No configuration
- **WHEN** no `.pbxedit.yml` exists in the current directory or any ancestor
- **THEN** every command behaves as it does without this capability

#### Scenario: Missing --config
- **WHEN** `--config other.yml` is given and no such file exists
- **THEN** the command exits `2` naming the path

### Requirement: Default project
When `project` is set and `--project` is not given, commands SHALL use that project, resolved relative to the directory holding the configuration file. `--project` SHALL override it.

#### Scenario: Project named in configuration
- **WHEN** the configuration has `project: App.xcodeproj`, the directory also contains `Tools.xcodeproj`, and `pbxedit lint` runs without `--project`
- **THEN** `App.xcodeproj` is linted and no ambiguity error is raised

### Requirement: Rules supply targets and platform filters
Each entry of `rules` SHALL have a `match` glob and may set `targets` and `platformFilters`. For a given path and attribute, the first rule in file order that matches the path and sets that attribute SHALL supply it. Globs SHALL match source-root-relative paths, with `*` matching within one path segment, `**` matching zero or more whole segments and `?` matching one character; character classes and brace expansion SHALL be rejected as unsupported.

#### Scenario: First file in a new target directory
- **WHEN** the configuration has a rule `match: "Tools/**"` with `targets: [AppKit]`, no file of the same kind exists in `Tools` or any ancestor of it, and `Tools/Build.swift` is added
- **THEN** the file joins `AppKit`, where inference alone would have exited `1` asking for `--target`

#### Scenario: Attributes come from different rules
- **WHEN** the first matching rule (`App/**`) sets only `platformFilters: [tvos]` and a later matching rule (`App/Mixed/**`) sets only `targets: [App]`, and `App/Mixed/New.swift` is added
- **THEN** the file joins `App` with `platformFilters = (tvos, )`

#### Scenario: Explicitly no filter
- **WHEN** a rule `App/Filtered/**` sets `platformFilters: []` and `App/Filtered/New.swift` is added, whose siblings disagree about filters
- **THEN** the build file is written with no `platformFilters`, and sibling filters are not consulted

### Requirement: Precedence
A value given by a command-line flag SHALL override the configuration. A value given by the configuration SHALL override inference, and SHALL suppress the ambiguity error inference would have raised for that attribute. The output SHALL attribute a configured decision to the configuration, giving the rule's position and glob: in text as `(config, rule <n> "<glob>")`, and in `--json` as `source.kind = "config"` with `source.rule` and `source.glob`, which are `null` for every other kind.

#### Scenario: Configuration resolves disagreement
- **WHEN** the siblings of `App/Mixed/New.swift` disagree about targets, rule 1 is `App/tvOS/**` with `platformFilters: [tvos]` and rule 2 is `App/Mixed/**` with `targets: [App]`
- **THEN** the add succeeds with target `App`, attributed to rule 2 `App/Mixed/**`

#### Scenario: Flag wins
- **WHEN** a rule `App/Views/**` sets `targets: [App]` and `--target AppTests` is given for `App/Views/Bar.swift`
- **THEN** the file joins `AppTests` only, attributed to the flag

### Requirement: Lint baseline default
When `lint.baseline` is set and neither `--baseline` nor `--write-baseline` is given, `pbxedit lint` SHALL behave as if `--baseline` named that file, resolved relative to the directory holding the configuration. `--no-baseline` SHALL disable this.

#### Scenario: Configured baseline
- **WHEN** the configuration has `lint: { baseline: .pbxedit-baseline.json }`, that file records the project's two `M3` findings, and `pbxedit lint` runs
- **THEN** only findings absent from that baseline are reported and the summary says `2 baselined`; with `--no-baseline` both `M3` findings are reported and the exit code is `1`

### Requirement: Path exemptions
`lint.exempt` SHALL map a rule ID to a list of globs. A finding of that rule whose path matches any of the globs SHALL be suppressed and counted in the summary as exempt: the text summary gains `, <n> exempt` when `n > 0`, and the JSON `summary` always carries `exempt`. Only rules whose findings carry a path — `M3`, `M6`, `D1`, `D2` — SHALL be exemptible. Exemptions SHALL be applied before the baseline, and `--write-baseline` SHALL NOT record exempt findings.

#### Scenario: Orphans under a directory stay out of groups
- **WHEN** the configuration exempts `M3` for `AppTests/Views/**` and `lint` runs on `rules/m3-orphan.pbxproj`, whose `AB12` (`AppTests/Views/FooTests.swift`) has no parent group
- **THEN** `lint` reports no `M3` finding, prints `0 errors, 0 warnings, 1 exempt`, and exits `0`; with the exemption on `App/**` instead, the finding is reported as before

#### Scenario: Structural rule cannot be exempted
- **WHEN** the configuration has `exempt: { S2: ["**"] }`
- **THEN** every command exits `2` saying `S2` is not exemptible and naming the line

### Requirement: An M3 exemption governs add
When a path matches an `M3` exemption, `pbxedit add` SHALL NOT create a group child for it, SHALL NOT create groups for it, and SHALL write its file reference with `sourceTree = SOURCE_ROOT`, the full path and `name`, attributing the location to the exemption: in text `(config, exempt M3 "<glob>")`, in `--json` `source.kind = "exemption"` with `source.glob` set and `source.rule` `null`. An existing reference on such a path that has no parent group SHALL be reused without gaining one. The pre-write and post-write checks SHALL honour the same exemption, so that a reference the plan creates or reuses on an exempt path raises no `M3` error.

#### Scenario: Exempt path
- **WHEN** `M3` is exempt for `Tools/**`, a rule gives `Tools/**` the target `AppKit`, and `Tools/Build.swift` is added
- **THEN** a file reference (`name = Build.swift; path = Tools/Build.swift; sourceTree = SOURCE_ROOT`), build file and phase entry are created, no group is created or modified, the location is attributed `(config, exempt M3 "Tools/**")`, the add succeeds, and `lint` with the same configuration is clean while `lint` without the exemption reports the one `M3`

#### Scenario: Pre-write check honours the exemption
- **WHEN** a plan creates a file reference for `Tools/Build.swift` with no group child and `M3` is exempt for `Tools/**`
- **THEN** the runner's check over the touched objects reports no `M3` error; without the exemption it does

### Requirement: Strict validation
The configuration SHALL be validated before any command acts. An unknown key, a value of the wrong type, a target name not in the project, an unknown platform name, an unknown rule ID, an unsupported glob, or malformed YAML SHALL exit `2` with the file name, the line, and what was expected. Nothing SHALL be written when validation fails. Target names SHALL be checked against the loaded project by every command that loads one.

#### Scenario: Misspelled key
- **WHEN** a rule has `target: [App]` instead of `targets`
- **THEN** the command exits `2` naming the file, the line, the key `target`, and the allowed keys `match, targets, platformFilters`

#### Scenario: Target that does not exist
- **WHEN** a rule names the target `AppTest` and the project has `App`, `AppExtension`, `AppKit` and `AppTests`
- **THEN** the command exits `2` naming the rule and listing the project's targets, and a mutating command leaves the project file unchanged

### Requirement: Configuration root
`project`, `lint.baseline` and every glob SHALL be relative to the directory holding the configuration file. That directory SHALL be the project's source root or an ancestor of it; otherwise the command SHALL exit `2`.

#### Scenario: Configuration above the source root
- **WHEN** `.pbxedit.yml` lies in `<root>` and the project is `<root>/Sub/App.xcodeproj`
- **THEN** a rule `match: "Sub/App/**"` applies to the project's `App/**` files, and a configuration in `<root>/Elsewhere` is rejected for that project
