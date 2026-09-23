# Tasks

Every engine and command test asserts on the model or the written bytes, that the checks pass (A, the rule set relative to the inputs, among them) and that `plutil -lint` accepts the result. Fixture: `Tests/Fixtures/merge/reordered-array/`.

## 1. Order agreement in the files

- [x] 1.1 Write the failing test for "A reorder against an insertion keeps ours and theirs" in `HunkTests`: the issue's repro (base `(en, Base)`, ours `(Base, en)`, theirs `(en, Base, fr)`) offers `ours` and `theirs` only; verify it fails on 1.1.2 and on `merge-both-frameworks-links` (`both` offered)
- [x] 1.2 Write the tests that must keep passing: "An insertion against a removal still merges with both" in `HunkTests` and `MergeEngineTests` (base `(en, Base, it)`, ours `(de, en, Base)`, theirs `(fr, en, Base, it)`: `both` offered, decided `both` the merge is `merged` with `(de, fr, en, Base)` and checks A–F passed), and the Frameworks reorder of issue #21 still refused; verify all three pass before 1.3
- [x] 1.3 Implement design D1 and D2 in `Sources/PBXOps/Merge/UnorderedInsertions.swift`: `ordersAgree` on `AnalysedHunk.Sides` (the renamed `Inputs`, without the base it no longer needs) for every admitted leaf, replacing `insertionsOnly` and `isFrameworksPhase`; verify 1.1 and 1.2 pass and `HunkTests`, `MergeEngineTests`, `MergeCheckTests` stay green
- [x] 1.4 Write the engine test for the repro: `MergeEngineTests` — the reorder repro exits `decisionsNeeded` with the two choices, and `--decisions` asking `both` for it exits `unsupported` naming the key; verify with 1.3 in place

## 2. The regression through the binary

- [x] 2.1 Add the `reordered-array` scenario to `MergeFixtureFileTests.scenarios()` (expected `decisionsNeeded`), regenerate with `PBXEDIT_WRITE_MERGE_FIXTURES=1 swift test --filter MergeFixtureFileTests`, and add its row to `Tests/Fixtures/merge/README.md`
- [x] 2.2 Write `MergeCommandTests.testAReorderAgainstAnInsertionKeepsOursAndTheirs`: the fixture through the binary — exit `3` with `ours | theirs` for that hunk and no `both` in its choices, and a decisions file asking `both` exiting `2`; verify it fails without 1.3

## 3. Verification and documentation

- [x] 3.1 `swift build` and `swift test` green across all four targets (read the summary, not the exit code; the oracle lane included); `swift test -c release --filter PerformanceTests` green with the figures recorded
- [x] 3.2 Reconcile `docs/design.md` (status line, the `merge` Commands row, a Motivation-table row for issue #24) and add dated notes at D2 of the archived `merge-both-unordered-insertions` design and D1 of the archived `merge-both-frameworks-links` design; add § 18 to `TODO.md` with the evidence
