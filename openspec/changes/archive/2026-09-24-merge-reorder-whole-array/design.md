# Design

## Context

See proposal.md (Why) and issue #32. The three-way line merge (merge design D6) clusters the two sides' line changes by base position. A change only one side made in a cluster of its own is stable text, and a cluster both sides changed differently is a hunk. Git behaves the same way, and it works for any text whose lines stand alone. An array's element lines do not stand alone when one side *moves* an element: Myers' diff spells the move as a deletion in one place and an insertion in another, and the two halves can land in different clusters.

Measured on `v1.3.0` with the issue's repro (base `(en, Base)`, ours `(Base, en)`, theirs `(en, Base, fr)`, one element per line):

| cluster | ours | theirs | outcome |
|---|---|---|---|
| line `en,` | deletes it | keeps it | stable: deleted |
| after `Base,` | inserts `en,` | inserts `fr,` | hunk `en` / `fr` |

Decided `theirs`: `(Base, fr)`. Check C governs the leaf by the one decided hunk and compares it with that hunk's `theirs` counterfactual, the whole text with the hunk resolved `theirs`. The clean deletion is already in that text, so the check agrees with the loss.

A reorder whose halves both fall outside the other side's changes produces no hunk at all. Check C's rule for an array both sides changed then requires each side's retained elements in that side's order, which a disagreement makes impossible, so it exits `1` (proposal.md, measured).

## Goals / Non-Goals

Goals: `ours` or `theirs` on a hunk over a reordered array yields that side's whole array; a reorder against another change is always a decision and never an unrecoverable exit `1`; and no exit `0` loses an element every side holds.

Non-goals: see proposal.md. At design level, also: no change to Myers' diff, to trimming or to how clusters are formed outside the kept spans.

## Decisions

### D1. The line merge keeps a span in one piece

`ThreeWay.merge` takes `wholeSpans`, a list of base line ranges. After clustering, every cluster inside a span is joined into one cluster from the first's start to the last's end. A cluster is inside when its base range overlaps the span, or, for an insertion (an empty range), when it falls strictly between the span's first and last line, after the line that opens the array and before the line that closes it. The joined cluster then goes through the unchanged tail of `merge`. If only one side changed anything in it, it is stable text. If both did, it is a hunk whose `ours` and `theirs` are each side's changes applied over the whole stretch, which inside a span covering an array means each side's whole array. Zealous trimming still runs. It removes only lines both sides share at the ends, so `ours` or `theirs` still reproduces that side's array exactly.

`ThreeWay` stays text-generic. It knows ranges of lines, not arrays, and an empty `wholeSpans` (the default, and every existing caller) behaves exactly as before.

*Alternative considered:* widening only a span that already holds a hunk, leaving a clean reorder-and-insert to merge line by line. Rejected on measurement: check C refuses that clean merge whenever the two orders disagree, so leaving it alone keeps an exit `1` the user cannot resolve.

### D2. Which spans: both sides changed, and their orders disagree

`ReorderedArrays.spans` walks the neutralised base's syntax tree (`SyntaxTree.arrayLines()`, new in `PBXSyntax`: every array reached by dictionary keys, with the lines from its `(` to its `)`). It keeps an array when ours and the neutralised theirs, the texts the line merge reads, each hold an array at that key path that differs from base's, and the two are not in *order agreement*. Order agreement is issue #24's test: restricted to the elements both hold, counted, the two arrays are equal (`UnorderedInsertions.ordersAgree(_:_:)`, now also over two plain arrays).

This is the exact condition under which no merged text can satisfy check C's order rule for the array, and so the condition under which splitting it serves nobody. Everywhere else the line merge is untouched:

- Two sides that only insert, or insert against a removal, agree. Every `both` offered today (issues #13, #17, #21, and #24's insertion-against-removal) is unchanged, measured by the unchanged `HunkTests`, `MergeEngineTests` and fixture statuses.
- An array only one side changed is never a span. It merges as that side's array, which check C already requires.
- Two sides that reorder identically agree, and merge as before.

A repeated key is resolved as every lookup resolves it (the first occurrence), matching `PlistLeaves`.

### D3. Check C: an element every side holds is never dropped

After the leaf's own rule, check C runs one more test on any leaf that is an array in base, ours, theirs and the result. The multiset intersection of base, ours and theirs, less the result's elements, must be empty. It holds whatever governs the leaf: a decided hunk, several, or none. No side removed such an element, so no decision can have asked for its removal. The message names the elements dropped and the array the merge has.

With D1 and D2 in place the repro no longer reaches it. It exists because D2's condition was derived by reasoning about Myers' output, not proved, and the failure it guards against is silent. The Red test uses a new fault seam, `MergeFaults.narrowArrayHunks`, which passes no spans, and runs the issue's repro decided `theirs`. Without the rule that run exits `0` with `(Base, fr)` (the `v1.3.0` behaviour). With it, check C fails naming `EE0000000000000000000001 knownRegions` and exit is `1`.

## Risks / Trade-offs

- **A bigger hunk.** Where the spans apply, the user decides one whole array rather than a few lines, and loses the other side's non-conflicting edits to that array whichever way they choose. That is the intended trade: the other choice is an array that is neither side's, or an exit `1`. Only arrays whose orders disagree are affected.
- **Keys change for those hunks.** A hunk's key hashes its text, so a decisions file written against `v1.3.0` for such a hunk names an unknown key and exits `2`. The only such decision that exited `0` produced the wrong array.
- **Cost.** One extra walk of the base tree and three leaf maps per merge, only when base has arrays at all. The release `PerformanceTests` record the Alamofire merge timings against `v1.3.0`'s.

## Migration Plan

None beyond the key note above.

## Open Questions

None.
