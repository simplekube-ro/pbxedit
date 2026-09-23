# Proposal

## Why

Issue #20: `pbxedit merge` 1.1.2 loses one side's attribute change silently. When theirs changes a file's membership and both sides set the same reference or build-file attribute to different values, the merge keeps ours' value, asks nothing, lists no residual, owes nothing, and passes all six checks with exit `0`. The issue's repro: a file reference `F` with no `fileEncoding` in base, `fileEncoding = 4` in ours, `fileEncoding = 10` plus a platform filter in theirs; the result holds `4` and `platformFilter = ios`, and nobody is told that `10` was dropped. In the variant where both sides re-filter, the unit *is* a decision, but deciding `theirs` still writes ours' `4`: the user's answer is only half applied.

The cause is one line of `PathComparison.expectation` (`Sources/PBXOps/Merge/Replay.swift`, merge design D9 E): "Where both changed it, either side's value is accepted: the one the result has." A leaf both sides changed differently therefore produces no residual, so the unit stays `replayed` (or keeps the plain `theirs` choice), nothing is owed, and check E — which shares that comparison — has nothing to fail on. Check C cannot catch it either: the unit's paths are neutralised out of base and theirs before the text merge, so the attribute's leaf is in neither copy C compares.

Every other conflicting value in the file reaches the user as a hunk. A membership change next to it should not make one disappear.

## What Changes

- The per-path comparison treats an attribute base, ours and theirs do not agree on — ours differs from base, theirs differs from base, and the two differ from each other, an absent value counting as a value — as a **conflicting** difference, whatever value the result holds. It covers every attribute of a unit's file references and of the build files in its rows — the two the comparison resolves three-way today. A build file's `settings` is already compared against theirs' directly, so a conflict there is already a residual and stays one.
- A conflicting difference is a residual, so the unit becomes a decision offering `ours` and `theirs-membership`: the merge exits `3` with a question naming the attribute and both sides' values, or, decided `theirs-membership`, replays theirs' membership and lists the attribute as owed. No unit is replayed or skipped while such an attribute is unaccounted for — including a unit that would be skipped because both sides made the same membership change.
- Check E, which runs the same comparison over every replayed path, therefore fails when a conflicting attribute is not owed. A new fault seam (`MergeFaults.ignoreAttributeConflicts`, reachable only through `@testable import`) drops the conflict from the classification for the test, which proves E bites.
- `Residual` carries the conflict: ours' value beside theirs' and a flag, so the text report prints "both sides changed `fileEncoding`: ours `4`, theirs `10`" and the JSON residual objects gain `ours` and `conflicting`. The addition is additive; `schemaVersion` stays `1`.
- The regression is committed as the three-way fixture `Tests/Fixtures/merge/attribute-conflict/` and run through the binary for both of the issue's repros.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `merge`: "Each unit is replayed, skipped or decided" states that a conflicting attribute change makes a unit a decision whatever its membership; "Replay reproduces theirs exactly or says what it cannot" states the three-way rule for an attribute and that a conflict is a residual whichever value the result holds; "Nothing is written until every check passes" names a conflicting change among the differences check E accounts for, with the fault-seam scenario.

## Non-goals

- Writing theirs' attribute value. A replay changes membership only through the `add`, `remove` and `move` planners (design D4); an attribute pbxedit has no verb for stays ours', and the conflict is owed rather than resolved. A `theirs-attributes` choice would need a writer for every attribute and is not in this change.
- Making a conflicting attribute a text *hunk*. The unit's paths are neutralised before the line merge by design (D3); un-neutralising an attribute's lines would put membership back into the text merge, which check F exists to forbid.
- Any change to checks A, B, C, D or F, to the line merge, to hunk keys or to the decisions file shape. A unit key already derives from the unit's paths and its three versions' membership, so keys written against `v1.1.2` for units without a conflict are unchanged.
- Widening what counts as membership, or reporting attribute conflicts for references that are not part of any unit — those travel as text and reach the user as hunks already.
- A version bump. The release that carries this fix also carries issue #21.

Checked against `docs/design.md` § Out of scope for v1: nothing here touches it. The change is a correctness fix inside the shipped `merge` capability.

## Impact

- `Sources/PBXOps/Merge/Replay.swift`: `Residual` gains `ours` and `conflicting` and a description for a conflict; `PathComparison.compare` emits a conflicting residual instead of accepting the result's value, and gains `conflicts(paths:base:ours:theirs:)` — the same comparison against ours, filtered.
- `Sources/PBXOps/Merge/Units.swift`: `ClassifiedUnit.classify` looks for conflicts before the skip, so a unit whose membership matches theirs is still a decision when an attribute conflicts; `ignoringConflicts` carries the fault.
- `Sources/PBXOps/Merge/MergeChecks.swift`: `MergeFaults.ignoreAttributeConflicts`; check E and check B are otherwise unchanged (an owed conflict is neither `settings`, `rows` nor `presence`, so B compares rows as before).
- `Sources/pbxedit/MergeReport.swift`: the owed and residual lines print both sides' values; `ResidualJSON` gains `ours` and `conflicting`.
- Tests: `ResidualTests` (the comparison, both repros and the disjoint control), `MergeEngineTests` (exit `3`, the choices, `theirs-membership` and the skipped-unit case), `MergeCheckTests` (the fault seam for E), `MergeCommandTests` (the issue's two repros through the binary, text and `--json`), `MergeFixtureFileTests` plus `Tests/Fixtures/merge/attribute-conflict/`.
- `docs/design.md`: status line, a Motivation-table row for issue #20, and a dated note at D4/D9 E of the archived `merge-command` design.
- No new dependency. No version bump. Depends on `merge-command` (shipped).
