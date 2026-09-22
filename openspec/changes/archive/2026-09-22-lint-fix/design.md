# Design

## Context

Findings carry rule, object ID and related IDs (`Finding`). Planners produce `Plan`s from steps through `PlanBuilder`, which already answers "is there a group for directory D, including the ones this plan will create" (`group(forDirectory:path:)`, `plannedGroups`) and inserts children in name order (`addChild(_:named:to:)`) — add-command design D5. `OperationRunner` executes, checks, writes atomically and verifies. `Conventions.targets(for:kind:in:)` gives `flags ?? config ?? inference`. `RemovePlanner` has the step shapes for removing a phase entry and deleting a build file. A repair is a function from a finding to steps. See proposal.md for motivation and `docs/design.md` § Severity and repair.

The reference workload is the originating project: about 655 M3 findings, a handful of M1. It is private and never committed; the measured substitute is described under Evidence.

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
                 func plan(_ finding: Finding, conventions: Conventions, builder: inout PlanBuilder) -> FixOutcome }
enum FixOutcome { case planned, notFixable(reason: String) }
```

`RepairPlanner.plan(findings, in:conventions:exemptions:minter:)` runs the fixers over the findings and returns a `RepairPlan`: the `Plan`, the findings repaired, and the findings of a fixable rule that were not, each with its reason. The plan's `Change`s and `Decision`s are keyed by the finding (`"M3 AB12"`) in their `path` field, the way `add` keys them by path argument, so the report can list what was done per finding. `PlanBuilder`'s shared view of planned groups is what makes 95 orphans in one directory produce one new group rather than 95.

### D2. Order: M2, then M1, then M3

M2 deletions first, so M1 never lists a build file that M2 is about to delete. M3 last because it is independent of both. Within a rule, findings are processed in `RuleSet.ordered` order (object ID, then path, then message) so the plan, and therefore the diff, is deterministic.

### D3. M1 target choice reuses add's inference

The build file's file resolves to a path; its kind comes from the file-type table; `Conventions.targets(for:kind:in:)` with empty flags gives config-then-inference. Exactly one target → fixable, and the entry goes to that target's phase for the kind, as `add` would place it. Otherwise `notFixable`, with the reason: no sibling to infer from, no target in common (the variants listed), several configured targets (listed), a target without the phase, a file type the table does not know or one that is never built (a `.plist`), a `productRef` (a package product; its phase is not inferable), or the chosen target already building the file (listing would be an M5). "Several" is deliberately not fixable even though it is a legal membership: one orphaned build file can belong to only one of them, and picking is a guess. A build file listed in more than one phase is not touched either.

A build file in no phase whose `fileRef` (or `productRef`) does not resolve carries no recoverable information except its ID, exactly like the M2 case; it is deleted.

The build file's own `platformFilters` are left as found.

### D4. M3 never touches the reference

Only `addChild`, plus `createGroup` for missing chain links. The reference keeps its `path` and `sourceTree`, so a `SOURCE_ROOT`-spelled reference lands in a group without being re-spelled and resolves exactly as before, whatever its new parent resolves to.

A `<group>`-relative orphan has no chain to resolve through, so the model reports it as resolving relative to the source root. Grouping it keeps its resolved path only when the destination group resolves to the source root — the main group, or a name-only group directly under it — which is the case for a `path` with no directory component. A `<group>`-relative `path` with a directory in it (`App/Legacy/Old.swift`) would resolve to `App/Legacy/App/Legacy/Old.swift` under the group for `App/Legacy`, so the fixer refuses it, naming both paths, and points at `remove` then `add`, which re-spell it. The general rule is one check, made on the destination the builder chose: the reference's `path` joined to the destination's resolved directory must equal its current resolved path.

Not project-relative (`SDKROOT` and the like, or `<absolute>`) or a child of more than one group → `notFixable`. An M3-exempt path is never a finding, so it is never repaired.

### D5. Whole-project before/after comparison

Ordinary operations check scoped to `touched`. A repair compares complete finding sets:

```
before = evaluate(project)            selected = the findings the fixers planned for
after  = evaluate(result)
require  selected ∩ after == ∅   and   after − before == ∅
```

Findings are compared by identity `(rule, object, related)` (`Finding.identity`), never by message. Whole-project evaluation is affordable once per run, and it is the only check that can catch a repair that fixes M3 while creating an M4 — or, for that matter, a new M6 warning; a new finding of either severity aborts, because the spec promises none. Findings that vanish as a side effect (the S2 on a phase whose dangling entry went) are allowed: only appearances and survivors are violations. The scoped check is not merely weaker here, it is wrong: a repair touches phases and groups that may carry unrelated, unfixable damage (the fixture's build file listed in two phases names the very Sources phase an M1 repair adds to), and a scoped check would refuse the whole repair for it.

`OperationRunner.run(_:dryRun:verification:)` takes `Verification`: `.scoped` (default — every shipped command is unchanged) or `.wholeProject(before:selected:)`. The post-write check uses the same mode over the bytes read back, so a repair that reads back differently is caught the same way.

### D6. No batch scope

`typed-project-model` measured the M3 repair shape at scale before this change existed: 700 create-and-add-child repairs on `Alamofire.pbxproj` in a release build take 0.20 s with a query after each (its archived design, Risks), because the model patches its indexes for exactly these mutations. The planner reads the loaded project (one path index, built once), and `Plan.apply` runs the steps on a copy; nothing batches, and nothing needs to. Target: the 655-orphan repair in under two seconds. Measured below.

### D7. Baseline is reported on, not rewritten

`--fix` ignores the baseline while choosing what to repair — baselined damage is damage — and honours it while reporting, as `lint` does: after the repair the remaining findings are filtered through the baseline (the configured default or `--baseline`), the entries that no longer occur are listed as resolved, and a line says how many the repair resolved and that `--write-baseline <path>` rewrites it. The exit code follows `lint`'s rule over the remaining, baselined findings. Rewriting the baseline is a second file modification with its own review implications, so `--fix --write-baseline` is a usage error; keeping it explicit keeps `--fix` to one file. `--dry-run` without `--fix` is a usage error too.

### D8. The report

Human output, in order: each repaired finding (`repaired M3 AB12 <path>: <message>`) with its decisions and changes indented beneath, each remaining finding as `lint` prints it, with `not fixable: <reason>` beneath the ones of a fixable rule, the resolved-baseline lines, the summary (`lint`'s counts plus `N repaired, M not fixable`), the baseline hint, the diff on a dry run, and the `project.pbxproj: modified` line derived from the write, as every mutating command ends. JSON: `lint`'s object plus `modified`, `dryRun`, `repaired` (each finding with its `decisions`, `changes` and `notes`), `remaining` in place of `findings` (each finding plus `reason`, `null` unless it is of a fixable rule and was not repaired), `summary.repaired`, `summary.notFixable`, `diff` and `error`. A verification failure prints the offending findings and exits `1` with nothing written.

## Risks / Trade-offs

- [An M3 repair puts a file into a plausible but unintended group] → The group is the one representing the file's directory — the same place `add` would put it — so repaired files and newly added files end up alike. Visible in `--dry-run`.
- [A large repair diff is hard to review] → The diff has two line shapes only. `docs/design.md`'s adoption plan gates it on unchanged build and test counts on all platforms, and an Xcode open-and-save producing no diff.
- [M2 deletes a build file someone meant to reconnect] → A build file with neither `fileRef` nor `productRef` resolving carries no recoverable information except its ID; the output lists every deletion.
- [Whole-project comparison is defeated by a finding that changes identity] → Identity is (rule, object, related); repairs do not change IDs of existing objects (spec: Existing objects are reused), so identities are stable.
- [The originating project's orphans may be `<group>`-relative with directory paths] → Then `--fix` repairs none of them and names each with the remove-then-add route (D4). The spelling of its orphans is not known here; `lint --fix --dry-run` on the project shows which case it is before anything is written. A `SOURCE_ROOT` orphan — the shape `add` writes under a name-only group, and the shape the `rules/m3-orphan` fixture has — is repaired as measured below.

## Evidence

Placeholders marked **[originating project]** are for the owner to fill in by running the commands on the private project; everything else is measured here.

### Reference-workload substitute (tasks 8.1–8.3)

The originating project (1,719 references, 655 orphans in some thirty directories) is never committed. `RepairPerformanceTests` (`Tests/PBXOpsTests`) builds the closest substitute from the largest corpus file, `Alamofire.pbxproj` (222,891 bytes, 880 objects, 157 references, 29 groups): 655 `SOURCE_ROOT` references are created through the model, in no group, spread over thirty directories — fifteen that existing groups resolve to and fifteen with no group at all — each with a build file in a Sources phase so that it is a built, ungrouped file like the originals. `lint --fix` on the result, through `OperationRunner` in a temporary `.xcodeproj`, is asserted to: write once (`modified` true, no leftover file, one rename); produce a diff whose removed lines are none and whose added lines are all `children` entries or the lines of the fifteen new `PBXGroup` definitions; leave zero M3 findings and no new finding of any rule; keep the file-reference count; pass `plutil -lint`; and finish in under two seconds in a release build (thirty seconds is the debug guard). The class name matches CI's release-mode `--filter PerformanceTests`.

- Release build, Apple silicon, 655 orphans on the Alamofire substitute (502,220 bytes, 2,190 objects, 15 groups created): **load 0.002 s, whole-project evaluation 0.017 s, plan 0.013 s, apply 0.056 s, the runner's execute-check-write-read-back-check 0.105 s — 0.194 s in all** against the 2 s budget (the `SCALE release …` line of `RepairPerformanceTests.testSixHundredFiftyFiveOrphansAreRepairedInOneWrite`; debug build about 4 s). Found on the way: the first measurement was 2.21 s, of which each of the three whole-project evaluations cost 0.69 s, because M1, M2, M5 and M6 asked `project.uniqueObjects.contains(where:)` inside their per-object loops — quadratic, and rebuilding the object array each time. They now skip duplicate IDs with a `seen` set as M3 and M4 already did (`Sources/PBXOps/Rules/MembershipRules.swift`, no behaviour change; every rule test and the corpus test pass unchanged), which brought one evaluation to 0.017 s and makes `lint` itself forty times faster on a project this size.
- **[originating project]** `time pbxedit lint --fix --dry-run --project <path>`: ___ s; M3 before ___, after ___; groups created ___.

### Oracle (task 8.3)

`CLITests.OracleTests` runs `xcodebuild -list -json -project` on the repaired substitute — the same synthesis, done in `CLITests` through the model (`Synthesis.swift`), then `lint --fix` through the binary, 655 errors before and none after — and on the repaired `Tests/Fixtures/repair/app.pbxproj` (exit `1`, six errors remain, the file written), alongside the 31 add/remove/move scenarios; 33 scenarios in all under Xcode 27.0. The `rules/` fixtures are not oracle material: they have no build configuration lists, which `xcodebuild` refuses whatever their membership looks like. **[originating project]** `xcodebuild -list` on the repaired project: ___.

### Examples (task 9.1)

Real `pbxedit lint --fix` output against `Tests/Fixtures/repair/app.pbxproj` (19 errors: 10 repairable, 5 of a repairable rule that are not, 4 S2 of which 3 sit on objects the repair removes), pinned by `LintFixCommandTests.testDesignEvidenceExamplesAreRealOutput` — exactly, except that the three minted group IDs are random per run, so the test masks them. There is no `README.md` yet; this is the "Adopting on an existing project" section for it, to be moved when the first change creates the file.

Adopting on an existing project: see what is wrong, preview the repair, repair, then baseline whatever remains.

```
$ pbxedit lint --project App.xcodeproj
error S2 AA0000000000000000000007 : group AA0000000000000000000007 () refers to DEAD0002 in 'children', which does not exist
…
19 errors, 0 warnings

$ pbxedit lint --fix --dry-run --project App.xcodeproj
repaired M2 BB0000000000000000000405: build file BB0000000000000000000405 in build phase CC0000000000000000000001 (Sources) has a 'fileRef' AA0000000000000000000998 that does not resolve
  removed phase entry from CC0000000000000000000001: entry in Sources of App (CC0000000000000000000001)
  deleted object BB0000000000000000000405: build file whose file does not resolve
repaired M2 CC0000000000000000000007: build phase CC0000000000000000000007 (Sources) lists DEAD0001, which is not a build file
  removed phase entry from CC0000000000000000000007: entry DEAD0001 in Sources of AppKit (CC0000000000000000000007)
repaired M1 BB0000000000000000000400 App/Services/Rate2.swift: build file BB0000000000000000000400 (App/Services/Rate2.swift) is listed in no build phase
  targets: App (inferred, 3 siblings in App/Services)
  added phase entry to CC0000000000000000000001: entry in Sources of App (CC0000000000000000000001)
  note: 1 of 3 siblings in App/Services is also a member of AppExtension; pbxedit add App/Services/Rate2.swift --target AppExtension adds it there too
repaired M1 BB0000000000000000000404: build file BB0000000000000000000404 (AA0000000000000000000999) is listed in no build phase
  deleted object BB0000000000000000000404: build file in no phase whose file does not resolve
repaired M3 AA0000000000000000000406 App/Views/Baz.swift: file reference AA0000000000000000000406 (App/Views/Baz.swift) has no parent group
  added child to group AA0000000000000000000003: child of group Views (AA0000000000000000000003)
repaired M3 AA0000000000000000000407 App/Features/A.swift: file reference AA0000000000000000000407 (App/Features/A.swift) has no parent group
  created group 8F6B39B7BDE875EF56E94F57: group Features for App/Features under App (AA0000000000000000000002)
  added child to group 8F6B39B7BDE875EF56E94F57: child of group Features (8F6B39B7BDE875EF56E94F57)
repaired M3 AA0000000000000000000408 App/Features/C.swift: file reference AA0000000000000000000408 (App/Features/C.swift) has no parent group
  added child to group 8F6B39B7BDE875EF56E94F57: child of group Features (8F6B39B7BDE875EF56E94F57)
repaired M3 AA0000000000000000000409 App/Features/B.swift: file reference AA0000000000000000000409 (App/Features/B.swift) has no parent group
  added child to group 8F6B39B7BDE875EF56E94F57: child of group Features (8F6B39B7BDE875EF56E94F57)
repaired M3 AA0000000000000000000411 README.md: file reference AA0000000000000000000411 (README.md) has no parent group
  added child to group AA0000000000000000000001: child of group main group (AA0000000000000000000001)
repaired M3 AA0000000000000000000413 Tools/Generated/Gen.swift: file reference AA0000000000000000000413 (Tools/Generated/Gen.swift) has no parent group
  created group 142BA5324EEAA0DF4270BB92: group Tools for Tools under main group (AA0000000000000000000001)
  created group B5CD31D1415078315BA05E38: group Generated for Tools/Generated under Tools (142BA5324EEAA0DF4270BB92)
  added child to group B5CD31D1415078315BA05E38: child of group Generated (B5CD31D1415078315BA05E38)
error S2 AA0000000000000000000007 : group AA0000000000000000000007 () refers to DEAD0002 in 'children', which does not exist
error M1 BB0000000000000000000401 App/Mixed/Mixed3.swift: build file BB0000000000000000000401 (App/Mixed/Mixed3.swift) is listed in no build phase
  not fixable: the siblings in App/Mixed have no target in common: App (1), AppExtension (1)
error M1 BB0000000000000000000402 AppTests/Foo/fixture.json: build file BB0000000000000000000402 (AppTests/Foo/fixture.json) is listed in no build phase
  not fixable: no file of the same kind in its directory or any ancestor to infer a target from
error M1 BB0000000000000000000403 App/Views/Twice.swift: build file BB0000000000000000000403 (App/Views/Twice.swift) is listed in 2 build phases: CC0000000000000000000001, CC0000000000000000000004
  not fixable: listed in 2 build phases; which one is right is a human decision
error M3 AA0000000000000000000410 App/Legacy/Old.swift: file reference AA0000000000000000000410 (App/Legacy/Old.swift) has no parent group
  not fixable: its <group>-relative path App/Legacy/Old.swift would resolve to App/Legacy/App/Legacy/Old.swift under the group for App/Legacy; pbxedit remove App/Legacy/Old.swift, then pbxedit add App/Legacy/Old.swift, re-spells it
error M3 AA0000000000000000000412 App/Mixed/Dup.swift: file reference AA0000000000000000000412 (App/Mixed/Dup.swift) has 2 parent groups: AA0000000000000000000015, AA0000000000000000000016
  not fixable: a child of 2 groups, AA0000000000000000000015 and AA0000000000000000000016; which one is right is a human decision
6 errors, 0 warnings, 10 repaired, 5 not fixable
--- a/project.pbxproj
+++ b/project.pbxproj
…
project.pbxproj: not modified (dry run)

$ pbxedit lint --fix --project App.xcodeproj
… the same report without the diff …
6 errors, 0 warnings, 10 repaired, 5 not fixable
project.pbxproj: modified

$ pbxedit lint --write-baseline .pbxedit-baseline.json --project App.xcodeproj
6 errors, 0 warnings
baseline written: .pbxedit-baseline.json (6 entries)
```

The group the created `Features` group is added to is not listed as a change of its own: `created group` names the parent, and the plan's `addChild` of the new group is part of that creation, as it is for `add`. The exit code of both `--fix` runs is `1`, since errors remain; after the baseline is written, `lint` exits `0` with `6 baselined`.
