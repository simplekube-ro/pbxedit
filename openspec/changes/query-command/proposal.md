# Proposal

## Why

Today the only way to learn which target builds a file is to grep the project file and count lines (`grep -c 'Foo.swift in Sources'` must be 2, or 4 for a shared source), then map a build-phase ID back to a target by line number. Agents get this wrong, and a wrong answer looks like a passing test run. The model already knows the answer; this change exposes it.

## What Changes

- Add `pbxedit query <path>…`: for each path, report whether it is a member, its file reference ID, group path, and each membership — target, phase, build file ID, `platformFilters` — or that it is covered by a synchronized folder.
- Add `pbxedit query --target <name>`: list the files a target builds, by resolved path.
- Human and `--json` output. Strictly read-only.

## Capabilities

### New Capabilities
- `query`: read-only answers about a file's membership in the project and about a target's members.

### Modified Capabilities

None.

## Non-goals

- Querying build settings, schemes, dependencies or package products.
- A general query language or filtering beyond `--target`.
- Reporting rule violations; that is `lint`. `query` reports facts, including odd ones (no group, no phase), without judging them.

## Impact

- New: `Sources/pbxedit/Query.swift`, `Sources/PBXOps/Query/`, tests under `Tests/PBXOpsTests/` and `Tests/CLITests/`.
- Introduces the path-argument convention (design.md D1) that `add`, `remove` and `move` reuse.
- Depends on `typed-project-model`; uses the CLI skeleton from `integrity-rules-lint`.
