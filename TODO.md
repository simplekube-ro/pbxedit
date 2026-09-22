# TODO — applying the v1 change chain

Ten OpenSpec changes, written 2026-09-21 against `docs/design.md`. Apply them in order; each is independently mergeable. Tick a box only when the step's evidence exists.

Run sessions from this repository so its own `/opsx:*` skills and `openspec/config.yaml` apply.

## Per-change procedure

For each change, on a branch named after it:

1. **Re-verify the artifacts.** They were written before any code existed. Read the change's `proposal.md`, `design.md`, `specs/` and `tasks.md` against what has actually shipped since (`openspec list --specs`, the merged code, `docs/design.md`). Fix drift in the artifacts *before* applying. Then `openspec validate <change> --strict`.
2. **Apply:** `/opsx:apply <change>`. Test-first, task by task.
3. **Verify:** `swift build`, `swift test` — read the summary, not the exit code. From `add-command` onward also the oracle tests (`xcodebuild -list` on post-operation fixtures).
4. **Reconcile:** if what shipped differs from the artifacts or from `docs/design.md`, update them now.
5. **Archive:** `/opsx:archive <change>` — syncs the delta into `openspec/specs/`.
6. **Commit, push, PR, merge.** Tick the box below in the same PR.

## Chain

| # | Change | Capability | Needs |
|---|---|---|---|
| 1 | `lossless-syntax-tree` | `pbx-syntax` | — |
| 2 | `typed-project-model` | `pbx-model` | 1 |
| 3 | `integrity-rules-lint` | `integrity-rules` | 2 |
| 4 | `query-command` | `query` | 2, CLI skeleton from 3 |
| 5 | `add-command` | `add` | 3, 4 |
| 6 | `conventions-config` | `conventions-config` | 5 |
| 7 | `remove-command` | `remove` | 5 |
| 8 | `move-command` | `move` | 7 |
| 9 | `lint-fix` | `integrity-repair` | 5 (honours 6 when present) |
| 10 | `release-distribution` | `distribution` | 3 to start; 9 for `v1.0.0` |

6, 7 and 9 are independent of each other once 5 has merged.

## Checklist

### 1. lossless-syntax-tree
- [x] Artifacts re-verified, `openspec validate --strict` green
- [x] Applied — all tasks ticked (18/18)
- [x] `swift test` summary read; corpus round-trip and fuzzer green (103 tests, 0 failures; 26 corpus files; fuzzer 2,000 iterations in 3.2 s; parse + 100 edits + serialize 7.2 ms median in a release build)
- [x] Open question answered: Xcode 27 canonical quoting set (design D5) — write-side set unchanged; no Xcode-written corpus file contradicts it. No witness either way for `:`, `//` or `___` as the only cause of quoting, nor for Xcode 27 leaving `$` bare; recorded as unknown in D5
- [ ] Archived, merged — archived as `openspec/changes/archive/2026-09-22-lossless-syntax-tree`; not yet merged

### 2. typed-project-model
- [x] Artifacts re-verified, `openspec validate --strict` green — drift fixed: trivia access needed the closing delimiter and key/value annotations too (design D5), the fixture needs three targets for the spec's scenarios, task 7.1 named "the originating project's file from the corpus" which is never committed, and the group/target kinds that share a structural role are recorded (design D1)
- [x] Applied — all tasks ticked (18/18)
- [x] `swift test` green; 700-mutation measurement recorded (110 syntax + 63 model tests, 0 failures; corpus loads and serializes byte for byte through the model, every definition-line comment Xcode wrote agrees with `annotation(for:)`; 700 create-and-add-child repairs on `Alamofire.pbxproj` in a release build: 0.198 s with no queries, 0.202 s with a parent query after each, 0.200 s with a path query after each, against a 1 s limit — **no batch scope needed for change 9**; see the archived design's Risks)
- [ ] Archived, merged — archived as `openspec/changes/archive/2026-09-22-typed-project-model`, delta synced into `openspec/specs/pbx-model/`; not yet merged

### 3. integrity-rules-lint
- [ ] Artifacts re-verified
- [ ] Applied
- [ ] `swift test` green; zero findings on fresh Xcode template projects
- [ ] `docs/design.md` updated: S5 as a warning, `--write-baseline`
- [ ] Finding counts for the originating project recorded in the change's design.md
- [ ] Archived, merged
- [ ] *Milestone:* `pbxedit lint` usable in RandomPlayer CI with a baseline

### 4. query-command
- [ ] Artifacts re-verified — check the `MembershipReport` JSON shape against change 5's needs before applying
- [ ] Applied
- [ ] `swift test` green; read-only test (bytes and mtime) green
- [ ] Archived, merged

### 5. add-command
- [ ] Artifacts re-verified
- [ ] Applied
- [ ] `swift test` green, including the four Motivation regression fixtures and the `modified` property test
- [ ] Oracle tests green on macOS
- [ ] `docs/design.md` updated: `--phase`
- [ ] Archived, merged

### 6. conventions-config
- [ ] Artifacts re-verified
- [ ] Applied
- [ ] `swift test` green; all change-5 tests still green with no planner changes
- [ ] `docs/design.md` § Config reconciled with shipped keys
- [ ] Archived, merged

### 7. remove-command
- [ ] Artifacts re-verified
- [ ] Applied
- [ ] `swift test` green; S2/M2 before/after test green; oracle tests green
- [ ] `docs/design.md` Commands table updated
- [ ] Archived, merged

### 8. move-command
- [ ] Artifacts re-verified
- [ ] Applied
- [ ] `swift test` green, including the cross-target regression and the Xcode-captured rename fixture; oracle tests green
- [ ] `docs/design.md` Commands table updated
- [ ] Archived, merged

### 9. lint-fix
- [ ] Artifacts re-verified — confirm whether change 2's batch scope exists
- [ ] Applied
- [ ] `swift test` green; reference workload (originating project): one write, only `children` lines and new groups in the diff, zero M3 afterwards, under two seconds
- [ ] `xcodebuild -list` reads the repaired originating project
- [ ] Archived, merged
- [ ] *Milestone:* RandomPlayer can do its one-commit orphan repair

### 10. release-distribution
- [ ] (pending-user) Public name decided — `pbxedit` collides with `ZehMatt/PBXEdit`
- [ ] (pending-user) Licence chosen
- [ ] (pending-user) Homebrew tap repository and `TAP_TOKEN` secret created
- [ ] Artifacts re-verified
- [ ] Applied
- [ ] `oracle` job is a required check, and shown to fail on a deliberately bad write
- [ ] `v0.1.0` cut and verified (assets, checksum, `brew install`, pinning snippet)
- [ ] `v1.0.0` cut after change 9; Xcode version for the manual open-and-save check recorded
- [ ] Archived, merged

## After v1 — adoption in RandomPlayer

A separate OpenSpec change in the RandomPlayer repository, closing its issue #632:

- [ ] Pin a pbxedit release by URL and checksum into `.tools/`
- [ ] `scripts/add-file.rb` becomes a shim over `pbxedit add` (keeps `--template`); `--lint` maps to `pbxedit lint`
- [ ] One `pbxedit lint --fix` commit for the ~655 orphans — gated on all-platform builds, unchanged test counts, and an Xcode open-and-save producing no diff
- [ ] `pbxedit lint` in CI or the commit-guard hook
- [ ] After one overlap release: delete the Ruby script and its tests; rewrite `scripts/CLAUDE.md` limitations, including the line calling a missing group child "the convention" for `RandomPlayerTests/Views/*`
