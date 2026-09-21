# Tasks

## 1. Targets

- [ ] 1.1 Add `PBXOps` library, `pbxedit` executable and their test targets to `Package.swift`, with `swift-argument-parser` as a dependency of the executable only; verify `swift build` succeeds and `swift run pbxedit --help` prints usage

## 2. Findings and rule engine

- [ ] 2.1 Write failing tests for `Finding` fields (the ungrouped-file scenario) and for deterministic ordering
- [ ] 2.2 Implement `Finding`, `Rule`, `RuleSet.evaluate(project, scope:)` per design D1–D2; verify 2.1 passes

## 3. Structural rules

- [ ] 3.1 Create one minimal fixture per S-rule scenario under `Tests/Fixtures/rules/`; write failing tests asserting the exact findings for S1 (single finding, other rules skipped), S2, S3, S4 and S5
- [ ] 3.2 Implement S1–S5; verify 3.1 passes
- [ ] 3.3 Add the corpus test from design.md's first risk (every ID-shaped attribute key is either in the S2 list or explicitly ignored); verify it passes or extend the S2 list until it does

## 4. Membership rules

- [ ] 4.1 Create fixtures and write failing tests for M1, M2, M3 (including the product exemption), M4, M5 and M6 scenarios
- [ ] 4.2 Implement M1–M5; verify their tests pass
- [ ] 4.3 Implement M6 with inferred target roots per design D4; verify the M6 scenario passes and a shared-sources fixture produces no M6 finding
- [ ] 4.4 Add a test asserting zero findings on each freshly generated Xcode template project in the corpus, including one with a Swift package dependency; verify it passes

## 5. Disk rules

- [ ] 5.1 Write failing tests for D1 and D2, including the synchronized-folder scenario, against an in-memory `DiskReader`; add a test that a run without `--disk` makes no `DiskReader` calls
- [ ] 5.2 Implement `DiskReader`, D1 and D2 per design D5; verify 5.1 passes

## 6. Scoped evaluation

- [ ] 6.1 Write a failing test for the Unrelated damage scenario (600 M3s, clean scoped result) and one where a scoped object collides with an unscoped one under M4
- [ ] 6.2 Implement scope filtering on `object` and `related`; verify 6.1 passes

## 7. lint command

- [ ] 7.1 Write failing CLI tests (spawn the built binary against fixtures) for human output, JSON output shape, byte-identical project file after the run, and exit codes `0`/`1`/`2` including `--strict`
- [ ] 7.2 Implement `ProjectOptions` discovery and write failing-then-passing tests for the Project location scenarios
- [ ] 7.3 Implement the `lint` subcommand and renderers per design D7; verify 7.1 passes
- [ ] 7.4 Write failing tests for the three Baseline scenarios; implement `--write-baseline` and `--baseline` with the format in design D6; verify they pass

## 8. Documentation

- [ ] 8.1 Update `docs/design.md`: S5 wording and severity per design D3, and `--write-baseline` in the Commands table; verify the rule tables in `docs/design.md` and the spec agree rule by rule
- [ ] 8.2 Run `pbxedit lint` on the originating project's file from the corpus and record the finding counts per rule in this change's design.md as the adoption reference; verify the M3 count is of the order of 655
