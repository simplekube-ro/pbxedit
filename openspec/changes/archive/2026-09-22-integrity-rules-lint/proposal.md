# Proposal

## Why

A project file can be syntactically valid, build green, and still be wrong: a test file whose build file is in no Sources phase never runs; a file with no group is invisible in Xcode. On the originating project 38% of file references are in that second state and nothing reported it. This change defines what "consistent" means, once, as a rule set — and ships the first command, `pbxedit lint`, so projects can adopt the check before any editing command exists.

## What Changes

- Add the `PBXOps` library target with the rule set from `docs/design.md`: structural S1–S5, membership M1–M6, disk D1–D2. Each finding carries a rule ID, severity, object ID, resolved path when there is one, and a message.
- Rules can be evaluated over the whole project or scoped to a set of touched objects — the form later commands use as their pre-write check.
- Add the `pbxedit` executable (swift-argument-parser) with its first command, `lint`: human and `--json` output, `--disk`, `--write-baseline` and `--baseline`, project discovery, and exit codes.
- Refine rule S5 in `docs/design.md` to match what the parser makes possible (see design.md D3).

## Capabilities

### New Capabilities
- `integrity-rules`: the rule set defining a consistent project file, and the `lint` command that reports violations of it.

### Modified Capabilities

None.

## Non-goals

- Repairing findings. `lint --fix` is the `lint-fix` change.
- Config-file exemptions and a configured baseline path. Those arrive with `conventions-config`.
- Rules about build settings, schemes, signing or package references.
- Rules that need source-level analysis, such as "a file used by an extension must also be a member of it" (out of scope for v1 per `docs/design.md`).

## Impact

- New: `Sources/PBXOps/Rules/`, `Sources/pbxedit/`, `Tests/PBXOpsTests/`, `Tests/CLITests/`, `Tests/Fixtures/rules/`.
- `Sources/PBXSyntax`: one public read-only property, `StringNode.isCanonicallyQuoted`, so S5 can ask the layer that owns the quoting rule (design D3).
- New dependency: `swift-argument-parser` (one of the two permitted by project policy).
- `docs/design.md`: S5 wording, and `--write-baseline` added to the `lint` row of the Commands table.
- Depends on `typed-project-model`.
