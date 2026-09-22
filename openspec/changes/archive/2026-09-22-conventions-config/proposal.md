# Proposal

## Why

Sibling inference covers a project's conventions wherever there are siblings that agree. It cannot cover the first file in a new target directory, a directory whose existing members are split, or a deliberate exception such as generated files that should stay out of the navigator. Without somewhere to state these, the knowledge goes back into agent prompts and wrapper scripts — where the predecessor's mistakes came from.

## What Changes

- Add an optional `.pbxedit.yml`, discovered by walking up from the current directory, or named with `--config`.
- `project:` sets the default project so `--project` is unnecessary.
- `rules:` — ordered path globs supplying `targets` and `platformFilters`. They sit between flags and inference: flags beat config, config beats inference. Output attributes such decisions to the rule that made them.
- `lint:` — a default `baseline` path, and `exempt` globs per path-addressable rule (M3, M6, D1, D2). An M3 exemption also stops `add` from creating a group child for matching paths.
- Strict validation: unknown keys, unknown target names, unknown rule IDs and non-exemptible rules are errors with a line number.

## Capabilities

### New Capabilities
- `conventions-config`: a checked-in configuration file that states project conventions inference cannot discover, and tailors `lint` to the project.

### Modified Capabilities

None. `add` and `integrity-rules` state their own behaviour; this capability states how configuration feeds into them.

## Non-goals

- Rules that depend on source-level references ("files used by the extension must join it") — out of scope for v1 per `docs/design.md`.
- Per-rule severity changes, or exempting structural rules S1–S5.
- User-level or global configuration. One file, in the repository.
- Settings for file templates or disk operations, which the tool does not perform.

## Impact

- New: `Sources/PBXOps/Config/`, tests, fixtures. `Conventions` gains a config source; the planners are unchanged for targets and platform filters. The one planner change is design D6: an M3-exempt path gets no group child.
- New dependency: `Yams` — the second and last of the two permitted by project policy. YAML over JSON because a rules file needs comments.
- `ProjectOptions` (every command gains `--config`) and `lint` (`--no-baseline`, the `exempt` count) read defaults from the config; `OperationRunner` honours exemptions in its checks.
- Output shapes grow additively: `add --json` `decisions[].source` gains `rule` and `glob`; `lint --json` `summary` gains `exempt`.
- Depends on `add-command`.
