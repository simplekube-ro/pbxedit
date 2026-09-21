# Tasks

## 1. Planner

- [ ] 1.1 Write failing planner tests on the model fixtures for Complete removal: ordinary file, damaged membership (no phase, no group), project-only file; assert the step list and that the serialized result contains neither deleted ID as text
- [ ] 1.2 Implement enumeration from indexes and referrers-first step ordering per design D1; verify 1.1 passes and each result passes `plutil -lint`
- [ ] 1.3 Write failing tests for the multi-target guard (exit-`1` outcome listing targets), `--all`, and a reference with two build files in one target bypassing the guard per design D3
- [ ] 1.4 Implement the guard and `--all`; verify 1.3 passes

## 2. Detach

- [ ] 2.1 Write failing tests for `--target`: shared source detached with the reference and group child intact; last membership detached leaves the reference and emits the "built by no target" note; not a member of the named target is an error listing actual targets
- [ ] 2.2 Implement detach per design D4; verify 2.1 passes

## 3. Group pruning

- [ ] 3.1 Write failing tests: last file in a two-level chain prunes both groups; siblings present keeps the group; main group and products group are never pruned; a group empty before the operation is untouched; several paths in one plan prune their shared directory group once
- [ ] 3.2 Implement pruning over the combined plan per design D5; verify 3.1 passes

## 4. Refusals

- [ ] 4.1 Add a fixture with a `PBXVariantGroup`; write failing tests for the localized-variant refusal, the synchronized-folder refusal, and the unknown path error with a file absent from disk still removable
- [ ] 4.2 Implement the refusals; verify 4.1 passes with the project file unchanged in each case

## 5. Safety

- [ ] 5.1 Write a failing test that `touched` includes former referrers and that a deliberately incomplete plan (stub leaving a phase entry) is rejected by the scoped check with an `M2` finding
- [ ] 5.2 Widen the scope per design D6 and add the raw-text assertion for deleted IDs; verify 5.1 passes
- [ ] 5.3 Write a failing test that `pbxedit lint` findings for `S2` and `M2` are identical before and after each successful removal scenario; verify it passes

## 6. Command

- [ ] 6.1 Write failing CLI tests: exit codes for each scenario, all-or-nothing with one unknown path among three, `--dry-run` diff with bytes unchanged, JSON output listing removed objects by ID and kind, `modified` equal to "bytes differ"
- [ ] 6.2 Implement the `remove` subcommand and renderers; verify 6.1 passes
- [ ] 6.3 Extend the macOS oracle test to run `xcodebuild -list` on each post-remove fixture; verify it passes

## 7. Documentation

- [ ] 7.1 Add a `remove` section to `README.md` from real output, and update the `remove` row in `docs/design.md`'s Commands table (empty-group pruning, exit `1` on unknown path); verify the examples by running them
