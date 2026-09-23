# Three-way merge fixtures

The inputs of `pbxedit merge` for the command and oracle tests
(`Tests/CLITests/MergeCommandTests.swift`, `OracleTests`). Each directory
holds `base.pbxproj`, `ours.pbxproj` and `theirs.pbxproj`. Every `base` is
`xcode27/platform-filters-after-xcode27-save.pbxproj`, byte for byte, except
`both-objects`, whose base is that file with a `packageReferences` list and
one `XCRemoteSwiftPackageReference`, and `reordered-array`, whose base is that
file with `knownRegions` written one element per line; `ours` and `theirs` are that base after
the operations below, made in memory with
pbxedit's own planners (settings by a text edit of the tree), with seeded ID
minting so the files are the same on every run. They are pbxedit's own
fixtures, not third-party material, so they have no entry in
`Tests/Fixtures/NOTICE`.

They are built by `MergeFixtureFileTests.scenarios()` in
`Tests/PBXOpsTests/MergeFixtureFileTests.swift`, which also checks on every
test run that the committed files are what it builds. Do not edit them by
hand; change the recipe and regenerate:

```sh
PBXEDIT_WRITE_MERGE_FIXTURES=1 swift test --filter MergeFixtureFileTests
```

| Scenario | Ours | Theirs | `pbxedit merge` |
|---|---|---|---|
| `both-add` | `add App/Views/Bar.swift` | `add App/Services/New.swift --platform ios` | exit `0`: `New.swift` replayed |
| `rename` | `add App/Views/Bar.swift` | `move App/Views/Foo.swift App/Features/Foo.swift --keep-membership` | exit `0`: the rename replayed as one unit |
| `conflicting-setting` | `SWIFT_VERSION = 5.10;` in `1000000000000000000000A1` | `SWIFT_VERSION = 6.2;` there | exit `3`: one hunk, `ours` or `theirs` |
| `settings-residual` | the base | `add AppKit/Extra.h --target AppKit`, its build file given `settings = {ATTRIBUTES = (Public, ); };` | exit `3`: `ours` or `theirs-membership`; with `theirs-membership`, exit `0` and `settings` owed |
| `theirs-adds-target` | the base | a `PBXNativeTarget` named `Widget` | exit `2`: the merge never creates a target |
| `phase-removed` | the base | `AppKit/AppKit.h` moved from `AppKit`'s Headers to its Sources phase, and the Headers phase deleted | exit `3` (the deleted phase conflicts with ours' copy of it); decided either way, exit `1`: check F finds `AppKit.h`'s reference no longer managed in the text merge |
| `shared-array` | `knownRegions = (de, en, Base, it, );` and `SWIFT_VERSION = 5.10;` in `1000000000000000000000A1` | `knownRegions = (fr, en, Base, es, );` and `SWIFT_VERSION = 6.2;` there | exit `3`: three hunks, two of them governing `knownRegions` (issue #12); every combination of their decisions exits `0` |
| `both-regions` | `knownRegions = (de, en, Base, );` | `knownRegions = (fr, en, Base, );` | exit `3`: one hunk offering `ours`, `theirs` and `both` (issue #13); with `both`, exit `0` and `(de, fr, en, Base, )` |
| `both-objects` | one more `XCRemoteSwiftPackageReference` (`EF…02`, `https://example.com/a`) in the list and its own object | one more (`EF…03`, `https://example.com/b`) | exit `3`: two hunks, the list and the two multi-line objects, both offering `ours`, `theirs` and `both` (issue #17); with both `both`, exit `0` and all three packages |
| `attribute-conflict` | `fileEncoding = 4;` on `AA0000000000000000000260` (`App/Filtered/F1.swift`) | that file re-filtered (`remove --target App`, `add --target App --platform ios,macos`) and `fileEncoding = 10;` on its reference | exit `3`: the unit offers `ours` or `theirs-membership` over the conflicting `fileEncoding` (issue #20); with `theirs-membership`, exit `0`, theirs' filters and `fileEncoding` owed |
| `both-frameworks` | `CoreHaptics.framework` linked into `App`'s Frameworks phase (an SDKROOT reference, a build file, a child of the `Frameworks` group, an entry of `CC0000000000000000000002`) | the same for `GameController.framework` | exit `3`: four hunks, each offering `ours`, `theirs` and `both` (issue #21); with all four `both`, exit `0` and both frameworks linked, ours' entry before theirs' |
| `reordered-array` | `knownRegions = (Base, en, );` — base's two regions swapped | `knownRegions = (en, Base, fr, );` — one inserted | exit `3`: the hunk over `knownRegions` offers `ours` and `theirs` only, though its own texts look like two insertions (issue #24); `both` for it is exit `2` |
