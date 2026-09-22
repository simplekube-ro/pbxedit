# Tasks

## 1. Path arguments

- [x] 1.1 Write failing tests for `PathArgument.resolve`: cwd-relative from a subdirectory, absolute, `./` and `..` segments, the source root itself and a path outside the source root as errors
- [x] 1.2 Implement `PathArgument` in `PBXOps` per design D1 with no disk access; verify 1.1 passes

## 2. Membership report

- [x] 2.1 Write failing tests building `MembershipReport` from the shipped fixtures for: ordinary member (`model/app.pbxproj`, `App/Views/Foo.swift`), shared source with `platformFilters` ordered by target (`App/Shared.swift`), build file in no phase (`rules/m1-no-phase.pbxproj`), reference with no group (`rules/m3-orphan.pbxproj`), unknown path, synchronized-folder path (`App/Generated/User.swift`); and that the encoded JSON keeps `null` keys present
- [x] 2.2 Implement `MembershipReport` and its builder per design D2; verify 2.1 passes

## 3. Target listing

- [x] 3.1 Write failing tests for the Target listing scenario (`AppTests`: ordering by phase then path), an SDK framework entry rendered as `$(SDKROOT)/…`, and a target with no such name yielding nothing
- [x] 3.2 Implement `TargetMembers` per design D2; verify 3.1 passes

## 4. Command

- [x] 4.1 Write failing CLI tests: human output for one member and the lint hint, `--json` for mixed results with exit `1`, exit `0` for a synchronized path, exit `2` for an unknown target listing target names, `--target` with paths and no arguments at all as usage errors, an unparseable project as exit `2`, run from a subdirectory with `--project`, a path outside the source root as exit `2`
- [x] 4.2 Implement the `query` subcommand and both renderers, including the "run `pbxedit lint`" hint per design D4; verify 4.1 passes
- [x] 4.3 Add a CLI test asserting the project file's bytes and modification time are unchanged after each invocation form; verify it passes

## 5. Documentation

- [x] 5.1 Record one human and one JSON example taken from real command output in this change's design.md (Evidence) — there is no `README.md` yet; the section moves there when the file is created — and update the `query` row and the status line of `docs/design.md`; verify the examples match by running them against the model fixture
