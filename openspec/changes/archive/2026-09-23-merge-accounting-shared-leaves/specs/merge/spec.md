# Spec Delta

## MODIFIED Requirements

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
