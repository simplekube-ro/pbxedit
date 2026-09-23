# Proposal

## Why

Issue #12: `pbxedit merge` 1.1.0 exits `1` on check C (accounting) for a valid resolution when two decided hunks govern one leaf. The shape is ordinary: both sides change both ends of `knownRegions` (base `(en, Base)`, ours `(de, en, Base, it)`, theirs `(fr, en, Base, es)`), the line merge gives two hunks, one for the head and one for the tail, and each governs `<project> knownRegions`. Decided `ours`/`theirs` the merge passes; `theirs`/`theirs` and `theirs`/`ours` are refused. Both are valid resolutions, and nothing is written, so the user is sent to a manual fallback for an answer they gave correctly.

The cause is in `MergeChecks.accounting`: a governed leaf's expected value is the **last** deciding hunk's own counterfactual, the text in which every *other* hunk is resolved `ours`. That text does not contain an earlier hunk's decision. The same flaw also let a wrong result through: decided `theirs`/`theirs`, the check accepted `(de, en, Base, es)`, which drops theirs' `fr` for ours' `de`.

## What Changes

- Check C, for a leaf that more than one hunk governs and at least one of them is decided `ours` or `theirs`, expects the effect of **every** governing hunk's choice at once. Each hunk's counterfactual shows what its choice alone does to the leaf, measured against the build with every hunk `ours`. An array must hold that build's elements plus every hunk's additions minus every hunk's removals, with each counterfactual's retained elements in its order: C's array rule, with the all-`ours` build as the base and one side per hunk. A `both` hunk among them counts with its `both` counterfactual.
- A leaf that is not an array in all of those texts expects the one value the hunks change it to, or, if they change it to several, its value in the text with every decision applied.
- Unchanged: a leaf one decided hunk governs still expects that hunk's counterfactual value exactly; a leaf governed only by `both` hunks still follows C's ordinary three-way rule.
- The regression is committed as the three-way fixture `Tests/Fixtures/merge/shared-array/` and run through the binary for the issue's three rows.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `merge`: the "Nothing is written until every check passes" requirement states how check C accounts for a leaf that several decided hunks govern, with two scenarios: every combination of decisions passes, and a wrong result still fails.

## Non-goals

- Changing how hunks are formed or keyed. Two hunks over one array stay two decisions; merging them into one hunk would change the keys of decisions files already written against `v1.1.0`.
- Offering `both` for a hunk over an array. `both` needs disjoint touched sets, and an array is one leaf.
- Any change to checks A, B, D, E or F, to the replay or to the decisions file.
- A version bump. The release that carries this fix is a follow-up issue.

Checked against `docs/design.md` § Out of scope for v1: nothing here touches it. The change is a correctness fix inside the shipped `merge` capability.

## Impact

- `Sources/PBXOps/Merge/MergeChecks.swift`: `accounting` collects every hunk governing a leaf, and a new `composedProblem` checks a leaf that several govern. `DecidedHunk` gains `value(at:)` and `resolvedValue(at:)`. The public signature of `accounting` is unchanged.
- Tests: `MergeEngineTests` (every combination through the engine), `MergeCheckTests` (wrong results on synthesised merges, a `both` hunk sharing the array, the `skipTextMerge` fault through the engine), `MergeCommandTests` (the issue's three rows through the binary), `MergeFixture.knownRegions`, `MergeFixtureFileTests` (the new `shared-array` scenario, with a `README.md` row).
- `docs/design.md`: status line, and a Motivation-table row for issue #12. The archived `merge-command` design gets a dated note at D9 C.
- No new dependency. No version bump. Depends on `merge-command` (shipped).
