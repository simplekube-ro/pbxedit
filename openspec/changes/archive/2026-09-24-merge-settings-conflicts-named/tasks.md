# Tasks

## 1. The conflict rule over build-file settings

- [x] 1.1 `ResidualTests`: the repro's conflicting `settings` (base none, ours `{COMPILER_FLAGS = "-w"; }`, theirs `{COMPILER_FLAGS = "-Wall"; }` with the row re-created), asserting `conflicting`, ours', theirs' and the result's value, and the same on a comparison whose result holds theirs' settings — Red on `v1.2.0` (`conflicting: false`, `ours: nil`)
- [x] 1.2 `ResidualTests`: the one-sided controls that must not move — theirs-only settings stay a plain residual with no `ours`, and the same settings on both sides produce none — passing before the fix and after
- [x] 1.3 Make `PathComparison.conflicting` generic over the compared value and run the conflict test on a row's `settings` with the counterparts `compare` already resolves (`was`, `ourRow`), reporting it through `conflict(…)`; verify 1.1 and 1.2 pass and `swift test --filter ResidualTests` is green

## 2. The rule over spelling and the parent group

- [x] 2.1 `ResidualTests`: a `name` both sides set to different values on one reference (theirs also re-filtering) is a conflicting residual carrying ours' value — Red on `v1.2.0`
- [x] 2.2 `ResidualTests`: both sides moving one file to different paths (base `App/Filtered/F1.swift`, ours `App/Views/F1.swift`, theirs `App/Other/F1.swift`) reports no residual at all and the unit offers `ours` and `theirs` — design D2's measurement, passing before the fix and after
- [x] 2.3 Label a spelling or parent-group difference that survives the replay as conflicting, leaving a value the replay reproduced unreported; verify 2.1 and 2.2 pass together

## 3. The engine, the owed entry and the checks

- [x] 3.1 `MergeEngineTests`: the issue's repro exits `3` with the unit offering `ours` and `theirs-membership` and its `settings` residual conflicting with both values, and the both-sides-re-filter variant (ours `macos`, theirs `ios`) does the same — Red on `v1.2.0` for the flag and ours' value
- [x] 3.2 `MergeEngineTests`: the repro decided `theirs-membership` exits `0` with checks A–F passed, the merged build file keeping ours' settings, and the `owed` entry conflicting with ours' and theirs' values — Red on `v1.2.0`
- [x] 3.3 `MergeCheckTests`: with `MergeFaults.ignoreAttributeConflicts` the unit is replayed, nothing is owed, and check E fails naming the build file and `settings`, exit `1`, nothing written — proves E bites without a new fault seam
- [x] 3.4 Verify 3.1–3.3 pass with no change beyond §1 and §2 (`swift test --filter MergeEngineTests`, `--filter MergeCheckTests`), and read the summaries

## 4. The fixture and the command

- [x] 4.1 `MergeFixture.settingsConflict(…)` and the `settings-conflict` scenario in `MergeFixtureFileTests.scenarios()`, regenerated with `PBXEDIT_WRITE_MERGE_FIXTURES=1 swift test --filter MergeFixtureFileTests`; verify the committed-files test and the per-scenario status test are green and `Tests/Fixtures/merge/README.md` has its row
- [x] 4.2 `MergeCommandTests`: the fixture through the binary — exit `3`, the text report naming both sides' settings, `--json` carrying `ours` and `conflicting: true` in `residuals`, then the `theirs-membership` re-run exiting `0` with the same fields in `owed` and `plutil -lint` clean on the written file
- [x] 4.3 Add the merged fixture to the oracle lane (`OracleTests.testXcodebuildReadsEveryMergedProject`, decided `theirs-membership`) and verify `xcodebuild -list` reads it

## 5. Verification and reconciliation

- [x] 5.1 `swift build` and the whole `swift test` suite green — read the summary, counts and "none skipped", so the oracle lane ran
- [x] 5.2 Release `PerformanceTests` (`swift test -c release --filter PerformanceTests`) green, with the Alamofire merge timings recorded against `v1.2.0`'s
- [x] 5.3 `docs/design.md` reconciled: the status line, the `merge` Commands row (what the conflict test covers and what it does not), a Motivation-table row for issue #28, and a dated note at the archived `merge-attribute-conflicts-asked` design's D1
- [x] 5.4 `openspec validate merge-settings-conflicts-named --strict` green and `TODO.md` § 19 filled in with the evidence for each box
