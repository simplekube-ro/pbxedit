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
and the disk preconditions (change `move-command`); `lint --fix`, with the
whole-project verification (change `lint-fix`); `--version`, the
`ORACLE_REQUIRED` oracle mode and `docs/RELEASING.md` (change
`release-distribution`; `v1.0.0` released 2026-09-22); the platform-filter
spelling Xcode 27 writes, read and written everywhere (change
`platform-filter-canonical-form`, issue #6, found by the open-and-save
check); `merge`, a semantic three-way merge of one `project.pbxproj` with
its decisions round trip and checks A–F (change `merge-command`, issue #9,
for `v1.1.0`); check C accounting for a leaf that several decided hunks
govern (change `merge-accounting-shared-leaves`, issue #12); `both` offered
for different insertions into one unordered array (change
`merge-both-unordered-insertions`, issue #13); `both` offered for multi-line
objects both sides insert at one place, from the untrimmed union of the two
sides' text (change `merge-both-multiline-objects`, issue #17, for `v1.1.2`);
a conflicting attribute change on a file whose membership theirs changed
asked about instead of resolved to ours in silence (change
`merge-attribute-conflicts-asked`, issue #20); `both` offered for different
links inserted into one Frameworks phase, where the two sides' insertions
reorder nothing base held (change `merge-both-frameworks-links`, issue #21);
`both` refused where the two sides order what they both hold differently in
the files, which the hunk's own texts can hide (change
`merge-both-order-agreement`, issue #24). Issues #20, #21 and #24 shipped
together as `v1.2.0` (2026-09-24). A build file's `settings`, and a spelling
or placement difference the replay leaves, reported as a conflict with both
sides' values when each side changed it (change
`merge-settings-conflicts-named`, issue #28, released as `v1.3.0` 2026-09-24).
An array both sides change and order differently kept in one hunk, so
`ours` or `theirs` yields that side's whole array, and check C refusing any
result that drops an element base, ours and theirs all hold (change
`merge-reorder-whole-array`, issue #32, released as `v1.4.0` 2026-09-24).
A case-only rename accepted by `move` on a case-insensitive volume: when
both paths resolve on disk, the spelling each directory lists decides
(change `move-case-only-rename`, issue #36, released as `v1.5.0`
2026-09-24).

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
| *(pbxedit `v0.1.0`, issue #6)* Every `platformFilters = (ios, );` the tool wrote was rewritten by Xcode 27 on save to `platformFilter = ios;`, a diff on each release check | The tool's own spelling had never been checked against an Xcode save; no corpus file carries a platform filter. Regression: `Tests/Fixtures/xcode27/` |
| *(pbxedit `v1.1.0`, issue #12)* `merge` refused a valid resolution (exit `1`, check C) when two decided hunks governed one array, e.g. both ends of `knownRegions` | Check C took a governed leaf's expectation from one hunk's counterfactual, in which every other hunk is `ours`. Regression: `Tests/Fixtures/merge/shared-array/` |
| *(pbxedit `v1.1.0`, issue #13)* `merge` offered only `ours` or `theirs` when both sides inserted different elements into one unordered array (`knownRegions`, `packageReferences`, group `children`), so every choice lost one side's addition | `both` needed disjoint touched leaves, and an array is one leaf. Regression: `Tests/Fixtures/merge/both-regions/` |
| *(pbxedit `v1.1.1`, issue #17)* `merge` offered only `ours` or `theirs` for a multi-line object both sides added at one place (a Swift package, a group), so two packages added on two branches could not both survive: every combination either lost one or was refused by check A | Zealous trimming cut inside the two objects, so `ours + theirs` did not parse; and it left the base counterfactual holding the trimmed frame twice, so the hunk had no base to compare against at all. Regression: `Tests/Fixtures/merge/both-objects/` |
| *(pbxedit `v1.1.2`, issue #20)* `merge` kept ours' value silently when theirs changed a file's membership and both sides set the same reference or build-file attribute to different values: no question, no residual, nothing owed, all six checks passed — and a unit decided `theirs` was only half applied | The per-path comparison accepted whichever value the result held where both sides had changed the attribute, so no residual existed for the classification or for check E to see; the unit's paths are neutralised before the text merge, so check C never sees the leaf either. Regression: `Tests/Fixtures/merge/attribute-conflict/` |
| *(pbxedit `v1.1.2`, issue #21)* `merge` could not keep both links when two branches each linked a different framework into one target's Frameworks phase: `both` wherever offered failed check A (`M1 … is listed in no build phase`), and every other combination dropped one side's link | The phase's `files` hunk offered `ours` or `theirs` only: `both`'s shared-insertion test excluded a Frameworks phase's `files` by name, though two insertions reorder nothing base held. Regression: `Tests/Fixtures/merge/both-frameworks/` |
| *(pbxedit `v1.2.0`, issue #28, a follow-up to #20)* `merge` reported a build file's `settings` that both sides changed to different values as `conflicting: false` with `ours: null`, so a consumer could not tell it from a change only theirs made, nor show the user the value being kept | The per-path comparison resolved reference and build-file *attributes* three-way but compared `settings`, spelling and placement against theirs' value alone, so #20's conflict test never ran on them. Regression: `Tests/Fixtures/merge/settings-conflict/` |
| *(pbxedit `v1.1.2`, issue #24, found while fixing #21)* `merge` offered `both` where one side had *reordered* an array the other only inserted into, and the decision then exited `1` on check C (`theirs' order of (en, Base, fr, ) is lost`) | `both`'s insertion test read the hunk's counterfactual texts, which zealous trimming can shorten until a reorder looks like an insertion; nothing asked the three files whether the two sides' orders agree. Regression: `Tests/Fixtures/merge/reordered-array/` |
| *(pbxedit `v1.3.0`, issue #32, a follow-up to #24)* `merge` decided `theirs` on a reorder-against-insertion hunk dropped an element all three sides keep (base `(en, Base)`, ours `(Base, en)`, theirs `(en, Base, fr)` gave `(Base, fr)`), exit `0` with every check passed; and a reorder and an insertion that did not overlap line by line exited `1` on check C with nothing to decide | The line merge split ours' move into a clean deletion and a conflicting insertion, so a hunk's choice covered half of it, and check C measured the leaf against that hunk's counterfactual, which already held the deletion. Regression: `Tests/Fixtures/merge/reordered-array/` decided both ways, through the binary and in the merged-project oracle |
| *(pbxedit `v1.4.0`, issue #36)* `move` refused a case-only rename (`Foo.swift` → `foo.swift`) on a case-insensitive volume with "looks like a copy, not a move", exit `1`, and before the rename it gave the same message rather than "move the file on disk first" | The disk precondition asked `FileManager.fileExists`, which folds case on such a volume, so both spellings existed. Regression: `MovePlannerTests` on a case-insensitive `MemoryDisk`, `DiskReaderTests` and `MoveCommandTests` on the real disk |

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
| v1.1 command | `merge` | A conflicted project file was resolved outside pbxedit, exactly where "pbxedit is the only writer of membership" matters most (issue #9); the merge replays membership through the same planners and merges the rest as text |
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
  question is deliberately not a convention. `PlatformFilters`
  (`Sources/PBXOps/Inference/`) holds S4's platform list, the `--platform`
  parser, and the one reading and the one spelling of a build file's filter
  (§ Conventions, "Platform-filter spelling"); `Step.createBuildFile` and
  `MovePlanner` write through it.
- `OperationRunner` (in this layer, called by the CLI) owns everything after
  planning: execute, check, write, verify — the pipeline § 4 describes. Its
  `verification` parameter is `.scoped` for every command but one: the
  errors among the touched objects abort. `lint --fix` passes
  `.wholeProject(before:selected:)`: the complete finding set of the result
  is compared by identity (rule, object, related — `Finding.identity`) with
  the set before, and a selected finding that survives or any finding that
  was absent before, warning included, aborts. The scoped check would be
  wrong for a repair, not just weaker: a touched phase may carry unrelated
  damage no fixer can touch. In a debug build the runner also asserts, once
  the check has passed, that no ID the plan deleted still occurs in the
  result as a whole identifier token (`Plan.deletedObjectsMentioned(in:)`):
  a failure there would be a key missing from S2's list, not a user error.
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
  refills with a new subgroup survives. `Sources/PBXOps/Repair/`
  (`RepairPlanner`) is the planner behind `lint --fix`: one `Fixer` per
  repairable rule turns a finding into steps or into the reason there are
  none, M2 first, then M1, then M3, each rule's findings in report order, so
  two runs plan the same steps; its `RepairPlan` carries the findings
  repaired and the ones left with a reason, and keys the plan's changes and
  decisions by finding (`M3 AB12`) where the commands key them by path.
  The M3 fixer is add's group resolution and nothing else; the M1 fixer is
  add's target inference with the flags empty; the M2 fixer is remove's
  detach steps.
- `Sources/PBXOps/Merge/` is `merge` (the archived `merge-command` design
  has the detail). `MergeEngine` is a pure function of three byte arrays:
  a `MembershipSnapshot` per version (managed references — `<group>` or
  `SOURCE_ROOT`, plain-group parents, not a product, every build file in a
  Sources, Resources or Headers phase — by resolved path, with their rows);
  `MergeUnit.discover` links the paths theirs changed into units by
  reference and build-file ID; `ClassifiedUnit.classify` makes each
  replayed, skipped or a decision, after a trial replay against ours finds
  the *residuals* (build-file `settings`, a group other than the
  directory's, reference attributes) no verb can write, each conflicting
  where both sides changed it; `Neutralise`
  removes every unit path from base and theirs with `RemovePlanner`,
  keeping a group it empties that theirs changed or added;
  `ThreeWay` (Myers' diff, zealous trimming) merges the text into stable
  regions and hunks, which `AnalysedHunk` resolves counterfactually into
  governed `(object ID, key path)` sets; `Replay` takes each unit from what
  the merged file holds to theirs' membership with `MovePlanner`
  (`keepMembership`), `RemovePlanner`, `AddPlanner` (every flag set) and
  `PlanBuilder.rewriteFilters` — the filter rewrite `move` performs,
  extracted so both share it; `MergeChecks` A–F verify before anything is
  written; `MergeDecisions` is the decisions file, bound to the inputs'
  SHA-256 (CryptoKit, a system framework, not a dependency). The checks
  carry a test-only fault seam (`MergeFaults`), so each check's Red test
  disables the step it guards.

### 4. CLI

`add`, `move`, `remove`, `merge`, `lint [--fix]`, `query`.

- `--dry-run` prints the plan and a unified diff, and exits with the code the
  real run would have. `--json` on every command.
- `--version` prints one line and exits `0`: the release version
  (`1.0.0`) from `Sources/pbxedit/Version.swift`, which the release workflow
  sets from the tag and refuses when they disagree; a development build
  prints the next version with `-dev` and, when `PBXEDIT_BUILD_HASH` holds a
  commit hash, `+` and its first seven characters (`1.0.0-dev+0123abc`). A
  release build ignores the variable.
- Write is temp-file-then-rename (`project.pbxproj.pbxedit-<pid>` beside the
  file, `fsync`, `rename(2)`). The written bytes are read back, re-parsed and
  the invariants re-checked over the same scope; a failure restores the
  original bytes. A plan with no steps writes nothing at all.
- The "modified / not modified" line is derived from one fact: whether the
  bytes on disk were replaced — computed once, from the bytes read back.
- Exit codes: `0` success or no-op, `1` rule violation or refused operation,
  `2` usage or parse error, `3` decisions needed (`merge` only). For `lint`, whose job is to report, a file that
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
| `move <from> <to>` | Records a move that has already happened on disk: `<to>` must exist and `<from>` must not (source still present is "move the file on disk first", both present is "looks like a copy; `add` the new file"); those two `exists` questions are the only disk reads, except that when both resolve, as both spellings of one name do on a case-insensitive volume, each path counts only if every directory on it lists its component spelled exactly so, which makes a case-only rename (`Foo.swift` → `foo.swift`) a move. The reference keeps its ID and becomes a child of the group for the destination directory (created as needed; a rename within one directory keeps its listing in place); `path`, `sourceTree`, `name` and — when the extension changes — `lastKnownFileType` are rewritten only where they change, by `add`'s spelling rule, and every comment naming the file follows. Membership follows the destination: targets and `platformFilters` are decided as `add` decides them (`--target`, `--platform`, config, then the destination's siblings, for the file's kind by extension or else by its current phase), the file is detached from targets no longer chosen (as `remove --target`), attached to new ones (as `add`), and retained build files get their filters rewritten; when nothing differs nothing is written for membership, so a same-target move between pathful groups is a two-line diff. `--keep-membership` leaves targets and filters as they were and only notes what the destination's siblings belong to; an inference question at the destination is refused naming both `--target` and `--keep-membership`. A `<from>` no reference resolves to but some resolve beneath is a directory move: every member goes to the corresponding path under `<to>` as one plan, groups for the old tree fall to pruning, files on disk in the destination directories that no member maps to are counted in a note. A `<to>` inside a synchronized folder removes the file's explicit entries (the folder builds it now) and says so. Groups left empty are pruned as `remove` prunes. Exit `1` on the disk preconditions, on a `<from>` not in the project (a `<from>` under a synchronized folder points to `add <to>`), on a `<to>` some reference already resolves to (named), on a child of a variant or version group, and on a synchronized folder beneath a moved directory; `2` on `<from>` equal to `<to>`, on `--keep-membership` with `--target`/`--platform`, or an unknown target. `--dry-run`, `--json` and the output shape are `add`'s, each file's block headed `<from> -> <to>` and keyed by the destination path, plus a `moves` array (`[{from, to}]`) in the JSON |
| `remove <path>…` | The file need not exist on disk; it is never read. Removes every build file of the reference, each from every phase listing it, the reference from every group listing it, and the reference — referrers first, enumerated from the indexes so damaged membership (no phase, no group, two build files in one target) is removed just the same. A `PBXGroup` the removal leaves empty is removed too, up the chain, never the main group or the products group, never a group that was empty before; each is listed. If the reference's build files are owned by several targets, requires `--target <name>` to detach it from that target only — its phase entries go, a build file left in no phase is deleted, the reference and its group child stay, and the output notes when no target builds it any more — or `--all`. Exit `1` on a path no reference resolves to (a typo must not pass silently), on `--target` naming a target the file is not in (listing the ones it is in), on a child of a variant or version group, and on a path covered only by a synchronized folder; `2` on a target name the project does not have or `--target` with `--all`. The pre-write and post-write checks are scoped to the touched objects *and every former referrer* of a deleted one (its groups, phases and their targets), and deleted IDs are searched for as whole tokens in the result. `--dry-run`, `--json` and the output shape are `add`'s |
| `lint` | Runs the rule set; errors before warnings, each ordered by rule then object ID. `--write-baseline <file>` records the current findings (keyed by rule and object ID) and exits 0; `--baseline <file>` reports and fails only on findings not in the baseline, and lists entries that no longer occur as resolved (`lint.baseline` in the config is the default; `--no-baseline` ignores it); `lint.exempt` globs suppress and count findings; `--disk` enables disk rules; `--strict` makes warnings fail. `--fix` repairs what is unambiguous (§ Severity and repair) as one plan and one write through the operation pipeline in whole-project verification, then reports as `lint` would on the result: each repaired finding with its decisions and changes, each remaining finding with `not fixable: <reason>` under the ones of a repairable rule, the summary with `N repaired, M not fixable`, the resolved-baseline lines and a hint to rewrite the baseline with `--write-baseline`, and the `modified` line derived from the write; the exit code is `lint`'s over what remains (baseline honoured for reporting and the exit code, never for choosing what to repair). `--fix --dry-run` adds the unified diff and writes nothing; `--dry-run` alone and `--fix --write-baseline` are usage errors. `--json` carries `modified`, `dryRun`, `repaired`, `remaining` (each with `reason`), `resolved`, `summary` (`lint`'s plus `repaired`, `notFixable`), `diff`, `error` |
| `merge <base> <ours> <theirs>` | A non-interactive three-way merge of three versions of one `project.pbxproj`; the three inputs are only read. The output is `--output <file>`, or else the project's `project.pbxproj` located as every command locates it (none: exit `2`); it may be `<ours>` itself. `.pbxedit.yml`, bound to the located project, is read only for `lint.exempt`; with `--output` alone none is read, and a `--config` with no project to locate is exit `2`. Membership is compared per path — a managed reference's spelling, parent group and rows (target, phase kind, platform filters, build-file `settings`) — and the paths theirs changed are linked into units (both ends of a rename are one unit). A unit is *replayed* when only theirs changed it and the trial replay reproduces theirs, *skipped* when ours already has theirs' membership, else a *decision*: `ours`, `theirs`, or `theirs-membership` in its place when a residual cannot be written, which is then listed as owed. A value of a reference or build file that base, ours and theirs do not agree on — each side changed it, to different values — is a *conflicting* residual, reported with both sides' values: for a value no verb writes (an attribute, a build file's `settings`) whatever the result holds, so it makes the unit a decision offering `ours` and `theirs-membership` whatever its membership, replayed and skipped included; for spelling and placement, which `move` and `add` do write, only where a difference survives the replay, so both sides moving one file to different paths stays a faithful replay. A unit's rows and the presence of a reference are the unit's own question and are never reported as conflicting values. Every unit path is neutralised in base and theirs with `remove`'s planner (a group it empties that theirs changed or added stays, so theirs' change to it merges as text) and the rest is merged line by line; a conflicting hunk is decided `ours`, `theirs`, or `both` when the two sides change disjoint `(object ID, key path)` sets, or share only insertions of different elements into an array whose order means nothing (`buildConfigurations`, `children`, `dependencies`, `exceptions`, `fileSystemSynchronizedGroups`, `files`, `knownRegions`, `membershipExceptions`, `packageProductDependencies`, `packageReferences`, `targets`) and no element twice, by `isa` and identifying fields. A `PBXFrameworksBuildPhase`'s `files` is link order, and is admitted under the same rule: two insertions reorder nothing base held. For every such array the three files must also agree on the order of what both sides hold — the hunk's own texts can make a reorder look like an insertion — so a reorder against an insertion keeps `ours` and `theirs`. Such an array — both sides change it and order what they both hold differently — is kept in one hunk, every change inside its lines joined whether or not they overlap, so `ours` or `theirs` yields that side's whole array: the line merge would otherwise split a move into a clean deletion and a conflicting insertion. `both` takes ours' lines then theirs'; where that text does not qualify — zealous trimming having cut inside a multi-line object both sides added at one place — it takes ours' untrimmed lines then theirs', the frame trimming lifted out written once between them, under the same test. Replay goes through `add`'s, `remove`'s and `move`'s planners only, keeping every surviving reference and build file. Checks before anything is written, exit `1` naming the object and key: (A) no finding neither input had, (B) every target's membership equals the expected, (C) three-way accounting of every leaf keyed by object ID, arrays with their order and never without an element base, ours and theirs all hold, (D) replay isolation, (E) per-path membership, placement and attributes against theirs, a conflicting value among the differences it fails on unless it is owed, (F) no managed membership reached the merge as bytes. Exit `3` lists every open unit and hunk at once, with keys, the three versions' values, the allowed choices and a decisions template bound to the inputs' SHA-256; `--decisions <file>` feeds it back, a stale file, unknown key or refused choice exits `2`. Exit `2` too for an input that does not parse, a target theirs adds or removes or ours removes, or a hunk whose resolutions do not parse. The write is `add`'s, read back with A and B re-run. `--dry-run` adds the unified diff of ours against the merge; `--json` carries `status`, `modified`, `dryRun`, `output`, `inputs`, `units`, `hunks`, `checks`, `owed`, `findings`, `template`, `diff`, `error` |
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
| S4 | `platformFilters` is a plist array of known platform names (`ios`, `maccatalyst`, `macos`, `tvos`, `watchos`, `xros`, `driverkit`), and `platformFilter` — the singular key Xcode writes for a lone `ios` or `maccatalyst` — is one of those two strings. A build file with either key and an allowed value is clean; the legal but non-canonical `platformFilters = (ios, )` is not a finding | error |
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
- `lint --fix`: M1 adds the phase entry when the target is unambiguous — the
  one target `add` would infer for the file with no flags (config, then the
  siblings of its kind), in that target's phase for the file's type — and
  deletes a build file in no phase whose file does not resolve; M2 drops the
  dangling entry, every listing of it, and removes and deletes a build file
  whose file does not resolve; M3 inserts the reference into the group
  matching its resolved path, creating groups as needed, and never re-spells
  it, so a `<group>`-relative orphan is grouped only where its `path` still
  resolves to the same file (a bare basename into the main group; one with a
  directory in it is reported, with `remove` then `add` as the way to
  re-spell it). Everything else of those rules — no or several candidate
  targets, a target without the phase, a target that already builds the
  file, a build file in two phases, a reference with two parents or one that
  is not project-relative — is reported with the reason. Repairs are planned
  M2, then M1, then M3, in report order within a rule, as one plan and one
  write. It never mints an ID for an object that already exists: the only
  objects created are groups. The check is the whole rule set before and
  after, by finding identity: every repaired finding must be gone and no
  finding may appear, or nothing is written. `--fix --dry-run` prints the
  plan and the diff.
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
| `platformFilters` | Per chosen target, must be unanimous among the siblings' build files in that target, otherwise an error asking for `--platform`. When no sibling is built by the target, none — Xcode's default. A sibling's filter is read from either key (see the spelling note below) |
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

**Platform-filter spelling.** `platformFilters` is the attribute's name in
pbxedit's vocabulary — `--platform`, the config key, the decision line, the
JSON arrays — while the file has two keys, and Xcode 27 is particular about
which (measured with Xcode 27.0, `Tests/Fixtures/xcode27/`; change
`platform-filter-canonical-form`): exactly one filter that is `ios` or
`maccatalyst` is written `platformFilter = ios;`, every other non-empty set
`platformFilters = (…);` in the order given, none writes neither key. Reading
is the union: the array when present, else the single key as a one-element
list, else none — one function each, `PlatformFilters.read(from:)` and
`PlatformFilters.spelling(of:)`, used by every reader and writer. A build
file whose value an operation does not change is never re-spelled (the
untouched-bytes rule); one whose value changes ends up with the canonical
spelling and none of the old key. `lint --fix` writes no filter.

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
  fixture (`CLITests.OracleTests`, 36 scenarios over `add`, `remove`, `move`
  and `lint --fix` plus the repaired workload substitute, and three merges:
  both sides adding, a rename, and a `theirs-membership` decision). The suite skips
  where `xcodebuild` is unusable, except under `ORACLE_REQUIRED=1`, which
  the CI `oracle` job sets so it fails instead; that job is a required check
  for merging and for releasing. What it guards is narrower than the name
  suggests: `-list` refuses a project only for top-level damage (an unknown
  `objectVersion`, a dangling `rootObject` or `mainGroup`) and accepts
  object-level corruption that the rule set already refuses before a write
  (measured on Xcode 27; the archived `release-distribution` design has the
  table). Object-level correctness rests on the rule set and on the manual
  open-and-save check; the lane proves Xcode still opens what pbxedit wrote.
- **Merge:** `PBXOpsTests` cover each stage on its own — snapshots, units,
  the line merge (with a 10k-line performance probe), classification,
  neutralisation, hunks, the replay and the trial — and each check A–F on
  synthesised results paired with a clean `lint` on the same result, plus a
  fault-seam Red test per check; `MergeEngineTests` run every spec scenario
  on bytes built from the Xcode-saved fixture and assert on the model,
  check A and `plutil -lint`. `CLITests.MergeCommandTests` run the binary on
  committed three-way fixtures (`Tests/Fixtures/merge/`, generated by a
  test-only recipe that also checks them). `MergePerformanceTests` merges
  the largest corpus file with a conflict under 2 s in a release build.
- **Pre-release, manual:** open a post-operation project in Xcode, save, expect
  no diff — `docs/RELEASING.md` § 2, which records the Xcode version used.
- **Regression fixtures:** one per failure in the Motivation table. The first
  is the prefix-match case: two objects whose IDs are `X` and `X0`.

## Distribution

Universal macOS binary on GitHub Releases, a Homebrew tap, and `swift run` /
Mint from source.

- Releases are built from tags `vMAJOR.MINOR.PATCH` by a workflow that needs
  the `test` and `oracle` checks, checks the tag against `Version.swift`,
  builds `swift build -c release --arch arm64 --arch x86_64`, asserts
  `lipo -archs` lists both architectures and every slice's
  `LC_BUILD_VERSION` has `minos 13.0` (the `Package.swift` minimum), and
  publishes `pbxedit-<version>-macos-universal.tar.gz` with a `.sha256`
  file. Pinned use is `curl` + `shasum -a 256 -c` + `tar`, ten lines of
  shell, documented in the README.
- The tap formula installs the prebuilt binary (no toolchain needed) and its
  test block runs `pbxedit --version`; the release workflow commits the new
  `url`, `sha256` and `version` to the tap.
- Minimum macOS 13, declared in `Package.swift`, stated in the README and
  asserted on the released binary.
- `docs/RELEASING.md` is the procedure: version bump, the manual Xcode
  open-and-save check with the Xcode version recorded, the tag, the
  post-release Homebrew and pinning verification.
- Not notarized: `curl` and Homebrew set no quarantine attribute; revisit if
  users report Gatekeeper prompts. No Linux or Windows binaries.

## Out of scope for v1

- Creating files from templates, or moving and deleting files on disk.
- Synchronized-group exception sets.
- Build settings, schemes, target creation, Swift package references.
- Rules that depend on source-level references (for example "files used by an
  extension target must also join it"); the intersection note surfaces these
  but does not solve them.
- For `merge` (v1.1): git integration — reading index stages, telling a
  merge from a rebase, labelling sides, registering a merge driver; the
  caller extracts the three files. Merging `.pbxedit.yml`, which is outside
  the tool's write scope. A verb for build-file `settings`, for a group
  other than the directory's, or for reference attributes: these stay
  residuals a decision settles. Targets theirs adds or removes.

## Open items

- ~~The name collides with an existing GitHub project, `ZehMatt/PBXEdit`.~~
  Decided 2026-09-22: the name stays `pbxedit`.
- ~~Licence.~~ Decided 2026-09-22: MIT (`LICENSE`); the corpus is MIT
  throughout, so `Tests/Fixtures/NOTICE` is compatible.
