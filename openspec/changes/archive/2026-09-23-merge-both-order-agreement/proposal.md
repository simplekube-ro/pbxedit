# Proposal

## Why

Issue #24, found while applying `merge-both-frameworks-links`: since `v1.1.1`, `both` is offered for a hunk over an array whenever both sides *look* like they only inserted — and that test reads the hunk's counterfactual texts, which zealous trimming can shorten until a side that **reordered** looks like one that inserted. The merge then offers a resolution no text can satisfy and exits `1` on check C, which is the failure of issue #12 from the other end: a decision the user gave, refused.

Measured on `v1.1.2`: base `knownRegions = (en, Base)`, ours `(Base, en)`, theirs `(en, Base, fr)`. The hunk's own texts are base `(Base, )`, ours `(Base, en, )`, theirs `(Base, fr, )` — two insertions — so `both` is offered, and `both` exits `1` with `theirs' order of (en, Base, fr, ) is lost in (Base, en, fr, )`.

Check C is right: it requires each side's retained elements to appear in the result in that side's own order, and where ours and theirs disagree about two elements they both keep, no result can honour both. The offer is what is wrong.

`merge-both-frameworks-links` blocked this for one key only — a Frameworks phase's `files`, where the consequence is link order — with a file-wide subsequence test. Every other admitted array still has the hole.

## What Changes

- `both` is admitted for a shared array leaf only when, **in the three files themselves**, the elements ours and theirs both hold appear in the same relative order in each. Two sides that only insert always agree, so every `both` offered today for insertions is unchanged; a reorder on one side against an insertion on the other, or two sides reordering differently, is refused with `ours` and `theirs`.
- That one rule replaces the Frameworks-only file-wide subsequence test of `merge-both-frameworks-links`: `UnorderedInsertions.insertionsOnly` goes, and with it the asymmetry that change recorded as a trade-off. A Frameworks-phase reorder stays refused, now by the rule every key shares.
- A file-wide *subsequence* test is explicitly not adopted: it would refuse a `both` that works today, where one region of an array inserts while another removes (base `(en, Base, it)`, ours `(de, en, Base)`, theirs `(fr, en, Base, it)` merges to `(de, fr, en, Base)` with every check passing — measured).
- The regression is committed as the three-way fixture `Tests/Fixtures/merge/reordered-array/` and run through the binary.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `merge`: the "Everything else is merged as text" requirement states the order-agreement condition on the three files for every array that may share a hunk's `both`, and drops the Frameworks-only wording; two scenarios are added (a reorder against an insertion keeps `ours` and `theirs`; an insertion against a removal still merges with `both`).

## Non-goals

- Making a reorder mergeable. Where the two sides order the same elements differently, there is no `both`: the user takes `ours` or `theirs` and reorders afterwards.
- Changing check C, the replay, hunk keys or the decisions file shape. C is the authority this change stops contradicting; its rule is untouched.
- Widening or narrowing which attributes may share a `both` (`UnorderedInsertions.keys` is unchanged), or the identity test for two insertions of one object.
- Teaching the analysis what a hunk's real base stretch is. The counterfactual texts stay as they are; this change adds the one whole-file question whose answer the counterfactuals cannot be trusted for.

Checked against `docs/design.md` § Out of scope for v1: nothing here touches it. The change is a correctness fix inside the shipped `merge` capability.

## Impact

- `Sources/PBXOps/Merge/UnorderedInsertions.swift`: `insertionsOnly` and the `PBXFrameworksBuildPhase` branch are replaced by `ordersAgree`, applied to every admitted leaf; `isFrameworksPhase` goes with them.
- Tests: `HunkTests` (the issue's repro refused; the insertion-against-removal case still offers `both`; the Frameworks reorder still refused, by the general rule), `MergeEngineTests` (the repro exits `decisionsNeeded` with two choices, and the insertion-against-removal case merges with `both`), `MergeCommandTests` (the repro through the binary), `MergeFixtureFileTests` plus `Tests/Fixtures/merge/reordered-array/` and a `README.md` row.
- `docs/design.md`: status line, the `merge` Commands row, a Motivation-table row for issue #24; dated notes at D2 of the archived `merge-both-unordered-insertions` design and at D1 of the archived `merge-both-frameworks-links` design.
- No new dependency. Depends on `merge-both-frameworks-links` (merged).
