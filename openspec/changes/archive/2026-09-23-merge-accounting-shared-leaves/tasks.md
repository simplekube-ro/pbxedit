# Tasks

Every engine and command test asserts on the model or the written bytes, that the checks (A, the rule set relative to the inputs, among them) pass, and that `plutil -lint` accepts the result. Fixture: `Tests/Fixtures/merge/shared-array/`.

## 1. Accounting over a shared leaf

- [x] 1.1 Write the failing tests for "Two decided hunks govern one array": `MergeFixture.knownRegions` (a text edit, one element per line), `MergeEngineTests.sharedArraySides()` and `testTwoDecidedHunksGoverningOneArrayAcceptEveryCombination` (all four head/tail combinations merge, `knownRegions` as the spec says); verify it fails on `theirs`/`ours` with the issue's message
- [x] 1.2 Write the failing tests for "A wrong result over a shared array still fails": `MergeCheckTests.testTwoDecidedHunksOverOneArrayExpectBothDecisions` (four wrong results fail naming `EE0000000000000000000001 knownRegions`, `lint` clean on each; the reorder passes only under `multisetArrays`), `testABothHunkSharingAnArrayWithADecidedOneCounts`, `testTheSkipTextMergeFaultFailsAccountingOnASharedArray`; verify they fail on the old check (it accepts `(de, en, Base, es)` for `theirs`/`theirs`)
- [x] 1.3 Implement design D1 in `MergeChecks.accounting` (`composedProblem`, `decidedBuild`, `DecidedHunk.value(at:)`/`resolvedValue(at:)`); verify 1.1 and 1.2 pass and the rest of `MergeCheckTests` and `MergeEngineTests` stay green

## 2. The regression through the binary

- [x] 2.1 Add the `shared-array` scenario to `MergeFixtureFileTests.scenarios()` (expected `decisionsNeeded`), regenerate with `PBXEDIT_WRITE_MERGE_FIXTURES=1`, and add its row to `Tests/Fixtures/merge/README.md`
- [x] 2.2 Write `MergeCommandTests.testTwoDecidedHunksOverOneArray`: the issue's three rows through the binary, exit `0` and the written `knownRegions`; verify it fails without 1.3 (`theirs`/`theirs` and `theirs`/`ours` exit `1`) and passes with it

## 3. Verification and documentation

- [x] 3.1 `swift build` and `swift test` green across all four targets (read the summary); `swift test -c release --filter PerformanceTests` green
- [x] 3.2 Reconcile `docs/design.md` (status line; the Motivation-table row for issue #12) and add a dated note at D9 C of the archived `merge-command` design; add § 13 to `TODO.md` with the evidence
