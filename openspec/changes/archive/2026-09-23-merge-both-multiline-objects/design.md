# Design

## Context

See proposal.md (Why) and issue #17. `merge-command` design D6 trims every hunk zealously (`--zdiff3`): the lines common to the start and to the end of both sides' text become stable context before and after the hunk, and `ThreeWay.trim` returns them but `ThreeWay.merge` only appends them to the neighbouring stable regions. `ThreeWay.Hunk` keeps just `base`, `ours` and `theirs`. D7 offers `both` when `hunk.ours + hunk.theirs` parses and its leaves are base's with each side's changes applied; `merge-both-unordered-insertions` D1–D2 relaxed the disjointness test for insertions into an unordered array.

Measured on the issue's repro (base `Tests/Fixtures/xcode27/platform-filters-after-xcode27-save.pbxproj` with `packageReferences = (EF…01)` and one `XCRemoteSwiftPackageReference`; ours adds `EF…02` for `https://example.com/a`, theirs `EF…03` for `https://example.com/b`, both with the same `requirement`):

| hunk | base | ours | theirs | governs | choices |
|---|---|---|---|---|---|
| 1 | empty | `EF…02 …,` | `EF…03 …,` | `EE…01 packageReferences` | `ours`, `theirs`, `both` |
| 2 | empty | 3 lines: `EF…02 … = {`, `isa = …;`, `repositoryURL = "…a";` | 3 lines, `EF…03` and `…b` | the two objects' `isa`, `repositoryURL`, `requirement.kind`, `requirement.minimumVersion` | `ours`, `theirs` |

Hunk 2's `before` is empty and its `after` is the five shared lines `requirement = {`, `kind = …;`, `minimumVersion = …;`, `};`, `};`. So `ours + theirs` opens two dictionaries and closes one: it does not parse, and `both` is not offered.

## Goals / Non-Goals

Goals: a `both` for a hunk trimming cut inside a multi-line object, gated by exactly the test that gates `both` today.

Non-goals: see proposal.md. At design level, also: no change to `ThreeWay.merge`'s clustering or trimming, and no second `both` in the choice list — a hunk offers `both` at most once, whichever form produced it.

## Decisions

### D1. The hunk keeps the lines trimming took from it

`ThreeWay.Hunk` gains `before` and `after`, the lines `ThreeWay.trim` moved into the stable regions on either side, and `stretchBase` (design D2); `ThreeWay.merge` passes them when it builds the trimmed hunk, and they default to empty — `stretchBase` to `base` — so a hunk built by hand (tests, `AnalysedHunk` counterfactuals) is unchanged. `before + ours + after` is then ours' untrimmed text for the stretch and `before + theirs + after` theirs'.

They belong on the `Hunk` rather than on the `Region` or on a parallel array in `Merge`: the hunk is the only consumer, a parallel array can fall out of step with `regions`, and an enum case cannot take a defaulted payload. `Hunk` stays `Equatable`, so two hunks with the same three texts but different trimming context are no longer equal — correct, and `LineMergeTests`' trimming assertions are updated to say so.

*Alternative considered:* recompute `before`/`after` in `AnalysedHunk` from the neighbouring stable regions. Rejected: `RegionBuilder` coalesces stable text, so nothing says how many of a stable region's lines came from trimming.

*Alternative considered:* let `trim` keep the frame in `base` instead of a separate field. Rejected: `base` is part of a hunk's key and of what the report prints for it, and both must not move.

### D2. The base counterfactual takes the whole stretch

Found while applying: the analysis had no base at all for exactly the hunks this change is about. `AnalysedHunk`'s base counterfactual replaces the hunk's lines with `hunk.base`, but zealous trimming moves `before` and `after` into the stable regions on either side and shortens `base` by them *only where the base has them in the same place*. Where it does not — an insertion at one point, where the base stretch is empty — the base counterfactual is handed the frame twice, and in the repro it does not parse at all: EF…01's `requirement` block appears once as stable context and once as the base's own continuation. With no base, `analyse` falls to "everything the sides disagree on, owned by both", every governed leaf is shared, `UnorderedInsertions.admits` refuses it, and `both` is never considered whatever its text would be.

So `ThreeWay.Hunk` also keeps `stretchBase`: the base's own lines for the whole stretch, which is the untrimmed `base` `trim` received, and `base` again for a hunk it did not cut. `ThreeWay.Merge` gains `text(replacingStretchOf:with:)`, which replaces the hunk *and* the `before`/`after` the stable regions on either side carry for it, resolving every other hunk `ours`. The base counterfactual uses it; `ours`, `theirs` and `both` keep the cheaper `text(_:index:lines:)`, whose result is already the untrimmed stretch in place.

For a hunk whose base did share the frame this is the same text as before, so nothing else moves. For one whose base did not, the base counterfactual now loads where it did not, which is what gives `oursTouched` and `theirsTouched` their disjoint object leaves.

### D3. `both` is the first form that qualifies

`AnalysedHunk.analyse` builds the candidate forms in order:

1. the trimmed form, `hunk.ours + hunk.theirs`, as today;
2. the untrimmed union, `hunk.ours + hunk.after + hunk.before + hunk.theirs` — ours' untrimmed text followed by theirs', with the frame the trimming lifted out written once between them, since `before` precedes and `after` follows the hunk in the merged text either way.

A hunk trimming did not cut has `before` and `after` empty, so form 2 equals form 1 and is not tried. Each form goes through the existing D7 gate unchanged: it must parse and load; every leaf of the `both` text must equal base's with ours' and theirs' changes applied; every leaf both sides touch must be admitted by `UnorderedInsertions.admits` and pass `MergeChecks.arrayProblem`; and the duplicate-key count must not grow. The first form that passes becomes the hunk's `both`; if none does, `choices` stays `ours`, `theirs`.

Trying the trimmed form first is what keeps every `both` `v1.1.x` offers byte-identical — the acceptance criterion in the issue. `UnorderedInsertions.admits` and the expected-leaf map do not depend on the candidate text, so they are computed once, outside the loop.

*Alternative considered:* always use the untrimmed union. Rejected: it would rewrite the `both` text of every hunk trimming touched, for no gain, and the issue asks for the 1.1.x text to be kept.

*Alternative considered:* emit `before + ours + after + before + theirs + after` and drop the surrounding stable lines instead. Rejected: the stable regions are shared with every other hunk's counterfactual and with `Merge.text`; a resolution may only replace its own hunk's lines.

### D4. The resolution is stored, not recomputed

`AnalysedHunk` gains `let both: [[UInt8]]?` — the lines the qualifying form produced, `nil` when none did — and `resolution(.both)` returns it (falling back to `hunk.ours + hunk.theirs`, which is unreachable while `.both` is only in `choices` when `both` is non-`nil`). `choices` contains `.both` exactly when it is non-`nil`. Everything downstream — `counterfactual`, `MergeChecks.decidedBuild` and `resolvedValue`, `MergeEngine`'s merged text, the decisions template — already goes through `resolution`, so nothing else changes.

Hunk keys hash the trimmed `base`, `ours` and `theirs` plus the governed object IDs, none of which this change touches, so every key in an existing decisions file still resolves. The report's `base`/`ours`/`theirs` text and the governed table are likewise the trimmed hunk's, unchanged.

### D5. Nothing is loosened

The untrimmed retry cannot offer `both` where the trimmed form was refused for a reason other than layout: the leaf test, the shared-leaf admission and the duplicate-key test are applied to it in full. Two objects added under one ID still share their leaves, which are not array insertions, so neither form is offered. An object hunk whose `both` would leave one of the two objects unreferenced is not this check's business: checks A–F run on the decided result before any write, and S2 refuses a list entry with no object.

### D6. Tests

- `LineMergeTests`: `trim` returns the context and the merged hunk carries it; a hunk trimming did not cut has neither.
- `HunkTests`: the repro's object hunk offers `both` and its `both` text is ours' three lines, the five-line `requirement` tail, then theirs' three lines; the merged leaves hold both packages; the `knownRegions` repro's `both` is still exactly ours' line then theirs'; two objects under one ID offer `ours`, `theirs`.
- `MergeEngineTests`: the repro with both hunks decided `both` passes checks A–F with `plutil -lint` clean and holds all three packages and their objects; with hunk 1 `both` and hunk 2 `ours` check A still fails on S2, as the issue reports.
- `MergeCommandTests`: the repro through the binary on a new `Tests/Fixtures/merge/both-objects/`, `both` offered on both hunks in `--json`, exit `0` with all three packages written.
- Not the oracle lane: `xcodebuild -list` resolves a project's package dependencies before it lists anything, so it refuses any project holding an `XCRemoteSwiftPackageReference` whose `repositoryURL` is not a real repository — `Could not resolve package dependencies`. The fixture's URLs are `https://example.com/…`, so the merged project cannot go through `xcodebuild`; `plutil -lint`, checks A–F and the model assertions carry it instead.

## Risks / Trade-offs

- [The untrimmed union duplicates the frame between the two sides] → The frame is the text the two sides share at the edges of the stretch; writing it once between them is what makes each side's object complete. Anything else the duplication produces — a repeated key, a lost or doubled array element — fails the leaf or duplicate-key test and `both` is not offered.
- [`ThreeWay.Hunk`'s equality now distinguishes trimming context] → Only `LineMergeTests` compares whole hunks, and `HunkTests`' "the same three texts" comparison is between two hunks with no trimming context. Hunk keys do not read it.
- [`both` on an object hunk while the list hunk keeps `ours`] → The decided result then holds an object nothing refers to. That is not a rule violation and no worse than today, where the same pair of decisions fails check A outright; every combination still passes through A–F before a byte is written.
- [The oracle lane does not read the new fixture] → Measured: `xcodebuild -list` exits `74` with `Could not resolve package dependencies` on the merged project, because the packages' URLs are made up. The merge itself is unaffected; a package fixture simply cannot be an oracle fixture.
- [A large hunk's second candidate doubles the parse work] → Only for a hunk whose trimmed `both` failed, which today ends the analysis for that hunk. The release `PerformanceTests` merge is the guard.
