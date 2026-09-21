# Design

## Context

`add-command` built `OperationRunner`, `Plan` and the step vocabulary, including the three removal steps. This change is a planner plus a command. See proposal.md for motivation.

## Goals / Non-Goals

**Goals**

- A removal that is complete even when the starting state is damaged — removing a half-registered file is a common repair.
- No accidental loss of a shared source from a target.

**Non-Goals**

- Undo. `git checkout project.pbxproj` is the undo; the tool's job is to make the change atomic and reviewable.

## Decisions

### D1. The planner enumerates from the indexes, not from expectations

For the reference `R` resolving to the path: every build file with `fileRef == R`; for each, every phase listing it (zero, one or several); every group listing `R` (zero, one or several). A step is emitted per occurrence found. Because nothing assumes "one of each", the damaged-membership scenario needs no special case.

Step order: `removePhaseEntry*`, `deleteObject(buildFile)*`, `removeChild*`, `deleteObject(R)`, then group pruning. Referrers go before referents so an intermediate state never has a dangling ID, which keeps executor assertions simple.

### D2. Unknown path is exit `1`, unlike re-add's `0`

`add` verifies the file exists on disk, so a typo cannot pass. `remove` cannot make that check — the file is usually already gone — so treating "not in the project" as success would let a typo pass silently. Agents needing idempotence can run `pbxedit query` first.

*Alternative considered:* an `--if-present` flag. Deferred until someone needs it.

### D3. Multi-target guard counts targets, not build files

The guard fires when the distinct targets owning the reference's build files number more than one. A reference with two build files in the *same* target (an M5 defect) is removed whole without the guard.

### D4. `--target` keeps the reference

Detaching is "stop building this here", not "this file left the project". Keeping the reference and group child means the file stays visible in the navigator, and a later `add --target` reuses the reference. The output notes when the file is now built by no target.

### D5. Group pruning

After planning the reference's removal, walk up from each former parent: if the group's children, minus what this plan removes, are empty, and it is neither `mainGroup` nor `productRefGroup`, emit `removeChild(from: parent)` and `deleteObject(group)` and continue with the parent. "Empty before the operation" is excluded by construction, because the walk starts only from groups this plan touched.

With several paths in one invocation, pruning runs once over the combined plan, so removing all files of a directory in one command prunes the directory's group.

### D6. Widened check scope

`touched` includes each deleted ID's former referrers (parent groups, phases, targets). The scoped S2/M2 evaluation on those referrers is what proves nothing still points at a deleted object. Deleted IDs themselves are also searched for as raw text in the serialized result — a cheap belt-and-braces assertion in the runner's debug build and in tests.

## Risks / Trade-offs

- [Pruning removes a group the user keeps deliberately empty] → Only groups emptied by this very operation are pruned; the output lists each. Xcode itself keeps such groups, so this is a deliberate difference, chosen because agents delete directories far more often than they curate empty groups.
- [A reference listed in several groups resolves to different paths through each] → The model resolves through the first parent (model D4); removal is by reference ID once found, so all listings are removed regardless.
- [Annotation comments elsewhere mention the removed file] → Comments live on the references being removed; nothing else carries the name.
