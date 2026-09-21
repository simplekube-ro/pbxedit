# Design

## Context

The model provides primitive mutations; the rule set provides scoped evaluation; `query-command` provides `PathArgument` and `MembershipReport`. This change composes them into the first mutating command and, in doing so, builds the operation machinery `remove`, `move` and `lint --fix` reuse. See proposal.md for motivation and `docs/design.md` §§ Architecture 3–4, Conventions.

## Goals / Non-Goals

**Goals**

- An add that cannot produce any failure listed in `docs/design.md` § Motivation, each pinned by a regression fixture.
- Operation machinery generic enough that later commands add a planner and nothing else.
- Output in which every decision is attributable.

**Non-Goals**

- Guessing. Where siblings disagree the command stops and asks.
- Concurrency control between two pbxedit processes. The write is atomic; last writer wins, as with any editor.

## Decisions

### D1. Plan, then execute, on a copy

```
Planner:  (Project, Request, Conventions) -> Result<Plan, PlanError>
Plan:     { steps: [Step], decisions: [Decision], notes: [String], touched: Set<ID> }
Step:     createFileReference | createGroup | createBuildFile | addChild | addPhaseEntry
          | removeChild | removePhaseEntry | deleteObject | setAttribute | refreshAnnotations
```

The planner only reads. The executor applies steps to an in-memory `Project` value; a failure at any point discards that value. IDs are minted at planning time so `touched` and the output can name them.

*Alternative considered:* mutate directly while deciding. Rejected — it is how the predecessor ended up with half-applied adds, and it makes dry-run a second code path.

### D2. One pipeline for every mutating command

```
load -> plan -> execute in memory -> check(scope: touched)
     -> [dry-run: diff, stop]
     -> write temp -> rename -> reload from disk -> check(scope: touched)
     -> on failure: restore original bytes
```

`OperationRunner` owns this. `modified` is set in exactly one place: after a successful rename, by comparing new bytes to the original. A no-op plan (zero steps) skips the write, so `modified` stays `false`. Nothing else in the code base can print that word.

### D3. "Ensure" semantics

The add planner asks four questions per path and emits a step only for a "no": is there a reference resolving here; is it a child of the directory's group; does each target have a build file for it; is each build file in the right phase. Idempotence, the reuse path and completing partial membership are then one behaviour, not three.

### D4. Sibling inference

`Conventions.infer(for path, kind)`:

1. Siblings = file references resolving into the same directory with the same kind (source, resource, header, project-only), excluding the path itself. If empty, repeat for the parent directory, up to the source root.
2. Targets = intersection over siblings of their target sets. Extras are counted for the note.
3. `platformFilters`, per chosen target = the single value shared by all siblings' build files in that target, else a `PlanError.ambiguous` listing variants and counts.

Each result is wrapped in `Decision(value, source)` where `source` is `.flag`, `.inferred(count, directory)`, `.fileType` or `.structure`. `conventions-config` later adds `.config(ruleIndex)` between flag and inference without touching planners.

Group membership is deliberately absent from inference: the originating project shows siblings are 38% wrong about it.

### D5. Group for a directory

Find groups resolving to the directory via the model's path index. Prefer one whose chain is pathful; among equals take the first in object order. If none, find the deepest ancestor directory that has a group and create the missing chain beneath it. A created group gets `path = <dirname>; sourceTree = "<group>"` when its parent resolves to the parent directory, otherwise `name = <dirname>; path = <full path>; sourceTree = SOURCE_ROOT`.

### D6. File-type table

A static table maps extension → (kind, `lastKnownFileType`), covering what Xcode's new-file templates produce plus common resources. Unknown extensions are an error with a `--phase` hint, never a default; a wrong silent default (a JSON fixture compiled as a source) is worse than a question.

### D7. Atomic write

Temp file `project.pbxproj.pbxedit-<pid>` in the same directory, `fsync`, `rename(2)`. The original bytes are held in memory for the post-write restore. The temp file is removed in a `defer` on every path.

## Risks / Trade-offs

- [Intersection inference joins too few targets, e.g. misses an extension target] → By design: the note reports it, and `--target` adds it. Joining too many is the worse failure because it can break another platform's build.
- [Ancestor walk infers from an unrelated directory] → The output names the directory inferred from; the walk stops at the first ancestor with any sibling of the same kind.
- [Name-order detection misjudges a nearly sorted group] → Insertion last is always valid; the ordering rule is cosmetic.
- [Post-write verification doubles load time] → Two loads of a 10,000-line file are tens of milliseconds.

## Migration Plan

None; first mutating command. `docs/design.md` gains `--phase` in the Commands table in this change.
