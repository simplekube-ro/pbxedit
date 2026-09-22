# Proposal

## Why

Issue #6, found by the `v1.0.0` open-and-save check (`docs/RELEASING.md` § 2) with Xcode 27.0 (27A266a): pbxedit always writes a build file's platform filter as the plural array, `platformFilters = (ios, );`, but Xcode's canonical spelling for a lone `ios` or `maccatalyst` is the singular key, `platformFilter = ios;`, and Xcode rewrites ours on save. That is a diff on every pbxedit-written iOS filter, which the release checklist counts as a blocker. The read side is also incomplete: rule S4 and, before this change, parts of the tool read only the plural key, so on a real Xcode-written project a `platformFilter = ios` sibling is silently "no filter". Nothing in the corpus carries a platform filter, which is why no test caught it.

## What Changes

- One rule for reading a build file's platform filter, applied everywhere that reads one — the model views, sibling inference, rule S4, `move`'s membership delta, `query`'s membership and target reports, the operation renderer: both keys are recognised; the singular key is normalised to a one-element list; a build file with neither has no filter.
- One rule for writing one, applied by `add`, by `move` (attaching and rewriting retained build files) and by any future writer: exactly one filter that is `ios` or `maccatalyst` is written as `platformFilter = <value>;`; every other non-empty set is written as `platformFilters = (…);` in the order given; an empty set writes neither key. Both keys never coexist after a write. A build file whose value does not change is not touched, whatever its spelling — the lossless-tree rule "untouched bytes are never rewritten" is kept, so a legacy `platformFilters = (ios, )` pbxedit itself wrote before this change is left alone until its value changes.
- Rule S4 checks both keys: the singular key must be a string and one of `ios`, `maccatalyst`; the plural key must be a plist array of known names, as before.
- The evidence Xcode 27 produced is committed as regression fixtures under `Tests/Fixtures/xcode27/` (pbxedit's own fixtures as Xcode saved them; not third-party material). The hand-written fixtures' `platformFilters = (ios, )` lines, which Xcode never writes, become `platformFilter = ios;` where they stand for Xcode-written content; the pre-save probe keeps the plural single-`ios` spelling as the "legacy spelling pbxedit still reads" regression.
- `--platform <list>|none`, the `.pbxedit.yml` `platformFilters` key, the decision line `platformFilters: <target>: <values> (<provenance>)` and the JSON `platformFilters` array in reports keep their current syntax: they name the attribute in pbxedit's vocabulary, not the key as spelled in the file.

## Capabilities

### New Capabilities
- `platform-filters`: how a build file's platform filter is read, inferred, checked (rule S4) and written, in the form Xcode writes.

### Modified Capabilities
- `add`: the "Platform filters are inferred only when unanimous" requirement states the singular spelling for a lone `ios`/`maccatalyst` and that inference reads both keys.
- `move`: the "Membership follows the destination" requirement states that a retained build file's filters are rewritten in canonical form, only when their value changes.
- `integrity-rules`: the "Structural rules" requirement's S4 clause covers the singular key.
- `query`: the "Membership of a path" requirement states that the reported `platformFilters` is the same whichever key the file uses.

### Why one new capability and four deltas
`openspec/config.yaml` asks for one capability per change. The platform filter's spelling is one fact with one owner — the new `platform-filters` capability, where the read and write rules and S4's clause live — but four shipped specs cite the plural spelling in their own requirement text or scenarios. Those deltas only re-point the shipped wording at the new rule; none introduces behaviour of its own, and splitting them into four changes would leave the shipped specs contradicting the tool between merges. One capability, four citations.

## Non-goals

- A finding for the non-canonical but legal plural single-`ios` spelling (an S5-like warning), or a `lint --fix` that re-spells it: `lint --fix` never rewrites what it does not repair, and `docs/design.md` § Out of scope for v1 keeps repairs to the M rules.
- Deciding what Xcode does when a build file carries both keys: not measured; reading keeps the plural-first precedence the model already has, and writing never produces the pair.
- Filters on anything but `PBXBuildFile`: S4 keeps checking both keys on whatever object carries them, as it did the plural key; nothing else reads or writes them elsewhere (no committed corpus file carries a platform filter on any object, so no other carrier is measured).
- Adding platform names to the known list, or reading Xcode's platform lists from the SDK.
- The two other kinds of diff in the same Xcode save (`Tests/Fixtures/xcode27/xcode27-save.diff`): Xcode's multi-line formatting of a `PBXFileSystemSynchronizedRootGroup` that a hand-written fixture spelled on one line, and Xcode's silent deletion of fixture damage `lint --fix` reports as not fixable. Both are handled in the release procedure, not here.

## Impact

- `Sources/PBXOps/Inference/PlatformFilters.swift` gains the read rule (`read(from:)`) and the write rule (`spelling(of:)`); `Sources/PBXOps/Plan/Plan.swift` (`createBuildFile`), `Sources/PBXOps/Move/MovePlanner.swift` (the retained-build-file rewrite), `Sources/PBXOps/Rules/StructuralRules.swift` (S4), `Sources/PBXOps/Rules/Finding.swift` (S4's title), `Sources/PBXOps/Inference/Conventions.swift`, `Sources/PBXOps/Query/{MembershipReport,TargetMembers}.swift` use them. `Step.createBuildFile(id:fileRef:platformFilters:)` keeps its shape; the spelling is chosen when the step is applied.
- `PBXModel` is unchanged: `BuildFile.platformFilters` and `.platformFilter` already expose both keys.
- Fixtures: `Tests/Fixtures/xcode27/` (new, with a `README.md`); `Tests/Fixtures/{add,move,remove,repair}/app.pbxproj` rewritten from `platformFilters = (ios, );` to `platformFilter = ios;`. Tests that pinned the plural spelling or the plural-only accessor are updated only where the new spelling is the reason.
- `docs/design.md`: § Rules S4, § Conventions (`platformFilters` row and a note on the file spelling), the Motivation table gains the Xcode 27 row, the status line.
- No new dependency. Depends on `add-command`, `move-command`, `integrity-rules-lint`, `query-command` (all shipped).
