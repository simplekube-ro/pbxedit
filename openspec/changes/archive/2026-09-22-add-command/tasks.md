# Tasks

## 1. Plan and executor

- [x] 1.1 Write failing tests for `Plan` execution on the `add/app.pbxproj` fixture: each `Step` kind applied in memory yields the expected model state; a failing step leaves the caller's original `Project` value unchanged, including its queries (a copy's mutation must not patch the original's indexes)
- [x] 1.2 Implement `Plan`, `Step`, `Change`, `Decision`, `PlanBuilder` and the in-memory executor per design D1 — with the copy-on-write cache fix in `PBXModel` if 1.1 shows it is needed; verify 1.1 passes

## 2. Operation runner

- [x] 2.1 Write failing tests for `OperationRunner` with hand-built plans: zero-step plan writes nothing and reports `modified: false`; a plan whose result fails the scoped check writes nothing and returns the findings; a successful plan replaces the file and reports `modified: true`; no temp file remains in any case
- [x] 2.2 Write a failing test injecting a post-write verification failure; assert the original bytes are restored and the outcome is a violation
- [x] 2.3 Implement the pipeline and atomic writer per design D2 and D7; verify 2.1–2.2 pass
- [x] 2.4 Write a failing test for dry-run (unified diff produced, bytes unchanged, same outcome code); implement; verify it passes

## 3. File types and groups

- [x] 3.1 Write failing tests for the file-type table: Swift source, `.xcstrings` resource with `lastKnownFileType`, header, `.entitlements` as project-only, unknown extension as an error
- [x] 3.2 Implement the table per design D6; verify 3.1 passes
- [x] 3.3 Write failing tests for group resolution and creation: pathful chain yields `<group>` plus basename; a name-only group yields `SOURCE_ROOT` plus full path; missing intermediate groups are created under the deepest existing ancestor; sorted groups get in-order insertion
- [x] 3.4 Implement directory-to-group resolution and chain creation per design D5; verify 3.3 passes

## 4. Inference

- [x] 4.1 Write failing tests for the four target-inference scenarios (unanimous, shared siblings with note, empty directory via ancestor, no common target) and the two platform-filter scenarios, asserting the `Decision.source` of each result
- [x] 4.2 Implement `Conventions` per design D4; verify 4.1 passes

## 5. Add planner

- [x] 5.1 Write failing tests for the ensure semantics of design D3: new file; re-add as zero steps; reference with no group and no phase entry completed with existing IDs; second target added without touching the reference
- [x] 5.2 Write failing regression tests, one fixture each, for the `docs/design.md` Motivation failures this change closes: same basename in another target gets its own reference; reuse path gains the group child; build file always gains its phase entry; M4 collision aborts
- [x] 5.3 Implement the add planner, including the synchronized-folder no-op, the missing-phase error and all-or-nothing handling of several paths; verify 5.1–5.2 pass, every resulting fixture passes `plutil -lint`, and the full rule set reports no new findings

## 6. Command

- [x] 6.1 Write failing CLI tests: missing file exits `1` unchanged; `--target`, `--platform`, `--phase` overrides with provenance in output; unknown target exits `2` listing names; JSON shape; one bad path among three leaves bytes unchanged
- [x] 6.2 Write a failing CLI property test over every add scenario above asserting `modified` equals "bytes differ from before the run"
- [x] 6.3 Implement the `add` subcommand and renderers; verify 6.1–6.2 pass

## 7. Oracle and documentation

- [x] 7.1 Add a macOS-only test that runs `xcodebuild -list -json -project` on each post-add fixture and asserts success; verify it passes locally and is skipped cleanly where `xcodebuild` is absent
- [x] 7.2 Update `docs/design.md` (`--phase`, status line, where the write lives) and record real `add` output in this change's design.md Evidence section (there is no `README.md` yet, as `query-command` found); pin the examples with a CLI test that runs them
