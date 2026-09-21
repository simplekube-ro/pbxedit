# Spec Delta

## Purpose

Let a repository state, in one reviewed file, the project conventions that cannot be inferred from existing members, and the lint exemptions and baseline it has chosen, so that this knowledge lives with the project instead of in prompts and wrapper scripts.

## ADDED Requirements

### Requirement: Discovery
The configuration SHALL be the file named by `--config`, or else the first `.pbxedit.yml` found in the current directory or its ancestors. Absence of a configuration file SHALL NOT be an error. A `--config` path that does not exist SHALL exit `2`.

#### Scenario: Found in an ancestor
- **WHEN** the command runs in `<root>/App/Views` and `<root>/.pbxedit.yml` exists
- **THEN** that file is used, and paths inside it are interpreted relative to `<root>`

#### Scenario: No configuration
- **WHEN** no `.pbxedit.yml` exists in the current directory or any ancestor
- **THEN** every command behaves as it does without this capability

### Requirement: Default project
When `project` is set and `--project` is not given, commands SHALL use that project.

#### Scenario: Project named in configuration
- **WHEN** the configuration has `project: App.xcodeproj`, the directory also contains `Tools.xcodeproj`, and `pbxedit lint` runs without `--project`
- **THEN** `App.xcodeproj` is linted and no ambiguity error is raised

### Requirement: Rules supply targets and platform filters
Each entry of `rules` SHALL have a `match` glob and may set `targets` and `platformFilters`. For a given path and attribute, the first rule in file order that matches the path and sets that attribute SHALL supply it. Globs SHALL match source-root-relative paths, with `*` matching within one path segment, `**` matching across segments and `?` matching one character.

#### Scenario: First file in a new target directory
- **WHEN** the configuration has a rule `match: "AppSlowTests/**"` with `targets: [AppSlowTests]`, the directory `AppSlowTests/New` has no siblings in any ancestor of the same kind, and a file there is added
- **THEN** the file joins `AppSlowTests`

#### Scenario: Attributes come from different rules
- **WHEN** the first matching rule sets only `platformFilters: [tvos]` and a later matching rule sets only `targets: [App]`
- **THEN** the file joins `App` with `platformFilters = (tvos, )`

#### Scenario: Explicitly no filter
- **WHEN** a matching rule sets `platformFilters: []`
- **THEN** the build file is written with no `platformFilters`, and sibling filters are not consulted

### Requirement: Precedence
A value given by a command-line flag SHALL override the configuration. A value given by the configuration SHALL override inference, and SHALL suppress the ambiguity error inference would have raised for that attribute. The output SHALL attribute a configured decision to the configuration, giving the rule's position and glob.

#### Scenario: Configuration resolves disagreement
- **WHEN** siblings disagree about targets and a rule sets `targets: [App]`
- **THEN** the add succeeds with target `App`, attributed to rule 2 `App/Shared/**`

#### Scenario: Flag wins
- **WHEN** a rule sets `targets: [App]` and `--target AppTests` is given
- **THEN** the file joins `AppTests` only, attributed to the flag

### Requirement: Lint baseline default
When `lint.baseline` is set and neither `--baseline` nor `--write-baseline` is given, `pbxedit lint` SHALL behave as if `--baseline` named that file. `--no-baseline` SHALL disable this.

#### Scenario: Configured baseline
- **WHEN** the configuration has `lint: { baseline: .pbxedit-baseline.json }` and `pbxedit lint` runs
- **THEN** only findings absent from that baseline are reported

### Requirement: Path exemptions
`lint.exempt` SHALL map a rule ID to a list of globs. A finding of that rule whose path matches any of the globs SHALL be suppressed and counted in the summary as exempt. Only rules whose findings carry a path — `M3`, `M6`, `D1`, `D2` — SHALL be exemptible.

#### Scenario: Generated files stay out of groups
- **WHEN** the configuration exempts `M3` for `**/Generated/**` and `App/Generated/User.swift` has no parent group
- **THEN** `lint` reports no `M3` finding for it and the summary counts one exempt finding

#### Scenario: Structural rule cannot be exempted
- **WHEN** the configuration has `exempt: { S2: ["**"] }`
- **THEN** every command exits `2` saying `S2` is not exemptible and naming the line

### Requirement: An M3 exemption governs add
When a path matches an `M3` exemption, `pbxedit add` SHALL NOT create a group child for it, SHALL NOT create groups for it, and SHALL write its file reference with `sourceTree = SOURCE_ROOT` and the full path. The pre-write check SHALL honour the same exemption.

#### Scenario: Exempt path
- **WHEN** `M3` is exempt for `**/Generated/**` and `App/Generated/New.swift` is added
- **THEN** a file reference, build file and phase entry are created, no group is created or modified, and the add succeeds

### Requirement: Strict validation
The configuration SHALL be validated before any command acts. An unknown key, a value of the wrong type, a target name not in the project, an unknown platform name, an unknown rule ID, or malformed YAML SHALL exit `2` with the file name, the line, and what was expected. Nothing SHALL be written when validation fails.

#### Scenario: Misspelled key
- **WHEN** a rule has `target: [App]` instead of `targets`
- **THEN** the command exits `2` naming the file, the line, the key `target`, and the allowed keys

#### Scenario: Target that does not exist
- **WHEN** a rule names the target `AppTest` and the project has `App` and `AppTests`
- **THEN** the command exits `2` naming the rule and listing the project's targets
