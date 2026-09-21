# Tasks

## 1. Dependency and types

- [ ] 1.1 Add `Yams` to `Package.swift` for `PBXOps`; verify `swift build` succeeds and `Package.resolved` lists exactly `swift-argument-parser` and `Yams` as direct dependencies

## 2. Glob matcher

- [ ] 2.1 Write failing tests for the matcher: `*` within a segment, `**` across segments including zero segments, `?`, anchoring at both ends, and rejection of `[...]` and `{...}` as unsupported
- [ ] 2.2 Implement the matcher per design D3; verify 2.1 passes

## 3. Loading and validation

- [ ] 3.1 Write failing tests for discovery: `--config`, walking up from a subdirectory, no file found, missing `--config` path as exit `2`
- [ ] 3.2 Write failing tests for strict decoding: misspelled key with line number and allowed keys, wrong value type, malformed YAML, unknown rule ID, non-exemptible rule `S2`, unknown platform name
- [ ] 3.3 Implement discovery and strict decoding per design D4 and D7; verify 3.1–3.2 pass
- [ ] 3.4 Write a failing test for the Target that does not exist scenario; implement project-dependent validation that runs before planning; verify it passes and that a mutating command given an invalid configuration leaves the project file unchanged

## 4. Conventions layer

- [ ] 4.1 Write failing tests for first-match-per-attribute: single rule, attributes from two different rules, `platformFilters: []` meaning explicitly none, no rule matching falls through to inference
- [ ] 4.2 Write failing tests for both Precedence scenarios, asserting `Decision.source` is `.config` with rule position and glob, or `.flag`
- [ ] 4.3 Insert the config source into `Conventions` per design D1–D2 without changing any planner; verify 4.1–4.2 pass and all `add-command` tests still pass

## 5. Lint integration

- [ ] 5.1 Write failing tests for the configured baseline default and `--no-baseline`
- [ ] 5.2 Write failing tests for path exemptions: an exempt `M3` finding is suppressed and counted; a non-matching path is still reported
- [ ] 5.3 Implement `exemptions` filtering in `RuleSet.evaluate` per design D5 and the `lint` defaults; verify 5.1–5.2 pass

## 6. Add integration

- [ ] 6.1 Write a failing test for the Exempt path scenario: no group created or modified, `SOURCE_ROOT` reference, add succeeds, `plutil -lint` passes
- [ ] 6.2 Implement the planner skip per design D6; verify 6.1 passes
- [ ] 6.3 Write a failing CLI test that `project:` in the configuration resolves the two-projects ambiguity; implement in `ProjectOptions`; verify it passes

## 7. Documentation

- [ ] 7.1 Add a Configuration section to `README.md` with a complete commented example and the list of exemptible rules; verify the example by loading it in a test
- [ ] 7.2 Reconcile `docs/design.md` § Config with the shipped keys (`--no-baseline`, first-match-per-attribute, exemptible rule list); verify every key in the doc exists in the decoder and the reverse
