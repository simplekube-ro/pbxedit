# Tasks

## 1. Planner

- [x] 1.1 Add the fixtures `Tests/Fixtures/remove/app.pbxproj` (the `add/app.pbxproj` project plus the `Features` → `New` → `Thing.swift` chain, `App/App.entitlements` and an already-empty group) and `remove/roots.pbxproj`; write failing planner tests for Complete removal: ordinary file (`App/Services/Rate.swift`), damaged membership (`add/partial.pbxproj`: no phase, no group), project-only file; assert the step list and order, the touched set, and that no identifier token of the serialized result equals a deleted ID
- [x] 1.2 Implement enumeration from indexes and referrers-first step ordering per design D1; verify 1.1 passes and each result passes `plutil -lint`
- [x] 1.3 Write failing tests for the multi-target guard (`App/Services/Cache.swift`: a `PlanError` listing both targets), `--all`, and `rules/m5-double-add.pbxproj` (two build files in one target) bypassing the guard per design D3
- [x] 1.4 Implement the guard and `--all`; verify 1.3 passes

## 2. Detach

- [x] 2.1 Write failing tests for `--target`: shared source detached with the reference and group child intact; last membership detached leaves the reference and emits the "built by no target" note; not a member of the named target is an error listing actual targets; a build file in no phase is left alone
- [x] 2.2 Implement detach per design D4; verify 2.1 passes

## 3. Group pruning

- [x] 3.1 Write failing tests: last file in a two-level chain prunes both groups; siblings present keeps the group; main group and products group are never pruned (`remove/roots.pbxproj`); a group empty before the operation is untouched; several paths in one plan prune their shared directory group once
- [x] 3.2 Implement pruning over the combined plan per design D5; verify 3.1 passes

## 4. Refusals

- [x] 4.1 Write failing tests for the localized-variant refusal (`App/Resources/en.lproj/Localizable.strings`), the synchronized-folder refusal (`App/Generated/User.swift`), the unknown path error, and a file absent from disk still removable
- [x] 4.2 Implement the refusals per design D7; verify 4.1 passes with the project unchanged in each case

## 5. Safety

- [x] 5.1 Write a failing test that `touched` includes former referrers and that a deliberately incomplete plan (stub leaving a phase entry) is rejected by the scoped check with an `M2` finding
- [x] 5.2 Widen the scope per design D6 and add `Plan.deletedObjects` / `Plan.deletedObjectsMentioned(in:)` with the runner's debug assertion; verify 5.1 passes
- [x] 5.3 Write a failing test that the rule set's `S2` and `M2` findings are identical before and after each successful removal scenario, including on fixtures with pre-existing findings; verify it passes

## 6. Command

- [x] 6.1 Write failing CLI tests: exit codes for each scenario (`0`, `1` for refusals, `2` for an unknown target name and `--target` with `--all`), all-or-nothing with one unknown path among three, `--dry-run` diff with bytes unchanged, JSON output listing removed objects by ID and kind, `modified` equal to "bytes differ" over every scenario
- [x] 6.2 Implement the `remove` subcommand, reusing the `add` renderer (moved to `OperationReport`, not forked); verify 6.1 passes
- [x] 6.3 Extend the macOS oracle test to run `xcodebuild -list` on each post-remove fixture; verify it passes

## 7. Documentation

- [x] 7.1 Record real `remove` output in this change's design.md Evidence section (there is no `README.md` yet, as changes 4–6 found) and pin it with a CLI test; update the `remove` row in `docs/design.md`'s Commands table (`--target`/`--all`, empty-group pruning, exit `1` on unknown path, refusals) and the status line
