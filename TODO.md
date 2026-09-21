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
- [ ] Artifacts re-verified, `openspec validate --strict` green
- [ ] Applied — all tasks ticked
- [ ] `swift test` summary read; corpus round-trip and fuzzer green
- [ ] Open question answered: Xcode 27 canonical quoting set (design D5)
- [ ] Archived, merged

### 2. typed-project-model
- [ ] Artifacts re-verified
- [ ] Applied
- [ ] `swift test` green; 700-mutation measurement recorded (decides whether a batch scope is needed for change 9)
- [ ] Archived, merged

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
