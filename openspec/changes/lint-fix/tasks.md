# Tasks

## 1. Repair framework

- [ ] 1.1 Write failing tests for `PlanBuilder`: two findings needing the same missing group yield one `createGroup`; planned groups are visible to later lookups; steps are emitted in deterministic order
- [ ] 1.2 Implement `Fixer`, `FixOutcome` and `PlanBuilder` per design D1–D2; verify 1.1 passes

## 2. Verification mode

- [ ] 2.1 Write failing tests for `OperationRunner` with `.noNewFindings(selected:)`: passes when selected findings vanish and nothing new appears; fails, leaving bytes unchanged, when a stub plan fixes M3 but introduces an M4; fails when a selected finding survives
- [ ] 2.2 Implement the verification parameter and finding identity comparison per design D5; verify 2.1 passes and all existing operation tests still pass with the default

## 3. M2 fixer

- [ ] 3.1 Write failing tests for both M2 scenarios: entry naming a non-existent ID removed alone; build file with unresolvable `fileRef` removed from its phase and deleted
- [ ] 3.2 Implement the M2 fixer; verify 3.1 passes and results pass `plutil -lint`

## 4. M1 fixer

- [ ] 4.1 Write failing tests: build file in no phase joins the unanimous siblings' target using its existing ID with zero objects created; ambiguous siblings yield `notFixable` listing candidates; target lacking the phase yields `notFixable`; build file in two phases is not touched; existing `platformFilters` are preserved
- [ ] 4.2 Implement the M1 fixer per design D3; verify 4.1 passes

## 5. M3 fixer

- [ ] 5.1 Write failing tests: orphan joins an existing group as a one-line diff; 95 orphans in a directory with no group produce one new group with children in name order; `SOURCE_ROOT` spelling byte-identical afterwards; non-project-relative reference and multiply-parented reference are `notFixable`
- [ ] 5.2 Implement the M3 fixer per design D4 reusing add's group resolution; verify 5.1 passes

## 6. Command

- [ ] 6.1 Write failing CLI tests: `--fix` report lists repairs then remaining findings with reasons; exit code reflects the result; second run reports `modified: false` with bytes unchanged; `--fix --dry-run` prints a diff and writes nothing; JSON shape includes `repaired`, `remaining` and `modified`
- [ ] 6.2 Write a failing test for the Object census scenario on a fixture mixing M1, M2 and M3
- [ ] 6.3 Implement `--fix` and `--dry-run` on the `lint` subcommand; verify 6.1–6.2 pass

## 7. Exemptions and baseline

- [ ] 7.1 Write failing tests: an M3-exempt path is not grouped; baselined fixable findings are repaired and the output reports the count of resolved baseline entries with the `--write-baseline` hint; the baseline file's bytes are unchanged
- [ ] 7.2 Implement per design D7; verify 7.1 passes

## 8. Reference workload

- [ ] 8.1 Run `lint --fix` in a test against the originating project's file from the corpus; assert a single write, a diff containing only added `children` lines and new `PBXGroup` definitions, zero M3 findings afterwards, unchanged file-reference count, and `plutil -lint` success
- [ ] 8.2 Measure 8.1 in a release build; verify it completes in under two seconds, or enable the batch invalidation scope per design D6 and re-measure
- [ ] 8.3 On macOS, run `xcodebuild -list` on the repaired file within a copy of the originating `.xcodeproj` directory from the corpus; verify success

## 9. Documentation

- [ ] 9.1 Add an "Adopting on an existing project" section to `README.md`: `lint`, `lint --fix --dry-run`, `lint --fix`, then baseline whatever remains; update `docs/design.md` § Severity and repair with the whole-project verification and repair order; verify commands in the README run as written against a fixture
