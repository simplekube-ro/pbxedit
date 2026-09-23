# Proposal

## Why

Issue #21: when two branches each link a **different** framework or package product into the same target's `PBXFrameworksBuildPhase`, no combination of `pbxedit merge` 1.1.2 decisions keeps both links. That is the everyday "each branch adds a dependency" case, so it always ends in a manual resolution.

The repro (base: `App`'s Frameworks phase linking `Foundation.framework`; ours links `CoreHaptics.framework`, theirs `GameController.framework`, each adding a file reference, a build file, a group child and a phase entry) gives four hunks. Three of them — the build-file objects, the file references, the group's `children` — offer `ours`, `theirs` and `both`. The fourth, the phase's `files`, offers only `ours` or `theirs`, because a Frameworks phase's `files` is link order and `merge-both-unordered-insertions` excluded it by name. So:

- `both` wherever it is offered → exit `1`, check A: `M1 … (GameController.framework) is listed in no build phase`. Nothing is written.
- everything `ours` → exit `0` and theirs' link is dropped; everything `theirs` → exit `0` and ours' is.

Link order only matters *between* entries whose symbols collide. Two independent insertions reorder nothing either side had, so the exclusion is stricter than the meaning it protects.

## What Changes

- A `PBXFrameworksBuildPhase`'s `files` is admitted to the shared-insertion test like the other unordered arrays: `both` is offered when base's array is a subsequence of each side's (both sides only insert), and no element ours inserts has the identity of one theirs inserts — for a `PBXBuildFile`, its `fileRef`/`productRef` identity, so the same framework added under two IDs is still refused. The `both` text keeps ours' insertions before theirs' at the shared position, and each side's own entries in its own order, which is what check C's ordered array rule verifies.
- Removals and reorders in a Frameworks phase keep offering `ours` and `theirs` only: base must be a subsequence of both sides, which a removal or a reorder breaks. For this key the test runs on the three files as well as on the hunk's counterfactuals, because zealous trimming can make a reorder look like an insertion in a counterfactual — measured, and otherwise a `both` that check C refuses with exit `1`. `buildSettings` arrays (`LD_RUNPATH_SEARCH_PATHS`), `buildPhases` and `buildRules` are unchanged — they are not in the admitted key set at all.
- The regression is committed as the three-way fixture `Tests/Fixtures/merge/both-frameworks/` and run through the binary: all-`both` exits `0`, both frameworks are linked, both build files are in the phase, and checks A–F pass.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `merge`: the "Everything else is merged as text" requirement stops excluding a `PBXFrameworksBuildPhase`'s `files` from the insertions that may share a hunk's `both`, and its "an array whose order matters" scenario keeps only the `buildSettings` case; three scenarios are added (the issue's repro offers and honours `both`; a removal or reorder in the phase does not; the same framework under two IDs does not).

## Non-goals

- A `both-theirs-first` choice, or any way to pick the order of the two insertions. Ours-then-theirs is the one order, as for every other array `both` merges; a user who needs the other order edits afterwards or resolves by hand.
- Offering `both` where either side removes or reorders existing entries of a Frameworks phase, or where the two insertions are the same object under two IDs.
- Treating a Frameworks phase's `files` as membership. A build file is membership only in a Sources, Resources or Headers phase (spec: Membership changes are grouped into units), so a Frameworks link stays unmanaged and travels as text; `add`, `remove` and `move` still do not touch one, and this change adds no verb that does.
- Relaxing `buildSettings`, `buildPhases` or `buildRules`, where order is the meaning.
- Any change to the checks, the replay, hunk keys or the decisions file shape.

Checked against `docs/design.md` § Out of scope for v1: nothing here touches it. No operation for linking a framework is added — the change only stops the text merge from forcing a choice between two links each branch already made, and the `merge` entry's residual list and Swift-package exclusions are untouched.

## Impact

- `Sources/PBXOps/Merge/UnorderedInsertions.swift`: the `PBXFrameworksBuildPhase` exclusion goes; the type's documentation says why an insertion into an ordered array is still safe.
- Tests: `HunkTests` (the Frameworks insertion now offers `both`; a removal, a reorder and the same framework twice do not), `MergeEngineTests` (the issue's repro decided all-`both`: exit `0`, both links, checks A–F), `MergeCommandTests` (the repro through the binary), `MergeFixtureFileTests` plus `Tests/Fixtures/merge/both-frameworks/` and a `README.md` row, and the merged-project oracle.
- `docs/design.md`: status line, the `merge` Commands row (the admitted key list), a Motivation-table row for issue #21.
- No new dependency. Depends on `merge-both-unordered-insertions` and `merge-both-multiline-objects` (shipped).
