# Design

## Context

See proposal.md — Why, and issue #6. The measured facts (Xcode 27.0, 27A266a; probe `Tests/Fixtures/xcode27/platform-filters-before.pbxproj` → `platform-filters-after-xcode27-save.pbxproj`):

| Handed to Xcode | Xcode saved |
|---|---|
| `platformFilters = (ios, );` | `platformFilter = ios;` |
| `platformFilters = (maccatalyst, );` | `platformFilter = maccatalyst;` |
| `platformFilter = ios;`, `platformFilter = maccatalyst;` | unchanged |
| `platformFilters = (tvos, );`, `(macos, );` | unchanged |
| `platformFilters = (ios, maccatalyst, );`, `(ios, tvos, );` | unchanged |

What exists. `PBXModel.BuildFile` exposes both keys (`platformFilters: [String]?`, `platformFilter: String?`) and `Membership.BuildFileEntry` forwards them. Four readers in `PBXOps` already normalise by hand with the same expression, `entry.platformFilters ?? entry.platformFilter.map { [$0] } ?? []` (`Conventions.platformFilters`, `MovePlanner`, `MembershipReport`, `TargetMembers`); `S4Rule` reads only `platformFilters`. Two writers exist, both plural-only: `Plan.apply(.createBuildFile)` appends a `platformFilters` array, and `MovePlanner` emits `setAttribute("platformFilters", …)` plus a `setAttribute("platformFilter", nil)` when the singular key was present. `lint --fix` writes no filter (archived `lint-fix` design: "left as found"). `Project.createObject` sorts attribute keys and `Project.setAttribute` inserts a new key in key order, so a `platformFilter` key lands after `fileRef`, where Xcode puts it, with no new model code.

Constraints: `serialize(parse(bytes)) == bytes` and "untouched bytes are never rewritten" (`docs/design.md` § 1); a `Step` maps one-to-one onto a model mutation (add-command design D1); `--platform`, the config key and the report shapes are shipped surface.

## Goals / Non-Goals

**Goals:**
- One reading of a build file's filter, one spelling rule for writing it, both in one place, used by every reader and writer in `PBXOps`.
- S4 accepts exactly the set of spellings Xcode 27 writes and rejects the rest, on both keys.
- The release check's two projects, after pbxedit's operations, differ from Xcode's saved copies in no `platformFilter*` line — asserted by a test that replays the check.

**Non-Goals:**
- Re-spelling filters the operation does not change (no normalisation pass, no `lint --fix` rule): the legacy plural single-`ios` is legal, Xcode reads it, and rewriting it would break the untouched-bytes rule.
- A model-level accessor: the model stays a faithful view of both keys; interpretation is an operations concern.
- Changing what `lint --fix` writes: it writes no filter today and gains none.

## Decisions

**D1 — The read rule lives in `PlatformFilters` (`Sources/PBXOps/Inference/PlatformFilters.swift`).** `PlatformFilters.read(from: BuildFile) -> [String]` returns `platformFilters ?? platformFilter.map { [$0] } ?? []`; the four hand-written copies call it. Precedence is plural-first because that is what the shipped readers already do and a build file with both keys is unmeasured (proposal, Non-goals); the rule is one line, so the choice is easy to revisit with evidence. Alternative: an accessor on `PBXModel.BuildFile`. Rejected: the model deliberately exposes what the file says (`platformFilter` is documented there as "the single-value form older Xcode versions wrote", which this change shows is not merely older); the enum that already holds S4's platform list and the `--platform` parser is the natural home for "what a filter means".

**D2 — The write rule is `PlatformFilters.spelling(of: [String]) -> Spelling`**, an enum `none | singular(String) | plural([String])`: `singular` when the list has exactly one element and it is `ios` or `maccatalyst` (`PlatformFilters.singularValues`), `plural` for any other non-empty list in the order given, `none` for empty. Two consumers:
- `Plan.apply(.createBuildFile)` appends `NewEntry("platformFilter", .string(v))` or `NewEntry("platformFilters", .array(…))` or nothing. `Step.createBuildFile(id:fileRef:platformFilters:)` keeps its shape — the step carries the value, the spelling is chosen when the step meets the model — so every existing plan expectation and `Change` detail holds.
- `MovePlanner`, for a retained build file whose value differs (compared through D1), emits `setAttribute` steps: the chosen key set to the new value, and whichever of the two keys the build file currently has but should not carry cleared with `nil`. The steps are ordinary `setAttribute`s, so they print, compare and apply as today. A build file whose value is unchanged gets no step, whatever its spelling — that is the untouched-bytes rule and the "legacy spelling is left alone" requirement in one.
Alternative: a new `Step.setPlatformFilters(of:to:)` applied by the planner. Rejected: add-command D1 pins one step to one model mutation; a compound step would need its own apply logic and would hide from `--dry-run` which keys change.

**D3 — S4 evaluates both keys per object.** For `platformFilters`: unchanged (array of known names). For `platformFilter`: must be a string, and the string must be in `PlatformFilters.singularValues`; the message names the offending value and lists `ios, maccatalyst`. The `Finding` title for S4 becomes "platform filters are known platform names, spelled as Xcode spells them". No finding is added for a build file carrying both keys, or for the non-canonical plural single-`ios` (proposal, Non-goals). Two new rule fixtures under `Tests/Fixtures/rules/`: `s4-singular-unknown.pbxproj` (`platformFilter = tvos;` beside a legal `platformFilter = ios;` and `platformFilter = maccatalyst;`) and `s4-singular-not-string.pbxproj` (`platformFilter = (ios, );`).

**D4 — Fixtures.** `Tests/Fixtures/xcode27/` holds the evidence as captured (byte-exact) with a `README.md` saying what each file is and that they are pbxedit's own fixtures saved by Xcode (no `NOTICE` entry). The hand-written `add`, `move`, `remove`, `repair` `app.pbxproj` fixtures rewrite their `platformFilters = (ios, );` lines to `platformFilter = ios;`: they stand for Xcode-written projects and Xcode never writes that line. `platform-filters-before.pbxproj` keeps the plural single-`ios` (and single-`maccatalyst`) spelling as the regression fixture for "the legacy spelling pbxedit still reads". Existing tests change only where the new spelling is the reason: `MovePlannerTests` step expectations (`platformFilter` key instead of `platformFilters`), `RepairPlannerTests`' "existing platformFilters are preserved" (through D1 rather than the raw plural accessor), the `move` spec's fixture paragraph.

**D5 — Vocabulary.** The flag, the config key, the decision attribute, the change details and the JSON key stay `platformFilters`/`--platform`: they name the attribute in pbxedit's vocabulary (the same word `docs/design.md` § Conventions uses), while the file's key is a spelling the tool chooses. Renaming any of them would be a surface change with no user benefit and a `schemaVersion` question.

**D6 — The regression test replays the release check.** `CLITests` runs `add App/Views/Bar.swift`, `move App/Views/Foo.swift App/Features/Foo.swift`, `remove App/Services/Rate.swift` on `move/app.pbxproj` and `lint --fix` on `repair/app.pbxproj` through the binary (the sequence of `docs/RELEASING.md` § 2 that produced the captured copies), then compares the multiset of lines containing `platformFilter` with the Xcode-saved copies' and asserts zero S4 on the results. The comparison is deliberately narrow, with a comment naming the two excluded kinds of difference (synchronized-group layout; Xcode's deletion of unfixable damage), so a future change to either shows up as a comment to update rather than as a silently loosened test. The oracle lane gains scenarios that run `add` and `move` on the Xcode-saved probe.

## Risks / Trade-offs

- [Xcode changes the canonical spelling again, or differs by version] → the probe pair is the evidence for one version and `docs/RELEASING.md` § 2 re-runs the check per release on the newest Xcode; the write rule is one function, and a new row in the table above is the change to make.
- [A build file with both keys] → read plural-first (D1), never written by pbxedit, not flagged. If evidence arrives that Xcode prefers the singular key, D1 and the S4 non-finding are the two lines to change.
- [Legacy `platformFilters = (ios, )` lines linger in projects pbxedit v0.1.0 wrote] → they are legal and Xcode rewrites them on its next save, which is the diff issue #6 reported once and then never again; pbxedit rewrites them the next time it changes the value. A normalising repair is deliberately not offered (proposal, Non-goals).
- [The narrow comparison in D6 hides other regressions] → it is one test among the existing byte-level diff snapshots; its job is only the filter lines, and the comment says so.

## Migration Plan

None for users: reading is a superset of before, writing is what Xcode wants. Projects with lines pbxedit v0.1.0 wrote converge on Xcode's next save.
