# Spec Delta

## Purpose

Turn the membership defects `lint` reports into a single reviewed repair, reusing the project's existing objects, so that a damaged project can be made consistent in one atomic, verifiable step rather than by hand.

## ADDED Requirements

### Requirement: Build files in no phase are listed (M1)
For a build file that no phase lists, `pbxedit lint --fix` SHALL add it to the build phase matching its file's type in the target that builds the file's siblings, determined as `add` infers targets. When that inference yields no single target, or the target has no such phase, the finding SHALL be left unrepaired with the reason. A build file listed in more than one phase SHALL NOT be repaired.

#### Scenario: Test file that never ran
- **WHEN** `AppTests/Services/FooTests.swift` has a build file listed in no phase, and every sibling is built by `AppTests`
- **THEN** the existing build file's ID is added to `AppTests`' Sources phase, no object is created, and `pbxedit query` reports the membership with target `AppTests`

#### Scenario: Ambiguous target
- **WHEN** the siblings share no common target
- **THEN** the finding remains, reported as not fixable because the target is ambiguous, with the candidate targets listed

### Requirement: Dangling phase entries are removed (M2)
A build-phase entry naming an ID that is not a build file SHALL be removed from the phase. A build file whose `fileRef` and `productRef` both fail to resolve SHALL be removed from every phase listing it and deleted.

#### Scenario: Entry pointing nowhere
- **WHEN** a Sources phase lists `DEAD0001` and no such object exists
- **THEN** that entry is removed and nothing else in the phase changes

#### Scenario: Build file with no file
- **WHEN** a build file's `fileRef` names a deleted reference and one phase lists the build file
- **THEN** the phase entry and the build file are both removed

### Requirement: Ungrouped file references are grouped (M3)
A file reference that is a child of no group SHALL be made a child of the group representing its resolved directory, creating missing groups as `add` does and inserting in name order where the group is already in name order. The reference's `path`, `sourceTree` and ID SHALL NOT change. A reference that is not project-relative, or that is a child of more than one group, SHALL be left unrepaired with the reason.

#### Scenario: Orphan with an existing group
- **WHEN** `AppTests/Views/FooTests.swift` is referenced, built, and a child of no group, and a `Views` group exists under `AppTests`
- **THEN** the reference becomes a child of that group, and the diff is one added line

#### Scenario: Orphans in a directory with no group
- **WHEN** 95 ungrouped references resolve into `AppTests/SharePlay` and no group represents that directory
- **THEN** one `SharePlay` group is created under the `AppTests` group, and all 95 references become its children in name order

#### Scenario: Source-root spelling is kept
- **WHEN** the orphan is written as `path = AppTests/Views/FooTests.swift; sourceTree = SOURCE_ROOT;`
- **THEN** after the repair those two attributes are byte-identical, and the reference resolves to the same path

### Requirement: Existing objects are reused
A repair SHALL NOT create a file reference or a build file, and SHALL NOT change the ID of any existing object. The only objects created SHALL be groups.

#### Scenario: Object census
- **WHEN** `lint --fix` repairs a project with M1, M2 and M3 findings
- **THEN** the number of file references is unchanged, the number of build files has not increased, and every ID present before is either still present or belonged to a deleted dangling build file

### Requirement: One plan, one write, verified
All repairs in an invocation SHALL be applied as a single plan and a single atomic write. The complete rule set SHALL be evaluated on the result before and after writing: every finding selected for repair SHALL be gone, and no finding SHALL exist that was absent before. Otherwise nothing SHALL be written and the command SHALL exit `1` naming the offending finding.

#### Scenario: Large repair
- **WHEN** `lint --fix` runs on a project with 655 M3 findings spread over thirty directories
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
The output SHALL list each repaired finding with what was done and the IDs involved, then each remaining finding, marking those that are of a fixable rule but were not repaired with the reason. `modified` SHALL be `true` if and only if the project file's bytes were replaced. The exit code SHALL be that of `lint` evaluated on the result: `0` when no error remains, `1` otherwise.

#### Scenario: Partial repair
- **WHEN** 40 M3 findings are repaired and one S2 error and one ambiguous M1 remain
- **THEN** the output lists 40 repairs, then the two remaining findings with the M1 marked not fixable and why, and the exit code is `1`

### Requirement: Dry run
`lint --fix --dry-run` SHALL print the same report plus a unified diff, SHALL write nothing, and SHALL exit with the code the real run would have.

#### Scenario: Preview before adoption
- **WHEN** `pbxedit lint --fix --dry-run` runs on the damaged project
- **THEN** the diff is shown, `modified` is `false`, and the project file is unchanged

### Requirement: Exemptions and baselines
A finding suppressed by a configured exemption SHALL NOT be repaired. A baseline SHALL NOT limit repairs: baselined findings of fixable rules SHALL be repaired, and the output SHALL say how many baseline entries are now resolved and that the baseline can be rewritten with `--write-baseline`.

#### Scenario: Exempt path is left alone
- **WHEN** `M3` is exempt for `**/Generated/**` and an ungrouped reference resolves there
- **THEN** it is not grouped

#### Scenario: Baselined damage is repaired
- **WHEN** the baseline holds 655 M3 entries and `lint --fix` runs
- **THEN** all fixable ones are repaired and the output reports them as resolved baseline entries
