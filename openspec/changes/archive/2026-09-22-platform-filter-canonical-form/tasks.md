# Tasks

Every operation test applies the plan, asserts on the model, asserts the rule set is clean over the touched objects, and runs `plutil -lint` on the output. Fixtures: `Tests/Fixtures/xcode27/` (the Xcode 27 evidence, committed as captured), `Tests/Fixtures/move/app.pbxproj`, `Tests/Fixtures/repair/app.pbxproj`.

## 1. Read rule

- [x] 1.1 Write failing tests for "Both spellings are read as one value": on `xcode27/platform-filters-after-xcode27-save.pbxproj`, `MembershipReport` and `TargetMembers` give the expected `platformFilters` for every filtered path (`F1` `[ios]`, `F2` `[maccatalyst]`, `Kit` `[maccatalyst]`, `OnlyApp` `[macos]`, `Panel` `[ios, maccatalyst]`, `Common` `[ios, tvos]`, `TV1` `[tvos]`), `Conventions.platformFilters` infers `maccatalyst` for `AppKit/New.swift` in `AppKit` and reports `ios` vs `maccatalyst` for `App/Filtered/New.swift` in `App`; and `platform-filters-before.pbxproj` (the legacy spelling) yields membership reports and target listings equal to the Xcode-saved copy's for every path and target, both with zero S4 findings
- [x] 1.2 Implement `PlatformFilters.read(from:)` (design D1) and route `Conventions`, `MovePlanner`, `MembershipReport` and `TargetMembers` through it; verify 1.1 passes

## 2. Rule S4

- [x] 2.1 Write failing tests for "Rule S4 checks both keys": zero S4 on the Xcode-saved probe; the new fixtures `rules/s4-singular-unknown.pbxproj` (`platformFilter = tvos;` flagged naming `tvos` and listing `ios, maccatalyst`; `platformFilter = ios;` and `= maccatalyst;` not flagged) and `rules/s4-singular-not-string.pbxproj` (`platformFilter = (ios, );` flagged as not a string); the existing `platformFilters = ios;` still flagged as not an array
- [x] 2.2 Implement S4 over both keys (design D3) and the finding title; verify 2.1 passes and the rule fixtures still pass `plutil -lint`

## 3. Write rule

- [x] 3.1 Write failing tests for `PlatformFilters.spelling(of:)` (`[ios]` and `[maccatalyst]` singular; `[tvos]`, `[macos]`, `[ios, tvos]`, `[ios, maccatalyst]` plural in the order given; `[]` none) and for `Plan.apply(.createBuildFile)` serialising `platformFilter = ios;`, `platformFilter = maccatalyst;`, `platformFilters = (ios, tvos, );`, `platformFilters = (tvos, );` and no key, each after `fileRef` on the definition line, each passing the scoped rule set and `plutil -lint`
- [x] 3.2 Implement the spelling rule and the `createBuildFile` writer (design D2); verify 3.1 and the existing `PlanTests` (tvos stays plural) pass
- [x] 3.3 Write failing `MovePlannerTests` for "An unchanged filter is never re-spelled" and "A changed value replaces the spelling": a value-preserving rename of `App/Filtered/F1.swift` in the probe emits no filter step and leaves the definition line unchanged but for the name; `App/iOS/Panel.swift` → `App/Shared/Panel.swift` emits `setAttribute("platformFilter", nil)` on `BB0000000000000000000190` and the reverse move of `Common.swift` emits `setAttribute("platformFilter", "ios")` on `BB0000000000000000000200`, details unchanged (`platformFilters removed (was ios)`, `platformFilters = ios (was none)`); on `platform-filters-before.pbxproj`, `App/Filtered/F1.swift` → `AppKit/F1.swift --target AppKit` creates a build file with `platformFilter = maccatalyst;`, and `--target App --platform maccatalyst` rewrites the retained build file to `platformFilter = maccatalyst;` with `platformFilters` removed; a change to a two-value list from a singular key sets `platformFilters` and removes `platformFilter`
- [x] 3.4 Implement the retained-build-file rewrite in `MovePlanner` (design D2); verify 3.3 passes

## 4. Fixtures, command surface and the regression

- [x] 4.1 Rewrite the `platformFilters = (ios, );` lines of `Tests/Fixtures/{add,move,remove,repair}/app.pbxproj` to `platformFilter = ios;` (design D4); add `Tests/Fixtures/xcode27/README.md`; update the tests that pinned the plural spelling or the plural-only accessor (`MovePlannerTests`, `RepairPlannerTests`) only where the new spelling is the reason; verify `swift test` is green across all four targets
- [x] 4.2 Write failing `AddCommandTests` for "Filters are written as Xcode writes them" and "The command surface names the attribute, not the key": `add App/Views/Bar.swift --platform ios` / `maccatalyst` / `ios,tvos` / `tvos` / `none` on `move/app.pbxproj` write exactly `platformFilter = ios;`, `platformFilter = maccatalyst;`, `platformFilters = (ios, tvos, );`, `platformFilters = (tvos, );`, no key; `--json` keeps `attribute: platformFilters`, `value: App: ios` and `platformFilters: ["ios"]`; `add App/Mixed/New.swift --target AppExtension` on the probe infers `ios` from the singular sibling and writes it singular; verify they pass (the writer shipped in 3.2)
- [x] 4.3 Write the failing regression test for issue #6 (design D6): replay `docs/RELEASING.md` § 2 — `add App/Views/Bar.swift`, `move App/Views/Foo.swift App/Features/Foo.swift`, `remove App/Services/Rate.swift` on `move/app.pbxproj`; `lint --fix` on `repair/app.pbxproj` — and assert the multiset of lines containing `platformFilter` equals the Xcode-saved copy's for each, with zero S4 on the results and a comment naming the two excluded kinds of difference; verify it passes
- [x] 4.4 Extend `CLITests.OracleTests` with `add` and `move` scenarios on the Xcode-saved probe (a singular filter written next to singular siblings; a move that rewrites one); verify `xcodebuild -list` reads them

## 5. Documentation

- [x] 5.1 Reconcile `docs/design.md`: S4's row in § Rules, the `platformFilters` row and a spelling note in § Conventions, the Motivation table's new row (issue #6), the status line; add a one-line dated note to the archived `move-command` design where it states `setAttribute(platformFilters)` as the retained-build-file mechanism
- [x] 5.2 Add § 11 to `TODO.md` with the evidence for this change
