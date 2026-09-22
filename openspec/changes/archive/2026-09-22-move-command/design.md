# Design

## Context

Everything a move needs exists: directory-to-group resolution and structural `path`/`sourceTree` derivation (`PlanBuilder.group(forDirectory:path:)`, `reference(for:in:)` from `add`), membership decisions (`Conventions`), detach and group pruning (`RemovePlanner`), comment refresh (`Project.setAttribute` refreshes the annotations of the object and its build files), the checked write (`OperationRunner`) and one renderer (`OperationReport`). This change is a planner that composes them, plus disk preconditions. See proposal.md for motivation.

## Goals / Non-Goals

**Goals**

- The smallest diff that makes the project true again: two lines for a same-target move between pathful groups.
- One behaviour for the predecessor's "cross-target `git mv`, four manual edits" case.

**Non-Goals**

- Detecting moves from git. The user states `<from>` and `<to>`.
- Moving anything on disk. `git mv` (or Finder) moves the file; `pbxedit move` records it.

## Decisions

### D1. Move is re-path + re-parent + membership delta

Per file, `MovePlanner` computes, in this step order:

1. **Destination group** — add's group resolution for `dirname(to)`, creating the chain if needed. An `M3`-exempt destination (`lint.exempt` in `.pbxedit.yml`) gets no group at all, as `add` gives it none (conventions-config D6).
2. **Reference attributes** — add's structural rule gives the new spelling: `<group>` plus basename and no `name` under a group resolving to the directory; `SOURCE_ROOT`, the full path and `name` under a name-only group. `setAttribute` is emitted only for an attribute whose value changes, `name` included (set when the spelling has one, removed when it has none), and `lastKnownFileType` when the extension changes to one the file-type table knows (never an `explicitFileType`). Attributes go first because `setAttribute` refreshes the annotations of the reference and its build files (model D6), so the group child added in step 3 is written with the new name. The corpus shows the shape this yields for a named reference: every `SOURCE_ROOT` reference with a `name` that Xcode wrote (MLX, Kingfisher, CocoaPods) has `name` equal to the last component of `path`, and a test pins that invariant.
3. **Parents** — `removeChild` from every current parent except the destination group itself, `addChild` to the destination group unless the reference is already its child (a rename within one directory keeps its listing and position). A reference with no parent simply gains one.
4. **Membership delta** — `current` = the targets from the model; `desired` = `Conventions.targets(for: to)` unless `--keep-membership`. Detach `current − desired` with remove's detach steps (`RemovePlanner.detach`, now internal: the target's phase entries go, a build file left in no phase is deleted); attach `desired − current` with add's build-file steps (`createBuildFile` with `Conventions.platformFilters(for: to)`, `addPhaseEntry` in the phase of the file's kind); for `current ∩ desired`, `setAttribute(platformFilters)` when the desired filters differ, on each of that target's build files. The file's kind is `FileTypes.type(of: to)?.kind`, else the kind of the phase its build files are in (a `data.bin` added with `--phase resources` stays a resource); a file with neither has no membership to follow.
5. **Pruning** over the combined plan, from every group that lost a child (`RemovePlanner.prune`, now internal).

The explicit `refreshAnnotations` step the original design listed is not needed: `setAttribute` performs it, and a basename change always changes `path`.

*Alternative considered:* implement as `remove` then `add`. Rejected — new IDs for everything, a diff that hides the rename, and a transient state in which the file is in no target.

### D2. Membership follows the destination by default

The predecessor's documentation shows the failure this avoids: a test moved from the fast to the slow target kept compiling into the fast target because only the path was fixed. Re-deriving membership makes the common intent the default; `--keep-membership` covers reorganizations inside a target where the destination has unusual siblings.

When `current == desired` nothing is emitted for membership, so a plain move stays a two-line diff. With `--keep-membership` the conventions decide nothing; sibling inference is still *consulted* so the output can note that the destination's siblings belong to other targets — an inference error there is swallowed, because "leave it as it was" is the answer either way.

`--target` and `--platform` are accepted as for `add` and take the same precedence over configuration and inference.

### D3. Ambiguity at the destination is an error naming both exits

Inference ambiguity raises the same `PlanError`s as in `add` (`noCommonTarget`, `noSiblings`, `ambiguousPlatformFilters`); `move` appends "or `--keep-membership`" to their remedies through `PlanError.orKeepMembership(_:)`, because for a move "leave it as it was" is always a coherent answer.

### D4. Disk preconditions

The planner takes a `DiskReader` (`FileSystemDiskReader` from the CLI, `MemoryDisk` in tests) and checks, per moved file, `<to>` exists and `<from>` does not, before anything else is planned. These are the only disk reads, and they run under `--dry-run` too, since a dry run reports the exit code the real run would have. Three refusals: `notMovedOnDisk` (source present, destination absent: "move the file on disk first"), `looksLikeACopy` (both present: "use `add` for the new file"), `destinationMissing` (neither present).

Injecting the reader is the one departure from "planners see only the model": the directory-mode decision (D5) needs the project, the per-member disk check needs the member list, and the note about extra files at the destination needs both, so splitting the check into the CLI would duplicate the mapping.

### D5. Directory mode is decided by the project, not the disk

`<from>` is a directory move when no reference resolves to it exactly and at least one resolves beneath it. Members are mapped by replacing the `<from>` prefix with `<to>`, in object order. Files on disk directly inside the destination directories the members map to, which no member maps to, are ignored — adding them is `add`'s job — and counted in one note; `DiskReader.files(in:)` lists one directory, so directories no member lands in are not searched. A synchronized root group whose folder lies beneath `<from>` is a refusal: its `path` would have to change too, and the tool does not edit synchronized groups.

Groups for the old directory tree are not renamed in place; members are re-parented to groups resolved or created for the new tree, and the old groups fall to pruning. This costs a larger diff for a directory rename than an in-place group rename would, but it is one code path with no special cases for pathless groups, groups holding non-member children, or partial moves.

### D6. Into and out of a synchronized folder

Into: planned as remove's complete removal for that file (every target, no `--all` guard — the folder builds it now), with a `synchronized` change naming the group; the membership report afterwards shows the coverage. Out: a `<from>` with no reference under a synchronized folder fails the "something resolves to `<from>`" validation with `PlanError.synchronizedSource`, whose message points to `pbxedit add <to>`.

### D7. Output

`OperationReport` gains an optional label per path: `move` prints `<from> -> <to>` as the header of each file's block, and every decision, change and note is keyed by the destination path, which is also what `results` reports. The JSON object is `add`'s with one more key, `moves` (`[{from, to}]` in plan order); `add` and `remove` keep their ten keys.

## Risks / Trade-offs

- [Default membership swap surprises someone reorganizing files] → Every detach and attach is listed in the output and visible in `--dry-run`; `--keep-membership` is named in the ambiguity message.
- [Directory rename produces a large diff compared with renaming the group in place] → Accepted for v1 (D5). Revisit if users report it; the spec does not forbid an in-place optimisation later since object identity of *groups* is not promised.
- [`name` attribute handling diverges from Xcode's] → No Xcode-written before/after pair of a rename could be obtained non-interactively: Xcode cannot be driven from a test, and the pinned corpus repositories' histories hold no commit in which Xcode renamed such a file (checked with `gh api` on the project-file histories of Alamofire, Kingfisher, mlx-swift and CocoaPods/Xcodeproj). The shape is pinned instead against what Xcode wrote in the corpus (D1 step 2), and the pre-release manual open-and-save check covers the rest.
- [The planner reads the disk] → Only through `DiskReader.exists` and `files(in:)`, only for the paths named, and the reader is injected (D4).

## Evidence

Real `pbxedit move` output against `Tests/Fixtures/move/app.pbxproj` (task 7.1), pinned by `MoveCommandTests.testDesignEvidenceExamplesAreRealOutput` — exactly, except that the one minted build-file ID (`2E3B5F…` here) is random on every run, so the test masks it. There is no `README.md` yet; these are the examples for its `move` section, to be moved when the first change creates the file.

The sequence the command is for — the user moves the file, then records it. Same target, pathful groups on both sides: a two-line diff.

```
$ git mv App/Views/Foo.swift App/Features/Foo.swift
$ pbxedit move --dry-run App/Views/Foo.swift App/Features/Foo.swift --project App.xcodeproj
App/Views/Foo.swift -> App/Features/Foo.swift
  location: path = Foo.swift; sourceTree = <group>; in group Features (AA0000000000000000000017) (structure)
  targets: App (inferred, 3 siblings in App)
  reused file reference AA0000000000000000000120: file reference App/Views/Foo.swift
  removed child from group AA0000000000000000000003: child of group Views (AA0000000000000000000003)
  added child to group AA0000000000000000000017: child of group Features (AA0000000000000000000017)
  reused build file BB0000000000000000000020: build file in App
  note: App/Features/Foo.swift: 1 of 3 siblings in App is also a member of AppExtension; pass --target App --target AppExtension to join it too
  membership: App (Sources)
--- a/project.pbxproj
+++ b/project.pbxproj
@@ -155,7 +155,6 @@
 		AA0000000000000000000003 /* Views */ = {
 			isa = PBXGroup;
 			children = (
-				AA0000000000000000000120 /* Foo.swift */,
 				AA0000000000000000000023 /* Legacy */,
 			);
 			path = Views;
@@ -282,6 +281,7 @@
 		AA0000000000000000000017 /* Features */ = {
 			isa = PBXGroup;
 			children = (
+				AA0000000000000000000120 /* Foo.swift */,
 				AA0000000000000000000018 /* New */,
 			);
 			path = Features;
project.pbxproj: not modified (dry run)
$ echo $?
0
```

The predecessor's "cross-target `git mv`" case (`docs/design.md` Motivation): the reference keeps its ID, the old build file goes, a new one joins the destination's target.

```
$ git mv AppTests/Services/RateTests.swift AppSlowTests/Services/RateTests.swift
$ pbxedit move AppTests/Services/RateTests.swift AppSlowTests/Services/RateTests.swift --project App.xcodeproj
AppTests/Services/RateTests.swift -> AppSlowTests/Services/RateTests.swift
  location: path = RateTests.swift; sourceTree = <group>; in group Services (AA0000000000000000000029) (structure)
  targets: AppSlowTests (inferred, 1 sibling in AppSlowTests/Services)
  platformFilters: AppSlowTests: none (inferred, 1 sibling in AppSlowTests/Services)
  reused file reference AA0000000000000000000310: file reference AppTests/Services/RateTests.swift
  removed child from group AA0000000000000000000027: child of group Services (AA0000000000000000000027)
  added child to group AA0000000000000000000029: child of group Services (AA0000000000000000000029)
  removed phase entry from CC0000000000000000000005: entry in Sources of AppTests (CC0000000000000000000005)
  deleted object BB0000000000000000000180: build file in AppTests
  created build file 2E3B5F674264C02656F0776F: build file for AppSlowTests
  added phase entry to CC0000000000000000000010: entry in Sources of AppSlowTests (CC0000000000000000000010)
  removed child from group AA0000000000000000000005: child of group AppTests (AA0000000000000000000005)
  deleted object AA0000000000000000000027: group Services (AA0000000000000000000027), left empty
  membership: AppSlowTests (Sources)
project.pbxproj: modified
```

The same move with `--keep-membership` leaves the file in `AppTests` and says what it saw:

```
$ pbxedit move --keep-membership AppTests/Services/RateTests.swift AppSlowTests/Services/RateTests.swift --project App.xcodeproj
AppTests/Services/RateTests.swift -> AppSlowTests/Services/RateTests.swift
  location: path = RateTests.swift; sourceTree = <group>; in group Services (AA0000000000000000000029) (structure)
  targets: AppTests (flag)
  reused file reference AA0000000000000000000310: file reference AppTests/Services/RateTests.swift
  removed child from group AA0000000000000000000027: child of group Services (AA0000000000000000000027)
  added child to group AA0000000000000000000029: child of group Services (AA0000000000000000000029)
  reused build file BB0000000000000000000180: build file in AppTests
  removed child from group AA0000000000000000000005: child of group AppTests (AA0000000000000000000005)
  deleted object AA0000000000000000000027: group Services (AA0000000000000000000027), left empty
  note: AppSlowTests/Services/RateTests.swift: membership kept (--keep-membership); the 1 sibling in AppSlowTests/Services belongs to AppSlowTests
  membership: AppTests (Sources)
project.pbxproj: modified
```

Run before the file has moved on disk, or after it has been copied:

```
$ pbxedit move App/Views/Foo.swift App/Features/Foo.swift --project App.xcodeproj
error: App/Views/Foo.swift is still on disk and App/Features/Foo.swift is not; move the file on disk first (pbxedit moves nothing on disk), then run this command
project.pbxproj: not modified
$ echo $?
1
```
