# Spec Delta

## MODIFIED Requirements

### Requirement: Each unit is replayed, skipped or decided
A unit SHALL be *skipped* when ours already holds theirs' membership for every path of the unit, compared without object IDs (both sides made the same change, or theirs only re-created objects), and no path of the unit carries a conflicting attribute change (Requirement: Replay reproduces theirs exactly or says what it cannot). It SHALL be *replayed* when ours holds base's membership for every path of the unit and the replay reproduces theirs (Requirement: Replay reproduces theirs exactly or says what it cannot). Otherwise it SHALL need a decision: `ours` keeps ours' membership for the unit; `theirs` replays theirs' membership onto ours'; `theirs-membership` replaces `theirs` when the replay cannot reproduce theirs, and replays what it can while listing the rest as owed. `ours` SHALL always be offered; `theirs` or `theirs-membership` SHALL be offered unless the replay cannot run at all, in which case the report SHALL say why. A unit a path of which carries a conflicting attribute change SHALL need a decision whatever its membership, offering `ours` and `theirs-membership`, never `theirs`: no unit SHALL be replayed or skipped while an attribute both sides changed to different values is unaccounted for.

#### Scenario: Both sides add different files
- **WHEN** ours is base after `pbxedit add App/Views/Bar.swift` and theirs is base after `pbxedit add App/Services/New.swift --platform ios`
- **THEN** the command exits `0`; the `App/Services/New.swift` unit is replayed; the merged project lists both files in `App`'s Sources phase, `New.swift` with `platformFilter = ios;`; and `Bar.swift` keeps ours' reference and build-file IDs

#### Scenario: Both sides made the same change
- **WHEN** ours and theirs are each base after `pbxedit add App/Views/Bar.swift` (so the two carry different IDs)
- **THEN** the unit is skipped, the merged project holds ours' objects for `Bar.swift` and no second reference or build file, and the command exits `0`

#### Scenario: Different changes to one file
- **WHEN** ours is base after `pbxedit move App/Filtered/F1.swift App/Views/F1.swift --keep-membership` and theirs is base after `pbxedit remove App/Filtered/F1.swift`
- **THEN** the command exits `3` and the report lists one unit, with the paths `App/Filtered/F1.swift` and `App/Views/F1.swift`, choices `ours` and `theirs`, and base's, ours' and theirs' membership for each path

#### Scenario: Keep theirs on delete against move
- **WHEN** ours is base after `pbxedit remove App/Filtered/F1.swift`, theirs is base after `pbxedit move App/Filtered/F1.swift App/Views/F1.swift --keep-membership`, and the decision for that unit is `theirs`
- **THEN** the merged project resolves a reference to `App/Views/F1.swift` built by `App` with `platformFilter = ios;`, and none to `App/Filtered/F1.swift`

#### Scenario: A conflicting attribute makes a unit a decision
- **WHEN** ours sets `fileEncoding = 4;` on the reference of `App/Filtered/F1.swift` (`AA0000000000000000000260`) and theirs re-filters that file with `pbxedit remove App/Filtered/F1.swift --target App` followed by `pbxedit add App/Filtered/F1.swift --target App --platform ios,macos` and sets `fileEncoding = 10;` on its reference
- **THEN** the command exits `3` writing nothing, and the unit for `App/Filtered/F1.swift` is a decision offering `ours` and `theirs-membership`, with a residual naming `fileEncoding`, ours' `4` and theirs' `10`

#### Scenario: Theirs-membership owes the conflicting attribute
- **WHEN** that unit is decided `theirs-membership`
- **THEN** the command exits `0` with checks A–F passed, the merged build file of `App/Filtered/F1.swift` has `platformFilters = (ios, macos, );`, its reference keeps `fileEncoding = 4;`, and the report lists `fileEncoding` as owed for that path

#### Scenario: Both sides re-filter and conflict
- **WHEN** ours re-filters `App/Filtered/F1.swift` to `macos` and sets `fileEncoding = 4;` on its reference, and theirs re-filters it to `ios, macos` and sets `fileEncoding = 10;`
- **THEN** the command exits `3`, the unit offers `ours` and `theirs-membership` and not `theirs`, and with `theirs-membership` it exits `0` with `platformFilters = (ios, macos, );`, `fileEncoding = 4;` and `fileEncoding` owed

#### Scenario: The same membership change with a conflicting attribute is not skipped
- **WHEN** ours and theirs are each base after `pbxedit add App/Views/Bar.swift` (so the two carry different IDs), ours sets `fileEncoding = 4;` on its new reference and theirs `fileEncoding = 10;` on its
- **THEN** the unit is a decision offering `ours` and `theirs-membership`, not skipped, with a residual naming `fileEncoding`, and the command exits `3`

### Requirement: Replay reproduces theirs exactly or says what it cannot
A replay SHALL change membership only through `add`'s, `remove`'s and `move`'s planners and the platform-filter rewrite `move` performs, and SHALL treat the unit as a transition from what the merged file holds to theirs' membership. It SHALL keep the file reference wherever the path survives and each build file whose target survives, rewriting a surviving build file's filters in place when only they changed, so the attributes of both survive. It SHALL use `move` for a reference theirs moved and the file still holds, `remove` for a path theirs no longer has, and `add` with explicit targets, platforms and phase for a path or target theirs added, and never infers. Before classifying, the command SHALL replay each unit against ours in memory and compare the result with theirs: the unit's references' spelling (`path`, `name`, `sourceTree`) and resolved path, the resolved path of each one's parent group, its rows, and every other attribute of its references and build files, which SHALL equal theirs' where only theirs changed it and ours' where only ours did. An attribute base, ours and theirs do not agree on — ours differs from base, theirs differs from base and the two differ from each other, an absent value counting as a value — SHALL be a *conflicting* difference whatever value the result holds, since neither side's value can be kept without dropping the other's; a conflicting difference SHALL name the attribute with both sides' values. Each difference is a *residual* — typically build-file `settings`, a group other than the file's directory group, or a reference attribute such as `fileEncoding`, `includeInIndex`, `name` or `explicitFileType` — and makes the unit a decision offering `theirs-membership`.

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

### Requirement: Nothing is written until every check passes
After the text merge and before the replay, and again after the replay, the command SHALL verify, and SHALL exit `1` writing nothing when a check fails, naming the check, the object ID and the key path or path:
- **A — no new finding.** The rule set over the result, warnings included, SHALL report nothing that neither ours nor theirs reports; a finding is matched by rule and path when it has a path, otherwise by rule, object and related objects. Exemptions from `.pbxedit.yml` apply.
- **B — membership.** Every target's managed rows, compared without IDs, SHALL equal ours' with the rows of every replayed unit and every unit decided `theirs` or `theirs-membership` taken from theirs.
- **C — accounting.** Over every leaf value of the neutralised base, ours and the neutralised theirs, recursing through dictionaries and keyed by object ID: a leaf only theirs changed SHALL have theirs' value in the text-merged result, one only ours changed or neither changed ours' value, one both changed identically that value; one both changed differently SHALL be governed by a decided hunk and have the decided side's value. An array only one side changed SHALL equal that side's, in order; one both changed SHALL hold ours' elements plus theirs' additions minus theirs' removals, each side's retained elements in that side's relative order. A leaf that several hunks govern, at least one decided `ours` or `theirs`, SHALL reflect every one of those decisions at once: measured against the text with every hunk resolved `ours`, each hunk's decided counterfactual (its `both` text for a hunk decided `both`) contributes its own change, and an array SHALL hold that text's elements plus every hunk's additions minus every hunk's removals, each counterfactual's retained elements in its order. A leaf that only `both` hunks govern SHALL follow the three-way rule above.
- **D — replay isolation.** Removing every replayed path from the text-merged result and from the final result SHALL give the same project.
- **E — per path.** For every replayed path, the comparison of Requirement "Replay reproduces theirs exactly or says what it cannot" SHALL find no difference other than the residuals listed as owed, a conflicting attribute change among them.
- **F — no membership as bytes.** Between ours and the text-merged result, no managed reference SHALL appear, disappear or change its spelling, resolved path or parents, and no build file of one SHALL appear, disappear or change its phases or platform filters.

#### Scenario: A lost setting fails accounting
- **WHEN** theirs sets `PRODUCT_NAME = Renamed;` in `1000000000000000000000A4` and the text merge is replaced, for the test, by taking ours verbatim
- **THEN** check C fails naming `1000000000000000000000A4` and `buildSettings.PRODUCT_NAME`, the command exits `1`, and the output file is unchanged, while `pbxedit lint` alone on the result reports nothing

#### Scenario: A value in the wrong configuration fails accounting
- **WHEN** check C runs on a result in which theirs' `SWIFT_VERSION` change to `1000000000000000000000A2` landed in `1000000000000000000000A3` instead
- **THEN** check C fails naming both configurations

#### Scenario: A lost reorder fails accounting
- **WHEN** check C runs on a result in which an array only theirs reordered (`App`'s `buildPhases`) keeps ours' order
- **THEN** check C fails naming the target and `buildPhases`

#### Scenario: Membership smuggled as bytes fails
- **WHEN** check F runs on a text-merged result that gained theirs' `App/Services/New.swift` reference and build file as text
- **THEN** check F fails naming the reference

#### Scenario: A replay that drops an attribute fails
- **WHEN** the re-filter scenario above replays with `remove --all` and `add` instead of keeping the reference, for the test
- **THEN** check E fails naming `AA0000000000000000000260`'s `fileEncoding`

#### Scenario: Two decided hunks govern one array
- **WHEN** base has `knownRegions = (en, Base, );` in `EE0000000000000000000001`, ours `(de, en, Base, it, )` and `SWIFT_VERSION = 5.10;` in `1000000000000000000000A1`, theirs `(fr, en, Base, es, )` and `SWIFT_VERSION = 6.2;` there, one element per line, so that two hunks govern `EE0000000000000000000001 knownRegions`, and the command is re-run with the head hunk and the tail hunk decided `ours`/`theirs`, `theirs`/`theirs` or `theirs`/`ours` (the setting hunk `ours`)
- **THEN** each run exits `0` with checks A–F passed, and `knownRegions` is `(de, en, Base, es, )`, `(fr, en, Base, es, )` and `(fr, en, Base, it, )` respectively

#### Scenario: A wrong result over a shared array still fails
- **WHEN** check C runs, with both `knownRegions` hunks of the scenario above decided `theirs`, on a result whose `knownRegions` is `(fr, en, Base, )`, `(fr, en, Base, it, )`, `(de, en, Base, es, )` or `(en, fr, Base, es, )`
- **THEN** check C fails naming `EE0000000000000000000001` and `knownRegions` for each, while `pbxedit lint` alone on the result reports no error

#### Scenario: A conflict dropped from a unit's residuals fails
- **WHEN** the conflicting-`fileEncoding` scenario is merged with the classification's conflicting residuals dropped, for the test, so the unit is replayed and nothing is owed
- **THEN** check E fails naming `AA0000000000000000000260` and `fileEncoding`, the command exits `1`, and the output file is unchanged
