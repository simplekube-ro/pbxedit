# Design

## Context

`add-command` introduced `Decision(value, source)` and a `Conventions` value that planners query; its sources are flags, inference, file type and structure. `integrity-rules-lint` introduced baselines and findings that carry a path. This change adds one source and one filter. See proposal.md for motivation and `docs/design.md` § Conventions.

## Goals / Non-Goals

**Goals**

- Planners do not change. Configuration enters through `Conventions` only.
- A configuration error is impossible to miss and impossible to half-apply.

**Non-Goals**

- A schema that anticipates future commands. Keys are added when a command needs them.

## Decisions

### D1. Configuration is a layer inside `Conventions`

```
Conventions.targets(for path) =
    flags.targets ?? config.firstRule(matching: path, setting: \.targets) ?? infer(...)
```

The same shape serves `platformFilters`. Because lookup short-circuits, a configured attribute never triggers inference for that attribute, so the ambiguity error cannot arise — which is the behaviour the Precedence requirement asks for, obtained structurally rather than by a special case.

### D2. First match per attribute

*Alternative considered:* last match wins, as in `.gitignore`. Rejected: rules here assign values rather than toggling inclusion, and "the first rule that says anything about targets" is easier to predict and to report ("rule 2"). Per-attribute rather than per-rule matching lets a platform rule (`App/tvOS/**`) and a target rule (`App/**`) coexist without repeating each other.

### D3. Own glob matcher

A small matcher over path segments: `*`, `?`, `**`. `fnmatch(3)` does not implement `**`, and adding a dependency for forty lines is against policy. Character classes and brace expansion are not supported; using them is a validation error so nobody relies on them by accident.

### D4. Decode with Yams into strict `Decodable` types

Yams' `YAMLDecoder` gives typed decoding but silently ignores unknown keys. Each config type therefore decodes through a keyed container and then compares `container.allKeys` with its `CodingKeys`, throwing `unknownKey(name, allowed)`. Line numbers come from composing the document to a `Yams.Node` first and keeping each mapping's `mark`.

Project-dependent validation (target names) runs after the project loads, before any planner.

### D5. Exemption is a filter on findings

`RuleSet.evaluate` gains an `exemptions` parameter applied after evaluation, the same place scope filtering happens, returning suppressed findings separately so `lint` can count them. Because the pre-write check calls the same function, `add` honours exemptions with no additional code — except for D6.

### D6. An M3-exempt add skips the group steps

The add planner's second "ensure" question (is the reference a child of its directory's group) is skipped when the path is M3-exempt, and the structural derivation falls to the `SOURCE_ROOT` branch because there is no group chain. `Decision.source` for the reference's `sourceTree` records `.config`.

### D7. Configuration root defines relative paths

`project`, `lint.baseline` and rule globs are relative to the directory containing `.pbxedit.yml`. Validation rejects a configuration whose directory is not the project's source root or an ancestor of it, since globs are matched against source-root-relative paths after re-basing.

## Risks / Trade-offs

- [A broad rule hides a real inference disagreement] → The output attributes the decision to the rule on every run, and `add --dry-run` shows it before anything is written.
- [Exemptions become a way to silence real damage] → Only four rules are exemptible; suppressed findings are counted on every `lint` run, never hidden.
- [Yams is a sizeable dependency for one file] → Accepted in `docs/design.md`; it is linked only into `PBXOps`' config module and the executable.
- [Target-name validation makes the config brittle across branches where a target is being added] → The error lists valid targets and names the rule; fixing it is one line. Silent acceptance would send files to no target.
