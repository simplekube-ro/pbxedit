# Spec Delta

## MODIFIED Requirements

### Requirement: Membership of a path
`pbxedit query <path>` SHALL report, for the file reference resolving to that path: its ID, its resolved path, the path of group names leading to it, every group that lists it, and its memberships — one entry per build file for each build phase listing it and each target owning that phase, giving the target (ID and name), the phase (ID and name), the build file ID and its `platformFilters`, read as `platform-filters` reads them (the `platformFilters` array, or the single `platformFilter` as a one-element array, or empty), so the report is the same whichever key the file uses. Facts SHALL be reported as found, including a reference with no group or a build file with no phase (rule M3 and rule M1 inputs, reported without judgement). When several references resolve to the path (rule M4's input), the first in object order is reported. Memberships SHALL be ordered by target name, then phase name, then build file ID.

#### Scenario: Ordinary member
- **WHEN** `App/Views/Foo.swift` is built by target `App` in its Sources phase (fixture `model/app.pbxproj`)
- **THEN** the report shows `member: true`, the reference ID `AA0000000000000000000120`, group path `App/Views`, groups `[AA0000000000000000000003]`, and one membership with target `App`, phase `Sources`, build file `BB0000000000000000000020` and `platformFilters` `[]`

#### Scenario: Shared source with platform filters
- **WHEN** `App/Shared.swift` has build files in the Sources phases of `App` and of `AppExtension`, the latter with `platformFilters = (ios, maccatalyst, )` (fixture `model/app.pbxproj`)
- **THEN** the report lists two memberships, `App` first then `AppExtension`, the second with `platformFilters` `[ios, maccatalyst]`

#### Scenario: Singular key reported as the same array
- **WHEN** `App/Filtered/F1.swift` (`platformFilter = ios;`) and `AppKit/Kit.swift` (`platformFilter = maccatalyst;`) are queried in `xcode27/platform-filters-after-xcode27-save.pbxproj`
- **THEN** their memberships report `platformFilters` `[ios]` and `[maccatalyst]`, in text as `platforms: ios` and `platforms: maccatalyst`

#### Scenario: Build file in no phase
- **WHEN** `AppTests/FooTests.swift` has a build file `BF01` that no phase lists (fixture `rules/m1-no-phase.pbxproj`)
- **THEN** the report shows `member: true` and one membership with build file `BF01` and target and phase given as absent

#### Scenario: Reference with no group
- **WHEN** `AppTests/Views/FooTests.swift` resolves to reference `AB12`, which is a child of no group (fixture `rules/m3-orphan.pbxproj`)
- **THEN** the report shows `member: true`, an absent group path, no groups, and its membership in `App`
