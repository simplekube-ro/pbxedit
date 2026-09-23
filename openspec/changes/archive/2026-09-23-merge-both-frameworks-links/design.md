# Design

## Context

See proposal.md (Why) and issue #21. `merge-both-unordered-insertions` design D2 relaxed `both`'s disjointness test for one shape: leaves both sides change that are insertions into an array whose order carries no meaning. `UnorderedInsertions.keys` lists the admitted attribute names, and `admits` excludes one case by `isa`:

```swift
if key == "files", case .string(let isa)? = baseObjects?[id.rawValue]?["isa"], isa == "PBXFrameworksBuildPhase" { return false }
```

Measured on the issue's repro through the engine (base `Tests/Fixtures/xcode27/platform-filters-after-xcode27-save.pbxproj`; each side adds an SDKROOT framework reference, a build file, a child of the `Frameworks` group `AA0000000000000000000007` and an entry of `App`'s Frameworks phase `CC0000000000000000000002`):

| hunk | governs | 1.1.2 choices |
|---|---|---|
| 1 | the two `PBXBuildFile` objects' `isa`, `fileRef` | `ours`, `theirs`, `both` |
| 2 | the two `PBXFileReference` objects' five keys each | `ours`, `theirs`, `both` |
| 3 | `CC0000000000000000000002 files` | **`ours`, `theirs`** |
| 4 | `AA0000000000000000000007 children` | `ours`, `theirs`, `both` |

`both` wherever offered fails check A with `M1 AC0000000000000000000011: build file … (System/Library/Frameworks/GameController.framework) is listed in no build phase`, and all-`ours` writes a project in which ours' framework is linked and theirs' is not. Both measurements are the issue's, reproduced.

## Goals / Non-Goals

Goals: `both` for the one hunk that lacks it, under exactly the test the other three passed — and, because this array's order is meaning, never a `both` the checks would refuse.

Non-goals: see proposal.md. At design level, also: no new choice, no new key in `UnorderedInsertions.keys` (`files` is already there), and no change to `admits`' insertion and identity conditions.

## Decisions

### D1. An insertion is safe in an ordered array too

The exclusion goes. What it protected is real — a Frameworks phase's `files` is link order, and the static linker resolves duplicate symbols by it — but it protected it against the wrong thing. `admits` already requires that base's array be a subsequence of *each* side's, so both sides only inserted: neither moved nor dropped an entry, and the relative order of everything base held is the same in ours, in theirs and in the `both` text. Two insertions can only collide with each other, and two entries that resolve the same symbols are the same dependency added twice, which the identity test below already refuses.

So the rule becomes: for an array in `keys`, `both` is admitted when both sides only insert and no element ours inserts has the identity of one theirs inserts. `PBXBuildFile`'s identifying fields are `fileRef` and `productRef`, and `identity(of:)` resolves a field that names an object to that object's own identity, so two build files pointing at one framework — the same `sourceTree`, `path` and `name` — are one identity under two IDs and keep offering `ours` and `theirs` only. That is the case worth refusing: the same framework linked twice would be a duplicate-symbol build failure, and the file it names is what decides, not the build file's ID.

The order the `both` text produces is ours' insertions before theirs' at the shared position, each side's own entries in its own order — the same as for every other array `both` merges, and what `AnalysedHunk` already verifies with `MergeChecks.arrayProblem(…, unordered: false)` before offering the choice. No check changes: check C runs that same ordered rule over the result.

**Found while applying.** The subsequence test reads the *hunk's counterfactual* texts, and zealous trimming can shorten the base stretch so that a side which reordered looks like one that inserted. Measured: base links `Foundation` then `CoreHaptics`, ours swaps the two, theirs adds `GameController`; the hunk's counterfactual arrays are `(CoreHaptics)`, `(CoreHaptics, Foundation)` and `(CoreHaptics, GameController)` — two insertions — so the exclusion's removal alone offers `both`, and the merge then exits `1` on check C: `theirs' order of (Foundation, CoreHaptics, GameController) is lost`. Offering a choice that the checks refuse is the defect of issue #12, and for link order it is the one shape that must not slip through.

*(2026-09-23, change `merge-both-order-agreement`, issue #24: this file-wide test was replaced, two commits later, by the order-agreement rule that every admitted key shares — `insertionsOnly` and `isFrameworksPhase` are gone, and the asymmetry below with them; `Inputs` became `Sides`, ours and theirs without the base the subsequence test needed.)* So for this key, and only for it, the insertion test also runs on the three *files* the merge was built from: `UnorderedInsertions.insertionsOnly` requires base's own `files` array to be a subsequence of ours' and of theirs'. `AnalysedHunk.analyse` therefore takes an `Inputs` (the base, ours and theirs the line merge read — the neutralised base and theirs in the engine, where neutralisation never touches an unmanaged Frameworks link). The counterfactual test stays as it is for every other key: requiring the file-wide test there would refuse a `both` that works today, where one hunk of an array inserts and another removes, each decided on its own.

The same counterfactual blind spot can offer a `both` that check C then refuses for the arrays admitted since `v1.1.1` — `knownRegions` with a reorder on one side against an insertion on the other, measured on `v1.1.2`. That is a defect of its own, older and wider than this change, and it belongs to a change of its own rather than being folded in here; nothing in this change makes it worse, and the file-wide test above is the shape a fix for it would generalise.

*Alternative considered:* admit it only when the phase's `files` entries name frameworks in different SDKs, or only when neither side's insertion is a static library. Rejected: pbxedit has no model of what a link resolves, and the test would refuse the ordinary case (two `.framework`s) on a guess about a rare one (two static libraries whose symbols overlap) that a user resolving by hand would have to think about anyway — and which `ours`/`theirs` still allow them to.

*Alternative considered:* a `both-theirs-first` choice, as the issue offers as a fallback. Rejected: it doubles the choice list for every array `both` already merges, and a decisions file that says `both-theirs-first` for one hunk and `both` for another is harder to read than an edit after the merge. If ordering between two new links ever matters to someone, that is the release to reconsider it in.

### D2. Nothing else moves

`UnorderedInsertions.keys` is unchanged: `buildSettings` arrays are never admitted (a hunk leaf must be a direct attribute of an object, three path components, so `buildSettings.LD_RUNPATH_SEARCH_PATHS` is out by shape), and `buildPhases` and `buildRules` are not in the set. The spec sentence that named a Frameworks phase's `files` beside them loses that clause; the `LD_RUNPATH_SEARCH_PATHS` half of its scenario stays, and the Frameworks half becomes the new `both` scenario.

The type keeps its name. Its documentation gains the reason an insertion into an ordered array is admitted, so the next reader does not restore the exclusion.

## Risks / Trade-offs

- **Two links whose order matters.** Where both new entries export the same symbol, ours-then-theirs is a choice pbxedit makes rather than the user. The user can still take `ours` or `theirs` and add the other link with Xcode, and the same risk already exists for the group `children` and package lists `both` merges today. The static case (two libraries with overlapping symbols added on two branches) is rare and is a build failure the build surfaces, not a silent wrong result.
- **Two tests instead of one.** A Frameworks phase's `files` is now tested twice, in the hunk and in the files. It is the only key with an asymmetric rule, which a reader could take for an accident; the `insertionsOnly` helper and its comment say why, and the reorder test in `HunkTests` fails if it is removed.
- **`files` of a phase kind that is membership.** A Sources, Resources or Headers phase's `files` entries for managed paths never reach a hunk: their units are neutralised out of base and theirs, and check F fails if any managed membership reaches the merge as bytes. So admitting `files` for every phase kind cannot smuggle membership past the replay — F is the seam that proves it, and it is unchanged.

## Migration Plan

None. A hunk that offered `ours`, `theirs` now offers `both` as well; its key is unchanged (a key is its three texts and the objects it governs, not its choices), so decisions files written against `v1.1.2` keep working.

## Open Questions

None.
