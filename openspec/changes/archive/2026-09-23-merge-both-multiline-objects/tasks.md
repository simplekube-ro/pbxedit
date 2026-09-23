# Tasks

## 1. The hunk keeps its trimming context

- [x] 1.1 Write the failing `LineMergeTests` cases for design D1: `ThreeWay.trim` returns a hunk carrying `before` and `after`, `ThreeWay.merge` keeps them on the hunk it emits (`merge("az", "akxlz", "akylz")`), and a hunk trimming did not cut has both empty. Red: `Hunk` has no such members
- [x] 1.2 Add `before` and `after` to `ThreeWay.Hunk`, defaulting to empty, and set them in `ThreeWay.trim` and `ThreeWay.merge` (design D1). Verify `swift test --filter PBXOpsTests.LineMergeTests` is green and the whole suite still builds

## 2. `both` tries the untrimmed union

- [x] 2.1 Write the failing `HunkTests` case for the issue #17 repro: with the base, ours and theirs of design D1's table, the hunk governing the two `XCRemoteSwiftPackageReference` objects offers `ours`, `theirs`, `both`; its `both` text is ours' three lines, then the five-line `requirement` tail, then theirs' three lines; and the `both` counterfactual's leaves hold both objects with each side's `repositoryURL`. Red: the hunk offers `ours`, `theirs`
- [x] 2.2 Make `AnalysedHunk.analyse` try the untrimmed union when the trimmed form does not qualify, and store the qualifying lines on the hunk for `resolution(.both)` (design D2, D3). Verify 2.1 passes
- [x] 2.3 Write and pass the `HunkTests` cases that fix the boundary (design D4, D5): the `knownRegions` repro's `both` is still exactly ours' line then theirs' line, and two packages added under one ID with different `repositoryURL`s offer `ours`, `theirs` only
- [x] 2.4 Verify the hunk keys, governed sets and reported texts did not move: `swift test --filter PBXOpsTests` and `swift test --filter CLITests` green with no change to any existing assertion about a key or a hunk's `base`/`ours`/`theirs` text

## 3. Through the engine and the binary

- [x] 3.1 Write the failing `MergeEngineTests` case: the repro with both hunks decided `both` exits with checks A–F passed, `plutil -lint` clean, the rule set clean, and the model holding three `packageReferences` entries and three `XCRemoteSwiftPackageReference` objects with the three URLs; and with hunk 1 `both`, hunk 2 `ours`, check A still fails naming S2 and the missing object
- [x] 3.2 Verify 3.1 passes with no engine change (design D3: everything reads `resolution`); if it does not, fix what it names and say so in the task's evidence
- [x] 3.3 Add the three-way fixture `Tests/Fixtures/merge/both-objects/` for the repro, regenerated with `PBXEDIT_WRITE_MERGE_FIXTURES=1 swift test --filter MergeFixtureFileTests`, and a `README.md` entry; verify `MergeFixtureFileTests` is green without the environment variable
- [x] 3.4 Write and pass the `MergeCommandTests` case that runs the fixture through the binary: exit `3` with both hunks offering `both` in `--json`, then exit `0` with both decided `both` and all three packages and objects in the written file

## 4. Verification and reconciliation

- [x] 4.1 Run `swift build` and `swift test`, read the summary, and record the counts and any skips in `TODO.md`
- [x] 4.2 Run the oracle lane (`xcodebuild -list` on the post-operation fixtures) and the release `PerformanceTests` (`swift test -c release --filter PerformanceTests`); record the merge timings, and record why the new fixture stays out of the oracle lane (design D6)
- [x] 4.3 Reconcile `docs/design.md` (status line, the `merge` row, a Motivation-table row for issue #17), `CLAUDE.md`'s state paragraph and a dated note at the archived `merge-command` design's D7; verify `openspec validate merge-both-multiline-objects --strict` is green
