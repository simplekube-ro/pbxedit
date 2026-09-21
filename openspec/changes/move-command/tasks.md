# Tasks

## 1. Single-file planner

- [ ] 1.1 Write failing planner tests for Identity is preserved and The reference follows the file: same-target move (IDs kept, Sources phase untouched), re-parent with group creation, `SOURCE_ROOT` reference re-pathed, reference that had no group gains one
- [ ] 1.2 Write a failing test for the Minimal diff scenario asserting exactly one removed and one added line
- [ ] 1.3 Implement re-parent and re-path by composing add's group resolution and structural derivation per design D1 steps 1–3; verify 1.1–1.2 pass and results pass `plutil -lint`
- [ ] 1.4 Capture a fixture from Xcode's own rename of a file in a pathless group; write a failing test for the Rename in place scenario including `name` attribute handling; implement step 5 and the `name` rule; verify the old basename no longer appears in the file

## 2. Membership delta

- [ ] 2.1 Write failing tests for the four Membership follows the destination scenarios: cross-target (reference ID kept, detach and attach listed), platform directory change (build file ID kept, filter removed), `--keep-membership` with the informational note, ambiguous destination as an error naming `--target` and `--keep-membership`
- [ ] 2.2 Implement the delta per design D1 step 4 and D3, reusing remove's detach steps and add's attach steps; verify 2.1 passes
- [ ] 2.3 Write a failing regression test for the predecessor's "cross-target `git mv`" case from `docs/design.md` Motivation: after the move `pbxedit query` shows the new target only, and the full rule set reports no new findings; verify it passes

## 3. Preconditions and validation

- [ ] 3.1 Write failing tests with the in-memory `DiskReader`: destination missing, source still present, both present (copy message suggesting `add`)
- [ ] 3.2 Write failing tests for project validation: unknown `<from>`, `<to>` already a member (names the reference ID), variant-group child on either side
- [ ] 3.3 Implement preconditions per design D4 and the validations; verify 3.1–3.2 pass with the project file unchanged

## 4. Synchronized folders and pruning

- [ ] 4.1 Write failing tests: move into a synchronized folder removes explicit entries with a note; move out of one fails pointing to `add`
- [ ] 4.2 Write failing tests that the source group is pruned when emptied and kept when it has other children
- [ ] 4.3 Implement per design D6 and wire remove's pruning over the combined plan; verify 4.1–4.2 pass

## 5. Directory moves

- [ ] 5.1 Write failing tests for the Directory rename scenario (five files, two subdirectories, all IDs kept, old groups gone, new groups present) and for one file missing at the destination leaving the project unchanged
- [ ] 5.2 Write a failing test that non-member files under `<to>` are ignored and counted in a note
- [ ] 5.3 Implement directory mode per design D5; verify 5.1–5.2 pass

## 6. Command

- [ ] 6.1 Write failing CLI tests: exit codes per scenario, `--dry-run`, JSON listing old and new path with per-file decisions and changes, `modified` equal to "bytes differ"
- [ ] 6.2 Implement the `move` subcommand and renderers; verify 6.1 passes
- [ ] 6.3 Extend the macOS oracle test to each post-move fixture; verify `xcodebuild -list` succeeds

## 7. Documentation

- [ ] 7.1 Add a `move` section to `README.md` showing the `git mv` then `pbxedit move` sequence with real output; update the `move` row in `docs/design.md` (directory arguments, `--keep-membership`, membership follows destination); verify the examples by running them
