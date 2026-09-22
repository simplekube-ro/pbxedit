# move Specification

## Purpose
Bring the project back in line with the disk after a file or directory has been moved or renamed, in one atomic step that keeps each file's identity in the project and changes its target membership only when the new location calls for it. The tool never moves anything on disk: the user (or `git mv`) does, and `pbxedit move` records it.

Scenarios name the fixture `Tests/Fixtures/move/app.pbxproj`: the `remove/app.pbxproj` project (targets `App`, `AppExtension`, `AppTests`, `AppKit`; the pathful groups `App` → `Views`, `Features` → `New`; the name-only group `Views` (`AA0000000000000000000011`) under `AppTests` holding `AppTests/Views/FooTests.swift` (`AA0000000000000000000140`, spelled `name = FooTests.swift; path = AppTests/Views/FooTests.swift; sourceTree = SOURCE_ROOT`); the variant group `AA0000000000000000000201`; the synchronized folder `App/Generated` (`AA0000000000000000000301`)) plus: a target `AppSlowTests` (`DD0000000000000000000005`, Sources phase `CC0000000000000000000010`) building `AppSlowTests/Services/SlowTests.swift`; `AppTests/Services/RateTests.swift` (`AA0000000000000000000310`, build file `BB0000000000000000000180` in `AppTests`' Sources `CC0000000000000000000005`); `App/iOS/Panel.swift` (`AA0000000000000000000320`, build file `BB0000000000000000000190` with `platformFilter = ios;`, the spelling Xcode writes for a lone `ios`) and `App/Shared/Common.swift` (no filter); the name-only group `State` (`AA0000000000000000000022`) under `AppTests` holding `AppTests/State/StateTests.swift` (`AA0000000000000000000340`, spelled `SOURCE_ROOT`); the pathful group `AppTests/Services` (`AA0000000000000000000027`); the directory `App/Views/Legacy` with `Top.swift`, `A/A1.swift`, `A/A2.swift`, `B/B1.swift`, `B/B2.swift` (groups `AA0000000000000000000023`–`25`, references `AA0000000000000000000350`–`354`, all built by `App`); `App/Models/User.swift` (`AA0000000000000000000370`, group `Models` `AA0000000000000000000026`); and `App/Old.swift` (`AA0000000000000000000380`, build file `BB0000000000000000000250`, a child of the `App` group `AA0000000000000000000002`).

## Requirements

### Requirement: Identity is preserved
`pbxedit move <from> <to>` SHALL keep the file reference's ID. A build file SHALL keep its ID when its target still builds the file after the move.

#### Scenario: Move within a target
- **WHEN** `App/Views/Foo.swift` (`AA0000000000000000000120`, build file `BB0000000000000000000020`) is moved to `App/Features/Foo.swift`, both directories' files belong to `App`, and the file has been moved on disk
- **THEN** the file reference ID and the build file ID are unchanged, and the Sources phase `CC0000000000000000000001` is not modified

### Requirement: The reference follows the file
After a move the file reference SHALL resolve to `<to>`, SHALL be a child of the group representing the destination directory and of no other group, and SHALL have `path`, `sourceTree` and `name` derived from that group chain by the rule `add` uses: `<group>` plus basename and no `name` under a group resolving to the directory; `SOURCE_ROOT`, the full path and `name` under a name-only group. Only attributes whose value changes SHALL be written. Missing destination groups SHALL be created, and groups left empty by the move SHALL be removed as `remove` does (never the main group or the products group). A reference already listed in the destination group (a rename within one directory) SHALL keep its listing in place.

#### Scenario: Re-parent between pathful groups
- **WHEN** `App/Views/Foo.swift` moves to `App/Features/Modern/Foo.swift` and no group exists for `Modern`
- **THEN** a group `Modern` (`path = Modern`) is created under `Features` (`AA0000000000000000000017`), the reference becomes its child with `path = Foo.swift; sourceTree = "<group>";` unchanged, and it is no longer a child of `Views` (`AA0000000000000000000003`)

#### Scenario: Source-root reference
- **WHEN** `AppTests/Views/FooTests.swift` (`AA0000000000000000000140`) moves to `AppTests/State/FooTests.swift`, whose group `State` (`AA0000000000000000000022`) has no path
- **THEN** its `path` becomes `AppTests/State/FooTests.swift`, `sourceTree` stays `SOURCE_ROOT`, `name` stays `FooTests.swift`, it is a child of `AA0000000000000000000022` and not of `AA0000000000000000000011`, and the emptied group `AA0000000000000000000011` is removed

#### Scenario: Source-root reference into a pathful group
- **WHEN** `AppTests/State/StateTests.swift` (`AA0000000000000000000340`, spelled `SOURCE_ROOT` with `name`) moves to `AppTests/Services/StateTests.swift`, whose group `AA0000000000000000000027` resolves to that directory
- **THEN** the reference is rewritten to `path = StateTests.swift; sourceTree = "<group>";` with no `name`, and the emptied group `State` is removed

#### Scenario: Reference that had no group
- **WHEN** the `SOURCE_ROOT` reference `AA0000000000000000000340` has been removed from every group (it still resolves to `AppTests/State/StateTests.swift`; a `<group>`-relative reference without a parent resolves nowhere useful and is not addressable) and `AppTests/State/StateTests.swift` moves to `AppTests/Services/StateTests.swift`
- **THEN** after the move it is a child of `AA0000000000000000000027` and of no other group, and the group `State`, empty before the move, is left alone

### Requirement: Renames update every comment
When the basename changes, every annotation comment naming the file — on the reference's definition, its group entry, each build file's definition and each phase entry — SHALL carry the new name, and the reference's `name` attribute, when the spelling keeps one, SHALL be the new basename, which is the shape Xcode writes for every `SOURCE_ROOT` reference with a `name` in the corpus. When the extension changes to one the file-type table knows, `lastKnownFileType` SHALL follow it (an `explicitFileType` is left alone).

#### Scenario: Rename in place
- **WHEN** `App/Old.swift` moves to `App/New.swift`
- **THEN** the project file no longer contains the text `Old.swift`, contains `New.swift in Sources` on the build file `BB0000000000000000000250`'s definition and its entry in `CC0000000000000000000001`, and the reference keeps its listing in the `App` group where it was

#### Scenario: Rename that changes the extension
- **WHEN** `App/Old.swift` moves to `App/Old.m`
- **THEN** the reference's `lastKnownFileType` becomes `sourcecode.c.objc`

#### Scenario: Rename of a named reference
- **WHEN** `AppTests/State/StateTests.swift` moves to `AppTests/State/StoreTests.swift`
- **THEN** the reference reads `name = StoreTests.swift; path = AppTests/State/StoreTests.swift; sourceTree = SOURCE_ROOT;`

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

### Requirement: The disk must already reflect the move
The command SHALL read the disk only to check, for each moved file, that `<to>` exists and `<from>` does not, and SHALL exit `1` without writing otherwise — before anything is planned, also under `--dry-run`.

#### Scenario: Move not yet performed
- **WHEN** `App/Views/Foo.swift` still exists on disk and `App/Features/Foo.swift` does not
- **THEN** the command exits `1` saying the file must be moved on disk first

#### Scenario: Both exist
- **WHEN** both paths exist on disk
- **THEN** the command exits `1` saying this looks like a copy, and suggests `add` for the new file

#### Scenario: Neither exists
- **WHEN** neither path exists on disk
- **THEN** the command exits `1` saying the destination does not exist

### Requirement: Source and destination are validated against the project
The command SHALL exit `1` without writing when no file reference resolves to `<from>` or beneath it, when a file reference already resolves to `<to>`, or when either path's reference is a child of a `PBXVariantGroup` or an `XCVersionGroup`. `<from>` equal to `<to>` SHALL be a usage error.

#### Scenario: Destination already a member
- **WHEN** `App/Views/Foo.swift` moves to `App/Shared.swift`, to which `AA0000000000000000000130` already resolves
- **THEN** the command exits `1` naming `AA0000000000000000000130`

#### Scenario: Unknown source
- **WHEN** `App/Fooo.swift` moves anywhere and nothing resolves to or beneath it
- **THEN** the command exits `1` saying the path is not in the project

#### Scenario: Localized variant
- **WHEN** `App/Resources/en.lproj/Localizable.strings` (`AA0000000000000000000210`, a child of the variant group `AA0000000000000000000201`) is the source
- **THEN** the command exits `1` naming the variant group

### Requirement: Synchronized folders
When `<to>` is covered by a synchronized root group, the command SHALL remove the file's reference, build files, phase entries and group child, as `remove` does for every target, and SHALL report that membership now comes from the folder, naming the group. When `<from>` has no reference and lies in a synchronized folder, the command SHALL exit `1` saying so and pointing to `add` for the destination.

#### Scenario: Into a synchronized folder
- **WHEN** `App/Models/User.swift` moves to `App/Generated/User.swift` and `App/Generated` is the synchronized root group `AA0000000000000000000301`
- **THEN** the reference `AA0000000000000000000370`, its build file `BB0000000000000000000240`, its entry in `CC0000000000000000000001` and its child in `Models` are removed, the emptied group `AA0000000000000000000026` is removed, the output names `AA0000000000000000000301`, and the membership afterwards reads as covered by that group

#### Scenario: Out of a synchronized folder
- **WHEN** `App/Generated/User.swift` moves to `App/Models/User.swift`
- **THEN** the command exits `1` naming the synchronized group and suggesting `pbxedit add App/Models/User.swift`

### Requirement: Directory moves
When no file reference resolves to `<from>` and one or more resolve to paths beneath it, the command SHALL treat `<from>` and `<to>` as directories and move every such member to the corresponding path under `<to>`, as a single all-or-nothing plan. Each file SHALL be subject to every requirement above, and pruning SHALL run once over the combined plan. Files on disk in the destination directories that no member maps to SHALL be ignored and counted in a note. A synchronized root group whose folder lies beneath `<from>` SHALL make the command exit `1` naming it.

#### Scenario: Directory rename
- **WHEN** the directory `App/Views/Legacy` has been renamed on disk to `App/Views/Modern`, with five member files in `Legacy`, `Legacy/A` and `Legacy/B`
- **THEN** all five references resolve under `App/Views/Modern`, the groups `AA0000000000000000000023`, `24` and `25` are gone, groups for `Modern`, `Modern/A` and `Modern/B` exist under `Views`, and every reference and build file keeps its ID

#### Scenario: One file missing at the destination
- **WHEN** `App/Views/Modern/B/B2.swift` does not exist on disk
- **THEN** the command exits `1` naming that file, and the project file is unchanged

#### Scenario: Extra files at the destination
- **WHEN** `App/Views/Modern/Extra.swift` exists on disk and is not a member
- **THEN** the move succeeds and a note counts one file under `App/Views/Modern` that is not in the project

#### Scenario: Synchronized folder beneath the source
- **WHEN** `App` moves to `Application`, and `App/Generated` is a synchronized root group
- **THEN** the command exits `1` naming `AA0000000000000000000301`, and the project file is unchanged

### Requirement: Safety, output and dry run
The rule set, scoped to the objects touched and to every former referrer of a deleted object, SHALL report no errors before and after the write (rules S2–S5, M1–M5). The output SHALL show, per file, the old and new path, each decision with its source, and each object created, changed or removed with its ID; `modified` SHALL be `true` if and only if the project file's bytes were replaced. `--dry-run` and `--json` SHALL behave as they do for `add`: the same JSON object plus `moves`, an array of `{from, to}` per file in plan order, with `results` the membership report of each destination path after the operation.

#### Scenario: Minimal diff
- **WHEN** `App/Views/Foo.swift` moves to `App/Features/Foo.swift` within one target between two pathful groups without a rename
- **THEN** the diff consists of exactly one line removed from `Views`' children and one line added to `Features`' children

#### Scenario: Message matches reality
- **WHEN** any `move` invocation finishes, whether it succeeded, was refused or failed
- **THEN** `modified` is `true` exactly when the bytes of `project.pbxproj` differ from before the run
