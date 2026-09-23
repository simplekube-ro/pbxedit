# merge Specification

## Purpose

Merge three versions of one `project.pbxproj` — a common base, ours and theirs — semantically: file membership is replayed with pbxedit's own planners instead of merged as lines, everything else is merged as text, and every change either side made is accounted for before a byte is written, so a conflicted project file can be resolved without leaving pbxedit.

Scenarios name `base`, `ours` and `theirs`. Unless a scenario says otherwise, `base` is `Tests/Fixtures/xcode27/platform-filters-after-xcode27-save.pbxproj` (targets `App`, `AppExtension`, `AppTests`, `AppKit`, `AppSlowTests`; six `Debug` build configurations `1000000000000000000000A1`–`A6`; the synchronized folder `App/Generated`), and `ours` and `theirs` are `base` after the operations the scenario names, made with pbxedit itself or, for settings, by editing the text. "Replayed", "skipped" and "decision" are the outcomes of a unit (Requirement: Membership changes are grouped into units).

## Requirements

### Requirement: Inputs and output
`pbxedit merge <base> <ours> <theirs>` SHALL read the three files and write nothing but its output file. The output SHALL be the file named by `--output <file>`, or else the `project.pbxproj` of the project located as every other command locates one (`--project`, the `project` key of `.pbxedit.yml`, the single `.xcodeproj` in the current directory); with neither, the command SHALL exit `2`. The three inputs SHALL NOT be modified unless one of them is the output. `.pbxedit.yml` — found as for every command, or named with `--config` — SHALL be read only for its `lint.exempt` globs (the checks honour them) and SHALL be bound to the located project's source root; with `--output` alone no configuration is read, and a `--config` for which no project can be located SHALL exit `2` saying it needs a project's source root. A configuration that does not load SHALL be reported as itself (exit `2`), not as nowhere to write. The command SHALL never prompt.

#### Scenario: Default output is the project file
- **WHEN** `pbxedit merge b.pbxproj o.pbxproj t.pbxproj --project App.xcodeproj` runs, where `o.pbxproj` is ours with `App/Views/Bar.swift` added and `t.pbxproj` is theirs with `App/Services/New.swift` added
- **THEN** `App.xcodeproj/project.pbxproj` holds the merge, the three input files are byte-for-byte unchanged, and no other file in the directory is created or modified

#### Scenario: Explicit output
- **WHEN** the same merge runs with `--output merged.pbxproj` and no project can be located
- **THEN** `merged.pbxproj` holds the merge and the command exits `0`

#### Scenario: Nowhere to write
- **WHEN** neither `--output` is given nor a project can be located
- **THEN** the command exits `2` saying where the output would go, and writes nothing

#### Scenario: A broken configuration is not nowhere to write
- **WHEN** the merge runs next to `App.xcodeproj` with no `--output` and a `.pbxedit.yml` that is not valid YAML
- **THEN** the command exits `2` naming `.pbxedit.yml`, does not say "nowhere to write", and writes nothing

#### Scenario: An explicit configuration needs a project
- **WHEN** the merge runs with `--output merged.pbxproj --config ci.yml` where no project can be located and `ci.yml` has no `project` key
- **THEN** the command exits `2` saying the configuration binds its paths to a project's source root, and writes nothing

### Requirement: Membership changes are grouped into units
The command SHALL compare, per path, the membership each version holds: whether a project-relative file reference resolves to the path, its `path`, `name` and `sourceTree`, the resolved path of its parent group, and its rows — one per build file in a Sources, Resources or Headers phase, as target, phase kind, platform filters (read as `platform-filters` reads them) and build-file `settings`. A reference is *managed* when its `sourceTree` is `<group>` or `SOURCE_ROOT`, it resolves to a project-relative path no synchronized folder covers, its parents are plain groups, it is no target's product, and each of its build files is listed only in Sources, Resources or Headers phases, each owned by a target; every other reference, build file and row is not membership and travels as text. The paths whose membership or whose reference or build-file IDs differ between base and theirs SHALL be linked into units: two paths belong to one unit when one version's reference or build file at one path has the same ID as another version's at the other path. A unit therefore holds both ends of a rename, and a reference-only change (a reference gained or dropped with no build file, or a directory move of a file no target builds) is a unit like any other.

#### Scenario: Rename is one unit
- **WHEN** theirs is base after `pbxedit move App/Views/Foo.swift App/Features/Foo.swift --keep-membership`
- **THEN** the report lists one unit with the paths `App/Views/Foo.swift` and `App/Features/Foo.swift`, outcome replayed, and the merged project resolves reference `AA0000000000000000000120` to `App/Features/Foo.swift` with its build file `BB0000000000000000000020` still in `App`'s Sources phase

#### Scenario: A file no target builds
- **WHEN** theirs is base after `pbxedit add App/Notes.md` (a reference and a group child, no build file)
- **THEN** the report lists a unit for `App/Notes.md`, outcome replayed, and the merged project has a reference resolving to it as a child of the `App` group, with no build file

#### Scenario: Unmanaged changes are not units
- **WHEN** theirs adds a `SDKROOT` reference for `System/Library/Frameworks/Combine.framework` and a build file for it in `App`'s Frameworks phase
- **THEN** no unit is reported for it, and the merged project carries both objects with theirs' IDs and values

### Requirement: Each unit is replayed, skipped or decided
A unit SHALL be *skipped* when ours already holds theirs' membership for every path of the unit, compared without object IDs (both sides made the same change, or theirs only re-created objects). It SHALL be *replayed* when ours holds base's membership for every path of the unit and the replay reproduces theirs (Requirement: Replay reproduces theirs exactly or says what it cannot). Otherwise it SHALL need a decision: `ours` keeps ours' membership for the unit; `theirs` replays theirs' membership onto ours'; `theirs-membership` replaces `theirs` when the replay cannot reproduce theirs, and replays what it can while listing the rest as owed. `ours` SHALL always be offered; `theirs` or `theirs-membership` SHALL be offered unless the replay cannot run at all, in which case the report SHALL say why.

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

### Requirement: Replay reproduces theirs exactly or says what it cannot
A replay SHALL change membership only through `add`'s, `remove`'s and `move`'s planners and the platform-filter rewrite `move` performs, and SHALL treat the unit as a transition from what the merged file holds to theirs' membership. It SHALL keep the file reference wherever the path survives and each build file whose target survives, rewriting a surviving build file's filters in place when only they changed, so the attributes of both survive. It SHALL use `move` for a reference theirs moved and the file still holds, `remove` for a path theirs no longer has, and `add` with explicit targets, platforms and phase for a path or target theirs added, and never infers. Before classifying, the command SHALL replay each unit against ours in memory and compare the result with theirs: the unit's references' spelling (`path`, `name`, `sourceTree`) and resolved path, the resolved path of each one's parent group, its rows, and every other attribute of its references and build files, which SHALL equal theirs' where only theirs changed it and ours' where only ours did. Each difference is a *residual* — typically build-file `settings`, a group other than the file's directory group, or a reference attribute such as `fileEncoding`, `includeInIndex`, `name` or `explicitFileType` — and makes the unit a decision offering `theirs-membership`.

#### Scenario: A re-filter keeps ours' attribute
- **WHEN** ours sets `fileEncoding = 4;` on the reference of `App/Filtered/F1.swift` and theirs re-filters the file with `pbxedit remove App/Filtered/F1.swift --target App` followed by `pbxedit add App/Filtered/F1.swift --target App --platform ios,macos`
- **THEN** the unit is replayed, the merged reference `AA0000000000000000000260` keeps `fileEncoding = 4;`, and its build file is `BB0000000000000000000140` with `platformFilters = (ios, macos, );`

#### Scenario: Build-file settings are a residual
- **WHEN** theirs adds `AppKit/Extra.h` to `AppKit`'s Headers phase with `settings = {ATTRIBUTES = (Public, ); };` on its build file
- **THEN** the command exits `3`; the unit offers `ours` and `theirs-membership`, not `theirs`, and its residual names the build file's `settings`; with the decision `theirs-membership` the command exits `0`, the merged project has `AppKit/Extra.h` in `AppKit`'s Headers phase without `settings`, and the report lists `settings` as owed for `AppKit/Extra.h`

#### Scenario: A group other than the directory's is a residual
- **WHEN** theirs adds `App/Views/Bar.swift` as a child of the `Services` group (`AA0000000000000000000013`) with `path = ../Views/Bar.swift`
- **THEN** the unit is a decision offering `ours` and `theirs-membership`, and its residual names the parent group

### Requirement: Everything else is merged as text
Before the text merge, every path of every unit SHALL be removed from copies of base and theirs with `remove`'s planner, only in a copy that holds a reference for it (paths in synchronized folders are never removed). A group these removals leave empty is pruned, except one theirs holds and changed apart from its children, or added: that group SHALL stay, empty, in both copies, and the replay SHALL NOT prune it either, so theirs' change to it is merged as text. Ours SHALL then be merged line by line with the neutralised base and theirs: a region only one side changed takes that side's lines, a region both changed identically takes them once, and overlapping or same-position changes are a conflicting *hunk*. Each hunk SHALL be resolved by its decision: `ours` or `theirs` takes that side's lines verbatim, `both` takes ours' lines then theirs'. `both` SHALL be offered only when the text with `both` parses and the `(object ID, key path)` pairs ours changes and those theirs changes are disjoint and both appear in it with their side's values; a hunk whose `ours` or `theirs` resolution does not parse SHALL exit `2`. Every unit is neutralised whatever its outcome, so the hunks do not depend on unit decisions and one run reports every open unit and hunk.

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

### Requirement: Nothing is written until every check passes
After the text merge and before the replay, and again after the replay, the command SHALL verify, and SHALL exit `1` writing nothing when a check fails, naming the check, the object ID and the key path or path:
- **A — no new finding.** The rule set over the result, warnings included, SHALL report nothing that neither ours nor theirs reports; a finding is matched by rule and path when it has a path, otherwise by rule, object and related objects. Exemptions from `.pbxedit.yml` apply.
- **B — membership.** Every target's managed rows, compared without IDs, SHALL equal ours' with the rows of every replayed unit and every unit decided `theirs` or `theirs-membership` taken from theirs.
- **C — accounting.** Over every leaf value of the neutralised base, ours and the neutralised theirs, recursing through dictionaries and keyed by object ID: a leaf only theirs changed SHALL have theirs' value in the text-merged result, one only ours changed or neither changed ours' value, one both changed identically that value; one both changed differently SHALL be governed by a decided hunk and have the decided side's value. An array only one side changed SHALL equal that side's, in order; one both changed SHALL hold ours' elements plus theirs' additions minus theirs' removals, each side's retained elements in that side's relative order. A leaf that several hunks govern, at least one decided `ours` or `theirs`, SHALL reflect every one of those decisions at once: measured against the text with every hunk resolved `ours`, each hunk's decided counterfactual (its `both` text for a hunk decided `both`) contributes its own change, and an array SHALL hold that text's elements plus every hunk's additions minus every hunk's removals, each counterfactual's retained elements in its order. A leaf that only `both` hunks govern SHALL follow the three-way rule above.
- **D — replay isolation.** Removing every replayed path from the text-merged result and from the final result SHALL give the same project.
- **E — per path.** For every replayed path, the comparison of Requirement "Replay reproduces theirs exactly or says what it cannot" SHALL find no difference other than the residuals listed as owed.
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

### Requirement: Decisions round trip
When any unit or hunk needs a decision that was not supplied, the command SHALL exit `3`, write nothing, and report every open unit and hunk at once, each with a stable key, its base, ours and theirs values, its allowed choices and, for a hunk, the `(object ID, key path)` pairs it governs. The report SHALL include a decisions template: a JSON object `{"inputs": {"base": <sha256>, "ours": <sha256>, "theirs": <sha256>}, "units": {<key>: null, …}, "hunks": {<key>: null, …}}`. `--decisions <file>` SHALL supply the choices in that shape. A unit key SHALL be derived from the unit's paths and its three versions' membership, a hunk key from its three texts and the object IDs it governs, so the same inputs always give the same keys and two identical hunks in different objects get different keys. A decisions file whose `inputs` do not match the three files' SHA-256, that names a key which matches nothing, or that gives a choice the item does not offer SHALL exit `2` and apply nothing.

#### Scenario: Template and re-run
- **WHEN** the conflicting-setting scenario exits `3` and its template, with the hunk set to `theirs`, is passed back with `--decisions`
- **THEN** the command exits `0` and the report lists the hunk as decided `theirs`

#### Scenario: Stale decisions
- **WHEN** a decisions file written for other inputs is passed
- **THEN** the command exits `2` saying the decisions are for other inputs, and writes nothing

#### Scenario: Unknown key or refused choice
- **WHEN** a decisions file names a hunk key that is not in the report, or gives `both` for a hunk that does not offer it
- **THEN** the command exits `2` naming the key, and writes nothing

### Requirement: Unsupported inputs
The command SHALL exit `2`, writing nothing and naming the cause, when an input does not parse or load, when theirs adds or removes a target or ours removes one (targets are matched by name; a target only ours added is supported), when a unit path has two managed references in one version, or when a hunk's `ours` or `theirs` resolution does not parse.

#### Scenario: Theirs adds a target
- **WHEN** theirs has a `PBXNativeTarget` named `Widget` that base and ours do not
- **THEN** the command exits `2` naming `Widget` and theirs

#### Scenario: A target only ours added
- **WHEN** ours adds a target `Widget` and theirs adds `App/Services/New.swift`
- **THEN** the command exits `0` and the merged project has both

#### Scenario: Input does not parse
- **WHEN** theirs is truncated in the middle of an object
- **THEN** the command exits `2` naming theirs with the parser's line and column

### Requirement: Output, dry run and exit codes
The command SHALL exit `0` when the merge is written and verified or there is nothing to change, `1` when a check fails or a planner refuses a step, `2` for usage errors and unsupported inputs, and `3` when decisions are needed. The report SHALL list each unit with its paths, outcome, decision, the changes its replay made with object IDs, and owed residuals; each hunk with its key and decision; each check with its result; and a last line `<output>: modified` or `<output>: not modified`, derived from whether the output file's bytes were replaced. The write SHALL be atomic (a temporary file beside the output, renamed over it), and the written bytes SHALL be read back and re-checked (A and B), restoring the previous bytes on failure. With `--dry-run` the command SHALL write nothing, print the report and a unified diff of ours against the merge, and exit with the code the real run would have. With `--json` the output SHALL be one JSON object with `schemaVersion`, `status` (`merged`, `decisionsNeeded`, `failed` or `unsupported`), `modified`, `dryRun`, `output`, `inputs`, `units`, `hunks`, `checks`, `owed`, `findings`, `template`, `diff` and `error`, absent values as `null`, never omitted.

#### Scenario: Nothing to change
- **WHEN** ours equals theirs
- **THEN** the command exits `0`, the report says there is nothing to merge, and the output file's bytes are unchanged unless they differed from ours

#### Scenario: Dry run
- **WHEN** the both-sides-add scenario runs with `--dry-run`
- **THEN** the diff shows `App/Services/New.swift` being added to ours, the output file is unchanged, the last line reads `not modified`, and the command exits `0`

#### Scenario: JSON on decisions needed
- **WHEN** the conflicting-setting scenario runs with `--json`
- **THEN** the output is one JSON object with `status` `decisionsNeeded`, `modified` `false`, one entry in `hunks` whose `choices` are `["ours", "theirs"]`, and `template` carrying that hunk's key with `null`

#### Scenario: Xcode can read the result
- **WHEN** the both-sides-add, rename and residual (`theirs-membership`) scenarios are merged
- **THEN** `xcodebuild -list` reads each merged project (oracle lane)
