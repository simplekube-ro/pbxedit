# Tasks

Every engine and command test asserts on the model or the written bytes, that the checks (A, the rule set relative to the inputs, among them) pass, and that `plutil -lint` accepts the result. Fixture: `Tests/Fixtures/merge/both-regions/`.

## 1. Offering both

- [x] 1.1 Write the failing tests for "Different insertions into one unordered array" and "Two packages added on both sides" in `HunkTests` (`both` offered, its text holding every element); verify they fail on today's rule (choices `ours`, `theirs`)
- [x] 1.2 Write the tests for "An array whose order matters keeps ours and theirs" and "The same package under two IDs keeps ours and theirs" in `HunkTests`, plus a removal on one side; they pass today and must keep passing
- [x] 1.3 Implement design D1–D2 (`UnorderedInsertions.swift`, `AnalysedHunk.analyse`); verify 1.1 and 1.2 pass and the rest of `HunkTests` stays green

## 2. Through the engine and the binary

- [x] 2.1 Write `MergeEngineTests` for the repro decided `both` and "Both ends of one unordered array decided both" (and `both`/`theirs`), checks A–F passing, `plutil -lint` clean; update any test that asserted `knownRegions` hunks offer only `ours`, `theirs`
- [x] 2.2 Add the `both-regions` scenario to `MergeFixtureFileTests.scenarios()`, regenerate with `PBXEDIT_WRITE_MERGE_FIXTURES=1`, add its row to `Tests/Fixtures/merge/README.md`
- [x] 2.3 Write `MergeCommandTests.testDifferentInsertionsIntoOneUnorderedArrayOfferBoth`: the repro through the binary, `both` in the JSON choices, exit `0` and `(de, fr, en, Base, )` written

## 3. Verification and documentation

- [x] 3.1 `swift build` and `swift test` green across all four targets (read the summary); `swift test -c release --filter PerformanceTests` green
- [x] 3.2 Reconcile `docs/design.md` (status line; the `merge` Commands row; a Motivation-table row for issue #13), add a dated note at D7 of the archived `merge-command` design, add § 14 to `TODO.md` with the evidence
