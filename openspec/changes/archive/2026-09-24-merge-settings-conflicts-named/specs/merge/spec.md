# Spec Delta

## MODIFIED Requirements

### Requirement: Replay reproduces theirs exactly or says what it cannot
A replay SHALL change membership only through `add`'s, `remove`'s and `move`'s planners and the platform-filter rewrite `move` performs, and SHALL treat the unit as a transition from what the merged file holds to theirs' membership. It SHALL keep the file reference wherever the path survives and each build file whose target survives, rewriting a surviving build file's filters in place when only they changed, so the attributes of both survive. It SHALL use `move` for a reference theirs moved and the file still holds, `remove` for a path theirs no longer has, and `add` with explicit targets, platforms and phase for a path or target theirs added, and never infers. Before classifying, the command SHALL replay each unit against ours in memory and compare the result with theirs: the unit's references' spelling (`path`, `name`, `sourceTree`) and resolved path, the resolved path of each one's parent group, its rows, and every other attribute of its references and build files, which SHALL equal theirs' where only theirs changed it and ours' where only ours did. A value base, ours and theirs do not agree on — ours differs from base, theirs differs from base and the two differ from each other, an absent value counting as a value — SHALL be a *conflicting* difference, since neither side's value can be kept without dropping the other's; a conflicting difference SHALL name what differs together with both sides' values, so a consumer can tell it from a change only one side made and show the user the value being kept. The test SHALL cover every value the comparison resolves per value: a build file's `settings` and every other attribute of a reference or a build file, and the references' spelling and the resolved path of the parent group. For a value no verb writes — `settings` and the attributes — a conflict SHALL be a difference whatever value the result holds, since a result that holds theirs' value there holds it by accident and the other side's change was dropped just the same. For spelling and the parent group, which the replay does write through `move` and `add`, the conflict SHALL label a difference that survives the replay, and a value the replay reproduced SHALL NOT be reported: both sides moving one file to different paths is a faithful replay, not a conflict. A unit's rows and whether a reference resolves to a path at all SHALL NOT be reported as conflicting values: they are the unit's own membership question, which its choices settle and whose three versions the report prints for each path. Each difference is a *residual* — typically build-file `settings`, a group other than the file's directory group, or a reference attribute such as `fileEncoding`, `includeInIndex`, `name` or `explicitFileType` — and makes the unit a decision offering `theirs-membership`.

#### Scenario: A re-filter keeps ours' attribute
- **WHEN** ours sets `fileEncoding = 4;` on the reference of `App/Filtered/F1.swift` and theirs re-filters the file with `pbxedit remove App/Filtered/F1.swift --target App` followed by `pbxedit add App/Filtered/F1.swift --target App --platform ios,macos`
- **THEN** the unit is replayed, the merged reference `AA0000000000000000000260` keeps `fileEncoding = 4;`, and its build file is `BB0000000000000000000140` with `platformFilters = (ios, macos, );`

#### Scenario: Build-file settings are a residual
- **WHEN** theirs adds `AppKit/Extra.h` to `AppKit`'s Headers phase with `settings = {ATTRIBUTES = (Public, ); };` on its build file
- **THEN** the command exits `3`; the unit offers `ours` and `theirs-membership`, not `theirs`, and its residual names the build file's `settings`; with the decision `theirs-membership` the command exits `0`, the merged project has `AppKit/Extra.h` in `AppKit`'s Headers phase without `settings`, and the report lists `settings` as owed for `AppKit/Extra.h`

#### Scenario: A group other than the directory's is a residual
- **WHEN** theirs adds `App/Views/Bar.swift` as a child of the `Services` group (`AA0000000000000000000013`) with `path = ../Views/Bar.swift`
- **THEN** the unit is a decision offering `ours` and `theirs-membership`, and its residual names the parent group

#### Scenario: A conflicting attribute is a difference whichever value the result holds
- **WHEN** base has no `fileEncoding` on `AA0000000000000000000260`, ours has `4`, theirs has `10`, and the comparison runs on a result holding `4` and again on one holding `10`
- **THEN** each comparison reports one conflicting residual for `fileEncoding` on `AA0000000000000000000260`, carrying ours' `4` and theirs' `10`

#### Scenario: A build-file attribute both sides changed is a conflict
- **WHEN** base builds `App/Filtered/F1.swift` in `App`, both sides set one attribute of its build file other than `fileRef`, its platform filters and `settings` to different values (for the test `compilerFlags`, `"-DOURS"` against `"-DTHEIRS"`), and theirs also re-filters the file to `ios, macos`
- **THEN** the comparison reports a conflicting residual naming that attribute of the build file in `App`, and the unit is a decision offering `ours` and `theirs-membership`

#### Scenario: Settings both sides changed are a conflict whichever value the result holds
- **WHEN** base has no `settings` on the build file of `App/Filtered/F1.swift` in `App`, ours sets `settings = {COMPILER_FLAGS = "-w"; };` on it, theirs re-creates that row with `settings = {COMPILER_FLAGS = "-Wall"; };`, and the comparison runs on a result holding ours' settings and again on one holding theirs'
- **THEN** each comparison reports the build file's `settings` as a conflicting residual carrying ours' `{COMPILER_FLAGS = "-w"; }` and theirs' `{COMPILER_FLAGS = "-Wall"; }`

#### Scenario: Theirs-membership owes the conflicting settings
- **WHEN** that unit is decided `theirs-membership`
- **THEN** the command exits `0` with checks A–F passed, the merged build file keeps ours' `settings = {COMPILER_FLAGS = "-w"; };`, and the report lists that `settings` as owed for the path, conflicting, with ours' and theirs' values

#### Scenario: Settings only theirs changed are not a conflict
- **WHEN** base has no `settings` on that build file, ours changes nothing about it, and theirs re-creates the row with `settings = {COMPILER_FLAGS = "-Wall"; };`
- **THEN** the residual for the build file's `settings` names theirs' value, is not conflicting, and carries no value for ours

#### Scenario: A name both sides changed is a conflict
- **WHEN** base has no `name` on the reference of `App/Filtered/F1.swift`, ours sets `name = OursName.swift;`, and theirs sets `name = TheirsName.swift;` and re-filters the file to `ios, macos`
- **THEN** the residual for `name` is conflicting and carries ours' `OursName.swift` beside theirs' `TheirsName.swift`

#### Scenario: Both sides moving one file differently is no conflict
- **WHEN** ours is base after `pbxedit move App/Filtered/F1.swift App/Views/F1.swift --keep-membership` and theirs is base after `pbxedit move App/Filtered/F1.swift App/Other/F1.swift --keep-membership`
- **THEN** the trial replay reports no residual at all — no spelling and no parent-group conflict, though the three versions hold three different paths and groups — and the unit is a decision offering `ours` and `theirs`
