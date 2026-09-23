# Design

## Context

See proposal.md (Why) and issue #20. `merge-command` design D4 classifies a unit by replaying it against ours in memory and comparing the result with theirs; D9 E runs the same comparison on the real result. Both go through `PathComparison.compare` (`Sources/PBXOps/Merge/Replay.swift`), which compares spelling, parent group and rows against theirs' and resolves every other attribute of the reference and of its build files three-way, in `expectation`:

```swift
let theirsChanged = theirs != base
let oursChanged = ours != base
if theirsChanged, oursChanged, merged == ours { return ours }
return theirsChanged ? theirs : ours
```

The third line is the defect: where both sides changed an attribute, whichever value the result happens to hold is declared correct. Measured on the issue's repro (base `Tests/Fixtures/xcode27/platform-filters-after-xcode27-save.pbxproj`, `App/Filtered/F1.swift`, reference `AA0000000000000000000260`):

| | `fileEncoding` | membership | 1.1.2 outcome |
|---|---|---|---|
| base | absent | `App`, filters `ios` | — |
| ours | `4` | unchanged | — |
| theirs | `10` | re-filtered `ios`, `macos` | unit `replayed`, no residual, exit `0`, result `fileEncoding = 4` |

`expectation` returns ours' `4` because the replay keeps ours' reference, so no residual exists, the unit needs no decision, and check E — the same comparison — finds nothing. The leaf is invisible to check C as well: `MergeEngine` neutralises every unit path out of base and theirs before the text merge, so `AA0000000000000000000260` has no `fileEncoding` leaf in either copy C compares.

## Goals / Non-Goals

Goals: a conflicting attribute change always reaches the user, through the machinery that already exists for what a replay cannot reproduce (residual → decision → owed), with check E enforcing it.

Non-goals: see proposal.md. At design level, also: no new unit choice, no new check, and no change to what a replay writes.

## Decisions

### D1. A conflict is a difference, not a preference

`expectation` loses its third line. A key is *conflicting* when `ours != base && theirs != base && ours != theirs`, comparing `PlistValue?` so that an absent value is a value — the issue's repro has no `fileEncoding` in base at all, and a side that drops an attribute base had has changed it as surely as one that rewrites it.

A conflicting key is a residual **whatever value the result holds**. Accepting theirs' value there would be as wrong as accepting ours': both sides changed the attribute, and whichever value survives, the other side's change was dropped without being named. The expected value the residual reports is theirs' (it is the side the comparison exists to reproduce), and the residual carries ours' beside it so the report can show the user what they are choosing between.

Where ours holds no counterpart object at all, ours changed nothing about it and theirs' value stands, exactly as today; a key both sides changed to the *same* value is not conflicting and stays settled.

### D2. The conflict rides on `Residual`, not on a new kind

`Residual` gains `ours: String?` and `conflicting: Bool`, both defaulted, and `description` branches on the flag:

```
App/Filtered/F1.swift (AA0000000000000000000260): both sides changed fileEncoding: ours 4, theirs 10
```

The `Kind` stays `.attribute(key)` / `.buildFileAttribute(target:key:)`. That matters: check E matches an owed residual by `(path, kind)`, and check B switches over the kind to decide how to compare rows. Two new kinds would have to be threaded through both, and a conflict is the same *subject* as a plain attribute residual — the same key of the same object — differing only in why it cannot be reproduced. One `(path, kind)` can never be both at once, so the owed key stays unambiguous.

`MergeRenderer` prints the residual's own description for a unit's residuals, so the unit report needs no change; the `owed:` line, which composes its own text, gains the conflicting form. `ResidualJSON` gains `ours` and `conflicting`, always present (`null` for a value that is absent), which keeps the spec's "absent values as `null`, never omitted" and is additive: `schemaVersion` stays `1`.

*Alternative considered:* a `Residual.Kind.conflict(String)` case. Rejected for the threading above, and because the text report would then say "conflict fileEncoding is 4, theirs 10", which reads as a kind of object rather than as a question.

### D3. A conflict makes the unit a decision, skipped or not

For a unit the trial already runs on, nothing more is needed: the conflicting residual comes back from `Trial.run`, and `ClassifiedUnit.classify`'s existing `case .replayed(let residuals)` turns any non-empty residual list into a decision offering `ours` and `theirs-membership`. That covers both of the issue's repros, including the one where 1.1.2 offered a plain `theirs`: the choice becomes `theirs-membership`, whose contract is to replay what it can and owe the rest, so the user's answer is applied in full or named as owed — never half applied in silence.

The skip is decided *before* the trial, and its comparison is masked membership only, so a unit where both sides made the same membership change but set one attribute differently would still be skipped in silence. `classify` therefore asks for conflicts before returning `.skipped`:

```swift
if states.allSatisfy({ $0.ours == $0.theirs }) {
    let conflicts = ignoringConflicts ? [] : PathComparison.conflicts(paths: unit.paths, base: base, ours: oursSnapshot, theirs: theirs)
    ...  // skipped when empty, else a decision offering ours and theirs-membership
}
```

`PathComparison.conflicts` is `compare` against ours' own snapshot, filtered to the conflicting residuals: conflict is a property of base, ours and theirs alone, so the result argument cannot change the answer, and running the one comparison keeps a second implementation of the rule from drifting. It needs no replay, so the skipped path stays cheap — the trial still runs only for units that are not skipped.

For such a unit `theirs-membership` replays a membership ours already holds (no change) and owes the attribute. That is the honest report: the membership needed nothing, the attribute needs the user.

### D4. Check E enforces it, and a fault seam proves it

Check E needs no new rule — it runs `PathComparison.compare` over every replayed path and fails on any difference not listed as owed, so a conflicting attribute fails it unless the decision that produced it owed it. What the change owes is the Red test for that: `MergeFaults.ignoreAttributeConflicts` drops conflicts in `classify` (the 1.1.2 classification) and nowhere else, so the unit is `replayed`, `owed` is empty, and check E fails naming `AA0000000000000000000260` and `fileEncoding`, exit `1`, nothing written. Putting the fault in the classification rather than in the comparison is the point: a fault in the comparison would blind the check too and prove nothing.

## Risks / Trade-offs

- **More questions than 1.1.2.** Any merge where both sides changed one attribute of one membership-touched file now exits `3` instead of silently keeping ours'. That is the issue's request, and the alternative is a wrong file. A side that re-created a reference and thereby dropped an attribute ours changed is a conflict by D1's rule and will be asked about; the answer (`ours`, or `theirs-membership` with the attribute owed) is a sentence in a decisions file, and the loss it prevents is silent.
- **`Residual` is public API.** The two new properties are defaulted, so every existing initialiser call still compiles; `Equatable` now distinguishes a conflict from a plain residual with the same kind, which no test depends on.
- **Performance.** One extra comparison per skipped unit, over the unit's paths only, with no replay. The release `PerformanceTests` measurement is part of the verification.

## Migration Plan

None. The fix is behavioural inside one command; no fixture regenerates except the new one, and decisions files written for inputs without a conflict keep their keys.

## Open Questions

None.
