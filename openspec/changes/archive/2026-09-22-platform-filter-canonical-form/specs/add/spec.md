# Spec Delta

## MODIFIED Requirements

### Requirement: Platform filters are inferred only when unanimous
When `--platform` is not given, the new build files SHALL carry the platform filters that all siblings' build files in the same target carry, including none, reading a sibling's filter from either the `platformFilters` array or the single `platformFilter` key (`platform-filters`: Both spellings are read as one value). When siblings disagree, the command SHALL exit `1` asking for `--platform`. When no sibling is built by the target, the build file SHALL carry no filters (rule S4 names the values allowed). The chosen filters SHALL be written in the form Xcode writes: a lone `ios` or `maccatalyst` as `platformFilter = <value>;`, anything else as the `platformFilters` array (`platform-filters`: Filters are written as Xcode writes them).

#### Scenario: Platform directory
- **WHEN** `App/tvOS/TV3.swift` is added and every sibling in `App/tvOS` has `platformFilters = (tvos, )`
- **THEN** the new build file has `platformFilters = (tvos, )`

#### Scenario: Disagreement
- **WHEN** `App/Filtered/New.swift` is added and in `App/Filtered` one sibling has `platformFilter = ios;` and the other has no filter
- **THEN** the command exits `1`, lists the variants with counts, and asks for `--platform`

#### Scenario: Lone ios is written with the singular key
- **WHEN** `App/Views/Bar.swift` is added with `--platform ios`
- **THEN** the new build file has `platformFilter = ios;` and no `platformFilters` key, the decision reads `platformFilters: App: ios (flag)` and the membership report shows `platformFilters` `[ios]`
