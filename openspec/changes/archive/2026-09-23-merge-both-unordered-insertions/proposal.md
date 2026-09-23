# Proposal

## Why

Issue #13: `pbxedit merge` 1.1.0 offers `both` only when the leaves ours and theirs change are disjoint, and a whole array is one leaf. When both sides insert *different* elements into the same unordered array (two new `knownRegions`, two new `packageReferences`, two new group `children`), the hunk offers only `ours` or `theirs`, and whichever is chosen loses one side's addition. Base `(en, Base)`, ours `(de, en, Base)`, theirs `(fr, en, Base)` exits `3` with one hunk over `EE0000000000000000000001 knownRegions` and choices `ours`, `theirs`: every allowed decision drops `de` or `fr`. The downstream helper `pbxedit merge` is meant to replace already merges this shape; without it upstream, adopting `pbxedit merge` loses behaviour users rely on.

## What Changes

- A hunk also offers `both` (ours' lines, then theirs') when the leaves both sides change are all **insertions into an unordered array**:
  1. each such leaf is an array in base, ours and theirs, and base's array is a subsequence of each side's (no removal, no reorder of a shared element);
  2. the array is a direct attribute of an object whose order carries no meaning: `buildConfigurations`, `children`, `dependencies`, `exceptions`, `fileSystemSynchronizedGroups`, `files` (except a `PBXFrameworksBuildPhase`'s, which is the link order), `knownRegions`, `membershipExceptions`, `packageProductDependencies`, `packageReferences`, `targets`;
  3. no element ours inserts has the identity of one theirs inserts: the same string, or objects with the same `isa` and identifying fields (the same package under two IDs), which would leave a duplicate;
  4. the `both` text parses, its other leaves are base's with each side's changes, as today, and each shared array passes check C's array rule (ours' elements plus theirs' additions, each side's order kept as a subsequence).
- Order-carrying arrays keep today's choices: anything under `buildSettings` (`LD_RUNPATH_SEARCH_PATHS`), `buildPhases`, `buildRules`, a Frameworks phase's `files`. So do a scalar conflict and the same object inserted under two IDs.
- Hunk keys, the decisions file and checks A–F are unchanged. A decisions file written against `v1.1.0` still applies: `both` is only added to the choices.

## Capabilities

### New Capabilities
(none)

### Modified Capabilities
- `merge`: the "Everything else is merged as text" requirement states when `both` is offered for insertions into one unordered array, with scenarios for the issue's repro and the four shapes that keep today's choices.

## Non-goals

- Offering `both` for an array whose order matters, for removals or reorders, or for arrays that are not a direct attribute of an object (anything under `buildSettings`).
- Merging such arrays without a decision. The hunk is still reported and exit `3` still asks; `both` is only offered.
- Changing how hunks are formed or keyed, check C, or the decisions file.
- Any change to membership units or the replay.

Checked against `docs/design.md` § Out of scope for v1: nothing here touches it. `packageReferences` is merged as text, as every non-membership attribute already is; no verb for packages is added.

## Impact

- `Sources/PBXOps/Merge/Hunks.swift`: `AnalysedHunk.analyse` admits shared leaves that `UnorderedInsertions` accepts. New `Sources/PBXOps/Merge/UnorderedInsertions.swift`: the array list, the insertion test and element identity.
- Tests: `HunkTests` (the repro and the four excluded shapes), `MergeEngineTests` (the repro through the engine with checks A–F; both ends of one array decided `both`), `MergeCommandTests` (the repro through the binary), a three-way fixture `Tests/Fixtures/merge/both-regions/`.
- `docs/design.md`: status line, the Commands-table `merge` row, a Motivation-table row for issue #13. The archived `merge-command` design gets a dated note at D7.
- No new dependency. The release is `v1.1.1`, after merge, per `docs/RELEASING.md`.
