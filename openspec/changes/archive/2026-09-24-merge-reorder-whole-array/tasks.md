# Tasks

## 1. The lines an array spans

- [x] 1.1 `ArrayLinesTests` (new): an array one element per line spans its parentheses; a one-line array spans that line; comments and a quoted string's newlines count; arrays inside arrays are not reached by keys; an empty tree has none — failing to compile before 1.2
- [x] 1.2 `SyntaxTree.arrayLines()` in `Sources/PBXSyntax/Lines.swift`, walking tokens in `forEachToken` order and counting `\n` in trivia and token text; verify 1.1 passes

## 2. The line merge keeps a span whole

- [x] 2.1 `LineMergeTests`: a reorder split across a hunk is one hunk inside its span (and, without spans, still the split of `v1.3.0`); changes that do not overlap inside a span are one hunk; a span only one side changes stays stable; a hunk outside a span is not widened — Red with `wholeSpans` accepted and ignored
- [x] 2.2 `ThreeWay.merge(…, wholeSpans:)` joining every cluster inside a span, with `within(_:_:)` for an insertion strictly inside; verify 2.1 passes and the existing `LineMergeTests` are unchanged

## 3. The engine and check C

- [x] 3.1 `MergeEngineTests`: the repro is one hunk whose texts and governed values are each side's whole array, and it resolves `ours` to `(Base, en)` and `theirs` to `(en, Base, fr)` (the #24 test's `(Base, fr)` expectation replaced); a reorder and an insertion that do not overlap exit `3` with `ours | theirs` and resolve to each side's array — Red on `v1.3.0` (`(Base, fr)`; exit `1` on check C)
- [x] 3.2 `MergeCheckTests`: `droppedByNoSide` over the repro, a result that keeps everything, a removal by ours and a repeated element; the `narrowArrayHunks` fault run on the repro decided `theirs` fails check C naming `EE0000000000000000000001 knownRegions` and `en`, while without the fault it merges — Red with the stubs
- [x] 3.3 `ReorderedArrays.spans` (both sides change the array, orders disagree), `UnorderedInsertions.ordersAgree(_:_:)` over two arrays, the engine passing the spans unless `narrowArrayHunks`, and `droppedByNoSide` in check C after the leaf's own rule; verify 3.1 and 3.2 pass and `HunkTests` and `MergeFixtureFileTests` are unchanged

## 4. The command and the oracle

- [x] 4.1 `MergeCommandTests`: the `reordered-array` fixture through the binary decided `theirs` writes `(en, Base, fr, )` and decided `ours` writes `(Base, en, )`, each exit `0`, `pbxedit lint` and `plutil -lint` clean
- [x] 4.2 `reordered-array` decided `theirs` in `OracleTests.testXcodebuildReadsEveryMergedProject`, and its `Tests/Fixtures/merge/README.md` row stating both results

## 5. Verification and reconciliation

- [x] 5.1 `swift build` and the whole `swift test` suite green with `ORACLE_REQUIRED=1`. Read the summary: counts, and none skipped
- [x] 5.2 Release `PerformanceTests` green, with the Alamofire merge timings recorded against `v1.3.0`'s
- [x] 5.3 `docs/design.md` reconciled: status line, the `merge` Commands row, a Motivation-table row for issue #32, and a dated note at D1 of the archived `merge-both-order-agreement` design
- [x] 5.4 `openspec validate merge-reorder-whole-array --strict` green and `TODO.md` § 20 filled in with the evidence for each box
