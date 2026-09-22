# Design

## Context

`add-command` built `OperationRunner`, `Plan` and the step vocabulary, including the three removal steps (`removeChild`, `removePhaseEntry`, `deleteObject`), plus the renderer that prints a plan's changes, notes and post-operation membership in text and JSON. `conventions-config` made the runner honour `lint.exempt` in both checks. This change is a planner plus a command. See proposal.md for motivation.

## Goals / Non-Goals

**Goals**

- A removal that is complete even when the starting state is damaged — removing a half-registered file is a common repair.
- No accidental loss of a shared source from a target.

**Non-Goals**

- Undo. `git checkout project.pbxproj` is the undo; the tool's job is to make the change atomic and reviewable.

## Decisions

### D1. The planner enumerates from the indexes, not from expectations

For the reference `R` resolving to the path: every build file with `fileRef == R`; for each, every phase listing it (zero, one or several — `Project.phases(of:)` yields one entry per listing); every group listing `R` (zero, one or several — `Project.parents(of:)` likewise). A step is emitted per occurrence found. Because nothing assumes "one of each", the damaged-membership scenario (`add/partial.pbxproj`) needs no special case, and a phase or group listing the same ID twice (S3) gets two removal steps, each removing one listing.

Step order: `removePhaseEntry*`, `deleteObject(buildFile)*`, `removeChild*`, `deleteObject(R)`, then group pruning. Referrers go before referents so an intermediate state never has a dangling ID, which keeps executor assertions simple.

### D2. Unknown path is exit `1`, unlike re-add's `0`

`add` verifies the file exists on disk, so a typo cannot pass. `remove` cannot make that check — the file is usually already gone — so treating "not in the project" as success would let a typo pass silently. Agents needing idempotence can run `pbxedit query` first.

*Alternative considered:* an `--if-present` flag. Deferred until someone needs it.

### D3. Multi-target guard counts targets, not build files

The guard fires when the distinct targets owning the reference's build files' phases number more than one. A reference with two build files in the *same* target (an M5 defect, `rules/m5-double-add.pbxproj`) is removed whole without the guard. A build file in no phase, or in a phase no target owns, counts for no target.

### D4. `--target` keeps the reference

Detaching is "stop building this here", not "this file left the project". Keeping the reference and group child means the file stays visible in the navigator, and a later `add --target` reuses the reference. What is removed is exact: each listing of the reference's build files in a phase the named target owns; a build file left in no phase by that is deleted, one still listed elsewhere (a phase shared between targets) is kept. A build file already in no phase belongs to no target and is left alone — it is M1 damage, not this target's membership. The reference stays in `touched` (it is reused, as `add` treats a reused reference), and M1's finding names the reference as related, so a detach on a file with such damage is refused by the pre-write check with that finding; `remove` without `--target` takes the damage away instead. The output notes when the file is now built by no target.

A name that is not a target at all is a usage error (exit `2`, listing the targets) exactly as for `add`; the CLI validates it before planning. "Not a member of that target" is a refusal (exit `1`). `--target` with `--all` is a usage error.

### D5. Group pruning

After planning the reference's removal, walk up from each former parent: if the group's children, minus what this plan removes, are empty, and it is neither `mainGroup` nor `productRefGroup`, emit `removeChild(from: parent)` for each parent listing it and `deleteObject(group)`, and continue with the parents. "Empty before the operation" is excluded by construction, because the walk starts only from groups this plan touched. Only `PBXGroup` is pruned: a variant or version group cannot be a former parent, because D7 refuses their children.

With several paths in one invocation, pruning runs once over the combined plan, so removing all files of a directory in one command prunes the directory's group. Each pruned group is a `deletedObject` change attributed to the first path whose removal reached it.

### D6. Widened check scope

`touched` includes each deleted ID's former referrers (parent groups, phases, and the targets owning those phases), and the pruned groups' parents. The scoped S2/M2 evaluation on those referrers is what proves nothing still points at a deleted object. Deleted IDs themselves are also searched for in the serialized result as whole identifier tokens (runs of letters, digits and `_`), since a short ID such as `AB12` is a substring of `AB123` — `Plan.deletedObjects` and `Plan.deletedObjectsMentioned(in:)`. The runner asserts, in debug builds only and only after the scoped check has passed, that the two agree; tests assert it on every successful removal.

### D7. Refusals

A reference that is a child of a `PBXVariantGroup` or an `XCVersionGroup` is refused: removing one variant leaves a localization half-registered, removing one model version leaves `currentVersion` dangling, and neither is v1's business. A path that resolves to no reference but lies under a synchronized root group is refused naming the group: its membership comes from the folder and can only be changed by editing exception sets, which is out of scope.

## Risks / Trade-offs

- [Pruning removes a group the user keeps deliberately empty] → Only groups emptied by this very operation are pruned; the output lists each. Xcode itself keeps such groups, so this is a deliberate difference, chosen because agents delete directories far more often than they curate empty groups.
- [A reference listed in several groups resolves to different paths through each] → The model resolves through the first parent (model D4); removal is by reference ID once found, so all listings are removed regardless.
- [Annotation comments elsewhere mention the removed file] → Comments live on the references being removed; nothing else carries the name.
- [The debug assertion of D6 fires on a project where a deleted ID lives under a key S2 does not check] → The scoped check has passed at that point, so this would be a gap in S2's key list, which the corpus test keeps honest; the assertion exists to surface exactly that.

## Evidence

Real `pbxedit remove` output against `Tests/Fixtures/remove/app.pbxproj` (task 7.1), pinned by `RemoveCommandTests.testDesignEvidenceExamplesAreRealOutput`. There is no `README.md` yet; these are the examples for its `remove` section, to be moved when the first change creates the file. Nothing is minted by a removal, so the output is exact.

```
$ pbxedit remove --dry-run App/Features/New/Thing.swift --project App.xcodeproj
App/Features/New/Thing.swift
  removed phase entry from CC0000000000000000000001: entry in Sources of App (CC0000000000000000000001)
  deleted object BB0000000000000000000160: build file in App
  removed child from group AA0000000000000000000018: child of group New (AA0000000000000000000018)
  deleted object AA0000000000000000000280: file reference App/Features/New/Thing.swift
  removed child from group AA0000000000000000000017: child of group Features (AA0000000000000000000017)
  deleted object AA0000000000000000000018: group New (AA0000000000000000000018), left empty
  removed child from group AA0000000000000000000002: child of group App (AA0000000000000000000002)
  deleted object AA0000000000000000000017: group Features (AA0000000000000000000017), left empty
  membership: not a member
--- a/project.pbxproj
+++ b/project.pbxproj
@@ -29,7 +29,6 @@
 		BB0000000000000000000141 /* F2.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000261 /* F2.swift */; };
 		BB0000000000000000000150 /* AppKit.h in Headers */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000270 /* AppKit.h */; settings = {ATTRIBUTES = (Public, ); }; };
 		BB0000000000000000000151 /* Kit.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000271 /* Kit.swift */; };
-		BB0000000000000000000160 /* Thing.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000280 /* Thing.swift */; };
 /* End PBXBuildFile section */
 (the remaining hunks — the reference, the two groups, the App group's child and the phase entry — elided; the test pins the head and the last line)
project.pbxproj: not modified (dry run)
$ echo $?
0
```

The real run prints the same lines without the diff and ends with `project.pbxproj: modified`. Detaching keeps the reference:

```
$ pbxedit remove App/Services/Cache.swift --target AppExtension --project App.xcodeproj
App/Services/Cache.swift
  removed phase entry from CC0000000000000000000004: entry in Sources of AppExtension (CC0000000000000000000004)
  deleted object BB0000000000000000000113: build file in AppExtension
  membership: App (Sources)
project.pbxproj: modified
```

A shared file without a choice:

```
$ pbxedit remove App/Services/Cache.swift --project App.xcodeproj
error: App/Services/Cache.swift belongs to App and AppExtension; pass --target <name> to detach it from one, or --all to remove it from the project
project.pbxproj: not modified
$ echo $?
1
```
