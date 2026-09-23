# Tasks

Every engine and command test asserts on the model or the written bytes, that the checks pass (A, the rule set relative to the inputs, among them) and that `plutil -lint` accepts the result. Fixture: `Tests/Fixtures/merge/both-frameworks/`.

## 1. `both` for the Frameworks phase's files

- [x] 1.1 Write the failing test for "Different links inserted into one Frameworks phase" at hunk level: `MergeFixture.linking(_:reference:buildFile:in:)` (an SDKROOT framework reference, its build file, a child of `AA0000000000000000000007`, an entry of `CC0000000000000000000002`) and `HunkTests.testInsertionsIntoAFrameworksPhaseOfferBoth`, replacing `testInsertionsIntoAFrameworksPhaseKeepOursAndTheirs`; verify it fails on 1.1.2 (`[ours, theirs]`)
- [x] 1.2 Write the failing tests that must keep refusing: `HunkTests` — a removal beside an insertion, a reorder of base's entry, and the same framework under two IDs, each offering `ours` and `theirs` only; verify they pass before and after 1.3 (they are the guard, red only if 1.3 overreaches)
- [x] 1.3 Implement design D1: drop the `PBXFrameworksBuildPhase` exclusion in `Sources/PBXOps/Merge/UnorderedInsertions.swift`, add `insertionsOnly` on the three files (`AnalysedHunk.Inputs`, threaded from `MergeEngine` and the test helpers) and document why an insertion into an ordered array is admitted; verify 1.1 and 1.2 pass and `HunkTests`, `LineMergeTests` stay green

## 2. The repro end to end

- [x] 2.1 Write the failing test for the second half of "Different links inserted into one Frameworks phase" in `MergeEngineTests`: the issue's repro exits `decisionsNeeded` with four hunks; decided all-`both` it merges with checks A–F passed, both file references, both build files in `CC0000000000000000000002` with ours' entry before theirs', and both children in the `Frameworks` group; verify it fails on 1.1.2 (check A, `M1 … is listed in no build phase`)
- [x] 2.2 Add the `both-frameworks` scenario to `MergeFixtureFileTests.scenarios()` (expected `decisionsNeeded`), regenerate with `PBXEDIT_WRITE_MERGE_FIXTURES=1 swift test --filter MergeFixtureFileTests`, add its row to `Tests/Fixtures/merge/README.md`, and add it to the merged-project oracle test
- [x] 2.3 Write the failing test in `MergeCommandTests`: the repro through the binary — exit `3` listing a `both` choice for the `files` hunk, then all-`both` through `--decisions` exiting `0` with both links in the written file and `pbxedit lint` clean; verify it fails on 1.1.2 (exit `1`, check A)

## 3. Verification and documentation

- [x] 3.1 `swift build` and `swift test` green across all four targets (read the summary, not the exit code; the oracle lane included); `swift test -c release --filter PerformanceTests` green with the figures recorded
- [x] 3.2 Reconcile `docs/design.md` (status line, the `merge` Commands row's admitted key list, a Motivation-table row for issue #21) and add a dated note at D2 of the archived `merge-both-unordered-insertions` design; add § 17 to `TODO.md` with the evidence
