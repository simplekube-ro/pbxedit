# Design

## Context

See proposal.md (Why) and issue #24. `UnorderedInsertions.admits` (issue #13's design D2) decides whether the leaves both sides of a hunk changed may still take `both`. For an array leaf it asks, on the hunk's three *counterfactual* texts, that base's array be a subsequence of ours' and of theirs' — "both sides only inserted" — and that no element ours inserts have the identity of one theirs inserts.

The counterfactual is the whole file with this hunk resolved one way and every other hunk `ours`, and zealous trimming moves the lines common to the start and end of both sides out of the hunk. Measured on the issue's repro (base `knownRegions = (en, Base)`, ours `(Base, en)`, theirs `(en, Base, fr)`):

| | the file | the hunk's counterfactual |
|---|---|---|
| base | `(en, Base)` | `(Base, )` |
| ours | `(Base, en)` | `(Base, en, )` |
| theirs | `(en, Base, fr)` | `(Base, fr, )` |

In the counterfactual both sides only insert, so `both` is offered; in the files, ours swapped two elements theirs kept in base's order. Decided `both`, check C fails: `theirs' order of (en, Base, fr, ) is lost in (Base, en, fr, )`.

`merge-both-frameworks-links` (issue #21) hit the same thing for a Frameworks phase's `files` and blocked it there with `insertionsOnly`: base's array must be a subsequence of each side's *in the files*. Its design records the asymmetry — one key tested twice — as a trade-off, and the wider hole as a defect of its own. This is that defect.

## Goals / Non-Goals

Goals: never offer a `both` that check C must refuse, by one rule that every admitted array shares, without losing a `both` that works today.

Non-goals: see proposal.md. At design level, also: no change to the counterfactual tests, which remain what establish *what* each side inserted, and no attempt to repair the counterfactual base.

## Decisions

### D1. The two sides' orders must agree in the files

For every shared array leaf, on the arrays in the three files the merge read: take the elements ours and theirs both hold (as a multiset intersection), restrict each side's array to them, and require the two restricted sequences to be equal. Equal restricted sequences is exactly "no two elements appear in opposite relative order in ours and in theirs".

That is the necessary condition for any `both` text to pass check C. C requires each side's elements that survive into the result to appear there in that side's own order; two elements both sides keep but order differently cannot both be satisfied, whatever text `both` produces. So a leaf that fails this test has no honourable `both`, and one that passes it loses nothing: two sides that only insert keep base's order in both arrays and so agree, which is every `both` offered since `v1.1.1` for insertions.

The elements *only one* side holds carry no constraint, and the test ignores them by construction: an element theirs removed is not in the result, so C never asks where it is, and an element only ours holds cannot disagree with an order theirs does not have.

*Alternative considered:* the file-wide subsequence test `merge-both-frameworks-links` uses — base's array a subsequence of each side's, in the files. Rejected as the general rule: measured, it refuses a `both` that works today, where one region of an array inserts while another removes (base `(en, Base, it)`, ours `(de, en, Base)`, theirs `(fr, en, Base, it)`; the removal merges cleanly, the insertions share one hunk, `both` gives `(de, fr, en, Base)` and every check passes). Order agreement admits that case and still refuses every reorder, so it replaces the subsequence test for the Frameworks key too: `insertionsOnly` and `isFrameworksPhase` go, and `admits` has one rule for every key again.

*Alternative considered:* keep the Frameworks-only test and add order agreement beside it. Rejected: two file-wide tests where one implies what matters, and the subsequence test would keep refusing the insert-against-remove shape for Frameworks links alone, for no reason a reader could reconstruct.

*Note, 2026-09-24 (`merge-reorder-whole-array`, issue #32):* refusing `both` was right but not enough. The hunk this design refused `both` for covered only half of ours' move: the line merge split the swap into a clean deletion of `en` and a conflicting insertion, so `theirs` gave `(Base, fr)`, dropping an element all three sides hold, with exit `0`. Order disagreement, the test this design introduced, now also tells the line merge to keep such an array in one hunk, and check C refuses any result that drops an element base, ours and theirs all hold.

### D2. Where the test runs

`admits` already receives the two sides as the line merge read them (`AnalysedHunk.Sides`; the neutralised theirs in the engine, where neutralisation never touches an unmanaged array). With the subsequence test gone, base is not needed there at all, so `Inputs` — which carried it for `merge-both-frameworks-links` — becomes `Sides` with ours and theirs alone. The check goes there, beside the counterfactual conditions, so a leaf must pass both: the counterfactual conditions say what each side did to *this hunk*, and order agreement says the two sides do not contradict each other in the files. Nothing else moves.

## Risks / Trade-offs

- **A `both` that could have been offered.** Two sides that reorder the same elements *identically* also agree, so they still pass; two that reorder differently are refused even where the disagreeing elements would have been dropped by a third decision. That is the conservative direction: refusing offers `ours` and `theirs`, which always resolve.
- **The counterfactual base stays wrong.** This change does not repair it; it adds the one whole-file question whose answer the counterfactuals cannot be trusted for. Anything else that reads the counterfactual base — the governed-leaf sets, the values the report prints — is unchanged and was not measured to be wrong.

## Migration Plan

None. A hunk that offered `both` wrongly now offers `ours` and `theirs`; its key is unchanged, so a decisions file written against `v1.1.2` still matches, and one that said `both` for such a hunk now exits `2` naming the key — which is the point, since that `both` exited `1`.

## Open Questions

None.
