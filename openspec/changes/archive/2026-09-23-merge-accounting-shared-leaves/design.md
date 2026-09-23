# Design

## Context

See proposal.md (Why) and issue #12. The `merge-command` design D7 builds, for each hunk, counterfactual texts in which every *other* hunk is resolved `ours`. D9 C then said: "leaves governed by a hunk decided `ours`/`theirs` expect the decided side's counterfactual value". That holds when one hunk governs a leaf. When two do, each counterfactual sees only its own hunk's choice, and `accounting` kept whichever hunk came last.

Measured on the `shared-array` scenario (base `(en, Base)`, ours `(de, en, Base, it)`, theirs `(fr, en, Base, es)`, plus an unrelated `SWIFT_VERSION` conflict): three hunks, the first two governing `EE0000000000000000000001 knownRegions`.

| head / tail | before | after |
|---|---|---|
| `ours` / `ours` | exit `0` `(de, en, Base, it)` | same |
| `ours` / `theirs` | exit `0` `(de, en, Base, es)` | same |
| `theirs` / `theirs` | exit `1`, check C | exit `0` `(fr, en, Base, es)` |
| `theirs` / `ours` | exit `1`, check C | exit `0` `(fr, en, Base, it)` |

## Goals / Non-Goals

Goals: every valid combination of decisions over a shared leaf passes check C, and C still has something to check on such a leaf: a result that loses, swaps or reorders an element fails.

Non-goals: see proposal.md.

## Decisions

### D1. Compose each hunk's effect instead of trusting one counterfactual

For a leaf path `p`, let `G` be the decided hunks whose governed set holds `p`. When `|G| > 1` and some hunk in `G` is decided `ours` or `theirs`:

- `O` = `p`'s value with every hunk `ours`. This is any governing hunk's `ours` counterfactual, since each of those is that same text.
- `Vᵢ` = `p`'s value in hunk `i`'s counterfactual for its choice. For `ours`/`theirs` it is already in `AnalysedHunk.values`. For `both` it is read from `counterfactual(.both)`, which is only parsed in this case.
- Arrays (`O`, every `Vᵢ` and the result): the expected multiset is `O + Σ(Vᵢ − O) − Σ(O − Vᵢ)`, and each `Vᵢ`'s retained elements must be a subsequence of the result. This is C's array rule with `O` as the base and one side per hunk. The additions are a plain sum, not the three-way rule's "theirs' additions minus ours' additions": two hunks are disjoint line ranges, so an element each of them adds is added twice.
- Otherwise: the distinct `Vᵢ` that differ from `O`. None means expect `O`, one means expect it, several means expect `p` in the text with every hunk resolved as decided (`MergeChecks.decidedBuild`, built at most once per run).

`|G| == 1` with an `ours`/`theirs` decision keeps the old exact comparison. `G` of `both` hunks only keeps the ordinary three-way rule, which the issue asks for explicitly: the decided build *is* the result there, so comparing against it checks nothing.

*Alternative considered:* the issue's suggestion, which expects every multiply governed leaf to equal its value in the text with all decisions applied. Rejected as the main rule. In the engine that text is byte for byte the text-merged result, so the comparison passes whatever the line merge did inside the hunks. It fails only under the `skipTextMerge` fault. The composition is independent of how `pre` was built, and it caught a wrong result the old check accepted (`(de, en, Base, es)` for `theirs`/`theirs`). The all-decisions text is kept as the fallback for a non-array leaf that two hunks change to different values. No real `project.pbxproj` shape is known to reach that case (a string is one line), and there the fallback avoids a false failure.

### D2. Where it lives

Everything is in `MergeChecks.accounting` and a new `composedProblem`, with two helpers on `DecidedHunk`. The engine, `AnalysedHunk` and the decisions file are unchanged. `accounting` keeps its public signature. The `wholeDictionaryLeaves` and `multisetArrays` faults apply to the new path the same way they apply to the old one.

### D3. Tests

- `MergeEngineTests.testTwoDecidedHunksGoverningOneArrayAcceptEveryCombination`: all four combinations merge with checks C, F, D, E, B, A passing, `plutil -lint` clean, and `knownRegions` equal to the head choice's element, then `en, Base`, then the tail choice's.
- `MergeCheckTests`: on the `theirs`/`theirs` text merge, the four wrong results `(fr, en, Base)`, `(fr, en, Base, it)`, `(de, en, Base, es)` and `(en, fr, Base, es)` each fail naming `EE0000000000000000000001 knownRegions`, while `lint` reports no error on them. The reordered one passes under `multisetArrays`. A `both` head with a `theirs` tail passes, and losing ours' `de` from it fails. With the `skipTextMerge` fault the engine fails C on `knownRegions`.
- `MergeCommandTests.testTwoDecidedHunksOverOneArray`: the issue's three rows through the binary on `Tests/Fixtures/merge/shared-array/`, exit `0` and the written `knownRegions`.

## Risks / Trade-offs

- [Composition assumes the hunks' effects on one array are independent] → They are disjoint line ranges of one array, and Xcode writes one element per line, so each hunk adds and removes its own lines. If that ever did not hold, the check would fail loudly (exit `1`, nothing written) rather than pass a wrong merge.
- [A `both` hunk sharing a leaf costs one more parse] → Only for that leaf, and in practice unreachable: `both` is never offered over an array. The code handles it so that the rule has no gap.
