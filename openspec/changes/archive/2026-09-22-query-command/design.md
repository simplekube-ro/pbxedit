# Design

## Context

`PBXModel` already answers these questions in memory — `membership(of:)`, `fileReferences(at:)`, `parents(of:)`, `resolvedPath(of:)`, `synchronizedRootGroup(covering:)`, `targets(synchronizing:)` — and the CLI skeleton from `integrity-rules-lint` provides `ProjectOptions`, `OutputOptions`, `UsageError`, `CommandOutcome` and the JSON encoder (sorted keys, `null` for absent). This change is a rendering of the membership indexes plus the first handling of user-supplied paths. See proposal.md for motivation.

## Goals / Non-Goals

**Goals**

- A path-argument convention decided once and reused by every later command.
- A JSON shape that is the same object `add`, `remove` and `move` later embed in their own output as "membership after the operation".

**Non-Goals**

- Performance work. Loading dominates; a query is an index lookup.

## Decisions

### D1. Path arguments: cwd-relative in, source-root-relative inside

`PathArgument.resolve(_ raw: String, cwd: String, sourceRoot: String) throws -> String` makes the argument absolute against the current directory (an absolute argument is taken as is), normalizes it lexically with `PBXModel.PathNormalizer` (no symlink resolution, no disk access), and strips the source-root prefix. Everything downstream sees source-root-relative paths only. It lives in `PBXOps` so all commands share it. The source root is `ProjectOptions.sourceRoot(of:)`, the directory holding the `.xcodeproj`; the CLI passes `FileManager.default.currentDirectoryPath` as `cwd`, and `--project` is resolved against the same directory, so the two agree.

An argument that lands outside the source root, or on the source root itself, is `PathArgumentError`, which the CLI reports as a usage error (exit `2`) naming both paths.

Found while applying: `ProjectOptions.locate()` standardizes `--project` with Foundation's `standardizedFileURL`, which drops a leading `/private` from an existing path, while `FileManager.currentDirectoryPath` keeps it — so from `/private/var/…/App/Views`, `Foo.swift` resolved to `/private/var/…` and `../../App.xcodeproj` to `/var/…`, and the two disagreed. `ProjectOptions.currentDirectory` now standardizes the current directory the same way, in one place, so a relative path and a relative or absolute `--project` always agree. `PathArgument` itself stays purely lexical.

*Alternative considered:* always interpret arguments relative to the source root. Rejected: shell completion and agent habits produce cwd-relative paths, and a silent mismatch would surface as "not a member".

Lexical normalization only, because `query` must not touch the disk and because a moved or deleted file still needs to be addressable.

### D2. One `MembershipReport` type

```
MembershipReport { path, member, fileReference?, groupPath?, groups: [ID],
                   memberships: [Entry], synchronized: SynchronizedCoverage? }
Entry               { target: ObjectRef?, phase: ObjectRef?, buildFile: ID, platformFilters: [String] }
ObjectRef           { id: ID, name: String? }
SynchronizedCoverage { group: ID, path: String, targets: [ObjectRef] }
```

Built by `MembershipReport(project:path:)` from a loaded `Project` and a source-root-relative path — a pure function, so a mutating command can build it from its post-edit in-memory model as well as `query` from the file. `Encodable` and `Equatable`, with a hand-written `encode(to:)` so optionals are encoded as `null` rather than omitted; consumers can rely on every key being present. Later commands return `[MembershipReport]` for the paths they touched.

Checked against `add-command` (TODO § 4): its `--json` output embeds "the membership report for each path", its scenarios read `member`, the target name of each membership, and "each object created or reused with its ID" — so the target and the phase are `{id, name}` pairs rather than bare names, and the reference, group and build-file IDs are all in the report. `remove` and `lint --fix` read `member: false` and the memberships' target names; nothing they need is missing.

- `member` is true exactly when a file reference resolves to the path. A reference with no build file (an `.entitlements`) is a member with no memberships.
- `groupPath` is the `name ?? path` of each group from the main group's child down to the reference's first parent, joined by `/`; groups with neither (the main group) contribute nothing, so a child of the main group has the group path `""`. `null` when the reference has no parent. `groups` lists every parent, so an M3 multiplicity is visible.
- One `Entry` per build file × phase listing × owning target; a build file in no phase yields one entry with `phase` and `target` `null`, a phase in no target yields entries with `target` `null`. Ordered by target name, phase name, build file ID, so the output is stable.
- `platformFilters` is always an array: `platformFilters`, else `[platformFilter]` for the single-value form older Xcode wrote, else `[]`.
- When several references resolve to the path (M4), the first in object order is reported; the human renderer's hint covers it.

`TargetMembers(project:target:)` is the `--target` counterpart: `{ target: ObjectRef, members: [Member] }`, `Member { buildFile, fileReference?, path?, phase: ObjectRef, platformFilters }`, one per phase entry, ordered by phase name then path (absent paths last). A file that is not project-relative (an SDK framework) shows as `$(<sourceTree>)/<path>`.

### D3. Exit code `1` for non-members

An agent's verification step is `pbxedit query <file>`; it must fail when the file is not built. A path covered by a synchronized group counts as success because it *is* built. A project file that does not parse or load is exit `2` ("usage or parse error" in `docs/design.md`); only `lint` treats that as a finding.

### D4. Facts, not judgements

A build file with no phase is rendered as a membership with `target: null, phase: null`. `query` does not print rule IDs; the human renderer adds the hint "run `pbxedit lint`" when a report has no group or several, or a membership with no phase or no target.

### D5. Layout

`Sources/PBXOps/Query/PathArgument.swift`, `MembershipReport.swift`, `TargetMembers.swift`; `Sources/pbxedit/Query.swift` holds the subcommand and both renderers. The JSON envelope (`schemaVersion`, `results` or `target` + `members`) is the command's, as `lint`'s is; the report types carry no version of their own.

## Risks / Trade-offs

- [Lexical normalization disagrees with the disk when symlinks are involved, e.g. `/var` vs `/private/var` on macOS] → Accepted. The project file stores lexical paths; matching it lexically is the consistent choice, and `--project` and the paths are resolved against the same current directory. The usage error names both paths so the mismatch is visible. Documented in `--help`.
- [The JSON shape is reused by three later commands, so a mistake here propagates] → `schemaVersion` plus additive-only evolution; reviewed against `add-command`'s needs before this change was applied (D2).

## Evidence

Real output against `Tests/Fixtures/model/app.pbxproj` (task 5.1; there is no `README.md` yet — these are the examples for its `query` section, to be moved when the first change creates the file):

```
$ pbxedit query App/Shared.swift App/Nope.swift --project App.xcodeproj
App/Shared.swift: member
  reference: AA0000000000000000000130
  group: App (AA0000000000000000000002)
  target: App, phase: Sources, build file: BB0000000000000000000030
  target: AppExtension, phase: Sources, build file: BB0000000000000000000040, platforms: ios, maccatalyst
App/Nope.swift: not a member
$ echo $?
1
```

```
$ pbxedit query --json App/Views/Foo.swift --project App.xcodeproj
{
  "results" : [
    {
      "fileReference" : "AA0000000000000000000120",
      "groupPath" : "App/Views",
      "groups" : [
        "AA0000000000000000000003"
      ],
      "member" : true,
      "memberships" : [
        {
          "buildFile" : "BB0000000000000000000020",
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
      "path" : "App/Views/Foo.swift",
      "synchronized" : null
    }
  ],
  "schemaVersion" : 1
}
```

```
$ pbxedit query --target AppTests --project App.xcodeproj
AppTests (DD0000000000000000000003): 2 entries
  Sources: AppTests/Foo/Bar.swift (BB0000000000000000000070)
  Sources: AppTests/Views/FooTests.swift (BB0000000000000000000060)
```
