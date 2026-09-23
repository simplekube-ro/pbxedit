# Tasks

Every engine and command test asserts on the model or the written bytes, that the checks pass (A, the rule set relative to the inputs, among them) and that `plutil -lint` accepts the result. Fixture: `Tests/Fixtures/merge/attribute-conflict/`.

## 1. A conflicting attribute is a residual

- [x] 1.1 Write the failing tests for "A conflicting attribute is a difference whichever value the result holds" and "A build-file attribute both sides changed is a conflict" in `ResidualTests`: the issue's repro (base absent, ours `4`, theirs `10` on `AA0000000000000000000260`, theirs re-filtering) reports one conflicting residual carrying both values, on a result holding ours' value and on one holding theirs'; the same for one other attribute of the build file in `App`; verify both fail on 1.1.2 (no residual at all)
- [x] 1.2 Keep the control green: assert in `ResidualTests` that the existing re-filter scenario (only ours changed `fileEncoding`) still has no residual, and that an attribute both sides changed to the *same* value has none
- [x] 1.3 Implement design D1 and D2 in `Sources/PBXOps/Merge/Replay.swift`: `expectation` loses its both-changed line, `compare` emits the conflicting residual with ours' value, `Residual` gains `ours` and `conflicting` with the conflicting `description`, and `PathComparison.conflicts(paths:base:ours:theirs:)` is `compare` against ours filtered; verify 1.1 and 1.2 pass and `ResidualTests`, `ReplayTests` stay green

## 2. The unit becomes a decision

- [x] 2.1 Write the failing tests for "A conflicting attribute makes a unit a decision", "Theirs-membership owes the conflicting attribute" and "Both sides re-filter and conflict" in `MergeEngineTests`: the two repros exit `decisionsNeeded` with choices `ours`, `theirs-membership` and a residual naming `fileEncoding`; decided `theirs-membership` the merge is `merged` with `platformFilter = ios;`, `fileEncoding = 4;`, all six checks passed and `fileEncoding` in `owed`; verify they fail on 1.1.2 (the first `merged` with no question, the second decided `theirs`)
- [x] 2.2 Write the failing test for "The same membership change with a conflicting attribute is not skipped" in `MergeEngineTests`: both sides add `App/Views/Bar.swift` with different `fileEncoding`, the unit is a decision, not skipped; verify it fails on 1.1.2 (skipped)
- [x] 2.3 Implement design D3 in `Sources/PBXOps/Merge/Units.swift` (the conflict lookup before the skip, `ignoringConflicts`) and thread `MergeFaults.ignoreAttributeConflicts` from `MergeEngine`; verify 2.1 and 2.2 pass and `ClassificationTests`, `MergeEngineTests` stay green

## 3. Check E, the report and the fault seam

- [x] 3.1 Write the failing test for "A conflict dropped from a unit's residuals fails" in `MergeCheckTests`: the repro merged with `.ignoreAttributeConflicts` fails check E naming `AA0000000000000000000260` and `fileEncoding`, status `failed`, and the same merge without the fault is `decisionsNeeded`; verify it fails before 2.3 (both runs are `merged`)
- [x] 3.2 Write the failing tests in `MergeCommandTests`: the issue's two repros through the binary — exit `3` with the residual line naming both values in the text report, `--json` carrying `ours` and `conflicting` on the unit's residual, and the `theirs-membership` re-run exiting `0` with an `owed` entry; verify they fail on 1.1.2 (exit `0`)
- [x] 3.3 Implement the report side in `Sources/pbxedit/MergeReport.swift`: the `owed:` line for a conflict and `ResidualJSON`'s `ours` and `conflicting` (always present, `schemaVersion` unchanged); verify 3.1 and 3.2 pass

## 4. The regression fixture

- [x] 4.1 Add the `attribute-conflict` scenario to `MergeFixtureFileTests.scenarios()` (expected `decisionsNeeded`), regenerate with `PBXEDIT_WRITE_MERGE_FIXTURES=1 swift test --filter MergeFixtureFileTests`, and add its row to `Tests/Fixtures/merge/README.md`

## 5. Verification and documentation

- [x] 5.1 `swift build` and `swift test` green across all four targets (read the summary, not the exit code; the oracle lane included); `swift test -c release --filter PerformanceTests` green with the figures recorded
- [x] 5.2 Reconcile `docs/design.md` (status line, a Motivation-table row for issue #20) and add a dated note at D4 and D9 E of the archived `merge-command` design; add § 16 to `TODO.md` with the evidence
