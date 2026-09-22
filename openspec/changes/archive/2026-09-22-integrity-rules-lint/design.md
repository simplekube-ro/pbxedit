# Design

## Context

`PBXModel` exposes objects, resolved paths and membership with multiplicity preserved (none / one / several). This change turns those observations into judgements and ships the first executable. See proposal.md for motivation and `docs/design.md` § Rules.

## Goals / Non-Goals

**Goals**

- One rule implementation used two ways: whole-project by `lint`, scoped by every mutating command's pre-write check.
- Output stable enough to be a CI contract: deterministic order, versioned JSON.
- A CLI skeleton the later commands slot into without restructuring.

**Non-Goals**

- A plugin system or user-defined rules.
- Per-rule severity overrides. Exemptions by path arrive with `conventions-config`; severity stays fixed.

## Decisions

### D1. A rule is a pure function from model to findings

```
protocol Rule     { var id: RuleID { get }; func evaluate(_ project: Project) -> [Finding] }
protocol DiskRule { var id: RuleID { get }; func evaluate(_ project: Project, disk: any DiskReader) -> [Finding] }
```

Rules hold no state and do not see each other. `RuleSet.evaluate(project, scope:, disk:)` runs all `Rule`s, then the `DiskRule`s when a reader is given, then filters by scope. Filtering after evaluation costs a few milliseconds and removes any chance of a scoped run disagreeing with a full run.

S1 is not a `Rule` over a `Project`, because there is no `Project` until the bytes parse, round-trip and load: `RuleSet.evaluate(bytes:, scope:, disk:)` does those three steps and returns the single S1 finding when one fails — a `ParseError` (with its line and column), a serialization that differs from the input, or a `LoadError` (no `objects`, no resolvable `rootObject`; what `PBXModel` design D8 refuses). `lint` calls the bytes form; a mutating command, which already holds a loaded `Project`, calls the project form.

*Alternative considered:* scope-aware rules that visit only touched objects. Rejected: every rule would need its own notion of "related", and M4/M5 are inherently global.

### D2. Scope matches object or related object

A `Finding` carries `object: ObjectID?` and `related: [ObjectID]`. Scoped evaluation keeps a finding when either intersects the scope. This is what lets `add` fail on an M4 between its new reference and a pre-existing one, while ignoring 600 unrelated M3s. `object` is optional only for D2 (a file on disk that no object names) and for an S5 on a string outside `objects`; every other finding names an object. A finding with no object never matches a scope.

Findings are ordered for output once, in `RuleSet`: errors before warnings, then by rule ID, then by object ID (byte order, the order Xcode sorts sections by), then by path, then by message — so two runs on the same file print the same lines, and the JSON is diffable.

### D3. S5 becomes a warning about canonical quoting

`docs/design.md` states S5 as "quoted if and only if it requires quoting", as an error. `lossless-syntax-tree` D5 established that a bare string with an illegal character cannot parse at all (that is S1), so the only S5 that can occur is a legal but non-canonical spelling — typically a bare hyphen written by another tool. That is harmless to Xcode, so it is a warning. This change updates `docs/design.md` accordingly.

The canonical form is the write-side rule of `lossless-syntax-tree` D5, which lives in `PBXSyntax` as the internal `StringCoding.needsQuoting`. S5 needs it read-only, so `PBXSyntax` gains one public computed property, `StringNode.isCanonicallyQuoted` (`isQuoted == needsQuoting(value)`), tested in `PBXSyntaxTests`; nothing about writing changes. S5 walks every string node in the file — keys and values, inside and outside `objects` — and reports each non-canonical one on the enclosing object (none for a string outside `objects`), with the raw text in the message.

### D4. M6 target roots are inferred

A directory is the *root of target T* when at least 90% of the project-relative files under that top-level directory which are in any Sources phase are in T's. M6 fires for a Sources build file whose file lies under another target's root while that directory is not a root of its own target. The threshold keeps shared-source directories from producing noise: a directory whose files all belong to two targets is a root of both, and neither is flagged. The rule is a warning because inference can be wrong.

"Top-level directory" is the first component of the resolved path; files at the source root, absolute paths and references that are not project-relative take no part. Files are counted once per target, however many build files a target has for them.

### D5. Disk access behind a protocol

`DiskReader` (exists, list directory) is passed only when `--disk` is set. Tests use an in-memory implementation. Rules other than D1/D2 never receive it — they conform to `Rule`, whose `evaluate` has no reader parameter, while D1 and D2 conform to `DiskRule` — which makes "no file-system access without `--disk`" a compile-time property. The reader answers questions about source-root-relative paths; the CLI's implementation is built on the project's source root (the directory holding the `.xcodeproj`).

D1 checks `.relative` and `.absolute` references and skips references that are not project-relative (`SDKROOT`, `BUILT_PRODUCTS_DIR`, …) and every target's `productReference`. D2 lists the directory each group resolves to — that directory only, not its subtree, since a subdirectory without a group is not "inside a directory some group resolves to" — and reports each regular file with a source or resource extension that no file reference resolves to and no synchronized root group covers. The extension list is a fixed table in the rule.

### D6. Baseline format

```json
{ "schemaVersion": 1, "entries": [ { "rule": "M3", "object": "AB12" } ] }
```

Sorted by rule then object, one entry per line, so diffs are reviewable. Keyed by object ID rather than path because IDs survive moves and S/M findings on pathless objects still need a key. A finding with no object (D2, an S5 outside `objects`) keys on its path instead, in the same `object` field. One entry suppresses every finding with that rule and key, so a group with two dangling children is one S2 entry; a baseline is coarse by design, since its job is to freeze old damage, not to describe it.

A baseline that does not parse, or has a `schemaVersion` the tool does not know, is a usage error (exit `2`).

### D7. CLI layout

`Sources/pbxedit/` holds `PbxEdit` (root `ParsableCommand`), `ProjectOptions` (`--project`, discovery), `OutputOptions` (`--json`), and one file per subcommand. Commands do no logic: they call `PBXOps` and render the result. Exit codes are mapped in one place from a `CommandOutcome` enum (`ok`, `violations`, `usage`); a usage error is thrown as a `UsageError` carrying its message, printed to standard error (as JSON with an `error` key under `--json`), and exits `2`.

For `lint`, an unparseable or unloadable project file is the S1 finding and exits `1` like any other error-severity finding, because reporting is `lint`'s job; `docs/design.md`'s "`2` … parse error" is for the commands that need a loaded project to do anything at all. The design doc records this distinction in this change.

The rule set produces findings; the command renders them. Human output is one line per finding — `<severity> <rule> <object or path>: <message>` — then a summary line. JSON output is one object with `schemaVersion`, `project` (the `project.pbxproj` path), `findings` (`rule`, `severity`, `object`, `path`, `related`, `message`; absent values are `null`, never omitted) and `summary` (`errors`, `warnings`, `baselined`, `resolved`), keys sorted, nothing else on standard output.

## Evidence

Recorded at the end of the change (tasks 4.4 and 8.2); `PBXOpsTests.CorpusRuleTests` keeps it as permanent tests.

**Finding counts on the committed corpus** (`pbxedit lint` without `--disk`; `testEveryCorpusFileEvaluatesAndCountsArePrinted` prints this table, `testCommittedCorpusHasNoErrorsExceptTheKnownDefects` pins it):

| File | Findings |
|---|---|
| 22 of the 26 files — Alamofire ×2, CocoaPods-Xcodeproj ×7, Irisin, SnapKit, mlx-swift, Kingfisher ×2, episode-code-samples `Trips`, sqlite-data `Examples`, tuist `AppWithExtensions`, `ProjectWithoutProductsGroup`, `SynchronizedRootGroups`, `TargetWithCustomBuildRules`, `Xcode16-Test`, `Xcode16BuildConfigurations` | clean |
| tuist `FileSharedAcrossTargets` | M4 ×1 — two references (`6C103C07…`, `6CB96501…`) in the same group, both `FileSharedAcrossTargetsTests.swift`; a real defect in the fixture |
| tuist `ProjectWithSwiftPackageTraits` | S3 ×1 — `ViewController.swift`'s build file listed twice in the Sources phase; a real defect |
| tuist `iOS-Project` | S3 ×1 — the same defect (the fixture is a copy) |
| tuist `WithoutWorkspace` | S5 ×234 (warnings) — the one file another tool generated, with bare hyphens and needless quotes throughout; no errors |

So the rule set reports zero errors on every Xcode-written corpus file except three true positives, each checked against the file text, and no warnings on any Xcode-written file. The three tuist fixtures with defects are exactly the ones `PBXSyntaxTests.CorpusTests` records as template-generated by Xcode 8.3–14.3 and then edited by hand.

**"Fresh Xcode template projects" (TODO § 3).** Xcode's templates cannot be instantiated without the GUI, so no freshly generated project was added. The closest committed files are the tuist/XcodeProj fixtures, generated by Xcode 8.3 to 26.1 (`CreatedOnToolsVersion` in `Tests/Fixtures/NOTICE`), including `ProjectWithSwiftPackageTraits` (a Swift package dependency) and `SynchronizedRootGroups` (Xcode 16 synchronized folders): six of them are clean and the other three carry the defects above and nothing else. The gap — no file saved by a fresh Xcode 27 template — remains; a project the owner generates locally can be checked with `pbxedit lint --project`.

**Originating project.** Private, not in the corpus; run locally with `pbxedit lint --project <path>` (or through `PBXEDIT_EXTRA_CORPUS`, which the corpus tests read). Counts to be filled in by the owner:

> *(placeholder — originating project, RandomPlayer)* S1 __, S2 __, S3 __, S4 __, S5 __, M1 __, M2 __, M3 __ (expected ≈ 655), M4 __, M5 __, M6 __; with `--disk`: D1 __, D2 __. Date and commit: __.

**S2 key list.** Extended by the corpus test from the twelve keys the spec first named to the twenty-nine it now names: `containerPortal`, `buildConfigurationList`, `buildConfigurations`, `baseConfigurationReference` (witnessed by `rules/s2-dangling-xcconfig.pbxproj`, since no corpus project uses an xcconfig), `baseConfigurationReferenceAnchor`, `buildRules`, `currentVersion`, `package`, `packageProductDependencies`, `packageReferences`, `fileSystemSynchronizedGroups`, `exceptions`, `remoteRef`, `ProductGroup`, `ProjectRef`, `buildPhase` (in `PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet`) and `TestTargetID` (in `TargetAttributes`). About 6,900 in-file references are checked. `remoteGlobalIDString` is the one ignored key, with its reason in the test.

## Risks / Trade-offs

- [S2's key list misses a reference-bearing key in some object kind] → Add a corpus test that collects every attribute value (at any depth) equal to an ID present in the object table, grouped by key, and fails on a key that is neither in the S2 list nor in an explicit ignore list with a stated reason. The list is extended until the corpus is covered; the spec names the shipped list.
- [M3 exemptions are too narrow for package products or too wide] → The corpus test asserts zero M3 findings on the corpus files that are Xcode-generated template projects with little or no editing (the tuist/XcodeProj fixtures, which `Tests/Fixtures/NOTICE` records with their `CreatedOnToolsVersion`), including `ProjectWithSwiftPackageTraits`, which has a Swift package dependency. Xcode's templates cannot be instantiated without the GUI (`lossless-syntax-tree` design, Risks), so no freshly generated project can be created in this change; the gap is recorded in the Evidence section below.
- [JSON output becomes a contract prematurely] → `schemaVersion` is present from the first release; additive fields do not bump it.
- [M6 false positives] → Warning severity, excluded from the exit code unless `--strict`.
