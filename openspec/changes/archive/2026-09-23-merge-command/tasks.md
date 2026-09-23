# Tasks

Every engine test runs `MergeEngine` on bytes built from `Tests/Fixtures/xcode27/platform-filters-after-xcode27-save.pbxproj`, asserts on the model of the result, asserts check A's relative rule set is clean, and runs `plutil -lint` on the serialized result. "Verify" means reading the `swift test` summary, not the exit code.

## 1. Contract the merge relies on (`add` delta)

- [x] 1.1 Write `AddPlannerTests` for "A second add with another platform set extends membership" and "A reused build file keeps its filter" on `add/app.pbxproj`; they document shipped behaviour, so verify they pass as written (a failure here is a bug to fix before going on)

## 2. Values and the line merge

- [x] 2.1 Write failing `PlistValueTests`: a tree read without trivia; `leaves` keys `objects/<ID>/buildSettings/<KEY>` for every `XCBuildConfiguration` of the base; arrays as one ordered leaf; first entry wins on a duplicate key; a duplicate-key counter
- [x] 2.2 Implement `PlistValue` and `leaves` (design D8); verify 2.1 passes
- [x] 2.3 Write failing `LineMergeTests`: Myers diff edit scripts on small cases and on the base against itself (empty); three-way regions — unchanged, one side, identical on both, overlapping change (hunk), same-position insertions (hunk), adjacent replacements (clean), a deletion against a change (hunk); zealous trimming of a hunk's common first and last lines; determinism across runs; 10k-line inputs merge in under 100 ms in a release build
- [x] 2.4 Implement `LineDiff` and `ThreeWay` (design D6); verify 2.3 passes

## 3. Snapshots and units

- [x] 3.1 Write failing `MembershipSnapshotTests` on the base: managed references by path with spelling, parents, `groupPath`, attributes; rows for Sources, Resources and Headers with filters from either key and `settings` (`AppKit/AppKit.h`'s `ATTRIBUTES`); not managed: the `SDKROOT` framework, products, the `en` variant child, anything in `App/Generated`; masked states equal across two versions that differ only in IDs
- [x] 3.2 Implement `MembershipSnapshot` (design D2); verify 3.1 passes
- [x] 3.3 Write failing `UnitTests`: a rename is one unit of two paths (spec "Rename is one unit"); ours' rename of a path theirs removes joins the same unit; `App/Notes.md` added with no build file is a unit ("A file no target builds"); the `SDKROOT` `Combine.framework` and its Frameworks build file are no unit ("Unmanaged changes are not units"); re-created IDs with an equal masked state are a unit; unit keys are stable across runs and change when a version's state changes
- [x] 3.4 Implement unit discovery and keys (design D3); verify 3.3 passes

## 4. Replay

- [x] 4.1 Write failing `MovePlannerTests` guard: the filter-rewrite tests of `platform-filter-canonical-form` still pass after the rewrite moves into `PlanBuilder.rewriteFilters` (run them before and after; no expectation changes)
- [x] 4.2 Extract `PlanBuilder.rewriteFilters(of:to:path:)` from `MovePlanner.planMembership`; verify 4.1 and the whole `MovePlannerTests` suite pass unchanged
- [x] 4.3 Write failing `ReplayTests`, transitions applied to the base as "current": added source with `ios` (reference, group child, build file with `platformFilter = ios;`); added with two targets and different filters (two `add` calls); `--phase none` attach; remove of a path theirs dropped; rename with `--keep-membership` semantics keeps `AA0000000000000000000120` and `BB0000000000000000000020`; directory move of two files rebuilds the group and prunes the old one; re-filter keeps the reference and build-file IDs and ours' `fileEncoding`; phase-kind change detaches and attaches; `M3`-exempt path gets no group child with exemptions
- [x] 4.4 Implement `Replay.plan` with `ReplayDisk` (design D5); verify 4.3 passes, and that every transition's result is clean under the scoped rule set and `plutil -lint`
- [x] 4.5 Write failing `ResidualTests` (the trial and the per-path comparison of design D4/D9 E): `AppKit/Extra.h` with build-file `settings` → residual `settings`; `App/Views/Bar.swift` under `Services` with `path = ../Views/Bar.swift` → residual parent group; theirs' `includeInIndex = 0` on an added reference → residual attribute; a re-filter with ours' `fileEncoding` → no residual; a trial that throws (`noSuchPhase`) → only `ours`, with the message
- [x] 4.6 Implement the trial and the comparison; verify 4.5 passes

## 5. Classification, neutralisation, hunks

- [x] 5.1 Write failing `ClassificationTests` for the spec's "Both sides add different files" (replayed), "Both sides made the same change" (skipped), "Different changes to one file" (decision `ours`/`theirs`, three versions' membership in the item), "Build-file settings are a residual" (`ours`/`theirs-membership`)
- [x] 5.2 Implement classification (design D4); verify 5.1 passes
- [x] 5.3 Write failing `NeutraliseTests`: unit paths removed only where held; a synchronized-folder path never removed; with the `skipPresenceFilter` fault the run exits `1` naming the absent path
- [x] 5.4 Implement neutralisation (design D6); verify 5.3 passes
- [x] 5.5 Write failing `HunkTests`: "Conflicting setting values" (one hunk, governed `1000000000000000000000A1 buildSettings.SWIFT_VERSION`, base/ours/theirs values, choices `ours`/`theirs`); "Adjacent insertions" (`both` offered, and the `both` text holds both keys); "Identical hunks in two configurations have two keys"; a hunk whose `theirs` text does not parse → unsupported; a `both` that would duplicate a key is not offered
- [x] 5.6 Implement hunk analysis and keys (design D7); verify 5.5 passes

## 6. Checks

- [x] 6.1 Write failing `MergeCheckTests` for C: a lost `PRODUCT_NAME` in `1000000000000000000000A4` (fault `skipTextMerge`) fails C naming the leaf while `RuleSet` alone passes; the value in the wrong configuration fails naming both; a lost reorder of `App`'s `buildPhases` fails; an identical change on both sides and two different settings in one `buildSettings` pass; with the fault `wholeDictionaryLeaves` the two-settings case fails; with `multisetArrays` the lost reorder passes (so the probe expecting failure goes red)
- [x] 6.2 Implement check C (design D9) and the two faults; verify 6.1 passes
- [x] 6.3 Write failing tests for F (theirs' `App/Services/New.swift` smuggled into the pre-replay text fails naming the reference; with `skipStructuralDiscovery`, theirs' `--phase none` attach reaches the result as bytes and F fails), for E (`replayRemoveAll` drops `fileEncoding` on `AA0000000000000000000260` and E fails naming it), for D (a replay that also edits an unrelated path fails), for B (a row dropped from a replayed unit fails naming the target), for A (a new `M3` orphan fails; a finding ours already had passes)
- [x] 6.4 Implement checks A, B, D, E, F and the remaining faults; verify 6.3 passes

## 7. Engine and decisions

- [x] 7.1 Write failing `MergeEngineTests` for every remaining spec scenario of `merge`: keep theirs on delete against move; a re-filter keeps ours' attribute; `theirs-membership` exits `0` with `settings` owed; a setting and a file merge cleanly; a target only ours added; theirs adds a target (unsupported, naming `Widget`); an input that does not parse (unsupported, line and column); ours equals theirs (nothing to merge); every result checked as the header says
- [x] 7.2 Write failing `DecisionsTests`: template shape and SHA-256 binding; template → re-run → merged; stale inputs → unsupported naming inputs; unknown key and refused choice (`both` where not offered) → unsupported naming the key; a decision for a replayed unit is an unknown key
- [x] 7.3 Implement `MergeEngine` and `MergeDecisions` (design D10, D11); verify 7.1 and 7.2 pass
- [x] 7.4 Measure: a synthetic three-way merge on the largest corpus file (a file added on each side, one conflicting setting) in a release build; record the time in the design's Risks and add it to `PerformanceTests` with a limit of 2 s

## 8. Command

- [x] 8.1 Generate `Tests/Fixtures/merge/<scenario>/{base,ours,theirs}.pbxproj` for both-add, rename, conflicting-setting, settings-residual and theirs-adds-target with a test-only helper, commit them with a `README.md` saying how they were built
- [x] 8.2 Write failing `MergeCommandTests`: "Default output is the project file" (inputs byte-identical, no stray files); "Explicit output"; "Nowhere to write" (exit `2`); exit codes `0`/`1`/`2`/`3` on the fixtures; "Dry run" (diff, `not modified`); "JSON on decisions needed" (every key present, `null` for absent); decisions round trip through a file; stale decisions (exit `2`, nothing written); output equal to `<ours>` works; `pbxedit --help` lists `merge` and exit code `3`
- [x] 8.3 Implement `Merge.swift`, `MergeReport.swift`, `CommandOutcome.decisionsNeeded`, the shared atomic write and read-back (design D11, D12); verify 8.2 and the whole CLI suite pass
- [x] 8.4 Extend `CLITests.OracleTests` with the both-add, rename and `theirs-membership` merges; verify `xcodebuild -list` reads each (and that the suite fails under `ORACLE_REQUIRED=1` if it cannot)

## 9. Documentation and release preparation

- [x] 9.1 Reconcile `docs/design.md`: status line, § Decisions (commands), § 4 CLI (the `merge` row, exit code `3`), § Testing (merge tests and oracle count), § Out of scope (git integration, `.pbxedit.yml` merging); README (`merge` section with the git recipe: extract `:1`/`:2`/`:3`, run, re-run with decisions); `CLAUDE.md` state of the repository; `TODO.md` § 12 with the evidence
- [x] 9.2 Add a `merge` step to `docs/RELEASING.md` § 2 (merge two branches of the Xcode-saved project, one adding and one moving a file, into `ops/`), and keep `ReleasingDocumentTests` green
- [x] 9.3 Run `swift build`, `swift test`, `swift test -c release --filter PerformanceTests`; read the summaries and record the counts in `TODO.md` § 12

## 10. Review follow-ups

- [x] 10.1 Write failing tests for a group neutralisation empties: theirs' `indentWidth` on it survives the merge; a group theirs added keeps its ID and attribute; a group theirs deleted with its file gives no hunk; a group theirs emptied and kept is not pruned by the replay (`NeutralisePrunedGroupTests`)
- [x] 10.2 Implement `Neutralise.keptGroups` and `keeping:` through `RemovePlanner`, `MovePlanner`, the replay and check D (design D6); verify 10.1 passes
- [x] 10.3 Regression tests for the review's fixes: rows in another order are no change (`ReplayTests`); identical sides that both add a target have nothing to merge (`MergeEngineTests`); a trial with ours' snapshot passed in equals one built inside; one wording for filters (`PlatformFilterTests`); a failed re-check names the check when the restore also failed (`MergeRendererTests`)
- [x] 10.4 Write failing `MergeCommandTests` for a broken `.pbxedit.yml` (not "nowhere to write") and `--output` with `--config` and no project (design D12); split `ProjectOptions` into `loadConfig()`, `locate(config:)` and `context(pbxproj:config:)`; verify they pass
- [x] 10.5 Write failing `ReplayTests` for two rows of one path in one target (Sources and Resources of `App`): a second row attached keeps the first's build file; one of two detached; one of two re-filtered in place (no build file deleted or created); the trial finds no residual; through the engine the unit is replayed and merges
- [x] 10.6 Match a target's rows by phase kind in the replay, with `AddPlanner`'s internal `perPhase` mode and `RemovePlanner`'s internal per-phase detach (design D5 step 4); verify 10.5 and the whole suite pass
