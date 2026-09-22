# Design

## Context

The model provides primitive mutations (`createObject`, `deleteObject`, `addChild`, `removeChild`, `addPhaseEntry`, `removePhaseEntry`, `setAttribute`, `refreshAnnotations`) and `IDMinter`; the rule set provides scoped evaluation (`RuleSet.evaluate(project, scope:)`, keeping a finding when its object or a related object is in scope); `query-command` provides `PathArgument` and `MembershipReport`. This change composes them into the first mutating command and, in doing so, builds the operation machinery `remove`, `move` and `lint --fix` reuse. See proposal.md for motivation and `docs/design.md` §§ Architecture 3–4, Conventions.

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
Planner:  (Project, Request, Conventions) throws(PlanError) -> Plan
Plan:     { steps: [Step], changes: [Change], decisions: [Decision], notes: [String], touched: Set<ID> }
Step:     createFileReference | createGroup | createBuildFile | addChild | addPhaseEntry
          | removeChild | removePhaseEntry | deleteObject | setAttribute | refreshAnnotations
Change:   one human-readable line per object created, reused or modified, with its ID
```

The planner only reads. `Plan.apply(to:)` applies the steps to a copy of the `Project` value and returns the result; a failure at any point discards that value, and the caller's original is untouched — which required the model's `Project` to give a copy its own index cache on first mutation (proposal, Impact). IDs are minted at planning time so `touched` and the output can name them. A `PlanBuilder` accumulates steps, changes, decisions, notes and `touched`, and remembers the groups the plan will create by directory, so two paths into one new directory share one new group (and so `lint --fix` can ask "does a group for D exist, including ones this plan creates").

`touched` names every object a step creates or modifies *and every object the plan reuses* — the existing reference, its build files, the groups and phases inserted into — so the pre-write check also judges a re-add of a damaged member (a reference with two parents, a build file in two phases) rather than reporting success on it. A plan with zero steps still runs the check over what it reused.

*Alternative considered:* mutate directly while deciding. Rejected — it is how the predecessor ended up with half-applied adds, and it makes dry-run a second code path.

### D2. One pipeline for every mutating command

```
load -> plan -> execute in memory -> check(scope: touched)
     -> [dry-run: diff, stop]
     -> write temp -> rename -> reload from disk -> check(scope: touched)
     -> on failure: restore original bytes
```

`OperationRunner` (in `PBXOps`, `Sources/PBXOps/Plan/OperationRunner.swift`) owns everything after planning: it is constructed on the project file (reading and loading it once, so the CLI can validate flags against the same `Project` the planner sees), and `run(_ plan:, dryRun:)` executes, checks, writes, verifies and reports. The CLI plans; the runner never sees flags. Error-severity findings in scope abort; warnings (S5, M6) are reported as notes and do not.

`modified` is set in exactly one place: after the write, by reading the file back and comparing its bytes to the original. A no-op plan (zero steps) skips the write, so `modified` stays `false`; a post-write failure restores the original bytes and `modified` is `false` again. Nothing else in the code base can print that word.

### D3. "Ensure" semantics

The add planner asks four questions per path and emits a step only for a "no": is there a reference resolving here; is it a child of some group; does each target have a build file for it in some phase; is each build file in the right phase. Idempotence, the reuse path and completing partial membership are then one behaviour, not three. A build file for the reference that no phase lists is reused for the first target that lacks one, rather than a new one minted beside it (the `partial` fixture). An existing reference keeps its `path` and `sourceTree` spelling even when it is orphaned and gains a group child: `SOURCE_ROOT` resolves regardless of the chain, and re-spelling would be a second change nobody asked for.

### D4. Sibling inference

`Conventions.targets(for:kind:in:)` and `Conventions.platformFilters(for:kind:target:in:)`, each `flags ?? infer`:

1. Siblings = file references resolving into the same directory with the same kind (source, resource, header, project-only, by extension), excluding the path itself and excluding references built by no target, which abstain rather than disagree. If empty, repeat for the parent directory, up to the source root. Empty everywhere is `PlanError.noSiblings`.
2. Targets = intersection over siblings of their target sets. Extras are counted for the note. An empty intersection is `PlanError.noCommonTarget` listing each distinct target set with its count.
3. `platformFilters`, per chosen target = the single value shared by all siblings' build files in that target, else `PlanError.ambiguousPlatformFilters` listing variants and counts. When no sibling is built by that target (the first file joining a target from its directory), the build file gets no filters, which is what Xcode writes by default.

Each result is wrapped in `Decision(value, source)` where `source` is `.flag`, `.inferred(siblings, directory)`, `.fileType` or `.structure`. `conventions-config` later adds `.config(rule)` between flag and inference without touching planners; the seam is that planners only ever call `Conventions`, never inference directly.

Group membership is deliberately absent from inference: the originating project shows siblings are 38% wrong about it.

### D5. Group for a directory

The source root's group is the main group. For any other directory: find the `PBXGroup`s resolving to it via the model's path index; prefer one that has its own `path` (so a `<group>`-relative child resolves through it), else the first by depth and object order. If none resolves there, take the group for the parent directory (recursively, which may plan its creation) and look among its children for a group named exactly like the directory's basename that has no `path` — the name-only groups Xcode's older projects hold, where every child is spelled against `SOURCE_ROOT`; reuse it rather than planting a second, pathful group of the same name beside it. Otherwise create a group beneath the parent's group: `path = <dirname>; sourceTree = "<group>"` when that parent group resolves to the parent directory, otherwise (the parent is a name-only group) `name = <dirname>; path = <full path>; sourceTree = SOURCE_ROOT`.

The file reference follows the same rule: `<group>` plus basename when the chosen group resolves to the file's directory, else `SOURCE_ROOT` plus the full path, with `name` set to the basename as Xcode writes it.

A new child goes in name order (case-insensitive) when the group's children already are, and last otherwise. A new phase entry goes last; Xcode does not sort `files`.

### D6. File-type table

A static table maps extension → (kind, `lastKnownFileType`), covering what Xcode's new-file templates produce plus common resources. Unknown extensions are an error with a `--phase` hint, never a default; a wrong silent default (a JSON fixture compiled as a source) is worse than a question. With `--phase` given, an unknown extension is written with `lastKnownFileType = file`, which is what Xcode writes for a file it does not recognise. Bundle directories Xcode treats as one file (`.xcassets`, `.scnassets`, `.xcdatamodeld`, …, the list `DiskEntry.bundleExtensions` already holds) pass the "must be a file" check; any other directory fails it.

### D7. Atomic write

Temp file `project.pbxproj.pbxedit-<pid>` in the same directory, `fsync`, `rename(2)`. The original bytes are held in memory for the post-write restore. The temp file is removed in a `defer` on every path.

## Risks / Trade-offs

- [Intersection inference joins too few targets, e.g. misses an extension target] → By design: the note reports it, and `--target` adds it. Joining too many is the worse failure because it can break another platform's build.
- [Ancestor walk infers from an unrelated directory] → The output names the directory inferred from; the walk stops at the first ancestor with any sibling of the same kind.
- [Name-order detection misjudges a nearly sorted group] → Insertion last is always valid; the ordering rule is cosmetic.
- [Post-write verification doubles load time] → Two loads of a 10,000-line file are tens of milliseconds.
- [A name-only group reused by D5 is not the one the user meant] → Only a pathless group named exactly like the directory, directly under the parent directory's group, qualifies; the change list names the group and its ID, and `--dry-run` shows it.

## Migration Plan

None; first mutating command. `docs/design.md` gains `--phase` in the Commands table in this change.

## Evidence

Real `pbxedit add` output against `Tests/Fixtures/add/app.pbxproj` with `App/Views/Bar.swift` on disk (task 7.2), pinned by `AddCommandTests.testDesignEvidenceExamplesAreRealOutput` — exactly, except that the two minted IDs (`D0591B…`, `A2C1C4…` here) are random on every run, so the test masks them and checks the diff's added lines rather than its hunk positions, which follow the IDs' sort order. There is no `README.md` yet; these are the examples for its `add` section, to be moved when the first change creates the file.

```
$ pbxedit add --dry-run App/Views/Bar.swift --project App.xcodeproj
App/Views/Bar.swift
  phase: Sources (file type)
  location: path = Bar.swift; sourceTree = <group>; in group Views (AA0000000000000000000003) (structure)
  targets: App (inferred, 1 sibling in App/Views)
  platformFilters: App: none (inferred, 1 sibling in App/Views)
  created file reference D0591B5336CBE0FF19A69027: file reference for App/Views/Bar.swift (path = Bar.swift; sourceTree = <group>)
  added child to group AA0000000000000000000003: child of group Views (AA0000000000000000000003)
  created build file A2C1C436873BA2E083589590: build file for App
  added phase entry to CC0000000000000000000001: entry in Sources of App (CC0000000000000000000001)
  membership: App (Sources)
--- a/project.pbxproj
+++ b/project.pbxproj
@@ -7,6 +7,7 @@
 	objects = {
 
 /* Begin PBXBuildFile section */
+		A2C1C436873BA2E083589590 /* Bar.swift in Sources */ = {isa = PBXBuildFile; fileRef = D0591B5336CBE0FF19A69027 /* Bar.swift */; };
 		BB0000000000000000000010 /* AppMain.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000110 /* AppMain.swift */; };
 		BB0000000000000000000020 /* Foo.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000120 /* Foo.swift */; };
 		BB0000000000000000000030 /* Shared.swift in Sources */ = {isa = PBXBuildFile; fileRef = AA0000000000000000000130 /* Shared.swift */; };
@@ -56,6 +57,7 @@
 		AA0000000000000000000261 /* F2.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = F2.swift; sourceTree = "<group>"; };
 		AA0000000000000000000270 /* AppKit.h */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.h; path = AppKit.h; sourceTree = "<group>"; };
 		AA0000000000000000000271 /* Kit.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Kit.swift; sourceTree = "<group>"; };
+		D0591B5336CBE0FF19A69027 /* Bar.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Bar.swift; sourceTree = "<group>"; };
 /* End PBXFileReference section */
 
 /* Begin PBXFileSystemSynchronizedRootGroup section */
@@ -119,6 +121,7 @@
 		AA0000000000000000000003 /* Views */ = {
 			isa = PBXGroup;
 			children = (
+				D0591B5336CBE0FF19A69027 /* Bar.swift */,
 				AA0000000000000000000120 /* Foo.swift */,
 			);
 			path = Views;
@@ -379,6 +382,7 @@
 				BB0000000000000000000130 /* OnlyApp.swift in Sources */,
 				BB0000000000000000000140 /* F1.swift in Sources */,
 				BB0000000000000000000141 /* F2.swift in Sources */,
+				A2C1C436873BA2E083589590 /* Bar.swift in Sources */,
 			);
 			runOnlyForDeploymentPostprocessing = 0;
 		};
project.pbxproj: not modified (dry run)
$ echo $?
0
```

The real run prints the same lines without the diff and ends with `project.pbxproj: modified`. Run again, it reuses everything and writes nothing:

```
$ pbxedit add App/Views/Bar.swift --project App.xcodeproj
App/Views/Bar.swift
  phase: Sources (file type)
  targets: App (inferred, 1 sibling in App/Views)
  reused file reference D0591B5336CBE0FF19A69027: file reference App/Views/Bar.swift
  reused build file A2C1C436873BA2E083589590: build file in App
  membership: App (Sources)
project.pbxproj: not modified
```

```
$ pbxedit add --json App/Views/Bar.swift --project App.xcodeproj
{
  "changes" : [
    {
      "action" : "createdFileReference",
      "detail" : "file reference for App/Views/Bar.swift (path = Bar.swift; sourceTree = <group>)",
      "object" : "D0591B5336CBE0FF19A69027",
      "path" : "App/Views/Bar.swift"
    },
    {
      "action" : "addedChild",
      "detail" : "child of group Views (AA0000000000000000000003)",
      "object" : "AA0000000000000000000003",
      "path" : "App/Views/Bar.swift"
    },
    {
      "action" : "createdBuildFile",
      "detail" : "build file for App",
      "object" : "A2C1C436873BA2E083589590",
      "path" : "App/Views/Bar.swift"
    },
    {
      "action" : "addedPhaseEntry",
      "detail" : "entry in Sources of App (CC0000000000000000000001)",
      "object" : "CC0000000000000000000001",
      "path" : "App/Views/Bar.swift"
    }
  ],
  "decisions" : [
    {
      "attribute" : "phase",
      "path" : "App/Views/Bar.swift",
      "source" : {
        "directory" : null,
        "kind" : "fileType",
        "siblings" : null
      },
      "value" : "Sources"
    },
    {
      "attribute" : "location",
      "path" : "App/Views/Bar.swift",
      "source" : {
        "directory" : null,
        "kind" : "structure",
        "siblings" : null
      },
      "value" : "path = Bar.swift; sourceTree = <group>; in group Views (AA0000000000000000000003)"
    },
    {
      "attribute" : "targets",
      "path" : "App/Views/Bar.swift",
      "source" : {
        "directory" : "App/Views",
        "kind" : "inferred",
        "siblings" : 1
      },
      "value" : "App"
    },
    {
      "attribute" : "platformFilters",
      "path" : "App/Views/Bar.swift",
      "source" : {
        "directory" : "App/Views",
        "kind" : "inferred",
        "siblings" : 1
      },
      "value" : "App: none"
    }
  ],
  "diff" : null,
  "dryRun" : false,
  "error" : null,
  "findings" : [

  ],
  "modified" : true,
  "notes" : [

  ],
  "results" : [
    {
      "fileReference" : "D0591B5336CBE0FF19A69027",
      "groupPath" : "App/Views",
      "groups" : [
        "AA0000000000000000000003"
      ],
      "member" : true,
      "memberships" : [
        {
          "buildFile" : "A2C1C436873BA2E083589590",
          "phase" : {
            "id" : "CC0000000000000000000001",
            "name" : "Sources"
          },
          "platformFilters" : [

          ],
          "target" : {
            "id" : "DD0000000000000000000001",
            "name" : "App"
          }
        }
      ],
      "path" : "App/Views/Bar.swift",
      "synchronized" : null
    }
  ],
  "schemaVersion" : 1
}
```
