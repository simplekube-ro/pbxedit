# Xcode 27 evidence

Files Xcode 27.0 (27A266a) wrote when it opened and saved pbxedit's own
fixtures, captured during the `v1.0.0` open-and-save check
(`docs/RELEASING.md` § 2) that found issue #6. They are pbxedit's fixtures
saved by Xcode, not third-party material, so they have no entry in
`Tests/Fixtures/NOTICE`. Do not edit them: each is byte-exact as Xcode
left it.

| File | What it is |
|---|---|
| `platform-filters-before.pbxproj` | The `move/app.pbxproj` project with every platform-filter spelling laid out as a probe, as handed to Xcode — `F1.swift` `platformFilters = (ios, );` and `F2.swift` `platformFilters = (maccatalyst, );` are the spelling pbxedit wrote before change `platform-filter-canonical-form`, and this file is the regression fixture for "the legacy spelling pbxedit still reads" |
| `platform-filters-after-xcode27-save.pbxproj` | The same project after Xcode saved it: the two lines above became `platformFilter = ios;` and `platformFilter = maccatalyst;`; every other spelling (`platformFilter = ios;`, `platformFilters = (tvos, );`, `(macos, );`, `(ios, maccatalyst, );`, `(ios, tvos, );`) was left alone; the synchronized group was re-laid out over several lines |
| `move-app-after-xcode27-save.pbxproj` | `move/app.pbxproj` after `pbxedit add App/Views/Bar.swift`, `move App/Views/Foo.swift App/Features/Foo.swift`, `remove App/Services/Rate.swift` and Xcode's save |
| `repair-app-after-xcode27-save.pbxproj` | `repair/app.pbxproj` after `pbxedit lint --fix` and Xcode's save; Xcode also deleted the damage `--fix` reports as not fixable and split the doubly-listed `Twice.swift` build file |
| `xcode27-save.diff` | The diff of that save over the post-operation files, as `git diff` showed it |
| `repair-fixable.pbxproj` | Not an Xcode save: `platform-filters-after-xcode27-save.pbxproj` with one group child removed, the one M3 orphan `lint --fix` restores byte for byte — the `lint --fix` input of the release check (`docs/RELEASING.md` § 2), whose starting files must be Xcode-saved and carry only fixable damage |

The rule these files establish — exactly one filter that is `ios` or
`maccatalyst` is spelled `platformFilter = <value>;`, everything else
`platformFilters = (…);` — is `PlatformFilters.spelling(of:)` in
`Sources/PBXOps/Inference/PlatformFilters.swift`; `docs/design.md`
§ Conventions records it.
