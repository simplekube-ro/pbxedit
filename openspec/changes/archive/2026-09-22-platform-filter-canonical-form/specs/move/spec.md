# Spec Delta

## MODIFIED Requirements

### Requirement: Membership follows the destination
The targets and platform filters for `<to>` SHALL be determined as `add` determines them — `--target` and `--platform`, then configuration, then sibling inference at the destination — for the file's kind, taken from its extension or else from the phase its build files are in. Where they differ from the file's current membership, the command SHALL detach the file from targets no longer chosen (as `remove --target` does), attach it to newly chosen targets (as `add` does), rewrite the filters of retained build files whose value differs, and list each such change in the output. A retained build file's current filter SHALL be read from either key, and a rewritten one SHALL be written in the form Xcode writes, with the other key removed (`platform-filters`: Filters are written as Xcode writes them; An unchanged filter is never re-spelled). When nothing differs, nothing SHALL be emitted for membership. With `--keep-membership`, membership and filters SHALL be left exactly as they were; the destination's siblings then decide nothing, and a note SHALL say when they belong to other targets.

#### Scenario: Cross-target move
- **WHEN** `AppTests/Services/RateTests.swift` moves to `AppSlowTests/Services/RateTests.swift`, whose sibling belongs to `AppSlowTests`
- **THEN** the file reference `AA0000000000000000000310` is kept, the `AppTests` build file `BB0000000000000000000180` and its entry in `CC0000000000000000000005` are removed, a build file is created in `AppSlowTests`' Sources phase `CC0000000000000000000010`, and the output lists the detach, the attach and `targets: AppSlowTests (inferred, 1 sibling in AppSlowTests/Services)`

#### Scenario: Platform directory change
- **WHEN** `App/iOS/Panel.swift` with `platformFilter = ios;` moves to `App/Shared/Panel.swift`, whose sibling carries no filter
- **THEN** the build file `BB0000000000000000000190` keeps its ID, loses its `platformFilter` key, and the output lists the change; the reverse move of `App/Shared/Common.swift` into `App/iOS` gives `BB0000000000000000000200` `platformFilter = ios;`

#### Scenario: Keep membership
- **WHEN** the cross-target move above runs with `--keep-membership`
- **THEN** the file is still built only by `AppTests`, no build file is created or removed, and the output notes that the siblings in `AppSlowTests/Services` belong to `AppSlowTests`

#### Scenario: Destination is ambiguous
- **WHEN** `App/Views/Foo.swift` moves to `App/Mixed/Foo.swift`, where one sibling belongs to `App` and one to `AppExtension`, and neither a flag nor the configuration decides
- **THEN** the command exits `1` listing the variants and naming both remedies, `--target` and `--keep-membership`
