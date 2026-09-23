# Spec Delta

## MODIFIED Requirements

### Requirement: Idempotence and completion
Adding a path that is already a complete member of the chosen targets SHALL change nothing and exit `0`. When membership is partial, the command SHALL add only what is missing and SHALL reuse every existing object; it SHALL NOT create a second file reference for a path or a second build file for a reference within one target (rules M4, M5). A target the file already belongs to SHALL keep its build file exactly as it is: the build file is reused and its platform filter is never rewritten, whatever `--platform` says. Adding a member to another target with its own `--platform` SHALL extend its membership with a build file carrying those filters, reusing the file reference. `merge` replays membership through these guarantees (`merge`: Replay reproduces theirs exactly or says what it cannot).

#### Scenario: Re-add
- **WHEN** `pbxedit add App/Views/Foo.swift` runs against `app.pbxproj`, where the file is already a member of `App`
- **THEN** the run reports `modified: false`, exits `0`, and the project file's bytes are unchanged

#### Scenario: Reference exists without a group or phase entry
- **WHEN** `pbxedit add AppTests/Views/FooTests.swift --target App` runs against `partial.pbxproj`, where reference `AB12` is in no group and its build file `BF01` is in no phase
- **THEN** the command creates the groups `AppTests` and `Views` under the main group, adds `AB12` as a child of `Views`, adds `BF01` to the Sources phase `S001`, and creates no new reference or build file

#### Scenario: Add to a second target
- **WHEN** `App/Services/Rate.swift` is a member of `App` and `pbxedit add App/Services/Rate.swift --target AppExtension` runs
- **THEN** one build file and one phase entry are created for `AppExtension`'s Sources phase, and the file reference `AA0000000000000000000230` and the `Services` group are untouched

#### Scenario: A second add with another platform set extends membership
- **WHEN** `App/Services/Rate.swift` is a member of `App` with no filter and `pbxedit add App/Services/Rate.swift --target AppExtension --platform ios` runs
- **THEN** a build file with `platformFilter = ios;` is created in `AppExtension`'s Sources phase for the reference `AA0000000000000000000230`, `App`'s build file `BB0000000000000000000110` is unchanged and still has no filter, and no second reference is created

#### Scenario: A reused build file keeps its filter
- **WHEN** `App/tvOS/TV1.swift` is a member of `App` with `platformFilters = (tvos, );` and `pbxedit add App/tvOS/TV1.swift --target App --platform ios` runs
- **THEN** the build file `BB0000000000000000000120` is reused with `platformFilters = (tvos, );`, the run reports `modified: false`, exits `0`, and the project file's bytes are unchanged
