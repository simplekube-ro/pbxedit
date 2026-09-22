# Spec Delta

## Purpose

Turn the membership defects `lint` reports into a single reviewed repair, reusing the project's existing objects, so that a damaged project can be made consistent in one atomic, verifiable step rather than by hand.

## ADDED Requirements

### Requirement: Build files in no phase are listed (M1)
For a build file that no phase lists, `pbxedit lint --fix` SHALL add it to the build phase matching its file's type in the target that builds the file's siblings, determined as `add` infers targets (flags absent, then the configuration, then sibling inference). When that yields no single target, or the target has no such phase, or the file's type is unknown or never built, or the target already builds the file, the finding SHALL be left unrepaired with the reason. A build file in no phase whose `fileRef` and `productRef` both fail to resolve SHALL be deleted. A build file listed in more than one phase SHALL NOT be repaired.

#### Scenario: Test file that never ran
- **WHEN** `App/Services/Rate2.swift` has a build file listed in no phase, and every sibling in `App/Services` is built by `App`
- **THEN** the existing build file's ID is added to `App`'s Sources phase, no object is created, and `pbxedit query` reports the membership with target `App`

#### Scenario: Ambiguous target
- **WHEN** the siblings share no common target
- **THEN** the finding remains, reported as not fixable because the siblings have no target in common, with the variants listed

#### Scenario: Target without the phase
- **WHEN** the configuration sends `AppTests/Foo/fixture.json` to `AppTests`, whose target has no Resources phase
- **THEN** the finding remains, reported as not fixable because `AppTests` has no Resources phase

#### Scenario: Dead build file in no phase
- **WHEN** a build file in no phase has a `fileRef` naming an ID that does not exist
- **THEN** the build file is deleted and nothing else changes

### Requirement: Dangling phase entries are removed (M2)
A build-phase entry naming an ID that is not a build file SHALL be removed from the phase, every listing of it. A build file whose `fileRef` and `productRef` both fail to resolve SHALL be removed from every phase listing it and deleted.

#### Scenario: Entry pointing nowhere
- **WHEN** a Sources phase lists `DEAD0001` and no such object exists
- **THEN** that entry is removed and nothing else in the phase changes

#### Scenario: Build file with no file
- **WHEN** a build file's `fileRef` names a deleted reference and one phase lists the build file
- **THEN** the phase entry and the build file are both removed

### Requirement: Ungrouped file references are grouped (M3)
A file reference that is a child of no group SHALL be made a child of the group representing its resolved directory, creating missing groups as `add` does and inserting in name order where the group is already in name order. The reference's `path`, `sourceTree` and ID SHALL NOT change, and the reference SHALL resolve to the same path afterwards; when grouping would change what it resolves to — a `<group>`-relative `path` with a directory component — the finding SHALL be left unrepaired with a reason naming both paths and `remove` then `add`. A reference that is not project-relative, or that is a child of more than one group, SHALL be left unrepaired with the reason.

#### Scenario: Orphan with an existing group
- **WHEN** `App/Views/Baz.swift` is referenced with `sourceTree = SOURCE_ROOT`, built, and a child of no group, and a `Views` group resolves to `App/Views`
- **THEN** the reference becomes a child of that group, in name order, and the diff is one added line

#### Scenario: Orphans in a directory with no group
- **WHEN** three ungrouped references resolve into `App/Features` and no group represents that directory
- **THEN** one `Features` group is created under the `App` group, and all three references become its children in name order

#### Scenario: Source-root spelling is kept
- **WHEN** the orphan is written as `path = App/Views/Baz.swift; sourceTree = SOURCE_ROOT;`
- **THEN** after the repair those two attributes are byte-identical, and the reference resolves to the same path

#### Scenario: Group-relative orphan at the root
- **WHEN** the orphan is written as `path = README.md; sourceTree = "<group>";`
- **THEN** it becomes a child of the main group and still resolves to `README.md`

#### Scenario: Group-relative orphan that cannot keep its path
- **WHEN** the orphan is written as `path = App/Legacy/Old.swift; sourceTree = "<group>";`
- **THEN** it is not grouped, and the reason says it would resolve to `App/Legacy/App/Legacy/Old.swift` under the group for `App/Legacy` and names `pbxedit remove` then `pbxedit add`

#### Scenario: Two parents
- **WHEN** `App/Mixed/Dup.swift` is a child of two groups
- **THEN** it is not repaired, and the reason names both groups

### Requirement: Existing objects are reused
A repair SHALL NOT create a file reference or a build file, and SHALL NOT change the ID of any existing object. The only objects created SHALL be groups.

#### Scenario: Object census
- **WHEN** `lint --fix` repairs a project with M1, M2 and M3 findings
- **THEN** the number of file references is unchanged, the number of build files has not increased, and every ID present before is either still present or belonged to a deleted dangling build file

### Requirement: One plan, one write, verified
All repairs in an invocation SHALL be applied as a single plan and a single atomic write. The complete rule set SHALL be evaluated on the result before and after writing: every finding selected for repair SHALL be gone, and no finding SHALL exist that was absent before, findings being compared by rule, object and related objects. Otherwise nothing SHALL be written and the command SHALL exit `1` naming the offending finding.

#### Scenario: Large repair
- **WHEN** `lint --fix` runs on a project with 655 M3 findings spread over thirty directories, half of them without a group
- **THEN** the project file is written once, the diff contains only added group-children lines and new group definitions, and a following `pbxedit lint` reports no M3 finding

#### Scenario: A repair would cause new damage
- **WHEN** applying the plan would introduce a finding that did not exist before
- **THEN** the command exits `1` naming it, and the project file is unchanged

### Requirement: Idempotence
Running `lint --fix` on a project with no fixable findings SHALL write nothing.

#### Scenario: Second run
- **WHEN** `lint --fix` runs twice in succession
- **THEN** the second run reports `modified: false` and the project file's bytes are unchanged

### Requirement: Reporting and exit code
The output SHALL list each repaired finding with what was done and the IDs involved, then each remaining finding, marking those that are of a fixable rule but were not repaired with the reason, then a summary counting errors, warnings, repairs and not-fixable findings. `modified` SHALL be `true` if and only if the project file's bytes were replaced, and the last line SHALL say so. The exit code SHALL be that of `lint` evaluated on the result: `0` when no error remains, `1` otherwise. `--json` SHALL print one object with `schemaVersion`, `project`, `modified`, `dryRun`, `repaired` (each finding with its `decisions`, `changes` and `notes`), `remaining` (each finding with a `reason`, `null` unless it is of a fixable rule and was not repaired), `resolved`, `summary` (`errors`, `warnings`, `baselined`, `resolved`, `exempt`, `repaired`, `notFixable`), `diff` and `error`. `--dry-run` without `--fix`, and `--fix` with `--write-baseline`, SHALL be usage errors.

#### Scenario: Partial repair
- **WHEN** ten findings are repaired and an S2 error, three M1 and two M3 findings no fixer can take remain
- **THEN** the output lists the ten repairs, then the six remaining findings in `lint`'s order with the M1 and M3 ones marked not fixable and why, the summary says `6 errors, 0 warnings, 10 repaired, 5 not fixable`, and the exit code is `1`

#### Scenario: Flags that do not go together
- **WHEN** `lint --dry-run` is given without `--fix`, or `lint --fix --write-baseline <file>`
- **THEN** the command exits `2` saying so and nothing is written

### Requirement: Dry run
`lint --fix --dry-run` SHALL print the same report plus a unified diff, SHALL write nothing, and SHALL exit with the code the real run would have.

#### Scenario: Preview before adoption
- **WHEN** `pbxedit lint --fix --dry-run` runs on the damaged project
- **THEN** the diff is shown, `modified` is `false`, and the project file is unchanged

### Requirement: Exemptions and baselines
A finding suppressed by a configured exemption SHALL NOT be repaired. A baseline SHALL NOT limit repairs: baselined findings of fixable rules SHALL be repaired, and the output SHALL say how many baseline entries are now resolved and that the baseline can be rewritten with `--write-baseline`. The baseline file SHALL NOT be modified.

#### Scenario: Exempt path is left alone
- **WHEN** `M3` is exempt for `Tools/Generated/**` and an ungrouped reference resolves there
- **THEN** it is not grouped, and no group is created for it

#### Scenario: Baselined damage is repaired
- **WHEN** the baseline holds every current finding and `lint --fix` runs
- **THEN** all fixable ones are repaired, the output reports them as resolved baseline entries with the `--write-baseline` hint, and the baseline file's bytes are unchanged
