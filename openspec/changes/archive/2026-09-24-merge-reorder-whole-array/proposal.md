# Proposal

## Why

Issue #32, found while adopting `pbxedit merge` in RandomPlayer's conflict helper: when one side reorders an array and the other inserts into it, the decision `theirs` does not give theirs' array. It drops an element **all three** sides keep, and the merge exits `0` with checks A–F passed.

Measured on `v1.3.0` with the `reordered-array` fixture (issue #24's repro): base `knownRegions = (en, Base)`, ours `(Base, en)`, theirs `(en, Base, fr)`. The line merge reads ours' swap as two changes, a deletion of `en` at the head and an insertion of `en` after `Base`. Only the insertion point conflicts with theirs' `fr`, so the deletion merges cleanly and the one hunk is `en` against `fr`. Decided `theirs`, the result is `(Base, fr)`. Check C passes because it measures the leaf against the hunk's `theirs` counterfactual, which already has the clean deletion applied.

Measuring the neighbourhood turned up a second failure of the same cause. A reorder and an insertion that do **not** overlap line by line (base `(en, Base, de, it, es)`, ours moves `en` to the end, theirs inserts `fr` after `de`) merge with no hunk at all. Check C then refuses the result, `theirs' order of (en, Base, de, fr, it, es, ) is lost in (Base, de, fr, it, es, en, )`, and the command exits `1` with nothing to decide. That is correct but a dead end: where the two sides order the elements they both hold differently, no single text honours both orders, so no merge of that array can pass check C.

## What Changes

- An array both sides change, and whose shared elements ours and theirs order differently, is kept in **one hunk**: every change the line merge finds inside the array's lines joins it. The hunk's `ours` is ours' whole array and its `theirs` is theirs' whole array, so the decision `ours` or `theirs` yields that side's array. The repro decided `theirs` gives `(en, Base, fr)`, and decided `ours` gives `(Base, en)`.
- The non-overlapping reorder and insertion become that one hunk too. They exit `3` offering `ours` and `theirs` instead of exiting `1`.
- Check C gains a rule that holds whatever governs a leaf: an array loses no element that base, ours and theirs all hold, counted. Widening is what makes the repro right; this rule makes sure a line-merge shape nobody has measured cannot bring the defect back as an exit `0`. A new fault seam, `narrowArrayHunks`, turns the widening off so the rule's Red test runs on the issue's own repro.
- The "order agreement" test of issue #24 (`UnorderedInsertions.ordersAgree`) gains an array-level form, so the widening and `both`'s admission ask one question.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `merge`: "Everything else is merged as text" states when an array is kept in one hunk. The reorder-against-insertion scenario gains its results for `ours` and `theirs`, and a non-overlapping scenario is added. "Nothing is written until every check passes" adds the all-sides element rule to check C, with a scenario.

## Non-goals

- Merging a reorder. Where the two sides order shared elements differently, the user still takes `ours` or `theirs` and reorders afterwards. `both` stays refused for such a hunk (issue #24).
- Widening any other hunk. Arrays whose two orders agree (every insertion-only case, issues #13, #17 and #21, and an insertion against a removal) are merged exactly as before, and so is an array only one side changed.
- Changing the order rule of check C, hunk keys' derivation, the decisions file shape or the JSON report. A hunk that is now wider has a different key, like any hunk whose text changes.
- Arrays nested inside arrays, which no `project.pbxproj` writes. Only arrays reached through dictionary keys, the ones check C compares as leaves, are kept whole.

Checked against `docs/design.md` § Out of scope for v1: nothing here touches it. The change is a correctness fix inside the shipped `merge` capability.

## Impact

- `Sources/PBXSyntax/Lines.swift` (new): `SyntaxTree.arrayLines()`, the line span of every array reached by keys. It is generic plist knowledge, with no Xcode in it.
- `Sources/PBXOps/Merge/LineMerge.swift`: `ThreeWay.merge(…, wholeSpans:)` joins every cluster inside a span into one.
- `Sources/PBXOps/Merge/ReorderedArrays.swift` (new): the spans the engine passes, one per array both sides change with disagreeing orders.
- `Sources/PBXOps/Merge/UnorderedInsertions.swift`: `ordersAgree(_:_:)` over two arrays, which the existing object-level form now calls.
- `Sources/PBXOps/Merge/MergeEngine.swift`: passes the spans, unless `MergeFaults.narrowArrayHunks` is set.
- `Sources/PBXOps/Merge/MergeChecks.swift`: `droppedByNoSide` and its use in check C, and the fault seam.
- Tests: `ArrayLinesTests` (new), `LineMergeTests`, `MergeEngineTests`, `MergeCheckTests`, `MergeCommandTests`, and the `reordered-array` fixture decided `theirs` in the merged-project oracle. The fixture's inputs are unchanged, so it is not regenerated. Its `README.md` row states the new results.
- `docs/design.md`: status line, the `merge` Commands row, a Motivation-table row for issue #32, and a dated note at D1 of the archived `merge-both-order-agreement` design, whose migration note described the old narrow hunk.
- No new dependency.
