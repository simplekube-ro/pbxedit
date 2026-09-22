# pbxedit — design

Status: approved design (2026-09-21). Implemented so far: layer 1, `PBXSyntax`
(change `lossless-syntax-tree`), and layer 2, `PBXModel` (change
`typed-project-model`).

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

Pure functions: `(model, request, conventions) → Plan`. A Plan is a list of
primitive edits plus a human-readable and JSON description.

- The invariant checker (below) runs on the post-edit model **before** anything
  is written. Any violation among touched objects aborts the operation.
- `conventions` is sibling inference merged with the config file and flags.

### 4. CLI

`add`, `move`, `remove`, `lint [--fix]`, `query`.

- `--dry-run` prints the plan and a unified diff. `--json` on every command.
- Write is temp-file-then-rename. The written bytes are re-parsed and the
  invariants re-checked.
- The "modified / not modified" line is derived from one fact: whether the
  bytes on disk were replaced.
- Exit codes: `0` success or no-op, `1` rule violation or refused operation,
  `2` usage or parse error.

### Commands

| Command | Behaviour |
|---|---|
| `add <path>…` | File must exist on disk. Creates the file reference, group chain, build file and phase entry as one plan. Re-adding an existing member is a no-op, never a second ID |
| `move <from> <to>` | File must already be at `<to>` on disk. Re-parents the reference, rewrites its path, and swaps build-phase membership when the destination implies different targets |
| `remove <path>…` | Removes build files, phase entries, the group child and the reference. If several targets use the reference, requires `--target` to detach one or `--all` |
| `lint` | Runs the rule set. `--fix` repairs what is unambiguous; `--baseline <file>` fails only on new findings; `--disk` enables disk rules |
| `query <path>` | Read-only: targets, phases, `platformFilters`, group path, IDs. Also `query --target <name>` to list members |

### Synchronized folders

If a path lies inside a `PBXFileSystemSynchronizedRootGroup`, `add` reports
"already a member via synchronized group" and exits 0. Managing membership
exception sets is out of scope for v1.

## Rules

One rule set serves both the post-edit checker and `lint`.

### Structural — always errors

| ID | Rule |
|---|---|
| S1 | The file parses and round-trips byte-for-byte |
| S2 | Every referenced ID exists (`fileRef`, `children`, `files`, `buildPhases`, `mainGroup`, `productRef`, target dependencies) |
| S3 | No duplicate object IDs; no ID twice in one `children` or `files` array |
| S4 | `platformFilters` is a plist array of known platform names |
| S5 | A string is quoted if and only if it requires quoting |

### Membership

| ID | Rule | Level |
|---|---|---|
| M1 | Every `PBXBuildFile` is in exactly one build phase | error |
| M2 | Every build-phase entry points to a `PBXBuildFile` whose `fileRef` or `productRef` resolves | error |
| M3 | Every `PBXFileReference` has exactly one parent group (product and package references exempt) | error |
| M4 | No two file references resolve to the same disk path | error |
| M5 | No two build files in one phase share a file reference | error |
| M6 | A source file is in the Sources phase of a target while its path lies under another target's root | warning |

### Disk — warnings, with `lint --disk`

| ID | Rule |
|---|---|
| D1 | A file reference's resolved path exists |
| D2 | A source file under a group's directory is unreferenced and not covered by a synchronized group |

### Severity and repair

- A mutation fails on any S or M error among the objects it touched, even in a
  project that already has unrelated findings. A mutation can never create a
  new orphan.
- `lint --fix`: M1 adds the phase entry when the target is unambiguous; M2
  drops the dangling entry; M3 inserts the reference into the group matching
  its resolved path, creating groups as needed. It never mints an ID for an
  object that already exists. `--fix --dry-run` prints the plan.
- Whether a file gets a group child is **never inferred from siblings**. It is
  always added unless the config exempts the path.

## Conventions

### Sibling inference for `add`

Siblings are file references whose resolved path is in the same directory and
of the same kind (source or resource). If there are none, walk up to the
nearest ancestor directory that has some.

| Attribute | Rule |
|---|---|
| Targets | The **intersection** of the siblings' target sets. Targets that only some siblings belong to are reported as a note. An empty intersection is an error listing the variants |
| `platformFilters` | Must be unanimous among siblings, otherwise an error asking for `--platform` |
| `sourceTree` and `path` | Derived structurally, not inferred: if the destination group chain resolves to the file's directory, `<group>` plus basename; otherwise `SOURCE_ROOT` plus the full path |
| Build phase | From the file type |

Precedence: flags, then config, then inference. Every decision is printed with
its provenance, for example `target: AppTests (inferred, 94 siblings)`.

### Config

Optional `.pbxedit.yml` at the repository root.

```yaml
project: App.xcodeproj
rules:
  - match: "AppSlowTests/**"        # default for empty directories, or an override
    targets: [AppSlowTests]
  - match: "App/tvOS/**"
    platformFilters: [tvos]
lint:
  baseline: .pbxedit-baseline.json
  exempt:
    M3: ["**/Generated/**"]
```

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
