# Proposal

## Why

`pbxedit merge` 1.1.1 offers `both` for different insertions into one unordered array (issue #13), but not for the multi-line *objects* those insertions point at. When both sides add a Swift package, a group or a package product dependency, the two new objects land in one hunk whose zealous (`--zdiff3`) trimming cuts inside them: their shared tail — `requirement = { … }; };` for a package — becomes stable context, so `ours + theirs` no longer parses and only `ours` and `theirs` are offered. Measured on the issue's repro (issue #17): the `packageReferences` hunk offers `ours | theirs | both`, the object hunk only `ours | theirs`, and every allowed combination either loses one side's package or is refused by check A with `S2 … refers to EF0000000000000000000003 … which does not exist`. Two packages added on two branches therefore cannot both survive a merge.

## What Changes

- A hunk whose trimmed `ours + theirs` does not qualify for `both` is tried again with the **untrimmed** union: ours' whole text for the stretch, then theirs'. Inside the trimmed frame that is `ours + after + before + theirs`, where `before` and `after` are the lines trimming moved into stable context.
- The untrimmed union is offered as `both` only when it passes the same D7 test the trimmed form passes today: it parses and loads, every leaf equals base's with each side's changes, no new duplicate key, and any leaf both sides touch is an unordered-array insertion under issue #13's rules.
- The trimmed form is tried first, so every `both` that 1.1.1 offers keeps exactly the lines it has today.
- `ThreeWay.Hunk` keeps the lines trimming moved out, so the untrimmed union can be rebuilt. Hunk keys, the governed set, the reported `base`/`ours`/`theirs` text and the `ours`/`theirs` resolutions are unchanged.
- A hunk's *base* counterfactual is built by replacing its whole stretch, the trimmed frame included, rather than its lines alone. Where the base never held that frame — an insertion at one point, which is every hunk this change is about — the old text handed it to the base twice and did not even parse, so the analysis had no base and offered nothing. This is the same defect seen from the other side, and fixing it is what lets the leaf test run at all.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `merge`: the requirement "Everything else is merged as text" — `both` takes ours' lines then theirs', or, when that does not qualify, ours' untrimmed lines then theirs' untrimmed lines; the qualifying test is otherwise unchanged.

## Non-goals

- No new choice beyond `ours`, `theirs` and `both`, and no ordering choice between the two sides' text: `both` is always ours first.
- No relaxation of the D7 acceptance test. A union that fails it is still refused, and refusing a resolution stays the safe outcome.
- No change to how hunks are cut: the line diff, the cluster rule and zealous trimming are untouched, so keys, governed sets and the reported hunk texts stay as they are.
- No identity test for the objects in an object hunk beyond what issue #13 already applies to the array leaves that reference them; the same package added under two IDs is still governed by the list hunk's rule.
- No report surface for the untrimmed text (no new JSON field, no new human line).
- Nothing here touches "Out of scope for v1" in `docs/design.md`: git integration, `.pbxedit.yml` merging and verbs for residuals stay out.

## Impact

- `Sources/PBXOps/Merge/LineMerge.swift` — `ThreeWay.Hunk` gains the trimmed context and the base's untrimmed stretch; `ThreeWay.trim` and `ThreeWay.merge` record them; `ThreeWay.Merge` gains a text builder that replaces a hunk's whole stretch.
- `Sources/PBXOps/Merge/Hunks.swift` — `AnalysedHunk` stores the lines its `both` resolves to and tries the two candidate forms; `resolution(.both)` returns the stored lines.
- Tests: `LineMergeTests` (the trimming assertions gain the context), `HunkTests`, `MergeEngineTests`, `MergeCommandTests`, and a new three-way fixture under `Tests/Fixtures/merge/`.
- No new dependency. `MergeChecks`, `Decisions`, `MergeEngine` and the CLI read the new `both` lines through `AnalysedHunk.resolution` unchanged.
