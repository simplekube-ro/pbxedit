# Tasks

## 1. Dependency and types

- [x] 1.1 Add `Yams` to `Package.swift` for `PBXOps`; verify `swift build` succeeds and `Package.resolved` lists exactly `swift-argument-parser` and `Yams` as direct dependencies — Yams 5.4.0; `Build complete!`

## 2. Glob matcher

- [x] 2.1 Write failing tests for the matcher: `*` within a segment, `**` across segments including zero segments, `?`, anchoring at both ends, and rejection of `[...]`, `{...}`, empty segments and `**` mixed into a segment as unsupported — `GlobTests`
- [x] 2.2 Implement the matcher per design D3; verify 2.1 passes — `PathGlob`; 7 tests, 0 failures

## 3. Loading and validation

- [x] 3.1 Write failing tests for discovery: `--config`, walking up from a subdirectory, no file found, missing `--config` path as exit `2` — `ConfigTests`, `ConfigCommandTests`
- [x] 3.2 Write failing tests for strict decoding: misspelled key with line number and allowed keys, wrong value type, malformed YAML, unknown rule ID, non-exemptible rule `S2`, unknown platform name, unsupported glob — `ConfigTests`
- [x] 3.3 Implement discovery and strict decoding per design D4 and D7 (including the source-root check and prefix); verify 3.1–3.2 pass — `Config`, `ConfigFile`, `BoundConfig`; `ProjectOptions.context()`; 16 + 8 tests, 0 failures
- [x] 3.4 Write a failing test for the Target that does not exist scenario; implement project-dependent validation that runs before planning in every command; verify it passes and that a mutating command given an invalid configuration leaves the project file unchanged — `BoundConfig.validate(targets:)`, `ProjectContext.validate` in `add`, `lint`, `query`

## 4. Conventions layer

- [x] 4.1 Write failing tests for first-match-per-attribute: single rule, attributes from two different rules, `platformFilters: []` meaning explicitly none, no rule matching falls through to inference — `ConfigConventionsTests`
- [x] 4.2 Write failing tests for both Precedence scenarios, asserting `Decision.source` is `.config` with rule position and glob, or `.flag` — `ConfigConventionsTests`, `ConfigAddTests`
- [x] 4.3 Insert the config source into `Conventions` per design D1–D2 without changing any planner; add `rule` and `glob` to the JSON `source`; verify 4.1–4.2 pass and all `add-command` tests still pass — `Conventions.config`, `Decision.Source.config`; `git diff --stat Sources/PBXOps/Add/` empty; `AddCommandTests` 12/12, `AddPlannerTests` green

## 5. Lint integration

- [x] 5.1 Write failing tests for the configured baseline default and `--no-baseline` — `ConfigLintTests`
- [x] 5.2 Write failing tests for path exemptions: an exempt `M3` finding is suppressed and counted in text and JSON; a non-matching path is still reported; `--write-baseline` omits exempt findings — `ExemptionTests`, `ConfigLintTests`
- [x] 5.3 Implement `exemptions` filtering in `RuleSet.evaluate` and `OperationRunner` per design D5 and the `lint` defaults; verify 5.1–5.2 pass — `Exemptions`, `RuleSet.evaluate(exemptions:)`, `OperationRunner.exemptions`, `lint --no-baseline` and the `exempt` count

## 6. Add integration

- [x] 6.1 Write a failing test for the Exempt path scenario: no group created or modified, `SOURCE_ROOT` reference, add succeeds, `plutil -lint` passes; and a runner test that the pre-write check honours the exemption — `ExemptionTests.testAnM3ExemptPathIsPlannedWithoutAGroup` (model assertions, rule set with and without the exemption, `plutil -lint`), `ExemptionTests.testTheRunnerHonoursExemptionsBeforeAndAfterTheWrite`, `ConfigAddTests.testAnM3ExemptPathGetsNoGroupChildAndASourceRootReference` (end to end, text and JSON, re-add)
- [x] 6.2 Implement the planner skip per design D6; verify 6.1 passes — additive `AddPlanner.plan(..., exemptions: Exemptions? = nil)`, `Decision.Source.exemption(rule:glob:)`; `AddPlannerTests` 16/16 and `AddCommandTests` 12/12 unchanged and green
- [x] 6.3 Write a failing CLI test that `project:` in the configuration resolves the two-projects ambiguity; implement in `ProjectOptions`; verify it passes — `ConfigCommandTests.testProjectInTheConfigurationResolvesTheTwoProjectsAmbiguity`

## 7. Documentation

- [x] 7.1 Add the complete commented example as `Tests/Fixtures/config/example.pbxedit.yml` (there is no `README.md` yet; the change's design.md Evidence records where it goes) with the list of exemptible rules; verify it by loading it strictly in a test — `ConfigTests.testTheDocumentedExampleLoads`
- [x] 7.2 Reconcile `docs/design.md` § Config with the shipped keys (`--config`, `--no-baseline`, first-match-per-attribute, exemptible rule list, provenance and summary shapes); verify by a test that every key in the doc's example exists in the decoder and the reverse — `ConfigTests.testTheDesignDocumentExampleAgreesWithTheDecoder` parses the doc's example strictly and checks every decoder key appears in it
