# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## State of the repository

`pbxedit` is a Swift CLI that manages **file membership** in an Xcode `project.pbxproj` (`add`, `move`, `remove`, `lint [--fix]`, `query`). It is being built through a chain of ten OpenSpec changes against the approved design. Shipped so far: layer 1, `PBXSyntax` (`lossless-syntax-tree`), layer 2, `PBXModel` (`typed-project-model`), the rule set plus `lint` and the CLI skeleton (`integrity-rules-lint`: `Sources/PBXOps/Rules/`, `Sources/pbxedit/`), `query` (`query-command`: `Sources/PBXOps/Query/`), `add` with the Plan/conventions/runner machinery (`add-command`: `Sources/PBXOps/{Plan,Inference,Add}/`), `.pbxedit.yml` with the config layer of `Conventions`, lint exemptions and the baseline default (`conventions-config`: `Sources/PBXOps/Config/`, Yams), `remove` with the shared operation renderer (`remove-command`: `Sources/PBXOps/Remove/`, `Sources/pbxedit/{Remove,OperationReport}.swift`), `move` with directory moves and `--keep-membership` (`move-command`: `Sources/PBXOps/Move/`), `lint --fix` with whole-project verification (`lint-fix`: `Sources/PBXOps/Repair/`, `Sources/pbxedit/RepairReport.swift`), and the Xcode-canonical platform-filter spelling (`platform-filter-canonical-form`: `Sources/PBXOps/Inference/PlatformFilters.swift`, Xcode-saved evidence under `Tests/Fixtures/xcode27/`), all archived under `openspec/changes/archive/`; `openspec list --specs` shows what has landed. `release-distribution` is applied up to the first push (`--version`, the `ORACLE_REQUIRED` oracle mode, `docs/RELEASING.md`, `release.yml`, the `oracle` CI job, the tap formula) and waits on the rehearsal and first releases in `TODO.md` § 10.

- `docs/design.md` — the approved design. Authoritative for architecture, rule IDs and v1 scope. Read it before writing any artifact or code. A change that departs from it updates `docs/design.md` in the same change.
- `TODO.md` — the ordered change chain, the per-change procedure and the checklist. Tick a box only when the step's evidence exists, in the same PR as the change.
- `openspec/config.yaml` — project context and artifact rules injected into every `/opsx:*` skill.
- `openspec/changes/<change>/` — `proposal.md`, `design.md`, `specs/<capability>/spec.md`, `tasks.md`. Archiving a change moves it to `openspec/changes/archive/<date>-<change>/` and syncs its delta into `openspec/specs/<capability>/spec.md`.

## Workflow

Work happens one OpenSpec change at a time, in the order in `TODO.md` (`lossless-syntax-tree` → `typed-project-model` → `integrity-rules-lint` → `query-command` → `add-command` → then `conventions-config`, `remove-command`, `lint-fix` independently → `move-command` after remove → `release-distribution`). Each on a branch named after the change:

1. **Re-verify the artifacts first.** They were all written before any code existed. Read them against what has shipped since (`openspec list --specs`, merged code, `docs/design.md`), fix drift in the artifacts, then `openspec validate <change> --strict`.
2. `/opsx:apply <change>` — test-first, task by task: each behaviour task is preceded by the task that writes its failing test.
3. Verify with `swift build` and `swift test` — **read the test summary, not the exit code**; do not tick a task without it. From `add-command` onward also the oracle tests (`xcodebuild -list` on post-operation fixtures).
4. Reconcile artifacts and `docs/design.md` with what actually shipped, then `/opsx:archive <change>`.

Artifact rules (from `openspec/config.yaml`): one capability per change; proposals carry a "Non-goals" section checked against "Out of scope for v1"; specs cite the rule ID (S1–S5, M1–M6, D1–D2) wherever a requirement implements one; every requirement has a WHEN/THEN scenario concrete enough to become a fixture. Add a regression fixture for any failure in the design's Motivation table that a change touches.

## Commands

```sh
swift build
swift test
swift test --filter PBXSyntaxTests                    # one test target
swift test --filter PBXSyntaxTests.LexerTests/testX   # one test
openspec validate <change> --strict
openspec list --specs
```

`Package.swift` targets Swift 6 language mode, macOS 13+. `swift test -c release --filter PerformanceTests` runs the release-build performance check that CI also runs. `PBXEDIT_EXTRA_CORPUS` names extra `project.pbxproj` files or directories for the corpus tests to run against locally (private projects are never committed).

## Architecture

One SwiftPM package, four layers; each depends only on the one before it.

1. **`PBXSyntax`** — lossless syntax tree for the old-style ASCII plist. Whitespace and comments are trivia attached to tokens. Knows nothing about Xcode. Edits are node insert/remove/replace; a new node copies formatting from a sibling in the same container. Parse errors carry line and column.
2. **`PBXModel`** — a typed *view* over the tree, not a copy. Exact-ID object table; typed accessors only for the kinds the tool mutates (file references, build files, groups, variant groups, build phases, native targets, synchronized root groups); every other `isa` passes through untouched. Derived indexes: file reference → build files → phases → targets; reference → parent group; group → resolved disk path.
3. **`PBXOps`** — pure functions `(model, request, conventions) → Plan`. A Plan is primitive edits plus a human-readable and JSON description. The invariant checker runs on the post-edit model **before** anything is written; a violation among touched objects aborts. `conventions` = sibling inference merged with `.pbxedit.yml` and flags (precedence: flags, config, inference; every decision printed with provenance).
4. **CLI** (`Sources/pbxedit/`) — `--dry-run` prints plan and unified diff; `--json` everywhere. Write is temp-file-then-rename, then the written bytes are re-parsed and re-checked. Exit codes: `0` success or no-op, `1` rule violation or refused operation, `2` usage or parse error.

One rule set (S = structural, M = membership, D = disk) serves both the post-edit checker and `lint`. Rule IDs are defined in `docs/design.md` § Rules.

### Non-negotiables

- `serialize(parse(bytes)) == bytes` for any input that parses. Untouched bytes are never rewritten.
- Object IDs are opaque strings matched **exactly** — never by prefix, never assumed hex. New IDs are 24 hex chars, collision-checked.
- File lookup is by **resolved path, never basename**.
- The tool edits `project.pbxproj` and nothing else on disk.
- The "modified / not modified" output is derived from one fact: whether the bytes on disk were replaced.
- A mutation can never create a new orphan; whether a file gets a group child is never inferred from siblings.
- `lint --fix` never mints an ID for an object that already exists.
- No `fatalError`, `try!` or force unwraps in `Sources/PBXSyntax`; fuzzed input yields a clean round-trip or a located parse error, never a crash.
- Dependencies are `swift-argument-parser` and `Yams` only. A third needs a stated reason in the proposal.

### Testing shape

- Syntax: byte-exact round-trip over a corpus of real project files (`Tests/Fixtures/corpus/`, provenance and licence recorded in `Tests/Fixtures/NOTICE`), plus a seeded mutation fuzzer.
- Operations: fixture project → operation → assertions on the **model**, plus a diff snapshot. Every operation test also asserts the rule set is clean and `plutil -lint` passes.
- Oracle lane (macOS CI): `xcodebuild -list` reads every post-operation fixture.

## Open items that block publishing

Pending the user's decision (see `TODO.md` § 10): the public name (`pbxedit` collides with `ZehMatt/PBXEdit`), the licence, and the Homebrew tap repository.
