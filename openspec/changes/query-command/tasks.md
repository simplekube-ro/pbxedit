# Tasks

## 1. Path arguments

- [ ] 1.1 Write failing tests for `PathArgument.resolve`: cwd-relative from a subdirectory, absolute, `./` and `..` segments, and a path outside the source root as a usage error
- [ ] 1.2 Implement `PathArgument` in `PBXOps` per design D1 with no disk access; verify 1.1 passes

## 2. Membership report

- [ ] 2.1 Write failing tests building `MembershipReport` from the model fixtures for: ordinary member with `platformFilters`, shared source (ordered by target), build file in no phase, reference with no group, unknown path, synchronized-folder path
- [ ] 2.2 Implement `MembershipReport` and its builder per design D2; verify 2.1 passes and the encoded JSON keeps `null` keys present

## 3. Target listing

- [ ] 3.1 Write failing tests for the Target listing scenario (ordering by phase then path) and the Unknown target scenario
- [ ] 3.2 Implement the target members query; verify 3.1 passes

## 4. Command

- [ ] 4.1 Write failing CLI tests: human output for one member, `--json` for mixed results with exit `1`, exit `0` for a synchronized path, exit `2` for an unknown target listing target names, run from a subdirectory with `--project`
- [ ] 4.2 Implement the `query` subcommand and both renderers, including the "run `pbxedit lint`" hint per design D4; verify 4.1 passes
- [ ] 4.3 Add a CLI test asserting the project file's bytes and modification time are unchanged after each invocation form; verify it passes

## 5. Documentation

- [ ] 5.1 Add a `query` section to `README.md` with one human and one JSON example taken from real command output; verify the examples match by running them against the model fixture
