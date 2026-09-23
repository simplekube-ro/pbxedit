# Three-way merge fixtures

The inputs of `pbxedit merge` for the command and oracle tests
(`Tests/CLITests/MergeCommandTests.swift`, `OracleTests`). Each directory
holds `base.pbxproj`, `ours.pbxproj` and `theirs.pbxproj`. Every `base` is
`xcode27/platform-filters-after-xcode27-save.pbxproj`, byte for byte; `ours`
and `theirs` are that base after the operations below, made in memory with
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
