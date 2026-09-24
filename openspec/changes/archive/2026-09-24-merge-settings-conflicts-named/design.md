# Design

## Context

See proposal.md (Why) and issue #28. One function decides what a merge reports per path: `PathComparison.compare` (`Sources/PBXOps/Merge/Replay.swift`), shared by the trial that classifies a unit (merge design D4) and by check E (D9 E). It resolves the attributes of a reference and of its build files three-way — the rule `merge-attribute-conflicts-asked` added for issue #20 — but every other value it compares against theirs' alone:

```swift
differ(.spelling("path"), wanted.path, merged.path)
differ(.spelling("name"), wanted.name, merged.name)
differ(.spelling("sourceTree"), wanted.sourceTree, merged.sourceTree)
differ(.parentGroup, wanted.groupPaths.joined(separator: ", "), merged.groupPaths.joined(separator: ", "))
…
differ(.settings(target: target), want.settings?.description, have.settings?.description, object: have.buildFile)
```

`differ` reports "theirs has X, the merge has Y" and leaves `ours` and `conflicting` at their defaults, which is the issue: measured on the repro (base no `settings`, ours `{COMPILER_FLAGS = "-w"; }`, theirs `{COMPILER_FLAGS = "-Wall"; }` with the row re-created) the residual is `conflicting: false`, `ours: null`, while the `fileEncoding` of #20 in the same shape is `conflicting: true` with both values.

Two facts shape the fix. First, the counterparts the test needs are already in hand: `compare` resolves `before` (base's reference, by the ID theirs kept, else by path) and `held` (ours'), and inside the per-target loop `was` and `ourRow`, for exactly this rule on attributes. Second, the kinds differ in whether a replay can write them: `settings` has no verb (`Replay.run`: "`settings` has no verb: it is compared by the trial, never written"), while spelling and the parent group are what `move` and `add` write.

## Goals / Non-Goals

Goals: one conflict rule for every value the comparison resolves per value, so a consumer can tell a two-sided conflict from a one-sided change and print ours' value, for `settings` as for an attribute; and a stated, measured reason for every kind the rule does not cover.

Non-Goals: see proposal.md. At design level, also: no new residual kind, no new unit choice, no new check, no new fault seam, and no change to what a replay writes or to which unit is replayed, skipped or decided.

## Decisions

### D1. One rule, applied per value, with the counterparts already resolved

`PathComparison.conflicting(base:ours:theirs:)` keeps issue #20's definition — `ours != base && theirs != base && ours != theirs`, an absent value counting as a value — and becomes generic over an `Equatable` value, so the `String?` spellings and the joined group paths go through the same three lines as `PlistValue?` attributes. One rule, one place it can change; a second String-shaped copy would be free to drift.

`settings` is tested inside the per-target loop with `was?.settings` and `ourRow?.settings`, the same counterparts the build-file attributes use, and reported through the existing `conflict(…)` helper so it carries ours' value, theirs', the result's and the flag. As for attributes, a path where ours holds no counterpart row changed nothing about the settings and theirs' value stands, unlabelled.

*Alternative considered:* give `settings` its own three-way `expectation`, suppressing the residual where only ours changed it. Rejected: it would change which residuals exist for a one-sided change, which the issue explicitly leaves alone ("One-sided `settings` changes are unchanged"), and would make a unit that today owes ours-only settings silently keep them.

### D2. Whatever-the-result-holds applies to values no verb writes; spelling and the group are labelled, not invented

For `settings` and the attributes the conflict is a residual **whatever value the result holds**, as #20 decided for attributes: nothing in a replay writes them, so a result that holds theirs' value there holds it by accident — the unmatched-rows path detaches ours' build file and attaches a fresh one — and ours' change was dropped just as silently.

Spelling and the parent group are different in kind: the replay writes them. Measured, base `App/Filtered/F1.swift`, ours `move`d to `App/Views/F1.swift`, theirs to `App/Other/F1.swift`:

| | `path` | parent group | trial | unit |
|---|---|---|---|---|
| base | `F1.swift` | `App/Filtered` | — | — |
| ours | `F1.swift` | `App/Views` | — | — |
| theirs | `F1.swift` | `App/Other` | **no residual** | decision `ours`, `theirs` |

The three group paths differ pairwise, so a whatever-the-result-holds rule would call that a conflict, invent a residual where the replay reproduced theirs exactly, and withdraw the `theirs` choice that applies in full. So for these two kinds the rule *labels* a difference that survives the replay: `theirs != merged` first, then the conflict test decides between a conflicting residual and today's plain one. The value that survives in the result is ours', which is what the label promises to show.

That distinction is the answer to the issue's "or the docs say why it doesn't": the kinds split by whether pbxedit has a verb for the value, which is the same line `docs/design.md` § Out of scope for v1 already draws around residuals.

### D3. Rows and presence stay outside the rule

`.rows` and `.presence` are not a value the user chooses between: they are the unit's own membership question. The unit's choices (`ours`, `theirs` or `theirs-membership`) settle them, and the report already prints base's, ours' and theirs' masked membership for each path of the unit (`ClassifiedUnit.PathStates`), so nothing is hidden. Labelling them would also feed check B, which reads `.rows` and `.presence` as "do not compare this path's rows at all" — a flag there buys nothing and risks the meaning of the kinds it switches on. The specs say this, so the next reader does not have to re-derive it.

### D4. Nothing downstream changes shape

`Residual.Kind` is untouched, so check E keeps matching an owed residual by `(path, kind)` and check B keeps reading `.settings` as "compare this path's rows without settings". A residual, conflicting or not, already makes a unit a decision offering `ours` and `theirs-membership` (`ClassifiedUnit.classify`'s `owing`), and a conflicting `settings` cannot reach the skip: `MaskedRow` carries `settings`, so a unit whose masked membership matches theirs' has the same settings on both sides. The report and JSON need no change either — `ours` and `conflicting` are printed and encoded since #20 — so `schemaVersion` stays `1`.

Check E's Red test needs no new seam: `MergeFaults.ignoreAttributeConflicts` drops every conflicting residual from the classification, so with a `settings` conflict unowed, E fails naming the build file and `settings`.

## Risks / Trade-offs

- **A conflicting `settings` where the result holds theirs' value is a new residual** → That is the point of the rule, and the unit it belongs to was already a decision in every case measured; the residual makes the dropped change visible instead of silent. Whole-suite verification, the fixtures and the release performance run are the evidence that nothing else moved.
- **A spelling or parent-group conflict changes report text and JSON for inputs that merged before** → Only the `ours` and `conflicting` fields of a residual that was already reported; the unit's outcome, choices and keys are untouched, so a `--decisions` file written against `v1.2.0` still applies.
- **`conflicting` becoming generic is a source-compatible but public-ish change** → It is `static` and internal (`static func conflicting`), used only by `compare`; no caller outside the module exists.
- **Performance** → The same comparison plus at most four equality tests per path. The release `PerformanceTests` measurement is part of the verification.

## Migration Plan

None. The fix is reporting fidelity inside one command; no committed fixture regenerates except the new one, and no key changes.

## Open Questions

None.
