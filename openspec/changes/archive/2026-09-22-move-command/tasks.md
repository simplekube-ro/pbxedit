# Tasks

Every planner test applies the plan, asserts on the model, asserts the rule set is clean over the touched objects (and the whole project where the fixture starts clean), and runs `plutil -lint` on the output. All against `Tests/Fixtures/move/app.pbxproj`.

## 1. Single-file planner

- [x] 1.1 Write failing planner tests for Identity is preserved and The reference follows the file: same-target move (IDs kept, Sources phase untouched), re-parent with group creation, `SOURCE_ROOT` reference re-pathed into a name-only group, `SOURCE_ROOT` reference rewritten to `<group>` under a pathful group, reference that had no group gains one
- [x] 1.2 Write a failing test for the Minimal diff scenario asserting exactly one removed and one added line
- [x] 1.3 Implement re-path and re-parent by composing add's group resolution and spelling per design D1 steps 1–3; verify 1.1–1.2 pass and results pass `plutil -lint`
- [x] 1.4 Write a failing test for the Rename in place and Rename of a named reference scenarios (old basename gone from the file, `name` follows the basename, the in-place listing kept), plus a corpus test pinning that every Xcode-written `SOURCE_ROOT` reference with a `name` has `name == basename(path)`; implement the `name` rule; record in design D1 that no Xcode-captured rename fixture could be obtained non-interactively

## 2. Membership delta

- [x] 2.1 Write failing tests for the four Membership follows the destination scenarios: cross-target (reference ID kept, detach and attach listed, decision with provenance), platform directory change (build file ID kept, filter removed), `--keep-membership` with the informational note, ambiguous destination as an error naming `--target` and `--keep-membership`
- [x] 2.2 Implement the delta per design D1 step 4 and D3, reusing remove's detach steps and add's attach steps; verify 2.1 passes
- [x] 2.3 Write a failing regression test for the predecessor's "cross-target `git mv`" case from `docs/design.md` Motivation: after the move the membership report shows the new target only, and the full rule set reports no new findings; verify it passes

## 3. Preconditions and validation

- [x] 3.1 Write failing tests with the in-memory `MemoryDisk`: destination missing, source still present, both present (copy message suggesting `add`)
- [x] 3.2 Write failing tests for project validation: unknown `<from>`, `<to>` already a member (names the reference ID), variant-group child on either side
- [x] 3.3 Implement preconditions per design D4 and the validations; verify 3.1–3.2 pass with the project unchanged

## 4. Synchronized folders and pruning

- [x] 4.1 Write failing tests: move into a synchronized folder removes explicit entries with a change naming the group; move out of one fails pointing to `add`
- [x] 4.2 Write failing tests that the source group is pruned when emptied and kept when it has other children
- [x] 4.3 Implement per design D6 and wire remove's pruning over the combined plan; verify 4.1–4.2 pass

## 5. Directory moves

- [x] 5.1 Write failing tests for the Directory rename scenario (five files, `Legacy`, `Legacy/A`, `Legacy/B`; all IDs kept, old groups gone, new groups present) and for one file missing at the destination leaving the project unchanged
- [x] 5.2 Write failing tests that non-member files in the destination directories are ignored and counted in a note, and that a synchronized folder beneath `<from>` is refused
- [x] 5.3 Implement directory mode per design D5; verify 5.1–5.2 pass

## 6. Command

- [x] 6.1 Write failing CLI tests: exit codes per scenario, `--dry-run`, JSON with `moves` listing old and new path and per-file decisions and changes, `modified` equal to "bytes differ" over every scenario
- [x] 6.2 Implement the `move` subcommand and the renderer's label and `moves`; verify 6.1 passes
- [x] 6.3 Extend the macOS oracle test to each post-move fixture; verify `xcodebuild -list` succeeds

## 7. Documentation

- [x] 7.1 Record real `pbxedit move` output (the `git mv` then `pbxedit move` sequence) in this change's design.md Evidence, pinned by a CLI test, as changes 4–7 did in the absence of a `README.md`; update the `move` row in `docs/design.md` (directory arguments, `--keep-membership`, membership follows destination, disk preconditions, refusals) and § Architecture 3
