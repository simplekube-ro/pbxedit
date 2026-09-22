# Spec Delta

## Purpose

How a build file's platform filter is read, inferred, checked and written: both spellings Xcode has used are read as one value, rule S4 accepts exactly what Xcode accepts, and the tool writes the spelling Xcode 27 writes, so an Xcode save after a pbxedit write produces no diff.

Scenarios name the fixtures under `Tests/Fixtures/xcode27/`: `platform-filters-after-xcode27-save.pbxproj` (the `move/app.pbxproj` project as Xcode 27.0 saved it after a probe of every spelling: `App/Filtered/F1.swift` with `platformFilter = ios;` and `F2.swift` with `platformFilter = maccatalyst;`, both built by `App`; `App/Mixed/OnlyApp.swift` with `platformFilters = (macos, );` in `App` and `OnlyExt.swift` with `platformFilter = ios;` in `AppExtension`; `AppKit/Kit.swift` with `platformFilter = maccatalyst;` in `AppKit`; `App/iOS/Panel.swift` with `platformFilters = (ios, maccatalyst, );`; `App/Shared/Common.swift` with `platformFilters = (ios, tvos, );`; `App/tvOS/TV1.swift` and `TV2.swift` with `platformFilters = (tvos, );`), `platform-filters-before.pbxproj` (the same project as it was handed to Xcode, with `F1.swift` spelled `platformFilters = (ios, );` and `F2.swift` `platformFilters = (maccatalyst, );` — the spelling pbxedit wrote before this change), and `move-app-after-xcode27-save.pbxproj` / `repair-app-after-xcode27-save.pbxproj` (the release check's post-operation projects as Xcode saved them; `xcode27-save.diff` beside them is that save's diff).

## ADDED Requirements

### Requirement: Both spellings are read as one value
A build file's platform filter SHALL be read as a list of platform names: the `platformFilters` array when present, else the single `platformFilter` string as a one-element list, else the empty list. Every reader — the membership and target reports, sibling inference, `move`'s comparison of current and desired filters, and the operation output — SHALL use this one reading, so a project's filters are the same whichever spelling the file uses.

#### Scenario: Every spelling in the Xcode-saved probe is read
- **WHEN** `platform-filters-after-xcode27-save.pbxproj` is queried for `App/Filtered/F1.swift`, `App/Filtered/F2.swift`, `AppKit/Kit.swift`, `App/Mixed/OnlyApp.swift`, `App/iOS/Panel.swift`, `App/Shared/Common.swift` and `App/tvOS/TV1.swift`
- **THEN** the memberships report `platformFilters` of `[ios]`, `[maccatalyst]`, `[maccatalyst]`, `[macos]`, `[ios, maccatalyst]`, `[ios, tvos]` and `[tvos]` respectively, and `query --target App` lists `F1.swift` with `[ios]`

#### Scenario: The legacy spelling reads the same
- **WHEN** `platform-filters-before.pbxproj` and `platform-filters-after-xcode27-save.pbxproj` are both loaded
- **THEN** every path's membership report and every target's member listing are equal between the two, and neither has an S4 finding

#### Scenario: Inference reads the singular key
- **WHEN** `AppKit/New.swift` is to join `AppKit` in `platform-filters-after-xcode27-save.pbxproj`, whose one sibling `Kit.swift` has `platformFilter = maccatalyst;`
- **THEN** the inferred filters are `maccatalyst` (`inferred, 1 sibling in AppKit`), and for `App/Filtered/New.swift` joining `App` the siblings' `platformFilter = ios;` and `platformFilter = maccatalyst;` are reported as a disagreement listing `ios` and `maccatalyst`, asking for `--platform`

### Requirement: Rule S4 checks both keys
Rule S4 SHALL report as an error a `platformFilters` value that is not a property-list array of known platform names (`ios`, `maccatalyst`, `macos`, `tvos`, `watchos`, `xros`, `driverkit`), and a `platformFilter` value that is not a string equal to `ios` or `maccatalyst` — the two values Xcode writes with the singular key. A build file carrying either key with an allowed value SHALL have no S4 finding.

#### Scenario: The Xcode-saved probe is clean
- **WHEN** `lint` runs on `platform-filters-after-xcode27-save.pbxproj`
- **THEN** there is no S4 finding

#### Scenario: A singular key with a plural-only value
- **WHEN** a build file has `platformFilter = tvos;`
- **THEN** an `S4` error is reported on the build file, naming `tvos` and listing `ios, maccatalyst` as the values the singular key allows

#### Scenario: A singular key that is not a string
- **WHEN** a build file has `platformFilter = (ios, );`
- **THEN** an `S4` error is reported on the build file saying the value is not a string, and a build file with `platformFilters = ios;` is still reported as not an array

### Requirement: Filters are written as Xcode writes them
When a command writes a build file's platform filter, it SHALL write exactly one filter that is `ios` or `maccatalyst` as `platformFilter = <value>;`, any other non-empty list as `platformFilters = (<values>, );` in the order given, and an empty list as neither key. The key SHALL be placed in key order among the build file's attributes, as Xcode keeps them, and after the write the build file SHALL carry at most one of the two keys. This applies to every writer: `add`, `move` when it attaches a target or rewrites a retained build file, and any repair that writes a filter.

#### Scenario: Lone ios and lone maccatalyst are singular
- **WHEN** `pbxedit add App/Views/Canonical.swift --platform ios` and, separately, `--platform maccatalyst` run on `move/app.pbxproj`
- **THEN** the new build file's definition line reads `{isa = PBXBuildFile; fileRef = <id> /* Canonical.swift */; platformFilter = ios; }` and `platformFilter = maccatalyst;` respectively, with no `platformFilters` key

#### Scenario: Everything else is the array
- **WHEN** `pbxedit add App/Views/Canonical.swift --platform ios,tvos` and, separately, `--platform tvos` and `--platform none` run on `move/app.pbxproj`
- **THEN** the definition lines carry `platformFilters = (ios, tvos, );`, `platformFilters = (tvos, );` and no filter key at all

#### Scenario: An inferred lone ios is singular too
- **WHEN** `App/Mixed/New.swift` is added with `--target AppExtension` to `platform-filters-after-xcode27-save.pbxproj`, whose one `AppExtension` sibling has `platformFilter = ios;`
- **THEN** the decision reads `platformFilters: AppExtension: ios (inferred, 1 sibling in App/Mixed)` and the new build file carries `platformFilter = ios;`

### Requirement: An unchanged filter is never re-spelled
A build file whose filter value does not change SHALL be left byte for byte as it was, whatever its spelling. When the value changes, the build file SHALL end up with the canonical spelling of the new value and none of the old key.

#### Scenario: A move that keeps the value keeps the bytes
- **WHEN** `App/Filtered/F1.swift` (`platformFilter = ios;`) is moved to `App/Filtered/G1.swift` within `platform-filters-after-xcode27-save.pbxproj`
- **THEN** no membership change is reported and the build file's definition line differs only in the file name

#### Scenario: A changed value replaces the spelling
- **WHEN** `App/iOS/Panel.swift` (`platformFilter = ios;`) moves to `App/Shared/Panel.swift` in `move/app.pbxproj`, whose sibling has no filter, and `App/Shared/Common.swift` moves to `App/iOS/Common.swift`
- **THEN** `Panel.swift`'s build file loses its `platformFilter` key and `Common.swift`'s gains `platformFilter = ios;`, the output listing `platformFilters removed (was ios)` and `platformFilters = ios (was none)`

#### Scenario: The legacy spelling is replaced wholesale
- **WHEN** `App/Filtered/F1.swift` (`platformFilters = (ios, );` in `platform-filters-before.pbxproj`) moves to `AppKit/F1.swift` with `--target AppKit`, whose sibling has `platformFilter = maccatalyst;`
- **THEN** the build file created in `AppKit` carries `platformFilter = maccatalyst;`, and moving it with `--target App --platform maccatalyst` instead rewrites the retained build file to `platformFilter = maccatalyst;` with the `platformFilters` key removed

### Requirement: The Xcode-saved projects show no filter difference
After the release check's operations — `add App/Views/Bar.swift`, `move App/Views/Foo.swift App/Features/Foo.swift` and `remove App/Services/Rate.swift` on `move/app.pbxproj`; `lint --fix` on `repair/app.pbxproj` — every `platformFilter` or `platformFilters` line of the result SHALL be identical to the corresponding line of the Xcode-saved copy. The synchronized group Xcode reformats and the unfixable damage Xcode deletes are not part of this requirement.

#### Scenario: Regression for issue #6
- **WHEN** the release sequence runs on `move/app.pbxproj` and `lint --fix` on `repair/app.pbxproj`
- **THEN** the set of lines containing `platformFilter` in each result equals the set in `move-app-after-xcode27-save.pbxproj` and `repair-app-after-xcode27-save.pbxproj` respectively, and `lint` reports no S4 finding on either result

### Requirement: The command surface names the attribute, not the key
`--platform <list>|none`, the `.pbxedit.yml` `platformFilters` key, the decision line `platformFilters: <target>: <values> (<provenance>)`, the `platformFilters` change details and the `platformFilters` array in every JSON report SHALL keep their current syntax whatever spelling is written to the file.

#### Scenario: JSON is unchanged by the spelling
- **WHEN** `pbxedit add App/Views/Canonical.swift --platform ios --json` runs on `move/app.pbxproj`
- **THEN** the decision has `attribute` `platformFilters` and `value` `App: ios`, the membership report has `platformFilters` `["ios"]`, and the file carries `platformFilter = ios;`
