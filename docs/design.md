# pbxedit — design

Status: approved design (2026-09-21). Implemented so far: layer 1, `PBXSyntax`
(change `lossless-syntax-tree`); layer 2, `PBXModel` (change
`typed-project-model`); the rule set in layer 3, `PBXOps`, and the CLI
skeleton with `lint` (change `integrity-rules-lint`); `query`, the
path-argument convention and the `MembershipReport` shape (change
`query-command`); `add`, with the operation machinery every mutating command
shares — `Plan`, `OperationRunner`, sibling inference, `--dry-run` — (change
`add-command`); `.pbxedit.yml`, the config layer of `Conventions`, lint
exemptions and the baseline default (change `conventions-config`); `remove`,
with `--target`/`--all`, empty-group pruning and the widened check scope
(change `remove-command`); `move`, with directory moves, `--keep-membership`
and the disk preconditions (change `move-command`).

## Purpose

`pbxedit` is a command-line tool that manages **file membership** in an Xcode
`project.pbxproj`: adding, moving and removing files, checking the project's
structural integrity, and repairing what it finds. It is aimed at scripts and
coding agents, which need a project edit that is atomic, verifiable and
reported truthfully.

It does not manage build settings, schemes, targets or package dependencies.

## Motivation

The tool replaces a ~1,000-line Ruby script (`add-file.rb`) that edits the
project file with regular expressions over unparsed text. Its recurring
failures share that one root cause:

| Failure | Cause |
|---|---|
| A group ID resolved by *prefix* to a different object (`TVOSTEST0002` won over `TVOSTEST00020`) | Unanchored regex; no object table |
| "project NOT modified" printed on a path that then wrote the file | The message was not derived from the write |
| A `PBXBuildFile` created with no build-phase entry, so tests silently never ran | An add is several independent text inserts; nothing checks the result |
| Reusing an existing file reference skipped the group child | Lookup by basename; no model of group membership |
| Two files with the same basename in different targets: the wrong one compiled | Lookup by basename |
| Moving a file between targets needed four manual edits | No `move` or `remove` operation |

Measured on the originating project: 655 of 1,719 file references (38%) have no
parent group, mixed within the same directories — accumulated damage, not a
convention.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Audience | General-purpose open-source tool | Project conventions move out of code into inference and config |
| Language | Swift | Every user already has the toolchain |
| Parsing | Own **lossless** parser, not tuist/XcodeProj or the CocoaPods gem | Those re-serialize the whole file canonically (large diffs, churn against Xcode) and lag new `objectVersion`s and `isa` kinds. A lossless tree leaves untouched bytes alone and passes unknown objects through |
| v1 commands | `add`, `move`, `remove`, `lint` (with `--fix`), `query` | All are thin layers over one model |
| Conventions | Inferred from sibling files; an optional config file overrides | Zero-config for most projects, self-consistent by construction |
| Disk scope | `project.pbxproj` only | One responsibility; no VCS assumptions; trivially safe to dry-run |

## Architecture

One SwiftPM package, four layers. Each depends only on the one above it in
this list.

### 1. `PBXSyntax` — lossless syntax tree

Parses the old-style ASCII plist: dictionaries, arrays, quoted and bare
strings, data literals, `/* */` and `//` comments. Whitespace and comments are
kept as trivia attached to tokens. It knows nothing about Xcode.

- **Core invariant:** `serialize(parse(bytes)) == bytes` for any input that parses.
- Edits are node insert, remove and replace, addressed by structural path
  (dictionary keys and array indices from the root). Keys match exactly.
- A new node copies its formatting from a sibling in the same container, so
  files with mixed indentation styles stay locally consistent.
- Parse errors carry a line and column. Input is UTF-8; XML and binary
  property lists are rejected by name. Nesting deeper than 64 is an error.
- **Reads what Apple's reader accepts, writes what Xcode writes.** A bare
  string may contain letters, digits and `_ $ / : . -` on read. On write a
  string is left bare only if it is non-empty, uses letters, digits and
  `_ $ / .` only, and contains neither `//` nor `___`; existing strings keep
  their quoting. Checked against every Xcode-written file in the corpus,
  Xcode 27 included; what the corpus cannot show is recorded in design D5 of
  `openspec/changes/archive/2026-09-22-lossless-syntax-tree/design.md`.

### 2. `PBXModel` — typed view over the tree

A view, not a second copy of the data.

- Object table keyed by **exact** ID. IDs are opaque strings; non-hex synthetic
  IDs are valid.
- Typed accessors only for the kinds the tool mutates: `PBXFileReference`,
  `PBXBuildFile`, `PBXGroup`, `PBXVariantGroup`, the build phases,
  `PBXNativeTarget`, `PBXFileSystemSynchronizedRootGroup`. The group view also
  covers `XCVersionGroup` and the target view `PBXAggregateTarget` and
  `PBXLegacyTarget`, because they hold `children` and `buildPhases` and the
  indexes would otherwise be wrong; each view exposes its `isa`.
- Any other `isa` passes through untouched.
- Derived indexes: file reference → build files → phases → targets; file
  reference → parent groups (none, one or several — rules M1, M3 and M5 read
  the multiplicity); group → resolved disk path. **All file lookup is by
  resolved path, never by basename.** Paths are normalized (`.`, `..`, empty
  components, trailing slash) and compared case-sensitively.
- Broken projects load: dangling references, orphans and duplicate entries
  are observable, not errors. Only a missing `objects` or an unresolvable
  `rootObject` refuses to load.
- Primitive mutations — create and delete an object, add and remove a group
  child or a phase entry, set an attribute — place content where Xcode does:
  in the `/* Begin <isa> section */` block for the kind, in ID order when the
  block is sorted, creating and removing blocks as kinds appear and vanish.
  The model never refuses a mutation because the result would violate a rule;
  that is the rule set's job.
- New IDs are 24 hex characters, checked for collision against the table and
  against the session's earlier mints; the random source is replaceable.
- Owns the `/* Name in Sources */` comment text for the entries it writes,
  and refreshes existing comments after a rename. Checked against every
  definition-line comment in the corpus.
- Bulk repairs stay linear: 700 create-and-add-child repairs with a query
  after each take 0.2 s on the largest corpus file in a release build, so
  `lint --fix` needs no batch scope.

### 3. `PBXOps` — operations

Pure functions: `(model, request, conventions[, exemptions]) → Plan`. A Plan is a list of
primitive edits (`Step`: create a file reference, group or build file; add or
remove a child or a phase entry; delete an object; set an attribute; refresh
annotations) plus a human-readable and JSON description: one `Change` per
object created, reused or modified, one `Decision` per attribute decided with
its provenance, and notes. IDs are minted while planning, so the plan names
them.

- The plan is executed on a copy of the model in memory, and the invariant
  checker (below) runs on the result **before** anything is written, scoped to
  the objects the plan touched *or reused*. Any error among them aborts the
  operation; warnings are reported and do not.
- `conventions` is sibling inference merged with the config file and flags.
  Planners only ever ask `Conventions` (`targets(for:)`,
  `platformFilters(for:target:)`, `phase(for:)`); each answer is `flags ??
  config ?? inference` — the config layer (`ConfigConventions`, the `rules`
  of `.pbxedit.yml` re-based to the source root) arrived without planner
  changes. The configuration itself is `Sources/PBXOps/Config/`: `Config`
  (strict decoding over the composed YAML node, with line numbers),
  `ConfigFile` (discovery, the file's directory as the root of its paths),
  `BoundConfig` (bound to a source root; validates target names against the
  loaded project) and `Exemptions` (the `lint.exempt` filter on findings,
  which `RuleSet.evaluate` and `OperationRunner` take). The add planner also
  takes the exemptions (an optional parameter, `nil` without a config): an
  `M3`-exempt path gets a `SOURCE_ROOT` reference and no group child, the
  one place configuration reaches a planner directly, because the group
  question is deliberately not a convention.
- `OperationRunner` (in this layer, called by the CLI) owns everything after
  planning: execute, check, write, verify — the pipeline § 4 describes. In a
  debug build it also asserts, once the scoped check has passed, that no ID
  the plan deleted still occurs in the result as a whole identifier token
  (`Plan.deletedObjectsMentioned(in:)`): a failure there would be a key
  missing from S2's list, not a user error.
- Planners so far: `Sources/PBXOps/Add/` (`AddPlanner`),
  `Sources/PBXOps/Remove/` (`RemovePlanner`, which takes `target`/`all`
  instead of conventions — nothing is inferred for a removal) and
  `Sources/PBXOps/Move/` (`MovePlanner`, which composes the other two: add's
  group resolution and reference spelling from `PlanBuilder`, remove's
  detach and pruning, made internal for it; its `Plan` also carries `moves`,
  the `from`/`to` pairs). All share `PlanBuilder`, `PlanError` and, in the
  CLI, one renderer (`OperationReport`). `MovePlanner` is the one planner
  handed a `DiskReader`: the two `exists` questions of its preconditions run
  before anything is planned, and `files(in:)` counts a directory move's
  unregistered files. Pruning counts the children a plan adds to a group
  (`PlanBuilder.addedChildren`) as remaining, so a group a move empties and
  refills with a new subgroup survives.

### 4. CLI

`add`, `move`, `remove`, `lint [--fix]`, `query`.

- `--dry-run` prints the plan and a unified diff, and exits with the code the
  real run would have. `--json` on every command.
- Write is temp-file-then-rename (`project.pbxproj.pbxedit-<pid>` beside the
  file, `fsync`, `rename(2)`). The written bytes are read back, re-parsed and
  the invariants re-checked over the same scope; a failure restores the
  original bytes. A plan with no steps writes nothing at all.
- The "modified / not modified" line is derived from one fact: whether the
  bytes on disk were replaced — computed once, from the bytes read back.
- Exit codes: `0` success or no-op, `1` rule violation or refused operation,
  `2` usage or parse error. For `lint`, whose job is to report, a file that
  does not parse or load is the S1 finding and exits `1`; `2` is for usage
  errors, a project that cannot be located and a baseline that cannot be read.
  Warnings alone exit `0` unless `--strict`.
- `--project <path>` names the `.xcodeproj` or `project.pbxproj`; without it,
  the project `.pbxedit.yml` names is used, else the single `.xcodeproj` in
  the current directory, and none or several is a usage error. `--config
  <path>` names the configuration file instead of the nearest `.pbxedit.yml`
  (§ Config).
- Path arguments are relative to the current directory, normalized lexically
  (no symlink resolved, nothing read from disk) and matched against the
  source root, the directory holding the `.xcodeproj`. A path outside the
  source root is a usage error. One implementation, `PathArgument` in
  `PBXOps`, serves every command.
- `MembershipReport` (`PBXOps`) is the one description of a path's
  membership: `path`, `member`, `fileReference`, `groupPath`, `groups`,
  `memberships` (each `target` and `phase` as `{id, name}`, `buildFile`,
  `platformFilters`) and `synchronized` (`group`, `path`, `targets`). Absent
  values are `null`, never omitted. `query` prints it; the mutating commands
  embed it as the membership after the operation.

### Commands

| Command | Behaviour |
|---|---|
| `add <path>…` | File must exist on disk (a bundle directory such as `.xcassets` counts as a file). Creates whatever is missing — file reference, group chain, build file, phase entry — as one plan, reusing what exists: re-adding a member is a no-op, never a second ID, and partial membership is completed with the existing objects. `--target <name>` (repeatable) replaces the inferred targets, `--platform <list>|none` the inferred `platformFilters`, `--phase sources|resources|headers|none` the phase the file type implies; an unknown extension needs `--phase`. A path in a synchronized folder is reported as already a member. Output lists each decision with its provenance and each object with its ID; `--json` carries `decisions`, `changes`, `notes`, `findings`, `diff` and the membership report per path |
| `move <from> <to>` | Records a move that has already happened on disk: `<to>` must exist and `<from>` must not (source still present is "move the file on disk first", both present is "looks like a copy; `add` the new file"); those two `exists` questions are the only disk reads. The reference keeps its ID and becomes a child of the group for the destination directory (created as needed; a rename within one directory keeps its listing in place); `path`, `sourceTree`, `name` and — when the extension changes — `lastKnownFileType` are rewritten only where they change, by `add`'s spelling rule, and every comment naming the file follows. Membership follows the destination: targets and `platformFilters` are decided as `add` decides them (`--target`, `--platform`, config, then the destination's siblings, for the file's kind by extension or else by its current phase), the file is detached from targets no longer chosen (as `remove --target`), attached to new ones (as `add`), and retained build files get their filters rewritten; when nothing differs nothing is written for membership, so a same-target move between pathful groups is a two-line diff. `--keep-membership` leaves targets and filters as they were and only notes what the destination's siblings belong to; an inference question at the destination is refused naming both `--target` and `--keep-membership`. A `<from>` no reference resolves to but some resolve beneath is a directory move: every member goes to the corresponding path under `<to>` as one plan, groups for the old tree fall to pruning, files on disk in the destination directories that no member maps to are counted in a note. A `<to>` inside a synchronized folder removes the file's explicit entries (the folder builds it now) and says so. Groups left empty are pruned as `remove` prunes. Exit `1` on the disk preconditions, on a `<from>` not in the project (a `<from>` under a synchronized folder points to `add <to>`), on a `<to>` some reference already resolves to (named), on a child of a variant or version group, and on a synchronized folder beneath a moved directory; `2` on `<from>` equal to `<to>`, on `--keep-membership` with `--target`/`--platform`, or an unknown target. `--dry-run`, `--json` and the output shape are `add`'s, each file's block headed `<from> -> <to>` and keyed by the destination path, plus a `moves` array (`[{from, to}]`) in the JSON |
| `remove <path>…` | The file need not exist on disk; it is never read. Removes every build file of the reference, each from every phase listing it, the reference from every group listing it, and the reference — referrers first, enumerated from the indexes so damaged membership (no phase, no group, two build files in one target) is removed just the same. A `PBXGroup` the removal leaves empty is removed too, up the chain, never the main group or the products group, never a group that was empty before; each is listed. If the reference's build files are owned by several targets, requires `--target <name>` to detach it from that target only — its phase entries go, a build file left in no phase is deleted, the reference and its group child stay, and the output notes when no target builds it any more — or `--all`. Exit `1` on a path no reference resolves to (a typo must not pass silently), on `--target` naming a target the file is not in (listing the ones it is in), on a child of a variant or version group, and on a path covered only by a synchronized folder; `2` on a target name the project does not have or `--target` with `--all`. The pre-write and post-write checks are scoped to the touched objects *and every former referrer* of a deleted one (its groups, phases and their targets), and deleted IDs are searched for as whole tokens in the result. `--dry-run`, `--json` and the output shape are `add`'s |
| `lint` | Runs the rule set; errors before warnings, each ordered by rule then object ID. `--fix` repairs what is unambiguous; `--write-baseline <file>` records the current findings (keyed by rule and object ID) and exits 0; `--baseline <file>` reports and fails only on findings not in the baseline, and lists entries that no longer occur as resolved (`lint.baseline` in the config is the default; `--no-baseline` ignores it); `lint.exempt` globs suppress and count findings; `--disk` enables disk rules; `--strict` makes warnings fail |
| `query <path>…` | Read-only: for each path, whether a file reference resolves to it, its ID, group path and groups, and each membership — target, phase, build file ID, `platformFilters` — or the synchronized group covering it. Facts, not findings: a missing group or phase is reported as such with a hint to run `lint`. Exits `1` when a path is neither a member nor covered, `2` when the project file does not load. `query --target <name>` lists every build-phase entry of a target by phase then path; an unknown name exits `2` listing the targets |

### Synchronized folders

If a path lies inside a `PBXFileSystemSynchronizedRootGroup`, `add` reports
"already a member via synchronized group" and exits 0. Managing membership
exception sets is out of scope for v1.

## Rules

One rule set serves both the post-edit checker and `lint`.

Every finding carries the rule ID, its severity, the offending object's ID
(absent only for a finding about something no object names, such as a D2
file on disk), the object's resolved path when it has one, the IDs of the
related objects, and a message. A rule set run can be scoped to a set of
object IDs: a finding is kept when its object or a related object is in the
set, which is how a mutation's pre-write check ignores pre-existing damage.

### Structural

| ID | Rule | Level |
|---|---|---|
| S1 | The file parses, round-trips byte-for-byte, and loads as a project (has `objects` and a resolvable `rootObject`). When it does not, this is the only finding | error |
| S2 | Every referenced ID exists. The keys checked are the ones that hold object IDs in the corpus: `fileRef`, `productRef`, `children`, `files`, `buildPhases`, `targets`, `mainGroup`, `productRefGroup`, `productReference`, `dependencies`, `target`, `targetProxy`, `containerPortal`, `buildConfigurationList`, `buildConfigurations`, `baseConfigurationReference`, `baseConfigurationReferenceAnchor`, `buildRules`, `currentVersion`, `package`, `packageProductDependencies`, `packageReferences`, `fileSystemSynchronizedGroups`, `exceptions`, `remoteRef`, `ProductGroup`, `ProjectRef`, `buildPhase`, `TestTargetID`. `remoteGlobalIDString` is deliberately not checked: it names an object in the container portal's project. A corpus test fails when a new key holding IDs appears | error |
| S3 | No duplicate object IDs; no ID twice in one `children` or `files` array | error |
| S4 | `platformFilters` is a plist array of known platform names (`ios`, `maccatalyst`, `macos`, `tvos`, `watchos`, `xros`, `driverkit`) | error |
| S5 | A string is quoted exactly when Xcode would quote it (the write-side rule of `PBXSyntax`, § 1). A bare string with an illegal character cannot parse at all — that is S1 — so what remains is a legal but non-canonical spelling, typically a bare hyphen written by another tool; harmless to Xcode, hence a warning | warning |

### Membership

| ID | Rule | Level |
|---|---|---|
| M1 | Every `PBXBuildFile` is in exactly one build phase (the same phase listing it twice is S3) | error |
| M2 | Every build-phase entry names a `PBXBuildFile` whose `fileRef` or `productRef` resolves | error |
| M3 | Every `PBXFileReference` has exactly one parent group (a target's `productReference` is exempt) | error |
| M4 | No two project-relative file references resolve to the same disk path (references under `SDKROOT`, `BUILT_PRODUCTS_DIR` and the like are not compared) | error |
| M5 | No two build files in one phase share a `fileRef` or a `productRef` | error |
| M6 | A source file is in the Sources phase of a target while its path lies under another target's root. A top-level directory is a target's root when the target builds at least 90% of the Sources-phase files under it; a directory can be the root of several targets, and a file in a directory that is a root of its own target is never flagged | warning |

### Disk — warnings, with `lint --disk`

| ID | Rule |
|---|---|
| D1 | A project-relative file reference's resolved path exists (products exempt) |
| D2 | A file with a source or resource extension, directly inside a directory some group resolves to, is referenced or covered by a synchronized group. The finding names the file's path; it has no object |

Without `--disk` the file system is not read beyond the project file: only
D1 and D2 can hold a disk reader, by construction.

### Severity and repair

- A mutation fails on any S or M error among the objects it touched, even in a
  project that already has unrelated findings; a reference a mutation keeps
  and touches (a re-add, a `remove --target`) counts as touched, so a file
  whose own membership is damaged must be repaired or removed whole first. A
  mutation can never create a new orphan.
- `lint --fix`: M1 adds the phase entry when the target is unambiguous; M2
  drops the dangling entry; M3 inserts the reference into the group matching
  its resolved path, creating groups as needed. It never mints an ID for an
  object that already exists. `--fix --dry-run` prints the plan.
- Whether a file gets a group child is **never inferred from siblings**. It is
  always added unless the config exempts the path.

## Conventions

### Sibling inference for `add`

Siblings are file references whose resolved path is in the same directory, of
the same kind (source, resource, header or project-only, by extension) and
built by some target — a file no target builds abstains. If there are none,
walk up to the nearest ancestor directory that has some; none anywhere is an
error asking for `--target`.

| Attribute | Rule |
|---|---|
| Targets | The **intersection** of the siblings' target sets. Targets that only some siblings belong to are reported as a note. An empty intersection is an error listing the variants |
| `platformFilters` | Per chosen target, must be unanimous among the siblings' build files in that target, otherwise an error asking for `--platform`. When no sibling is built by the target, none — Xcode's default |
| `sourceTree` and `path` | Derived structurally, not inferred: the group for a directory is the one resolving to it (preferring one with its own `path`), the source root's being the main group; if none, a name-only group named like the directory under the parent directory's group is reused, else the missing chain is created. A reference under a group that resolves to its directory is `<group>` plus basename; under a name-only group it is `SOURCE_ROOT` plus the full path, with `name`. A created group follows the same rule relative to its parent. A new child goes in name order when the group's children already are, last otherwise |
| Build phase | From the file type: a static extension table, never a default. An unknown extension is an error asking for `--phase`; with `--phase` it is written as `lastKnownFileType = file` |

Precedence: flags, then config, then inference. Every decision is printed with
its provenance, for example `targets: AppTests (inferred, 94 siblings in
AppTests/Views)`, `targets: AppSlowTests (config, rule 1 "AppSlowTests/**")`
or `targets: App (flag)`; in `--json` the decision's `source` carries `kind`
(`flag`, `config`, `exemption`, `inferred`, `fileType`, `structure`) with
`siblings` and `directory` for an inferred one, `rule` and `glob` for a
configured one and `glob` for an exemption (`location: … in no group
(config, exempt M3 "**/Generated/**")`), `null` otherwise. A configured attribute is never inferred, so the
disagreement errors cannot arise for it.

### Config

Optional `.pbxedit.yml`, found by walking up from the current directory, or
named with `--config <path>` on any command. Every path and glob in it is
relative to the directory holding the file, which must be the project's
source root or an ancestor of it (globs are then matched against the path
from that directory: `Sub/App/**` for a project in `Sub/`).

```yaml
# .pbxedit.yml — checked in at the project's source root, or an ancestor of
# it. Every path and glob below is relative to the directory holding this
# file. pbxedit finds it by walking up from the current directory; --config
# names another file.
project: App.xcodeproj               # the default for --project

rules:                               # globs over source-root-relative paths:
                                     # * within a segment, ** across segments, ? one character;
                                     # for each attribute the first matching rule that sets it wins
  - match: "AppSlowTests/**"         # what inference cannot see: the first file of a new directory
    targets: [AppSlowTests]
  - match: "App/tvOS/**"
    platformFilters: [tvos]          # [] means explicitly none; sibling filters are not consulted
  - match: "App/Shared/**"           # settles a directory whose members disagree
    targets: [App, AppExtension]

lint:
  baseline: .pbxedit-baseline.json   # the default for --baseline; --no-baseline ignores it
  exempt:                            # only the rules whose findings carry a path
    M3: ["**/Generated/**"]          # references with no parent group (add creates none there either)
    M6: ["Shared/**"]                # sources built by a target while lying under another target's root
    D1: ["**/*.generated.swift"]     # references whose file is not on disk
    D2: ["Scripts/**"]               # files on disk no reference covers
```

- `project` is used when `--project` is absent; `--project` wins.
- `rules` are matched per attribute: for `targets` and for `platformFilters`
  separately, the first rule in file order that matches the path *and sets
  that attribute* supplies it, so a platform rule and a target rule can
  overlap. Globs: `*` and `?` within one path segment, `**` as a whole
  segment matching zero or more segments; character classes, braces and
  empty segments are rejected.
- `lint.baseline` is the default for `--baseline` unless `--baseline`,
  `--write-baseline` or `--no-baseline` is given.
- `lint.exempt` maps a rule ID to globs. Only `M3`, `M6`, `D1` and `D2` — the
  rules whose findings carry a path — are exemptible; an exempt finding is
  dropped and counted (`0 errors, 0 warnings, 3 exempt`; `summary.exempt` in
  JSON), applied before the baseline and never written into one. Every
  mutating command's pre-write and post-write checks honour the same
  exemptions. An `M3` exemption also tells `add` to create no group child for
  a matching path (§ Severity and repair).
- Validation is strict and runs before any command acts: an unknown key, a
  value of the wrong type, malformed YAML, an unknown platform or rule ID, a
  non-exemptible rule, an unsupported glob, or a target the project does not
  have, exits `2` naming the file, the line and what was expected.

Dependencies: `swift-argument-parser` and `Yams`. Nothing else.

## Testing

Development is test-first.

- **Syntax:** byte-exact round-trip over a corpus of real project files across
  `objectVersion`s 45 to 100 (`Tests/Fixtures/corpus/`; MIT-licensed, each
  pinned to a commit, with provenance and SHA-256 in `Tests/Fixtures/NOTICE`).
  Private projects are never committed; `PBXEDIT_EXTRA_CORPUS` names extra
  files or directories to run the same tests against locally. A seeded
  mutation fuzzer (2,000 iterations by default) must produce either a clean
  round-trip or a located parse error, never a crash.
- **Operations:** fixture project → operation → assertions on the *model*, plus
  a snapshot of the diff. Every operation test also asserts the rule set is
  clean and `plutil -lint` passes.
- **Oracle lane (macOS CI):** `xcodebuild -list` reads every post-operation
  fixture.
- **Pre-release, manual:** open a post-operation project in Xcode, save, expect
  no diff.
- **Regression fixtures:** one per failure in the Motivation table. The first
  is the prefix-match case: two objects whose IDs are `X` and `X0`.

## Distribution

Universal macOS binary on GitHub Releases, a Homebrew tap, and `swift run` /
Mint from source.

## Out of scope for v1

- Creating files from templates, or moving and deleting files on disk.
- Synchronized-group exception sets.
- Build settings, schemes, target creation, Swift package references.
- Rules that depend on source-level references (for example "files used by an
  extension target must also join it"); the intersection note surfaces these
  but does not solve them.

## Open items

- The name collides with an existing GitHub project, `ZehMatt/PBXEdit`
  ("Lightweight Xcode project editor"). Decide before publishing publicly.
- Licence.
