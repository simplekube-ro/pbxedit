# Tasks

## 1. Repair framework and fixture

- [x] 1.1 Add `Tests/Fixtures/repair/app.pbxproj` (the `add/app.pbxproj` project plus M1, M2, M3 damage of every fixable and not-fixable shape and one S2 that remains) and write failing tests for `RepairPlanner`: fixable findings are planned and the rest carry a reason; two M3 findings needing the same missing group yield one `createGroup`; the plan's changes are keyed by finding; findings are processed M2, M1, M3 in `RuleSet.ordered` order so two runs give identical steps
- [x] 1.2 Implement `Fixer`, `FixOutcome`, `RepairPlan` and `RepairPlanner` per design D1–D2; verify 1.1 passes

## 2. Verification mode

- [x] 2.1 Write failing tests for `OperationRunner` with `.wholeProject(before:selected:)`: passes when selected findings vanish and nothing new appears; fails, leaving bytes unchanged, when a stub plan fixes M3 but introduces an M4; fails when a selected finding survives; a finding that vanishes as a side effect does not fail it; the post-write check uses the same mode
- [x] 2.2 Implement the verification parameter and `Finding.identity` per design D5; verify 2.1 passes and all existing operation tests still pass with the default

## 3. M2 fixer

- [x] 3.1 Write failing tests for both M2 scenarios: entry naming a non-existent ID removed alone (every listing of it); build file with unresolvable `fileRef` removed from its phase and deleted
- [x] 3.2 Implement the M2 fixer; verify 3.1 passes and results pass `plutil -lint`

## 4. M1 fixer

- [x] 4.1 Write failing tests: build file in no phase joins the unanimous siblings' target using its existing ID with zero objects created; ambiguous siblings yield `notFixable` listing the variants; a configured target lacking the phase yields `notFixable`; build file in two phases is not touched; existing `platformFilters` are preserved; a build file in no phase with a dangling `fileRef` is deleted
- [x] 4.2 Implement the M1 fixer per design D3; verify 4.1 passes

## 5. M3 fixer

- [x] 5.1 Write failing tests: orphan joins an existing group as a one-line diff in name order; three orphans in a directory with no group produce one new group with children in name order; `SOURCE_ROOT` spelling byte-identical afterwards and the resolved path unchanged; a `<group>`-relative orphan at the root joins the main group; a `<group>`-relative orphan with a directory in its path, a non-project-relative reference and a multiply-parented reference are `notFixable` with the reasons of design D4
- [x] 5.2 Implement the M3 fixer per design D4 reusing add's group resolution; verify 5.1 passes

## 6. Command

- [x] 6.1 Write failing CLI tests: `--fix` report lists repairs then remaining findings with reasons; exit code reflects the result; second run reports `modified: false` with bytes unchanged; `--fix --dry-run` prints a diff and writes nothing; `--dry-run` alone and `--fix --write-baseline` exit `2`; JSON shape per design D8 (`repaired`, `remaining`, `modified`, `summary.repaired`, `summary.notFixable`)
- [x] 6.2 Write a failing test for the Object census scenario on the mixed fixture, and a `modified`-matches-the-bytes test over the fix invocations
- [x] 6.3 Implement `--fix` and `--dry-run` on the `lint` subcommand with its report; verify 6.1–6.2 pass

## 7. Exemptions and baseline

- [x] 7.1 Write failing tests: an M3-exempt path is not grouped and no group is created for it; baselined fixable findings are repaired and the output reports the count of resolved baseline entries with the `--write-baseline` hint; the baseline file's bytes are unchanged
- [x] 7.2 Implement per design D7; verify 7.1 passes

## 8. Reference workload

- [x] 8.1 Write `RepairPerformanceTests`: synthesize the substitute of design Evidence (655 `SOURCE_ROOT` orphans over thirty directories on `Alamofire.pbxproj`, half of the directories without a group), run the repair through `OperationRunner` in a temporary `.xcodeproj`, and assert a single write, a diff containing only added `children` lines and new `PBXGroup` definitions, zero M3 findings and no new finding afterwards, unchanged file-reference count, and `plutil -lint` success; the originating project is private and never committed, so its line in the Evidence stays a marked placeholder
- [x] 8.2 Measure 8.1 in a release build (`swift test -c release --filter PerformanceTests`); verify it completes in under two seconds and record the numbers in design.md Evidence
- [x] 8.3 Extend `OracleTests` with the repaired substitute and the repaired mixed fixture; verify `xcodebuild -list` reads both

## 9. Documentation

- [x] 9.1 Record the "Adopting on an existing project" examples (`lint`, `lint --fix --dry-run`, `lint --fix`, then `--write-baseline`) in design.md Evidence, pinned as real output by a CLI test (there is no `README.md` yet, as changes 4–8 found); update `docs/design.md` § Severity and repair with the whole-project verification, the repair order, the M3 spelling rule and the dead-build-file deletion, the `lint` row with `--fix`/`--dry-run`, § Architecture 3 with `RepairPlanner` and the runner's verification modes, and the status line
