# Spec Delta

## MODIFIED Requirements

### Requirement: Everything else is merged as text
Before the text merge, every path of every unit SHALL be removed from copies of base and theirs with `remove`'s planner, only in a copy that holds a reference for it (paths in synchronized folders are never removed). A group these removals leave empty is pruned, except one theirs holds and changed apart from its children, or added: that group SHALL stay, empty, in both copies, and the replay SHALL NOT prune it either, so theirs' change to it is merged as text. Ours SHALL then be merged line by line with the neutralised base and theirs: a region only one side changed takes that side's lines, a region both changed identically takes them once, and overlapping or same-position changes are a conflicting *hunk*. An array reached from the root through dictionary keys that ours and theirs both change, and whose shared elements they order differently — restricted to the elements both hold, counted, the two arrays differ — SHALL be kept in one piece: every change inside its lines, from the line of its `(` to the line of its `)`, SHALL join one stretch, which is a hunk whose `ours` is ours' whole array and whose `theirs` is theirs' whole array, whether or not the changes overlap line by line. No side's reorder is then split between a clean change and a hunk. An array whose two orders agree, or which only one side changes, SHALL be merged line by line as any other text. Each hunk SHALL be resolved by its decision: `ours` or `theirs` takes that side's lines verbatim; `both` takes ours' lines then theirs', and where that text does not qualify, ours' *untrimmed* lines then theirs' untrimmed lines. A side's untrimmed lines are its own together with the lines zealous trimming moved out of the hunk into the stable context before and after it, so each side's whole stretch is emitted once and the shared context the trimming lifted out is emitted between them. The two forms SHALL be tried in that order and the first that qualifies SHALL be the hunk's `both`; a hunk that trimming did not cut has one form only. `both` SHALL be offered only when the text with one of those forms parses and every `(object ID, key path)` pair ours changes and every pair theirs changes appears in it with that side's value, where the two sets are disjoint except for pairs that are insertions into one unordered array: an array in base, ours and theirs, of which base's is a subsequence of each side's; a direct attribute of an object named `buildConfigurations`, `children`, `dependencies`, `exceptions`, `fileSystemSynchronizedGroups`, `files`, `knownRegions`, `membershipExceptions`, `packageProductDependencies`, `packageReferences` or `targets`; to which no element ours inserts has the identity of one theirs inserts (the same string, or objects with the same `isa` and identifying fields, such as one package's `repositoryURL`); of which, in the three files the merge read, the elements ours and theirs both hold appear in the same relative order in each — two sides that only insert always agree, and a side that reordered elements the other kept in base's order does not; and which, in the `both` text, holds ours' elements plus theirs' additions with each side's elements in that side's order. Neither the hunk's key, the pairs it governs, nor the `base`, `ours` and `theirs` text the report shows for it SHALL depend on which form its `both` took. An array under `buildSettings`, `buildPhases` or `buildRules` carries meaning in its order and SHALL NOT be offered `both` when both sides change it. A `PBXFrameworksBuildPhase`'s `files` is link order, and SHALL be offered `both` only under the rule above — both sides inserting, the two orders agreeing in the files, and no inserted element having the identity of one the other inserted, which for a `PBXBuildFile` is the file or product it names — so the same framework added under two IDs, a removal and a reorder each keep `ours` and `theirs` only; a hunk whose `ours` or `theirs` resolution does not parse SHALL exit `2`. Every unit is neutralised whatever its outcome, so the hunks do not depend on unit decisions and one run reports every open unit and hunk.

#### Scenario: Theirs' change to a group its unit empties survives
- **WHEN** base has `App/Solo/Solo.swift` as the only child of group `App/Solo`, ours is base, and theirs sets `indentWidth = 2;` on that group and detaches the file from `App`
- **THEN** the command exits `0`, the merged group keeps its ID and has `indentWidth = 2`, and `App/Solo/Solo.swift` is in no target

#### Scenario: A group theirs deleted with its only file
- **WHEN** base has `App/Solo/Solo.swift` as the only child of group `App/Solo`, ours is base, and theirs is base after `pbxedit remove App/Solo/Solo.swift`
- **THEN** the command exits `0` with no hunk, and the merged project holds neither the file nor the group

#### Scenario: A setting and a file merge cleanly
- **WHEN** ours sets `SWIFT_VERSION = 5.10;` in `1000000000000000000000A1` and theirs sets `PRODUCT_BUNDLE_IDENTIFIER = com.example.App2;` in `1000000000000000000000A2` and adds `App/Services/New.swift`
- **THEN** the command exits `0` and the merged project carries both settings in their own configurations and the new file

#### Scenario: Conflicting setting values
- **WHEN** ours sets `SWIFT_VERSION = 5.10;` and theirs `SWIFT_VERSION = 6.2;` in `1000000000000000000000A1`
- **THEN** the command exits `3` and the report lists one hunk governing `1000000000000000000000A1` `buildSettings.SWIFT_VERSION` with base `6.0`, ours `5.10`, theirs `6.2`, and choices `ours` and `theirs` only; with the decision `theirs` the merged value is `6.2`

#### Scenario: Adjacent insertions
- **WHEN** ours adds `OTHER_SWIFT_FLAGS = "-DOURS";` and theirs adds `OTHER_LDFLAGS = "-ObjC";` as the last key of `1000000000000000000000A1`'s `buildSettings`
- **THEN** the report lists one hunk offering `ours`, `theirs` and `both`, and with `both` the merged `buildSettings` holds both keys

#### Scenario: Identical hunks in two configurations have two keys
- **WHEN** ours sets `SWIFT_VERSION = 5.10;` and theirs `SWIFT_VERSION = 6.2;` in both `1000000000000000000000A2` and `1000000000000000000000A3`, where base has no such key
- **THEN** the report lists two hunks with different keys, each governing only its own configuration

#### Scenario: Different insertions into one unordered array
- **WHEN** base has `knownRegions = (en, Base, );` in `EE0000000000000000000001`, ours inserts `de` and theirs inserts `fr` before `en`, one element per line
- **THEN** the command exits `3` with one hunk governing `EE0000000000000000000001` `knownRegions` offering `ours`, `theirs` and `both`; with the decision `both` it exits `0` with checks A–F passed and `knownRegions` is `(de, fr, en, Base, )`

#### Scenario: Both ends of one unordered array decided both
- **WHEN** base has `knownRegions = (en, Base, );`, ours `(de, en, Base, it, )` and theirs `(fr, en, Base, es, )`, one element per line, so that two hunks govern `EE0000000000000000000001 knownRegions`
- **THEN** each hunk offers `both`, and with both decided `both` the command exits `0` with `knownRegions` `(de, fr, en, Base, it, es, )`

#### Scenario: Two packages added on both sides
- **WHEN** base's project object has `packageReferences` holding one `XCRemoteSwiftPackageReference`, and ours and theirs each add one more after it, with different IDs and different `repositoryURL`s
- **THEN** the hunk governing `packageReferences` offers `ours`, `theirs` and `both`, and its `both` lines list ours' new package, then theirs'

#### Scenario: An array whose order matters keeps ours and theirs
- **WHEN** ours and theirs each insert a different element at the same place in `1000000000000000000000A1`'s `buildSettings.LD_RUNPATH_SEARCH_PATHS`
- **THEN** the hunk offers `ours` and `theirs` only

#### Scenario: The same package under two IDs keeps ours and theirs
- **WHEN** ours and theirs each add to base's `packageReferences` an `XCRemoteSwiftPackageReference` with the same `repositoryURL`, under two different IDs
- **THEN** the hunk over `packageReferences` offers `ours` and `theirs` only

#### Scenario: Two packages added on both sides keep their objects
- **WHEN** base's project object has `packageReferences` holding one `XCRemoteSwiftPackageReference`, and ours and theirs each add one more after it with different IDs and different `repositoryURL`s, each object spanning several lines and ending in the same `requirement` block
- **THEN** the report lists a second hunk, governing the two new objects' `isa`, `repositoryURL` and `requirement` keys, which offers `ours`, `theirs` and `both`; with both hunks decided `both` the command exits `0` with checks A–F passed, and the merged project lists all three packages and holds all three objects

#### Scenario: A both that the trimmed form fits keeps its lines
- **WHEN** base has `knownRegions = (en, Base, );` in `EE0000000000000000000001`, ours inserts `de` and theirs inserts `fr` before `en`, one element per line
- **THEN** the hunk's `both` lines are ours' one line then theirs' one line, with no line of the surrounding stable context between or around them

#### Scenario: Two objects added under one ID keep ours and theirs
- **WHEN** ours and theirs each add to base's `packageReferences` an `XCRemoteSwiftPackageReference` under the same ID with a different `repositoryURL`
- **THEN** the hunk governing that object offers `ours` and `theirs` only, in the untrimmed form as in the trimmed one

#### Scenario: Different links inserted into one Frameworks phase
- **WHEN** ours links `CoreHaptics.framework` and theirs `GameController.framework` into `App`'s Frameworks phase `CC0000000000000000000002`, each adding an SDKROOT file reference, a build file, a child of the `Frameworks` group and an entry of the phase's `files`
- **THEN** the hunk governing `CC0000000000000000000002` `files` offers `ours`, `theirs` and `both`, and with every hunk decided `both` the command exits `0` with checks A–F passed, both frameworks linked, ours' entry before theirs', and both build files in the phase

#### Scenario: A removal or a reorder in a Frameworks phase keeps ours and theirs
- **WHEN** base's `files` array of `CC0000000000000000000002` is no subsequence of one side's — each side replacing base's `Foundation.framework` entry with its own link, or, from a base that links two frameworks, ours swapping the two while theirs adds a third
- **THEN** the hunk governing `CC0000000000000000000002` `files` offers `ours` and `theirs` only, whatever the hunk's own texts show

#### Scenario: The same framework under two IDs keeps ours and theirs
- **WHEN** ours and theirs each link `GameController.framework` into `CC0000000000000000000002`, under different file-reference and build-file IDs
- **THEN** the hunk governing `CC0000000000000000000002` `files` offers `ours` and `theirs` only

#### Scenario: A reorder against an insertion keeps ours and theirs
- **WHEN** base has `knownRegions = (en, Base, );` in `EE0000000000000000000001`, ours swaps the two to `(Base, en, )` and theirs inserts `fr` after them, one element per line
- **THEN** the command exits `3` writing nothing, with one hunk governing `EE0000000000000000000001` `knownRegions` that offers `ours` and `theirs` only, its base text `en, Base`, ours' `Base, en` and theirs' `en, Base, fr`; decided `theirs` the command exits `0` with checks A–F passed and `knownRegions` `(en, Base, fr, )`, and decided `ours` it exits `0` with `(Base, en, )`

#### Scenario: A reorder and an insertion that do not overlap are one hunk
- **WHEN** base has `knownRegions = (en, Base, de, it, es, );`, ours moves `en` to the end, `(Base, de, it, es, en, )`, and theirs inserts `fr` after `de`, `(en, Base, de, fr, it, es, )`, one element per line
- **THEN** the command exits `3` with one hunk over `EE0000000000000000000001` `knownRegions` offering `ours` and `theirs`; decided `theirs` it exits `0` with theirs' array, and decided `ours` with ours'

#### Scenario: An insertion against a removal still merges with both
- **WHEN** base has `knownRegions = (en, Base, it, );`, ours `(de, en, Base, )` and theirs `(fr, en, Base, it, );`, one element per line
- **THEN** the hunk over `EE0000000000000000000001` `knownRegions` offers `both`, and with it the command exits `0` with checks A–F passed and `knownRegions` is `(de, fr, en, Base, )`

### Requirement: Nothing is written until every check passes
After the text merge and before the replay, and again after the replay, the command SHALL verify, and SHALL exit `1` writing nothing when a check fails, naming the check, the object ID and the key path or path:
- **A — no new finding.** The rule set over the result, warnings included, SHALL report nothing that neither ours nor theirs reports; a finding is matched by rule and path when it has a path, otherwise by rule, object and related objects. Exemptions from `.pbxedit.yml` apply.
- **B — membership.** Every target's managed rows, compared without IDs, SHALL equal ours' with the rows of every replayed unit and every unit decided `theirs` or `theirs-membership` taken from theirs.
- **C — accounting.** Over every leaf value of the neutralised base, ours and the neutralised theirs, recursing through dictionaries and keyed by object ID: a leaf only theirs changed SHALL have theirs' value in the text-merged result, one only ours changed or neither changed ours' value, one both changed identically that value; one both changed differently SHALL be governed by a decided hunk and have the decided side's value. An array only one side changed SHALL equal that side's, in order; one both changed SHALL hold ours' elements plus theirs' additions minus theirs' removals, each side's retained elements in that side's relative order. A leaf that several hunks govern, at least one decided `ours` or `theirs`, SHALL reflect every one of those decisions at once: measured against the text with every hunk resolved `ours`, each hunk's decided counterfactual (its `both` text for a hunk decided `both`) contributes its own change, and an array SHALL hold that text's elements plus every hunk's additions minus every hunk's removals, each counterfactual's retained elements in its order. A leaf that only `both` hunks govern SHALL follow the three-way rule above. Whatever governs it, an array in base, ours, theirs and the result SHALL hold every element that base, ours and theirs all hold, counted: no side removed it, so no decision may.
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

#### Scenario: An element every side holds is never dropped
- **WHEN** base has `knownRegions = (en, Base, );`, ours `(Base, en, )` and theirs `(en, Base, fr, )`, one element per line, the line merge is left to split ours' swap, for the test, and the one hunk is decided `theirs`
- **THEN** check C fails naming `EE0000000000000000000001` and `knownRegions` and the dropped `en`, the command exits `1`, and the output file is unchanged

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
