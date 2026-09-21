# Design

## Context

Findings carry rule, object ID and related IDs. Planners produce `Plan`s from steps; `OperationRunner` checks, writes atomically and verifies. add's group resolution (D5 there) and `Conventions` inference exist. A repair is a function from a finding to steps. See proposal.md for motivation and `docs/design.md` § Severity and repair.

The reference workload is the originating project: about 655 M3 findings, a handful of M1.

## Goals / Non-Goals

**Goals**

- Repairs a reviewer can trust from the diff alone: added children lines, new groups, removed dangling lines — nothing else.
- A stronger check than ordinary operations get, because the plan is large and machine-chosen.

**Non-Goals**

- Interactive selection of findings. `--dry-run`, then run, is the workflow.
- Repairing by rule subset (`--fix M3`). Add it if adoption shows a need.

## Decisions

### D1. A fixer per rule, producing steps or a reason

```
protocol Fixer { var rule: RuleID { get }
                 func plan(_ f: Finding, _ p: Project, _ c: Conventions, _ b: inout PlanBuilder) -> FixOutcome }
enum FixOutcome { case planned, notFixable(reason: String) }
```

`PlanBuilder` accumulates steps across findings and answers "does a group for directory D exist, *including ones this plan will create*". That shared view is what makes 95 orphans in one directory produce one new group rather than 95.

### D2. Order: M2, then M1, then M3

M2 deletions first, so M1 never lists a build file that M2 is about to delete. M3 last because it is independent of both. Within a rule, findings are processed in object-ID order so the plan, and therefore the diff, is deterministic.

### D3. M1 target choice reuses add's inference

The build file's file resolves to a path; `Conventions.targets(for:)` with flags empty gives config-then-inference. Exactly one target → fixable. Zero or several → `notFixable`. "Several" is deliberately not fixable even though it is a legal membership: one orphaned build file can belong to only one of them, and picking is a guess.

The build file's own `platformFilters` are left as found.

### D4. M3 never touches the reference

Only `addChild`, plus `createGroup` for missing chain links. The reference keeps its `path` and `sourceTree`, so a `SOURCE_ROOT`-spelled reference lands in a group without being re-spelled. Consequence: such a reference resolves correctly regardless of whether its new parent group is pathful, because `SOURCE_ROOT` ignores the chain. A `<group>`-relative orphan has no chain to resolve through, so the model reports it as resolving relative to the source root; if that path does not exist under any group directory the fixer still groups it by that resolved path — the reference is not made worse, and D1 will flag it under `--disk`.

### D5. Whole-project before/after comparison

Ordinary operations check scoped to `touched`. A repair compares complete finding sets:

```
before = evaluate(project)            selected = fixable ∩ before
after  = evaluate(result)
require  selected ∩ after == ∅   and   after − before == ∅
```

Findings are compared by (rule, object, related). Whole-project evaluation is affordable once per run, and it is the only check that can catch a repair that fixes M3 while creating an M4.

`OperationRunner` gains a `verification` parameter: `.scoped(touched)` (default) or `.noNewFindings(selected:)`.

### D6. Bulk mutation performance

If `typed-project-model` task 7.1 showed per-mutation index invalidation to be too slow, the batch scope introduced there is used by the executor for any plan over 50 steps. Otherwise nothing is needed. Target: the 655-orphan repair in under two seconds.

### D7. Baseline is reported on, not rewritten

After a repair the command computes which baseline entries no longer occur and prints the count with the `--write-baseline` hint. Rewriting the baseline is a second file modification with its own review implications; keeping it explicit keeps `--fix` to one file.

## Risks / Trade-offs

- [An M3 repair puts a file into a plausible but unintended group] → The group is the one representing the file's directory — the same place `add` would put it — so repaired files and newly added files end up alike. Visible in `--dry-run`.
- [A large repair diff is hard to review] → The diff has two line shapes only. `docs/design.md`'s adoption plan gates it on unchanged build and test counts on all platforms, and an Xcode open-and-save producing no diff.
- [M2 deletes a build file someone meant to reconnect] → A build file with neither `fileRef` nor `productRef` resolving carries no recoverable information except its ID; the output lists every deletion.
- [Whole-project comparison is defeated by a finding that changes identity] → Identity is (rule, object, related); repairs do not change IDs of existing objects (spec: Existing objects are reused), so identities are stable.
