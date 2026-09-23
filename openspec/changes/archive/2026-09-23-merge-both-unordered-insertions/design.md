# Design

## Context

See proposal.md (Why) and issue #13. `merge-command` design D7 offers `both` when the `both` text parses, `oursTouched` and `theirsTouched` are disjoint, and the `both` text's leaves are base's with each side's changes applied. D8 makes an array one leaf, so two insertions into one array always share a leaf and `both` is never offered, even where `both` is exactly the merge a person would write by hand.

Measured on the issue's repro (base `(en, Base)`, ours `(de, en, Base)`, theirs `(fr, en, Base)`, from `Tests/Fixtures/xcode27/platform-filters-after-xcode27-save.pbxproj`): exit `3`, one hunk with `base` empty, `ours` `de,`, `theirs` `fr,`, governing `EE0000000000000000000001 knownRegions`, choices `ours`, `theirs`.

## Goals / Non-Goals

Goals: `both` for insertions of different elements into an array whose order means nothing; today's choices for everything else.

Non-goals: see proposal.md.

## Decisions

### D1. Shared leaves may be unordered insertions

In `AnalysedHunk.analyse`, let `shared = oursTouched ∩ theirsTouched`. `both` is considered when `shared` is empty (as today) or `UnorderedInsertions.admits(shared, …)`. Then the `both` text is loaded and accepted when:

- every leaf outside `shared` equals base's with ours' then theirs' changes, as today (the maps compared with `shared` removed from both);
- every leaf in `shared` is an array that passes `MergeChecks.arrayProblem(base:ours:theirs:result:unordered: false)`: check C's own array rule, so `both` is offered exactly when check C will accept it;
- the duplicate-key count does not grow, as today.

### D2. Which shared leaves are admitted

`UnorderedInsertions.admits` holds when every leaf `p` in `shared`:

1. is `objects.<id>.<key>`: three components, a direct attribute of an object. That excludes everything under `buildSettings` by construction.
2. has `key` in the list `buildConfigurations`, `children`, `dependencies`, `exceptions`, `fileSystemSynchronizedGroups`, `files`, `knownRegions`, `membershipExceptions`, `packageProductDependencies`, `packageReferences`, `targets`, and is not `files` of an object whose base `isa` is `PBXFrameworksBuildPhase`. `buildPhases` and `buildRules` are absent from the list, so they are excluded. *(2026-09-23, change `merge-both-frameworks-links`, issue #21: the exclusion of a `PBXFrameworksBuildPhase`'s `files` is gone. Its order is link order, but condition 3 means both sides only inserted, so nothing base held is reordered; the phase's `files` is admitted only when condition 3 also holds in the three *files*, not just in this hunk's counterfactuals, which zealous trimming can make a reorder look like an insertion in — see that change's design D1.)*
3. is an array in base, ours and theirs, with base's a subsequence of each side's. The leaf differs from base on both sides, so each side only inserts. *(2026-09-23, change `merge-both-order-agreement`, issue #24: read on the hunk's counterfactual texts, which zealous trimming can shorten until a side that reordered looks like one that inserted. A fourth condition now asks the three files themselves that ours and theirs order what they both hold the same way; see that change's design D1.)*
4. has no element in ours' additions (ours − base, as a multiset) with the identity of an element in theirs' additions.

*Identity* of an element: a string that names no object in that side's `objects` is itself. A string that names an object is `isa` plus its identifying fields, with any field that names an object replaced by that object's identity (depth-limited, so a cycle ends). The identifying fields:

| `isa` | fields |
|---|---|
| `XCRemoteSwiftPackageReference` | `repositoryURL` |
| `XCLocalSwiftPackageReference` | `relativePath` |
| `XCSwiftPackageProductDependency` | `package`, `productName` |
| `PBXBuildFile` | `fileRef`, `productRef` |
| `PBXTargetDependency` | `target`, `targetProxy`, `productRef` |
| `PBXContainerItemProxy` | `containerPortal`, `proxyType`, `remoteGlobalIDString`, `remoteInfo` |
| `XCBuildConfiguration` | `name` |
| `PBXFileReference`, `PBXGroup`, `PBXVariantGroup`, `XCVersionGroup`, `PBXReferenceProxy`, `PBXFileSystemSynchronizedRootGroup` | `sourceTree`, `path`, `name` |
| `PBXFileSystemSynchronizedBuildFileExceptionSet` | `target` |
| `PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet` | `buildPhase` |
| `PBXNativeTarget`, `PBXAggregateTarget`, `PBXLegacyTarget` | `name` |
| any other | the whole object |

Ours' elements are looked up in ours' counterfactual, which is ours' own text. Theirs' counterfactual resolves every *other* hunk `ours`, so an object theirs added in another hunk (the package object beside its `packageReferences` entry) is missing there; theirs' elements are looked up in the text with every hunk `theirs`, loaded at most once per run. An element both sides insert under one ID is caught by the same test (equal strings), so `both` never duplicates an element.

*Alternative considered:* rely on check A to catch a duplicate package after `both`. Rejected: A has no rule for packages, and offering a choice that a later check refuses is the trap the issue describes. Rule 4 of the issue asks for the identity test before offering.

*Alternative considered:* compare whole objects for identity. Rejected: the same package added on two branches differs in its `requirement` as often as not, and is still one package.

### D3. Where it lives

The list, the insertion test and identity are in a new `Sources/PBXOps/Merge/UnorderedInsertions.swift`; `analyse` calls it. `MergeChecks.arrayProblem` is reused unchanged. Check C needs nothing new: one hunk decided `both` over an array already falls to its three-way array rule, and several hunks over one array, some decided `both`, already compose through `resolvedValue` (change `merge-accounting-shared-leaves`, D1).

### D4. Tests

- `HunkTests`: the repro offers `both`, whose text has `(de, fr, en, Base)`; two packages with different URLs offer `both`; two insertions into `LD_RUNPATH_SEARCH_PATHS`, two into a Frameworks phase's `files`, the same package under two IDs, and a removal on one side offer `ours` and `theirs` only.
- `MergeEngineTests`: the repro decided `both` merges with checks A–F passing and `plutil -lint` clean; both ends of `knownRegions` decided `both`/`both` and `both`/`theirs` merge.
- `MergeCommandTests`: the repro through the binary on `Tests/Fixtures/merge/both-regions/`, `both` offered in the JSON and exit `0` with `(de, fr, en, Base)` written.

## Risks / Trade-offs

- [`both` on the array is not enough for a multi-line object both sides add at one place] → Two new `XCRemoteSwiftPackageReference` objects inserted after the same object form their own hunk, which zdiff3 trimming cuts inside the objects (their common tail becomes stable context), so its `both` text does not parse and only `ours`, `theirs` are offered there. That is `v1.1.0` behaviour and outside this change; a follow-up issue tracks it. Single-line elements (`knownRegions`) and one-line objects (build files, file references) are unaffected. *(2026-09-23: that follow-up is issue #17, fixed by change `merge-both-multiline-objects` — the `both` text for such a hunk is the untrimmed union of the two sides, and the hunk's base counterfactual is built from its whole stretch, which is what left the hunk with no base to compare against here.)*

- [An array on the list whose order does matter somewhere] → The list is the issue's, taken from the downstream helper where it is in use. A wrong entry only offers a choice; nothing merges without a decision, and C still checks each side's order is kept.
- [An unknown `isa` compared as the whole object] → Two objects that differ only in a non-identifying field count as different and `both` is offered. The worst case is a duplicate the user chose; no worse than `v1.1.0`, where every choice lost one side.
